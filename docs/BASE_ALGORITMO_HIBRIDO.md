# BASE ALGORÍTMICA — Optimizador Híbrido para ColeTotal (Para Análisis del Modelo Arquitecto)

> **Propósito de este documento:**
> Este archivo contiene toda la especificación matemática, algorítmica y de arquitectura del **Optimizador Híbrido en 2 Niveles (Subrogados en RAM + Oráculo Valhalla)** validado para el proyecto **ColeTotal (Transportes Serrano, Quilpué)**.
>
> **Instrucción para el Modelo Arquitecto (modelo avanzado):**
> NO implementes el código todavía. Tu tarea es:
> 1. Inspeccionar el repositorio real de ColeTotal (rutas/cartolas, `stop_planner.dart` o equivalente, wrapper de Valhalla, tipos de coordenadas y capa de UI que consume la recomendación).
> 2. Conectar cada pieza de este algoritmo base con los **archivos, clases, tipos y formatos reales** del proyecto.
> 3. Resolver (o confirmar conmigo si hay duda de negocio) las **5 decisiones de integración** de la Sección 6.
> 4. Generar el documento definitivo **`docs/SPEC_OPTIMIZADOR_HIBRIDO.md`**, con cero ambigüedades, firmas exactas en Dart, archivos permitidos/prohibidos y pruebas unitarias especificadas, listo para que un **modelo rápido/económico** lo implemente directamente sin tener que explorar todo el repositorio.

---

## 1. Contexto y Objetivo de Ingeniería (Por qué existe este algoritmo)

En **ColeTotal**, los taxis colectivos operan por **cartola oficial (DS 212)**: el pasajero puede subir en cualquier esquina $s$ y bajar en cualquier esquina $s'$ a lo largo del trazado autorizado de una variante $v$ en su sentido dirigido $\delta \in \{\text{Ida}, \text{Vuelta}\}$.

