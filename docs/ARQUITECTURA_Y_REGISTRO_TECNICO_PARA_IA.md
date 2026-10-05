# 🚖 ColeTotal — Arquitectura, Decisiones Técnicas y Registro de Continuidad para Desarrollo
> **Para:** Tomás Moraga & Asistentes de IA de Desarrollo  
> **De:** Marco Fernandoy & Pair Programming Agent  
> **Proyecto:** ColeTotal — Sistema Inteligente de Transporte Colectivo para Quilpué (Transportes Serrano S.A.)  
> **Versión Actual del Sistema:** `0.4.3+4` (la que declara `pubspec.yaml`) — *Alineada con el Hito 4 / Incremento 1.2 & 2.1 del Informe de Avance de Proyecto de Título*  
> **Fecha:** Octubre 2026 (revisado tras la auditoría técnica del 5 de octubre)  

---

## 📌 1. Propósito de este Documento

Este documento es la **fuente de verdad técnica consolidada** de lo construido en ColeTotal. Si estás leyendo esto como Tomás o como un modelo de Inteligencia Artificial al que se le encarga una nueva tarea o corrección sobre el repositorio, este texto te entrega el contexto: **el porqué detrás de cada decisión**, la justificación contra las limitaciones del mundo real (smartphones de gama baja de los colectiveros, cuotas de APIs, conectividad intermitente en Quilpué) y el mapa de archivos que componen el sistema.

Regla de este documento: **sólo se describe lo que el código hace**. Lo propuesto y todavía no implementado va marcado como tal.

---

## 🧭 2. Resumen Ejecutivo del Problema y Justificación Teórica

En la defensa de avance se criticaron principalmente tres vulnerabilidades del proyecto original:
1. **Dependencia ciega de servicios en la nube (Single Point of Failure):** Si Firebase o MapTiler fallan o agotan su cuota gratuita, la app no puede quedarse en blanco ni bloquear las pruebas con la línea Serrano.
2. **Desconexión con la realidad de los usuarios finales:** Los colectiveros son en su mayoría personas de 50 a 68 años con smartphones Android de gama de entrada (2 GB a 3 GB de RAM, baterías degradadas) y baja alfabetización digital; no se les puede pedir que busquen APKs en carpetas de descargas ni que gestionen correos corporativos complejos.
3. **Falta de rigor en versionado y pruebas de estrés:** Las versiones no estaban atadas a la metodología de desarrollo incremental ni existía registro de qué fallos sufren los choferes en su recorrido diario.

---

## ⚙️ 3. Soluciones Técnicas Implementadas (El "Por Qué" de Cada Cambio)

### 3.1. Consumo de Cuota de MapTiler y Respaldo Cartográfico
* **El Problema:** MapTiler otorga una cuota mensual gratuita de teselas que se consumía a un ritmo insostenible.
* **La causa principal (encontrada en la auditoría):** la plantilla de URL no tenía el marcador `{r}` y `TileLayer` usaba `retinaMode`. Sin `{r}`, flutter_map *simula* el modo retina pidiendo **cuatro teselas** del zoom siguiente por cada casilla: cuatro veces más peticiones, y con nombres de calles diminutos, porque además la ruta por defecto de MapTiler entrega teselas de 512 px.
* **La Solución:**
  1. `lib/config/map_config.dart` pide teselas de 256 px con `{r}` (`…/maps/{estilo}/256/{z}/{x}/{y}{r}.png`): el servidor entrega la versión `@2x` en pantallas densas, **una petición por casilla**.
  2. Los tres mapas (pasajero, flota, editor de paraderos) usan un único widget, `lib/widgets/app_tile_layer.dart`, con el mismo respaldo y User-Agent, y un solo `NetworkTileProvider` (antes se creaba uno nuevo, con su cliente HTTP, en cada reconstrucción del mapa).
  3. flutter_map 8 guarda las teselas en disco con su caché integrada y respeta los encabezados HTTP del servidor.
  4. Respaldo `fallbackUrl`: si una tesela de MapTiler falla (error de red o HTTP, incluida la cuota agotada), flutter_map pide esa misma tesela a **CARTO** (claro/oscuro) o **Esri World Imagery** (satélite), tesela por tesela.

