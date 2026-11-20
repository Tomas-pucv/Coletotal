# PLAN_EJECUCION_RUTAS.md — Corrección de Trazado de Recorridos desde Cartolas MTT

## Reglas Globales para el Modelo Ejecutor
1. **Respeta el alcance de cada fase:** Modifica únicamente los archivos listados en la fase activa.
2. **No rompas contratos ni tests existentes:**
   - `lib/services/line_planner.dart` **NO se debe modificar** (pertenece al planificador de viajes del pasajero).
   - `normalizeForSearch`, `matchesAllTokens` y `containsAllTokens` en `lib/utils/text_search.dart` deben mantener su firma y comportamiento actual para no romper `test/text_search_test.dart` ni `test/lineas_screen_test.dart`.
   - `StreetIndex.search(String query, {required LatLng near, int limit = 6})` debe mantener su firma compatible con `lib/services/geocoding_service.dart` y `test/quilpue_pois_test.dart`.
   - `RecorridoEditorScreen.vueltaDesdeIda(List<LatLng> ida)` debe mantener su firma estática e invertir la lista recibida para no romper `test/lineas_screen_test.dart`.
   - `ValhallaClient.route(List<LatLng> waypoints, {required ValhallaCosting costing})` debe conservar `'type': 'break'` por omisión cuando no se active el modo sin giros en U, para no romper `test/valhalla_client_test.dart` ni `test/route_service_test.dart`.
3. **Verificación obligatoria:** Al terminar cada fase, ejecuta los comandos del bloque **Criterio de aceptación y verificación** antes de pasar a la siguiente.

---

## Fase 1: Pipeline Offline de Calles e Intersecciones

- **Archivos a modificar:**
  - `scripts/mapa_base/build.js`
  - `assets/map/calles_valparaiso.json` (generado cuando se ejecute con acceso a Overpass; `StreetIndex` soporta tanto 4 como 5 columnas)
  - `assets/map/intersecciones_valparaiso.json` (nuevo archivo generado; ya queda cubierto por `- assets/map/` en `pubspec.yaml`)

- **Objetivo técnico:**
  Excluir vías no vehiculares (`pedestrian`, `service`, `living_street`) del índice de calles, preservar la jerarquía vial (`highway`) manteniendo compatibilidad con las 4 columnas iniciales de `calles_valparaiso.json`, y precalcular un índice compacto de intersecciones reales `assets/map/intersecciones_valparaiso.json`.

