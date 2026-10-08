# Plan de Pruebas, Metodología de Versiones y Arquitectura Operacional — ColeTotal

> **Proyecto:** ColeTotal — Sistema de Gestión y Telemetría para Taxis Colectivos  
> **Comuna de Operación Piloto:** Quilpué, Región de Valparaíso  
> **Línea de Transporte:** Transportes Serrano  
> **Fecha de Documentación:** Octubre 2026  

> [!NOTE]
> **Estado de implementación (revisado el 5 de octubre de 2026).** Este documento es un plan: mezcla lo que ya está construido con lo que se propone. Lo que todavía no existe en el código va marcado **(propuesto, pendiente)**. La descripción de lo implementado, con sus archivos, está en `ARQUITECTURA_Y_REGISTRO_TECNICO_PARA_IA.md`.

---

## 1. Esquema de Versionado SemVer alineado al Informe de Título

De acuerdo con el documento *Informe_ColeTotal_Moraga_Fernandoy.docx*, el proyecto se rige por un **Ciclo de Vida Iterativo e Incremental (I&I)** compuesto por 4 fases metodológicas y 3 incrementos técnicos (§5.1, §5.2 y §5.3).

Para dotar al desarrollo de trazabilidad académica y formalidad ante la comisión evaluadora, se adopta un versionado semántico formal (`vMayor.Menor.Parche+Build`) sincronizado con los hitos del informe:

```mermaid
flowchart LR
    F1["Fase 1-3\nAnálisis y Diseño\n(v0.1 - v0.3)"] --> F4["Fase 4 / Inc. 1\nNúcleo Técnico Base\n(v0.4.0)"]
    F4 --> INC2["Incremento 2\nTracking y Rutas Viales\n(v0.4.1 - v0.4.2)"]
    INC2 --> INC3["Incremento 3\nResiliencia y Piloto Serrano\n(v0.5.0 - v0.6.0)"]
    INC3 --> REL["Release Final\nDefensa de Título\n(v1.0.0)"]
```

### Tabla de Equivalencia: Hitos vs. Versiones de Software

| Versión | Hito Metodológico Asociado | Alcance e Hitos Funcionales | Estado |
| :--- | :--- | :--- | :---: |
| **`v0.1.0`** | Fase 1: Análisis del Dominio | Levantamiento de requisitos D.S. 212, entrevistas garitas Serrano. | Completado |
| **`v0.2.0`** | Fase 2: Diseño de Arquitectura | Modelado NoSQL, esquemas de Firebase y definición de stack. | Completado |
| **`v0.3.0`** | Fase 3: Prototipado UX/UI | Prototipos de alta fidelidad Figma, flujos de navegación. | Completado |
| **`v0.4.0`** | Fase 4 / Incremento 1: Núcleo Base | Mapa interactivo `flutter_map` (hoy MapLibre), geolocalización `geolocator`, marcadores reactivos. | Completado |
| **`v0.4.1`** | Incremento 1.1: Rutas de Quilpué | Geometrías viales reales OSRM en Firestore, 20 paraderos, sentidos de calle. | Completado |
| **`v0.4.2`** | Incremento 1.2: Respaldo y Seguridad | Reglas de Firestore/RTDB, scripts de backup JSON/GeoJSON locales. | Completado |
| **`v0.4.3`** | Incremento 2.1: Estabilidad Piloto *(Actual)* | OTA Updater, optimización de cuota de mapas, búsqueda POI, Foreground Service. | **En curso** |
| **`v0.5.0`** | Incremento 2.2: Despliegue Garita | Validación en terreno con choferes e inspectores de Transportes Serrano (Garita Cumming). | Planificado |
| **`v0.6.0`** | Incremento 3.1: Resiliencia Offline | Almacenamiento local SQLite/Caché, mitigación de túneles y cerros sin cobertura. | Planificado |
| **`v0.7.0`** | Incremento 3.2: Multi-Garita Serrano | Panel Super-Admin consolidado (Cumming, Las Rosas, Belloto 2000). | Planificado |
| **`v1.0.0`** | Entrega y Defensa de Título | Versión productiva final validada, manual de usuario y cierre académico. | Hito Final |

> [!NOTE]
> La versión vigente es **`0.4.3+4`** (la de `pubspec.yaml`, que la app lee del propio APK).

---

## 2. Plan de Pruebas de Estrés Significativas (Stress Testing)

Para demostrar a la comisión que ColeTotal no es una maqueta frágil, se define un protocolo formal de pruebas de estrés bajo 4 dimensiones críticas:

