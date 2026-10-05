import 'dart:async';
import 'dart:ui' show Locale;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState, WidgetsBinding, WidgetsBindingObserver;
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import 'package:taxi1/l10n/app_localizations.dart';
import 'package:taxi1/services/preferences_service.dart';

/// Motivo por el que no hay posición del usuario.
enum LocationIssue { none, disabledByPreference, serviceDisabled, denied }

/// Dueño único del GPS del teléfono.
///
/// Antes tres sitios abrían el GPS por su cuenta: `MapScreen`, `RoutesScreen`
/// y la telemetría del chofer. Eso tenía dos fallas que no se veían en el
/// código, sino dentro del plugin:
///
///  * **geolocator mantiene un solo stream de posiciones** y, mientras siga
///    vivo, ignora los `locationSettings` de quien lo pide después. El mapa
///    abría el suyo al arrancar la app (el `IndexedStack` lo monta siempre),
///    así que la configuración del turno —servicio en primer plano con
///    notificación y wake lock— nunca llegaba a aplicarse. Con la pantalla
///    bloqueada Android estrangulaba el GPS y el colectivo desaparecía del
///    mapa de los pasajeros a los tres minutos.
///  * **geolocator guarda un solo callback de permiso.** Mapa y Paraderos lo
///    pedían a la vez en el primer arranque; el segundo pisaba al primero y
///    el `Future` del mapa no se completaba nunca, así que el mapa no seguía al
///    usuario hasta que éste tocaba el botón de recentrar.
///
/// Por eso ahora hay **un** stream, abierto acá, con la configuración que
/// corresponde ([setDriverMode]), y **una** solicitud de permiso compartida
/// ([ensurePermission]). Las pantallas escuchan este servicio y la telemetría
/// se suscribe a [positions].
class LocationService extends ChangeNotifier with WidgetsBindingObserver {
  LocationService._();
  static final LocationService instance = LocationService._();

  final _prefs = PreferencesService.instance;

  LatLng? _position;
  double? _accuracy;
  LocationIssue _issue = LocationIssue.none;
  bool _driverMode = false;
  bool _started = false;

  StreamSubscription<Position>? _sub;
  final StreamController<Position> _positions =
      StreamController<Position>.broadcast();
  Future<LocationIssue>? _permissionInFlight;

  /// Los reinicios del stream se encadenan: dos cambios seguidos de modo no
  /// pueden dejar dos suscripciones abiertas contra el plugin.
  Future<void> _restartChain = Future<void>.value();

  /// Última posición válida conocida. `null` mientras no hay ninguna o si el
  /// usuario apagó la ubicación en Preferencias.
  LatLng? get position => _position;

  /// Precisión de [position], en metros.
  double? get accuracy => _accuracy;

  LocationIssue get issue => _issue;

  /// Si el GPS está configurado para el turno del chofer.
  bool get driverMode => _driverMode;

  /// Cada posición nueva del GPS, sin la siembra inicial de
  /// `getLastKnownPosition`: la telemetría no debe publicar una posición vieja
  /// como si fuera actual.
  Stream<Position> get positions => _positions.stream;

  /// Abre el GPS según las preferencias. Se llama una vez desde `main()`.
  Future<void> start() async {
    if (_started) return;
    _started = true;
    _prefs.addListener(_onPrefsChanged);
    WidgetsBinding.instance.addObserver(this);
    await _restart();
  }

