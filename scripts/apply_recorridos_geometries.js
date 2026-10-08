// scripts/apply_recorridos_geometries.js
// Calcula y guarda la geometría vial de cada recorrido en Firestore, siguiendo
// las calles (y sus sentidos de tránsito) entre los paraderos, en orden.
//
// Calcula como la app (lib/services/routing.dart): Valhalla en auto, con los
// paraderos enganchados sólo a calles públicas y con los mismos datos de
// ruteo que lleva el teléfono (scripts/mapa_base/ruta.py), y OSRM si Valhalla
// no encuentra ruta.
//
// Uso: node scripts/apply_recorridos_geometries.js [--dry-run]
//   --dry-run   calcula y muestra, sin escribir en Firestore.
// Requiere haber hecho `firebase login` con una cuenta con acceso al proyecto,
// y pyvalhalla en scripts/mapa_base/.venv (ver README) o en VALHALLA_PYTHON.

const { execFileSync } = require('child_process');
const fs = require('fs');
const path = require('path');
const { getAccessToken, listCollection, patchDocument } = require('./lib/firebase_rest');

const USER_AGENT = 'ColeTotal/1.0 (cl.coletotal.app)';
const OSRM = 'https://router.project-osrm.org/route/v1/driving/';
const RUTA_PY = path.join(__dirname, 'mapa_base', 'ruta.py');
const VALHALLA_PYTHON = process.env.VALHALLA_PYTHON || [
  path.join(__dirname, 'mapa_base', '.venv', 'Scripts', 'python.exe'),
  path.join(__dirname, 'mapa_base', '.venv', 'bin', 'python'),
].find((ruta) => fs.existsSync(ruta)) || 'python';
const MAX_UBICACIONES = 20;
const soloMostrar = process.argv.includes('--dry-run');

// --- Polilíneas (precisión 6), como lib/utils/polyline.dart ---------------

function decodificar(texto) {
  const puntos = [];
  let i = 0;
  let lat = 0;
  let lng = 0;
  const siguiente = () => {
    let r = 0;
    let peso = 1;
    let b;
    do {
      b = texto.charCodeAt(i++) - 63;
      r += (b % 32) * peso;
      peso *= 32;
    } while (b >= 32);
    return r % 2 ? -((r + 1) / 2) : r / 2;
  };
  while (i < texto.length) {
    lat += siguiente();
    lng += siguiente();
    puntos.push([lat / 1e6, lng / 1e6]);
  }
  return puntos;
}

function codificar(puntos) {
  let salida = '';
  let pLat = 0;
  let pLng = 0;
  const valor = (v) => {
    let n = v < 0 ? -v * 2 - 1 : v * 2;
    while (n >= 32) {
      salida += String.fromCharCode(32 + (n % 32) + 63);
      n = Math.floor(n / 32);
    }
    salida += String.fromCharCode(n + 63);
  };
  for (const [lat, lng] of puntos) {
    const a = Math.round(lat * 1e6);
    const b = Math.round(lng * 1e6);
    valor(a - pLat);
    valor(b - pLng);
    pLat = a;
    pLng = b;
  }
  return salida;
}

/** Tramos de como mucho [n] puntos que se solapan en un paradero. */
function trocear(puntos, n) {
  const tramos = [];
  for (let inicio = 0; inicio < puntos.length - 1; ) {
    const fin = Math.min(inicio + n, puntos.length);
    tramos.push(puntos.slice(inicio, fin));
    inicio = fin - 1;
  }
  return tramos;
}

/** Une tramos sin repetir el punto de unión. */
function unir(tramos) {
  const salida = [];
  for (const tramo of tramos) {
    const repetido = salida.length && tramo.length &&
      salida[salida.length - 1][0] === tramo[0][0] && salida[salida.length - 1][1] === tramo[0][1];
    salida.push(...(repetido ? tramo.slice(1) : tramo));
  }
  return salida;
}

// --- Enrutadores ------------------------------------------------------------

