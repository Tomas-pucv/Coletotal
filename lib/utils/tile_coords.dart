import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

/// Índice de una tesela (tile) en el esquema Web Mercator / slippy map.
typedef TileIndex = ({int x, int y, int z});

/// Convierte una coordenada geográfica al índice de tesela que la contiene.
///
/// Se usa para pedirle a Esri *una sola* tesela de foto aérea como miniatura
/// del selector de estilo de mapa, en vez de abrir un mapa completo (que
/// arrastraría una vista nativa y varias peticiones de red) sólo para mostrar
/// un cuadrado de 2 cm.
TileIndex tileIndexFor(LatLng point, int zoom) {
  final n = 1 << zoom;

  final x = ((point.longitude + 180.0) / 360.0 * n).floor();

  final latRad = point.latitude * math.pi / 180.0;
  final y =
      ((1.0 - math.log(math.tan(latRad) + 1 / math.cos(latRad)) / math.pi) /
              2.0 *
              n)
          .floor();

  return (x: x.clamp(0, n - 1), y: y.clamp(0, n - 1), z: zoom);
}

/// Centro y zoom (escala de MapLibre, teselas de 512 px) con que [puntos]
/// caben enteros en una vista de [ancho] × [alto] píxeles lógicos, dejando un
/// margen de [relleno] píxeles por lado.
///
/// Sirve para mostrar una línea de colectivos completa al elegirla. Se calcula
/// en Web Mercator, como el mapa: así la latitud ocupa en pantalla lo mismo que
/// el cálculo.
({LatLng centro, double zoom}) encuadre(
  List<LatLng> puntos, {
  required double ancho,
  required double alto,
  double relleno = 48,
  double zoomMinimo = 3,
  double zoomMaximo = 16,
}) {
  double mercatorY(double lat) {
    final rad = lat * math.pi / 180;
    return math.log(math.tan(math.pi / 4 + rad / 2));
  }

  var minLat = double.infinity, maxLat = -double.infinity;
  var minLng = double.infinity, maxLng = -double.infinity;
  for (final p in puntos) {
    minLat = math.min(minLat, p.latitude);
    maxLat = math.max(maxLat, p.latitude);
    minLng = math.min(minLng, p.longitude);
    maxLng = math.max(maxLng, p.longitude);
  }
  final centro = LatLng((minLat + maxLat) / 2, (minLng + maxLng) / 2);

  // Fracción del mundo (de 0 a 1) que ocupa la caja en cada eje.
  final fx = (maxLng - minLng) / 360;
  final fy = (mercatorY(maxLat) - mercatorY(minLat)) / (2 * math.pi);
  final w = math.max(ancho - 2 * relleno, 1.0);
  final h = math.max(alto - 2 * relleno, 1.0);
  // En el zoom z el mundo mide 512·2^z píxeles.
  double zoomPara(double fraccion, double pixeles) => fraccion <= 0
      ? zoomMaximo
      : math.log(pixeles / (fraccion * 512)) / math.ln2;
  final zoom = math.min(zoomPara(fx, w), zoomPara(fy, h));
  return (centro: centro, zoom: zoom.clamp(zoomMinimo, zoomMaximo).toDouble());
}
