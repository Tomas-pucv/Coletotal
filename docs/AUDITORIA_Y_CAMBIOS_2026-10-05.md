# 🔍 ColeTotal — Auditoría Técnica y Registro de Cambios (5 de octubre de 2026)

> **Rama:** `proto` · **Versión declarada:** `0.4.3+4` (no se modificó)  
> **Estado:** todos los cambios están en el árbol de trabajo, **sin commit**.  
> **Alcance acordado:** corregir todos los errores (P0 a P4), agregar el selector de recorrido del chofer, alinear la documentación con el código y preparar la firma de release. El informe `.docx` no se tocó.

Este documento resume la auditoría completa de la app (código Flutter, reglas de Firebase, configuración Android, scripts y documentación), lo que se corrigió, cómo se verificó y lo que queda pendiente. El detalle línea por línea está en el diff de git.

---

## ⚠️ Antes de publicar: orden de despliegue

**Desplegar las reglas ANTES de repartir el APK nuevo:**

```bash
firebase deploy --only firestore:rules,database
```

La app nueva publica el campo `conectado` en cada posición. Las reglas viejas de Realtime Database rechazan cualquier campo que no conocen (`"$otro": false`), así que con ellas **toda la telemetría de la versión nueva sería rechazada** y los colectivos desaparecerían del mapa.

| Combinación | Resultado |
| :--- | :--- |
| App vieja + reglas viejas | Funciona como hasta ahora (con los errores de abajo). |
| App vieja + reglas nuevas | Funciona. Sólo falla la subida de auditoría de turnos (la app vieja no envía `uid`). |
| App nueva + reglas viejas | ❌ **No se publica ninguna posición.** |
| App nueva + reglas nuevas | ✅ Correcto. |

Después de repartir el APK nuevo conviene publicar `MIN_REQUIRED` con su número de compilación (ver §9) para que las instalaciones viejas queden obligadas a actualizar.

---

## 1. Cómo se verificó

| Verificación | Antes | Después |
| :--- | :--- | :--- |
| `flutter analyze` | 3 avisos | **Sin observaciones** |
| `flutter test` | 78 pruebas | **134 pruebas, todas aprobadas** (sin red ni Firebase) |
| `flutter build apk --release` | — | **Compila** (57,0 MB) con la nueva configuración de firma |

Además se comprobaron en vivo, con una petición cada uno, los dos supuestos más importantes:

- **Tamaño de las teselas de MapTiler:** la ruta por defecto (`/{z}/{x}/{y}.png`) entrega teselas de **512×512**; la ruta `/256/` entrega **256×256**, y `/256/…@2x` entrega **512×512** (versión retina del servidor).
- **Ruta a pie vs. ruta en auto** para el mismo par de puntos de Quilpué: el servidor peatonal de FOSSGIS respondió **641,9 m y 517 s (8,6 min)**; el servidor de demostración de OSRM, que es sólo para autos, respondió **1.088 m y 120 s (2 min)**. La app mostraba la segunda como si fuera caminando.

Los comportamientos de los plugins se verificaron leyendo su código fuente en la caché de pub (`geolocator_android 5.0.3`, `flutter_map 8.3.1`).

**No se verificó:** el comportamiento en un teléfono real (servicio en primer plano, modo avión, etc.; ver §10) ni las reglas en el emulador de Firebase, porque Firebase CLI no está instalado en este equipo. Las pruebas de contrato (§8) cubren la concordancia entre lo que escribe la app y lo que aceptan las reglas.

---

## 2. Errores corregidos

### 2.1. Críticos (P0)

#### P0-1 · El GPS del chofer nunca corría en primer plano
- **Síntoma:** con la pantalla bloqueada, Android limitaba la ubicación y el colectivo desaparecía del mapa de los pasajeros a los 3 minutos. La notificación "ColeTotal — en servicio" nunca aparecía.
- **Causa:** `geolocator_android` mantiene **un solo stream de posiciones** en caché y, mientras sigue vivo, devuelve ese mismo stream a cualquier llamada posterior a `getPositionStream`, **ignorando su configuración** (`geolocator_android.dart:169`). `MapScreen`, que el `IndexedStack` mantiene siempre montado, abría su stream al arrancar con una configuración simple. Por eso la configuración del turno (servicio en primer plano, *wake lock*, intervalo de 3 s) nunca se aplicaba.
- **Corrección:** nuevo `LocationService`, **único dueño del GPS** en toda la app. `setDriverMode(true)` cancela el stream y lo reabre con la configuración del turno (al cancelar la única suscripción, el plugin descarta su caché); `setDriverMode(false)` vuelve a la del pasajero. El mapa, la pestaña Paraderos, la ficha de paradero y la telemetría escuchan este servicio; ninguno llama a `geolocator` directamente.
- **Archivos:** `lib/services/location_service.dart` (nuevo), `firebase_telemetria_service.dart`, `turno_service.dart`, `map_screen.dart`, `routes_screen.dart`, `widgets/paradero_sheet.dart`, `main.dart`.

#### P0-2 · El primer arranque dejaba al mapa esperando el permiso para siempre
- **Causa:** el plugin guarda **un solo callback de permiso** (`PermissionManager.java`). El mapa y la pestaña Paraderos pedían permiso a la vez; el segundo pisaba al primero y el `Future` del mapa no se completaba nunca. El mapa no seguía al usuario hasta que éste tocaba el botón de recentrar.
- **Corrección:** `LocationService.ensurePermission()` comparte la solicitud en curso entre todos los que la piden. Además, al volver a la app desde los ajustes del teléfono se reintenta solo si faltaba el GPS o el permiso.

#### P0-3 · El botón de turno podía quedar girando para siempre
- **Causa:**
  1. `database.rules.json` rechaza todo hijo desconocido (`"$otro": false`), pero la app escribía `conectado` (en el `onDisconnect`), `recorridoId` y `recorridoNombre`.
  2. El `onDisconnect().update()` se registraba **antes** de que existiera el nodo, así que además fallaba la validación `hasChildren`.
  3. Se esperaba con `await` sin `try/catch`, y `iniciarTurno` no tenía `finally`: la excepción dejaba `_busy = true` para siempre.
