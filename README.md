# ColeTotal 🚖

Aplicación móvil para la gestión de líneas y flotas de **taxis colectivos** en
la Región de Valparaíso, con foco inicial en Transportes Serrano (Quilpué).

El pasajero ve dónde vienen los colectivos y qué línea le conviene tomar; el
conductor transmite su posición durante su turno; el administrador de garita
dibuja las líneas y supervisa la flota en vivo.

Los colectivos **no tienen paraderos fijos**: paran donde se les hace la seña,
a lo largo de todo su recorrido. La app trabaja con ese modelo operativo: cada
línea es un trazado continuo de ida y otro de vuelta, y al pasajero se le indica
en qué punto exacto de la línea subirse (punto de seña) y dónde bajarse.

Proyecto de título — Escuela de Ingeniería Informática, Pontificia Universidad
Católica de Valparaíso.

---

## Perfiles de usuario

La app tiene tres perfiles, y el menú lateral muestra en todo momento cuál está
activo y qué permite hacer.

| Perfil | Cómo se entra | Para qué sirve |
|---|---|---|
| **Invitado** | Sin registro | Consultar el mapa y las líneas, buscar cómo llegar y ver los colectivos en circulación |
| **Colectivero** | Patente + contraseña | Transmitir su posición a los pasajeros y a la garita durante el turno |
| **Administrador de garita** | Correo + contraseña | Dibujar las líneas, gestionar choferes y monitorear la flota |

Los dos perfiles con cuenta se registran con un **código de garita** que entrega
el administrador. El código determina el rol: no se elige en el formulario, y
las reglas de Firestore lo verifican en el servidor al crear la cuenta.

## Funcionalidades

### Pasajero (no requiere cuenta)

- Mapa interactivo con seguimiento de la ubicación, recentrado, zoom y rotación.
- **Colectivos en vivo** sobre el mapa, identificados con el color y la etiqueta
  de su línea/variante (p. ej. `"10 T"`). Una unidad que lleva más de 45 s sin
  señal se dibuja atenuada, y a los 3 min desaparece.
- **Modo Radar (1 km) y Modo Foco (2 km)**: en vista general el mapa muestra los
  colectivos en un radio de 1 km alrededor del pasajero y dibuja únicamente las
  líneas de esos vehículos cercanos para evitar saturación visual. Al tocar un
  colectivo o elegir una línea en la pestaña **Líneas**, el mapa pasa a Modo
  Foco sobre esa línea y amplía el radio de visualización de sus colectivos a
  2 km.
- Al tocar un colectivo: su patente, su línea y variante, hacia qué terminal se
  dirige, hace cuánto se lo vio y su trazado dibujado sobre el mapa.
- **Buscador de direcciones y optimizador híbrido en cascada (2 niveles)**: se
  escribe a dónde se quiere ir y la app propone qué línea tomar y en qué
  sentido, utilizando un modelo subrogado de optimización espaciotemporal
  (`HybridRouteOptimizer`) en dos niveles:
  - **Nivel 1 (Subrogado analítico con tablas acumuladas $O(1)$)**: filtra y
    evalúa en microsegundos los pares de subida y bajada sobre cada polilínea,
    penalizando tramos peatonales con factor de tortuosidad $\tau = 1.35$.
  - **Nivel 2 (Verificación exacta con Valhalla)**: al seleccionar una
    sugerencia, el candidato ganador del Nivel 1 se refina contra el grafo
    peatonal real de Valhalla en el dispositivo para obtener la ruta a pie y
    métricas exactas.
  Incluye un catálogo local de lugares de Quilpué y normalización insensible a
  tildes.
