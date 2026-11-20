import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import 'package:taxi1/models/recorrido.dart';
import 'package:taxi1/models/route_path.dart';
import 'package:taxi1/services/recorridos_service.dart';
import 'package:taxi1/services/routing.dart';
import 'package:taxi1/utils/polyline.dart';

/// Tabla de progresivas precalculadas (LUT) en memoria para una cartola dirigida
/// `(recorrido, sentido)`.
class DirectedRouteLut {
  /// Crea una tabla LUT con [nodes] discretizados y sus distancias acumuladas
  /// [cumulativeMeters] en metros siguiendo el sentido real de circulación.
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

  /// Largo total del trazado discretizado, en metros.
  double get totalLengthMeters =>
      cumulativeMeters.isEmpty ? 0.0 : cumulativeMeters.last;

  /// Distancia vehicular en metros entre el nodo de subida [upIndex] y el de
  /// bajada [downIndex] sobre la cartola oficial en tiempo constante O(1).
  double vehicularMeters(int upIndex, int downIndex) =>
      cumulativeMeters[downIndex] - cumulativeMeters[upIndex];

  /// Construye la LUT remuestreando [polyline] a paso uniforme [stepMeters] y
  /// calculando las progresivas acumuladas mediante Haversine (sin factor tau).
  factory DirectedRouteLut.fromPolyline({
    required Recorrido recorrido,
    required Sentido sentido,
    required List<LatLng> polyline,
    double stepMeters = HybridRouteOptimizer.kDiscretizationStepMeters,
  }) {
    final nodes = HybridRouteOptimizer.discretizePolyline(
      polyline,
      stepMeters: stepMeters,
    );
    if (nodes.length < 2) {
      return DirectedRouteLut(
        recorrido: recorrido,
        sentido: sentido,
        nodes: const [],
        cumulativeMeters: const [],
      );
    }

    final cumulative = List<double>.filled(nodes.length, 0.0);
    for (var i = 1; i < nodes.length; i++) {
      cumulative[i] =
          cumulative[i - 1] +
          HybridRouteOptimizer.haversineMeters(nodes[i - 1], nodes[i]);
    }

    return DirectedRouteLut(
      recorrido: recorrido,
      sentido: sentido,
      nodes: nodes,
      cumulativeMeters: List<double>.unmodifiable(cumulative),
    );
  }
}

/// Terna candidata evaluada en Nivel 1: subida, bajada y cartola dirigida.
class CandidateTriplet {
  /// Crea una terna candidata con sus métricas subrogadas y costo total [totalCost].
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

  /// Distancia subrogada peatonal de acceso: `tau * haversine(u, s_i)`.
  final double walkAccessMeters;

  /// Distancia vehicular sobre la cartola oficial: `A[j] - A[i]`.
  final double vehMeters;

  /// Distancia subrogada peatonal de egreso: `tau * haversine(s_j, d)`.
  final double walkEgressMeters;

  /// Costo objetivo acoplado:
  /// `Z = alpha * D_walk(u, s_i) + beta * D_veh(i, j) + gamma * D_walk(s_j, d)`.
  final double totalCost;

  Recorrido get recorrido => lut.recorrido;
  Sentido get sentido => lut.sentido;
  LatLng get boardingNode => lut.nodes[upIndex];
  LatLng get alightingNode => lut.nodes[downIndex];

  /// Suma de caminata subrogada de acceso y egreso, en metros.
  double get totalWalkMeters => walkAccessMeters + walkEgressMeters;

  /// Distancia geodésica directa de acceso (sin factor de tortuosidad `tau`).
  double get rawWalkAccessMeters =>
      walkAccessMeters / HybridRouteOptimizer.kTauTortuosity;

  /// Distancia geodésica directa de egreso (sin factor de tortuosidad `tau`).
  double get rawWalkEgressMeters =>
      walkEgressMeters / HybridRouteOptimizer.kTauTortuosity;
}

/// Estado resultante de la exploración en Nivel 1.
enum HybridPlanStatus {
  /// Existe al menos una terna en colectivo que supera a caminar directo.
  optimalFound,

  /// Caminar directo tiene costo menor o igual que la mejor terna en colectivo.
  directWalkPreferred,

