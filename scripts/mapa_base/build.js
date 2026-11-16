// scripts/mapa_base/build.js
// Genera el mapa base offline que la app trae dentro del APK, a partir de los
// datos abiertos de OpenStreetMap que publica Protomaps cada día:
//
//   assets/map/chile.pmtiles            Chile continental, zoom 0–10: carreteras,
//                                       rutas principales y ciudades.
//   assets/map/valparaiso.pmtiles       Región de Valparaíso, zoom 11–15: todas
//                                       las calles, edificios y lugares.
//   assets/map/style_light.json         Estilo claro de MapLibre.
//   assets/map/style_dark.json          Estilo oscuro.
//   assets/map/style_satellite.json     Foto aérea de Esri con las etiquetas.
//   assets/map/sprites/                 Íconos de los estilos.
//   assets/map/fonts/                   Tipografías de los nombres (glifos).
//   assets/map/calles_valparaiso.json   Índice de calles del buscador offline.
//   assets/map/ruteo_valparaiso.tar     Grafo de calles de Valhalla de la región,
//                                       para calcular rutas sin conexión.
//
// Uso (desde la raíz del repositorio):
//   npm ci --prefix scripts/mapa_base
//   node scripts/mapa_base/build.js [--build=AAAAMMDD]
//       [--solo=regiones,teselas,estilos,iconos,fuentes,calles,miniaturas,ruteo]
//
// Requiere:
//   - Node 18 o superior (usa fetch).
//   - El CLI `pmtiles` (https://github.com/protomaps/go-pmtiles/releases), en
//     el PATH o con su ruta en la variable de entorno PMTILES_BIN.
//   - Para el paso `ruteo`: Python con `pip install pyvalhalla==3.9.1 shapely`,
//     de preferencia en scripts/mapa_base/.venv (o indicar el Python en
//     VALHALLA_PYTHON; ver ruteo.py).
//
// Si se cambia la región, actualizar también `kChileBounds` y `kDetailBounds`
// en lib/config/map_config.dart: test/basemap_test.dart comprueba que
// coincidan con lo que quedó dentro de los archivos.

const { execFileSync } = require('child_process');
const crypto = require('crypto');
const fs = require('fs');
const path = require('path');
const { layers, namedFlavor } = require('@protomaps/basemaps');
const {
  convertFilter,
  expression,
  validateStyleMin,
} = require('@maplibre/maplibre-gl-style-spec');

const RAIZ = path.resolve(__dirname, '..', '..');
const ASSETS = path.join(RAIZ, 'assets', 'map');
const SPRITES = path.join(ASSETS, 'sprites');
const REGIONES = path.join(__dirname, 'regiones');
const CACHE = path.join(__dirname, '.cache');

const PMTILES = process.env.PMTILES_BIN || 'pmtiles';
const USER_AGENT = 'ColeTotal/1.0 (cl.coletotal.app)';

// Zoom máximo de cada archivo. Cada nivel más duplica, más o menos, el tamaño:
// medido con el build 20261006, Chile hasta z10 pesa 24 MB (z9: 12, z11: 47)
// y la región de z11 a z15 pesa 37 MB (hasta z14: 19).
const CHILE_MAX_ZOOM = 10;
const DETALLE_MIN_ZOOM = CHILE_MAX_ZOOM + 1;
const DETALLE_MAX_ZOOM = 15;

// Límites administrativos de geoBoundaries (versión fijada). ADM0 viene de
// Natural Earth (dominio público); ADM1 y ADM3, de la Biblioteca del Congreso
// Nacional (CC BY 3.0 IGO). Sólo se usan para recortar, no se dibujan.
const GEOBOUNDARIES =
  'https://github.com/wmgeolab/geoBoundaries/raw/9469f09/releaseData/gbOpen/CHL';

const BUILDS = 'https://build-metadata.protomaps.dev/builds.json';
/** Extracto de OpenStreetMap de Chile para el grafo de Valhalla (unos 350 MB). */
const GEOFABRIK_CHILE = 'https://download.geofabrik.de/south-america/chile-latest.osm.pbf';
/**
 * El Python con pyvalhalla: VALHALLA_PYTHON, o el entorno virtual
 * `scripts/mapa_base/.venv` si existe (ver README), o el del sistema.
 */
const VALHALLA_PYTHON = process.env.VALHALLA_PYTHON || [
  path.join(__dirname, '.venv', 'Scripts', 'python.exe'),
  path.join(__dirname, '.venv', 'bin', 'python'),
].find((ruta) => fs.existsSync(ruta)) || 'python';
const SPRITES_URL = 'https://protomaps.github.io/basemaps-assets/sprites/v4';
const OVERPASS = [
  'https://overpass-api.de/api/interpreter',
  'https://overpass.kumi.systems/api/interpreter',
];

// ---------------------------------------------------------------------------
// Utilidades
// ---------------------------------------------------------------------------

