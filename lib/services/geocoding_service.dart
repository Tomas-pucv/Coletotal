import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import 'package:taxi1/config/map_config.dart';
import 'package:taxi1/data/quilpue_pois.dart';
import 'package:taxi1/models/place_result.dart';
import 'package:taxi1/utils/text_search.dart';

/// Búsqueda de direcciones híbrida: POIs locales (0 ms y sin cuota) +
/// geocodificación MapTiler / Photon OSM para calles y numeraciones.
abstract final class GeocodingService {
  /// Sesga los resultados a la Quinta Región. Sin esto, "Freire" devuelve
  /// primero la comuna de Freire en la Araucanía, a 700 km.
  static const _proximity = kQuilpueCenter;

  /// Caja que cubre el Gran Valparaíso (Quilpué, Villa Alemana, Viña, Valpo).
  /// Recorta el ruido antes de que llegue a la lista.
  static const _bbox = '-71.75,-33.20,-71.20,-32.90';

  static const Duration timeout = Duration(seconds: 10);

  /// Cuántos resultados caben en el desplegable sin que haya que buscar.
  static const int maxResults = 6;

  static http.Client _client = http.Client();

  /// Sustituye el cliente HTTP. Sin esto los tests del buscador salían a la
  /// red de verdad: gastaban cuota de MapTiler y dependían de tener conexión.
  @visibleForTesting
  static set debugClient(http.Client client) => _client = client;

  /// Coincidencias del catálogo de POIs de Quilpué, sin tocar la red.
  ///
  /// Insensible a tildes y al orden de las palabras: casi nadie escribe
  /// "Líder" con tilde en el teléfono (ver `utils/text_search.dart`).
  static List<PlaceResult> searchLocal(String query) => kQuilpuePois
      .where((poi) => matchesAllTokens(query, [poi.name, poi.address]))
      .toList();

  /// Busca [query]. Primero coteja el catálogo de POIs de Quilpué; si faltan
  /// resultados, complementa con la API de geocodificación.
  static Future<List<PlaceResult>> search(String query) async {
    final q = query.trim();
    if (q.length < 2) return const [];

    // 1. Búsqueda instantánea en POIs locales (0 ms, 0 cuota de red).
    final results = searchLocal(q);
    if (results.length >= 5) return results.take(maxResults).toList();

    // 2. Con menos de 3 caracteres no se gasta red: la consulta es demasiado
    //    ambigua para que un geocodificador devuelva algo útil.
    if (q.length < 3) return results;

    // 3. MapTiler primero; si falla (cuota agotada, error HTTP, sin red), el
    //    respaldo abierto de Photon.
    final remote = await _searchMapTiler(q) ?? await _searchPhoton(q);

    // 4. Fusión sin duplicados: un POI local y el mismo lugar devuelto por la
    //    API se reconocen por el nombre normalizado.
    final seen = results.map((p) => normalizeForSearch(p.name)).toSet();
    for (final place in remote) {
      if (results.length >= maxResults) break;
      if (seen.add(normalizeForSearch(place.name))) results.add(place);
    }
    return results;
  }

  /// `null` si MapTiler no respondió bien: es la señal para probar Photon. Una
  /// lista vacía, en cambio, es una respuesta válida ("no hay nada").
  static Future<List<PlaceResult>?> _searchMapTiler(String q) async {
    try {
      final url = Uri.parse(
        'https://api.maptiler.com/geocoding/${Uri.encodeComponent(q)}.json'
        '?key=$kMapTilerKey'
        '&country=cl'
        '&language=es'
        '&limit=$maxResults'
        '&bbox=$_bbox'
        '&proximity=${_proximity.longitude},${_proximity.latitude}',
      );

      final res = await _client.get(url).timeout(timeout);
      if (res.statusCode != 200) {
        debugPrint('MapTiler Geocoding ${res.statusCode}: se intenta Photon');
        return null;
      }

      // `utf8` explícito y no `res.body`: sin `charset` en la cabecera,
      // package:http decodifica como latin1 y "Quilpué" llega como "QuilpuÃ©".
      final data =
          json.decode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      final features = data['features'] as List<dynamic>? ?? const [];
      return [
        for (final raw in features)
          if (raw is Map<String, dynamic>) ?_parseFeature(raw),
      ];
    } catch (e) {
      debugPrint('GeocodingService: MapTiler falló, se intenta Photon: $e');
      return null;
    }
  }

  /// Respaldo gratuito y abierto (OpenStreetMap) si MapTiler falla o agota la
  /// cuota. Va acotado a la misma caja de la Quinta Región.
  static Future<List<PlaceResult>> _searchPhoton(String q) async {
    try {
      final url = Uri.parse(
        'https://photon.komoot.io/api/?q=${Uri.encodeComponent(q)}'
        '&lat=${_proximity.latitude}&lon=${_proximity.longitude}'
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

      if (res.statusCode != 200) return const [];
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

  static PlaceResult? _parseFeature(Map<String, dynamic> feature) {
    final center = feature['center'];
    if (center is! List || center.length < 2) return null;

    final lon = center[0];
    final lat = center[1];
    if (lon is! num || lat is! num) return null;
    if (!lat.isFinite || !lon.isFinite) return null;

    // MapTiler devuelve "Calle 123, Comuna, Región, País" en `place_name`.
    // Se parte en dos para que la primera línea sea el dato y la segunda el
    // contexto, en vez de una sola línea larga y truncada.
    final placeName = (feature['place_name'] as String?)?.trim() ?? '';
    final text = (feature['text'] as String?)?.trim() ?? '';
    if (placeName.isEmpty && text.isEmpty) return null;

    final partes = placeName.split(',');
    final name = text.isNotEmpty
        ? text
        : (partes.isNotEmpty ? partes.first.trim() : placeName);
    final address = partes.length > 1
        ? partes.sublist(1).map((p) => p.trim()).join(', ')
        : '';

    return PlaceResult(
      id: (feature['id'] as String?) ?? '$placeName@$lat,$lon',
      name: name,
      address: address,
      location: LatLng(lat.toDouble(), lon.toDouble()),
    );
  }
}