- **Especificación de implementación:**
  1. En `scripts/mapa_base/build.js` (sección `6. Índice de calles`):
     - Reemplazar la expresión regular `VIAS` por vías estrictamente vehiculares de transporte público:
       ```js
       const VIAS =
         '^(motorway|trunk|primary|secondary|tertiary|unclassified|residential|road)(_link)?$';
       ```
     - En `consultarOverpass()`:
       - Cambiar el nombre del archivo de caché de `'calles_overpass.json'` a `'calles_overpass_geom.json'` para invalidar la caché anterior que no tenía geometría.
       - Cambiar la directiva de salida de Overpass de `out tags center qt;` a:
         ```
         out tags geom qt;
         ```
  2. En `calles()` dentro de `scripts/mapa_base/build.js`:
     - Para cada `via` de `datos.elements`, obtener su lista de coordenadas desde `via.geometry` (`via.geometry.map((p) => [p.lon, p.lat])`) o, como respaldo si no trae `geometry`, `[via.center.lon, via.center.lat]`.
     - Calcular el punto central de la `via` como el vértice medio `geom[Math.floor(geom.length / 2)]`.
     - Registrar la jerarquía vial `highway = (via.tags?.highway || 'residential').replace('_link', '')` con prioridad numérica:
       - `trunk` / `motorway`: `1`
       - `primary`: `2`
       - `secondary`: `3`
       - `tertiary`: `4`
       - `residential` / `unclassified` / `road`: `5`
     - Mantener el formato de salida de `assets/map/calles_valparaiso.json` agregando la prioridad como **5.º elemento** de cada tupla:
       ```js
       filas.push([nombre, comuna, +lat.toFixed(5), +lon.toFixed(5), prioridad]);
       ```
       *(Nota: los primeros 4 elementos siguen siendo `[nombre, comuna, lat, lon]`).*
  3. Cálculo y escritura de `assets/map/intersecciones_valparaiso.json` dentro de `calles()`:
     - Para cada `via` válida con `comuna` y `via.geometry`:
       - Guardar sus vértices `[lon, lat]` asociados a su clave de calle normalizada `${normalizar(nombre)}|${comuna}` (y también el nombre base sin prefijos `avenida`, `av`, `calle`, `camino`, `pasaje`).
     - Detectar cruces entre dos calles distintas $A$ y $B$ de la misma comuna cuando:
       - Comparten exactamente un vértice `[lon, lat]`, o
       - Tienen vértices a menos de `35` metros (`metros(pA, pB) <= 35`, necesario para avenidas de doble calzada como `Av. Ramón Freire`, `Av. Los Carrera`, `Marga Marga`, `Autopista Troncal Sur`).
     - Agrupar los puntos de cruce del mismo par $(A, B)$ que estén a menos de `80` metros usando `agrupar(puntosCruce, 80)` y tomar `medoide(grupo)` para obtener una coordenada `[+lat.toFixed(5), +lon.toFixed(5)]` por cruce.
     - Guardar en `assets/map/intersecciones_valparaiso.json` un mapa JSON compacto:
       ```json
       {
         "comuna|calle_a|calle_b": [[-33.04811, -71.42573], ...]
       }
       ```
       donde `calle_a` y `calle_b` van ordenadas alfabéticamente (`calleA < calleB ? `${comuna}|${calleA}|${calleB}` : `${comuna}|${calleB}|${calleA}``) con nombres base normalizados.

- **Criterio de aceptación y verificación:**
  - Si se dispone de red para consultar Overpass:
    ```powershell
    node scripts/mapa_base/build.js --solo=calles
    ```
  - Si se ejecuta offline sin regenerar Overpass, generar `assets/map/intersecciones_valparaiso.json` desde los datos locales disponibles (`assets/map/valparaiso.pmtiles`).
  - Verificar que `flutter test test/basemap_test.dart` pase sin errores.

---

## Fase 2: Motor de Búsqueda, Normalización Vial y Scoring Multicriterio

- **Archivos a modificar:**
  - `lib/utils/text_search.dart`
  - `lib/services/street_index.dart`

- **Objetivo técnico:**
  Evitar coincidencias falsas por subcadena (`"MARGA MARGA"` → `"Pasaje Margarita"`, `"MENA"` → `"Santa Filomena"`), separar prefijos viales del nombre base, penalizar pasajes/condominios/galerías frente a arterias principales y acotar búsquedas de cartola a un radio máximo sin romper la búsqueda del pasajero.

