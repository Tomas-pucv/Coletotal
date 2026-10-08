import 'package:latlong2/latlong.dart';

import 'package:taxi1/utils/tile_coords.dart';

/// Centro de Quilpué: punto de partida del mapa y de las miniaturas.
const LatLng kQuilpueCenter = LatLng(-33.0472, -71.4425);

// Zooms en la escala de MapLibre, que usa teselas de 512 px: su zoom z muestra
// lo mismo que flutter_map mostraba en z + 1. Por eso todos bajaron en uno al
// cambiar de motor; lo que se ve en pantalla es igual que antes.

const double kInitialZoom = 13;

/// Para mirar una cuadra: al centrar en un paradero o en un colectivo.
const double kStreetZoom = 15;

/// Para ubicar un destino buscado con su entorno.
const double kPlaceZoom = 14;

/// Con 3 cabe Chile entero en la pantalla de un teléfono.
const double kMinZoom = 3;

/// Las teselas de detalle llegan a z15; de ahí en adelante sólo se agrandan,
/// y más allá de 18 ya no se distingue nada nuevo.
const double kMaxZoom = 18;

/// Un rectángulo de coordenadas.
class GeoBounds {
  const GeoBounds({
    required this.north,
    required this.south,
    required this.east,
    required this.west,
  });

  final double north;
  final double south;
  final double east;
  final double west;

  LatLng get southWest => LatLng(south, west);
  LatLng get northEast => LatLng(north, east);

  bool contains(LatLng point) =>
      point.latitude <= north &&
      point.latitude >= south &&
      point.longitude <= east &&
      point.longitude >= west;

  bool containsBounds(GeoBounds other) =>
      other.north <= north &&
      other.south >= south &&
      other.east <= east &&
      other.west >= west;
}

/// Chile continental, el territorio de `assets/map/chile.pmtiles` (la vista
/// general). La cámara no sale de aquí: afuera no hay mapa que dibujar. El
/// archivo cubre además el mar hacia el oeste, para que al alejar el mapa el
/// Pacífico no quede en blanco (ver `scripts/mapa_base/build.js`).
const GeoBounds kChileBounds = GeoBounds(
  north: -17.506588,
  south: -55.918504,
  east: -66.4208064,
  west: -75.711415,
);

/// Región de Valparaíso continental: donde `assets/map/valparaiso.pmtiles`
/// tiene todas las calles. También acota al buscador, para que cada resultado
/// caiga sobre mapa dibujado.
const GeoBounds kDetailBounds = GeoBounds(
  north: -32.020791,
  south: -33.955888,
  east: -69.989346,
  west: -71.843144,
);

/// Estilo cartográfico elegible por el usuario.
enum MapStyle {
  normal,
  satellite;

  /// Valor persistido en [PreferencesService.mapType].
  String get prefValue => this == MapStyle.satellite ? 'satellite' : 'normal';

  static MapStyle fromPref(String value) =>
      value == 'satellite' ? MapStyle.satellite : MapStyle.normal;
}

/// Fotografía aérea de Esri (World Imagery). Es la única capa que sigue
/// viniendo de la red: ningún proveedor gratuito permite llevar sus imágenes
/// dentro de una app, y la única libre (Sentinel-2, 10 m por píxel) no deja
/// ver las calles. No pide clave ni cuenta; sí la mención de "Esri" en el mapa.
///
/// El estilo satelital (`assets/map/style_satellite.json`) trae esta misma
/// dirección; `test/basemap_test.dart` comprueba que coincidan. Esri no ofrece
/// versión `@2x` y sus índices van en orden `{z}/{y}/{x}`.
const String kSatelliteTileUrlTemplate =
    'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}';

/// URL de una tesela satelital concreta, para la miniatura del selector de
/// estilo: basta una imagen para un recuadro de 2 cm.
String satelliteThumbnailUrl({LatLng center = kQuilpueCenter, int zoom = 14}) {
  final tile = tileIndexFor(center, zoom);
  return kSatelliteTileUrlTemplate
      .replaceFirst('{z}', '${tile.z}')
      .replaceFirst('{y}', '${tile.y}')
      .replaceFirst('{x}', '${tile.x}');
}
