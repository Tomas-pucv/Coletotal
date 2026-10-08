import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';

import 'package:taxi1/models/route_path.dart';
import 'package:taxi1/services/basemap_service.dart';
import 'package:taxi1/utils/polyline.dart';

/// Medio con el que Valhalla calcula una ruta.
enum ValhallaCosting {
  /// En auto: el trayecto de los colectivos, por calles y en su sentido.
  auto,

  /// A pie: la ruta del pasajero hasta el paradero.
  pedestrian,
}

/// Valhalla dentro del propio teléfono, el enrutador principal de la app.
///
/// Calcula sin conexión con el grafo de calles de la región que viene en el
/// APK (`BasemapService.routingTilesPath`, ver `MainActivity.kt`). Devuelve
/// `null` si no está (iOS, la web, el escritorio, la primera copia todavía en
/// curso) o si no encuentra ruta (un punto fuera de la región): entonces
/// `Routing` le pregunta a OSRM. No se usa ningún servidor de Valhalla.
///
/// Reemplazó al servidor de demostración de OSRM para el trazado de las
/// líneas: el perfil de autos de OSRM pasa por huellas y caminos de servicio
/// (estacionamientos, accesos privados), y el de Valhalla se limita a calles
/// públicas (ver [_soloCallesPublicas]).
abstract final class ValhallaClient {
  /// Puntos por consulta: Valhalla rechaza más con su configuración por
  /// omisión. Una línea con más paraderos se pide en tramos que se solapan en
  /// un paradero.
  static const int maxLocations = 20;

  static const _canal = MethodChannel('cl.coletotal/valhalla');

  /// Valhalla del teléfono: la respuesta en JSON, o `null` si no está o no
  /// encontró ruta.
  static Future<String?> Function(String consulta) _local = _consultaLocal;

  @visibleForTesting
  static set debugLocal(Future<String?> Function(String consulta)? local) =>
      _local = local ?? _consultaLocal;

  static Future<String?> _consultaLocal(String consulta) async {
    if (kIsWeb || !Platform.isAndroid) return null;
    final teselas = BasemapService.instance.routingTilesPath;
    if (teselas == null) return null;
    try {
      return await _canal.invokeMethod<String>('route', {
        'tiles': teselas,
        'request': consulta,
      });
    } on PlatformException catch (e) {
      debugPrint('Valhalla local: ${e.code} ${e.message}');
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// Al ubicar un paradero en auto, sólo calles de residencial hacia arriba:
  /// sin senderos, huellas ni caminos de servicio. Con OSRM (que se usaba
  /// antes) un paradero ubicado lejos de su calle, como el de Villa Olímpica,
  /// se enganchaba a las huellas de los cerros sobre el zoológico y la línea
  /// dibujaba 2 km por donde no pasa ningún colectivo; otras entraban a
  /// estacionamientos y accesos privados.
  static const Map<String, Object> _soloCallesPublicas = {
    'min_road_class': 'residential',
  };

  /// Ruta que pasa por [waypoints] **en orden**. `null` si no se pudo
  /// calcular: quien llama decide si prueba con otro enrutador.
  static Future<RoutePath?> route(
    List<LatLng> waypoints, {
    required ValhallaCosting costing,
  }) async {
    final points = waypoints.where(isValidLatLng).toList(growable: false);
    if (points.length < 2) return null;

    final tramos = <List<LatLng>>[];
    var distance = 0.0;
    var duration = 0.0;
    for (final tramo in chunkWaypoints(points, maxLocations)) {
      final parcial = await _request(tramo, costing);
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
      provider: 'Valhalla',
    );
  }

  static Future<RoutePath?> _request(
    List<LatLng> points,
    ValhallaCosting costing,
  ) async {
    final consulta = {
      'locations': [
        for (final p in points)
          {
            'lat': p.latitude,
            'lon': p.longitude,
            // Cada paradero corta la ruta en un tramo. Se permite dar la
            // vuelta en él: probado con las líneas de la garita, prohibirlo
            // (`break_through`) agregaba vueltas a la manzana más largas que
            // los paraderos mal ubicados que las causaban.
            'type': 'break',
            if (costing == ValhallaCosting.auto)
              'search_filter': _soloCallesPublicas,
          },
      ],
      'costing': costing.name,
      // Sin indicaciones paso a paso: sólo hace falta el trazado.
      'directions_type': 'none',
      'units': 'kilometers',
    };
    final respuesta = await _local(jsonEncode(consulta));
    return respuesta == null ? null : _leer(respuesta, costing);
  }

  /// La ruta de una respuesta de Valhalla, o `null` si no trae una.
  static RoutePath? _leer(String respuesta, ValhallaCosting costing) {
    try {
      final data = json.decode(respuesta);
      if (data is! Map<String, dynamic>) return null;
      final trip = data['trip'];
      if (trip is! Map<String, dynamic>) return null;
      final legs = trip['legs'];
      if (legs is! List || legs.isEmpty) return null;

      final tramos = <List<LatLng>>[];
      for (final leg in legs) {
        final shape = leg is Map ? leg['shape'] : null;
        if (shape is! String || shape.isEmpty) return null;
        tramos.add(decodePolyline(shape).where(isValidLatLng).toList());
      }
      final geometry = joinLegs(tramos);
      if (geometry.isEmpty) return null;

      final summary = trip['summary'];
      final length = summary is Map ? summary['length'] : null;
      final time = summary is Map ? summary['time'] : null;
      return RoutePath(
        points: geometry,
        distanceMeters: length is num ? length * 1000 : 0,
        durationSeconds: time is num ? time.toDouble() : 0,
        provider: 'Valhalla',
      );
    } catch (e) {
      debugPrint('ValhallaClient (${costing.name}): respuesta ilegible: $e');
      return null;
    }
  }
}