- **Especificación de implementación:**
  1. En `lib/utils/text_search.dart`:
     - **Mantener intactas** `normalizeForSearch`, `matchesAllTokens`, `searchTokens` y `containsAllTokens`.
     - Agregar al final del archivo la normalización y tokenización vial:
       ```dart
       final RegExp _noAlfanumerico = RegExp(r'[^a-z0-9\s]');

       /// Prefijos de tipo de vía comunes en cartolas MTT y OpenStreetMap.
       const Set<String> kPrefijosViaIgnorables = {
         'av', 'avda', 'avenida', 'calle', 'cam', 'camino',
       };

       /// Prefijos o palabras que identifican vías menores / interiores.
       const Set<String> kPrefijosViaMenor = {
         'pje', 'psje', 'pasaje', 'condominio', 'galeria', 'callejon',
         'variante', 'retorno', 'conjunto', 'antiguo', 'interior',
       };

       /// Abreviaturas de títulos en nombres de calles chilenas.
       const Map<String, String> kAbreviaturasViales = {
         'almte': 'almirante',
         'gral': 'general',
         'pdte': 'presidente',
         'dr': 'doctor',
         'sta': 'santa',
         'sto': 'santo',
       };

       class NormalizedStreetQuery {
         const NormalizedStreetQuery({
           required this.baseTokens,
           required this.allTokens,
           required this.explicitMinorType,
         });

         /// Palabras del nombre propio de la calle (sin "av", "calle", etc.).
         final List<String> baseTokens;

         /// Todas las palabras normalizadas sin puntuación.
         final List<String> allTokens;

         /// `true` si el usuario escribió explícitamente "pasaje", "variante", etc.
         final bool explicitMinorType;
       }

       NormalizedStreetQuery parseStreetQuery(String raw) {
         final clean = normalizeForSearch(raw)
             .replaceAll(_noAlfanumerico, ' ')
             .trim()
             .replaceAll(_espacios, ' ');
         if (clean.isEmpty) {
           return const NormalizedStreetQuery(
             baseTokens: [],
             allTokens: [],
             explicitMinorType: false,
           );
         }
         final rawTokens = clean
             .split(' ')
             .where((t) => t.isNotEmpty)
             .map((t) => kAbreviaturasViales[t] ?? t)
             .toList(growable: false);

         final explicitMinor = rawTokens.any(kPrefijosViaMenor.contains);
         final base = rawTokens
             .where((t) =>
                 !kPrefijosViaIgnorables.contains(t) &&
                 (explicitMinor || !kPrefijosViaMenor.contains(t)))
             .toList(growable: false);

         return NormalizedStreetQuery(
           baseTokens: base.isNotEmpty ? base : rawTokens,
           allTokens: rawTokens,
           explicitMinorType: explicitMinor,
         );
       }
       ```
  2. En `lib/services/street_index.dart`:
     - Actualizar `_parsear` para aceptar filas tanto de 4 elementos `[nombre, comuna, lat, lon]` como de 5 elementos `[nombre, comuna, lat, lon, prioridad]`:
       ```dart
       static List<_Calle> _parsear(String json) {
         final filas = jsonDecode(json) as List<dynamic>;
         final resultado = <_Calle>[];
         for (final (i, fila) in filas.indexed) {
           if (fila case [
             final String nombre,
             final String comuna,
             final num lat,
             final num lon,
             ...final List<dynamic> resto,
           ]) {
             final prioridad = resto.isNotEmpty && resto.first is num
                 ? (resto.first as num).toInt()
                 : 3;
             resultado.add(
               _Calle(
                 id: i,
                 nombre: nombre,
                 comuna: comuna,
                 latitud: lat.toDouble(),
                 longitud: lon.toDouble(),
                 prioridad: prioridad,
               ),
             );
           }
         }
         return resultado;
       }
       ```
     - En la clase `_Calle`:
       - Precalcular al construir:
         - `final int prioridad;`
         - `final NormalizedStreetQuery parsed = parseStreetQuery(nombre);`
         - `final String comunaNorm = normalizeForSearch(comuna);`
         - `final bool esViaMenor = parsed.explicitMinorType;`
     - Implementar el cálculo de coincidencia y puntaje `_scoreCalle`:
       - **Coincidencia de tokens del nombre (`parsed.baseTokens`):**
         - Cuando `exactWords == true` (modo Cartola): cada token `q` de `query.baseTokens` debe coincidir de forma **exacta** (`cToken == q`) con un token de la calle (o de la comuna si el usuario incluyó la comuna). Si `query.baseTokens` tiene $K$ ocurrencias de una palabra (ej. `['marga', 'marga']`), la calle debe contener al menos $K$ tokens que coincidan o ser exactamente el nombre base sin que una sola palabra como `"margarita"` valide ambas.
         - Cuando `exactWords == false` (modo autocompletado / pasajero): se permite coincidencia exacta de token o prefijo de token (`cToken.startsWith(q)`), manteniendo compatibilidad con escritura incremental.
       - **Penalización/Bonificación:**
         - Si `calle.esViaMenor && !query.explicitMinorType`: penalizar sumando una distancia equivalente de `+2500` metros (en modo `search`) o descartar (en modo `searchCartolaCandidates`).
         - Si `calle.parsed.baseTokens.length == query.baseTokens.length` y todos los tokens base coinciden exactamente: bonificar restando `-800` metros equivalentes.
         - Bonificar según `prioridad` vial (`(prioridad - 3) * 150` metros equivalentes).
     - Mantener la firma de `StreetIndex.search`:
       ```dart
       static Future<List<PlaceResult>> search(
         String query, {
         required LatLng near,
         int limit = 6,
         bool exactWords = false,
         double? maxDistanceMeters,
       })
       ```
       - Si `maxDistanceMeters != null`, filtrar los candidatos cuya distancia real en metros a `near` supere `maxDistanceMeters`.
     - Agregar en `StreetIndex` un método para obtener todos los tramos candidatos de una calle de cartola dentro de un radio y buscar intersecciones precalculadas:
       ```dart
       static Future<List<PlaceResult>> searchCartolaCandidates(
         String nombreCalle, {
         required LatLng near,
         double maxDistanceMeters = 5500,
       })
       ```
       que invoque la búsqueda con `exactWords: true`, `maxDistanceMeters: maxDistanceMeters`, excluyendo vías menores (`calle.esViaMenor`) cuando `!parseStreetQuery(nombreCalle).explicitMinorType`, y devolviendo hasta `10` candidatos ordenados por score.
     - Agregar en `StreetIndex` la carga perezosa opcional de `assets/map/intersecciones_valparaiso.json` (`static Future<List<LatLng>> findPrecomputedIntersections(String calleA, String calleB, {String comuna = 'Quilpué'})`), devolviendo `const []` si el archivo no existe o no contiene el par, y limpiar también la caché de intersecciones dentro de `debugReset()`.