### 3.2. Buscador de Destinos con Puntos de Interés (POIs) Locales y Photon
* **El Problema:** MapTiler Geocoding en Chile sólo resuelve direcciones formales con numeración (ej. *"Freire 1420"*). Si un pasajero escribía *"Líder Belloto"*, *"Hospital"* o *"Plaza Vieja"*, la búsqueda fallaba o devolvía resultados absurdos a 700 km (como la comuna de Freire en la Araucanía).
* **La Solución:**
  1. `lib/data/quilpue_pois.dart` contiene **26 hitos urbanos** de Quilpué (supermercados, plazas, salud, colegios, estaciones EFE, servicios públicos).
  2. `GeocodingService` (`lib/services/geocoding_service.dart`) aplica un **motor híbrido**:
     - *Paso 1:* cotejo local instantáneo, **sin distinguir tildes ni orden de palabras** ("lider", "belloto lider" y "Líder" encuentran lo mismo; ver `lib/utils/text_search.dart`).
     - *Paso 2:* si faltan resultados, MapTiler Geocoding acotado a la V Región; si MapTiler falla, **Photon (OpenStreetMap)** con la misma caja (`-71.75,-33.20,-71.20,-32.90`).
  3. Las respuestas se decodifican como UTF-8 explícito (sin eso, "Quilpué" podía llegar como "QuilpuÃ©").
  4. En la interfaz (`MapSearchBar`), los POIs se destacan con el icono `Icons.stars_rounded`.

### 3.3. Telemetría Resiliente: Presencia, "Sin Señal" y Fantasmas
* **El Problema:** Un chofer que pasa por una zona de sombra celular no debe desaparecer del mapa, pero una unidad cuyo teléfono se apagó tampoco debe quedar clavada en el mapa.
* **La Solución (`FirebaseTelemetriaService`):**
  1. **Presencia:** el servicio escucha `.info/connected`. Mientras no hay conexión no se escribe (antes se encolaba una escritura por cada punto GPS y se reenviaban todas al volver la señal). Al reconectar se publica la posición actual.
  2. **Aviso de desconexión:** después de la primera escritura confirmada se registra `onDisconnect().update({conectado: false, ts})`, y se vuelve a registrar tras cada reconexión (el servidor lo consume al dispararse). Antes se registraba *antes* de que existiera el nodo, por lo que las reglas lo rechazaban siempre.
  3. **En el mapa:** una unidad con `conectado: false` o más de **45 s** sin posición se dibuja **atenuada** ("Sin señal"); a los **180 s** (`ColectivoActivo.maxAntiguedad`) desaparece.
  4. **Fantasmas:** la lista se vuelve a filtrar cada 15 s aunque no lleguen eventos. Antes el filtro de antigüedad sólo corría cuando algún nodo cambiaba, y la última unidad que quedaba en silencio no desaparecía nunca.
  5. **Hora del servidor:** la antigüedad se mide contra la hora del servidor (`.info/serverTimeOffset`), no contra el reloj del teléfono: un teléfono adelantado tres minutos no veía ningún colectivo.
  6. **Una sola lectura:** toda la app comparte una suscripción a `colectivos_activos` (`FirebaseTelemetriaService.state`), con como mucho un aviso por segundo. Antes cada pantalla abría la suya y el mapa entero se redibujaba con cada movimiento de cada unidad.

### 3.4. GPS en Segundo Plano y Servicio en Primer Plano (Teléfonos de Chofer)
* **El Problema:** Al bloquear la pantalla, Android estrangula la ubicación de las apps en segundo plano y, en teléfonos con poca RAM, termina el proceso.
* **El defecto encontrado en la auditoría:** el código pedía un servicio en primer plano, pero **nunca se aplicaba**. El plugin `geolocator` mantiene un único stream de posiciones e ignora la configuración de quien lo pide después. El mapa abría el suyo al arrancar la app, así que la configuración del turno (notificación, wake lock) se descartaba. Además, el mapa y la pestaña Paraderos pedían permiso de ubicación a la vez en el primer arranque, y el plugin perdía una de las dos solicitudes.
* **La Solución (`lib/services/location_service.dart`):**
  1. Un único dueño del GPS para toda la app. Las pantallas y la telemetría lo escuchan; nadie más llama a `geolocator`.
  2. Al iniciar el turno, `setDriverMode(true)` cierra y reabre el stream con `AndroidSettings` de turno: servicio en primer plano con notificación fija ("ColeTotal — en servicio"), `enableWakeLock` e intervalo de 3 s. Al terminar el turno vuelve a la configuración de pasajero.
  3. La solicitud de permiso es compartida: si varias pantallas la piden a la vez, se hace una sola.
  4. Al volver a la app desde los ajustes del teléfono, se reintenta solo si faltaba el GPS o el permiso.