  /// Al volver a la app se reintenta si faltaba el GPS o el permiso: lo normal
  /// es que el usuario haya ido a los ajustes del teléfono justamente a eso, y
  /// antes tenía que volver a tocar "Reintentar" o el botón de centrar.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    if (_issue == LocationIssue.serviceDisabled ||
        _issue == LocationIssue.denied) {
      unawaited(_restart());
    }
  }

  /// Vuelve a intentar: tras activar el GPS o conceder el permiso desde los
  /// ajustes del teléfono.
  Future<void> retry() => _restart();

  /// Configura el GPS para el turno del chofer ([enabled]) o para el pasajero.
  ///
  /// Devuelve el problema de ubicación que impidió abrirlo, o
  /// [LocationIssue.none] si quedó funcionando.
  Future<LocationIssue> setDriverMode(bool enabled) async {
    if (_driverMode != enabled || _sub == null) {
      _driverMode = enabled;
      await _restart();
    }
    return _issue;
  }

  /// Pide permiso de ubicación una sola vez aunque varios lo pidan a la vez:
  /// todos comparten la misma solicitud en curso.
  Future<LocationIssue> ensurePermission() => _permissionInFlight ??=
      _checkPermission().whenComplete(() => _permissionInFlight = null);

  Future<bool> openLocationSettings() => Geolocator.openLocationSettings();

  Future<bool> openAppSettings() => Geolocator.openAppSettings();

  // --- Interno ---------------------------------------------------------------

  /// El turno necesita el GPS aunque el pasajero lo tenga apagado en
  /// Preferencias; en la práctica `TurnoService` ya baja el turno cuando eso
  /// pasa, así que es sólo un orden de evaluación.
  bool get _wantsStream => _driverMode || _prefs.locationTracking;

  void _onPrefsChanged() {
    final abierto = _sub != null;
    if (_wantsStream != abierto) unawaited(_restart());
  }

  Future<void> _restart() {
    final next = _restartChain.then((_) => _doRestart());
    _restartChain = next.catchError((Object e) {
      debugPrint('LocationService: no se pudo reiniciar el GPS: $e');
    });
    return _restartChain;
  }

  Future<void> _doRestart() async {
    // Cancelar la única suscripción hace que geolocator descarte su stream
    // cacheado, y el próximo `getPositionStream` sí aplica la configuración
    // nueva.
    await _sub?.cancel();
    _sub = null;

    if (!_wantsStream) {
      // Con la ubicación apagada no se muestra una posición vieja como si
      // fuera la actual.
      _position = null;
      _accuracy = null;
      _issue = LocationIssue.disabledByPreference;
      notifyListeners();
      return;
    }

    final issue = await ensurePermission();
    if (issue != LocationIssue.none) {
      _setIssue(issue);
      return;
    }

    // Mientras llega el primer arreglo (que en interiores puede tardar), la
    // última posición conocida ya sirve para centrar el mapa y ordenar los
    // paraderos.
    if (_position == null) {
      try {
        final last = await Geolocator.getLastKnownPosition();
        if (last != null) _accept(last, fresh: false);
      } catch (_) {}
    }

    _sub = Geolocator.getPositionStream(locationSettings: _settings()).listen(
      _accept,
      onError: (Object e) {
        debugPrint('LocationService: error del GPS: $e');
        // La telemetría lo registra en la auditoría del turno.
        _positions.addError(e);
        _setIssue(LocationIssue.serviceDisabled);
      },
    );
    _setIssue(LocationIssue.none);
  }

  Future<LocationIssue> _checkPermission() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return LocationIssue.serviceDisabled;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return LocationIssue.denied;
      }
      return LocationIssue.none;
    } catch (e) {
      // En plataformas sin geolocator (Windows, web de escritorio) estas
      // llamadas lanzan.
      debugPrint('LocationService: no se pudo consultar el permiso: $e');
      return LocationIssue.serviceDisabled;
    }
  }

  LocationSettings _settings() {
    if (defaultTargetPlatform == TargetPlatform.android) {
      final l10n = lookupAppLocalizations(const Locale('es'));
      return AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
        intervalDuration: _driverMode ? const Duration(seconds: 3) : null,
        // Servicio en primer plano sólo durante el turno: es lo que mantiene
        // vivo el GPS con la pantalla bloqueada y protege al proceso del
        // "low memory killer" en teléfonos de gama de entrada.
        foregroundNotificationConfig: _driverMode
            ? ForegroundNotificationConfig(
                notificationTitle: l10n.turnoNotificationTitle,
                notificationText: l10n.turnoNotificationText,
                enableWakeLock: true,
                setOngoing: true,
              )
            : null,
      );
    }
    if (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS) {
      return AppleSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
        activityType: _driverMode
            ? ActivityType.automotiveNavigation
            : ActivityType.other,
        pauseLocationUpdatesAutomatically: false,
        allowBackgroundLocationUpdates: _driverMode,
        showBackgroundLocationIndicator: _driverMode,
      );
    }
    return const LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 5,
    );
  }

  void _accept(Position p, {bool fresh = true}) {
    final lat = p.latitude;
    final lng = p.longitude;
    // En emuladores o antes del primer arreglo real, Geolocator puede devolver
    // 0,0 o NaN, lo que rompe flutter_map ("LatLng is not finite").
    if (!lat.isFinite || !lng.isFinite || (lat == 0.0 && lng == 0.0)) return;

    _position = LatLng(lat, lng);
    _accuracy = p.accuracy;
    _issue = LocationIssue.none;
    if (fresh) _positions.add(p);
    notifyListeners();
  }

  void _setIssue(LocationIssue issue) {
    if (_issue == issue) return;
    _issue = issue;
    notifyListeners();
  }

  /// Devuelve el servicio a su estado inicial. Sólo para tests.
  @visibleForTesting
  Future<void> debugReset() async {
    await _sub?.cancel();
    _sub = null;
    _prefs.removeListener(_onPrefsChanged);
    if (_started) WidgetsBinding.instance.removeObserver(this);
    _started = false;
    _driverMode = false;
    _position = null;
    _accuracy = null;
    _issue = LocationIssue.none;
    _permissionInFlight = null;
    _restartChain = Future<void>.value();
  }
}
