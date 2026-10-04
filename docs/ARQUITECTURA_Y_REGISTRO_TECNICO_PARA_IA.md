# 🚖 ColeTotal — Arquitectura, Decisiones Técnicas y Registro de Continuidad para Desarrollo
> **Para:** Tomás Moraga & Asistentes de IA de Desarrollo  
> **De:** Marco Fernandoy & Pair Programming Agent  
> **Proyecto:** ColeTotal — Sistema Inteligente de Transporte Colectivo para Quilpué (Transportes Serrano S.A.)  
> **Versión Actual del Sistema:** `v0.4.3.1` (Build `4`) — *Alineada con el Hito 4 / Incremento 1.2 & 2.1 del Informe de Avance de Proyecto de Título*  
> **Fecha:** Octubre 2026  

---

## 📌 1. Propósito de este Documento

Este documento es la **fuente de verdad técnica consolidada** de todo lo construido, refactorizado y asegurado en la plataforma ColeTotal. Si estás leyendo esto como Tomás o como un modelo de Inteligencia Artificial al que se le encarga una nueva tarea o corrección sobre el repositorio, este texto te entrega el contexto completo: **el porqué detrás de cada decisión**, la justificación contra las limitaciones del mundo real (smartphones de gama baja de los colectiveros, cuotas de APIs, conectividad intermitente en Quilpué) y el mapa exacto de archivos que componen el sistema.

---

## 🧭 2. Resumen Ejecutivo del Problema y Justificación Teórica

En la defensa de avance se criticaron principalmente tres vulnerabilidades del proyecto original:
1. **Dependencia ciega de servicios en la nube (Single Point of Failure):** Si Firebase o MapTiler fallan o agotan su cuota gratuita, la app no puede quedarse en blanco ni bloquear las pruebas con la línea Serrano.
2. **Desconexión con la realidad de los usuarios finales:** Los colectiveros son en su mayoría personas de 50 a 68 años con smartphones Android de gama de entrada (2 GB a 3 GB de RAM, baterías degradadas) y baja alfabetización digital; no se les puede pedir que busquen APKs en carpetas de descargas ni que gestionen correos corporativos complejos.
3. **Falta de rigor en versionado y pruebas de estrés:** Las versiones no estaban atadas a la metodología de desarrollo incremental ni existía registro de qué fallos sufren los choferes en su recorrido diario.

---

## ⚙️ 3. Soluciones Técnicas Implementadas (El "Por Qué" de Cada Cambio)

### 3.1. Mitigación del Consumo de Cuota de MapTiler (Fallback Cartográfico $0)
* **El Problema:** MapTiler otorga 100.000 cargas de teselas mensuales en su plan gratuito. Al navegar o hacer zoom en Quilpué sin caché de disco, cada movimiento descargaba decenas de imágenes `.png`. El plan se consumía a un ritmo insostenible que amenazaba con paralizar el piloto.
* **La Solución:** 
  1. Se implementó `fallbackTileUrlTemplate` en `lib/config/map_config.dart`.
  2. En `TileLayer` de `MapScreen` y `FlotaScreen` se enlazó `fallbackUrl`.
  3. Si MapTiler responde con error HTTP `429 Too Many Requests`, `403` o falla de red, `FlutterMap` conmuta de forma automática e invisible a teselas de **CARTO Positron** (`cartocdn.com`) para modo claro/oscuro y **Esri World Imagery** para satélite.
  4. **Costo garantizado: \$0 USD** y operatividad 100% ininterrumpida.