async function valhalla(paradas) {
  const piezas = [];
  let metros = 0;
  for (const tramo of trocear(paradas, MAX_UBICACIONES)) {
    const consulta = {
      locations: tramo.map(([lat, lon]) => ({
        lat,
        lon,
        type: 'break',
        search_filter: { min_road_class: 'residential' },
      })),
      costing: 'auto',
      directions_type: 'none',
      units: 'kilometers',
    };
    let respuesta;
    try {
      respuesta = execFileSync(VALHALLA_PYTHON, [RUTA_PY], {
        input: JSON.stringify(consulta),
        encoding: 'utf8',
        stdio: ['pipe', 'pipe', 'pipe'],
      });
    } catch (err) {
      console.warn(`   Valhalla: ${(err.stderr || err.message).toString().trim()}`);
      return null;
    }
    const { trip } = JSON.parse(respuesta);
    if (!trip || !trip.legs || !trip.legs.length) return null;
    piezas.push(unir(trip.legs.map((l) => decodificar(l.shape))));
    metros += trip.summary.length * 1000;
  }
  return { puntos: unir(piezas), metros, proveedor: 'Valhalla' };
}

async function osrm(paradas) {
  const piezas = [];
  let metros = 0;
  for (const tramo of trocear(paradas, 25)) {
    const coords = tramo.map(([lat, lng]) => `${lng},${lat}`).join(';');
    const res = await fetch(`${OSRM}${coords}?overview=full&geometries=polyline6`, {
      headers: { 'User-Agent': USER_AGENT },
    });
    if (!res.ok) return null;
    const json = await res.json();
    if (json.code !== 'Ok' || !json.routes || !json.routes[0]) return null;
    piezas.push(decodificar(json.routes[0].geometry));
    metros += json.routes[0].distance;
  }
  return { puntos: unir(piezas), metros, proveedor: 'OSRM' };
}

async function run() {
  console.log('🔄 Conectando con Firestore...');
  const token = await getAccessToken();

  const paraderos = await listCollection(token, 'paraderos');
  const paraderosMap = new Map(paraderos.map((p) => [p.id, p]));
  console.log(`✅ ${paraderosMap.size} paraderos cargados.`);

  const recorridos = await listCollection(token, 'recorridos');
  console.log(`✅ ${recorridos.length} recorridos encontrados en Firestore.`);
  if (soloMostrar) console.log('   (--dry-run: no se escribe nada)');
  console.log('');

  let actualizados = 0;

  for (const r of recorridos) {
    const paradas = (r.paraderoIds || [])
      .map((id) => paraderosMap.get(id))
      .filter((stop) => stop && typeof stop.lat === 'number' && typeof stop.lng === 'number')
      .map((stop) => [stop.lat, stop.lng]);

    if (paradas.length < 2) {
      console.warn(`⚠️ Omitiendo ${r.id}: tiene menos de 2 paraderos válidos.`);
      continue;
    }

    try {
      const ruta = (await valhalla(paradas)) || (await osrm(paradas));
      if (!ruta || ruta.puntos.length < 2) {
        console.error(`❌ Ningún enrutador encontró ruta para ${r.id}`);
        continue;
      }
      const geometria = codificar(ruta.puntos);

      if (!soloMostrar) {
        await patchDocument(
          token,
          `recorridos/${r.id}`,
          { geometria, actualizadoEn: new Date() },
          ['geometria', 'actualizadoEn'],
        );
      }

      console.log(`📍 [${r.id}] ${r.nombre}`);
      console.log(
        `   ${ruta.proveedor}: ${(ruta.metros / 1000).toFixed(2)} km | ` +
          `${ruta.puntos.length} puntos | geometría de ${geometria.length} caracteres`,
      );
      actualizados++;
    } catch (err) {
      console.error(`❌ Error en recorrido ${r.id}: ${err.message}`);
    }
  }

  console.log(
    `\n🎉 Geometrías ${soloMostrar ? 'calculadas' : 'guardadas'}: ${actualizados}/${recorridos.length}`,
  );
}

run().catch((err) => {
  console.error('❌ Error:', err.message || err);
  process.exit(1);
});