- **Corrección:**
  - Las reglas aceptan `conectado` (booleano), `recorridoId` (≤ 128) y `recorridoNombre` (≤ 120), y exigen `ts <= now`.
  - El aviso de desconexión se registra **después de la primera escritura confirmada**, sin bloquear, y se vuelve a registrar en cada reconexión (`.info/connected`), porque el servidor lo consume al dispararse.
  - `iniciarTurno` y `terminarTurno` usan `try/finally`.

#### P0-4 · Sin señal, varias acciones esperaban indefinidamente
- **Causa:** el `Future` de una escritura de Firestore o Realtime Database se completa recién cuando **el servidor** la confirma; sin red no falla, se queda esperando. Esto colgaba "Terminar turno", "Cerrar sesión" (que espera al turno), "Iniciar turno" y todos los guardados del administrador. Era justo el escenario de cerros sin cobertura que el proyecto declara cubrir.
- **Corrección:** nuevo `confirmOrQueue` (`lib/services/firestore_writes.dart`): espera la confirmación como mucho 6 s; si no llega, devuelve `WriteOutcome.queuedOffline` y la escritura sigue en la cola local del SDK. Las operaciones de Realtime Database al terminar el turno tienen un plazo de 4 s. Las pantallas de administración muestran *"Guardado sin conexión: se sincronizará al recuperar la señal"*.
  ```dart
  final outcome = await confirmOrQueue(ref.set(data), label: 'paradero');
  // WriteOutcome.confirmed | WriteOutcome.queuedOffline
  ```
- **Afecta a:** terminar e iniciar turno, cerrar sesión, crear/editar/dar de baja/reactivar paraderos, importar la semilla, guardar/eliminar recorridos, habilitar/deshabilitar choferes, cambiar el nombre del perfil y subir la auditoría.
- **Detalle:** `StopsService.upsert` usa `doc()` + `set()` en vez de `add()`, porque `add()` no entrega el id hasta que responde el servidor.

#### P0-5 · El historial "Recientes" se borraba en cada arranque
- **Causa:** `StopHistoryService.load()` corre cuando sólo están cargados los paraderos semilla. Ningún id de Firestore resolvía todavía, la "migración" los descartaba **y guardaba esa lista vacía en disco**. El historial sólo duraba una sesión. El test existente validaba justamente ese comportamiento.
- **Corrección:** `migrateHistory()` (función pura) sólo convierte las entradas guardadas por nombre y **conserva** los ids desconocidos. Los ids que de verdad ya no existen se podan cuando llegan los paraderos reales. El servicio escucha a `StopsService` para redibujar la lista.

#### P0-6 · Colectivos fantasma
- **Causa:** el filtro de antigüedad sólo corría cuando llegaba un evento de Realtime Database. Si el último chofer en servicio se quedaba sin señal (o le cerraban la app), no llegaban más eventos y su marcador quedaba en el mapa de todos indefinidamente.
- **Corrección:** la flota se vuelve a filtrar cada 15 s aunque no lleguen eventos. Una unidad sin señal se dibuja **atenuada** a los 45 s y **desaparece** a los 180 s.

### 2.2. Funcionales (P1)

#### P1-1 · "Cómo llegar" calculaba la ruta en auto
- **Causa:** se pedía `driving-car` a OpenRouteService y `driving` a OSRM, y se mostraba el tiempo en auto como si fuera caminando (ver las cifras de §1). Además, la ruta en auto da rodeos por el sentido de las calles, que a un peatón no le importa.
- **Corrección:**
  - OpenRouteService usa `foot-walking`.
  - OSRM usa el servidor peatonal de FOSSGIS (`routing.openstreetmap.de/routed-foot`), el mismo que usa openstreetmap.org.
  - Como último recurso se usa el servidor de autos, con el tiempo recalculado a paso de peatón (`kWalkingSpeedMps = 1,3 m/s`).
  - La tarjeta del mapa muestra el ícono de caminata.

#### P1-2 · Distancias y rutas medidas desde la posición de partida
- **Causa:** `RouteService.origin` se fijaba con el primer punto GPS de la sesión, y el color de cercanía de los paraderos, la ficha de paradero y "Cómo llegar" lo preferían a la posición real. La pestaña Paraderos pedía la posición una sola vez, y mientras esperaba (en interiores, decenas de segundos) **un spinner a pantalla completa tapaba la lista**.
- **Corrección:**
  - Todo usa la posición actual de `LocationService`.
  - La lista de paraderos se muestra siempre, con un aviso "Buscando ubicación…".
  - La lista se reordena al moverse más de 50 m.

#### P1-3 · Autenticación
- **Errores:**
  - Un chofer deshabilitado que intentaba entrar veía *"Patente o contraseña incorrecta"*.
  - Sin red, el inicio de sesión decía "credenciales inválidas", y la comprobación del código de garita decía "código inválido".
  - Deshabilitar a un chofer no tenía efecto hasta que él reiniciara la app: seguía transmitiendo.
  - El listener de sesión lanzaba una segunda lectura del perfil en paralelo con la del inicio de sesión.
- **Corrección:**
  - `_refreshProfile` devuelve `ProfileResult { ok, missing, disabled, network }`, que se traduce a `cuentaDeshabilitada`, `sinConexion` o `credencialesInvalidas`.
  - `lookupCodigo` consulta sólo al servidor y lanza `sinConexion` si no puede; el registro muestra un estado "sin conexión" con ícono propio.
  - **La app escucha el propio documento de perfil** mientras hay sesión: si la garita pone `activo: false`, cierra la sesión en segundos (lo que también termina el turno).
  - Una bandera `_signingIn` evita la lectura duplicada.