- **Criterio de aceptación y verificación:**
  ```powershell
  flutter analyze lib/utils/text_search.dart lib/services/street_index.dart
  flutter test test/text_search_test.dart test/quilpue_pois_test.dart
  ```

---

## Fase 3: Servicio de Resolución de Secuencias de Cartola (`CartolaResolver`)

- **Archivos a crear:**
  - `lib/services/cartola_resolver.dart` *(nuevo archivo)*

- **Objetivo técnico:**
  Resolver una secuencia ordenada de nombres de calles de cartola $[C_1, C_2, \dots, C_n]$ aislada de `kQuilpuePois`, calculando cruces/tramos consecutivos y rumbos (`heading`) sin arrastrar el ancla `near` cuando una calle no existe.

- **Especificación de implementación:**
  Crear `lib/services/cartola_resolver.dart` con las siguientes estructuras y métodos:
  1. Modelos de datos:
     - `PasoCartola`: `id`, `nombre`, `coordenadaManual`, `coordenadaResuelta`, `heading`, `coordenada`, `resuelto`, `copyWith`.
     - `SecuenciaCartolaResuelta`: `pasos`, `waypoints`, `headings`.
  2. Algoritmo en `abstract final class CartolaResolver`:
     - Constante `static const double maxRadioPasoMetros = 5500;` y `static const Distance _geo = Distance();`.
     - Método principal `resolverSecuencia(List<PasoCartola> pasos, {LatLng anclaInicial = kQuilpueCenter})`.
     - **Paso A — Obtener candidatos por cada paso:**
       - Recorrer `pasos` manteniendo `LatLng ancla = anclaInicial`.
       - Si `paso.coordenadaManual != null`, sus candidatos son `[paso.coordenadaManual!]` y `ancla = paso.coordenadaManual!`.
       - Si no tiene coordenada manual, consultar `await StreetIndex.searchCartolaCandidates(paso.nombre, near: ancla, maxDistanceMeters: maxRadioPasoMetros)`.
       - Si la lista de candidatos está vacía: el paso queda con `coordenadaResuelta: null` y **`ancla` NO cambia** (conserva el último punto válido para no arrastrar la búsqueda a otra comuna).
       - Si hay candidatos: actualizar provisionalmente `ancla` al mejor candidato.
     - **Paso B — Selección de tramos e intersecciones entre calles consecutivas:**
       - Para cada par de pasos resueltos consecutivos $(i, j)$ con nombres $C_i$ y $C_j$:
         1. Consultar `await StreetIndex.findPrecomputedIntersections(C_i, C_j)` y quedarse con el cruce más cercano al `ancla` (dentro de `maxRadioPasoMetros`).
         2. Si no hay cruce precalculado en el JSON, elegir el par de candidatos $(p_i \in \text{cand}(C_i), p_j \in \text{cand}(C_j))$ que minimice $\text{dist}(p_i, p_j) + 0.35 \cdot \text{dist}(\text{anclaAnterior}, p_i)$.
         3. Si $\text{dist}(p_i, p_j) \le 120\text{ m}$, el cruce estimado entre $C_i$ y $C_j$ es el punto medio entre $p_i$ y $p_j$; de lo contrario, se conservan $p_i$ y $p_j$ elegidos por continuidad espacial.
     - **Paso C — Asignación de coordenadas y `heading` libre de giros en U:**
       - Para cada calle intermedia $C_i$ que tiene cruce de entrada $E_i$ (con $C_{i-1}$) y cruce de salida $S_i$ (con $C_{i+1}$):
         - Si $\text{dist}(E_i, S_i) \ge 40\text{ m}$, la coordenada resuelta de $C_i$ se ubica en el **punto medio interior** entre $E_i$ y $S_i$, y su rumbo `heading` se calcula con `_bearingDegrees(E_i, S_i)` en el rango $[0, 360)$.
         - Para el primer paso resuelto ($C_1$) y el último ($C_n$), se usa el candidato de $C_1$ (o $C_n$) alineado con el primer/último cruce, y su `heading` apunta hacia el siguiente punto (o desde el penúltimo punto).
       - Filtrar waypoints consecutivos duplicados o a menos de `15` metros entre sí para evitar micro-bucles en el enrutador.

