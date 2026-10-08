# ColeTotal 🚖

Aplicación móvil para la gestión de paraderos, recorridos y flotas de **taxis
colectivos** en la Región de Valparaíso, con foco inicial en Transportes
Serrano (Quilpué).

El pasajero ve dónde vienen los colectivos y a qué paradero le conviene ir; el
conductor transmite su posición durante su turno; el administrador de garita
gestiona los datos de la línea y supervisa la flota en vivo.

Proyecto de título — Escuela de Ingeniería Informática, Pontificia Universidad
Católica de Valparaíso.

---

## Perfiles de usuario

La app tiene tres perfiles, y el menú lateral muestra en todo momento cuál está
activo y qué permite hacer.

| Perfil | Cómo se entra | Para qué sirve |
|---|---|---|
| **Invitado** | Sin registro | Consultar el mapa, buscar paraderos y ver los colectivos en circulación |
| **Colectivero** | Patente + contraseña | Transmitir su posición a los pasajeros y a la garita durante el turno |
| **Administrador de garita** | Correo + contraseña | Gestionar paraderos, recorridos y choferes, y monitorear la flota |

Los dos perfiles con cuenta se registran con un **código de garita** que entrega
el administrador. El código determina el rol: no se elige en el formulario, y
las reglas de Firestore lo verifican en el servidor al crear la cuenta.

## Funcionalidades

### Pasajero (no requiere cuenta)

- Mapa interactivo con seguimiento de la ubicación, recentrado, zoom y rotación.
- **Colectivos en vivo** sobre el mapa, coloreados según la capacidad que
  reporta cada chofer (disponible / medio lleno / lleno). Una unidad que lleva
  más de 45 s sin señal se dibuja atenuada, y a los 3 min desaparece.
- Al tocar un colectivo: su patente, su capacidad, hace cuánto se lo vio y,
  si el chofer la informó, su línea dibujada sobre el mapa.
- **Buscador de direcciones**: se escribe a dónde se quiere ir y la app
  recomienda el paradero, ordenando por el promedio de los dos tramos a pie
  (lo que se camina hasta el paradero y lo que se camina desde la bajada).
  Incluye un catálogo local de 26 lugares de Quilpué y no distingue tildes
  ("lider" encuentra "Líder").
- Lista de **paraderos** ordenada por cercanía a la posición actual o por los
  últimos consultados.
- Al tocar un paradero: los colectivos que pasan por él; al tocar una línea, su
  recorrido dibujado sobre el mapa.
- **Ruta a pie** hasta el paradero desde la posición actual, con distancia y
  tiempo caminando.

### Colectivero

- Pantalla de turno con un interruptor grande **En servicio / Fuera de
  servicio**.
- Elección del **recorrido** que se está cubriendo (se recuerda entre turnos y
  se puede cambiar en pleno turno).
- Selector de capacidad de un toque, que alimenta la semaforización que ven
  pasajeros y garita.
- Transmisión GPS en segundo plano mientras el turno está activo, con
  servicio en primer plano y notificación persistente.
- Confirmación en vivo ("última posición enviada hace 3 s") y aviso cuando no
  hay señal; la posición se reenvía sola al recuperarla.
- Auditoría del turno (pérdidas de GPS y de señal, cambios de capacidad y de
  recorrido) que se sube a Firestore al terminar, también si la app se cerró
  a mitad del turno.
- Aviso de consentimiento de geolocalización (Ley 19.628).

### Administrador de garita

- Portada con métricas: unidades en servicio, paraderos y recorridos.
- **Paraderos**: crear, mover sobre el mapa, editar, dar de baja y reactivar.
- **Recorridos**: nombre, color y lista ordenada de paraderos; el trazado se
  calcula siguiendo las calles entre ellos y se recalcula al mover un paradero.
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
- Los paraderos se muestran sin conexión gracias a una semilla local y a la
  caché offline de Firestore.
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
| Cloud Firestore | Usuarios, garitas, paraderos y recorridos |
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

La app arranca como Invitado y muestra el mapa con paraderos de referencia sin
necesidad de configurar nada. Para que funcionen el registro, los recorridos y
el panel de garita hay que preparar el proyecto de Firebase:

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
5. Entrar como administrador y cargar los paraderos (hay un botón para importar
   los de ejemplo) y los recorridos de la línea.

Sin el paso 5, la búsqueda de direcciones funciona, pero la ficha de paradero no
tiene colectivos que mostrar y la recomendación cae a ordenar por cercanía.

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
(estacionamientos, accesos privados), y los trazados que calculó para las
líneas lo muestran. Valhalla se limita a calles públicas. La ruta a pie, en
cambio, va a propósito por pasajes y escaleras.

El trazado de una línea es la ruta en auto que pasa por sus paraderos en
orden, así que sólo sigue la calle correcta si los paraderos están sobre su
calle: un paradero corrido obliga a la línea a desviarse o a dar la vuelta a
la manzana para tocarlo. Se ubican desde el editor de paraderos (mantener
presionado sobre el mapa), que vuelve a calcular las líneas que pasan por él;
`node scripts/apply_recorridos_geometries.js` los recalcula todos (con
`--dry-run`, sin guardar).

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
├── models/       AppUser, BusStop, Recorrido, ColectivoActivo, Garita
├── navigation/   Destinos y qué ve cada rol
├── screens/      admin/ · auth/ · driver/ · mapa, paraderos, preferencias
├── services/     Estado de la app en singletons ChangeNotifier (sesión,
│                 paraderos, recorridos, telemetría, turno) más utilidades sin
│                 estado (geocodificación, planificador de paraderos, ruteo)
├── theme/        Tema Material 3, colores semánticos, espaciado
├── utils/        Formato de distancias, patentes, errores
└── widgets/      Menú lateral, hojas de paradero y sugerencias, buscador
```

Verificación: `flutter analyze` y `flutter test` (176 pruebas, sin red ni
Firebase). Entre ellas hay pruebas de contrato que leen `firestore.rules` y
`database.rules.json` y fallan si el cliente escribe un campo que las reglas
rechazarían.

## Publicar una versión

1. Subir `version:` en `pubspec.yaml` (p. ej. `0.4.4+5`). Es la única fuente:
   la app la lee del propio APK para compararla con la publicada.
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
4. Publicar el aviso de actualización:
   ```bash
   APK_URL=https://.../ColeTotal.apk CHANGELOG="• ..." node scripts/seed_app_version.js
   ```
   Con `MIN_REQUIRED=n` las versiones anteriores a `n` ven la actualización
   como obligatoria.

## Limitaciones conocidas

- **Sin recuperación de contraseña para choferes.** La patente se traduce a un
  correo sintético que no recibe mensajes; si un chofer pierde su contraseña,
  el administrador deshabilita la cuenta y le entrega un código nuevo.
- **El sentido de marcha no se modela.** Un recorrido se trata como el conjunto
  de sus paraderos, así que la recomendación asume que desde la subida se
  alcanza cualquier otra parada de esa línea.
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