- **Puntos de seña** en vez de paraderos. Al seleccionar una línea se dibujan
  sus dos sentidos lado a lado, cada uno por su carril con flechas de sentido de
  marcha, un punto de seña por sentido ("Hacia Alto el Yugo", "Hacia el
  centro"), la ruta a pie hasta el punto de subida y los terminales marcados
  con el nombre oficial de la cartola. En un viaje armado se resalta sólo el
  tramo que se recorre arriba del colectivo.
- Cada colectivo en el mapa es un auto negro con su letrero amarillo, visto
  desde arriba: apunta hacia donde va, se desliza suavemente de una posición a
  la siguiente y lleva un anillo del color de su línea y su etiqueta.
- Pestaña **Líneas**: las líneas activas de la garita ordenadas de la más
  cercana a la más lejana, con cuántos colectivos circulan en cada una.
- **Ruta a pie** hasta el punto donde hacerle la seña al colectivo, con
  distancia y tiempo caminando, y marcas de dónde subirse y bajarse.

### Colectivero

- Su pestaña **Turno** es un mapa de navegación: el chofer es una flecha y
  abajo está el botón de **Iniciar turno**. En turno, la cámara se inclina,
  gira con el sentido de marcha y deja la flecha en la parte inferior; se aleja
  dinámicamente a mayor velocidad. Al mover el mapa deja de seguirlo y aparece
  **Volver a centrar**; el botón **2D/3D** alterna entre la vista plana con el
  norte arriba y la de navegación. La pantalla permanece encendida durante el
  turno. Al primer turno la app solicita permiso de notificaciones y exclusión
  de ahorro de batería para transmitir con la pantalla bloqueada.
- En el mapa se destaca su línea con las flechas de su sentido, las demás
  líneas atenuadas y los demás colectivos en servicio.
- Las pestañas del chofer son Turno, Líneas y Preferencias.
- Elección de la **línea** que se está cubriendo (se recuerda entre turnos y
  se puede cambiar en pleno turno).
- Transmisión GPS en segundo plano mientras el turno está activo, con
  servicio en primer plano y notificación persistente.
- Confirmación en vivo ("última posición enviada hace 3 s") y aviso cuando no
  hay señal; la posición se reenvía sola al recuperarla.
- Auditoría del turno (pérdidas de GPS y de señal, cambios de recorrido) que se
  sube a Firestore al terminar, también si la app se cerró a mitad del turno.
- Aviso de consentimiento de geolocalización (Ley 19.628).

### Administrador de garita

- Portada con métricas: unidades en servicio, líneas activas y choferes.
- **Recorridos y Cartola Oficial MTT (D.S. 212)**: cada línea cuenta con su
  nombre, metadatos de cartola (`linea`, `codigoVariante`, `nombreVariante`,
  `callesIda`, `callesVuelta`), color y su recorrido de **ida** y de **vuelta**.
  Se pueden dibujar sobre el mapa punto por punto o importar directamente
  pegando la secuencia de calles de la Cartola MTT (`CartolaResolver`), que
  cruza las intersecciones contra el grafo vial local
  (`intersecciones_valparaiso.json`) y ajusta el trazado con Valhalla sin giros
  en U (`break_through`). Encender o apagar una línea es un interruptor en la
  lista.
- **Choferes**: padrón de la garita con indicador de quién está en servicio e
  interruptor para habilitar o deshabilitar el acceso. Deshabilitar a un
  chofer cierra su sesión (y su turno) en segundos.
- **Flota**: mapa y lista en vivo de las unidades, con su estado, hace cuánto
  se las vio y, al tocar una, su recorrido. Se puede filtrar por garita.
- Sin señal, los cambios se guardan igual y se sincronizan al volver la red.

### Transversal

- Interfaz en español, adaptable a teléfono y tablet (barra inferior o rail
  lateral según el ancho).
- Tema claro / oscuro / automático, ajuste de tamaño de fuente y modo compacto.
- Las líneas se muestran sin conexión gracias a la caché offline de
  Firestore: su trazado viene calculado, no se pide a ningún servidor.
- El mapa viene dentro del APK: Chile entero en vista general y la Región de
  Valparaíso con todas sus calles, más un índice de sus calles para el
  buscador. Funcionan sin señal y sin claves de API; sólo la vista satelital
  necesita conexión (ver [Mapa base offline](#mapa-base-offline)).
- Ninguna acción espera indefinidamente al servidor: sin señal, terminar el
  turno, cerrar sesión o guardar un cambio terminan en segundos y lo
  pendiente se sincroniza después.

## Stack tecnológico

| Herramienta | Rol |
|---|---|
| Flutter / Dart | Desarrollo multiplataforma |
| `maplibre_gl` (MapLibre Native) | Mapa interactivo dibujado con la GPU; lee el mapa base offline (PMTiles de OpenStreetMap vía Protomaps) dentro del APK |
| Photon (OpenStreetMap) | Direcciones con numeración, cuando hay conexión |
| Esri World Imagery | Vista satelital (requiere conexión) |
| `geolocator` | GPS del dispositivo y seguimiento en segundo plano |
| Firebase Authentication | Sesiones de choferes y administradores |
| Cloud Firestore | Usuarios, garitas y líneas (recorridos) |
| Firebase Realtime Database | Telemetría GPS de alta frecuencia |
| Valhalla (dentro del teléfono), con OSRM de respaldo / OpenRouteService | Rutas a pie y trazado de los recorridos, también sin conexión |
| `shared_preferences` | Preferencias e historial local |

**Requisitos:** Flutter ≥ 3.44, Dart ≥ 3.12. Probado en Android; iOS necesita
además `ios/Runner/GoogleService-Info.plist`, que no está en el repositorio.

## Puesta en marcha

```bash
flutter pub get
flutter gen-l10n
flutter run
```

La app arranca como Invitado y muestra el mapa sin necesidad de configurar
nada. Para que funcionen el registro, las líneas y el panel de garita hay que
preparar el proyecto de Firebase:

1. **Authentication → Sign-in method**: habilitar *Correo electrónico/contraseña*.
2. **Firestore Database**: crearla en modo producción (la región es permanente).
3. **Desplegar las reglas**, que están versionadas en el repositorio:
   ```bash
   firebase deploy --only firestore:rules,database
   ```
4. **Sembrar los datos mínimos** desde la consola:
   - `garitas/{id}` → `{ nombre, comuna }`
   - `codigos_acceso/{CÓDIGO}` → `{ garitaId, rol: "colectivero", activo: true }`
   - otro `codigos_acceso` con `rol: "administrador"`

   El id del documento **es** el código que se entrega a la persona, así que
   conviene que sea largo, no adivinable y en mayúsculas (p. ej.
   `SERRANO-CHO-7K4M9`). Los códigos **no** se guardan en el repositorio: el
   script de datos de prueba los recibe por variables de entorno
   (`CHOFER_CODE`, `ADMIN_CODE`, `TEST_DRIVER_PASSWORD`).
5. Entrar como administrador y dibujar las líneas (menú → Recorridos).

Sin el paso 5, la búsqueda de direcciones funciona, pero no hay líneas que
proponer. Los pasajeros sólo ven las líneas de la garita `kGaritaPublica`
(`lib/config/garita_config.dart`, la de Transportes Serrano).

### Claves de API

El mapa, el buscador y la vista satelital no usan claves. La única opcional es
la de OpenRouteService, que mejora el ruteo:

```bash
flutter run --dart-define=ORS_API_KEY=tu_clave
```

Sin `ORS_API_KEY` la ruta a pie la calcula Valhalla, igual que el trazado de
las líneas. En Android corre **dentro del teléfono**, sin conexión, con el
grafo de calles de la región que viene en el APK. Fuera de la región, en iOS y
en la web se le pregunta a OSRM (servidores públicos de FOSSGIS a pie y de
demostración en auto). Ninguno pide clave.

OSRM es sólo el respaldo: en auto pasa por huellas y caminos de servicio
(estacionamientos, accesos privados). Valhalla se limita a calles públicas. La
ruta a pie, en cambio, va a propósito por pasajes y escaleras.

El trazado de cada sentido de una línea es la ruta en auto que pasa por los
puntos que marcó la garita, en orden. Si un tramo sale por otra calle, se
agrega un punto sobre la calle correcta y el trazado se rehace solo.

## Mapa base offline

Los mapas no descargan teselas: las traen en `assets/map/`, generadas a partir
de OpenStreetMap con `scripts/mapa_base/build.js`.

| Archivo | Contenido | Peso |
|---|---|---|
| `chile.pmtiles` | Chile continental y el mar al oeste, zoom 0–10 (rutas, calles principales, ciudades) | 24 MB |
| `valparaiso.pmtiles` | Región de Valparaíso, zoom 11–15 (todas las calles, edificios, lugares) | 35 MB |
| `style_*.json`, `sprites/`, `fonts/` | Estilos de MapLibre (claro, oscuro y satelital), con sus íconos y las tipografías de los nombres. Sin comercios ni numeración de casas: tapaban los nombres de las calles | 1,5 MB |
| `preview_*.png` | Miniaturas del selector de estilo | 80 KB |
| `calles_valparaiso.json` | Índice de unas 25 mil calles de la región, para buscar sin señal | 1,2 MB |
| `intersecciones_valparaiso.json` | Grafo de intersecciones viales de la región para resolver cartolas MTT (`CartolaResolver`) sin red | 2,8 MB |
| `ruteo_valparaiso.tar` | Grafo de calles de Valhalla de la región, para calcular rutas sin señal (del extracto de Chile de Geofabrik) | 65 MB |
| `basemap.json` | Build de origen, tamaño de cada archivo y lista de íconos y tipografías | — |

MapLibre dibuja el mapa con la GPU del teléfono. Cada estilo usa las dos
fuentes: la de Chile abajo y la de la región encima, que la tapa donde tiene
datos; dentro de la región, desde el zoom 11, las etiquetas las pone sólo la
de detalle. En el primer arranque tras instalar, la app copia los `.pmtiles`,
los íconos, las tipografías y, ya con el mapa a la vista, los datos de ruteo a
su carpeta de datos (MapLibre y Valhalla los leen de
archivos); en los siguientes los reutiliza mientras no cambie el mapa.

Para actualizar el mapa (con una vez por semestre basta; cada actualización
suma unos 125 MB a la historia de git):

1. Instalar el CLI `pmtiles` desde
   [go-pmtiles/releases](https://github.com/protomaps/go-pmtiles/releases) y
   dejarlo en el PATH (o su ruta en la variable `PMTILES_BIN`). Para los datos
   de ruteo, además, Python con pyvalhalla (la misma versión de Valhalla que
   trae la app):
   ```bash
   python -m venv scripts/mapa_base/.venv
   scripts/mapa_base/.venv/Scripts/pip install pyvalhalla==3.9.1 shapely   # en Linux/macOS: .venv/bin/pip
   ```
2. Generar:
   ```bash
   npm ci --prefix scripts/mapa_base
   node scripts/mapa_base/build.js
   ```
   Toma el build diario más reciente de Protomaps (o uno fijo con
   `--build=AAAAMMDD`; se guardan sólo los de la última semana). Con
   `--solo=estilos` (o `teselas`, `iconos`, `fuentes`, `calles`, `regiones`,
   `miniaturas`, `ruteo`) rehace sólo una parte. El ruteo baja el extracto de
   Chile de Geofabrik (unos 350 MB, queda en `scripts/mapa_base/.cache`) y
   arma el grafo en unos minutos; conviene regenerarlo junto con las teselas,
   para que el mapa y las rutas muestren las mismas calles. Los estilos se validan contra la
   especificación de MapLibre, y las miniaturas se dibujan con MapLibre
   Native, el mismo motor de la app. Si npm tiene `ignore-scripts` activo, el
   motor queda sin su binario; se baja así:
   ```bash
   cd scripts/mapa_base/node_modules/@maplibre/maplibre-gl-native
   npx node-pre-gyp install --fallback-to-build=false
   ```
3. `flutter test`: `test/basemap_test.dart` comprueba que los estilos apunten
   a archivos que existen y que los límites de `lib/config/map_config.dart`
   sigan coincidiendo con los archivos. Cada archivo tiene que quedar bajo los
   100 MB que acepta GitHub.

**Créditos y licencias.** Datos del mapa © colaboradores de OpenStreetMap
(ODbL), en teselas y estilos de [Protomaps](https://protomaps.com) (BSD/ODbL);
la app lo indica en una esquina de cada mapa. Tipografías Noto Sans (OFL).
Motor del mapa: [MapLibre](https://maplibre.org) (BSD). Límites para recortar:
[geoBoundaries](https://www.geoboundaries.org) (Chile: Natural Earth, dominio
público; regiones y comunas: Biblioteca del Congreso Nacional, CC BY 3.0 IGO).
Vista satelital: Esri World Imagery.

## Estructura del proyecto

```
lib/
├── config/       Centro, límites y zoom del mapa; versión instalada
├── l10n/         Textos en español (ARB + generados)
├── models/       AppUser, Recorrido (ida y vuelta), ColectivoActivo, Garita
├── navigation/   Destinos y qué ve cada rol
├── screens/      admin/ · auth/ · driver/ · mapa, líneas, preferencias
├── services/     Estado de la app en singletons ChangeNotifier (sesión,
│                 líneas, telemetría, turno) más utilidades sin estado
│                 (geocodificación, planificador de viajes, ruteo)
├── theme/        Tema Material 3, colores semánticos, espaciado
├── utils/        Formato de distancias, patentes, errores
└── widgets/      Menú lateral, sugerencias de viaje, buscador, mapa
```

Verificación: `flutter analyze` y `flutter test` (283 pruebas, sin red ni
Firebase). Entre ellas hay pruebas de contrato que leen `firestore.rules` y
`database.rules.json` y fallan si el cliente escribe un campo que las reglas
rechazarían, además de pruebas de estrés para el resolvedor de cartolas MTT y el
optimizador híbrido de rutas. Para levantar la app con la simulación local de
flota activada en modo demostración, usar `--dart-define=DEMO_MODE=true`.

## Publicar una versión

1. Subir `version:` en `pubspec.yaml` (p. ej. `0.4.4+5`). Es la única fuente:
   la app la lee del propio APK para mostrarla en Preferencias y registrarla en
   la auditoría de turnos.
2. Firmar siempre con la **misma** llave, o Android rechaza el APK nuevo
   encima del instalado. La llave se crea una sola vez y se guarda fuera del
   repositorio:
   ```bash
   keytool -genkey -v -keystore coletotal-release.jks -keyalg RSA -keysize 2048 -validity 10000 -alias coletotal
   ```
   y `android/key.properties` (ignorado por git):
   ```properties
   storePassword=...
   keyPassword=...
   keyAlias=coletotal
   storeFile=C:/ruta/a/coletotal-release.jks
   ```
   Sin ese archivo el APK se firma con la llave de debug del computador.
3. `flutter build apk --release` y subir el APK (se recomienda GitHub
   Releases). Pesa unos 192 MB: 60 son el mapa base, 27 los datos de ruteo
   y unos 50 los motores de MapLibre y Valhalla para tres arquitecturas
   (Android guarda sus bibliotecas sin comprimir). Con `--split-per-abi`, el
   APK de `arm64-v8a` (el de casi todos los teléfonos actuales) queda en unos
   125 MB, porque deja fuera las bibliotecas de las otras arquitecturas.

## Limitaciones conocidas

- **Sin recuperación de contraseña para choferes.** La patente se traduce a un
  correo sintético que no recibe mensajes; si un chofer pierde su contraseña,
  el administrador deshabilita la cuenta y le entrega un código nuevo.
- **Las líneas que pasan dos veces por el mismo lugar** (un circuito que vuelve
  por la misma calle en el mismo sentido) se recomiendan por su primera pasada:
  el punto más cercano de un trayecto es el primero que encuentra.
- **El cálculo de ETA todavía no está implementado.**
- Las reglas de Realtime Database no pueden consultar Firestore: no saben si un
  chofer está deshabilitado, y el `garitaId` de la telemetría se filtra del
  lado del cliente. La app cierra la sesión de un chofer deshabilitado en
  cuanto la garita lo marca, pero las reglas por sí solas no lo impedirían.
- La notificación del turno necesita, en Android 13 o superior, el permiso de
  notificaciones; sin él el servicio sigue transmitiendo, pero la
  notificación no se ve.
- **La vista satelital necesita conexión.** Ningún proveedor gratuito permite
  llevar fotos aéreas dentro de una app; sin señal se ven sólo las etiquetas.
- **El mapa base es una foto de OpenStreetMap a la fecha de su build** (ver
  `assets/map/basemap.json`): una calle nueva aparece recién al regenerarlo y
  publicar otro APK. Fuera de la Región de Valparaíso el detalle es menor.
- El buscador offline encuentra calles, no numeraciones; "Freire 1234" sigue
  necesitando conexión (Photon).
- **Las rutas sin conexión son sólo de Android y de la región.** iOS (sin
  puente a Valhalla todavía) y los puntos fuera de la Región de Valparaíso
  usan OSRM, que necesita red.
- **El mapa no funciona en el escritorio.** MapLibre para Flutter sólo existe
  para Android, iOS y la web; en Windows la app muestra el fondo del mapa sin
  calles. Los marcadores son imágenes dentro del mapa nativo: con TalkBack
  activo, la app pone encima de cada uno un botón invisible con su
  descripción, que se reubica cada vez que el mapa se detiene.

## Descargas

Obtener la última versión del APK en la sección
[releases](https://github.com/Tomas-pucv/Coletotal/releases).
