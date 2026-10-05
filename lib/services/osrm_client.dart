import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

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

/// Una ruta calculada: puntos más métricas.
class OsrmRoute {
  const OsrmRoute({
    required this.points,
    required this.distanceMeters,
    required this.durationSeconds,
  });

  final List<LatLng> points;
  final double distanceMeters;
  final double durationSeconds;
}

/// Cliente mínimo de OSRM, compartido.
///
/// Lo usan tanto la ruta a pie del pasajero (`RouteService`) como el trazado
/// de los recorridos de las líneas (`GaritaService`, `RecorridosService`): la
/// petición, el troceo y el formato de polilínea viven acá y no duplicados.
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
  /// quien llama decide si une los puntos con rectas o muestra un error.
  static Future<OsrmRoute?> route(
    List<LatLng> waypoints, {
    OsrmProfile profile = OsrmProfile.driving,
  }) async {
    final points = waypoints.where(isValidLatLng).toList(growable: false);
    if (points.length < 2) return null;

    final geometry = <LatLng>[];
    var distance = 0.0;
    var duration = 0.0;

    for (final tramo in chunk(points, maxWaypoints)) {
      final parcial = await _requestRoute(tramo, profile);
      if (parcial == null) return null;

      // Cada tramo empieza donde terminó el anterior: el punto de unión viene
      // repetido y se descarta para no dibujar un vértice doble.
      var nuevos = parcial.points;
      if (geometry.isNotEmpty &&
          nuevos.isNotEmpty &&
          nuevos.first == geometry.last) {
        nuevos = nuevos.sublist(1);
      }
      geometry.addAll(nuevos);
      distance += parcial.distanceMeters;
      duration += parcial.durationSeconds;
    }

    if (geometry.length < 2) return null;
    return OsrmRoute(
      points: geometry,
      distanceMeters: distance,
      durationSeconds: duration,
    );
  }

  /// Geometría codificada (polyline6) del trayecto en auto por [waypoints]. Es
  /// lo que se guarda en el campo `geometria` de un recorrido.
  static Future<String?> getEncodedRoute(List<LatLng> waypoints) async {
    final result = await route(waypoints);
    return result == null ? null : encodePolyline(result.points);
  }

  /// Puntos del trayecto en auto por [waypoints], o `null` si falló.
  static Future<List<LatLng>?> routeThrough(List<LatLng> waypoints) async =>
      (await route(waypoints))?.points;

  /// Parte [points] en tramos de como mucho [size] puntos, donde cada tramo
  /// empieza en el último punto del anterior.
  @visibleForTesting
  static List<List<LatLng>> chunk(List<LatLng> points, int size) {
    assert(size >= 2);
    final chunks = <List<LatLng>>[];
    var start = 0;
    while (start < points.length - 1) {
      final end = math.min(start + size, points.length);
      chunks.add(points.sublist(start, end));
      start = end - 1;
    }
    return chunks;
  }

  static Future<OsrmRoute?> _requestRoute(
    List<LatLng> points,
    OsrmProfile profile,
  ) async {
    final coords = points
        .map((p) => '${p.longitude},${p.latitude}')
        .join(';');
    try {
      final url = Uri.parse(
        '${profile.baseUrl}$coords?overview=full&geometries=polyline6',
      );
      final res = await _client
          .get(url, headers: _headers)
          .timeout(_timeout);
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
      return OsrmRoute(
        points: decoded,
        distanceMeters: distance is num ? distance.toDouble() : 0,
        durationSeconds: duration is num ? duration.toDouble() : 0,
      );
    } catch (e) {
      debugPrint('OsrmClient (${profile.name}): $e');
      return null;
    }
  }

  /// Decodifica el formato *encoded polyline* de Google/OSRM.
  ///
  /// `precision: 6` es lo que devuelve OSRM cuando se pide `polyline6`; el
  /// formato clásico de Google usa 5.
  ///
  /// Se decodifica con aritmética y no con operadores de bits. En la web, Dart
  /// compila a JavaScript y `~`, `>>` y `<<` devuelven enteros de 32 bits
  /// **sin signo**: `~(x >> 1)`, que en Android da el valor negativo, en el
  /// navegador daba 4.261.920.296 en vez de -33.047.000. Como todas las
  /// coordenadas de Quilpué son negativas, en la web cada trazado se
  /// decodificaba a puntos fuera del mapa, y los recorridos terminaban
  /// dibujados como rectas entre paraderos.
  static List<LatLng> decodePolyline(String encoded, {int precision = 6}) {
    final points = <LatLng>[];
    final factor = _pow10(precision);
    var index = 0;
    var lat = 0;
    var lng = 0;

    int nextValue() {
      var result = 0;
      var weight = 1;
      int b;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result += (b % 32) * weight;
        weight *= 32;
      } while (b >= 32);
      // "Zigzag": los impares son los negativos.
      return result.isOdd ? -((result + 1) ~/ 2) : result ~/ 2;
    }

    while (index < encoded.length) {
      lat += nextValue();
      lng += nextValue();
      points.add(LatLng(lat / factor, lng / factor));
    }
    return points;
  }

  /// Codifica [points] en *encoded polyline*. Inversa de [decodePolyline].
  ///
  /// Hace falta porque un recorrido largo se pide en varios tramos y la
  /// geometría cosida hay que volver a guardarla como un solo `polyline6`.
  static String encodePolyline(List<LatLng> points, {int precision = 6}) {
    final factor = _pow10(precision);
    final buffer = StringBuffer();
    var prevLat = 0;
    var prevLng = 0;

    // Con aritmética, por la misma razón que en [decodePolyline].
    void encodeValue(int value) {
      var v = value < 0 ? -value * 2 - 1 : value * 2;
      while (v >= 32) {
        buffer.writeCharCode(32 + v % 32 + 63);
        v ~/= 32;
      }
      buffer.writeCharCode(v + 63);
    }

    for (final p in points) {
      final lat = (p.latitude * factor).round();
      final lng = (p.longitude * factor).round();
      encodeValue(lat - prevLat);
      encodeValue(lng - prevLng);
      prevLat = lat;
      prevLng = lng;
    }
    return buffer.toString();
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

  static double _pow10(int n) => math.pow(10, n).toDouble();
}