### 3.5. Servicio de Auditoría y Diagnóstico de Turnos (`SessionLogService`)
* **El Problema:** Cuando los choferes experimentan problemas en terreno ("no me agarró el GPS", "se me pegó la app"), no había cómo saber qué ocurrió técnicamente.
* **La Solución (`lib/services/session_log_service.dart`):**
  1. Registra eventos por turno: `SHIFT_START`, `SHIFT_END`, `GPS_LOST`, `NETWORK_LOST`, `NETWORK_FAIL`, `STATE_CHANGED` y `ROUTE_CHANGED`.
  2. Las fallas repetidas se agrupan en un solo evento con contador (`repeticiones`) y cada turno tiene un tope de 300 eventos: sin eso, un turno largo sin señal superaba el máximo de 1 MiB de un documento de Firestore y no se podía subir nunca.
  3. El turno en curso se guarda en el teléfono (`SharedPreferences`). Si la app se cierra a mitad del turno, **al siguiente arranque se recupera** y se sube marcado `interrumpida: true`.
  4. Se sube en un solo documento a `garitas/{garitaId}/auditoria_turnos/{sessionId}` al terminar el turno. Sin señal no se espera al servidor: queda en la cola local y se reintenta al abrir la app, al iniciar sesión y al terminar otro turno.
  5. Cada documento lleva `uid`, patente, garita, recorrido, versión de la app y plataforma.

### 3.6. Sistema de Actualización In-App OTA (Sin Google Play Store comercial)
* **El Problema:** Enseñar a 20 colectiveros a buscar archivos APK en WhatsApp o en carpetas de descargas cada vez que corregimos un bug era inviable.
* **La Solución:**
  1. `AppUpdateService` (`lib/services/app_update_service.dart`) y `AppUpdateDialog` (`lib/widgets/app_update_dialog.dart`) consultan `config/app_version` en Firestore.
  2. La versión instalada se lee **del propio APK** (`lib/config/app_version.dart`, con `package_info_plus`). Antes estaba escrita a mano en cuatro lugares que no coincidían.
  3. Si `versionCode` remoto > instalado, se ofrece la actualización. Es **obligatoria** si el documento lo marca (`esObligatoria`) o si la versión instalada es menor que `minRequiredVersionCode`; una obligatoria sin enlace no bloquea la app.
  4. Sólo se abren enlaces `https`.
  5. En `PreferencesScreen` está el botón manual **"Buscar actualizaciones"**.
  6. `scripts/seed_app_version.js` publica la versión leyendo `pubspec.yaml` (ver §8).

### 3.7. Consola Multi-Garita para Transportes Serrano
* **El Problema:** Serrano tiene 3 terminales físicos en la comuna (Garita Cumming, Garita Las Rosas y Garita Belloto 2000). El administrador necesita poder ver toda la flota o filtrar por terminal.
* **La Solución (`lib/screens/admin/flota_screen.dart`):**
  1. Los chips del filtro se arman con la colección `garitas` de Firestore (antes eran ids y nombres escritos a mano). Arranca en la garita del administrador; "Todas las garitas" muestra la flota completa.
  2. Al tocar una unidad se centra la cámara y se dibuja el recorrido que el chofer informó estar cubriendo.
  3. Mientras la pestaña no está a la vista no se redibuja con cada movimiento de la flota.

### 3.8. Rediseño Estético: Amarillo Cálido Anaranjado de Colectivo Chileno
* **La Solución:** semilla de marca `kColeTotalSeed = Color(0xFFE58A00)` en `lib/theme/app_colors.dart`. Los colores de semaforización de capacidad (`disponible`: verde, `medioLleno`: ámbar, `lleno`: rojo) se mantienen intactos, ahora centralizados en `AppStatusColors.forEstado`.

