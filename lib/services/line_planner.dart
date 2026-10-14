import 'package:latlong2/latlong.dart';

import 'package:taxi1/config/garita_config.dart';
import 'package:taxi1/models/recorrido.dart';
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

  /// Total a pie, que es por lo que se ordenan las sugerencias.
  double get metrosAPie => metrosHastaLinea + metrosDesdeLinea;
}

/// Elige qué colectivo tomar para llegar a un destino.
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

  /// Las mejores formas de ir de [user] a [destino], de menos a más caminata,
  /// con a lo más una por línea (la de su mejor sentido).
  ///
  /// Por omisión usa las líneas públicas ([RecorridosService.publicas]): las
  /// activas de la garita [kGaritaPublica].
  static List<LineSuggestion> suggest({
    required LatLng user,
    required LatLng destino,
    List<Recorrido>? recorridos,
  }) {
    final lineas = recorridos ?? RecorridosService.instance.publicas;
    final porLinea = <String, LineSuggestion>{};

    for (final linea in lineas) {
      if (!linea.activo) continue;
      for (final (sentido, trayecto) in linea.trayectos) {
        final subida = nearestOnPolyline(trayecto.trazado, user);
        final bajada = nearestOnPolyline(trayecto.trazado, destino);
        if (subida == null || bajada == null) continue;
        if (subida.metros > maxCaminata || bajada.metros > maxCaminata) {
          continue;
        }
        final enColectivo = bajada.desdeInicio - subida.desdeInicio;
        if (enColectivo < minEnColectivo) continue;

        final sugerencia = LineSuggestion(
          recorrido: linea,
          sentido: sentido,
          subida: subida.punto,
          bajada: bajada.punto,
          metrosHastaLinea: subida.metros,
          metrosDesdeLinea: bajada.metros,
          metrosEnColectivo: enColectivo,
        );
        final actual = porLinea[linea.id];
        if (actual == null || sugerencia.metrosAPie < actual.metrosAPie) {
          porLinea[linea.id] = sugerencia;
        }
      }
    }

    final resultado = porLinea.values.toList()
      ..sort((a, b) => a.metrosAPie.compareTo(b.metrosAPie));
    return resultado.length > maxSuggestions
        ? resultado.sublist(0, maxSuggestions)
        : resultado;
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
