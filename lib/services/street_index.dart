import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';

import 'package:taxi1/models/place_result.dart';
import 'package:taxi1/utils/text_search.dart';

/// Índice offline de las calles de la Región de Valparaíso.
///
/// Sale de OpenStreetMap junto con el mapa base (`scripts/mapa_base/build.js`):
/// unas 25 mil calles, cada una con su comuna y un punto sobre ella. Con él el
/// buscador encuentra calles sin señal; antes sólo los 26 POIs de
/// `quilpue_pois.dart` funcionaban sin red.
///
/// Las calles no traen numeración: para "Freire 1234" sigue haciendo falta
/// Photon, que se consulta después si hay conexión.
abstract final class StreetIndex {
  static const String asset = 'assets/map/calles_valparaiso.json';

  static Future<List<_Calle>>? _calles;

  /// Lee el índice en segundo plano. Se llama al arrancar, sin esperarla,
  /// para que la primera búsqueda no tenga que esperar a que se cargue.
  static Future<void> preload() => _cargar();

  /// Calles que contienen todas las palabras de [query], de la más cercana a
  /// [near] a la más lejana: "los carrera" encuentra primero la de la comuna
  /// del usuario y no la de Valparaíso.
  static Future<List<PlaceResult>> search(
    String query, {
    required LatLng near,
    int limit = 6,
  }) async {
    final tokens = searchTokens(query);
    if (tokens.isEmpty) return const [];

    final calles = await _cargar();
    final coincidencias = [
      for (final calle in calles)
        if (containsAllTokens(calle.texto, tokens)) calle,
    ];
    // Lo que mide un grado de longitud respecto de uno de latitud: basta para
    // ordenar por cercanía sin la fórmula completa.
    final escala = math.cos(near.latitude * math.pi / 180);
    double distancia(_Calle c) {
      final dx = (c.longitud - near.longitude) * escala;
      final dy = c.latitud - near.latitude;
      return dx * dx + dy * dy;
    }

    coincidencias.sort((a, b) => distancia(a).compareTo(distancia(b)));
    return [for (final calle in coincidencias.take(limit)) calle.toPlace()];
  }

  @visibleForTesting
  static void debugReset() => _calles = null;

  static Future<List<_Calle>> _cargar() => _calles ??= _leer();

  static Future<List<_Calle>> _leer() async {
    try {
      final json = await rootBundle.loadString(asset);
      // Son 1,2 MB de JSON y 25 mil textos que normalizar: fuera del hilo de
      // la interfaz, o el teclado se traba en la primera búsqueda.
      return await compute(_parsear, json);
    } catch (e) {
      debugPrint('StreetIndex: no se pudo leer el índice de calles: $e');
      // Sin índice el buscador sigue con los POIs y Photon. Se olvida el
      // fallo para volver a intentarlo en la próxima búsqueda.
      _calles = null;
      return const [];
    }
  }

  static List<_Calle> _parsear(String json) {
    final filas = jsonDecode(json) as List<dynamic>;
    return [
      for (final (i, fila) in filas.indexed)
        if (fila case [
          final String nombre,
          final String comuna,
          final num lat,
          final num lon,
        ])
          _Calle(
            id: i,
            nombre: nombre,
            comuna: comuna,
            latitud: lat.toDouble(),
            longitud: lon.toDouble(),
          ),
    ];
  }
}

class _Calle {
  _Calle({
    required this.id,
    required this.nombre,
    required this.comuna,
    required this.latitud,
    required this.longitud,
  }) : texto = normalizeForSearch('$nombre $comuna');

  final int id;
  final String nombre;
  final String comuna;
  final double latitud;
  final double longitud;

  /// Nombre y comuna normalizados una sola vez, al cargar.
  final String texto;

  PlaceResult toPlace() => PlaceResult(
    id: 'calle_$id',
    name: nombre,
    address: '$comuna, Región de Valparaíso',
    location: LatLng(latitud, longitud),
  );
}