### 3.9. Elección del Recorrido por el Chofer
* **El Problema:** El modelo y la telemetría ya tenían `recorridoId`, pero ninguna pantalla permitía elegirlo: el "toca un colectivo y se ilumina su línea" del mapa nunca se activaba.
* **La Solución:** `TurnoScreen` tiene un selector con las líneas activas de la garita del chofer. La elección se recuerda entre turnos (`SharedPreferences`), se puede cambiar en pleno turno y se publica en la telemetría y en la auditoría (`ROUTE_CHANGED`).

### 3.10. Operación sin Señal
* Las escrituras de Firebase sólo se confirman cuando responde el servidor. Antes, sin señal, "Terminar turno", "Cerrar sesión" y los guardados del administrador quedaban girando indefinidamente.
* Ahora pasan por `confirmOrQueue` (`lib/services/firestore_writes.dart`): si no hay confirmación en unos segundos, la escritura queda en la cola local del SDK, la pantalla sigue y se avisa "Guardado sin conexión: se sincronizará al recuperar la señal".

### 3.11. Ruta a Pie Real
* Antes la ruta "a pie" se pedía con perfiles **de auto** y se mostraba el tiempo en auto: un trayecto de 640 m y 9 minutos caminando aparecía como 1,1 km y 2 minutos.
* Ahora `RouteService` usa OpenRouteService `foot-walking` (si hay clave), luego el servidor peatonal de OSRM de FOSSGIS y, como último recurso, el de autos con el tiempo recalculado a paso de peatón (1,3 m/s).
* La ruta parte de la posición **actual**, no del primer punto GPS de la sesión.

---

## 🗂️ 4. Mapa de Archivos Clave del Repositorio

```
lib/
├── config/
│   ├── app_version.dart           <-- Versión instalada, leída del APK
│   └── map_config.dart            <-- MapTiler 256 px + {r}, respaldo CARTO/Esri
├── data/
│   └── quilpue_pois.dart          <-- Catálogo de 26 hitos urbanos de Quilpué
├── models/
│   ├── app_user.dart              <-- Roles: invitado, colectivero, administrador
│   ├── colectivo_activo.dart      <-- Telemetría, presencia, antigüedad (45 s / 180 s)
│   ├── garita.dart                <-- Entidad terminal y CodigoAcceso
│   ├── place_result.dart          <-- Resultado del buscador
│   └── recorrido.dart             <-- Trazados de líneas y paraderos asociados
├── screens/
│   ├── admin/flota_screen.dart    <-- Consola multi-garita
│   ├── driver/turno_screen.dart   <-- Turno, recorrido y capacidad
│   ├── main_screen.dart           <-- Navegación principal y chequeo OTA
│   ├── map_screen.dart            <-- Mapa con capas que escuchan sus propios datos
│   └── preferences_screen.dart    <-- Tema, estilo de mapa y "Buscar actualizaciones"
├── services/
│   ├── app_update_service.dart    <-- Comparador de versiones OTA contra Firestore
│   ├── auth_service.dart          <-- Patente/correo, perfil escuchado en vivo
│   ├── firebase_telemetria_service.dart <-- Presencia + lectura compartida de la flota
│   ├── firestore_writes.dart      <-- confirmOrQueue: escrituras que no se cuelgan sin red
│   ├── geocoding_service.dart     <-- Motor híbrido POIs + MapTiler + Photon
│   ├── location_service.dart      <-- Único dueño del GPS (modo pasajero / modo turno)
│   ├── session_log_service.dart   <-- Auditoría de turnos con recuperación tras cierre
│   └── turno_service.dart         <-- Control de jornada del colectivero
├── utils/
│   └── text_search.dart           <-- Búsqueda sin tildes ni orden de palabras
└── widgets/
    ├── app_tile_layer.dart        <-- Capa de teselas común a los tres mapas
    ├── app_update_dialog.dart     <-- Diálogo emergente de actualización
    └── map_search_bar.dart        <-- Barra de búsqueda con iconos de POIs
public/
├── index.html                     <-- Portal de bienvenida y descarga móvil
└── afiche.html                    <-- Afiche imprimible en A4 con QR para la garita
scripts/
├── lib/firebase_rest.js           <-- Credenciales de Firebase CLI + REST de Firestore
├── apply_recorridos_geometries.js <-- Recalcula y guarda el trazado de cada línea
├── backup_coletotal.js            <-- Respaldo JSON/GeoJSON (con paginación y auditoría)
├── seed_app_version.js            <-- Publica la versión de pubspec.yaml para la OTA
└── seed_dummy_data.js             <-- Datos de prueba (códigos y clave por variables de entorno)
```

