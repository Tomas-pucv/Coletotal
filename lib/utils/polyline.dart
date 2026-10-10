import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

// Formato *encoded polyline* de Google: el que devuelven OSRM (`polyline6`) y
// Valhalla, y el que se guarda en el campo `geometria` de un recorrido.

/// Decodifica una polilínea. `precision: 6` es la de OSRM y Valhalla; el
/// formato clásico de Google usa 5.
///
/// Se decodifica con aritmética y no con operadores de bits. En la web, Dart
/// compila a JavaScript y `~`, `>>` y `<<` devuelven enteros de 32 bits
/// **sin signo**: `~(x >> 1)`, que en Android da el valor negativo, en el
/// navegador daba 4.261.920.296 en vez de -33.047.000. Como todas las
/// coordenadas de Quilpué son negativas, en la web cada trazado se
/// decodificaba a puntos fuera del mapa, y los recorridos terminaban
/// dibujados como rectas entre paraderos.
List<LatLng> decodePolyline(String encoded, {int precision = 6}) {
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

/// Codifica [points]. Inversa de [decodePolyline].
///
/// Hace falta porque un recorrido largo se pide en varios tramos y la
/// geometría cosida hay que volver a guardarla como una sola polilínea.
String encodePolyline(List<LatLng> points, {int precision = 6}) {
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
/// Un NaN rompe el mapa (sus puntos viajan a MapLibre como JSON, que no lo
/// admite), y los emuladores devuelven (0,0) antes del primer arreglo real de
/// GPS.
bool isValidLatLng(LatLng p) =>
    p.latitude.isFinite &&
    p.longitude.isFinite &&
    p.latitude >= -90 &&
    p.latitude <= 90 &&
    p.longitude >= -180 &&
    p.longitude <= 180;

/// Parte [points] en tramos de como mucho [size] puntos, donde cada tramo
/// empieza en el último punto del anterior: los enrutadores aceptan un
/// máximo de puntos por petición, y una línea con más paraderos se pide por
/// partes y se cose después.
List<List<LatLng>> chunkWaypoints(List<LatLng> points, int size) {
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

/// Une tramos consecutivos de una ruta sin repetir el punto de unión: cada
/// tramo empieza donde terminó el anterior.
List<LatLng> joinLegs(Iterable<List<LatLng>> legs) {
  final joined = <LatLng>[];
  for (final leg in legs) {
    var nuevos = leg;
    if (joined.isNotEmpty && nuevos.isNotEmpty && nuevos.first == joined.last) {
      nuevos = nuevos.sublist(1);
    }
    joined.addAll(nuevos);
  }
  return joined;
}

/// Calcula la distancia mínima en metros desde [point] hasta la polilínea [polyline].
///
/// Si la polilínea tiene 2 o más puntos, proyecta ortogonalmente [point] a cada
/// segmento vial y calcula la distancia geodésica exacta al punto más cercano.
double distanceToPolyline(LatLng point, List<LatLng> polyline) {
  if (polyline.isEmpty) return double.infinity;
  const distance = Distance();
  if (polyline.length == 1) {
    return distance.as(LengthUnit.Meter, point, polyline.first);
  }

  final latRad = point.latitude * math.pi / 180.0;
  final cosLat = math.cos(latRad);

  double minDistance = double.infinity;

  for (var i = 0; i < polyline.length - 1; i++) {
    final a = polyline[i];
    final b = polyline[i + 1];

    final dx = (b.longitude - a.longitude) * cosLat;
    final dy = b.latitude - a.latitude;
    final segLenSq = dx * dx + dy * dy;

    if (segLenSq == 0) {
      final d = distance.as(LengthUnit.Meter, point, a);
      if (d < minDistance) minDistance = d;
      continue;
    }

    final apx = (point.longitude - a.longitude) * cosLat;
    final apy = point.latitude - a.latitude;

    final t = (apx * dx + apy * dy) / segLenSq;
    final clampedT = t.clamp(0.0, 1.0);

    final closest = LatLng(
      a.latitude + clampedT * (b.latitude - a.latitude),
      a.longitude + clampedT * (b.longitude - a.longitude),
    );

    final d = distance.as(LengthUnit.Meter, point, closest);
    if (d < minDistance) {
      minDistance = d;
    }
  }

  return minDistance;
}

double _pow10(int n) => math.pow(10, n).toDouble();
