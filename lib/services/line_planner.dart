import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import 'package:taxi1/config/garita_config.dart';
import 'package:taxi1/models/colectivo_activo.dart';
import 'package:taxi1/models/recorrido.dart';
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
    this.costoTotal,
    this.esFallbackCaminataLarga = false,
  });

  final Recorrido recorrido;
  final Sentido sentido;

  /// El punto de la línea más cercano al usuario: ahí se le hace la seña.
  final LatLng subida;

  /// El punto de la línea más cercano al destino: ahí se pide la bajada.
  final LatLng bajada;

  /// Lo que camina el usuario hasta la línea, en línea recta.
  final double metrosHastaLinea;

  /// Lo que camina desde la bajada hasta el destino, en línea recta.
  final double metrosDesdeLinea;

  /// Lo que recorre arriba del colectivo, siguiendo la línea.
  final double metrosEnColectivo;

  /// Costo objetivo $Z$ calculado por [HybridRouteOptimizer].
  final double? costoTotal;

  /// `true` cuando la sugerencia proviene del radio de fallback (> 1000 m).
  final bool esFallbackCaminataLarga;

  /// Total a pie, que es por lo que se ordenan las sugerencias.
  double get metrosAPie => metrosHastaLinea + metrosDesdeLinea;
}

/// Métricas de proximidad y flota activa de un [Recorrido] para su
/// priorización en la pestaña Recorridos.
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

/// Punto de extensión desacoplado para ordenar recorridos (permite conectar un
/// algoritmo de recorrido óptimo sin acoplar la interfaz).
typedef LineRankingStrategy =
    int Function(LineaPriorizada a, LineaPriorizada b);

/// Elige qué colectivo tomar para llegar a un destino y prioriza las líneas por
/// cercanía al pasajero.
///
/// Los colectivos no tienen paraderos: paran donde se les hace la seña. Así
/// que para cada línea y cada sentido se busca el punto del recorrido más
/// cercano al usuario (la subida) y el más cercano al destino (la bajada), y
/// sólo sirve si la bajada viene **después** de la subida en ese sentido. Por
/// eso la ida y la vuelta van por separado: la misma calle puede llevar hacia
/// el destino en un sentido y alejar de él en el otro.
abstract final class LinePlanner {
  /// Más de cinco convierte una recomendación en otra lista que hay que leer.
  static const int maxSuggestions = 5;

  /// Lo más que se le pide caminar en cada tramo. Una línea que pasa más lejos
  /// no es una forma razonable de llegar.
  static const double maxCaminata = 1500;

  /// Lo mínimo arriba del colectivo para que valga la pena tomarlo: si la
  /// subida y la bajada quedan casi en el mismo punto, el destino está más
  /// cerca a pie que en colectivo.
  static const double minEnColectivo = 150;

  /// Estrategia de ranking configurable para la pestaña Recorridos. Por omisión
  /// usa [compararPorProximidad]; puede reemplazarse por un algoritmo de
  /// recorrido óptimo más adelante.
  static LineRankingStrategy rankingStrategy = compararPorProximidad;

  /// Compara dos líneas priorizando de la más cercana a la más lejana a la
  /// ubicación actual del pasajero, desempatando por el colectivo activo más
  /// cercano y unidades en servicio.
  static int compararPorProximidad(LineaPriorizada a, LineaPriorizada b) {
    final ma = a.metros;
    final mb = b.metros;
    if (ma != null || mb != null) {
      final da = ma ?? double.infinity;
      final db = mb ?? double.infinity;
      if ((da - db).abs() > 1.0) {
        return da.compareTo(db);
      }
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

    final resultado = [
      for (final linea in lineas)
        () {
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
          return LineaPriorizada(
            linea: linea,
            metros: posicion == null ? null : metrosHasta(linea, posicion),
            enServicio: deLinea.length,
            metrosColectivoMasCercano: masCercano,
          );
        }(),
    ];

    resultado.sort(strategy ?? rankingStrategy);
    return resultado;
  }

  /// Las mejores formas de ir de [user] a [destino] usando el optimizador
  /// híbrido ([HybridRouteOptimizer]), con a lo más una por línea (la de su
  /// mejor sentido y menor costo objetivo acoplado $Z$).
  ///
  /// Por omisión usa las líneas públicas ([RecorridosService.publicas]): las
  /// activas de la garita [kGaritaPublica]. Si caminar directo es mejor o
  /// equivalente que tomar colectivo, devuelve lista vacía.
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

      if (localSubida != null && localBajada != null) {
        final refinedVeh =
            (c.lut.cumulativeMeters[downStart] + localBajada.desdeInicio) -
            (c.lut.cumulativeMeters[upStart] + localSubida.desdeInicio);
        if (refinedVeh >= HybridRouteOptimizer.kMinVehicularMeters) {
          subida = localSubida.punto;
          bajada = localBajada.punto;
          metrosHastaLinea = localSubida.metros;
          metrosDesdeLinea = localBajada.metros;
          metrosEnColectivo = refinedVeh;
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
          costoTotal: c.totalCost,
          esFallbackCaminataLarga: plan.isLongWalkFallback,
        ),
      );
      if (resultado.length >= maxSuggestions) break;
    }

    return resultado;
  }

  /// A cuántos metros pasa [linea] de [p], por cualquiera de sus sentidos, o
  /// `null` si no tiene trazado. Ordena la pestaña Líneas.
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