---

## 🧪 5. Suite de Pruebas y Estado de Verificación

`flutter analyze` sin observaciones y **134 pruebas automatizadas aprobadas**, sin red ni Firebase:
- Roles, destinos y patentes (`roles_test.dart`).
- Planificador de paraderos y cliente OSRM: troceo de líneas largas, codificación de polilíneas (`planner_test.dart`).
- Ruta a pie: perfil peatonal, tiempo a paso de peatón, respuestas tardías (`route_service_test.dart`).
- GPS único: una sola solicitud de permiso, servicio en primer plano en el turno (`location_service_test.dart`).
- Telemetría: nodos ilegibles, antigüedad contra la hora del servidor, "sin señal" (`telemetria_test.dart`).
- Contrato con las reglas: lo que escribe el cliente cabe en `database.rules.json` y `firestore.rules` (`rules_contract_test.dart`).
- Auditoría de turnos: agrupación, tope, recuperación tras cierre (`session_log_test.dart`).
- Escrituras sin red (`firestore_writes_test.dart`), búsqueda sin tildes (`text_search_test.dart`), POIs y geocodificación con HTTP simulado (`quilpue_pois_test.dart`).
- Persistencia de paraderos e historial (`stops_test.dart`), actualizador (`app_update_test.dart`), tema y Preferencias (`widget_test.dart`).

---

## 🔒 6. Seguridad y Reglas (`firestore.rules`, `database.rules.json`)

1. **`config`:** lectura pública, escritura sólo desde la consola o los scripts.
2. **`garitas/{garitaId}/auditoria_turnos/{sessionId}`:** cada chofer crea sólo sus propios turnos (`uid` igual al de la sesión), en su propia garita y con a lo más 500 eventos. Sólo el administrador de esa garita los lee. Son inmutables: no hay `update` ni `delete`.
3. **`usuarios`:** el administrador sólo puede listar los usuarios de **su** garita, y sólo si está activo.
4. **`paraderos` y `recorridos`:** sólo el administrador de la garita escribe, con tipos y largos validados en cada `create` y `update`.
5. **`colectivos_activos` (Realtime Database):** cada chofer escribe sólo su nodo, con campos y tipos validados; `ts` no puede ser futuro.
6. **Códigos y contraseñas:** no se guardan en el repositorio. Los códigos de garita que estuvieron versionados en la rama `Proto` deben **rotarse** en la consola (el historial de git los conserva).

---

## ⚡ 7. Distribución del APK

1. **Detección in-app:** el diálogo `AppUpdateDialog` se abre al arrancar cuando hay una versión mayor publicada, o al tocar *"Buscar actualizaciones"* en Preferencias.
2. **Descarga directa:** el botón *"Actualizar ahora"* abre la URL `https` del APK publicada en `config/app_version`. Se recomienda alojar los APK en GitHub Releases o en Firebase Hosting, en vez de un servicio anónimo de archivos.
3. **Firma:** todas las versiones deben firmarse con la misma llave (`android/key.properties`, ver README); si no, Android no instala la nueva encima de la anterior.

---

## 💡 8. Recomendaciones para Tomás y Próximos Pasos de Trabajo

1. **Si vas a tocar la interfaz:** respeta la semilla `kColeTotalSeed = Color(0xFFE58A00)` y no reemplaces los colores de semaforización de `AppStatusColors` (verde/ámbar/rojo). Todo texto visible va en `lib/l10n/app_es.arb`.
2. **Si vas a publicar una nueva versión de prueba:**
   - Sube el número en `pubspec.yaml` (ej. `0.4.4+5`). No hay que tocar nada más en el código.
   - Compila con la llave del proyecto: `flutter build apk --release`.
   - Sube el APK y publica el aviso: `APK_URL=https://... CHANGELOG="..." node scripts/seed_app_version.js`.
3. **Si cambias lo que se escribe en Firebase:** actualiza las reglas en el mismo cambio; `rules_contract_test.dart` falla si no coinciden. Despliega con `firebase deploy --only firestore:rules,database`.
4. **Pendiente:** ETA (RF-08), sentido de marcha de los recorridos, solicitud del permiso de notificaciones en Android 13+.
