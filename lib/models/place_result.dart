import 'package:latlong2/latlong.dart';

/// Una dirección o punto de interés encontrado por el buscador.
///
/// Vivía dentro de `GeocodingService`, lo que obligaba al catálogo de POIs
/// (`data/quilpue_pois.dart`) a importar el servicio que a su vez lo importa a
/// él: un ciclo de dependencias entre datos y servicios.
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