```mermaid
mindmap
  root((Pruebas de Estrés))
    Telemetría RTDB
      50 choferes concurrentes
      Frecuencia 3 seg
      Medición de latencia y throughput
    Consultas Firestore
      200 lecturas concurrentes
      Límites de cuotas y reglas NoSQL
      Carga inicial de paraderos
    Cliente Móvil Flutter
      Consumo de RAM con 50 marcadores
      Frame rate continuo 60 fps
      Caché de texturas de mapa
    Resiliencia de Red
      Network flapping cada 10 seg
      Pérdida en cerros de Quilpué
      Reconexión sin pérdida de turno
```

### 2.1. Protocolo de Pruebas y Métricas de Aceptación

| Código | Prueba | Carga Simulada | Métrica de Éxito | Herramienta |
| :--- | :--- | :--- | :--- | :--- |
| **ST-01** | Estrés de Telemetría RTDB | 50 choferes transmitiendo GPS cada 3 s durante 30 min. | Latencia < 500 ms; 0 errores de escritura; costo RTDB < \$0.05. | Script Node.js con emulador de socket RTDB. |
| **ST-02** | Concurrencia de Pasajeros | 200 clientes solicitando paraderos y recorridos en 5 segundos. | 100% respuestas exitosas; tiempo de carga < 1.2 s. | Firebase Load Runner / K6. |
| **ST-03** | Consumo de RAM y Render Móvil | Mapa abierto con 50 colectivos animados + 9 polilíneas + 20 paraderos. | Consumo RAM < 180 MB en Android; FPS > 50 sostenido. | Flutter DevTools (Memory Profiler & Performance). |
| **ST-04** | Simulación de Caída de Cobertura | Teléfono del chofer alternando 15 s conectado / 45 s sin señal por 1 hora. | Ningún crash; reconexión automática; el turno persiste activo. | Modo avión programado con ADB. |

---

## 3. Plan de Supervisión en Garita y Sistema de Logs por Sesión

Durante la prueba piloto con los trabajadores de Transportes Serrano, los inspectores y choferes no reportarán errores técnicos de manera estructurada. Por ello, el sistema debe recolectar telemetría y diagnósticos de manera autónoma.

### 3.1. Arquitectura de Logs por Sesión (Local First + Batching Diario)

Para no saturar los datos móviles de los colectiveros ni generar cobros innecesarios en Firebase:

1. **Almacenamiento Local Continuo:** el turno en curso se guarda en el teléfono (`SharedPreferences`, no archivos `.jsonl`).
2. **Eventos Registrados** (implementados: `SHIFT_START`, `SHIFT_END`, `GPS_LOST`, `NETWORK_LOST`, `NETWORK_FAIL`, `STATE_CHANGED`, `ROUTE_CHANGED`):
   - `APP_START` con versión del SO, fabricante, modelo y RAM: **(propuesto, pendiente)**.
   - `SHIFT_START`: patente, garita, recorrido, versión de la app y plataforma. El nivel de batería: **(propuesto, pendiente)**.
   - `GPS_LOST`: errores del GPS durante el turno. `GPS_SIGNAL_RESTORED`: **(propuesto, pendiente)**.
   - `LOW_MEMORY_ALERT`: **(propuesto, pendiente)**.
   - `NETWORK_LOST` / `NETWORK_FAIL`: pérdida de conexión con Realtime Database y escrituras fallidas. Las repeticiones se agrupan en un solo evento con contador, con un tope de 300 eventos por turno.
   - `SHIFT_END`: duración del turno y eventos acumulados. Los kilómetros recorridos: **(propuesto, pendiente)**.
3. **Sincronización por Tandas (Batching):**
   - El log se envía al servidor al cerrar el turno. Si no hay señal, queda en cola y se reintenta al abrir la app, al iniciar sesión o al terminar otro turno (no se detecta la red WiFi).
   - Se almacena en la colección `garitas/{garitaId}/auditoria_turnos/{sessionId}`.
   - Si la app se cierra a mitad del turno, el turno se recupera en el siguiente inicio y se sube marcado `interrumpida: true`.
4. **Crash Reporting en Tiempo Real:** Integración con **Firebase Crashlytics** **(propuesto, pendiente)**.

---

## 4. Mapa Base Offline (reemplazó a MapTiler)