#### P1-4 · Se perdían trazados de recorridos
- **Errores:**
  - El editor guardaba siempre sin `geometria`, así que **cambiar sólo el nombre o el color** de una línea reemplazaba su trazado (incluido el afinado con `apply_recorridos_geometries.js`) por uno recalculado, o **lo borraba** si OSRM no respondía.
  - `OsrmClient.maxWaypoints = 25` **cortaba en silencio** las líneas de más de 25 paraderos.
  - Mover un paradero nunca actualizaba el trazado guardado de las líneas que pasan por él.
- **Corrección:**
  - El editor conserva la geometría si la lista de paraderos no cambió.
  - Las líneas largas se piden en tramos de 25 que se solapan en un paradero y se cosen; para eso se agregó `OsrmClient.encodePolyline`.
  - Al mover un paradero, `GaritaService.recomputeGeometriasFor()` recalcula en segundo plano las líneas afectadas de la garita (o borra su geometría si OSRM falla, para que los clientes la calculen en vivo) y avisa cuántas actualizó.

#### P1-5 · El chofer no podía elegir su recorrido
- **Causa:** `TurnoService.setRecorridoAsignado` existía pero ninguna pantalla lo llamaba, así que `recorridoId` siempre iba vacío. El "toca un colectivo y se ilumina su línea" del mapa nunca funcionaba, aunque la documentación lo describía.
- **Corrección:** `TurnoScreen` tiene un selector con las líneas activas de la garita del chofer (más "Sin recorrido"). La elección se recuerda entre turnos, se puede cambiar en pleno turno y se publica en la telemetría y en la auditoría (`ROUTE_CHANGED`). Si la garita renombra o desactiva la línea durante el turno, el cambio llega al mapa de los pasajeros.

#### P1-6 · "Última posición enviada" no se actualizaba
- **Causa:** la línea sólo se redibujaba cuando cambiaba algo del turno; publicar posiciones no avisaba a nadie.
- **Corrección:** muestra "Última posición enviada hace 3 s", avanza segundo a segundo y escucha cada envío. Sin conexión aparece el aviso *"Sin señal: tu posición se enviará apenas vuelva la conexión"*.

#### P1-7 · Auditoría de turnos (`SessionLogService`)
- **Errores:**
  - El turno en curso se guardaba en el teléfono pero **nadie lo volvía a leer**: si Android cerraba la app, la jornada se perdía.
  - Los eventos no tenían tope: un turno largo sin señal (un `NETWORK_FAIL` cada pocos segundos) superaba el máximo de 1 MiB de un documento de Firestore y se reintentaba para siempre.
  - La versión estaba escrita a mano (`'0.4.3+3'`, incorrecta).
  - Se registraban eventos fuera del turno.
  - Reintentar un turno ya subido era un `update` que las reglas rechazan, y se reintentaba para siempre.
- **Corrección:**
  - El turno interrumpido se recupera al arrancar, marcado `interrumpida: true`.
  - Las fallas repetidas se agrupan con un contador (`repeticiones`), y hay un tope de 300 eventos por turno.
  - El guardado local se agrupa cada 10 s.
  - El documento incluye `uid` y la versión real.
  - Sin turno no se registra nada.
  - Los reintentos son sólo del chofer dueño, se descartan ante un rechazo de permisos y la cola tiene un tope de 20.
  - Se sincroniza al abrir la app, al iniciar sesión y al terminar un turno.

#### P1-8 · El planificador proponía "bajarse donde uno se sube"
- **Causa:** si la parada de una línea más cercana al destino era la propia subida, se proponía igual.
- **Corrección:** se guardan las dos mejores bajadas por línea y nunca se devuelve la subida como bajada.

#### P1-9 · Actualizador OTA
- **Errores:** `minRequiredVersionCode` se leía y se ignoraba (no había forma de retirar una versión con un error grave). Una actualización obligatoria sin enlace dejaba un diálogo imposible de cerrar.
- **Corrección:**
  - `isMandatoryFor(versionInstalada) = (esObligatoria || instalada < minRequired) && apkUrl no vacía`.
  - Una actualización obligatoria se vuelve a mostrar aunque se haya postergado.
  - Sólo se abren enlaces `https`.

#### P1-10 · Búsquedas sensibles a tildes y texto mal decodificado
- **Errores:**
  - "lider", "estacion" o "quilpue" no encontraban "Líder", "Estación" ni "Quilpué", y "belloto lider" no encontraba "Líder Belloto".
  - La respuesta de MapTiler se decodificaba con `res.body` (latin1 si falta el `charset`), con riesgo de "QuilpuÃ©".
- **Corrección:**
  - `utils/text_search.dart` (`normalizeForSearch`, `matchesAllTokens`) quita tildes y no depende del orden de las palabras. Se usa en el buscador del mapa, la lista de paraderos y la lista del administrador.
  - Las respuestas se decodifican como UTF-8 explícito.
  - Photon quedó acotado a la caja de la V Región, como ya decía la documentación.

#### P1-11 · Reloj del teléfono desfasado
- **Causa:** la antigüedad de cada unidad (`ts`, puesto por el servidor) se comparaba con el reloj del teléfono. Un teléfono adelantado tres minutos no veía **ningún** colectivo, y uno atrasado veía fantasmas.
- **Corrección:** se usa la hora del servidor (`.info/serverTimeOffset`) para la antigüedad y para el "visto hace" de la consola de flota.

#### P1-12 · Ruta anterior visible y respuestas cruzadas
- **Errores:** al elegir otro paradero, la ruta anterior seguía dibujada (con su distancia y su tiempo) bajo el nombre del paradero nuevo mientras se calculaba la nueva. Una respuesta lenta podía pisar a una más nueva.
- **Corrección:** `setDestination` limpia la ruta anterior y `fetchRoute` descarta las respuestas atrasadas con un número de petición.