  /// No hay ternas factibles ni siquiera tras la política de fallback.
  noFeasibleRoute,
}

/// Resultado completo del Nivel 1 del optimizador híbrido.
class PlannedRouteResult {
  /// Crea un resultado de planificación para el origen y destino consultados.
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

  /// `true` cuando caminar directo es mejor o equivalente a tomar colectivo.
  bool get recommendDirectWalk =>
      status == HybridPlanStatus.directWalkPreferred;

  /// `true` cuando existe una recomendación óptima en colectivo.
  bool get hasRoute =>
      status == HybridPlanStatus.optimalFound && best != null;
}

/// Resultado verificado en Nivel 2 (Valhalla/OSRM peatonal + tramo oficial LUT).
class VerifiedHybridRoute {
  /// Crea una ruta verificada combinando geometría peatonal real y tramo vehicular.
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

  /// Distancia real a pie hasta la subida, o subrogado si el enrutador falló.
  double get exactWalkAccessMeters =>
      walkAccessPath?.distanceMeters ?? candidate.walkAccessMeters;

  /// Distancia real a pie desde la bajada, o subrogado si no se consultó o falló.
  double get exactWalkEgressMeters =>
      walkEgressPath?.distanceMeters ?? candidate.walkEgressMeters;
}

/// Optimizador Híbrido Cooperativo en 2 Niveles (Subrogados en RAM + Oráculo
/// Valhalla) para planificación puerta a puerta en colectivos de cartola DS 212.
abstract final class HybridRouteOptimizer {
  static const double kAlphaWalkAccess = 2.0;
  static const double kBetaVehicular = 1.0;
  static const double kGammaWalkEgress = 2.0;
  static const double kTauTortuosity = 1.25;
  static const double kEarthRadiusMeters = 6371000.0;
  static const double kMinVehicularMeters = 100.0;
  static const double kMaxWalkMeters = 1000.0;
  static const double kFallbackWalkMeters = 2000.0;
  static const double kDiscretizationStepMeters = 60.0;
  static const int kTopUpCandidates = 6;
  static const int kTopDownCandidates = 6;

  static final Map<String, DirectedRouteLut> _lutCache = {};

  /// Distancia geodésica esférica en metros mediante fórmula de Haversine.
  ///
  /// Acota `a` en `[0.0, 1.0]` antes de `sqrt`/`asin` para evitar `NaN` por
  /// errores de redondeo cuando [p1] y [p2] coinciden.
  static double haversineMeters(LatLng p1, LatLng p2) {
    final lat1Rad = p1.latitude * math.pi / 180.0;
    final lat2Rad = p2.latitude * math.pi / 180.0;
    final dLat = (p2.latitude - p1.latitude) * math.pi / 180.0;
    final dLon = (p2.longitude - p1.longitude) * math.pi / 180.0;

    final sinDLat = math.sin(dLat / 2.0);
    final sinDLon = math.sin(dLon / 2.0);
    final a =
        sinDLat * sinDLat +
        math.cos(lat1Rad) * math.cos(lat2Rad) * sinDLon * sinDLon;
    final clampedA = a.clamp(0.0, 1.0);
    final c = 2.0 * math.asin(math.sqrt(clampedA).clamp(0.0, 1.0));
    return kEarthRadiusMeters * c;
  }

  /// Subrogado peatonal `D_walk(p1, p2) = tau * haversine(p1, p2)`.
  static double surrogateWalkMeters(
    LatLng p1,
    LatLng p2, {
    double tau = kTauTortuosity,
  }) => tau * haversineMeters(p1, p2);

  /// Remuestrea [polyline] con interpolación lineal uniforme a pasos menores o
  /// iguales a [stepMeters], preservando el primer y último vértice válido.
  static List<LatLng> discretizePolyline(
    List<LatLng> polyline, {
    double stepMeters = kDiscretizationStepMeters,
  }) {
    final valid = polyline.where(isValidLatLng).toList(growable: false);
    if (valid.length < 2) return const [];
    if (stepMeters <= 0) return List<LatLng>.unmodifiable(valid);

    final nodes = <LatLng>[valid.first];
    for (var k = 1; k < valid.length; k++) {
      final a = valid[k - 1];
      final b = valid[k];
      final segLen = haversineMeters(a, b);
      if (segLen <= 1e-6) continue;

      final steps = (segLen / stepMeters).ceil();
      for (var s = 1; s <= steps; s++) {
        final t = s / steps;
        nodes.add(
          LatLng(
            a.latitude + (b.latitude - a.latitude) * t,
            a.longitude + (b.longitude - a.longitude) * t,
          ),
        );
      }
    }
    return List<LatLng>.unmodifiable(nodes);
  }