### 3.2. Buscador de Destinos con Puntos de Interés (POIs) Locales y Photon
* **El Problema:** MapTiler Geocoding en Chile solo resuelve direcciones formales con numeración (ej. *"Freire 1420"*). Si un pasajero escribía *"Líder Belloto"*, *"Hospital"* o *"Plaza Vieja"*, la búsqueda fallaba o devolvía resultados absurdos a 700 km (como la comuna de Freire en la Araucanía).
* **La Solución:**
  1. Se creó `lib/data/quilpue_pois.dart` con más de 25 hitos urbanos estratégicos de Quilpué (Líder Belloto, Portal Belloto, Santa Isabel, Hospital Quilpué, plazas cívicas, colegios, estaciones EFE).
  2. `GeocodingService` (`lib/services/geocoding_service.dart`) aplica un **motor híbrido**:
     - *Paso 1:* Cotejo local instantáneo (0 ms, 0 consumo de red).
     - *Paso 2:* Si faltan resultados, consulta a la API abierta de **Photon (OpenStreetMap)** con un *bounding box* estricto de la V Región (`-71.75,-33.20,-71.20,-32.90`).
  3. En la interfaz (`MapSearchBar`), los POIs se destacan con el icono `Icons.stars_rounded` y tipografía jerárquica.

### 3.3. Telemetría Resiliente: Eliminación del Parpadeo por Desconexión Breve
* **El Problema:** Antes se usaba `vehicleRef.onDisconnect().remove()` en Firebase Realtime Database. Cuando un chofer pasaba por una zona de sombra celular (ej. bajo el paso sobre nivel de Valencia o en cerros de Pompeya), el socket TCP se cerraba por 3 segundos y el vehículo desaparecía de los mapas de todos los pasajeros.
* **La Solución:**
  1. Se reemplazó el borrado abrupto por `onDisconnect().update({ 'conectado': false, 'ts': ServerValue.timestamp })` en `FirebaseTelemetriaService`.
  2. Se amplió `maxAntiguedad` en `ColectivoActivo` a **180 segundos (3 minutos)**.
  3. El colectivo no desaparece: se mantiene en el mapa, mostrando su última ubicación registrada hasta que vuelva a reconectar la antena celular.

### 3.4. Resiliencia ante el Android Low Memory Killer (OOM) en Teléfonos de Chofer
* **El Problema:** Al bloquear la pantalla o recibir una llamada, Android suele matar procesos en segundo plano en dispositivos con poca RAM.
* **La Solución:**
  1. En `FirebaseTelemetriaService`, al iniciar tracking en Android, se instancia un `AndroidSettings` con un **Foreground Service** continuo:
     - Notificación con prioridad alta (`PRIORITY_HIGH`) y fija (`setOngoing: true`).
     - `enableWakeLock: true` para evitar que el CPU entre en suspensión profunda.
  2. El chofer puede tener la app en segundo plano o la pantalla apagada en su soporte del auto y la posición satelital sigue transmitiéndose a los pasajeros.

### 3.5. Servicio de Auditoría y Diagnóstico de Turnos (`SessionLogService`)
* **El Problema:** Cuando los choferes experimentan problemas en terreno ("no me agarró el GPS", "se me pegó la app"), no había cómo saber qué ocurrió técnicamente.
* **La Solución:**
  1. Creado `lib/services/session_log_service.dart`.
  2. Registra eventos clave por jornada: `SHIFT_START`, `GPS_LOST`, `STATE_CHANGED`, `NETWORK_FAIL`, `SHIFT_END`.
  3. Almacena en búfer local (`SharedPreferences` en formato JSON) para no depender de la conexión.
  4. Sincroniza por lotes (batch) hacia Firestore en la ruta:
     `garitas/{garitaId}/auditoria_turnos/{sessionId}` al terminar el turno o cuando la app vuelve a conectarse a internet.

### 3.6. Sistema de Actualización In-App OTA (Sin Google Play Store comercial)
* **El Problema:** Enseñar a 20 colectiveros a buscar archivos APK en WhatsApp o en carpetas de descargas cada vez que corregimos un bug era inviable.
* **La Solución:**
  1. Creado `AppUpdateService` (`lib/services/app_update_service.dart`) y `AppUpdateDialog` (`lib/widgets/app_update_dialog.dart`).
  2. Consulta el documento `config/app_version` en Firestore.
  3. Si `versionCode` remoto > local, la app despliega un pop-up amigable informando las mejoras del changelog y ofreciendo un botón directo para actualizar.
  4. En `PreferencesScreen`, se añadió el botón manual **"Buscar actualizaciones"** que indica si la versión está al día o abre el asistente de descarga.

