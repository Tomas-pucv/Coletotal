import 'dart:async';

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import 'package:taxi1/models/colectivo_activo.dart';
import 'package:taxi1/services/session_log_service.dart';

/// Publica y lee las posiciones en vivo de las unidades.
///
/// Realtime Database y no Firestore, siguiendo el reparto del informe §7.3: la
/// telemetría GPS es escritura de alta frecuencia y lectura reactiva, que es
/// justo para lo que sirve RTDB.
///
/// Quien decide *cuándo* transmitir es `TurnoService`, no esta clase ni una
/// pantalla: ver la nota en [iniciarTracking].
class FirebaseTelemetriaService {
  FirebaseTelemetriaService._privateConstructor();
  static final FirebaseTelemetriaService instance =
      FirebaseTelemetriaService._privateConstructor();

  DatabaseReference get _db =>
      FirebaseDatabase.instance.ref('colectivos_activos');

  StreamSubscription<Position>? _positionSubscription;
  ColectivoActivo? _current;
  bool _isTracking = false;

  bool get isTracking => _isTracking;
  ColectivoActivo? get current => _current;
  EstadoCapacidad get estado => _current?.estado ?? EstadoCapacidad.disponible;

  /// Última posición publicada, para que la pantalla de turno pueda mostrar
  /// algo concreto en vez de un "transmitiendo" a ciegas.
  DateTime? _ultimoEnvio;
  DateTime? get ultimoEnvio => _ultimoEnvio;

  /// Todas las unidades activas, ya filtradas de fantasmas.
  Stream<List<ColectivoActivo>> get telemetriaStream {
    return _db.onValue.map((event) {
      final snapshot = event.snapshot;
      if (!snapshot.exists || snapshot.value == null) {
        return const <ColectivoActivo>[];
      }

      final data = snapshot.value;
      if (data is! Map) return const <ColectivoActivo>[];

      final ahora = DateTime.now();
      final result = <ColectivoActivo>[];
      for (final entry in data.entries) {
        final value = entry.value;
        if (value is! Map) continue;
        try {
          final colectivo = ColectivoActivo.fromJson(
            Map<String, dynamic>.from(value),
          );
          // Una unidad mal formada ya no tumba a las demás: antes un solo nodo
          // corrupto hacía que el `map` entero devolviera lista vacía y el mapa
          // se quedaba sin ningún colectivo.
          if (colectivo.isStale(ahora)) continue;
          result.add(colectivo);
        } catch (e) {
          debugPrint('Telemetría: nodo ilegible (${entry.key}): $e');
        }
      }
      return result;
    });
  }

  /// Empieza a transmitir la posición de este chofer.
  ///
  /// Se llama **sólo** desde `TurnoService`. Antes vivía en `MapScreen`, que
  /// además lo detenía en su `dispose()`: eso funcionaba de casualidad porque
  /// el `IndexedStack` mantenía la pantalla viva para siempre. Con la lista de
  /// pantallas dependiendo del rol, un cambio de rol reconstruye elementos y
  /// habría cortado la transmisión en silencio.
  Future<void> iniciarTracking({
    required String uid,
    required String patente,
    required String garitaId,
    EstadoCapacidad estado = EstadoCapacidad.disponible,
    String? recorridoId,
    String? recorridoNombre,
  }) async {
    if (_isTracking && _current?.uid == uid) return;
    await detenerTracking();

    if (!await Geolocator.isLocationServiceEnabled()) return;

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }
    if (permission == LocationPermission.deniedForever) return;

    _current = ColectivoActivo(
      uid: uid,
      idVehiculo: patente,
      garitaId: garitaId,
      latitud: 0,
      longitud: 0,
      estado: estado,
      recorridoId: recorridoId,
      recorridoNombre: recorridoNombre,
    );
    _isTracking = true;

    // En vez de borrar inmediatamente ante desconexión de socket (lo que causaba
    // que el colectivo desapareciera en zonas de sombra o túneles de Quilpué),
    // el nodo permanece en el mapa mientras dure el turno o hasta expirar la
    // antigüedad máxima de telemetría (180 segundos).
    final vehicleRef = _db.child(uid);
    await vehicleRef.onDisconnect().update({
      'conectado': false,
      'ts': ServerValue.timestamp,
    });

    // Configuración para permitir rastreo continuo en segundo plano en Android.
    final LocationSettings locationSettings;
    if (defaultTargetPlatform == TargetPlatform.android) {
      locationSettings = AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
        intervalDuration: const Duration(seconds: 3),
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'ColeTotal — en servicio',
          notificationText: 'Transmitiendo tu posición a los pasajeros',
          enableWakeLock: true,
          setOngoing: true,
        ),
      );
    } else {
      locationSettings = const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
      );
    }

    _positionSubscription =
        Geolocator.getPositionStream(locationSettings: locationSettings).listen(
          (position) {
            final actual = _current;
            if (!_isTracking || actual == null) return;

            final lat = position.latitude;
            final lng = position.longitude;
            if (!lat.isFinite || !lng.isFinite || (lat == 0.0 && lng == 0.0)) {
              return;
            }

            _current = actual.copyWith(latitud: lat, longitud: lng);
            _publicar();
          },
          onError: (Object e) {
            debugPrint('Error en el stream de ubicación en vivo: $e');
            SessionLogService.instance.logEvent('GPS_LOST', {'error': e.toString()});
          },
        );
  }

  /// Cambia la capacidad reportada sin esperar al siguiente arreglo de GPS.
  Future<void> setEstado(EstadoCapacidad estado) async {
    final actual = _current;
    if (actual == null) return;
    _current = actual.copyWith(estado: estado);
    if (_isTracking) await _publicar();
  }

  Future<void> _publicar() async {
    final actual = _current;
    if (actual == null) return;
    try {
      await _db.child(actual.uid).set({
        ...actual.toJson(),
        // El sello lo pone el servidor: el reloj del teléfono puede estar mal y
        // el filtro de unidades fantasma depende de esta marca.
        'ts': ServerValue.timestamp,
      });
      _ultimoEnvio = DateTime.now();
    } catch (e) {
      debugPrint('Telemetría: no se pudo publicar la posición: $e');
      SessionLogService.instance.logEvent('NETWORK_FAIL', {'error': e.toString()});
    }
  }

  /// Deja de transmitir y borra el nodo.
  ///
  /// Devuelve un `Future` que hay que **esperar** antes de cerrar sesión: el
  /// borrado necesita el token de autenticación todavía vigente.
  Future<void> detenerTracking() async {
    _isTracking = false;
    await _positionSubscription?.cancel();
    _positionSubscription = null;
    _ultimoEnvio = null;

    final actual = _current;
    _current = null;
    if (actual == null) return;

    try {
      await _db.child(actual.uid).onDisconnect().cancel();
      await _db.child(actual.uid).remove();
    } catch (e) {
      debugPrint('Telemetría: no se pudo remover el vehículo: $e');
    }
  }
}
