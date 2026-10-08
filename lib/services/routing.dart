import 'package:latlong2/latlong.dart';

import 'package:taxi1/models/route_path.dart';
import 'package:taxi1/services/osrm_client.dart';
import 'package:taxi1/services/valhalla_client.dart';
import 'package:taxi1/utils/polyline.dart';

/// Velocidad a pie con la que se estima el tiempo cuando el único enrutador
/// que respondió calcula en auto: 1,3 m/s ≈ 4,7 km/h, un paso normal.
const double kWalkingSpeedMps = 1.3;

/// Qué enrutador calcula cada ruta y en qué orden se prueban: Valhalla dentro
/// del teléfono primero y, si no está o no encuentra ruta, OSRM. Ninguno pide
/// clave.
abstract final class Routing {
  /// Trazado de una línea de colectivos por sus paraderos **en orden**, en
  /// auto (respeta el sentido de las calles). `null` si ningún enrutador
  /// respondió.
  static Future<RoutePath?> linePath(List<LatLng> stops) async =>
      await ValhallaClient.route(stops, costing: ValhallaCosting.auto) ??
      await OsrmClient.route(stops);

  /// [linePath] como polilínea (precisión 6): lo que se guarda en el campo
  /// `geometria` de un recorrido.
  static Future<String?> encodedLinePath(List<LatLng> stops) async {
    final path = await linePath(stops);
    return path == null ? null : encodePolyline(path.points);
  }

  /// Ruta a pie de [from] a [to].
  ///
  /// 1. Valhalla peatonal, en el teléfono.
  /// 2. OSRM peatonal (servidor de FOSSGIS).
  /// 3. OSRM en auto, con el tiempo recalculado a paso de peatón: la geometría
  ///    sirve igual para orientarse, pero su tiempo sería el de un auto.
  static Future<RoutePath?> walkingPath(LatLng from, LatLng to) async {
    final points = [from, to];
    final valhalla = await ValhallaClient.route(
      points,
      costing: ValhallaCosting.pedestrian,
    );
    if (valhalla != null) return _withWalkingTime(valhalla);

    final foot = await OsrmClient.route(points, profile: OsrmProfile.foot);
    if (foot != null) return _withWalkingTime(foot);

    final car = await OsrmClient.route(points);
    if (car == null) return null;
    return RoutePath(
      points: car.points,
      distanceMeters: car.distanceMeters,
      durationSeconds: car.distanceMeters / kWalkingSpeedMps,
      provider: car.provider,
    );
  }

  /// Si el enrutador no informó tiempo, a paso de peatón.
  static RoutePath _withWalkingTime(RoutePath path) => path.durationSeconds > 0
      ? path
      : RoutePath(
          points: path.points,
          distanceMeters: path.distanceMeters,
          durationSeconds: path.distanceMeters / kWalkingSpeedMps,
          provider: path.provider,
        );
}
