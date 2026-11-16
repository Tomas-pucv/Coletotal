# SPEC_OPTIMIZADOR_HIBRIDO.md — Especificación Definitiva del Optimizador Híbrido (2 Niveles) para ColeTotal

> **Estado:** Aprobada para implementación.
> **Base matemática:** [`docs/BASE_ALGORITMO_HIBRIDO.md`](BASE_ALGORITMO_HIBRIDO.md).
> **Propósito:** Especificación técnica cerrada (cero ambigüedades, firmas exactas en Dart, contratos reales del repositorio y plan de pruebas unitarias) del **Optimizador Híbrido Cooperativo en 2 Niveles (Subrogados en RAM + Oráculo Valhalla)** para ColeTotal (Transportes Serrano, Quilpué).

---

## 1. Alcance Exacto de Archivos

### 1.1 Archivos a crear
| Archivo | Propósito |
| :--- | :--- |
| `docs/SPEC_OPTIMIZADOR_HIBRIDO.md` | Esta especificación técnica definitiva. |
| `lib/services/hybrid_route_optimizer.dart` | Implementación del optimizador híbrido de 2 niveles (`DirectedRouteLut`, `CandidateTriplet`, `HybridPlanStatus`, `PlannedRouteResult`, `VerifiedHybridRoute`, `HybridRouteOptimizer`). |
| `test/hybrid_optimizer_test.dart` | Suite de pruebas unitarias (6 casos obligatorios de especificación + validación de Relay Nivel 2). |

### 1.2 Archivos a editar
| Archivo | Cambio permitido |
| :--- | :--- |
| `lib/services/line_planner.dart` | Integrar `HybridRouteOptimizer.optimize` dentro de `LinePlanner.suggest(...)`, conservando intactas todas las firmas públicas de `LinePlanner`, `LineaPriorizada`, `LineRankingStrategy` y el constructor existente de `LineSuggestion` (agregando únicamente los campos opcionales `costoTotal` y `esFallbackCaminataLarga`). |

### 1.3 Archivos que NO deben modificarse
- `lib/services/valhalla_client.dart`
- `lib/services/osrm_client.dart`
- `lib/services/routing.dart`
- `lib/services/route_service.dart`
- `lib/services/cartola_resolver.dart`
- `lib/services/street_index.dart`
- `lib/screens/map_screen.dart` y `lib/widgets/line_suggestions_sheet.dart`
- `test/planner_test.dart` y el resto de los archivos existentes en `test/`

---

## 2. Constantes y Reglas de Negocio Cerradas

Todas las constantes viven como `static const` dentro de `abstract final class HybridRouteOptimizer`:

| Constante en Dart | Símbolo | Tipo | Valor Fijo | Significado y Regla |
| :--- | :---: | :---: | :---: | :--- |
| `kAlphaWalkAccess` | $\alpha$ | `double` | `2.0` | Penalización de caminata de acceso $u \to s$. |
| `kBetaVehicular` | $\beta$ | `double` | `1.0` | Peso unitario del tramo a bordo en colectivo $s \to s'$. |
| `kGammaWalkEgress` | $\gamma$ | `double` | `2.0` | Penalización de caminata de egreso $s' \to d$. |
| `kTauTortuosity` | $\tau$ | `double` | `1.25` | Factor de tortuosidad de línea recta a malla vial urbana (Quilpué). |
| `kEarthRadiusMeters` | $R_{\text{earth}}$ | `double` | `6371000.0` | Radio terrestre medio en metros para Haversine esférico. |
| `kMinVehicularMeters` | $L_{\min}$ | `double` | `100.0` | Avance vehicular mínimo obligatorio por cartola DS 212 ($A[j] - A[i] \ge 100.0\text{ m}$). |
| `kMaxWalkMeters` | $W_{\max}$ | `double` | `1000.0` | Radio máximo nominal de caminata subrogada por tramo (acceso y egreso). |
| `kFallbackWalkMeters` | $W_{\text{fallback}}$ | `double` | `2000.0` | Radio relajado de respaldo cuando ningún candidato satisface $W_{\max}$. |
| `kDiscretizationStepMeters` | $\Delta_{\text{step}}$ | `double` | `60.0` | Paso uniforme máximo (en metros) para remuestrear las polilíneas al construir cada LUT. |
| `kTopUpCandidates` | $K_{\text{up}}$ | `int` | `6` | Máximo de nodos de subida evaluados por cartola dirigida. |
| `kTopDownCandidates` | $K_{\text{down}}$ | `int` | `6` | Máximo de nodos de bajada evaluados por cartola dirigida. |