- **Criterio de aceptación y verificación:**
  ```powershell
  flutter analyze lib/services/cartola_resolver.dart
  ```

---

## Fase 4: Enrutamiento Direccional sin Bucles en Valhalla y OSRM

- **Archivos a modificar:**
  - `lib/services/valhalla_client.dart`
  - `lib/services/osrm_client.dart`
  - `lib/services/routing.dart`

- **Objetivo técnico:**
  Impedir giros en U artificiales en los waypoints intermedios de un recorrido oficial y enviar el rumbo (`heading`) a Valhalla y `continue_straight=true` a OSRM, preservando intacto el comportamiento por defecto para los tests actuales y rutas peatonales.

- **Especificación de implementación:**
  1. En `lib/services/valhalla_client.dart`:
     - Agregar `bool preventUTurns = false` y `List<double?>? headings` en `ValhallaClient.route` y `_request`.
     - Mantener `'type': 'break'` para primer/último punto de cada tramo (regla obligatoria de Valhalla) y para todos los puntos cuando `!preventUTurns`. Usar `'type': 'break_through'` solo en puntos intermedios cuando `preventUTurns == true`.
     - Enviar `'heading'` y `'heading_tolerance': 45` cuando `costing == ValhallaCosting.auto` y exista `headings[i] != null` (mapeando correctamente la ventana de `headings` correspondiente a cada `chunkWaypoints`).
  2. En `lib/services/osrm_client.dart`:
     - Agregar `bool continueStraight = false` en `OsrmClient.route` y `_requestRoute`, agregando `&continue_straight=true` solo cuando `continueStraight && profile == OsrmProfile.driving`.
  3. En `lib/services/routing.dart`:
     - Reenviar `preventUTurns` y `headings` desde `Routing.linePath` y `Routing.encodedLinePath` hacia `ValhallaClient.route` y `OsrmClient.route`.

