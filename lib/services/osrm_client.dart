import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

/// Cliente mínimo de OSRM, compartido.
///
/// Existía ya un ruteo dentro de `RouteService`, pero atado a su caso: un
/// origen, un paradero de destino y el estado de la pantalla del pasajero.
/// Dibujar el recorrido de una línea necesita lo contrario — *muchos* puntos de
/// paso y ningún estado—, así que lo común (la petición y el decodificador de
/// polilíneas) vive acá y no duplicado en dos sitios.
abstract final class OsrmClient {
  static const _base = 'https://router.project-osrm.org/route/v1/driving/';

  /// OSRM rechaza peticiones demasiado largas. Un recorrido de colectivo no
  /// pasa de unas decenas de paraderos, así que este techo sólo protege de
  /// datos mal cargados.
  static const int maxWaypoints = 25;

  /// Traza una ruta que pasa por [waypoints] **en orden**.
  ///
  /// Devuelve `null` si no se pudo calcular; quien llama decide si cae a unir
  /// Obtiene la geometría codificada (polyline6) que pasa por [waypoints] en orden.
  static Future<String?> getEncodedRoute(List<LatLng> waypoints) async {
    final points = waypoints.where(isValidLatLng).toList(growable: false);
    if (points.length < 2) return null;

    final usados = points.length > maxWaypoints
        ? points.sublist(0, maxWaypoints)
        : points;

    final coords = usados
        .map((p) => '${p.longitude},${p.latitude}')
        .join(';');

    try {
      final url = Uri.parse('$_base$coords?overview=full&geometries=polyline6');
      final res = await http.get(
        url,
        headers: {'User-Agent': 'ColeTotal/1.0 (coletotal.app)'},
      ).timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) {
        debugPrint('OSRM ${res.statusCode}');
        return null;
      }

      final data = json.decode(res.body) as Map<String, dynamic>;
      if (data['code'] != 'Ok') return null;

      final routes = data['routes'] as List<dynamic>?;
      if (routes == null || routes.isEmpty) return null;

      final encoded = (routes.first as Map<String, dynamic>)['geometry'];
      if (encoded is! String || encoded.isEmpty) return null;

      return encoded;
    } catch (e) {
      debugPrint('OsrmClient.getEncodedRoute: $e');
      return null;
    }
  }

  /// Traza una ruta que pasa por [waypoints] **en orden**.
  ///
  /// Devuelve `null` si no se pudo calcular; quien llama decide si cae a unir
  /// los puntos con rectas o si muestra un error.
  static Future<List<LatLng>?> routeThrough(List<LatLng> waypoints) async {
    final encoded = await getEncodedRoute(waypoints);
    if (encoded == null) return null;
    final decoded = decodePolyline(encoded).where(isValidLatLng).toList();
    return decoded.isEmpty ? null : decoded;
  }

  /// Decodifica el formato *encoded polyline* de Google/OSRM.
  ///
  /// `precision: 6` es lo que devuelve OSRM cuando se pide `polyline6`; el
  /// formato clásico de Google usa 5.
  static List<LatLng> decodePolyline(String encoded, {int precision = 6}) {
    final points = <LatLng>[];
    final factor = _pow10(precision);
    var index = 0;
    var lat = 0;
    var lng = 0;

    while (index < encoded.length) {
      var result = 0;
      var shift = 0;
      int b;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      lat += ((result & 1) != 0) ? ~(result >> 1) : (result >> 1);

      result = 0;
      shift = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      lng += ((result & 1) != 0) ? ~(result >> 1) : (result >> 1);

      points.add(LatLng(lat / factor, lng / factor));
    }
    return points;
  }

  /// Coordenada finita y dentro de rango.
  ///
  /// flutter_map lanza "LatLng is not finite" ante un NaN, y los emuladores
  /// devuelven (0,0) antes del primer arreglo real de GPS.
  static bool isValidLatLng(LatLng p) =>
      p.latitude.isFinite &&
      p.longitude.isFinite &&
      p.latitude >= -90 &&
      p.latitude <= 90 &&
      p.longitude >= -180 &&
      p.longitude <= 180;

  static double _pow10(int n) {
    var result = 1.0;
    for (var i = 0; i < n; i++) {
      result *= 10;
    }
    return result;
  }
}