#### Otros arreglos menores
- Al tocar un paradero en el mapa, la cámara ya no vuelve sola al usuario con el siguiente punto GPS.
- Tocar un colectivo abre su ficha al instante; antes esperaba a que se calculara el trazado de la línea.
- Centrar el mapa respeta la preferencia "Animaciones".
- `RecorridosService`: el indicador "Trazando el recorrido…" ya no se apaga por la respuesta de otra línea.
- `StopsService`: si el servidor confirma que no queda ningún paradero activo, el mapa lo refleja en vez de seguir mostrando los últimos.
- La ficha del colectivo muestra la patente, la capacidad detallada, "Última señal hace X" y "Sin señal" cuando corresponde.

### 2.3. Corrección posterior: rutas en la versión web

Encontrado al probar la app con `flutter run` en el navegador (dispositivo "Chrome", que en este equipo es Brave). En Android no ocurría.

- **Síntoma:** al elegir una ruta aparecían errores ("El servicio de rutas no respondió correctamente") y los recorridos se dibujaban como rectas entre paraderos en vez de seguir las calles.
- **Causa 1, el decodificador de polilíneas:**
  - Usaba los operadores de bits `~` y `>>`. En la web, Dart se compila a JavaScript y esos operadores devuelven enteros de 32 bits **sin signo**: `~(x >> 1)`, que en Android da -33.047.000, en el navegador daba 4.261.920.296.
  - Como todas las coordenadas de Quilpué son negativas, cada trazado se decodificaba a puntos fuera del mapa. Comprobado con el trazado guardado de la Línea 101: con el decodificador anterior compilado a JavaScript, **0 de 203 puntos** eran válidos (el primero quedaba en latitud 4261,9).
  - Así, los trazados guardados se dibujaban fuera del mapa y las respuestas de OSRM se descartaban por inválidas: los recorridos caían a las rectas de respaldo y "Cómo llegar" fallaba.
  - Este error es anterior a la auditoría.
- **Causa 2, la cabecera `User-Agent`:** en la web, `package:http` usa `fetch`, y una cabecera `User-Agent` propia obliga a una verificación CORS previa. Los servidores de ruteo la rechazan, porque sólo aceptan `X-Requested-With` y `Content-Type`. Esta causa sí la introdujo la auditoría, al pasar "Cómo llegar" por `OsrmClient`, que enviaba esa cabecera.
- **Corrección:**
  - `osrm_client.dart`: el decodificador y el codificador usan aritmética en vez de operadores de bits; dan el mismo resultado en Android y en la web.
  - `osrm_client.dart` y `geocoding_service.dart` (Photon): en la web no se envía `User-Agent` propio; en Android se sigue enviando, como piden las políticas de uso de esos servidores.
  - `recorrido.dart`: se descartan los puntos inválidos de una geometría guardada; si quedan menos de dos, el recorrido se trata como sin geometría y se recalcula siguiendo las calles, en vez de dibujarse mal.
- **Verificación:**
  - El decodificador nuevo, compilado a JavaScript, decodifica el trazado de la Línea 101 igual que en Dart nativo: 203 de 203 puntos válidos, del paradero Valencia al Hospital Quilpué.
  - Dos pruebas nuevas: coordenadas negativas de Quilpué contra una cadena de referencia de OSRM, y descarte de una geometría corrupta.
  - `flutter analyze` sin observaciones y 134 pruebas aprobadas.
- **Datos:** 9 de los 10 recorridos de Firestore tienen su trazado guardado. El recorrido `koVkYdvKxMq2gRjn7Cnh` no lo tiene: se calcula en vivo siguiendo las calles, y se puede guardar con `node scripts/apply_recorridos_geometries.js`.
- **Para verlo en una sesión abierta de `flutter run`:** reinicio completo con `R`; una recarga en caliente no vuelve a decodificar los recorridos ya cargados.

---

## 3. Rendimiento y cuota (P2)

| Problema | Corrección |
| :--- | :--- |
| **Cuota de MapTiler ×4 y texto diminuto.** Sin `{r}` en la plantilla, `retinaMode` activaba el modo retina *simulado* de flutter_map: cuatro teselas por casilla. Además, la ruta por defecto entrega teselas de 512 px en casillas de 256. | Plantilla `…/maps/{estilo}/256/{z}/{x}/{y}{r}.png`: retina del servidor, **una petición por casilla**, texto del tamaño correcto. Respaldo CARTO también con `{r}`. |
| `TileLayer` creaba un `NetworkTileProvider` nuevo (con su propio cliente HTTP) **en cada reconstrucción** del mapa, perdiendo las conexiones abiertas. | Nuevo `widgets/app_tile_layer.dart`, común a los tres mapas, con un solo proveedor. |
| Los tres mapas tenían configuraciones distintas (retina, respaldo, User-Agent `com.example.taxi1`). | Unificados en `AppTileLayer` con `kTileUserAgentPackage = 'cl.coletotal.app'`. |
| Cuatro pantallas (mapa, flota, portada de garita, choferes) abrían **cada una** su suscripción a la flota y volvían a procesar el nodo entero con cada movimiento de cada unidad. | **Una sola suscripción** en `FirebaseTelemetriaService.state`, con como mucho un aviso por segundo. |
| Cada movimiento de un colectivo redibujaba **toda** la pantalla del mapa (teselas, todos los paraderos, controles). | Capas que escuchan sus propios datos: `_ColectivosLayer`, `_StopsLayer`, `_UserLocationLayer`. |
| Cada paradero del mapa tenía su propio `AnimationController` aunque nunca fuera a latir. | El pulso se crea sólo en el paradero seleccionado. |
| La consola de flota se redibujaba aunque su pestaña no estuviera a la vista. | Se pausa mientras está oculta y se pone al día al volver. |
| Sin señal, la telemetría encolaba una escritura por cada punto GPS y al reconectar enviaba cientos. | No escribe sin conexión; al reconectar publica sólo la posición actual. |
| `StopPlanner` hacía miles de cálculos geodésicos (Vincenty) por búsqueda: O(S·R·L). | Cada distancia se calcula una vez: O(S + ΣL). |
| `StopsService.byId` recorría la lista entera y se llamaba dentro de bucles. | Índice por id (`Map`). |
| Los chips de garita de la consola de flota estaban escritos a mano (ids, nombres y un caso especial para unidades sin garita). | Se leen de la colección `garitas`; arranca en la garita del administrador. Al tocar una unidad se dibuja su recorrido. |