### 4.1. Antecedente: el consumo de cuota de MapTiler
El plan gratuito de MapTiler incluía 100.000 teselas mensuales, que se consumían a un ritmo insostenible: cada paneo o zoom descargaba teselas por red, la plantilla de URL sin `{r}` hacía que flutter_map pidiera **cuatro teselas por casilla**, y cada búsqueda gastaba cuota de geocodificación. La auditoría del 5 de octubre corrigió la plantilla y agregó respaldo a CARTO/Esri, pero el problema de fondo seguía: el mapa dependía de una clave (escrita en el código), de una cuota y de tener señal. En octubre de 2026 MapTiler se reemplazó por un mapa base que viaja dentro del APK.

### 4.2. Solución: teselas de OpenStreetMap dentro del APK (costo $0, sin clave, sin red)

```mermaid
flowchart TD
    Req["Tesela (Z, X, Y)\nMapLibre, con la GPU"] --> Estilo{"¿Vista satelital?"}
    Estilo -- "No" --> General["Vista general de chile.pmtiles (z0–10)\nabajo, agrandada al acercarse"]
    General --> Detalle{"¿Está en valparaiso.pmtiles?\n(Región de Valparaíso, z11–15)"}
    Detalle -- "Sí" --> Calles["Encima, todas las calles y sus nombres\n(desde el teléfono, 0 ms de red)"]
    Detalle -- "No" --> Queda["Se ve la general,\ncon sus nombres"]
    Estilo -- "Sí" --> Esri["Foto aérea de Esri (requiere red)\n+ etiquetas offline encima"]
```

1. **Datos:** `assets/map/chile.pmtiles` (24 MB) y `assets/map/valparaiso.pmtiles` (35 MB), extraídos del build diario de OpenStreetMap de Protomaps con `scripts/mapa_base/build.js`. Al primer arranque se copian una vez a la carpeta de datos de la app y se leen por tramos.
2. **Dibujo:** MapLibre (`maplibre_gl`) lee los PMTiles directamente y dibuja con la GPU. Cada estilo tiene las dos fuentes: la general abajo y la de detalle sin fondo encima; dentro de la región, desde z11, los nombres los pone sólo el detalle. Sin íconos de comercios ni numeración de casas, para que se vean los nombres de las calles. El primer intento, `vector_map_tiles`, dibujaba cada tesela en Dart en el hilo principal y las teselas aparecían de a una en un Redmi Note 14.
3. **Búsqueda:** POIs locales, índice offline de unas 25 mil calles de la región y, sólo con red, Photon (ver §5).
4. **Sin señal** se pierde únicamente la foto aérea de la vista satelital (se ven las etiquetas) y la numeración de las direcciones.

### 4.3. Pruebas
* **Automatizadas:** `test/basemap_test.dart` lee las cabeceras reales de los PMTiles (zooms y límites contra `map_config.dart`) y revisa que cada estilo apunte a íconos, tipografías y fuentes que vienen en el APK; `test/basemap_service_test.dart` cubre la copia única al teléfono, las rutas `file://` de los estilos y el borrado de las cachés viejas; `test/app_map_test.dart`, los íconos de los marcadores y el halo del GPS en metros. Además `build.js` valida cada estilo contra la especificación de MapLibre y dibuja las miniaturas con MapLibre Native, el mismo motor de Android.
* **Manuales en un teléfono:**
  1. Modo avión, cerrar la app y volver a abrirla: los tres mapas (pasajero, flota, editor de paraderos) se dibujan y el buscador encuentra "Los Carrera" y "Líder".
  2. Alejarse hasta ver Chile entero y acercarse a Santiago y a Punta Arenas: hay mapa en todo el país, con menos detalle fuera de la región.
  3. Cambiar entre tema claro y oscuro con el mapa a la vista: se redibuja con el otro estilo.
  4. Vista satelital con y sin red: foto aérea con nombres de calles en blanco; sin red, sólo los nombres.
  5. Primer arranque tras instalar en el teléfono más lento disponible: medir cuánto tarda en aparecer el mapa (la copia de unos 60 MB) y comprobar que el segundo arranque es inmediato.
  6. Paneo y zoom continuos en Quilpué durante 5 minutos en ese mismo teléfono: sin tirones ni cierre por memoria.
  7. Tocar un colectivo, un paradero y la bandera del destino: abren su ficha (o el nombre del destino). Con TalkBack, cada marcador se anuncia con su descripción.
  8. Seguir al usuario (botón de centrar) mientras se camina: la cámara lo acompaña y deja de hacerlo al arrastrar el mapa.

---

## 5. Buscador de Destinos Inteligente con Puntos de Interés (POIs)