### Reglas de Decisión Integradas (Sección 6 de la Base Algorítmica)
1. **Discretización y Caché LUT:** $\Delta_{\text{step}} = 60.0\text{ m}$. Las tablas `DirectedRouteLut` se construyen de forma perezosa y se almacenan en caché en memoria (`_lutCache`) indexadas por `(recorrido.id, sentido.name, stepMeters, trayecto.geometria.hashCode, trayecto.trazado.length, first, last)`.
2. **Sentidos Dirigidos:** Cada `Recorrido` activo (`r.activo == true`) aporta sus trayectos válidos mediante `r.trayectos`, que entrega pares `(Sentido.ida, ida)` y opcionalmente `(Sentido.vuelta, vuelta)` ya ordenados en el sentido real de circulación DS 212.
3. **Top-$K$ y Fallback:** Se seleccionan hasta $K_{\text{up}} = 6$ nodos de subida y $K_{\text{down}} = 6$ nodos de bajada dentro de $W_{\max} = 1000.0\text{ m}$. Si no existe ninguna terna factible en toda la red, y `enableFallback == true`, se reintenta la búsqueda con $W_{\text{fallback}} = 2000.0\text{ m}$ marcando `isLongWalkFallback = true`. Si sigue vacío, se retorna `HybridPlanStatus.noFeasibleRoute`.
4. **Caminata Directa y Cardinalidad:**
   - Si $Z^* \ge Z_{\text{direct}}$ (donde $Z_{\text{direct}} = \alpha \cdot \tilde{D}_{\text{walk}}(u, d)$), el plan se marca con `status = HybridPlanStatus.directWalkPreferred` (`recommendDirectWalk == true`).
   - En `LinePlanner.suggest(...)`, si `plan.status != HybridPlanStatus.optimalFound`, se retorna `const []` para no sugerir colectivo cuando caminar directo es mejor o equivalente.
   - `PlannedRouteResult.rankedByLine` entrega la mejor terna óptima por cada `Recorrido.id` activo, ordenada por `totalCost` ascendente (hasta `LinePlanner.maxSuggestions = 5` en la UI).
5. **Integración Nivel 2 (Valhalla):** El Nivel 1 corre en RAM sin tocar Valhalla ni la red. Al seleccionar una terna (o un conjunto Top-$k$), el Nivel 2 llama a `Routing.walkingPath` (Valhalla peatonal local en Android con fallback OSRM) mediante `HybridRouteOptimizer.verifyWithValhalla` / `verifyTopKWithValhalla` (o `RouteService.instance.fetchRoute` desde `MapScreen`), y extrae el tramo vehicular exacto `lut.nodes.sublist(upIndex, downIndex + 1)` directamente de la cartola oficial.

---

## 3. Contratos y Modelos de Datos Exactos (Dart)

### 3.1 Imports Reales (`pubspec.yaml`)
```dart
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import 'package:taxi1/models/recorrido.dart';
import 'package:taxi1/models/route_path.dart';
import 'package:taxi1/services/recorridos_service.dart';
import 'package:taxi1/services/routing.dart';
import 'package:taxi1/utils/polyline.dart';
```

### 3.2 Clases y Firmas Exactas