function argumento(nombre) {
  const prefijo = `--${nombre}=`;
  const arg = process.argv.find((a) => a.startsWith(prefijo));
  return arg ? arg.slice(prefijo.length) : null;
}

const solo = argumento('solo')?.split(',');
const toca = (paso) => !solo || solo.includes(paso);

function mb(archivo) {
  return `${(fs.statSync(archivo).size / 1024 / 1024).toFixed(1)} MB`;
}

async function descargar(url, opciones = {}) {
  const res = await fetch(url, {
    ...opciones,
    headers: { 'User-Agent': USER_AGENT, ...(opciones.headers || {}) },
  });
  if (!res.ok) throw new Error(`HTTP ${res.status} en ${url}`);
  return res;
}

/** Descarga [url] una sola vez y la guarda en .cache/[nombre]. */
async function enCache(nombre, url) {
  const destino = path.join(CACHE, nombre);
  if (!fs.existsSync(destino)) {
    fs.mkdirSync(CACHE, { recursive: true });
    const res = await descargar(url);
    fs.writeFileSync(destino, Buffer.from(await res.arrayBuffer()));
  }
  return destino;
}

function leerJson(archivo) {
  return JSON.parse(fs.readFileSync(archivo, 'utf8'));
}

function escribirJson(archivo, valor) {
  fs.mkdirSync(path.dirname(archivo), { recursive: true });
  fs.writeFileSync(archivo, JSON.stringify(valor));
}

