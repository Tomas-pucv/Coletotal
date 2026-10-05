import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:taxi1/models/bus_stop.dart';
import 'package:taxi1/services/osrm_client.dart';
import 'package:taxi1/services/route_service.dart';

http.Response _osrm(List<LatLng> puntos, double distance, double duration) =>
    http.Response(
      jsonEncode({
        'code': 'Ok',
        'routes': [
          {
            'geometry': OsrmClient.encodePolyline(puntos),
            'distance': distance,
            'duration': duration,
          },
        ],
      }),
      200,
    );

void main() {
  const origen = LatLng(-33.0472, -71.4425);
  const a = BusStop(
    id: 'a',
    name: 'A',
    address: 'A',
    location: LatLng(-33.0438, -71.4390),
  );
  const b = BusStop(
    id: 'b',
    name: 'B',
    address: 'B',
    location: LatLng(-33.0510, -71.4480),
  );

  final service = RouteService.instance;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    service.clearDestination();
  });

  tearDown(() => OsrmClient.debugClient = http.Client());

  test('la ruta es a pie: usa el servidor peatonal y su tiempo', () async {
    final urls = <String>[];
    OsrmClient.debugClient = MockClient((request) async {
      urls.add(request.url.toString());
      return _osrm([origen, a.location], 642, 517);
    });

    service.setDestination(a);
    expect(await service.fetchRoute(origen, a), isTrue);

    expect(urls.single, contains('routed-foot'));
    expect(service.routeInfo!.durationSeconds, 517);
  });

  test('si sólo responde el servidor de autos, el tiempo es a paso de peatón',
      () async {
    // Antes se mostraba el tiempo en auto como si fuera caminando: 640 m de
    // caminata aparecían como dos minutos.
    OsrmClient.debugClient = MockClient((request) async {
      if (request.url.toString().contains('routed-foot')) {
        return http.Response('caído', 503);
      }
      return _osrm([origen, a.location], 1300, 120);
    });

    service.setDestination(a);
    expect(await service.fetchRoute(origen, a), isTrue);

    expect(
      service.routeInfo!.durationSeconds,
      closeTo(1300 / kWalkingSpeedMps, 1e-6),
    );
  });

  test('una respuesta que llega tarde no pisa a la ruta vigente', () async {
    final lenta = Completer<void>();
    OsrmClient.debugClient = MockClient((request) async {
      final haciaA = request.url.toString().contains('${a.location.longitude}');
      if (haciaA) await lenta.future;
      return haciaA
          ? _osrm([origen, a.location], 111, 100)
          : _osrm([origen, b.location], 222, 200);
    });

    service.setDestination(a);
    final primera = service.fetchRoute(origen, a);
    service.setDestination(b);
    final segunda = service.fetchRoute(origen, b);

    expect(await segunda, isTrue);
    lenta.complete();
    expect(await primera, isFalse);

    expect(service.destination, b);
    expect(service.routeInfo!.distanceMeters, 222);
  });

  test('cambiar de paradero borra la ruta anterior', () async {
    OsrmClient.debugClient = MockClient(
      (_) async => _osrm([origen, a.location], 642, 517),
    );
    service.setDestination(a);
    await service.fetchRoute(origen, a);
    expect(service.routePoints, isNotEmpty);

    // Mientras se calcula la nueva, la vieja no puede seguir dibujada bajo el
    // nombre del paradero nuevo.
    service.setDestination(b);
    expect(service.routePoints, isEmpty);
    expect(service.routeInfo, isNull);
  });

  test('coordenadas inválidas no salen a la red', () async {
    var peticiones = 0;
    OsrmClient.debugClient = MockClient((_) async {
      peticiones++;
      return http.Response('', 500);
    });

    expect(
      await service.fetchRoute(const LatLng(double.nan, 0), a),
      isFalse,
    );
    expect(service.lastError, 'invalid_coords');
    expect(peticiones, 0);
  });
}