#### `DirectedRouteLut`
```dart
class DirectedRouteLut {
  const DirectedRouteLut({
    required this.recorrido,
    required this.sentido,
    required this.nodes,
    required this.cumulativeMeters,
  });

  final Recorrido recorrido;
  final Sentido sentido;
  final List<LatLng> nodes;
  final List<double> cumulativeMeters;

  double get totalLengthMeters =>
      cumulativeMeters.isEmpty ? 0.0 : cumulativeMeters.last;

  double vehicularMeters(int upIndex, int downIndex) =>
      cumulativeMeters[downIndex] - cumulativeMeters[upIndex];

  factory DirectedRouteLut.fromPolyline({
    required Recorrido recorrido,
    required Sentido sentido,
    required List<LatLng> polyline,
    double stepMeters = HybridRouteOptimizer.kDiscretizationStepMeters,
  });
}
```

#### `CandidateTriplet`
```dart
class CandidateTriplet {
  const CandidateTriplet({
    required this.lut,
    required this.upIndex,
    required this.downIndex,
    required this.walkAccessMeters,
    required this.vehMeters,
    required this.walkEgressMeters,
    required this.totalCost,
  });

  final DirectedRouteLut lut;
  final int upIndex;
  final int downIndex;

  /// Distancia subrogada peatonal de acceso: tau * haversine(origin, boardingNode).
  final double walkAccessMeters;

  /// Distancia vehicular en metros sobre la cartola: A[downIndex] - A[upIndex].
  final double vehMeters;

  /// Distancia subrogada peatonal de egreso: tau * haversine(alightingNode, destination).
  final double walkEgressMeters;

  /// Costo total Z = alpha * walkAccess + beta * vehMeters + gamma * walkEgress.
  final double totalCost;

  Recorrido get recorrido => lut.recorrido;
  Sentido get sentido => lut.sentido;
  LatLng get boardingNode => lut.nodes[upIndex];
  LatLng get alightingNode => lut.nodes[downIndex];
  double get totalWalkMeters => walkAccessMeters + walkEgressMeters;
  double get rawWalkAccessMeters =>
      walkAccessMeters / HybridRouteOptimizer.kTauTortuosity;
  double get rawWalkEgressMeters =>
      walkEgressMeters / HybridRouteOptimizer.kTauTortuosity;
}
```

#### `HybridPlanStatus` y `PlannedRouteResult`
```dart
enum HybridPlanStatus {
  optimalFound,
  directWalkPreferred,
  noFeasibleRoute,
}

class PlannedRouteResult {
  const PlannedRouteResult({
    required this.status,
    required this.best,
    required this.rankedByLine,
    required this.topCandidates,
    required this.directWalkMeters,
    required this.directWalkCost,
    required this.isLongWalkFallback,
  });

  final HybridPlanStatus status;
  final CandidateTriplet? best;
  final List<CandidateTriplet> rankedByLine;
  final List<CandidateTriplet> topCandidates;
  final double directWalkMeters;
  final double directWalkCost;
  final bool isLongWalkFallback;

  bool get recommendDirectWalk => status == HybridPlanStatus.directWalkPreferred;
  bool get hasRoute => status == HybridPlanStatus.optimalFound && best != null;
}
```

#### `VerifiedHybridRoute`
```dart
class VerifiedHybridRoute {
  const VerifiedHybridRoute({
    required this.candidate,
    required this.walkAccessPath,
    required this.vehicularSegment,
    this.walkEgressPath,
  });

  final CandidateTriplet candidate;
  final RoutePath? walkAccessPath;
  final List<LatLng> vehicularSegment;
  final RoutePath? walkEgressPath;

  double get exactWalkAccessMeters =>
      walkAccessPath?.distanceMeters ?? candidate.walkAccessMeters;

  double get exactWalkEgressMeters =>
      walkEgressPath?.distanceMeters ?? candidate.walkEgressMeters;
}
```