/** Minúsculas, sin tildes ni signos: para agrupar "Av. Los Carrera" y "AV LOS CARRERA". */
function normalizar(texto) {
  return texto
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .toLowerCase()
    .replace(/[^a-z0-9ñ ]/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

// ---------------------------------------------------------------------------
// 1. Build de Protomaps
// ---------------------------------------------------------------------------

/**
 * El build pedido o el más reciente. Protomaps guarda los de la última
 * semana, así que una fecha vieja deja de existir a los pocos días.
 */
async function resolverBuild() {
  const builds = await (await descargar(BUILDS)).json();
  const pedido = argumento('build');
  const build = pedido
    ? builds.find((b) => b.key === `${pedido}.pmtiles`)
    : builds[builds.length - 1];
  if (!build) {
    throw new Error(
      `No existe el build ${pedido}. Disponibles: ` +
        builds.slice(-7).map((b) => b.key).join(', '),
    );
  }
  return {
    url: `https://build.protomaps.com/${build.key}`,
    fecha: build.key.replace('.pmtiles', ''),
    version: build.version,
  };
}

// ---------------------------------------------------------------------------
// 2. Regiones
// ---------------------------------------------------------------------------

const poligonos = (g) => (g.type === 'Polygon' ? [g.coordinates] : g.coordinates);

/**
 * Sólo los polígonos continentales (y sus islas cercanas, como Chiloé): Rapa
 * Nui y Juan Fernández quedan fuera, a cientos de kilómetros de la costa, y
 * estirarían la caja del mapa sobre el Pacífico.
 */
const continental = (g) => poligonos(g).filter((p) => p[0].some(([lon]) => lon > -76));

/**
 * Los nombres de ADM1 vienen con la codificación rota ("RegiÃ³n"): fueron
 * UTF-8 leído como Latin-1. Se repara para poder buscar la región por nombre.
 */
const repararNombre = (s) => (/Ã/.test(s) ? Buffer.from(s, 'latin1').toString('utf8') : s);

function caja(polys) {
  const b = [180, 90, -180, -90];
  for (const p of polys) {
    for (const [x, y] of p[0]) {
      b[0] = Math.min(b[0], x);
      b[1] = Math.min(b[1], y);
      b[2] = Math.max(b[2], x);
      b[3] = Math.max(b[3], y);
    }
  }
  return b.map((v) => +v.toFixed(4));
}

async function regiones() {
  const adm0 = leerJson(await enCache('CHL_ADM0.geojson',
    `${GEOBOUNDARIES}/ADM0/geoBoundaries-CHL-ADM0_simplified.geojson`));
  const adm1 = leerJson(await enCache('CHL_ADM1.geojson',
    `${GEOBOUNDARIES}/ADM1/geoBoundaries-CHL-ADM1_simplified.geojson`));

  // Más un rectángulo de mar al oeste: sin él, al alejar el mapa el Pacífico
  // quedaba en blanco donde las teselas ya no tocan la costa. El mar abierto
  // casi no pesa (cuesta 1 MB); Argentina sí, y por eso no se usa una caja.
  const oceano = [[[-82, -56.5], [-72, -56.5], [-72, -17], [-82, -17], [-82, -56.5]]];
  const chile = [...continental(adm0.features[0].geometry), oceano];
  const region = adm1.features.find(
    (f) => repararNombre(f.properties.shapeName) === 'Región de Valparaíso',
  );
  if (!region) throw new Error('No se encontró la Región de Valparaíso en ADM1');
  const valparaiso = continental(region.geometry);

  escribirJson(path.join(REGIONES, 'chile.geojson'),
    { type: 'MultiPolygon', coordinates: chile });
  escribirJson(path.join(REGIONES, 'valparaiso.geojson'),
    { type: 'MultiPolygon', coordinates: valparaiso });

  console.log(`✅ Regiones: Chile ${JSON.stringify(caja(chile))}`);
  console.log(`   Valparaíso ${JSON.stringify(caja(valparaiso))}`);
}

// ---------------------------------------------------------------------------
// 3. Teselas
// ---------------------------------------------------------------------------

function extraer(build, salida, region, zooms) {
  console.log(`🔄 Extrayendo ${path.basename(salida)} (${zooms.join(' ')})...`);
  // Se escribe a un temporal y se renombra al final: si la descarga se corta,
  // el archivo anterior sigue entero.
  const temporal = `${salida}.tmp`;
  execFileSync(PMTILES, [
    'extract', build.url, temporal, `--region=${region}`, ...zooms,
    '--download-threads=4',
  ], { stdio: ['ignore', 'inherit', 'inherit'] });
  fs.renameSync(temporal, salida);
  console.log(`✅ ${path.basename(salida)}: ${mb(salida)}`);
}

function teselas(build) {
  fs.mkdirSync(ASSETS, { recursive: true });
  extraer(build, path.join(ASSETS, 'chile.pmtiles'),
    path.join(REGIONES, 'chile.geojson'),
    [`--maxzoom=${CHILE_MAX_ZOOM}`]);
  extraer(build, path.join(ASSETS, 'valparaiso.pmtiles'),
    path.join(REGIONES, 'valparaiso.geojson'),
    [`--minzoom=${DETALLE_MIN_ZOOM}`, `--maxzoom=${DETALLE_MAX_ZOOM}`]);
}

// ---------------------------------------------------------------------------
// 4. Estilos (MapLibre)
// ---------------------------------------------------------------------------

/**
 * Prefijo de las rutas locales en los estilos. La app lo reemplaza por la
 * carpeta donde copió el mapa en el teléfono (`file:///…/mapa_base/`, ver
 * BasemapService): la ruta real depende de cada teléfono.
 */
const BASE = 'mapa-base://';

/**
 * Foto aérea de Esri World Imagery (sin clave). Tiene que coincidir con
 * `kSatelliteTileUrlTemplate` de lib/config/map_config.dart, que la usa para la
 * miniatura del selector; test/basemap_test.dart lo comprueba.
 */
const ESRI =
  'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}';

/**
 * Las tipografías de los nombres, con un nombre sin espacios: es también el
 * nombre de su carpeta, y así la ruta no depende de cómo MapLibre codifique
 * el espacio en una URL `file://`. La Devanagari sólo aparece en nombres en
 * hindi; en Chile basta con la normal.
 */
const FUENTES = {
  'Noto Sans Regular': 'noto-sans-regular',
  'Noto Sans Medium': 'noto-sans-medium',
  'Noto Sans Italic': 'noto-sans-italic',
  'Noto Sans Devanagari Regular v1': 'noto-sans-regular',
};

/**
 * Bloques de 256 caracteres que viajan en el APK: el latín con tildes y ñ, el
 * latín extendido y la puntuación (– — ’ “ ” …). Un nombre en otro alfabeto
 * pide un bloque que no está y MapLibre sólo omite esos caracteres.
 */
const RANGOS_GLIFOS = ['0-255', '256-511', '512-767', '8192-8447', '8448-8703'];
const FUENTES_URL = 'https://protomaps.github.io/basemaps-assets/fonts';
const FUENTES_DIR = path.join(ASSETS, 'fonts');

/** Douglas-Peucker sobre un anillo [lon, lat]; [tolerancia] en grados. */
function simplificar(anillo, tolerancia) {
  if (anillo.length <= 4) return anillo;
  const distancia = ([x, y], [x1, y1], [x2, y2]) => {
    const dx = x2 - x1;
    const dy = y2 - y1;
    const largo = dx * dx + dy * dy;
    const t = largo === 0 ? 0 : Math.max(0, Math.min(1, ((x - x1) * dx + (y - y1) * dy) / largo));
    return Math.hypot(x - (x1 + t * dx), y - (y1 + t * dy));
  };
  const conservar = new Array(anillo.length).fill(false);
  conservar[0] = conservar[anillo.length - 1] = true;
  const pila = [[0, anillo.length - 1]];
  while (pila.length) {
    const [a, b] = pila.pop();
    let mayor = 0;
    let indice = -1;
    for (let i = a + 1; i < b; i++) {
      const d = distancia(anillo[i], anillo[a], anillo[b]);
      if (d > mayor) {
        mayor = d;
        indice = i;
      }
    }
    if (mayor > tolerancia) {
      conservar[indice] = true;
      pila.push([a, indice], [indice, b]);
    }
  }
  return anillo.filter((_, i) => conservar[i]);
}

/**
 * La región simplificada (~500 m, con coordenadas de 4 decimales), para el
 * filtro `within` de las etiquetas de la vista general. Va copiada en cada
 * capa que la usa, así que su tamaño se multiplica: con todos los vértices
 * los estilos pesaban 410 KB y MapLibre los lee al abrir cada mapa y al
 * cambiar de tema. Simplificar la agranda o achica a lo más unos cientos de
 * metros, y ahí las teselas de detalle (de un kilómetro o más) igual cubren.
 */
function regionParaFiltro() {
  const region = leerJson(path.join(REGIONES, 'valparaiso.geojson'));
  return {
    type: 'MultiPolygon',
    coordinates: region.coordinates
      .filter((poligono) => poligono[0].length >= 20) // sin los islotes
      .map((poligono) => [
        simplificar(poligono[0], 0.005).map(([lon, lat]) => [+lon.toFixed(4), +lat.toFixed(4)]),
      ]),
  };
}

/**
 * Capas que no se dibujan: los íconos y nombres de comercios y servicios
 * (`pois`) y la numeración de las casas (`address_label`). Los pidió sacar el
 * usuario: tapaban los nombres de las calles, que en el centro casi no se
 * veían, y la app ya marca lo suyo (paraderos, colectivos, destino).
 */
const CAPAS_FUERA = new Set(['pois', 'address_label']);

/**
 * Etiquetas para la vista satelital: las del sabor oscuro son grises y sobre
 * la foto aérea casi no se leían. Texto blanco con halo negro, como las de
 * cualquier vista híbrida.
 */
const SOBRE_FOTO = Object.fromEntries(
  Object.entries(namedFlavor('dark')).map(([clave, color]) =>
    clave.includes('label')
      ? [clave, clave.endsWith('_halo') ? '#000000' : '#ffffff']
      : [clave, color],
  ),
);

/**
 * Un estilo de MapLibre con las dos fuentes de teselas.
 *
 * La vista general (`general`, Chile hasta z10) va completa y debajo; MapLibre
 * agranda sus teselas de z10 al acercarse. Encima va el detalle (`detalle`, la
 * región de z11 a z15) sin fondo: donde tiene teselas, su tierra y su agua
 * tapan a la general, también a sus etiquetas, porque MapLibre dibuja las
 * capas en orden. En la satelital el detalle no tiene tierra que las tape: ahí
 * las etiquetas de la general se esconden dentro de la región desde z11, o
 * saldrían repetidas.
 */
function estilo(sabor, sprite, build, { satelite = false } = {}) {
  const region = regionParaFiltro();
  const opciones = { lang: 'es', ...(satelite ? { labelsOnly: true } : {}) };
  const general = layers('general', sabor, opciones)
    .filter((capa) => !CAPAS_FUERA.has(capa.id))
    .map((capa) => {
      const copia = { ...capa, id: `general_${capa.id}` };
      // Sólo en la vista satelital: en la de calles, las etiquetas de la
      // general quedan debajo de la tierra y el agua (opacas) del detalle, que
      // se dibujan después, así que dentro de la región ya no se ven. Y sólo
      // en las capas que siguen visibles desde z11, donde empieza el detalle.
      if (satelite && capa.type === 'symbol' && (capa.maxzoom ?? 24) > DETALLE_MIN_ZOOM) {
        const fueraDelDetalle = [
          'any',
          ['<', ['zoom'], DETALLE_MIN_ZOOM],
          ['!', ['within', region]],
        ];
        // Algunos filtros de Protomaps usan la sintaxis antigua, que no se
        // puede mezclar con expresiones dentro de un mismo `all`.
        const propio = capa.filter && (expression.isExpressionFilter(capa.filter)
          ? capa.filter
          : convertFilter(capa.filter));
        copia.filter = propio ? ['all', propio, fueraDelDetalle] : fueraDelDetalle;
      }
      return copia;
    });
  const detalle = layers('detalle', sabor, opciones)
    .filter((capa) => capa.type !== 'background' && !CAPAS_FUERA.has(capa.id))
    .map((capa) => ({ ...capa, id: `detalle_${capa.id}` }));

  const osm = '© OpenStreetMap';
  const sources = {
    general: { type: 'vector', url: `pmtiles://${BASE}chile.pmtiles`, attribution: osm },
    detalle: { type: 'vector', url: `pmtiles://${BASE}valparaiso.pmtiles`, attribution: osm },
  };
  const fondo = [];
  if (satelite) {
    sources.esri = {
      type: 'raster',
      tiles: [ESRI],
      tileSize: 256,
      maxzoom: 19,
      attribution: 'Esri, Maxar, Earthstar Geographics',
    };
    fondo.push(
      // Lo que se ve sin conexión, debajo de las etiquetas blancas.
      { id: 'fondo', type: 'background', paint: { 'background-color': '#1b1b1b' } },
      { id: 'satelite', type: 'raster', source: 'esri' },
    );
  }

  const resultado = {
    version: 8,
    name: `ColeTotal ${satelite ? 'satélite' : sprite}`,
    metadata: { 'coletotal:build': `${build.fecha}-${build.version}` },
    glyphs: `${BASE}fonts/{fontstack}/{range}.pbf`,
    sprite: `${BASE}sprites/${sprite}`,
    sources,
    layers: [...fondo, ...general, ...detalle],
  };
  // Las tipografías con su nombre de carpeta (ver FUENTES), también dentro de
  // las expresiones `format` que eligen la letra según el alfabeto.
  let texto = JSON.stringify(resultado);
  for (const [nombre, id] of Object.entries(FUENTES)) {
    texto = texto.split(JSON.stringify(nombre)).join(JSON.stringify(id));
  }
  return JSON.parse(texto);
}

function estilos(build) {
  const salidas = [
    ['style_light.json', estilo(namedFlavor('light'), 'light', build)],
    ['style_dark.json', estilo(namedFlavor('dark'), 'dark', build)],
    ['style_satellite.json', estilo(SOBRE_FOTO, 'dark', build, { satelite: true })],
  ];
  for (const [nombre, contenido] of salidas) {
    const errores = validateStyleMin(contenido);
    if (errores.length) {
      throw new Error(`${nombre} no es un estilo válido:\n${errores.map((e) => e.message).join('\n')}`);
    }
    escribirJson(path.join(ASSETS, nombre), contenido);
    console.log(`✅ ${nombre}: ${contenido.layers.length} capas`);
  }
  // El estilo de sólo etiquetas que usaba vector_map_tiles quedó dentro del
  // satelital.
  fs.rmSync(path.join(ASSETS, 'style_labels.json'), { force: true });
}

// ---------------------------------------------------------------------------
// 5. Íconos y tipografías
// ---------------------------------------------------------------------------

async function bajar(url, destino) {
  const res = await descargar(url);
  fs.mkdirSync(path.dirname(destino), { recursive: true });
  fs.writeFileSync(destino, Buffer.from(await res.arrayBuffer()));
}

async function iconos() {
  // MapLibre pide `@2x` en pantallas de alta densidad y la normal en las demás.
  for (const sabor of ['light', 'dark']) {
    for (const nombre of [`${sabor}.json`, `${sabor}.png`, `${sabor}@2x.json`, `${sabor}@2x.png`]) {
      await bajar(`${SPRITES_URL}/${nombre}`, path.join(SPRITES, nombre));
    }
  }
  console.log('✅ Íconos light y dark (normal y @2x)');
}

async function fuentes() {
  fs.rmSync(FUENTES_DIR, { recursive: true, force: true });
  const unicas = new Map(Object.entries(FUENTES).filter(([nombre]) => !nombre.includes('Devanagari')));
  for (const [nombre, id] of unicas) {
    for (const rango of RANGOS_GLIFOS) {
      await bajar(
        `${FUENTES_URL}/${encodeURIComponent(nombre)}/${rango}.pbf`,
        path.join(FUENTES_DIR, id, `${rango}.pbf`),
      );
    }
  }
  console.log(`✅ Tipografías: ${[...unicas.values()].join(', ')} (${RANGOS_GLIFOS.length} bloques c/u)`);
}

// ---------------------------------------------------------------------------
// 6. Índice de calles
// ---------------------------------------------------------------------------

/** Tipos de vía que la gente busca por nombre (sin senderos, huellas ni escaleras). */
const VIAS =
  '^(motorway|trunk|primary|secondary|tertiary|unclassified|residential|' +
  'living_street|pedestrian|service|road)(_link)?$';

async function consultarOverpass() {
  const destino = path.join(CACHE, 'calles_overpass.json');
  if (fs.existsSync(destino)) return leerJson(destino);

  const consulta = `
    [out:json][timeout:600];
    area["boundary"="administrative"]["admin_level"="4"]["name"="Región de Valparaíso"]->.r;
    way(area.r)["highway"~"${VIAS}"]["name"];
    out tags center qt;
  `;
  let ultimoError;
  for (const servidor of OVERPASS) {
    try {
      console.log(`🔄 Consultando calles en ${new URL(servidor).host}...`);
      const res = await descargar(servidor, {
        method: 'POST',
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        body: `data=${encodeURIComponent(consulta)}`,
      });
      const datos = await res.json();
      fs.mkdirSync(CACHE, { recursive: true });
      fs.writeFileSync(destino, JSON.stringify(datos));
      return datos;
    } catch (e) {
      ultimoError = e;
      console.warn(`⚠️ ${e.message}`);
    }
  }
  throw ultimoError;
}

/** Rayo hacia el este: ¿está [lon, lat] dentro del anillo? */
function dentroDeAnillo([x, y], anillo) {
  let dentro = false;
  for (let i = 0, j = anillo.length - 1; i < anillo.length; j = i++) {
    const [xi, yi] = anillo[i];
    const [xj, yj] = anillo[j];
    if (yi > y !== yj > y && x < ((xj - xi) * (y - yi)) / (yj - yi) + xi) {
      dentro = !dentro;
    }
  }
  return dentro;
}

const dentroDePoligono = (punto, poligono) =>
  dentroDeAnillo(punto, poligono[0]) &&
  !poligono.slice(1).some((hueco) => dentroDeAnillo(punto, hueco));

/** Metros entre dos puntos cercanos (equirectangular: sobra para < 50 km). */
function metros([lon1, lat1], [lon2, lat2]) {
  const r = 6371000;
  const x = ((lon2 - lon1) * Math.PI) / 180 * Math.cos(((lat1 + lat2) / 2) * Math.PI / 180);
  const y = ((lat2 - lat1) * Math.PI) / 180;
  return Math.sqrt(x * x + y * y) * r;
}

/**
 * Agrupa los tramos de una misma calle. Una avenida larga viene en decenas de
 * tramos y debe quedar como un solo resultado; pero "Pasaje 1" existe en
 * muchas villas de la misma comuna y no son la misma calle. Se juntan los
 * tramos que quedan a menos de [umbral] metros de alguno del grupo.
 */
function agrupar(puntos, umbral = 400) {
  const grupos = [];
  for (const punto of puntos) {
    const cercanos = grupos.filter((g) => g.some((q) => metros(q, punto) < umbral));
    if (cercanos.length === 0) {
      grupos.push([punto]);
    } else {
      const [primero, ...resto] = cercanos;
      primero.push(punto);
      for (const g of resto) {
        primero.push(...g);
        grupos.splice(grupos.indexOf(g), 1);
      }
    }
  }
  return grupos;
}

/** El tramo más central del grupo: un punto que sí está sobre la calle. */
function medoide(puntos) {
  let mejor = puntos[0];
  let menor = Infinity;
  for (const p of puntos) {
    let suma = 0;
    for (const q of puntos) suma += metros(p, q);
    if (suma < menor) {
      menor = suma;
      mejor = p;
    }
  }
  return mejor;
}

async function calles() {
  const adm3 = leerJson(await enCache('CHL_ADM3.geojson',
    `${GEOBOUNDARIES}/ADM3/geoBoundaries-CHL-ADM3_simplified.geojson`));
  const region = leerJson(path.join(REGIONES, 'valparaiso.geojson'));
  const [minLon, minLat, maxLon, maxLat] = caja(region.coordinates);

  // Las comunas que tocan la caja de la región; las de más lejos no pueden
  // contener ninguna calle de la consulta.
  const comunas = adm3.features
    .map((f) => ({ nombre: f.properties.shapeName, polys: poligonos(f.geometry) }))
    .filter(({ polys }) => {
      const [a, b, c, d] = caja(polys);
      return a <= maxLon && c >= minLon && b <= maxLat && d >= minLat;
    });
  const comunaDe = (punto) =>
    comunas.find(({ polys }) => polys.some((p) => dentroDePoligono(punto, p)))?.nombre;

  const datos = await consultarOverpass();
  const porCalle = new Map();
  let sinComuna = 0;
  for (const via of datos.elements) {
    const nombre = via.tags?.name?.trim();
    if (!nombre || !via.center) continue;
    const punto = [via.center.lon, via.center.lat];
    // Juan Fernández y Rapa Nui también son de la región, pero no del mapa.
    if (punto[0] < -76) continue;
    const comuna = comunaDe(punto);
    if (!comuna) {
      sinComuna++;
      continue;
    }
    const clave = `${normalizar(nombre)}|${comuna}`;
    const calle = porCalle.get(clave) || { nombres: new Map(), comuna, puntos: [] };
    calle.nombres.set(nombre, (calle.nombres.get(nombre) || 0) + 1);
    calle.puntos.push(punto);
    porCalle.set(clave, calle);
  }

  // Accesos y estacionamientos con la dirección en el nombre ("Avenida Los
  // Carrera 351"): con la avenida misma en el índice sólo repiten resultados
  // en un desplegable que muestra seis.
  const nombresPorComuna = new Set([...porCalle.keys()]);
  const esDireccion = (clave) => {
    const [nombre, comuna] = clave.split('|');
    const base = nombre.match(/^(.*\S)\s+\d{2,}[a-z]?$/);
    return base !== null && nombresPorComuna.has(`${base[1]}|${comuna}`);
  };

  const filas = [];
  let direcciones = 0;
  for (const [clave, { nombres, comuna, puntos }] of porCalle) {
    if (esDireccion(clave)) {
      direcciones++;
      continue;
    }
    // La grafía más usada entre los tramos ("Avenida Los Carrera" y no
    // "Av. los Carrera" si sólo un tramo lo escribe así).
    const nombre = [...nombres.entries()].sort((a, b) => b[1] - a[1])[0][0];
    for (const grupo of agrupar(puntos)) {
      const [lon, lat] = medoide(grupo);
      filas.push([nombre, comuna, +lat.toFixed(5), +lon.toFixed(5)]);
    }
  }
  filas.sort((a, b) => a[1].localeCompare(b[1], 'es') || a[0].localeCompare(b[0], 'es'));

  const salida = path.join(ASSETS, 'calles_valparaiso.json');
  escribirJson(salida, filas);
  console.log(
    `✅ calles_valparaiso.json: ${filas.length} calles de ${datos.elements.length} tramos ` +
      `(${sinComuna} sin comuna, ${direcciones} accesos con número), ${mb(salida)}`,
  );
}

// ---------------------------------------------------------------------------
// 7. Miniaturas del selector de estilo
// ---------------------------------------------------------------------------

/**
 * Quilpué en el selector de estilo (Preferencias y el botón de capas). Son
 * imágenes porque abrir un mapa nativo para un recuadro de 2 cm costaría
 * memoria; se dibujan con MapLibre Native, el mismo motor de la app, a partir
 * de los estilos y las teselas recién generados. El centro es `kQuilpueCenter`
 * de lib/config/map_config.dart, y z13 de MapLibre es el z14 que usaba la
 * miniatura en flutter_map.
 */
async function miniaturas() {
  // Sólo este paso necesita el motor nativo: se carga aquí y no arriba.
  const mbgl = require('@maplibre/maplibre-gl-native');
  const sharp = require('sharp');
  const { PMTiles } = require('pmtiles');
  const zlib = require('zlib');

  class Archivo {
    constructor(ruta) {
      this.ruta = ruta;
      this.fd = fs.openSync(ruta, 'r');
    }
    getKey() {
      return this.ruta;
    }
    async getBytes(offset, length) {
      const buf = Buffer.alloc(length);
      fs.readSync(this.fd, buf, 0, length, offset);
      return { data: buf.buffer.slice(buf.byteOffset, buf.byteOffset + length) };
    }
  }
  const teselas = {
    general: new PMTiles(new Archivo(path.join(ASSETS, 'chile.pmtiles'))),
    detalle: new PMTiles(new Archivo(path.join(ASSETS, 'valparaiso.pmtiles'))),
  };

  async function pedir(url) {
    const tesela = url.match(/^pmt:\/\/(\w+)\/(\d+)\/(\d+)\/(\d+)$/);
    if (tesela) {
      const t = await teselas[tesela[1]].getZxy(+tesela[2], +tesela[3], +tesela[4]);
      if (!t) return null;
      const datos = Buffer.from(t.data);
      return datos[0] === 0x1f && datos[1] === 0x8b ? zlib.gunzipSync(datos) : datos;
    }
    const local = url.match(/^asset:\/\/(.*)$/);
    if (local) {
      const ruta = path.join(ASSETS, decodeURIComponent(local[1]));
      if (!fs.existsSync(ruta)) throw new Error(`El estilo pide ${local[1]}, que no existe`);
      return fs.readFileSync(ruta);
    }
    throw new Error(`La miniatura no debería usar la red: ${url}`);
  }

  for (const sabor of ['light', 'dark']) {
    // Las teselas como fuente `pmt://` que resuelve `pedir`, y las rutas
    // `mapa-base://` como `asset://`: el motor de Node no lee PMTiles locales.
    const estilo = JSON.parse(
      fs.readFileSync(path.join(ASSETS, `style_${sabor}.json`), 'utf8').split(BASE).join('asset://'),
    );
    for (const id of ['general', 'detalle']) {
      const h = await teselas[id].getHeader();
      estilo.sources[id] = {
        type: 'vector',
        tiles: [`pmt://${id}/{z}/{x}/{y}`],
        minzoom: h.minZoom,
        maxzoom: h.maxZoom,
        bounds: [h.minLon, h.minLat, h.maxLon, h.maxLat],
      };
    }
    const lado = 256;
    const densidad = 2;
    const pixeles = await new Promise((resolve, reject) => {
      const mapa = new mbgl.Map({
        ratio: densidad,
        request: (req, cb) => pedir(req.url).then((data) => (data ? cb(null, { data }) : cb()), cb),
      });
      mapa.load(estilo);
      mapa.render({ zoom: 13, center: [-71.4425, -33.0472], width: lado, height: lado }, (e, buf) => {
        mapa.release();
        if (e) reject(e);
        else resolve(buf);
      });
    });
    const salida = path.join(ASSETS, `preview_${sabor}.png`);
    await sharp(pixeles, { raw: { width: lado * densidad, height: lado * densidad, channels: 4 } })
      .png({ palette: true, quality: 90 })
      .toFile(salida);
    console.log(`✅ preview_${sabor}.png: ${(fs.statSync(salida).size / 1024).toFixed(0)} KB`);
  }
}

// ---------------------------------------------------------------------------
// 8. Ruteo (Valhalla)
// ---------------------------------------------------------------------------

/**
 * El grafo de calles de Valhalla para la región, con el que la app calcula
 * las rutas a pie y los trazados de las líneas sin conexión. Lo arma
 * `ruteo.py` con pyvalhalla a partir del extracto de Chile de Geofabrik.
 * Es otro corte de OpenStreetMap que el de las teselas (Geofabrik y no
 * Protomaps), así que conviene regenerarlos juntos.
 */
async function ruteo() {
  console.log('🔄 Bajando el extracto de Chile de Geofabrik (si no está en .cache)...');
  const pbf = await enCache('chile-latest.osm.pbf', GEOFABRIK_CHILE);
  execFileSync(VALHALLA_PYTHON, [
    path.join(__dirname, 'ruteo.py'),
    pbf,
    path.join(REGIONES, 'valparaiso.geojson'),
    path.join(ASSETS, 'ruteo_valparaiso.tar'),
  ], { stdio: ['ignore', 'inherit', 'inherit'] });
}

// ---------------------------------------------------------------------------
// 9. Manifiesto
// ---------------------------------------------------------------------------

/** Los archivos chicos que la app copia junto a las teselas: íconos y tipografías. */
function recursos() {
  const lista = [];
  for (const carpeta of [SPRITES, FUENTES_DIR]) {
    if (!fs.existsSync(carpeta)) continue;
    for (const entrada of fs.readdirSync(carpeta, { recursive: true })) {
      const ruta = path.join(carpeta, entrada);
      if (fs.statSync(ruta).isFile()) lista.push(path.relative(ASSETS, ruta).split(path.sep).join('/'));
    }
  }
  return lista.sort();
}

/**
 * `assets/map/basemap.json`: de qué build salieron las teselas, cuánto pesa
 * cada archivo y qué recursos chicos (íconos, tipografías) hay que copiar. La
 * app lo lee al arrancar (son unos bytes) para saber si la copia que hizo en
 * el teléfono sigue al día sin tener que abrir los 60 MB del APK cada vez.
 */
function manifiesto(build, conTeselas) {
  const archivo = path.join(ASSETS, 'basemap.json');
  const previo = fs.existsSync(archivo) ? leerJson(archivo) : {};
  const archivos = {};
  for (const nombre of ['chile.pmtiles', 'valparaiso.pmtiles', 'ruteo_valparaiso.tar']) {
    const ruta = path.join(ASSETS, nombre);
    if (fs.existsSync(ruta)) archivos[nombre] = fs.statSync(ruta).size;
  }
  // Una huella del contenido: si cambia un ícono o una tipografía, la app
  // vuelve a copiarlos aunque las teselas sigan siendo las mismas.
  const lista = recursos();
  const huella = crypto.createHash('sha1');
  for (const nombre of lista) huella.update(nombre).update(fs.readFileSync(path.join(ASSETS, nombre)));
  const contenido = {
    build: conTeselas ? build.fecha : previo.build,
    basemap: conTeselas ? build.version : previo.basemap,
    archivos,
    recursos: { huella: huella.digest('hex').slice(0, 12), archivos: lista },
  };
  fs.writeFileSync(archivo, `${JSON.stringify(contenido, null, 2)}
`);
  return contenido;
}

// ---------------------------------------------------------------------------

/** El build de las teselas que ya están en assets/map, según el manifiesto. */
function buildActual() {
  const archivo = path.join(ASSETS, 'basemap.json');
  if (!fs.existsSync(archivo)) return null;
  const { build, basemap } = leerJson(archivo);
  return build ? { fecha: build, version: basemap } : null;
}

async function run() {
  const build = await resolverBuild();
  console.log(`🗺️  Build de Protomaps ${build.fecha} (basemap ${build.version})\n`);

  if (toca('regiones')) await regiones();
  if (toca('teselas')) teselas(build);
  // Los estilos anotan el build de las teselas en sus metadatos: si cambian
  // las teselas se regeneran también, y si sólo se piden los estilos se usa
  // el build de las teselas que ya están, no el más reciente.
  if (toca('teselas') || toca('estilos')) {
    estilos(toca('teselas') ? build : buildActual() ?? build);
  }
  if (toca('iconos')) await iconos();
  if (toca('fuentes')) await fuentes();
  if (toca('calles')) await calles();
  if (toca('teselas') || toca('estilos') || toca('miniaturas')) await miniaturas();
  if (toca('ruteo')) await ruteo();
  const { build: fecha } = manifiesto(build, toca('teselas'));

  console.log(`\n✅ Listo. Datos © OpenStreetMap (ODbL), build ${fecha}.`);
}

run().catch((e) => {
  console.error(`❌ ${e.stack || e}`);
  process.exit(1);
});