  /// Construye (o recupera desde caché en RAM) las tablas LUT dirigidas para
  /// cada sentido válido de los [recorridos] activos.
  static List<DirectedRouteLut> buildLuts(
    Iterable<Recorrido> recorridos, {
    double stepMeters = kDiscretizationStepMeters,
  }) {
    final luts = <DirectedRouteLut>[];
    for (final r in recorridos) {
      if (!r.activo) continue;
      for (final (sentido, trayecto) in r.trayectos) {
        if (trayecto.trazado.length < 2) continue;

        final geomKey = trayecto.geometria.isNotEmpty
            ? '${trayecto.geometria.length}:${trayecto.geometria.hashCode}'
            : 'pts:${Object.hashAll(trayecto.trazado)}';
        final key =
            '${r.id}|${sentido.name}|${stepMeters.toStringAsFixed(1)}|$geomKey|'
            '${trayecto.trazado.length}|'
            '${trayecto.trazado.first.latitude},${trayecto.trazado.first.longitude}|'
            '${trayecto.trazado.last.latitude},${trayecto.trazado.last.longitude}';

        var lut = _lutCache[key];
        if (lut == null) {
          if (_lutCache.length >= 128) _lutCache.clear();
          lut = DirectedRouteLut.fromPolyline(
            recorrido: r,
            sentido: sentido,
            polyline: trayecto.trazado,
            stepMeters: stepMeters,
          );
          if (lut.nodes.length >= 2) {
            _lutCache[key] = lut;
          }
        } else if (!identical(lut.recorrido, r)) {
          // Conserva los arreglos precalculados en RAM actualizando la
          // referencia del objeto Recorrido en caché si cambiaron sus metadatos.
          lut = DirectedRouteLut(
            recorrido: r,
            sentido: sentido,
            nodes: lut.nodes,
            cumulativeMeters: lut.cumulativeMeters,
          );
          _lutCache[key] = lut;
        }

        if (lut.nodes.length >= 2) {
          luts.add(lut);
        }
      }
    }
    return luts;
  }

  /// Limpia la caché interna de tablas LUT (uso exclusivo en pruebas).
  @visibleForTesting
  static void clearCache() => _lutCache.clear();

