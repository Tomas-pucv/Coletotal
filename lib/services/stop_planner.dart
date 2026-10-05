import 'package:latlong2/latlong.dart';

import 'package:taxi1/models/bus_stop.dart';
import 'package:taxi1/models/recorrido.dart';
import 'package:taxi1/services/recorridos_service.dart';
import 'package:taxi1/services/stops_service.dart';

/// Un paradero propuesto para llegar a un destino, con el porqué a la vista.
class StopSuggestion {
  const StopSuggestion({
    required this.stop,
    required this.metersToUser,
    required this.metersToDestination,
    required this.recorrido,
    required this.bajada,
  });

  final BusStop stop;

  /// Lo que camina el usuario **hasta** el paradero.
  final double metersToUser;

  /// Lo que camina **desde** donde se baja hasta el destino.
  final double metersToDestination;

  /// La línea que consigue esa bajada. `null` cuando la garita todavía no ha
  /// cargado recorridos y la sugerencia es sólo por cercanía.
  final Recorrido? recorrido;

  /// Paradero donde conviene bajarse. `null` en el mismo caso que [recorrido].
  final BusStop? bajada;

  /// Promedio de los dos tramos a pie, que es el criterio pedido: "el mejor
  /// promedio de (colectivo más cercano al destino + paradero más cercano al
  /// usuario)". Menor es mejor.
  ///
  /// Promediar metros en vez de puntuaciones normalizadas es deliberado: el
  /// número resultante sigue siendo metros, así que se puede enseñar y
  /// discutir. Como el promedio es proporcional a la suma, ordenar por él
  /// equivale a ordenar por el total caminado.
  double get score => (metersToUser + metersToDestination) / 2;

  /// Total real a pie, que es lo que se le muestra al usuario.
  double get metersTotales => metersToUser + metersToDestination;
}

/// Elige por dónde tomar el colectivo para llegar a un destino.
abstract final class StopPlanner {
  static const _distance = Distance();

  /// Cuántas sugerencias devolver. Más de cinco convierte una recomendación en
  /// otra lista que hay que leer entera.
  static const int maxSuggestions = 5;

  /// Ordena los paraderos por conveniencia para ir de [user] a [destino].
  ///
  /// Para cada paradero de subida se busca, entre las líneas que lo sirven, la
  /// que tiene alguna parada más cerca del destino; esa parada es la bajada. El
  /// paradero se puntúa con el promedio de los dos tramos caminando.
  ///
  /// La bajada nunca es la propia subida: si la parada de una línea más cercana
  /// al destino es justo donde uno se sube, el colectivo no lleva a ninguna
  /// parte y se usa la siguiente mejor de esa línea.
  ///
  /// **Simplificación conocida:** no se modela el sentido de marcha. Un
  /// recorrido se trata como el conjunto de sus paraderos, así que se asume que
  /// desde la subida se puede alcanzar cualquier otra parada de esa línea. Con
  /// los datos que hay (una lista ordenada, sin ida/vuelta ni horarios) es lo
  /// más que se puede afirmar con honestidad.
  static List<StopSuggestion> suggest({
    required LatLng user,
    required LatLng destino,
    List<BusStop>? stops,
    List<Recorrido>? recorridos,
  }) {
    final todosLosParaderos = stops ?? StopsService.instance.stops;
    final todosLosRecorridos =
        recorridos ?? RecorridosService.instance.recorridos;

    final activos = todosLosParaderos
        .where((s) => s.activo)
        .toList(growable: false);
    if (activos.isEmpty) return const [];
    final porId = {for (final s in activos) s.id: s};

    // Cada distancia se calcula una sola vez. Antes se medía de nuevo por cada
    // combinación de subida, línea y bajada: miles de cálculos geodésicos
    // (Vincenty, iterativo) en cada búsqueda.
    final alDestino = {
      for (final s in activos) s.id: _metros(destino, s.location),
    };

    // Por línea, sus dos mejores bajadas; y por paradero, las líneas que lo
    // sirven.
    final bajadas = <String, _MejoresBajadas>{};
    final lineasPorParadero = <String, List<Recorrido>>{};
    for (final recorrido in todosLosRecorridos) {
      if (!recorrido.activo) continue;
      final mejores = _MejoresBajadas();
      for (final id in recorrido.paraderoIds.toSet()) {
        final stop = porId[id];
        if (stop == null) continue;
        lineasPorParadero.putIfAbsent(id, () => []).add(recorrido);
        mejores.ofrecer(stop, alDestino[id]!);
      }
      bajadas[recorrido.id] = mejores;
    }

    final suggestions = <StopSuggestion>[];

    for (final subida in activos) {
      final lineas = lineasPorParadero[subida.id];
      if (lineas == null) continue;

      Recorrido? mejorRecorrido;
      BusStop? mejorBajada;
      var mejorDistancia = double.infinity;

      for (final recorrido in lineas) {
        final candidata = bajadas[recorrido.id]!.distintaDe(subida.id);
        if (candidata == null) continue;
        if (candidata.$2 < mejorDistancia) {
          mejorDistancia = candidata.$2;
          mejorBajada = candidata.$1;
          mejorRecorrido = recorrido;
        }
      }

      if (mejorRecorrido == null || mejorBajada == null) continue;

      suggestions.add(
        StopSuggestion(
          stop: subida,
          metersToUser: _metros(user, subida.location),
          metersToDestination: mejorDistancia,
          recorrido: mejorRecorrido,
          bajada: mejorBajada,
        ),
      );
    }

    // Sin recorridos cargados no se puede afirmar a dónde te lleva ningún
    // colectivo. En vez de no mostrar nada, se degrada a "paraderos entre tú y
    // el destino"; la interfaz avisa de que es una aproximación.
    if (suggestions.isEmpty) {
      for (final stop in activos) {
        suggestions.add(
          StopSuggestion(
            stop: stop,
            metersToUser: _metros(user, stop.location),
            metersToDestination: alDestino[stop.id]!,
            recorrido: null,
            bajada: null,
          ),
        );
      }
    }

    suggestions.sort((a, b) => a.score.compareTo(b.score));
    return suggestions.length > maxSuggestions
        ? suggestions.sublist(0, maxSuggestions)
        : suggestions;
  }

  static double _metros(LatLng a, LatLng b) =>
      _distance.as(LengthUnit.Meter, a, b);
}

/// Las dos paradas de una línea más cercanas al destino.
///
/// Con la mejor sola no alcanza: si coincide con la subida, la respuesta es la
/// segunda.
class _MejoresBajadas {
  BusStop? _primera;
  var _dPrimera = double.infinity;
  BusStop? _segunda;
  var _dSegunda = double.infinity;

  void ofrecer(BusStop stop, double metros) {
    if (metros < _dPrimera) {
      _segunda = _primera;
      _dSegunda = _dPrimera;
      _primera = stop;
      _dPrimera = metros;
    } else if (metros < _dSegunda) {
      _segunda = stop;
      _dSegunda = metros;
    }
  }

  /// La mejor bajada que no sea [subidaId], con su distancia al destino.
  (BusStop, double)? distintaDe(String subidaId) {
    final primera = _primera;
    if (primera != null && primera.id != subidaId) return (primera, _dPrimera);
    final segunda = _segunda;
    if (segunda != null) return (segunda, _dSegunda);
    return null;
  }
}
