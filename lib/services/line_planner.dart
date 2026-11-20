import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import 'package:taxi1/config/garita_config.dart';
import 'package:taxi1/models/colectivo_activo.dart';
import 'package:taxi1/models/recorrido.dart';
import 'package:taxi1/models/route_path.dart';
import 'package:taxi1/services/hybrid_route_optimizer.dart';
import 'package:taxi1/services/recorridos_service.dart';
import 'package:taxi1/utils/polyline.dart';

/// Una forma de llegar a un destino en colectivo: qué línea tomar, en qué
/// sentido, dónde subirse y dónde bajarse.
class LineSuggestion {
  const LineSuggestion({
    required this.recorrido,
    required this.sentido,
    required this.subida,
    required this.bajada,
    required this.metrosHastaLinea,
    required this.metrosDesdeLinea,
    required this.metrosEnColectivo,
    this.metrosSubida = 0.0,
    this.costoTotal,
    this.esFallbackCaminataLarga = false,
    this.candidate,
  });

  final Recorrido recorrido;
  final Sentido sentido;

  /// Punto de la línea donde el pasajero aborda el colectivo.
  final LatLng subida;

  /// Punto de la línea donde el pasajero desciende del colectivo.
  final LatLng bajada;

  /// Distancia estimada en línea recta desde el origen hasta la subida.
  final double metrosHastaLinea;

  /// Distancia estimada en línea recta desde la bajada hasta el destino.
  final double metrosDesdeLinea;

  /// Distancia recorrida a bordo del colectivo siguiendo la cartola oficial.
  final double metrosEnColectivo;

  /// Progresiva en metros desde el inicio del trayecto hasta la [subida].
  /// Junto con [metrosBajada] delimita el tramo vehicular resaltado en el mapa.
  final double metrosSubida;

  /// Progresiva en metros desde el inicio del trayecto hasta la [bajada].
  double get metrosBajada => metrosSubida + metrosEnColectivo;

  /// Costo objetivo acoplado `Z` calculado en el Nivel 1 de [HybridRouteOptimizer].
  final double? costoTotal;

  /// `true` cuando la sugerencia proviene del radio extendido de búsqueda (> 1000 m).
  final bool esFallbackCaminataLarga;

  /// Terna evaluada en Nivel 1 que alimenta el Relay en cascada hacia Nivel 2.
  final CandidateTriplet? candidate;

  /// Suma de los tramos a pie de acceso y egreso, en metros.
  double get metrosAPie => metrosHastaLinea + metrosDesdeLinea;
}

/// Métricas de proximidad y flota activa de un [Recorrido] para su
/// priorización en la pestaña Líneas.
class LineaPriorizada {
  const LineaPriorizada({
    required this.linea,
    required this.metros,
    required this.enServicio,
    required this.metrosColectivoMasCercano,
  });

  final Recorrido linea;

  /// Distancia mínima desde la ubicación del pasajero al trazado (`null` sin GPS).
  final double? metros;

  /// Cantidad de colectivos en turno asignados a esta línea.
  final int enServicio;

  /// Distancia al colectivo activo más cercano de esta línea (`null` sin GPS o sin unidades).
  final double? metrosColectivoMasCercano;
}

/// Estrategia de ordenamiento para priorizar líneas en el catálogo.
typedef LineRankingStrategy =
    int Function(LineaPriorizada a, LineaPriorizada b);

/// Planificador de viajes puerta a puerta y priorizador de líneas por cercanía.
///
/// Coordina la arquitectura híbrida en cascada (Relay Nivel 1 -> Nivel 2):
/// 1. Nivel 1 ([suggest]): evalúa todas las cartolas dirigidas en RAM mediante
///    modelos subrogados ([HybridRouteOptimizer.optimize]) acoplando caminata
///    de acceso, tramo vehicular oficial (D.S. 212) y caminata de egreso.
/// 2. Nivel 2 ([verifyWithValhalla] / [verifyTopKWithValhalla]): verifica en
///    cascada los candidatos ganadores sobre la red vial peatonal real
///    (Valhalla local u OSRM de respaldo).
abstract final class LinePlanner {
  /// Cantidad máxima de sugerencias presentadas al pasajero.
  static const int maxSuggestions = 5;

  /// Distancia máxima en línea recta permitida para cada tramo de caminata.
  static const double maxCaminata = 1500;

  /// Distancia mínima recorrida en colectivo para considerar válida la opción.
  static const double minEnColectivo =
      HybridRouteOptimizer.kMinVehicularMeters;

  /// Estrategia de ranking activa para la pestaña Líneas.
  static LineRankingStrategy rankingStrategy = compararPorProximidad;

