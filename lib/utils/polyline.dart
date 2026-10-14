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

/// El punto de una línea más cercano a otro: dónde queda, a cuántos metros
/// está y en qué punto de la línea cae, medido desde su inicio.
class PuntoEnLinea {
  const PuntoEnLinea({
    required this.punto,
    required this.metros,
    required this.desdeInicio,
  });

  final LatLng punto;

  /// Distancia en línea recta desde el punto consultado.
  final double metros;

  /// Metros recorridos sobre la línea, desde su primer punto hasta [punto].
  /// Es lo que dice si un lugar viene antes o después que otro en el sentido
  /// de marcha.
  final double desdeInicio;
}

const double _radioTierra = 6371008.8;

/// Largo de [linea] en metros (aproximación equirectangular por tramo, de
/// sobra precisa para mostrar "4,3 km").
double polylineLength(List<LatLng> linea) {
  var total = 0.0;
  for (var i = 1; i < linea.length; i++) {
    final a = linea[i - 1];
    final b = linea[i];
    final lat = (a.latitude + b.latitude) / 2 * math.pi / 180;
    final dx = (b.longitude - a.longitude) * math.cos(lat);
    final dy = b.latitude - a.latitude;
    total += math.sqrt(dx * dx + dy * dy) * math.pi / 180 * _radioTierra;
  }
  return total;
}

/// El punto de [linea] más cercano a [p], o `null` si la línea está vacía.
///
/// Proyecta [p] sobre cada tramo en un plano local centrado en él: a la escala
/// de una ciudad el error es de centímetros, y evita la trigonometría esférica
/// en cada uno de los cientos de tramos de un recorrido. Si la línea pasa dos
/// veces igual de cerca, gana la primera pasada.
PuntoEnLinea? nearestOnPolyline(List<LatLng> linea, LatLng p) {
  if (linea.isEmpty) return null;
  final cosLat = math.cos(p.latitude * math.pi / 180);
  const grado = math.pi / 180 * _radioTierra;
  (double, double) plano(LatLng q) => (
    (q.longitude - p.longitude) * grado * cosLat,
    (q.latitude - p.latitude) * grado,
  );
  LatLng esfera(double x, double y) =>
      LatLng(p.latitude + y / grado, p.longitude + x / (grado * cosLat));

  var (ax, ay) = plano(linea.first);
  var mejor = PuntoEnLinea(
    punto: linea.first,
    metros: math.sqrt(ax * ax + ay * ay),
    desdeInicio: 0,
  );
  var acumulado = 0.0;
  for (var i = 1; i < linea.length; i++) {
    final (bx, by) = plano(linea[i]);
    final dx = bx - ax;
    final dy = by - ay;
    final largo2 = dx * dx + dy * dy;
    final largo = math.sqrt(largo2);
    // Dónde cae la perpendicular desde p (el origen) sobre el tramo, acotado
    // a sus extremos.
    final t = largo2 == 0 ? 0.0 : (-(ax * dx + ay * dy) / largo2).clamp(0, 1);
    final px = ax + t * dx;
    final py = ay + t * dy;
    final metros = math.sqrt(px * px + py * py);
    if (metros < mejor.metros) {
      mejor = PuntoEnLinea(
        punto: esfera(px, py),
        metros: metros,
        desdeInicio: acumulado + t * largo,
      );
    }
    acumulado += largo;
    ax = bx;
    ay = by;
  }
  return mejor;
}

/// Un punto de una línea y hacia dónde va la línea ahí.
typedef PuntoConRumbo = ({LatLng punto, double rumbo});

/// Puntos de [linea] cada [metros], desde [desde] metros del inicio, con el
/// rumbo del tramo en que caen: grados desde el norte en sentido horario, el
/// ángulo con que se ve el tramo en un mapa con el norte arriba. Son las
/// flechas que muestran hacia dónde va una línea.
///
/// Usa la misma aproximación por tramo que [polylineLength]. Los tramos de
/// largo cero no tienen rumbo y se saltan.
List<PuntoConRumbo> puntosCada(
  List<LatLng> linea,
  double metros, {
  double desde = 0,
}) {
  if (!(metros > 0) || linea.length < 2) return const [];
  const grado = math.pi / 180 * _radioTierra;
  final puntos = <PuntoConRumbo>[];
  var siguiente = math.max(0.0, desde);
  var recorrido = 0.0;
  for (var i = 1; i < linea.length; i++) {
    final a = linea[i - 1];
    final b = linea[i];
    final cosLat = math.cos((a.latitude + b.latitude) / 2 * math.pi / 180);
    final este = (b.longitude - a.longitude) * cosLat * grado;
    final norte = (b.latitude - a.latitude) * grado;
    final largo = math.sqrt(este * este + norte * norte);
    if (largo == 0) continue;
    final rumbo = (math.atan2(este, norte) * 180 / math.pi + 360) % 360;
    while (siguiente <= recorrido + largo) {
      final t = (siguiente - recorrido) / largo;
      puntos.add((
        punto: LatLng(
          a.latitude + (b.latitude - a.latitude) * t,
          a.longitude + (b.longitude - a.longitude) * t,
        ),
        rumbo: rumbo,
      ));
      siguiente += metros;
    }
    recorrido += largo;
  }
  return puntos;
}

double _pow10(int n) => math.pow(10, n).toDouble();
