import 'package:latlong2/latlong.dart';

/// Una ruta calculada por un enrutador: los puntos que siguen las calles, su
/// largo y su duración.
class RoutePath {
  const RoutePath({
    required this.points,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.provider,
  });

  final List<LatLng> points;
  final double distanceMeters;
  final double durationSeconds;

  /// Quién la calculó (`Valhalla`, `OSRM`), para mostrarlo en la ficha.
  final String provider;
}