  /// Compara dos líneas priorizando de la más cercana a la más lejana a la
  /// ubicación del pasajero (agrupadas al metro entero para garantizar orden
  /// débil estricto transitivo), desempatando por colectivo activo más cercano
  /// y cantidad de unidades en servicio.
  static int compararPorProximidad(LineaPriorizada a, LineaPriorizada b) {
    final ma = a.metros;
    final mb = b.metros;
    if (ma != null || mb != null) {
      if (ma == null) return 1;
      if (mb == null) return -1;
      final cmpDist = ma.round().compareTo(mb.round());
      if (cmpDist != 0) return cmpDist;

      final ca = a.metrosColectivoMasCercano ?? double.infinity;
      final cb = b.metrosColectivoMasCercano ?? double.infinity;
      final cmpColectivo = ca.compareTo(cb);
      if (cmpColectivo != 0) return cmpColectivo;
    }
    final cmpServicio = b.enServicio.compareTo(a.enServicio);
    if (cmpServicio != 0) return cmpServicio;
    return a.linea.nombre.compareTo(b.linea.nombre);
  }

  /// Calcula las métricas de cercanía y ordena [lineas] según [strategy] (o
  /// [rankingStrategy] por omisión).
  static List<LineaPriorizada> priorizarLineas({
    required List<Recorrido> lineas,
    required List<ColectivoActivo> colectivos,
    LatLng? posicion,
    LineRankingStrategy? strategy,
  }) {
    const distance = Distance();
    final validos = colectivos
        .where((c) => !(c.latitud == 0.0 && c.longitud == 0.0))
        .toList(growable: false);

    final resultado = <LineaPriorizada>[];
    for (final linea in lineas) {
      final deLinea = validos
          .where((c) => c.recorridoId == linea.id)
          .toList(growable: false);
      double? masCercano;
      if (posicion != null && deLinea.isNotEmpty) {
        for (final c in deLinea) {
          final d = distance.as(
            LengthUnit.Meter,
            posicion,
            LatLng(c.latitud, c.longitud),
          );
          if (masCercano == null || d < masCercano) {
            masCercano = d;
          }
        }
      }
      resultado.add(
        LineaPriorizada(
          linea: linea,
          metros: posicion == null ? null : metrosHasta(linea, posicion),
          enServicio: deLinea.length,
          metrosColectivoMasCercano: masCercano,
        ),
      );
    }

    resultado.sort(strategy ?? rankingStrategy);
    return resultado;
  }

  /// Ejecuta el Nivel 1 del optimizador híbrido ([HybridRouteOptimizer.optimize])
  /// para recomendar hasta [maxSuggestions] líneas entre [user] y [destino],
  /// ordenadas por menor costo objetivo acoplado `Z` (a lo más una por línea,
  /// en su sentido óptimo).
  ///
  /// Por omisión evalúa las líneas públicas ([RecorridosService.publicas]): las
  /// activas de la garita [kGaritaPublica]. Si caminar directo tiene menor o
  /// igual costo que tomar colectivo, devuelve una lista vacía.
  static List<LineSuggestion> suggest({
    required LatLng user,
    required LatLng destino,
    List<Recorrido>? recorridos,
  }) {
    final lineas = recorridos ?? RecorridosService.instance.publicas;
    final plan = HybridRouteOptimizer.optimize(
      origin: user,
      destination: destino,
      recorridos: lineas,
    );
    if (plan.status != HybridPlanStatus.optimalFound) {
      return const [];
    }

    final resultado = <LineSuggestion>[];
    for (final c in plan.rankedByLine) {
      if (c.rawWalkAccessMeters > maxCaminata ||
          c.rawWalkEgressMeters > maxCaminata) {
        continue;
      }

      final nodes = c.lut.nodes;
      final upStart = math.max(0, c.upIndex - 1);
      final upEnd = math.min(nodes.length, c.upIndex + 2);
      final downStart = math.max(0, c.downIndex - 1);
      final downEnd = math.min(nodes.length, c.downIndex + 2);

      final localSubida = nearestOnPolyline(
        nodes.sublist(upStart, upEnd),
        user,
      );
      final localBajada = nearestOnPolyline(
        nodes.sublist(downStart, downEnd),
        destino,
      );

      var subida = c.boardingNode;
      var bajada = c.alightingNode;
      var metrosHastaLinea = c.rawWalkAccessMeters;
      var metrosDesdeLinea = c.rawWalkEgressMeters;
      var metrosEnColectivo = c.vehMeters;
      var metrosSubida = c.lut.cumulativeMeters[c.upIndex];

      if (localSubida != null && localBajada != null) {
        final refinedVeh =
            (c.lut.cumulativeMeters[downStart] + localBajada.desdeInicio) -
            (c.lut.cumulativeMeters[upStart] + localSubida.desdeInicio);
        if (refinedVeh >= minEnColectivo) {
          subida = localSubida.punto;
          bajada = localBajada.punto;
          metrosHastaLinea = localSubida.metros;
          metrosDesdeLinea = localBajada.metros;
          metrosEnColectivo = refinedVeh;
          metrosSubida =
              c.lut.cumulativeMeters[upStart] + localSubida.desdeInicio;
        }
      }

      // Refina las progresivas sobre el trazado original sólo cuando coincide
      // con la pasada seleccionada en la LUT (evita que nearestOnPolyline
      // colapse rutas con bucles o retornos a su primera pasada).
      final trazadoOriginal = c.recorrido.trayecto(c.sentido)?.trazado;
      final pasoSubida = trazadoOriginal != null
          ? nearestOnPolyline(trazadoOriginal, subida)
          : null;
      final pasoBajada = trazadoOriginal != null
          ? nearestOnPolyline(trazadoOriginal, bajada)
          : null;
      if (pasoSubida != null && pasoBajada != null) {
        final tramosOriginal = pasoBajada.desdeInicio - pasoSubida.desdeInicio;
        final consistenteConLut =
            (tramosOriginal - metrosEnColectivo).abs() <=
            HybridRouteOptimizer.kDiscretizationStepMeters * 2;
        if (tramosOriginal >= minEnColectivo && consistenteConLut) {
          metrosSubida = pasoSubida.desdeInicio;
          metrosEnColectivo = tramosOriginal;
        }
      }

      resultado.add(
        LineSuggestion(
          recorrido: c.recorrido,
          sentido: c.sentido,
          subida: subida,
          bajada: bajada,
          metrosHastaLinea: metrosHastaLinea,
          metrosDesdeLinea: metrosDesdeLinea,
          metrosEnColectivo: metrosEnColectivo,
          metrosSubida: metrosSubida,
          costoTotal: c.totalCost,
          esFallbackCaminataLarga: plan.isLongWalkFallback,
          candidate: c,
        ),
      );
      if (resultado.length >= maxSuggestions) break;
    }

    return resultado;
  }