---

## 4. Seguridad y operación (P3)

### 4.1. Reglas de Firestore (`firestore.rules`)

| Antes | Ahora |
| :--- | :--- |
| Cualquier administrador, **incluso deshabilitado**, podía listar los usuarios de **todas** las garitas. | `allow list: if isAdminOf(resource.data.garitaId) && request.query.limit <= 200;` La consulta debe filtrar por la garita del propio administrador activo. |
| Cualquier cuenta con sesión podía crear auditorías en **cualquier** garita, de cualquier tamaño. | Sólo el propio chofer (`uid == request.auth.uid`), en **su** garita (`me().garitaId == garitaId`), con `eventos` como lista de ≤ 500. |
| Los paraderos sólo validaban coordenadas al crearse; un `update` podía escribir cualquier cosa. | `paraderoValido()` en `create` y `update`: coordenadas en rango, `nombre` de 1–60, `direccion` ≤ 120, `activo` booleano. |
| Los recorridos no se validaban. | `recorridoValido()`: `nombre` de 1–80, `paraderoIds` lista de ≤ 200, `color` entero, `activo` booleano, `geometria` texto de ≤ 300.000. |
| El dueño podía cambiar su `nombre` sin límite de largo. | `nombre` texto de 1–60. |

### 4.2. Reglas de Realtime Database (`database.rules.json`)
- Se permiten `recorridoId` (texto ≤ 128), `recorridoNombre` (texto ≤ 120) y `conectado` (booleano).
- `ts` debe ser `<= now`: antes una marca de tiempo futura mantenía "viva" una unidad para siempre.

### 4.3. Secretos fuera del repositorio
- `docs/LISTA_USUARIOS_Y_CREDENCIALES_PRUEBAS.md` y `scripts/seed_dummy_data.js` tenían en texto plano **el código de administrador de la garita, el código de chofer y la contraseña compartida de los choferes de prueba**, además de correos personales. Estaban publicados en `origin/Proto`. Con el código de administrador cualquiera podía registrarse como administrador y gestionar la garita entera.
- Se quitaron del repositorio: el script los recibe por variables de entorno (`CHOFER_CODE`, `ADMIN_CODE`, `TEST_DRIVER_PASSWORD`) y el documento quedó sin credenciales.
- **El historial de git los conserva: hay que rotarlos** (ver §9).

### 4.4. Scripts de administración (`scripts/`)
- **Nuevo `scripts/lib/firebase_rest.js`:**
  - Credenciales de Firebase CLI resueltas con `npm root -g`, o con `FIREBASE_TOOLS_PATH`. Antes los cuatro scripts usaban la ruta absoluta `C:/Users/marco/...` y fallaban en cualquier otro equipo.
  - Lectura paginada de colecciones y conversión de valores de Firestore, antes duplicada en cada script.
- **`apply_recorridos_geometries.js`:**
  - Se eliminó el parche puntual que reescribía los paraderos del recorrido `LA9lCeZPZ2Gv66LuO8Jy` en **cada** ejecución, pisando las ediciones del administrador.
  - Lee todos los documentos (antes, sólo los primeros 100).
- **`backup_coletotal.js`:** pagina (antes se detenía en 300 documentos en silencio) e incluye `config` y la auditoría de turnos de cada garita.
- **`seed_app_version.js`:**
  - Toma la versión de `pubspec.yaml`, y el enlace, las novedades y la versión mínima de variables de entorno.
  - Rechaza enlaces que no sean `https`.
  - Antes había que editar el archivo en cada entrega.
- **`seed_dummy_data.js`:** escribe la telemetría de demostración con `PATCH` en vez de `PUT`. El `PUT` reemplazaba el nodo entero y sacaba del mapa a los choferes reales en turno.

### 4.5. Firma del APK (`android/app/build.gradle.kts`)
- **Problema:** los APK de release se firmaban con la llave de debug de cada computador. Android sólo instala una actualización encima de otra si ambas tienen la misma firma, así que **un APK compilado por un integrante no podía actualizar uno compilado por el otro**, y la actualización OTA fallaba.
- **Cambio:** si existe `android/key.properties` (ignorado por git) se firma con la llave del proyecto; si no, se sigue usando la de debug, como hasta ahora. Las instrucciones están en el README.

---

## 5. Calidad de código y refactorizaciones (P4)

- **Versión única:** la versión estaba escrita a mano en cuatro lugares que no coincidían (`pubspec.yaml` `0.4.3+4`, actualizador `4`/`'0.4.3.1'`, auditoría `'0.4.3+3'`, Preferencias `'0.4.3.1'`). Ahora `lib/config/app_version.dart` la lee del propio APK con `package_info_plus`, que ya venía compilado en la app como dependencia de `geolocator`.
- **Textos traducibles:** se movieron al ARB los textos escritos a mano del diálogo de actualización, el botón "Buscar actualizaciones", la ficha del colectivo, el estado de capacidad detallado y los chips de la consola de flota.
  - Se agregaron 34 claves y se eliminaron 25 que ya no se usaban (pantalla de bienvenida, idioma, "en construcción", etc.).
  - El texto de la notificación del turno también sale del ARB.
- **Código muerto:** se eliminó `SettingRadioTile` (sin uso).
- **Tarjeta de coordenadas del mapa eliminada (a pedido):** la tarjeta inferior del mapa que mostraba la latitud y longitud del usuario (o "Buscando ubicación…") ya no aparece. Abajo sólo se muestra la tarjeta de la ruta a pie activa (paradero, distancia y tiempo caminando). Si el mapa sigue al usuario se ve en el botón de recentrar, y los problemas de GPS siguen apareciendo como avisos arriba. Archivo: `lib/screens/map_screen.dart` (`_StatusCard`).
- **Avisos del analizador:** se corrigieron los tres (`mounted` en lugar de `context.mounted` en Preferencias, y elementos `?` en los mapas).
- **`PlaceResult` pasó a `lib/models/place_result.dart`:** cortaba un ciclo de importación entre `data/` y `services/`. Además, `kQuilpuePois` ahora es `const`.
- **`OsrmClient` es el único cliente de ruteo:**
  - Agregados: perfiles a pie y en auto, troceo de líneas largas, codificación de polilíneas y un cliente HTTP inyectable.
  - `RouteService` dejó de duplicar la petición, el decodificador y la validación de coordenadas.
