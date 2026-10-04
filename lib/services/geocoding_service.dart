import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import 'package:taxi1/config/map_config.dart';

import 'package:taxi1/data/quilpue_pois.dart';

/// Una dirección o punto de interés encontrado por el buscador.
class PlaceResult {
  const PlaceResult({
    required this.id,
    required this.name,
    required this.address,
    required this.location,
    this.isPoi = false,
  });

  final String id;

  /// Lo primero de la dirección o nombre del POI: "Supermercado Líder Belloto".
  final String name;

  /// El resto, para desambiguar: "Quilpué, Valparaíso, Chile".
  final String address;

  final LatLng location;

  /// Si es un punto de interés clave (supermercado, plaza, hospital, etc.).
  final bool isPoi;

  @override
  bool operator ==(Object other) => other is PlaceResult && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

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

  /// Busca [query]. Primero coteja el catálogo de POIs de Quilpué; si faltan
  /// resultados, complementa con la API de geocodificación.
  static Future<List<PlaceResult>> search(String query) async {
    final q = query.trim();
    if (q.length < 2) return const [];

    final qLower = q.toLowerCase();

    // 1. Búsqueda instantánea en POIs locales (0 ms, 0 cuota de red)
    final localMatches = kQuilpuePois.where((poi) {
      final name = poi.name.toLowerCase();
      final addr = poi.address.toLowerCase();
      return name.contains(qLower) || addr.contains(qLower);
    }).toList(growable: true);

    // Si encontramos suficientes coincidencias directas en POIs, las devolvemos de inmediato
    if (localMatches.length >= 5) {
      return localMatches.take(6).toList();
    }

    // 2. Si es menos de 3 caracteres y no hubo suficientes POIs, no gastamos red
    if (q.length < 3) return localMatches;

    // 3. Consulta a MapTiler Geocoding
    final remoteResults = <PlaceResult>[];
    try {
      final url = Uri.parse(
        'https://api.maptiler.com/geocoding/${Uri.encodeComponent(q)}.json'
        '?key=$kMapTilerKey'
        '&country=cl'
        '&language=es'
        '&limit=6'
        '&bbox=$_bbox'
        '&proximity=${_proximity.longitude},${_proximity.latitude}',
      );

      final res = await http.get(url).timeout(timeout);
      if (res.statusCode == 200) {
        final data = json.decode(res.body) as Map<String, dynamic>;
        final features = data['features'] as List<dynamic>?;
        if (features != null) {
          for (final raw in features) {
            if (raw is! Map<String, dynamic>) continue;
            final place = _parseFeature(raw);
            if (place != null) remoteResults.add(place);
          }
        }
      } else {
        debugPrint('MapTiler Geocoding error ${res.statusCode}: intentando Photon OSM');
        final photonResults = await _searchPhoton(q);
        remoteResults.addAll(photonResults);
      }
    } catch (e) {
      debugPrint('GeocodingService fallback a Photon: $e');
      final photonResults = await _searchPhoton(q);
      remoteResults.addAll(photonResults);
    }

    // 4. Fusionar POIs locales con resultados remotos evitando duplicados
    final existingIds = localMatches.map((p) => p.name.toLowerCase()).toSet();
    for (final r in remoteResults) {
      if (!existingIds.contains(r.name.toLowerCase()) && localMatches.length < 6) {
        localMatches.add(r);
        existingIds.add(r.name.toLowerCase());
      }
    }

    return localMatches;
  }

  /// Fallback gratuito y abierto a Photon (OpenStreetMap) si MapTiler falla o agota cuota.
  static Future<List<PlaceResult>> _searchPhoton(String q) async {
    try {
      final url = Uri.parse(
        'https://photon.komoot.io/api/?q=${Uri.encodeComponent(q)}'
        '&lat=${_proximity.latitude}&lon=${_proximity.longitude}'
        '&limit=5',
      );
      final res = await http.get(
        url,
        headers: {'User-Agent': 'ColeTotal/1.0 (cl.coletotal.app)'},
      ).timeout(timeout);

      if (res.statusCode != 200) return const [];
      final data = json.decode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
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
        final name = (props['name'] as String?) ?? (props['street'] as String?) ?? '';
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
            isPoi: props['osm_value'] == 'supermarket' ||
                props['osm_value'] == 'hospital' ||
                props['osm_value'] == 'school',
          ),
        );
      }
      return results;
    } catch (_) {
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