#### `HybridRouteOptimizer` (Firmas Públicas)
```dart
abstract final class HybridRouteOptimizer {
  static double haversineMeters(LatLng p1, LatLng p2);

  static double surrogateWalkMeters(
    LatLng p1,
    LatLng p2, {
    double tau = kTauTortuosity,
  });

  static List<LatLng> discretizePolyline(
    List<LatLng> polyline, {
    double stepMeters = kDiscretizationStepMeters,
  });

  static List<DirectedRouteLut> buildLuts(
    Iterable<Recorrido> recorridos, {
    double stepMeters = kDiscretizationStepMeters,
  });

  @visibleForTesting
  static void clearCache();

  static PlannedRouteResult optimize({
    required LatLng origin,
    required LatLng destination,
    List<Recorrido>? recorridos,
    List<DirectedRouteLut>? preloadedRoutes,
    bool enableFallback = true,
    double maxWalkMeters = kMaxWalkMeters,
    double fallbackWalkMeters = kFallbackWalkMeters,
    double minVehicularMeters = kMinVehicularMeters,
    int topUp = kTopUpCandidates,
    int topDown = kTopDownCandidates,
  });

  static Future<VerifiedHybridRoute> verifyWithValhalla({
    required LatLng origin,
    required LatLng destination,
    required CandidateTriplet candidate,
    bool includeEgress = false,
    Future<RoutePath?> Function(LatLng from, LatLng to)? walkRouter,
  });

  static Future<List<VerifiedHybridRoute>> verifyTopKWithValhalla({
    required LatLng origin,
    required LatLng destination,
    required PlannedRouteResult plan,
    int k = 3,
    bool perLine = true,
    bool includeEgress = false,
    Future<RoutePath?> Function(LatLng from, LatLng to)? walkRouter,
  });
}
```

#### Contrato actualizado en `lib/services/line_planner.dart`
En `LineSuggestion`:
```dart
class LineSuggestion {
  const LineSuggestion({
    required this.recorrido,
    required this.sentido,
    required this.subida,
    required this.bajada,
    required this.metrosHastaLinea,
    required this.metrosDesdeLinea,
    required this.metrosEnColectivo,
    this.costoTotal,
    this.esFallbackCaminataLarga = false,
  });
  ...
  final double? costoTotal;
  final bool esFallbackCaminataLarga;
}
```
La firma de `LinePlanner.suggest` se conserva idéntica:
```dart
static List<LineSuggestion> suggest({
  required LatLng user,
  required LatLng destino,
  List<Recorrido>? recorridos,
});
```

---

## 4. Constructor de Tabla LUT y Discretización

### 4.1 Fórmula Haversine Segura y Subrogado Peatonal
1. `haversineMeters(LatLng p1, LatLng p2)`:
   - $\Delta\phi = (\phi_2 - \phi_1) \cdot \pi / 180$, $\Delta\lambda = (\lambda_2 - \lambda_1) \cdot \pi / 180$.
   - $a = \sin^2(\Delta\phi / 2) + \cos(\phi_1 \cdot \pi / 180) \cdot \cos(\phi_2 \cdot \pi / 180) \cdot \sin^2(\Delta\lambda / 2)$.
   - `final clampedA = a.clamp(0.0, 1.0);` (evita `NaN` cuando $p_1 = p_2$ por imprecisión de punto flotante).
   - `final c = 2.0 * math.asin(math.sqrt(clampedA).clamp(0.0, 1.0));`
   - Retorna `kEarthRadiusMeters * c` (en metros).
2. `surrogateWalkMeters(p1, p2, tau: 1.25)` retorna `tau * haversineMeters(p1, p2)`.

### 4.2 Discretización Uniforme (`discretizePolyline`)
1. Filtrar puntos con `isValidLatLng(p)`. Si quedan menos de 2 puntos, retornar `const []`.
2. Si `stepMeters <= 0`, retornar copia inmutable de los puntos válidos.
3. Inicializar `nodes = [valid.first]`.
4. Para cada segmento consecutivo $(a, b)$:
   - Calcular `segLen = haversineMeters(a, b)`.
   - Si `segLen <= 1e-6`, omitir segmento degenerado.
   - `final steps = (segLen / stepMeters).ceil();`
   - Para `s = 1 .. steps`, interpolar linealmente con `t = s / steps`:
     $$\phi_s = \phi_a + (\phi_b - \phi_a) \cdot t, \quad \lambda_s = \lambda_a + (\lambda_b - \lambda_a) \cdot t$$
   - Con `s == steps`, el vértice `b` queda preservado exactamente (incluyendo el último vértice del trazado).