El geocodificador de MapTiler, que se usaba antes, sólo contenía calles formales en Chile y no resolvía búsquedas cotidianas como *"Líder Belloto"*, *"Hospital"*, *"Plaza Vieja"* o *"Colegio Aconcagua"*; además gastaba cuota y no funcionaba sin señal.

### 5.1. Solución: de lo local a la red

```mermaid
flowchart LR
    Input["Usuario escribe consulta\n(ej. 'lider')"] --> LocalCat{"¿Coincide con\nCatálogo POIs Quilpué?"}
    LocalCat -- "Sí (Prioridad 1)" --> ResPOI["POI inmediato\n(0 ms, sin red)"]
    LocalCat -- "Faltan resultados" --> Calles["Índice offline de calles\nde la Región de Valparaíso\n(sin red, la más cercana primero)"]
    Calles -- "Faltan resultados" --> ExtGeo["Photon / OSM, sólo con red\n(numeración, caja de la región)"]
```

1. **Catálogo Local de POIs de Quilpué (`lib/data/quilpue_pois.dart`):**
   - Catálogo incluido en la app con **26 puntos** de Quilpué (búsqueda sin tildes ni orden de palabras):
     - Supermercados: Líder Belloto, Santa Isabel Freire, Unimarc Blanco.
     - Salud: Hospital de Quilpué, CESFAM Aviador Acevedo, Policlínico Pompeya.
     - Educación: Colegio Aconcagua, Liceo Guillermo Gronemeyer, Duoc UC.
     - Hitos urbanos: Plaza de Armas, Plaza Vieja, Estaciones EFE (Quilpué, El Sol, Belloto).
   - Respuesta instantánea con un ícono destacado (`Icons.stars_rounded`). Íconos por tipo de lugar: **(propuesto, pendiente)**.
2. **Índice offline de calles (`lib/services/street_index.dart`):** unas 25 mil calles de la Región de Valparaíso con su comuna, generadas desde OpenStreetMap junto con el mapa base. Ordena por cercanía al usuario: "los carrera" encuentra primero la de Quilpué.
3. **Geocodificación remota:** sólo si aún faltan resultados, **Photon (OpenStreetMap)**, sin clave y acotado a la caja de la región. Aporta la numeración ("Freire 1234"), que el índice no tiene.

---

## 6. Arquitectura Multi-Garita y Llaves de Acceso (Transportes Serrano)

Transportes Serrano opera con múltiples terminales en la comuna (Garita Cumming, Las Rosas, Belloto 2000). El sistema debe reflejar esta estructura organizativa sin mezclar los datos operativos entre garitas, pero ofreciendo una consola unificada para la gerencia.

> **Estado:** lo implementado es una colección plana `garitas` y el campo `garitaId` en usuarios, paraderos y recorridos, con dos roles (`colectivero`, `administrador`). La jerarquía `empresas/…`, los roles `admin_garita` y `super_admin` y las llaves de acceso simplificadas de §6.3 son **(propuesto, pendiente)**. La consola de flota ya filtra por garita (§3.7 de la arquitectura).

### 6.1. Modelo de Jerarquía en Firestore **(propuesto, pendiente)**

```
empresas/transportes_serrano
  ├── garitas/garita_cumming
  │     ├── recorridos: [ Línea 101, Línea 102 ]
  │     ├── choferes: [ chofer_01, chofer_02 ]
  │     └── codigos_acceso: [ SR-CUM-91, SR-CUM-92 ]
  ├── garitas/garita_las_rosas
  │     ├── recorridos: [ Línea 103, Línea 104 ]
  │     └── choferes: [ chofer_03, chofer_04 ]
  └── garitas/garita_belloto2000
        ├── recorridos: [ Línea 105, Línea 107 ]
        └── choferes: [ chofer_05, chofer_06 ]
```

### 6.2. Roles y Control de Acceso

1. **Chofer (`rol: 'colectivero'`):**
   - Asociado a su `garitaId` respectiva y su patente (`idVehiculo`).
   - Sólo puede iniciar turnos en los recorridos que corresponden a su garita.
2. **Inspector de Garita (`rol: 'admin_garita'`):**
   - Administra exclusivamente los choferes, recorridos y turnos de su propio terminal (ej. Garita Cumming).
3. **Super Administrador / Dueño de Línea (`rol: 'super_admin'`):**
   - Posee `empresaId: 'transportes_serrano'` con vista global.
   - En su pantalla de control dispone de un selector: `[ Ver Toda la Flota | Cumming | Las Rosas | Belloto 2000 ]`.

### 6.3. Sistema de Llaves de Acceso Simplificado (Onboarding sin Fricción) **(propuesto, pendiente)**