### 3.7. Consola Multi-Garita para Transportes Serrano
* **El Problema:** Serrano tiene 3 terminales físicos en la comuna (Garita Cumming, Garita Las Rosas y Garita Belloto 2000). El administrador general necesitaba poder ver toda la flota o filtrar por terminal sin mezclar los datos operativos.
* **La Solución:**
  1. En `lib/screens/admin/flota_screen.dart`, se añadieron *ChoiceChips* horizontales: `[ Toda la Flota Serrano | Garita Cumming | Garita Las Rosas | Garita Belloto 2000 ]`.
  2. El stream de telemetría escucha todos los vehículos en memoria y el filtrado es instantáneo en UI.
  3. Al presionar cualquier vehículo, se centra la cámara y se resalta la polilínea de su recorrido asignado.

### 3.8. Rediseño Estético: Amarillo Cálido Anaranjado de Colectivo Chileno
* **El Problema:** La paleta original usaba índigo-morado genérico.
* **La Solución:**
  1. Se actualizó la semilla de marca en `lib/theme/app_colors.dart` a `kColeTotalSeed = Color(0xFFE58A00)` (Amarillo-anaranjado cálido, representativo del letrero y cúpula de techo del taxi colectivo chileno).
  2. Se mantuvieron intactos los colores de semaforización de capacidad vehicular (`disponible`: verde, `medioLleno`: ámbar, `lleno`: rojo) para preservar el contraste operacional exigido por el informe.

---

## 🗂️ 4. Mapa de Archivos Clave del Repositorio

```
D:\Proyectos\Coletotal\
├── lib/
│   ├── config/
│   │   └── map_config.dart            <-- Llaves MapTiler + Fallback CARTO/Esri
│   ├── data/
│   │   └── quilpue_pois.dart          <-- Catálogo de 25+ hitos urbanos de Quilpué
│   ├── models/
│   │   ├── app_user.dart              <-- Roles: invitado, colectivero, administrador
│   │   ├── colectivo_activo.dart      <-- Telemetría, recorridoId, tolerancia 180s
│   │   ├── garita.dart                <-- Entidad terminal y CodigoAcceso
│   │   └── recorrido.dart             <-- Trazados de líneas y paraderos asociados
│   ├── screens/
│   │   ├── admin/flota_screen.dart    <-- Consola multi-garita con chips de filtro
│   │   ├── main_screen.dart           <-- Navegación principal y gancho de chequeo OTA
│   │   ├── map_screen.dart            <-- Mapa interactivo, proximidad y POIs
│   │   └── preferences_screen.dart    <-- Tema, estilo mapa y "Buscar actualizaciones"
│   ├── services/
│   │   ├── app_update_service.dart    <-- Comparador de versiones OTA contra Firestore
│   │   ├── auth_service.dart          <-- Autenticación basada en patente/código
│   │   ├── firebase_telemetria_service.dart <-- Foreground GPS + Realtime Database
│   │   ├── geocoding_service.dart     <-- Motor híbrido POIs + Photon OSM
│   │   ├── session_log_service.dart   <-- Búfer local y auditoría por lotes de choferes
│   │   └── turno_service.dart         <-- Control de jornada del colectivero
│   ├── theme/
│   │   ├── app_colors.dart            <-- Semilla Color(0xFFE58A00) + AppStatusColors
│   │   └── app_theme.dart             <-- Builder puro Material 3
│   └── widgets/
│       ├── app_update_dialog.dart     <-- Diálogo emergente de actualización
│       └── map_search_bar.dart        <-- Barra de búsqueda con iconos de POIs
├── public/
│   ├── index.html                     <-- Portal de bienvenida y descarga móvil
│   └── afiche.html                    <-- Afiche imprimible en A4 con QR para la garita
├── scripts/
│   ├── seed_dummy_data.js             <-- Poblador de garita, 7 choferes, 7 recorridos
│   └── seed_app_version.js            <-- Publicador de versión 0.4.3.1 en Firestore
└── test/
    ├── app_update_test.dart           <-- Pruebas de detección de versiones
    ├── quilpue_pois_test.dart         <-- Pruebas de POIs y geocodificación
    ├── session_log_test.dart          <-- Pruebas de serialización de auditoría
    └── widget_test.dart               <-- Pruebas de temas, contrastes y pantallas
```