- **El cuello de botella ("Paradoja de Valhalla"):** Evaluar ~180 ternas candidatas $(s, s', v, \delta)$ llamando directamente a Valhalla C++ local implica ~234 invocaciones secuenciales ($\sim 80\text{ ms/ruta} \approx 18{,}6\text{ s}$ de CPU al 100%), congelando la app en Android (error ANR).
- **La solución (Híbrido cooperativo en cascada / *Relay* de 2 niveles):**
  - **Nivel 1 (Exploración en RAM, $\approx 8{,}1\text{ ms}$):** Evalúa todas las ternas factibles en memoria usando dos subrogados ligeros ($\tilde{D}_{\text{walk}}$ y $\tilde{D}_{\text{veh}}$) y filtra estrictamente el sentido de marcha DS 212.
  - **Nivel 2 (Oráculo exacto Valhalla, $\approx 80\text{ ms}$):** Recibe únicamente la terna ganadora (o un conjunto acotado Top-$k$) para calcular la geometría vial exacta y las instrucciones paso a paso en MapLibre, reduciendo llamadas a Valhalla en $>99\%$ y manteniendo $0\text{ KB}$ de consumo de red.

---

## 2. Modelo Matemático Formal y Constantes Calibradas

### 2.1 Variables de Decisión y Parámetros Fijos
- **Entrada online:** coordenada GPS de origen del usuario $u = (\phi_u, \lambda_u)$ y coordenada GPS de destino final $d = (\phi_d, \lambda_d)$.
- **Espacio de cartolas dirigidas:** conjunto de pares $(v, \delta)$, donde cada variante de colectivo tiene trazados separados por sentido (ej. 3 variantes $\times$ 2 sentidos = 6 cartolas dirigidas).
- **Terna candidata:** $(s, s', v, \delta)$, donde $s$ es el nodo/esquina de subida y $s'$ es el nodo/esquina de bajada dentro de la misma cartola $(v, \delta)$.

| Parámetro | Símbolo | Valor Fijo Calibrado | Significado |
| :--- | :---: | :---: | :--- |
| Peso caminata acceso | $\alpha$ | `2.0` | Penalización de caminata $u \to s$ |
| Peso tramo vehicular | $\beta$ | `1.0` | Costo unitario de viaje a bordo $s \to s'$ |
| Peso caminata egreso | $\gamma$ | `2.0` | Penalización de caminata $s' \to d$ |
| Factor de tortuosidad | $\tau$ | `1.25` | Corrección de línea recta a malla vial urbana (Quilpué) |
| Radio terrestre medio | $R_{\text{earth}}$ | `6371000.0` m | Radio para fórmula esférica de Haversine |
| Avance mínimo DS 212 | $L_{\min}$ | `100.0` m | Distancia mínima en vehículo (evita sentido contrario / giros nulos) |
| Caminata máxima por tramo | $W_{\max}$ | `1000.0` m | Radio máximo de captación peatonal en acceso y en egreso |

### 2.2 Función Objetivo y Restricciones
$$\min \; Z(s, s', v, \delta) = \alpha \cdot \tilde{D}_{\text{walk}}(u, s) + \beta \cdot \tilde{D}_{\text{veh}}(s, s', v, \delta) + \gamma \cdot \tilde{D}_{\text{walk}}(s', d)$$

Sujeto a:
1. **Unicidad de servicio:** $s$ y $s'$ pertenecen a la misma variante $v$ y mismo sentido $\delta$.
2. **Sentido estricto DS 212:** $A_{v,\delta}[s'] - A_{v,\delta}[s] \ge L_{\min}$ (en metros, implica además índice $j > i$ si la ruta no es circular).
3. **Umbral peatonal:** $\tilde{D}_{\text{walk}}(u, s) \le W_{\max}$ y $\tilde{D}_{\text{walk}}(s', d) \le W_{\max}$.

---

## 3. Especificación de los Subrogados y la Tabla LUT

### 3.1 Subrogado Peatonal ($\tilde{D}_{\text{walk}}$)
Se calcula exclusivamente con aritmética trigonométrica (sin red, sin grafo, $\approx 0{,}001\text{ ms}$ por evaluación):

$$\Delta\phi = \text{rad}(\phi_2 - \phi_1), \quad \Delta\lambda = \text{rad}(\lambda_2 - \lambda_1)$$
$$a = \sin^2\left(\frac{\Delta\phi}{2}\right) + \cos(\text{rad}(\phi_1)) \cdot \cos(\text{rad}(\phi_2)) \cdot \sin^2\left(\frac{\Delta\lambda}{2}\right)$$
$$\tilde{D}_{\text{walk}}(p_1, p_2) = \tau \cdot 2 \cdot R_{\text{earth}} \cdot \arcsin\left(\min\left(1.0, \sqrt{a}\right)\right)$$

> **Nota crítica de implementación:** usar `clamp(0.0, 1.0)` sobre `a` antes de `sqrt` / `asin` para evitar `NaN` por errores de punto flotante cuando $p_1 = p_2$. La salida debe estar siempre en **metros** (`double`).

### 3.2 Subrogado Vehicular por Tabla de Progresivas LUT ($\tilde{D}_{\text{veh}}$)
Para cada cartola dirigida $(v, \delta)$:
1. Se pre-calcula (al iniciar la app o al cargar las rutas, una sola vez en memoria) una lista ordenada de nodos/esquinas discretizados desde la garita inicial hasta el término del recorrido:
   - `nodes[0 ... M-1]`: coordenadas `(lat, lng)` ordenadas en el sentido real de circulación.
   - `cumulativeMeters[0 ... M-1]` ($A_{v,\delta}$): distancia acumulada en metros sobre la polilínea oficial desde `nodes[0]` hasta `nodes[i]` (calculada con Haversine segmento a segmento **sin** multiplicar por $\tau$, porque la polilínea ya sigue la calle real).
2. Dado un índice de subida `i` y un índice de bajada `j` en la misma cartola $(v, \delta)$:
   $$\tilde{D}_{\text{veh}}(i, j, v, \delta) = A_{v,\delta}[j] - A_{v,\delta}[i]$$
   - Complejidad: **$\mathcal{O}(1)$**, cero consultas al grafo vial, exacto sobre la troncal oficial.

### 3.3 Pre-procesamiento de Polilíneas (Discretización)
Las polilíneas reales (GeoJSON / lista de vértices de MapLibre) pueden tener tramos rectos largos sin vértices intermedios (ej. 600 m entre dos vértices) o curvas con vértices cada 3 m.
- **Regla requerida:** Antes de construir `cumulativeMeters`, remuestrear/interpolar linealmente la polilínea de cada cartola a un paso uniforme $\Delta_{\text{step}}$ (valor recomendado: **`60.0` metros**, ~media cuadra), preservando el primer y último punto. Esto asegura densidad homogénea de esquinas candidatas y acota la cantidad total de nodos en RAM.

---

## 4. Lógica Paso a Paso del Algoritmo (Nivel 1 → Nivel 2)

```text
ENTRADA:
  - origin (u): LatLng
  - destination (d): LatLng
  - preloadedRoutes: List<DirectedCartolaLut>  // cada una con nodes[] y A[] en metros

PASO 1 — Línea base caminata directa:
  directWalkMeters = haversineMeters(u, d) * TAU
  directWalkCost   = ALPHA * directWalkMeters   // costo si no toma colectivo

PASO 2 — Búsqueda de Nivel 1 por cada cartola dirigida r en preloadedRoutes:
  2.1 Calcular walkAccess[i] = haversineMeters(u, r.nodes[i]) * TAU  para todo i
  2.2 Calcular walkEgress[j] = haversineMeters(r.nodes[j], d) * TAU  para todo j
  2.3 Filtrar upCandidates = los K_UP nodos (ej. K_UP = 6) con menor walkAccess[i]
      tales que walkAccess[i] <= W_MAX (si hay nodos dentro de W_MAX)
  2.4 Filtrar downCandidates = los K_DOWN nodos (ej. K_DOWN = 6) con menor walkEgress[j]
      tales que walkEgress[j] <= W_MAX (si hay nodos dentro de W_MAX)
  2.5 Para cada i en upCandidates:
        Para cada j en downCandidates:
          Si j <= i: continuar  // (salvo ruta circular si aplica)
          vehMeters = r.A[j] - r.A[i]
          Si vehMeters < L_MIN: continuar  // Restricción estricta DS 212
          totalCost = ALPHA * walkAccess[i] + BETA * vehMeters + GAMMA * walkEgress[j]
          Registrar candidato válido (r, i, j, totalCost, walkAccess[i], vehMeters, walkEgress[j])

PASO 3 — Política de Fallback (si no hubo ningún candidato factible):
  Si lista de candidatos válidos está vacía:
    Re-intentar Paso 2 relajando W_MAX -> W_FALLBACK (ej. 2000.0 m)
    y marcando flag isLongWalkFallback = true.
    Si aún sigue vacío -> retornar estado explícito sin ruta factible.

PASO 4 — Comparación contra caminata directa:
  Sea best = candidato con menor totalCost.
  Si best.totalCost >= directWalkCost:
    Marcar recomendación como "caminar directo es mejor o equivalente"
    (para que la UI pueda sugerir caminata directa en vez de colectivo).

PASO 5 — Paso al Nivel 2 (Cascada / Relay a Valhalla):
  - Opción estándar (1 llamada): invocar Valhalla únicamente para `best`
    (tramo acceso u->s*, tramo vehicular s*->s'*, tramo egreso s'*->d).
  - Opción Top-k por variante / mitigación de barreras (vía férrea EFE):
    tomar la mejor terna de cada variante (máx. 3) o las Top-K (ej. 2 o 3) ternas globales
    y validarlas con Valhalla en Nivel 2.
```

---

## 5. Checklist de Inspección para el Modelo Arquitecto (En el Repo Real)

Antes de generar `docs/SPEC_OPTIMIZADOR_HIBRIDO.md`, debes abrir y verificar en el repositorio de ColeTotal:

1. **Archivo planificador actual:** ¿Dónde vive `stop_planner.dart` (o equivalente), cuál es su firma pública actual y qué clases de la UI la llaman?
2. **Fuente de datos de rutas / cartolas:** ¿Cómo se cargan hoy las variantes (`Belloto 2000`, `Las Rosas`, `Cumming/El Mirador`)? ¿Son GeoJSON en `assets/`, JSON locales, objetos Dart hardcodeados? ¿Están ya separadas en `Ida` y `Vuelta` con el orden correcto o hay polígonos/circuitos cerrados?
3. **Librería geográfica:** ¿El proyecto usa `LatLng` de `latlong2`, de `maplibre_gl`, o una clase propia? (Usar el tipo exacto para evitar conversiones innecesarias).
4. **Cliente Valhalla (Nivel 2):** ¿Cómo se llama hoy a Valhalla desde Dart (`MethodChannel`, `ffi`, servicio REST local, wrapper)? ¿Se le pasan waypoints `(u, s, s', d)` en una llamada multimodal o 3 llamadas separadas (walk + auto/bus + walk)? ¿Valhalla permite forzar que el tramo en colectivo siga la cartola (`trace_route` / waypoints intermedios) o solo recibe subida y bajada?
5. **Estado de UI y errores:** ¿Qué espera la UI cuando no hay rutas o cuando el usuario está a $<300\text{ m}$ del destino?

---

## 6. Las 5 Decisiones de Integración que el Modelo Arquitecto Debe Fijar en la Spec Final

En `docs/SPEC_OPTIMIZADOR_HIBRIDO.md` **no debe quedar ningún "depende" ni parámetro abierto**. Debes fijar valores únicos tras leer el repo (o preguntarme antes si afecta la UX):

1. **Paso de discretización ($\Delta_{\text{step}}$) y caché de LUT:** confirmar valor exacto (ej. `60.0 m`) y en qué momento del ciclo de vida de la app se construye la LUT (idealmente lazy singleton o al cargar las rutas).
2. **Representación de sentidos (`Ida` / `Vuelta` vs circuito cerrado):** definir exactamente cómo se mapean las cartolas actuales del repo a listas dirigidas con índice creciente.
3. **Top-$K$ candidatos y *Fallback*:** confirmar $K_{\text{up}} = 6$, $K_{\text{down}} = 6$, y la acción exacta si no hay candidatos dentro de $W_{\max} = 1\,000\text{ m}$ (ej. relajar a $W_{\text{fallback}} = 2\,000\text{ m}$ con bandera `isLongWalkFallback` o retornar `PlanResult.noRoute`).
4. **Caminata directa y cardinalidad de resultados:** definir si retorna `1` terna óptima global, `Top-k` global (ej. 3 para mitigar cruces de vía férrea) o `1` terna óptima por cada variante activa (Belloto 2000, Las Rosas, Cumming/El Mirador).
5. **Integración exacta con Valhalla Nivel 2:** especificar la llamada exacta al wrapper existente en el repo para renderizar la(s) terna(s) ganadora(s) en MapLibre.

---

## 7. Estructura Obligatoria del Documento Final (`docs/SPEC_OPTIMIZADOR_HIBRIDO.md`)

El documento final que generes para el **modelo constructor (económico)** deberá tener exactamente estas 7 secciones:

1. **Alcance exacto de archivos:** lista de archivos a crear, archivos a editar y lista explícita de archivos que **NO** deben leerse ni modificarse.
2. **Constantes y reglas de negocio cerradas:** tabla con todos los valores fijos en Dart (`const`).
3. **Contratos y modelos de datos exactos (Dart):** *imports* reales del `pubspec.yaml` del repo, definición exacta de clases (`DirectedRouteLut`, `CandidateTriplet`, `PlannedRouteResult`, etc.) y firmas de métodos.
4. **Constructor de Tabla LUT y Discretización:** lógica exacta conectada al loader de rutas real del repo.
5. **Implementación paso a paso del Optimizador (Nivel 1 + Relay a Nivel 2):** pseudocódigo determinista sin ambigüedades, manejo explícito de unidades (metros y radianes) y conexión con el wrapper real de Valhalla.
6. **Manejo de casos borde:** tabla `Condición -> Comportamiento exacto`.
7. **Plan de Pruebas Unitarias y Comandos de Verificación:**
   - Casos de prueba obligatorios a implementar en `test/`:
     1. *Filtro estricto DS 212:* verifica que jamás se elija un par con $A[s'] - A[s] < 100\text{ m}$ o en sentido inverso ($j \le i$).
     2. *Acoplamiento de 3 tramos:* verifica que no elige ciegamente las esquinas más cercanas al origen y destino si eso viola sentido o aumenta el costo global $Z$.
     3. *Discretización de tramo recto largo:* verifica que una polilínea con vértices separados 500 m genera nodos intermedios cada $\Delta_{\text{step}}$ y suma progresivas consistentes.
     4. *Caminata directa:* origen y destino a 150 m $\implies$ activa recomendación de caminata directa ($Z^* \ge Z_{\text{direct}}$).
     5. *Fallback $> 1\,000\text{ m}$:* usuario a $1\,300\text{ m}$ de la ruta más cercana $\implies$ se comporta según la regla de fallback sin lanzar excepción ni retornar nulo inesperado.
     6. *Precisión Haversine:* verifica la fórmula en metros con dos coordenadas conocidas de Quilpué (ej. Estación Quilpué – Hospital de Quilpué) y caso $p_1 = p_2 \implies 0.0$ (sin `NaN`).
   - Comandos finales exactos que el modelo constructor debe ejecutar (`dart analyze ...` y `flutter test ...`).