### 4.3 Construcción de Progresivas (`DirectedRouteLut.fromPolyline`)
1. `nodes = HybridRouteOptimizer.discretizePolyline(polyline, stepMeters: stepMeters)`.
2. Si `nodes.length < 2`, retornar `DirectedRouteLut` vacío (`nodes: const []`, `cumulativeMeters: const []`).
3. `cumulativeMeters[0] = 0.0`.
4. Para `i = 1 .. nodes.length - 1`:
   $$A[i] = A[i - 1] + \text{haversineMeters}(\text{nodes}[i - 1], \text{nodes}[i])$$
   *(Sin multiplicar por $\tau$, porque la polilínea ya sigue el trazado vial oficial).*

### 4.4 Caché en Memoria (`buildLuts`)
1. Para cada `r` en `recorridos` con `r.activo == true`:
   - Iterar `(sentido, trayecto)` en `r.trayectos`.
   - Si `trayecto.trazado.length < 2`, omitir.
   - Clave determinista: `'${r.id}|${sentido.name}|${stepMeters.toStringAsFixed(1)}|${trayecto.geometria.hashCode}|${trayecto.trazado.length}|${trayecto.trazado.first.latitude},${trayecto.trazado.first.longitude}|${trayecto.trazado.last.latitude},${trayecto.trazado.last.longitude}'`.
   - Si existe en `_lutCache`, reutilizar; si no, construir con `DirectedRouteLut.fromPolyline` y almacenar en `_lutCache`.

---

## 5. Implementación Paso a Paso del Optimizador (Nivel 1 + Relay a Nivel 2)

### 5.1 Flujo Determinista del Nivel 1 (`HybridRouteOptimizer.optimize`)
1. **Validación de entrada:**
   - Si `!isValidLatLng(origin) || !isValidLatLng(destination)`, retornar `PlannedRouteResult` con `status: HybridPlanStatus.noFeasibleRoute`, `directWalkMeters: 0.0`, `directWalkCost: 0.0`, `isLongWalkFallback: false`.
2. **Paso 1 — Línea base caminata directa:**
   - `directWalkMeters = surrogateWalkMeters(origin, destination)`.
   - `directWalkCost = kAlphaWalkAccess * directWalkMeters`.
   - Si `haversineMeters(origin, destination) < 1e-3`, retornar inmediatamente `status: HybridPlanStatus.directWalkPreferred`, `directWalkMeters: 0.0`, `directWalkCost: 0.0`.
3. **Paso 2 — Búsqueda acoplada en memoria sobre todas las cartolas:**
   - Obtener `luts = preloadedRoutes ?? buildLuts(recorridos ?? RecorridosService.instance.publicas)`.
   - Para cada `lut` en `luts` (con `lut.nodes.length >= 2`):
     1. Calcular `walkAccess[i] = surrogateWalkMeters(origin, lut.nodes[i])` para $i = 0 \dots M-1$.
     2. Calcular `walkEgress[j] = surrogateWalkMeters(lut.nodes[j], destination)` para $j = 0 \dots M-1$.
     3. Seleccionar `upCandidates`: ordenar índices $i$ con `walkAccess[i] <= maxWalk` por distancia ascendente y tomar los primeros `topUp` ($6$).
     4. Seleccionar `downCandidates`: ordenar índices $j$ con `walkEgress[j] <= maxWalk` por distancia ascendente y tomar los primeros `topDown` ($6$).
     5. Evaluar el producto cartesiano $(i, j) \in \text{upCandidates} \times \text{downCandidates}$:
        - Si $j \le i$, continuar.
        - `vehMeters = lut.vehicularMeters(i, j)`.
        - Si `vehMeters < minVehicularMeters` ($100.0\text{ m}$), continuar (**restricción estricta DS 212**).
        - `totalCost = kAlphaWalkAccess * walkAccess[i] + kBetaVehicular * vehMeters + kGammaWalkEgress * walkEgress[j]`.
        - Registrar `CandidateTriplet`.
4. **Paso 3 — Política de Fallback:**
   - Si la lista de candidatos queda vacía y `enableFallback && fallbackWalkMeters > maxWalkMeters`:
     - Repetir el Paso 2 con `maxWalk = fallbackWalkMeters` ($2000.0\text{ m}$) y marcar `isFallback = true`.
   - Si sigue vacía, retornar `status: HybridPlanStatus.noFeasibleRoute` con `isLongWalkFallback: isFallback`.