- **Utilidades compartidas nuevas:**
  - `AppStatusColors.forEstado()` reemplaza tres `switch` idénticos.
  - `utils/estado_format.dart` (`estadoLabel`).
  - `formatAgo` en `utils/distance_format.dart`.
  - `utils/text_search.dart`.
- **Carga y estados:**
  - `GaritaService.loading` ahora es real. Antes se apagaba en el mismo instante en que se encendía y la pantalla de choferes mostraba "no hay choferes" mientras cargaba.
  - La consola de flota muestra "cargando" antes del primer dato.
- **Administración de paraderos:**
  - Lista los de la garita del administrador, **incluidos los dados de baja**, que ahora se pueden reactivar.
  - Antes mostraba los de todas las garitas (editar uno ajeno terminaba en error de permisos) y un paradero dado de baja desaparecía sin forma de recuperarlo.
  - Nombre, dirección y nombre de recorrido tienen el mismo largo máximo que exigen las reglas.
- **Accesibilidad:** los marcadores de colectivo tienen etiqueta para lectores de pantalla (patente y capacidad, o "sin señal").
- **Pruebas sin red:** los tests del buscador salían a la red de verdad (gastaban cuota de MapTiler y dependían de la conexión). Ahora usan un cliente HTTP simulado.

---

## 6. Documentación

| Archivo | Cambio |
| :--- | :--- |
| `README.md` | Funcionalidades al día: recorrido del chofer, ruta a pie, unidades "sin señal", reactivar paraderos, operación sin señal. También la sección "Publicar una versión" (versión, firma, aviso OTA), la cantidad de pruebas y las limitaciones. |
| `docs/ARQUITECTURA_Y_REGISTRO_TECNICO_PARA_IA.md` | Reescrito para describir sólo lo que el código hace. Nuevas secciones: GPS único, presencia, operación sin señal, ruta a pie y elección del recorrido. Mapa de archivos y reglas actualizados. |
| `docs/LISTA_USUARIOS_Y_CREDENCIALES_PRUEBAS.md` | Sin códigos, contraseñas ni correos personales. Flujo real del chofer, con la elección del recorrido. |
| `docs/PLAN_DE_PRUEBAS_Y_ESTRES_DETALLADO.md` | Lo no implementado quedó marcado **(propuesto, pendiente)**: Crashlytics, exención de batería, frecuencia adaptativa, jerarquía `empresas/…`, llaves de acceso simplificadas, eventos `APP_START`/`LOW_MEMORY_ALERT`. Cifras corregidas: 26 POIs, radio de 6 km, caché integrada de flutter_map. |
| `docs/estrategia_respaldo_firebase.md` | El Patrón Repositorio, el botón "Exportar Datos de Línea", `turnos_historicos` y el sifón CSV quedaron como **propuestos**. "Caché SQLite" corregido a caché offline de Firestore. El argumento para la defensa dejó de afirmar que el repositorio está implementado. |
| `docs/plan_pruebas_y_arquitectura_operacional.md` | **Eliminado:** era una copia idéntica, byte por byte, del anterior. |
| `docs/AUDITORIA_Y_CAMBIOS_2026-10-05.md` | Este documento. |

---

## 7. Inventario de archivos

### 7.1. Nuevos

| Archivo | Para qué |
| :--- | :--- |
| `lib/services/location_service.dart` | Único dueño del GPS: permiso compartido, modo pasajero / modo turno (servicio en primer plano), reintento al volver de ajustes. |
| `lib/services/firestore_writes.dart` | `confirmOrQueue` y `WriteOutcome`: escrituras que no se cuelgan sin señal. |
| `lib/config/app_version.dart` | Versión instalada, leída del APK. |
| `lib/models/place_result.dart` | Resultado del buscador (movido desde `GeocodingService`). |
| `lib/utils/text_search.dart` | Búsqueda sin tildes y sin depender del orden de las palabras. |
| `lib/utils/estado_format.dart` | Etiquetas de capacidad (corta y detallada). |
| `lib/widgets/app_tile_layer.dart` | Capa de teselas común a los tres mapas. |
| `scripts/lib/firebase_rest.js` | Credenciales y REST de Firestore compartidos por los scripts. |
| `test/location_service_test.dart` | GPS falso: una sola solicitud de permiso, servicio en primer plano al iniciar el turno, posiciones inválidas, preferencia apagada. |
| `test/route_service_test.dart` | Ruta a pie, tiempo a paso de peatón, respuestas atrasadas, limpieza de la ruta anterior. |
| `test/telemetria_test.dart` | Nodos ilegibles, antigüedad contra la hora del servidor, "sin señal", quitar el recorrido. |
| `test/rules_contract_test.dart` | Lo que escribe la app cabe en `database.rules.json` y `firestore.rules`. |
| `test/firestore_writes_test.dart` | Plazo de `confirmOrQueue` y errores tardíos. |
| `test/text_search_test.dart` | Normalización y búsqueda por palabras. |

### 7.2. Modificados