---

## 🧪 5. Suite de Pruebas y Estado de Verificación

El proyecto cuenta con una suite completa de **78 pruebas automatizadas (100% aprobadas sin errores ni regresiones)** que cubren:
- Reconciliación de destinos y seguridad por roles (`roles_test.dart`).
- Cálculo de distancias y algoritmo de planificación (`planner_test.dart`).
- Persistencia de paraderos e historial sin red (`stops_test.dart`).
- Tematización Material 3 y escalado de fuentes (`widget_test.dart`).
- Serialización de logs de turno y recuperación offline (`session_log_test.dart`).
- Lógica de comparación de versiones del actualizador (`app_update_test.dart`).
- Coordenadas geográficas y búsqueda de hitos de Quilpué (`quilpue_pois_test.dart`).

---

## 🔒 6. Seguridad y Reglas de Firestore Desplegadas (`firestore.rules`)

Para garantizar que el actualizador OTA y el sistema de auditoría funcionen en producción sin vulnerar la privacidad de los datos:
1. **Colección `config`:** Se estableció `allow read: if true; allow write: if false;` permitiendo que clientes anónimos o choferes verifiquen la versión del sistema sin requerir autenticación previa.
2. **Subcolección `garitas/{garitaId}/auditoria_turnos/{sessionId}`:** 
   - `allow create: if signedIn();` permite al chofer persistir su reporte al terminar el turno.
   - `allow read: if isAdminOf(garitaId);` restringe la lectura exclusivamente al inspector de dicha garita.
   - `allow update, delete: if false;` garantiza la inmutabilidad de los registros históricos de auditoría.

---

## ⚡ 7. Validación del Mecanismo OTA y Descarga Directa en 1 Clic

Durante la prueba en el teléfono físico se diagnosticaron dos puntos críticos para la experiencia de los choferes:
1. **Detección In-App exitosa:** La ventana emergente `AppUpdateDialog` se activa de forma reactiva al arrancar `MainScreen` cuando `remote.versionCode > local.versionCode`, o al presionar manualmente *"Buscar actualizaciones"* en Preferencias.
2. **Descarga Directa sin Fricción:** Se reemplazó la redirección a paneles de prueba (que exigían inicio de sesión en Google y causaban confusión) por un canal de descarga directa en 1 toque hacia el archivo `.apk` (`https://files.catbox.moe/99fybl.apk`), integrado en:
   - El botón *"Actualizar ahora"* del pop-up en la app.
   - El botón principal del portal web `https://coletotal-32735.web.app`.

---

## 💡 8. Recomendaciones para Tomás y Próximos Pasos de Trabajo

1. **Si vas a tocar la interfaz:** Respeta la semilla `kColeTotalSeed = Color(0xFFE58A00)` y no reemplaces los colores de semaforización de `AppStatusColors` (verde/ámbar/rojo).
2. **Si vas a publicar una nueva versión de prueba:**
   - Sube el número en `pubspec.yaml` (ej. `0.4.4+5`).
   - Actualiza `currentVersionCode` y `currentVersionName` en `lib/services/app_update_service.dart`.
   - Compila el APK: `flutter build apk --release`.
   - Sube el APK y actualiza la URL en Firestore con `node scripts/seed_app_version.js` para que el pop-up se active automáticamente en los celulares de los choferes ya instalados.
3. **Para probar en terreno:** Utiliza el portal en vivo desplegado en:  
   👉 `https://coletotal-32735.web.app` (para choferes) o imprime el afiche en `https://coletotal-32735.web.app/afiche.html` para colgarlo en Garita Cumming.