5. **Paso 4 — Ranking y Comparación contra Caminata Directa:**
   - Ordenar candidatos por `totalCost` ascendente (desempatando por `totalWalkMeters` ascendente y luego `vehMeters` ascendente).
   - Construir `rankedByLine`: conservar el primer (mejor) candidato por cada `recorrido.id`.
   - Sea `best = candidates.first`.
   - Si `best.totalCost >= directWalkCost`, retornar `status: HybridPlanStatus.directWalkPreferred` (conservando `best`, `rankedByLine`, `topCandidates` y `isLongWalkFallback`).
   - En otro caso, retornar `status: HybridPlanStatus.optimalFound`.

### 5.2 Flujo del Nivel 2 (`verifyWithValhalla` y `verifyTopKWithValhalla`)
1. `verifyWithValhalla` recibe `(origin, destination, candidate)` y usa `walkRouter ?? Routing.walkingPath` (Valhalla local `ValhallaCosting.pedestrian` $\to$ fallback OSRM):
   - Calcula `walkAccessPath = await router(origin, candidate.boardingNode)`.
   - Si `includeEgress == true`, calcula `walkEgressPath = await router(candidate.alightingNode, destination)`.
   - Extrae `vehicularSegment = List<LatLng>.unmodifiable(candidate.lut.nodes.sublist(candidate.upIndex, candidate.downIndex + 1))`.
   - Retorna `VerifiedHybridRoute`.
2. `verifyTopKWithValhalla` toma hasta `k` candidatos de `perLine ? plan.rankedByLine : plan.topCandidates` y ejecuta `verifyWithValhalla` para cada uno.

### 5.3 Integración en `LinePlanner.suggest`
1. Invoca `HybridRouteOptimizer.optimize(origin: user, destination: destino, recorridos: lineas)`.
2. Si `plan.status != HybridPlanStatus.optimalFound`, retorna `const []`.
3. Para cada `CandidateTriplet c` en `plan.rankedByLine`:
   - Filtra `if (c.rawWalkAccessMeters > maxCaminata || c.rawWalkEgressMeters > maxCaminata) continue;`.
   - Refina localmente el punto exacto de subida y bajada usando `nearestOnPolyline` en la ventana adyacente `[max(0, idx - 1), min(len, idx + 2)]` de `c.lut.nodes`.
   - Calcula las progresivas locales `subidaDesdeInicio = c.lut.cumulativeMeters[upStart] + localSubida.desdeInicio` y `bajadaDesdeInicio = c.lut.cumulativeMeters[downStart] + localBajada.desdeInicio`.
   - Si `bajadaDesdeInicio - subidaDesdeInicio >= HybridRouteOptimizer.kMinVehicularMeters`, usa las coordenadas proyectadas y métricas refinadas; en caso contrario conserva los nodos discretizados de la LUT.
   - Emite `LineSuggestion(..., costoTotal: c.totalCost, esFallbackCaminataLarga: plan.isLongWalkFallback)`.
4. Trunca a `maxSuggestions` ($5$).

---

## 6. Manejo de Casos Borde