Hoy el chofer se registra con su nombre, su patente, una contraseña y el código de garita.

Para choferes e inspectores con baja alfabetización digital:
1. El inspector presiona **"Crear Llave de Acceso"** en su panel y digita la patente (ej. `BXZR-88`).
2. La app genera un código simple de 6 caracteres (ej. `SR-4819`).
3. El chofer descarga ColeTotal, selecciona **"Soy Chofer"** e introduce únicamente ese código.
4. La app crea su sesión autenticada en Firebase bajo el correo virtual `bxzr88@coletotal.cl`, vinculando automáticamente su patente, su garita y sus permisos sin requerir correos electrónicos ni contraseñas complejas.

---

## 7. Telemetría Robusta en Terreno y Resiliencia ante Baja Memoria RAM

### 7.1. Filtrado de Visualización por Radio de Cercanía
Para no abrumar al pasajero con decenas de marcadores en comunas lejanas:
- El cliente móvil aplica un filtro espacial: con más de 4 unidades en servicio, sólo se dibujan las que están a **6 km** o menos de la posición del usuario (o del centro de Quilpué si no hay posición). El filtro por cuadrante visible: **(propuesto, pendiente)**.
- Al tocar un colectivo se despliega una tarjeta de detalle y **se ilumina en el mapa el trazado del recorrido que está cubriendo**, si el chofer lo eligió en su pantalla de turno.

### 7.2. Persistencia Ininterrumpida del Turno
- **Eliminación del borrado abrupto en `onDisconnect`:** en vez de `onDisconnect().remove()`, el servidor marca el nodo con `conectado: false` cuando detecta la desconexión, y la unidad sigue visible durante un periodo de gracia de **3 minutos**.
- Si el colectivo cruza un túnel o una zona de sombra, el vehículo **no desaparece del mapa**: con `conectado: false` o tras 45 s sin posición, el marcador se muestra atenuado y la tarjeta indica *"Última señal hace X"*.

### 7.3. Protección contra el Low Memory Killer (OOM) en Android
Los choferes de la locomoción colectiva suelen utilizar smartphones de gama de entrada con 2 GB o 3 GB de memoria RAM. Cuando el chofer bloquea la pantalla o recibe una llamada, Android puede terminar el proceso de ColeTotal para liberar memoria.

**Estrategia de Blindaje:**
1. **Foreground Service con Notificación Continua (implementado):**
   - Durante el turno el GPS corre en un servicio en primer plano con notificación fija ("ColeTotal — en servicio") y wake lock. La auditoría de octubre encontró que esta configuración no se aplicaba (el mapa abría antes su propio stream y el plugin ignoraba la del turno); se corrigió con un único dueño del GPS (`LocationService`).
2. **Exención de Optimización de Batería** **(propuesto, pendiente)**:
   - Solicitar al conductor la exención de ahorro de batería (`ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`) para que el fabricante (Xiaomi MIUI, Samsung OneUI) no congele el GPS.
3. **Frecuencia Adaptativa** **(propuesto, pendiente)**:
   - Con el vehículo detenido (velocidad < 2 km/h), subir el intervalo de 3 a 10 segundos para ahorrar batería.

---

## 8. Hoja de Ruta de Ejecución Técnica

| Paso | Acción Técnica | Componentes Afectados |
| :---: | :--- | :--- |
| **1** | Versión en `pubspec.yaml` (`0.4.3+4`), leída por la app desde el APK. ✅ | `pubspec.yaml`, `app_version.dart` |
| **2** | Mapa base offline dentro del APK (OpenStreetMap vía Protomaps), sin MapTiler ni claves; satélite de Esri. ✅ | `basemap_service.dart`, `app_map.dart`, `map_config.dart`, `scripts/mapa_base/` |
| **3** | Buscador: POIs de Quilpué, índice offline de calles y Photon. ✅ | `geocoding_service.dart`, `street_index.dart`, `quilpue_pois.dart` |
| **4** | Telemetría con presencia (`conectado`), `recorridoId` elegido por el chofer y GPS en primer plano. ✅ | `firebase_telemetria_service.dart`, `location_service.dart`, `turno_screen.dart` |
| **5** | Auditoría de turnos con almacenamiento local, tope de eventos y recuperación tras cierre. ✅ | `session_log_service.dart` |
| **6** | Diálogo de actualización (In-App OTA Update) contra Firestore. ✅ | `app_update_service.dart`, `app_update_dialog.dart` |
| **7** | Crashlytics, exención de batería y frecuencia adaptativa. (propuesto, pendiente) | — |