| Área | Archivos |
| :--- | :--- |
| Servicios | `auth_service`, `firebase_telemetria_service` (reescrito), `turno_service` (reescrito), `session_log_service` (reescrito), `route_service` (reescrito), `osrm_client` (reescrito), `geocoding_service`, `garita_service`, `stops_service`, `recorridos_service`, `stop_history_service`, `stop_planner`, `app_update_service` |
| Pantallas | `map_screen` (reescrito), `routes_screen`, `preferences_screen`, `driver/turno_screen`, `admin/flota_screen` (reescrito), `admin/paraderos_admin_screen`, `admin/recorridos_admin_screen`, `admin/choferes_admin_screen`, `admin/garita_hub_screen`, `auth/register_screen` |
| Widgets | `app_update_dialog`, `paradero_sheet`, `map_search_bar`, `setting_tile` |
| Modelos y datos | `colectivo_activo` (campo `conectado`, `seemsOffline`, `antiguedad`), `recorrido`, `data/quilpue_pois` |
| Configuración | `main.dart`, `config/map_config.dart`, `theme/app_colors.dart`, `utils/distance_format.dart`, `l10n/app_es.arb` (y archivos generados), `pubspec.yaml`, `pubspec.lock` |
| Reglas | `firestore.rules`, `database.rules.json` |
| Android | `android/app/build.gradle.kts` |
| Scripts | `apply_recorridos_geometries.js`, `backup_coletotal.js`, `seed_app_version.js`, `seed_dummy_data.js` |
| Pruebas | `app_update_test`, `planner_test`, `quilpue_pois_test`, `session_log_test`, `stops_test`, `widget_test` |
| Documentación | ver §6 |

### 7.3. Dependencias
- **Nueva dependencia directa:** `package_info_plus` (ya estaba compilada en la app como dependencia de `geolocator`, así que no agrega peso).
- **Nuevas dependencias de desarrollo:** `geolocator_platform_interface` y `plugin_platform_interface`, sólo para el GPS falso de las pruebas. Ya estaban en el `pubspec.lock`.

---

## 8. Pruebas automatizadas

De **78 a 134 pruebas**, todas sin red ni Firebase. Además de las nuevas de §7.1:

- **`stops_test.dart`:** se reescribió la prueba de migración del historial, que **validaba el error** de borrar los ids de Firestore. Ahora prueba que se conservan y que los nombres antiguos se convierten.
- **`app_update_test.dart`:** `minRequiredVersionCode`, obligatoria sin enlace y sólo `https`.
- **`session_log_test.dart`:** sin turno no registra nada, agrupación de fallas, tope de eventos, cola local sin Firebase, recuperación de un turno interrumpido.
- **`planner_test.dart`:** nunca propone bajarse en la subida; troceo de líneas largas sin repetir el punto de unión; codificación y decodificación de polilíneas, incluidas las coordenadas negativas de Quilpué contra una cadena de referencia (§2.3); descarte de geometrías corruptas.
- **`quilpue_pois_test.dart`:** búsqueda sin tildes, respaldo en Photon con texto UTF-8 y acotado a la región, todo con HTTP simulado.
- **`widget_test.dart`:** las plantillas de teselas usan `/256/` y `{r}`.

Las **pruebas de contrato** (`rules_contract_test.dart`) son las que evitan que el error P0-3 vuelva a ocurrir: leen las reglas reales del repositorio y fallan si la app escribe un campo que las reglas rechazarían.

---

## 9. Acciones pendientes (manuales)

1. **Desplegar las reglas** antes de repartir el APK nuevo (ver el inicio de este documento):
   `firebase deploy --only firestore:rules,database`.
2. **Rotar los códigos de garita y la contraseña de los choferes de prueba**, que estuvieron publicados en `origin/Proto`:
   - Crear códigos nuevos en `codigos_acceso`.
   - Marcar los viejos con `activo: false`.
   - Cambiar las contraseñas de las cuentas de prueba.
3. **Crear la llave de firma del proyecto** una sola vez (README → "Publicar una versión") y compartirla por un canal privado. Todos los APK futuros deben firmarse con ella. La primera instalación firmada con la llave nueva exige desinstalar una vez las versiones firmadas con llaves de debug.
4. **Instalar Firebase CLI** donde se despliegue y se corran los scripts: `npm install -g firebase-tools` y `firebase login`.
5. **Publicar la versión:**
   - Subir `pubspec.yaml` a `0.4.4+5`.
   - Compilar y subir el APK.
   - Correr `APK_URL=… CHANGELOG=… node scripts/seed_app_version.js`.
   - Cuando la mayoría haya actualizado, repetir con `MIN_REQUIRED=5` para obligar a las instalaciones viejas, cuya auditoría de turnos las reglas nuevas rechazan.
6. **Hacer commit** de los cambios (están todos en el árbol de trabajo de `proto`).
7. **Actualizar el informe** de Proyecto de Título donde describa comportamientos que cambiaron: GPS en segundo plano, ruta a pie, auditoría de turnos, recorrido del chofer, cantidad de pruebas. El informe se genera con scripts de Python, no se edita a mano.

---

## 10. Verificación en un teléfono real (pendiente)

Con un APK de release en Android:

- [ ] **Instalación limpia:** aparece **un solo** diálogo de permiso de ubicación y el mapa sigue al usuario sin tocar nada.
- [ ] **Chofer:** elige recorrido e inicia el turno. Aparece la notificación fija **"ColeTotal — en servicio"**. Con la pantalla bloqueada 5 minutos, otro teléfono sigue viendo moverse la unidad.
- [ ] **Modo avión en pleno turno:**
  - En otro teléfono, la unidad se ve atenuada a los ~45 s.
  - "Terminar turno" termina en menos de 10 s.
  - Al reconectar, el documento de auditoría aparece en Firestore.
- [ ] **Cerrar la app a la fuerza en pleno turno:** la unidad desaparece del mapa en menos de 3 minutos, y al volver a abrir la app el turno se sube marcado `interrumpida`.
- [ ] **"Cómo llegar":** la duración corresponde a caminar (≈ 12 min por kilómetro) y la ruta parte de la posición actual.
- [ ] **Tocar un colectivo** que informó su recorrido ilumina la línea.
- [ ] **Administrador:** deshabilita a un chofer en turno; su app cierra sesión en segundos y la unidad sale del mapa.
- [ ] **Administrador sin señal:** guardar un paradero muestra "Guardado sin conexión" y se sincroniza al volver la red.
- [ ] **Mapa:** los nombres de las calles se leen bien y, en DevTools, las peticiones de teselas son cerca de un cuarto de las de antes.