| Condición | Comportamiento Exacto |
| :--- | :--- |
| `origin` o `destination` con `NaN` / `Infinity` / fuera de rango | `optimize` retorna `HybridPlanStatus.noFeasibleRoute`, `best: null`, listas vacías, `isLongWalkFallback: false`. No lanza excepción. |
| `origin == destination` ($< 1\text{ mm}$) | `haversineMeters(origin, origin) == 0.0` sin `NaN` (gracias a `clamp(0.0, 1.0)`). `optimize` retorna `HybridPlanStatus.directWalkPreferred`, `directWalkMeters: 0.0`, `directWalkCost: 0.0`. |
| `recorridos` vacío o todas las líneas inactivas / sin trazado válido | `buildLuts` retorna lista vacía; `optimize` retorna `HybridPlanStatus.noFeasibleRoute`. |
| Trayecto con $< 2$ vértices válidos o todos los puntos colapsados | `discretizePolyline` retorna `[]`; la LUT queda con `< 2` nodos y es ignorada sin fallar. |
| Origen y destino separados $< 100\text{ m}$ (o $Z^* \ge Z_{\text{direct}}$) | `optimize` marca `HybridPlanStatus.directWalkPreferred` (`recommendDirectWalk == true`); `LinePlanner.suggest` retorna `[]`. |
| Usuario/destino entre $1000\text{ m}$ y $2000\text{ m}$ (subrogados) de la ruta | Primer pase en $W_{\max}=1000\text{ m}$ resulta vacío; fallback reintenta con $W_{\text{fallback}}=2000\text{ m}$ y retorna `isLongWalkFallback == true`. |
| Usuario/destino a $> 2000\text{ m}$ (subrogados) de toda ruta | Ambos pases vacíos; retorna `HybridPlanStatus.noFeasibleRoute` con `isLongWalkFallback == true` (si `enableFallback == true`). |
| Esquina más cercana al origen viene después de la del destino ($i_{\text{near}} > j_{\text{near}}$) | El par inválido $(i_{\text{near}}, j_{\text{near}})$ se descarta por $j \le i$; el bucle acoplado sobre $K_{\text{up}} \times K_{\text{down}}$ evalúa los demás pares válidos y selecciona la mejor terna factible con $A[j] - A[i] \ge 100\text{ m}$. |
| Valhalla local no disponible (`Routing.walkingPath` retorna `null`) | `VerifiedHybridRoute.walkAccessPath` queda en `null`, `vehicularSegment` sigue disponible desde la LUT y `exactWalkAccessMeters` cae al valor subrogado. |

---

## 7. Plan de Pruebas Unitarias y Comandos de Verificación

### 7.1 Pruebas Obligatorias en `test/hybrid_optimizer_test.dart`
1. **Filtro estricto DS 212:** Verificar que jamás se elige un par con $A[s'] - A[s] < 100\text{ m}$ o sentido inverso ($j \le i$).
2. **Acoplamiento de 3 tramos:** Verificar con un recorrido en forma de U/herradura que el optimizador descarta la esquina más cercana al origen si está después del destino o empeora $Z$, y selecciona el par acoplado $(s, s')$ de menor costo global $Z$.
3. **Discretización de tramo recto largo:** Verificar que una polilínea de 2 vértices separados $\approx 500\text{ m}$ genera nodos intermedios cada $\le 60.0\text{ m}$, conserva extremos y mantiene progresivas `cumulativeMeters` consistentes con Haversine.
4. **Caminata directa:** Origen y destino a $\approx 150\text{ m}$ $\implies$ `recommendDirectWalk == true`, `status == HybridPlanStatus.directWalkPreferred`, $Z^* \ge Z_{\text{direct}}$, y `LinePlanner.suggest` retorna `[]`.
5. **Fallback $> 1000\text{ m}$:** Usuario a $\approx 1300\text{ m}$ subrogados de la ruta más cercana $\implies$ activa `isLongWalkFallback == true` con `status == HybridPlanStatus.optimalFound`, sin excepciones ni nulos inesperados.
6. **Precisión Haversine:** Verificar `haversineMeters` entre Estación Quilpué (`-33.0456, -71.4450`) y Hospital de Quilpué (`-33.0497, -71.4307`) y verificar $p_1 = p_2 \implies 0.0$ exacto (sin `NaN`).
7. **Relay Nivel 1 $\to$ Nivel 2 (`verifyWithValhalla`):** Verificar con un enrutador peatonal inyectado que el Nivel 2 consulta únicamente el acceso (y opcionalmente el egreso) y conserva el sub-tramo vehicular exacto de la LUT sin invocar Valhalla en auto.

### 7.2 Comandos de Verificación Final
```powershell
flutter analyze lib/services/hybrid_route_optimizer.dart lib/services/line_planner.dart test/hybrid_optimizer_test.dart
flutter test test/hybrid_optimizer_test.dart test/planner_test.dart
flutter test
```
