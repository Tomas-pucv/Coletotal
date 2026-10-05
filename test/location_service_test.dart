import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:taxi1/services/location_service.dart';
import 'package:taxi1/services/preferences_service.dart';

/// GPS falso: registra cada solicitud de permiso y la configuración con la que
/// se abre cada stream, que es justo lo que el plugin real no deja ver.
class _FakeGeolocator extends GeolocatorPlatform
    with MockPlatformInterfaceMixin {
  LocationPermission permission = LocationPermission.denied;
  Completer<LocationPermission> pendingRequest = Completer();
  int requestCount = 0;
  final List<LocationSettings?> streamSettings = [];
  StreamController<Position>? controller;

  @override
  Future<bool> isLocationServiceEnabled() async => true;

  @override
  Future<LocationPermission> checkPermission() async => permission;

  @override
  Future<LocationPermission> requestPermission() {
    requestCount++;
    return pendingRequest.future;
  }

  @override
  Future<Position?> getLastKnownPosition({
    bool forceLocationManager = false,
  }) async => null;

  @override
  Stream<Position> getPositionStream({LocationSettings? locationSettings}) {
    streamSettings.add(locationSettings);
    controller = StreamController<Position>();
    return controller!.stream;
  }
}

Position _pos(double lat, double lng) => Position(
  latitude: lat,
  longitude: lng,
  timestamp: DateTime(2026, 10, 5),
  accuracy: 8,
  altitude: 0,
  altitudeAccuracy: 0,
  heading: 0,
  headingAccuracy: 0,
  speed: 0,
  speedAccuracy: 0,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeGeolocator fake;
  final service = LocationService.instance;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await PreferencesService.instance.load();
  });

  setUp(() async {
    await service.debugReset();
    fake = _FakeGeolocator();
    GeolocatorPlatform.instance = fake;
    await PreferencesService.instance.setLocationTracking(true);
  });

  tearDown(() => service.debugReset());

  test('dos pantallas que piden permiso a la vez comparten una solicitud', () async {
    // El mapa y la pestaña Paraderos lo pedían juntos en el primer arranque.
    // El plugin guarda un solo callback, así que el segundo pedido dejaba al
    // primero esperando para siempre.
    final a = service.ensurePermission();
    final b = service.ensurePermission();

    fake.pendingRequest.complete(LocationPermission.whileInUse);

    expect(await a, LocationIssue.none);
    expect(await b, LocationIssue.none);
    expect(fake.requestCount, 1);
  });

  test('un permiso denegado se informa como problema, sin abrir el GPS', () async {
    fake.pendingRequest.complete(LocationPermission.deniedForever);
    await service.start();

    expect(service.issue, LocationIssue.denied);
    expect(fake.streamSettings, isEmpty);
  });

  test('el turno reabre el GPS con servicio en primer plano', () async {
    // Antes la configuración del turno nunca llegaba al plugin: el mapa ya
    // tenía un stream abierto y geolocator devolvía ese, sin notificación ni
    // wake lock, así que con la pantalla bloqueada el GPS se detenía.
    fake.permission = LocationPermission.whileInUse;
    await service.start();

    expect(fake.streamSettings, hasLength(1));
    final pasajero = fake.streamSettings.last as AndroidSettings;
    expect(pasajero.foregroundNotificationConfig, isNull);

    expect(await service.setDriverMode(true), LocationIssue.none);
    expect(fake.streamSettings, hasLength(2));
    final turno = fake.streamSettings.last as AndroidSettings;
    expect(turno.foregroundNotificationConfig, isNotNull);
    expect(turno.foregroundNotificationConfig!.enableWakeLock, isTrue);
    expect(turno.intervalDuration, const Duration(seconds: 3));

    await service.setDriverMode(false);
    final despues = fake.streamSettings.last as AndroidSettings;
    expect(despues.foregroundNotificationConfig, isNull);
  });

  test('descarta posiciones inválidas y publica las buenas', () async {
    fake.permission = LocationPermission.whileInUse;
    await service.start();

    final recibidas = <Position>[];
    final sub = service.positions.listen(recibidas.add);

    fake.controller!.add(_pos(0, 0)); // emulador sin arreglo
    fake.controller!.add(_pos(-33.0472, -71.4425));
    await Future<void>.delayed(Duration.zero);

    expect(recibidas, hasLength(1));
    expect(service.position?.latitude, closeTo(-33.0472, 1e-9));
    expect(service.accuracy, 8);
    await sub.cancel();
  });

  test('apagar la ubicación en Preferencias cierra el GPS y la olvida', () async {
    fake.permission = LocationPermission.whileInUse;
    await service.start();
    fake.controller!.add(_pos(-33.0472, -71.4425));
    await Future<void>.delayed(Duration.zero);
    expect(service.position, isNotNull);

    await PreferencesService.instance.setLocationTracking(false);
    await Future<void>.delayed(Duration.zero);
    await service.retry();

    expect(service.issue, LocationIssue.disabledByPreference);
    expect(service.position, isNull);
  });
}