---

## 11. Sugerencias y revisiones futuras

### 11.1. Distribución y publicación
- **`applicationId com.example.taxi1`** (y `iosBundleId`): definir el identificador definitivo (p. ej. `cl.coletotal.app`) antes de ampliar el piloto. Cambiarlo obliga a reinstalar una vez, así que conviene hacerlo junto con la llave de firma nueva.
- **Alojamiento del APK:** hoy se descarga desde `files.catbox.moe`, un servicio anónimo de archivos. Conviene usar GitHub Releases o Firebase Hosting y publicar el SHA-256 del archivo.
- **Portal `public/index.html`:**
  - El botón de iPhone dice que la app funciona en Safari, pero enlaza a la misma página de descarga: no hay versión web desplegada. Corregir el texto o desplegar una versión web.
  - En iPhone se muestra igual la caja de descarga de Android.
  - El código QR depende de un servicio externo (`api.qrserver.com`); conviene una imagen estática.
- **`pubspec.yaml`:** la descripción sigue siendo "A new Flutter project.".

### 11.2. Android y permisos
- **Permiso de notificaciones (Android 13+):** sin él, el servicio del turno sigue transmitiendo pero la notificación no se ve. Pedirlo al iniciar el primer turno (por ejemplo con `permission_handler`).
- **`ACCESS_BACKGROUND_LOCATION`:** con el servicio en primer plano funcionando ya no es necesario. Quitarlo del manifiesto después de verificar en un teléfono que el turno sigue transmitiendo con la pantalla bloqueada. Es un permiso sensible (Ley 19.628 y políticas de Google Play).
- **Exención de optimización de batería** (Xiaomi MIUI, Samsung One UI congelan el GPS): propuesta en el plan de pruebas, sin implementar.
- **Frecuencia adaptativa del GPS** (detenido → 10 s): propuesta, sin implementar.
- **Al actualizar `geolocator`:** volver a verificar en un teléfono que la notificación del turno aparece. `LocationService` depende de que el plugin descarte su stream en caché al cancelarse la única suscripción (comportamiento verificado en `geolocator_android 5.0.3`).

### 11.3. Seguridad
- **Choferes deshabilitados en Realtime Database:** las reglas no pueden consultar Firestore, así que no saben si un chofer está deshabilitado. La app oficial cierra su sesión, pero un cliente modificado podría seguir escribiendo. Alternativas: Cloud Functions que revoquen la sesión o reflejen `activo` en Realtime Database, o *custom claims*. Ambas requieren el plan Blaze o un servidor.
- **Firebase App Check:** bloquearía escrituras que no vengan de la app oficial (por ejemplo, telemetría falsa con un script).
- **Restringir las claves de API:** la clave de Android de Firebase, por paquete y huella SHA-1, en Google Cloud Console; la clave de MapTiler incluida en el APK (`kMapTilerKey`), por aplicación u origen en el panel de MapTiler. Rotarla si se abusa de ella.
- **Pruebas de reglas con el emulador** (`@firebase/rules-unit-testing`): complementarían las pruebas de contrato con casos de permiso reales (admin de otra garita, chofer deshabilitado, auditoría ajena).

### 11.4. Funcionalidad pendiente
- **ETA (RF-08)** y **sentido de marcha** de los recorridos (ida y vuelta): el planificador hoy asume que desde la subida se llega a cualquier parada de la línea.
- **Planificador:** si caminar directo al destino es más corto que el total a pie con colectivo, sugerir caminar.
- **Resumen del turno** (tiempo en cada estado de capacidad, kilómetros) y **exportación de datos de la línea** desde el panel de garita: propuestos en `estrategia_respaldo_firebase.md`.
- **Crashlytics** para errores no controlados en terreno.
- **Patrón Repositorio** para desacoplar los servicios de los SDK de Firebase (propuesto).
- **Paraderos de otras garitas:** hoy el administrador sólo ve los suyos; si se necesitara verlos, mostrarlos en sólo lectura.

### 11.5. Rendimiento
- Si la flota crece: agrupar marcadores (*clustering*) y filtrar las unidades por la zona visible del mapa, en vez del radio fijo de 6 km.
- **Caché de Firestore ilimitada** (`CACHE_SIZE_UNLIMITED`): con los datos actuales no importa, pero en teléfonos con poco almacenamiento conviene un tope (p. ej. 100 MB).
- **Servidores de ruteo públicos** (demostración de OSRM, FOSSGIS): no ofrecen garantías y piden uso moderado. Para producción conviene una clave de OpenRouteService (`ORS_API_KEY`) o un servidor OSRM propio.

### 11.6. Calidad y mantenimiento
- **Dependencias:** `flutter pub outdated` muestra 39 paquetes con versiones nuevas fuera del rango actual (p. ej. `geolocator 14.1.x`, `flutter_map 8.3.2`, `latlong2 0.10.x`). Planificar una actualización con verificación en un teléfono (ver §11.2).
- **`.gitattributes`:** normalizar los finales de línea. Los registradores de plugins de `linux/`, `macos/` y `windows/` aparecen modificados sólo por eso.
- **Pruebas de interfaz:** agregar pruebas de `TurnoScreen` y `MapScreen` con servicios simulados, y pruebas de integración en dispositivo para el turno completo.
- **Pruebas en la web:** `flutter test` corre en la máquina virtual de Dart, donde los enteros se comportan distinto que en JavaScript; por eso no detectó el error de §2.3. Si la app se va a usar en el navegador, conviene correr también `flutter test --platform chrome`.
- **Animaciones:** el botón "Orientar al norte" sigue animando aunque la preferencia "Animaciones" esté apagada (detalle menor).
- **Instalaciones viejas:** su auditoría de turnos se rechaza con las reglas nuevas (no envían `uid`) y queda reintentándose en su cola local. Se resuelve obligándolas a actualizar con `MIN_REQUIRED` (§9).