  /// Ejecuta el Relay en cascada Nivel 1 -> Nivel 2 para la [suggestion]
  /// seleccionada, consultando al oráculo vial (Valhalla/OSRM o [walkRouter])
  /// sobre el tramo peatonal y extrayendo el segmento vehicular de la LUT.
  static Future<VerifiedHybridRoute?> verifyWithValhalla({
    required LatLng user,
    required LatLng destino,
    required LineSuggestion suggestion,
    bool includeEgress = false,
    Future<RoutePath?> Function(LatLng from, LatLng to)? walkRouter,
  }) async {
    var candidate = suggestion.candidate;
    if (candidate == null) {
      final plan = HybridRouteOptimizer.optimize(
        origin: user,
        destination: destino,
        recorridos: [suggestion.recorrido],
      );
      candidate = plan.best;
    }
    if (candidate == null) return null;

    return HybridRouteOptimizer.verifyWithValhalla(
      origin: user,
      destination: destino,
      candidate: candidate,
      includeEgress: includeEgress,
      walkRouter: walkRouter,
    );
  }

  /// Ejecuta en cascada Nivel 1 + Nivel 2 ([HybridRouteOptimizer.verifyTopKWithValhalla])
  /// verificando las mejores [k] sugerencias con el enrutador peatonal.
  static Future<List<VerifiedHybridRoute>> verifyTopKWithValhalla({
    required LatLng user,
    required LatLng destino,
    List<Recorrido>? recorridos,
    int k = 3,
    bool includeEgress = false,
    Future<RoutePath?> Function(LatLng from, LatLng to)? walkRouter,
  }) {
    final lineas = recorridos ?? RecorridosService.instance.publicas;
    final plan = HybridRouteOptimizer.optimize(
      origin: user,
      destination: destino,
      recorridos: lineas,
    );
    return HybridRouteOptimizer.verifyTopKWithValhalla(
      origin: user,
      destination: destino,
      plan: plan,
      k: k,
      includeEgress: includeEgress,
      walkRouter: walkRouter,
    );
  }

  /// Distancia mínima en metros desde [p] a cualquiera de los sentidos de
  /// [linea], o `null` si no tiene trazado.
  static double? metrosHasta(Recorrido linea, LatLng p) {
    double? mejor;
    for (final (_, trayecto) in linea.trayectos) {
      final cerca = nearestOnPolyline(trayecto.trazado, p);
      if (cerca != null && (mejor == null || cerca.metros < mejor)) {
        mejor = cerca.metros;
      }
    }
    return mejor;
  }
}
