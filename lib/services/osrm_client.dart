import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import 'package:taxi1/models/route_path.dart';
import 'package:taxi1/utils/polyline.dart';

/// Medio con el que se calcula una ruta.
enum OsrmProfile {
  /// En auto: es el trayecto de los colectivos, que respetan el sentido de las
  /// calles.
  driving,

  /// A pie: la ruta del pasajero hasta el paradero, que puede ir por calles de
  /// un solo sentido en cualquier dirección.
  foot;

  /// El servidor público de demostración de OSRM sólo tiene perfil de auto
  /// (ignora el nombre del perfil en la URL), así que el peatonal va al de
  /// FOSSGIS, el mismo que usa openstreetmap.org para sus indicaciones a pie.
  String get baseUrl => switch (this) {
    OsrmProfile.driving => 'https://router.project-osrm.org/route/v1/driving/',
    OsrmProfile.foot =>
      'https://routing.openstreetmap.de/routed-foot/route/v1/driving/',
  };
}

/// Cliente mínimo de OSRM: el enrutador de respaldo cuando Valhalla no
/// responde (ver `Routing`), tanto para la ruta a pie como para el trazado de
/// las líneas.
abstract final class OsrmClient {
  /// Puntos de paso por petición. Un recorrido con más paraderos se pide en
  /// tramos que se solapan en un paradero y se cosen después: antes la lista
  /// se cortaba en silencio en el paradero 25 y la línea quedaba dibujada (y
  /// guardada en Firestore) a medias.
  static const int maxWaypoints = 25;

  static const _timeout = Duration(seconds: 20);

  /// Identificación ante los servidores públicos de ruteo, que la piden en sus
  /// políticas de uso. **En la web no se envía**: el navegador pone la suya,
  /// y una cabecera `User-Agent` propia obliga a una verificación CORS previa
  /// que estos servidores rechazan (sólo aceptan `X-Requested-With` y
  /// `Content-Type`), con lo que todas las rutas fallaban.
  static const Map<String, String>? _headers = kIsWeb
      ? null
      : {'User-Agent': 'ColeTotal/1.0 (cl.coletotal.app)'};

  static http.Client _client = http.Client();

  @visibleForTesting
  static set debugClient(http.Client client) => _client = client;

  /// Ruta que pasa por [waypoints] **en orden**. `null` si no se pudo calcular:
  /// quien llama decide si prueba con otro enrutador o une los puntos con
  /// rectas.
  static Future<RoutePath?> route(
    List<LatLng> waypoints, {
    OsrmProfile profile = OsrmProfile.driving,
  }) async {
    final points = waypoints.where(isValidLatLng).toList(growable: false);
    if (points.length < 2) return null;

    final tramos = <List<LatLng>>[];
    var distance = 0.0;
    var duration = 0.0;
    for (final tramo in chunkWaypoints(points, maxWaypoints)) {
      final parcial = await _requestRoute(tramo, profile);
      if (parcial == null) return null;
      tramos.add(parcial.points);
      distance += parcial.distanceMeters;
      duration += parcial.durationSeconds;
    }

    final geometry = joinLegs(tramos);
    if (geometry.length < 2) return null;
    return RoutePath(
      points: geometry,
      distanceMeters: distance,
      durationSeconds: duration,
      provider: 'OSRM',
    );
  }

  static Future<RoutePath?> _requestRoute(
    List<LatLng> points,
    OsrmProfile profile,
  ) async {
    final coords = points.map((p) => '${p.longitude},${p.latitude}').join(';');
    try {
      final url = Uri.parse(
        '${profile.baseUrl}$coords?overview=full&geometries=polyline6',
      );
      final res = await _client.get(url, headers: _headers).timeout(_timeout);
      if (res.statusCode != 200) {
        debugPrint('OSRM (${profile.name}) ${res.statusCode}');
        return null;
      }

      final data = json.decode(res.body) as Map<String, dynamic>;
      if (data['code'] != 'Ok') return null;

      final routes = data['routes'] as List<dynamic>?;
      if (routes == null || routes.isEmpty) return null;

      final first = routes.first as Map<String, dynamic>;
      final encoded = first['geometry'];
      if (encoded is! String || encoded.isEmpty) return null;

      final decoded = decodePolyline(encoded).where(isValidLatLng).toList();
      if (decoded.isEmpty) return null;

      final distance = first['distance'];
      final duration = first['duration'];
      return RoutePath(
        points: decoded,
        distanceMeters: distance is num ? distance.toDouble() : 0,
        durationSeconds: duration is num ? duration.toDouble() : 0,
        provider: 'OSRM',
      );
    } catch (e) {
      debugPrint('OsrmClient (${profile.name}): $e');
      return null;
    }
  }
}
