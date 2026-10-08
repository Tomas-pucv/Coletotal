import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import 'package:taxi1/config/map_config.dart';
import 'package:taxi1/data/quilpue_pois.dart';
import 'package:taxi1/models/place_result.dart';
import 'package:taxi1/services/location_service.dart';
import 'package:taxi1/services/street_index.dart';
import 'package:taxi1/utils/text_search.dart';

/// Búsqueda de direcciones en tres pasos, de lo local a la red:
///
/// 1. Los POIs de Quilpué (`quilpue_pois.dart`), instantáneos.
/// 2. El índice offline de calles de la región ([StreetIndex]), sin red.
/// 3. Photon (OpenStreetMap), sólo si faltan resultados: aporta la
///    numeración, que el índice no tiene.
///
/// Antes el paso 2 no existía y el 3 era MapTiler, con Photon de respaldo:
/// sin señal sólo se encontraban los POIs, y cada búsqueda gastaba cuota.
abstract final class GeocodingService {
  /// Caja de la Región de Valparaíso, la misma del mapa con calles: así cada
  /// resultado cae sobre mapa dibujado. Sin ella, "Freire" devolvía primero
  /// la comuna de Freire en la Araucanía, a 700 km.
  static final String _bbox =
      '${kDetailBounds.west},${kDetailBounds.south},'
      '${kDetailBounds.east},${kDetailBounds.north}';

  static const Duration timeout = Duration(seconds: 10);

  /// Cuántos resultados caben en el desplegable sin que haya que buscar.
  static const int maxResults = 6;

  /// Dos resultados con el mismo nombre a menos de esto son el mismo lugar
  /// (la calle del índice y la que devuelve Photon, por ejemplo). Más lejos
  /// son calles distintas que se llaman igual, como "Los Carrera" en Quilpué
  /// y en Villa Alemana.
  static const double _mismoLugarMetros = 1500;

  static http.Client _client = http.Client();

  /// Sustituye el cliente HTTP. Sin esto los tests del buscador salían a la
  /// red de verdad y dependían de tener conexión.
  @visibleForTesting
  static set debugClient(http.Client client) => _client = client;

  /// Coincidencias del catálogo de POIs de Quilpué, sin tocar la red.
  ///
  /// Insensible a tildes y al orden de las palabras: casi nadie escribe
  /// "Líder" con tilde en el teléfono (ver `utils/text_search.dart`).
  static List<PlaceResult> searchLocal(String query) => kQuilpuePois
      .where((poi) => matchesAllTokens(query, [poi.name, poi.address]))
      .toList();

  /// Busca [query]: primero lo local (POIs y calles) y, si falta, Photon.
  static Future<List<PlaceResult>> search(String query) async {
    final q = query.trim();
    if (q.length < 2) return const [];

    // 1. Búsqueda instantánea en POIs locales.
    final results = searchLocal(q);
    if (results.length >= 5) return results.take(maxResults).toList();

    // Con menos de 3 caracteres no se busca más: la consulta es demasiado
    // ambigua para que un índice de 25 mil calles devuelva algo útil.
    if (q.length < 3) return results;

    // 2. Calles del índice offline, de la más cercana al usuario a la más
    //    lejana.
    final cerca = LocationService.instance.position ?? kQuilpueCenter;
    _agregar(
      results,
      await StreetIndex.search(q, near: cerca, limit: maxResults),
    );
    if (results.length >= maxResults) return results;

    // 3. Photon, para la numeración y lo que el índice no tenga. Sin red
    //    devuelve una lista vacía y quedan los resultados locales.
    _agregar(results, await _searchPhoton(q));
    return results;
  }

  /// Agrega [nuevos] a [results] sin repetir lugares y sin pasar de
  /// [maxResults].
  static void _agregar(List<PlaceResult> results, List<PlaceResult> nuevos) {
    const distancia = Distance();
    for (final place in nuevos) {
      if (results.length >= maxResults) return;
      final nombre = normalizeForSearch(place.name);
      final repetido = results.any(
        (r) =>
            normalizeForSearch(r.name) == nombre &&
            distancia(r.location, place.location) < _mismoLugarMetros,
      );
      if (!repetido) results.add(place);
    }
  }

  /// Geocodificador abierto de OpenStreetMap, sin clave. Va acotado a la caja
  /// de la región y sesgado hacia Quilpué.
  static Future<List<PlaceResult>> _searchPhoton(String q) async {
    try {
      final url = Uri.parse(
        'https://photon.komoot.io/api/?q=${Uri.encodeComponent(q)}'
        '&lat=${kQuilpueCenter.latitude}&lon=${kQuilpueCenter.longitude}'
        '&bbox=$_bbox'
        '&limit=5',
      );
      // En la web no se envía User-Agent propio: el navegador pone el suyo y
      // uno propio dispara una verificación CORS previa (ver OsrmClient).
      final res = await _client
          .get(
            url,
            headers: kIsWeb
                ? null
                : const {'User-Agent': 'ColeTotal/1.0 (cl.coletotal.app)'},
          )
          .timeout(timeout);

      if (res.statusCode != 200) {
        debugPrint('GeocodingService: Photon respondió ${res.statusCode}');
        return const [];
      }
      // `utf8` explícito y no `res.body`: sin `charset` en la cabecera,
      // package:http decodifica como latin1 y "Quilpué" llega como "QuilpuÃ©".
      final data =
          json.decode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      final features = data['features'] as List<dynamic>?;
      if (features == null) return const [];

      final results = <PlaceResult>[];
      for (final raw in features) {
        if (raw is! Map<String, dynamic>) continue;
        final geom = raw['geometry'] as Map<String, dynamic>?;
        final props = raw['properties'] as Map<String, dynamic>?;
        if (geom == null || props == null) continue;
        final coords = geom['coordinates'] as List<dynamic>?;
        if (coords == null || coords.length < 2) continue;

        final lon = (coords[0] as num).toDouble();
        final lat = (coords[1] as num).toDouble();
        final name =
            (props['name'] as String?) ?? (props['street'] as String?) ?? '';
        if (name.isEmpty) continue;

        final street = props['street'] as String?;
        final housenumber = props['housenumber'] as String?;
        final city = props['city'] as String? ?? 'Quilpué';
        final addressParts = [
          if (street != null && street != name) street,
          if (housenumber != null) '#$housenumber',
          city,
          'Chile',
        ];

        results.add(
          PlaceResult(
            id: 'photon_${props['osm_id'] ?? '${lat}_$lon'}',
            name: name,
            address: addressParts.join(', '),
            location: LatLng(lat, lon),
            isPoi:
                props['osm_value'] == 'supermarket' ||
                props['osm_value'] == 'hospital' ||
                props['osm_value'] == 'school',
          ),
        );
      }
      return results;
    } catch (e) {
      debugPrint('GeocodingService: Photon falló: $e');
      return const [];
    }
  }
}