  /// Ejecuta el Nivel 1 en RAM evaluando todas las cartolas dirigidas y
  /// acoplando los tramos de acceso, viaje vehicular DS 212 y egreso.
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
  }) {
    if (!isValidLatLng(origin) || !isValidLatLng(destination)) {
      return const PlannedRouteResult(
        status: HybridPlanStatus.noFeasibleRoute,
        best: null,
        rankedByLine: [],
        topCandidates: [],
        directWalkMeters: 0.0,
        directWalkCost: 0.0,
        isLongWalkFallback: false,
      );
    }

    if (haversineMeters(origin, destination) < 1e-3) {
      return const PlannedRouteResult(
        status: HybridPlanStatus.directWalkPreferred,
        best: null,
        rankedByLine: [],
        topCandidates: [],
        directWalkMeters: 0.0,
        directWalkCost: 0.0,
        isLongWalkFallback: false,
      );
    }

    final directWalkMeters = surrogateWalkMeters(origin, destination);
    final directWalkCost = kAlphaWalkAccess * directWalkMeters;
    final luts =
        preloadedRoutes ??
        buildLuts(recorridos ?? RecorridosService.instance.publicas);

    var isFallback = false;
    var candidates = _searchCandidates(
      origin: origin,
      destination: destination,
      luts: luts,
      maxWalk: maxWalkMeters,
      minVehicularMeters: minVehicularMeters,
      topUp: topUp,
      topDown: topDown,
    );

    if (candidates.isEmpty &&
        enableFallback &&
        fallbackWalkMeters > maxWalkMeters) {
      isFallback = true;
      candidates = _searchCandidates(
        origin: origin,
        destination: destination,
        luts: luts,
        maxWalk: fallbackWalkMeters,
        minVehicularMeters: minVehicularMeters,
        topUp: topUp,
        topDown: topDown,
      );
    }

    if (candidates.isEmpty) {
      return PlannedRouteResult(
        status: HybridPlanStatus.noFeasibleRoute,
        best: null,
        rankedByLine: const [],
        topCandidates: const [],
        directWalkMeters: directWalkMeters,
        directWalkCost: directWalkCost,
        isLongWalkFallback: isFallback,
      );
    }

    candidates.sort((a, b) {
      final cmpCost = a.totalCost.compareTo(b.totalCost);
      if (cmpCost != 0) return cmpCost;
      final cmpWalk = a.totalWalkMeters.compareTo(b.totalWalkMeters);
      if (cmpWalk != 0) return cmpWalk;
      return a.vehMeters.compareTo(b.vehMeters);
    });

    final seenLineIds = <String>{};
    final rankedByLine = <CandidateTriplet>[];
    for (final c in candidates) {
      if (seenLineIds.add(c.recorrido.id)) {
        rankedByLine.add(c);
      }
    }

    final best = candidates.first;
    final status = best.totalCost >= directWalkCost
        ? HybridPlanStatus.directWalkPreferred
        : HybridPlanStatus.optimalFound;

    return PlannedRouteResult(
      status: status,
      best: best,
      rankedByLine: List<CandidateTriplet>.unmodifiable(rankedByLine),
      topCandidates: List<CandidateTriplet>.unmodifiable(candidates),
      directWalkMeters: directWalkMeters,
      directWalkCost: directWalkCost,
      isLongWalkFallback: isFallback,
    );
  }

  static List<CandidateTriplet> _searchCandidates({
    required LatLng origin,
    required LatLng destination,
    required List<DirectedRouteLut> luts,
    required double maxWalk,
    required double minVehicularMeters,
    required int topUp,
    required int topDown,
  }) {
    if (topUp <= 0 || topDown <= 0) return [];
    final results = <CandidateTriplet>[];

    for (final lut in luts) {
      final count = lut.nodes.length;
      if (count < 2) continue;

      final walkAccess = List<double>.filled(count, 0.0);
      final walkEgress = List<double>.filled(count, 0.0);
      final upIndices = <int>[];
      final downIndices = <int>[];

      for (var i = 0; i < count; i++) {
        final node = lut.nodes[i];
        final dAccess = surrogateWalkMeters(origin, node);
        walkAccess[i] = dAccess;
        if (dAccess <= maxWalk) upIndices.add(i);

        final dEgress = surrogateWalkMeters(node, destination);
        walkEgress[i] = dEgress;
        if (dEgress <= maxWalk) downIndices.add(i);
      }

      if (upIndices.isEmpty || downIndices.isEmpty) continue;

      upIndices.sort((a, b) {
        final cmp = walkAccess[a].compareTo(walkAccess[b]);
        return cmp != 0 ? cmp : a.compareTo(b);
      });
      downIndices.sort((a, b) {
        final cmp = walkEgress[a].compareTo(walkEgress[b]);
        return cmp != 0 ? cmp : a.compareTo(b);
      });

      final upCandidates = upIndices.take(topUp).toList(growable: false);
      final downCandidates = downIndices.take(topDown).toList(growable: false);
      final addedPairs = <(int, int)>{};

      void addCandidatePair(int i, int j) {
        if (j <= i) return;
        final vehMeters = lut.vehicularMeters(i, j);
        if (vehMeters < minVehicularMeters) return;
        if (!addedPairs.add((i, j))) return;

        final access = walkAccess[i];
        final egress = walkEgress[j];
        final totalCost =
            kAlphaWalkAccess * access +
            kBetaVehicular * vehMeters +
            kGammaWalkEgress * egress;

        results.add(
          CandidateTriplet(
            lut: lut,
            upIndex: i,
            downIndex: j,
            walkAccessMeters: access,
            vehMeters: vehMeters,
            walkEgressMeters: egress,
            totalCost: totalCost,
          ),
        );
      }

      for (final i in upCandidates) {
        for (final j in downCandidates) {
          addCandidatePair(i, j);
        }
      }

      // Barrido exacto O(N) con ventana de mínimo prefijo sobre la función
      // separable Z(i, j) = (alpha * access[i] - beta * A[i]) + (gamma * egress[j] + beta * A[j]).
      // Garantiza encontrar siempre el óptimo global exacto incluso en curvas
      // con alta densidad de vértices donde topUp/topDown se concentran.
      final validUpSorted = [
        for (var i = 0; i < count; i++)
          if (walkAccess[i] <= maxWalk) i,
      ];
      final validDownSorted = [
        for (var j = 0; j < count; j++)
          if (walkEgress[j] <= maxWalk) j,
      ];
      var ptr = 0;
      int? bestPrefixUp;
      var bestPrefixTerm = double.infinity;
      int? globalBestI;
      int? globalBestJ;
      var globalBestCost = double.infinity;

      for (final j in validDownSorted) {
        while (ptr < validUpSorted.length) {
          final i = validUpSorted[ptr];
          if (i >= j || lut.vehicularMeters(i, j) < minVehicularMeters) break;
          final prefixTerm =
              kAlphaWalkAccess * walkAccess[i] -
              kBetaVehicular * lut.cumulativeMeters[i];
          if (prefixTerm < bestPrefixTerm) {
            bestPrefixTerm = prefixTerm;
            bestPrefixUp = i;
          }
          ptr++;
        }
        if (bestPrefixUp != null) {
          final cost =
              bestPrefixTerm +
              kBetaVehicular * lut.cumulativeMeters[j] +
              kGammaWalkEgress * walkEgress[j];
          if (cost < globalBestCost) {
            globalBestCost = cost;
            globalBestI = bestPrefixUp;
            globalBestJ = j;
          }
        }
      }
      if (globalBestI != null && globalBestJ != null) {
        addCandidatePair(globalBestI, globalBestJ);
      }
    }

    return results;
  }

  /// Ejecuta el Nivel 2 (Relay a Valhalla / OSRM peatonal) para una terna
  /// ganadora [candidate] y extrae el sub-tramo vehicular exacto de la cartola.
  static Future<VerifiedHybridRoute> verifyWithValhalla({
    required LatLng origin,
    required LatLng destination,
    required CandidateTriplet candidate,
    bool includeEgress = false,
    Future<RoutePath?> Function(LatLng from, LatLng to)? walkRouter,
  }) async {
    final router = walkRouter ?? Routing.walkingPath;
    final accessPath = await router(origin, candidate.boardingNode);
    final egressPath = includeEgress
        ? await router(candidate.alightingNode, destination)
        : null;
    final vehicularSegment = List<LatLng>.unmodifiable(
      candidate.lut.nodes.sublist(candidate.upIndex, candidate.downIndex + 1),
    );

    return VerifiedHybridRoute(
      candidate: candidate,
      walkAccessPath: accessPath,
      vehicularSegment: vehicularSegment,
      walkEgressPath: egressPath,
    );
  }

  /// Verifica en Nivel 2 hasta [k] ternas principales del [plan] (por línea o
  /// globales según [perLine]).
  static Future<List<VerifiedHybridRoute>> verifyTopKWithValhalla({
    required LatLng origin,
    required LatLng destination,
    required PlannedRouteResult plan,
    int k = 3,
    bool perLine = true,
    bool includeEgress = false,
    Future<RoutePath?> Function(LatLng from, LatLng to)? walkRouter,
  }) async {
    if (k <= 0) return const [];
    final source = perLine ? plan.rankedByLine : plan.topCandidates;
    final selected = source.take(k);
    final verified = <VerifiedHybridRoute>[];
    for (final candidate in selected) {
      verified.add(
        await verifyWithValhalla(
          origin: origin,
          destination: destination,
          candidate: candidate,
          includeEgress: includeEgress,
          walkRouter: walkRouter,
        ),
      );
    }
    return List<VerifiedHybridRoute>.unmodifiable(verified);
  }
}