- **Criterio de aceptación y verificación:**
  ```powershell
  flutter analyze lib/services/valhalla_client.dart lib/services/osrm_client.dart lib/services/routing.dart
  flutter test test/valhalla_client_test.dart test/route_service_test.dart
  ```

---

## Fase 5: Estado Unificado del Editor, Vuelta Inteligente y Sincronización UI

- **Archivos a modificar:**
  - `lib/screens/admin/recorridos_admin_screen.dart`

- **Objetivo técnico:**
  Unificar el estado de calles y puntos en el editor mediante `PasoCartola` y `CartolaResolver`, aislar los POIs del autocompletado de calles, mostrar advertencia visual en calles no resueltas, reconstruir la vuelta recalculando la secuencia de calles invertida y corregir los bugs de concurrencia de `_sentido` y del `TextEditingController`.

- **Especificación de implementación:**
  1. Mantener intacto `static List<LatLng> vueltaDesdeIda(List<LatLng> ida)`.
  2. Reemplazar `_calleInputController` por `_autocompleteController` (ciclo de vida manejado por `Autocomplete`) y usar `_pasos` + `_headings` por `Sentido`.
  3. Usar `_cambiarPuntos(void Function(List<LatLng>) cambio, {Sentido? sentido})` y `_programarAjuste([Sentido? s])` con el sentido capturado.
  4. En `_ajustar(Sentido sentido)`, pasar `preventUTurns: _pasos[sentido]!.isNotEmpty` y `headings: _headings[sentido]`.
  5. Implementar `_recalcularCartola(Sentido sentido, {bool moverCamara = true})`.
  6. Aislar `Autocomplete.optionsBuilder` y `_geocodificarCalle` usando exclusivamente `StreetIndex` (sin `kQuilpuePois`).
  7. Actualizar `_agregarCalle`, `_quitarCalle`, `_procesarTextoCartola` y `_vueltaDesdeIda` para operar sobre `_pasos` y recalcular con `CartolaResolver`.
  8. Mostrar icono/color de advertencia en los `Chip` con `!paso.resuelto`.

- **Criterio de aceptación y verificación:**
  ```powershell
  flutter analyze lib/screens/admin/recorridos_admin_screen.dart
  flutter test test/lineas_screen_test.dart test/recorrido_cartola_test.dart
  ```

---

## Fase 6: Pruebas Unitarias de Regresión y Estrés

- **Archivos a modificar:**
  - `test/recorrido_cartola_test.dart`

- **Objetivo técnico:**
  Verificar con el índice real `assets/map/calles_valparaiso.json` y `assets/map/intersecciones_valparaiso.json` que la resolución de calles y secuencias de cartola no sea secuestrada por POIs ni pasajes, calcule cruces coherentes y no salte de comuna ante calles inexistentes, además de medir el rendimiento bajo carga de las funciones nuevas.

- **Especificación de implementación:**
  1. Al inicio de `main()` en `test/recorrido_cartola_test.dart`, agregar `TestWidgetsFlutterBinding.ensureInitialized();`.
  2. Agregar un grupo de regresión con 3 tests:
     - `prioriza arterias principales sobre pasajes, galerías y condominios`
     - `resuelve secuencia de cartola con rumbos y sin secuestro de POIs`
     - `calle inexistente en el mapa base queda no resuelta sin saltar a otra comuna`
  3. Agregar un grupo de **pruebas de estrés** con medición de tiempo (`Stopwatch`) sobre las funciones nuevas:
     - `parseStreetQuery` (normalización masiva de strings de cartola)
     - `StreetIndex.searchCartolaCandidates` (búsquedas repetidas sobre índice real)
     - `StreetIndex.findPrecomputedIntersections` (consultas masivas de intersecciones reales)
     - `CartolaResolver.resolverSecuencia` (resolución repetida de secuencias largas de cartola)

- **Criterio de aceptación y verificación final (toda la suite del proyecto):**
  ```powershell
  flutter analyze
  flutter test test/recorrido_cartola_test.dart
  flutter test
  ```
