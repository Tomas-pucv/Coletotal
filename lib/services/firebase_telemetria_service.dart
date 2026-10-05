import 'dart:async';

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import 'package:taxi1/models/colectivo_activo.dart';
import 'package:taxi1/services/location_service.dart';
import 'package:taxi1/services/session_log_service.dart';

/// Lo que se sabe de la flota en vivo en un momento dado.
@immutable
class TelemetriaState {
  const TelemetriaState({
    this.colectivos = const [],
    this.failed = false,
    this.loaded = false,
  });

  /// Unidades vigentes, ya sin las que llevan demasiado tiempo en silencio.
  final List<ColectivoActivo> colectivos;

  /// Si la última lectura de Realtime Database falló.
  final bool failed;

  /// Si ya llegó al menos una lectura (para no mostrar "no hay unidades"
  /// antes de saberlo).
  final bool loaded;
}

/// Publica y lee las posiciones en vivo de las unidades.
///
/// Realtime Database y no Firestore, siguiendo el reparto del informe §7.3: la
/// telemetría GPS es escritura de alta frecuencia y lectura reactiva, que es
/// justo para lo que sirve RTDB.
///
/// Quien decide *cuándo* transmitir es `TurnoService`, no esta clase ni una
/// pantalla.
class FirebaseTelemetriaService {
  FirebaseTelemetriaService._privateConstructor();
  static final FirebaseTelemetriaService instance =
      FirebaseTelemetriaService._privateConstructor();

  FirebaseDatabase get _rtdb => FirebaseDatabase.instance;
  DatabaseReference get _db => _rtdb.ref('colectivos_activos');

  // --- Lectura: una sola suscripción para toda la app -----------------------

  /// Estado compartido de la flota.
  ///
  /// Antes cada pantalla (mapa, flota, portada de garita, choferes) abría su
  /// propio stream y volvía a parsear el nodo entero con cada movimiento de
  /// cada unidad. Ahora hay un solo listener y las pantallas escuchan esto.
  ValueListenable<TelemetriaState> get state => _state;
  final ValueNotifier<TelemetriaState> _state = ValueNotifier(
    const TelemetriaState(),
  );

  /// Como mucho un aviso por segundo: con veinte choferes enviando cada tres
  /// segundos llegan varios eventos por segundo, y cada uno redibujaba el mapa
  /// entero en teléfonos de gama de entrada.
  static const Duration _throttle = Duration(seconds: 1);

  /// Cada cuánto se vuelve a filtrar la lista aunque no lleguen eventos.
  ///
  /// El filtro de antigüedad sólo corría cuando *algún* nodo cambiaba, así que
  /// cuando el último chofer en servicio se quedaba sin señal (o le cerraban la
  /// app) no llegaba ningún evento más y su marcador quedaba clavado en el mapa
  /// de todos para siempre: justo el "colectivo fantasma" que el filtro debía
  /// evitar.
  static const Duration _refiltro = Duration(seconds: 15);

  StreamSubscription<DatabaseEvent>? _readSub;
  StreamSubscription<DatabaseEvent>? _offsetSub;
  Timer? _throttleTimer;
  Timer? _refiltroTimer;
  Timer? _retryTimer;
  DateTime _lastEmit = DateTime.fromMillisecondsSinceEpoch(0);
  List<ColectivoActivo> _raw = const [];
  bool _readFailed = false;
  bool _readLoaded = false;
  int _serverOffsetMs = 0;

  /// Hora del servidor según este teléfono.
  ///
  /// Las marcas `ts` las pone el servidor, así que la antigüedad de una unidad
  /// se mide contra esto y no contra `DateTime.now()`: el reloj de un teléfono
  /// puede estar desfasado minutos.
  DateTime serverNow() =>
      DateTime.now().add(Duration(milliseconds: _serverOffsetMs));

  /// Abre la lectura de la flota. Se llama una vez desde `main()`.
  void startListening() {
    if (_readSub != null) return;

    _offsetSub ??= _rtdb.ref('.info/serverTimeOffset').onValue.listen((event) {
      final value = event.snapshot.value;
      if (value is num) _serverOffsetMs = value.toInt();
    }, onError: (Object e) => debugPrint('Telemetría: sin offset: $e'));

    _readSub = _db.onValue.listen(
      (event) {
        _raw = parseSnapshot(event.snapshot.value);
        _readFailed = false;
        _readLoaded = true;
        _scheduleEmit();
      },
      onError: (Object e) {
        debugPrint('Telemetría: no se pudo leer la flota: $e');
        _readFailed = true;
        _emit();
        // Un error de RTDB cierra el stream: se reintenta en vez de dejar el
        // mapa sin colectivos hasta reiniciar la app.
        _readSub?.cancel();
        _readSub = null;
        _retryTimer?.cancel();
        _retryTimer = Timer(const Duration(seconds: 30), startListening);
      },
    );

    _refiltroTimer ??= Timer.periodic(_refiltro, (_) {
      if (_raw.isNotEmpty) _emit();
    });
  }

  /// Convierte el nodo `colectivos_activos` en unidades, sin filtrar.
  ///
  /// Una unidad mal formada no tumba a las demás: se salta y se registra.
  @visibleForTesting
  static List<ColectivoActivo> parseSnapshot(Object? data) {
    if (data is! Map) return const [];
    final result = <ColectivoActivo>[];
    for (final entry in data.entries) {
      final value = entry.value;
      if (value is! Map) continue;
      try {
        result.add(ColectivoActivo.fromJson(Map<String, dynamic>.from(value)));
      } catch (e) {
        debugPrint('Telemetría: nodo ilegible (${entry.key}): $e');
      }
    }
    return result;
  }

  /// Las unidades de [raw] que siguen vigentes a la hora del servidor [ahora].
  @visibleForTesting
  static List<ColectivoActivo> vigentes(
    List<ColectivoActivo> raw,
    DateTime ahora,
  ) => raw.where((c) => !c.isStale(ahora)).toList(growable: false);

  /// Fija la flota sin tocar la red. Sólo para tests.
  @visibleForTesting
  void debugSetColectivos(List<ColectivoActivo> colectivos) {
    _raw = colectivos;
    _readLoaded = true;
    _emit();
  }

  void _scheduleEmit() {
    final since = DateTime.now().difference(_lastEmit);
    if (since >= _throttle) {
      _emit();
      return;
    }
    _throttleTimer ??= Timer(_throttle - since, () {
      _throttleTimer = null;
      _emit();
    });
  }

  void _emit() {
    _lastEmit = DateTime.now();
    _state.value = TelemetriaState(
      colectivos: vigentes(_raw, serverNow()),
      failed: _readFailed,
      loaded: _readLoaded,
    );
  }

  // --- Escritura: el turno de este chofer ------------------------------------

  StreamSubscription<Position>? _positionSub;
  StreamSubscription<DatabaseEvent>? _connectedSub;
  ColectivoActivo? _current;
  bool _isTracking = false;
  bool _hasFix = false;
  bool _connected = false;
  bool _onDisconnectArmed = false;

  /// Momento de la última posición que el servidor confirmó.
  ValueListenable<DateTime?> get ultimoEnvio => _ultimoEnvio;
  final ValueNotifier<DateTime?> _ultimoEnvio = ValueNotifier(null);

  /// Si el teléfono del chofer tiene conexión con Realtime Database.
  ValueListenable<bool> get conectado => _conectado;
  final ValueNotifier<bool> _conectado = ValueNotifier(true);

  bool get isTracking => _isTracking;
  ColectivoActivo? get current => _current;
  EstadoCapacidad get estado => _current?.estado ?? EstadoCapacidad.disponible;

  /// Empieza a transmitir la posición de este chofer.
  ///
  /// El GPS ya tiene que estar en modo turno (`LocationService.setDriverMode`):
  /// acá sólo se escuchan sus posiciones. Antes este método abría su propio
  /// stream de geolocator, cuya configuración el plugin ignoraba porque el mapa
  /// ya tenía uno abierto.
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
    _hasFix = false;
    _onDisconnectArmed = false;

    _positionSub = LocationService.instance.positions.listen(
      _onPosition,
      onError: (Object e) {
        SessionLogService.instance.logEvent('GPS_LOST', {
          'error': e.toString(),
        });
      },
    );

    // Presencia: mientras no hay conexión no se escribe nada. Encolar una
    // escritura por cada arreglo de GPS sólo acumulaba cientos de posiciones
    // viejas que se reenviaban todas juntas al recuperar la señal.
    _connectedSub = _rtdb.ref('.info/connected').onValue.listen((event) {
      _onConnectedChanged(event.snapshot.value == true);
    });
  }

  void _onPosition(Position position) {
    final actual = _current;
    if (!_isTracking || actual == null) return;
    _current = actual.copyWith(
      latitud: position.latitude,
      longitud: position.longitude,
    );
    _hasFix = true;
    unawaited(_publicar());
  }

  void _onConnectedChanged(bool connected) {
    final antes = _connected;
    _connected = connected;
    _conectado.value = connected;
    if (connected == antes) return;

    if (connected) {
      // El `onDisconnect` del servidor se consume al dispararse: tras cada
      // reconexión hay que volver a registrarlo.
      _onDisconnectArmed = false;
      unawaited(_publicar());
    } else if (_isTracking) {
      SessionLogService.instance.logEvent('NETWORK_LOST');
    }
  }

  /// Cambia la capacidad reportada sin esperar al siguiente arreglo de GPS.
  Future<void> setEstado(EstadoCapacidad estado) async {
    final actual = _current;
    if (actual == null) return;
    _current = actual.copyWith(estado: estado);
    if (_isTracking) await _publicar();
  }

  /// Cambia la línea que el chofer dice estar cubriendo; `null` la quita.
  Future<void> setRecorrido(String? id, String? nombre) async {
    final actual = _current;
    if (actual == null) return;
    _current = id == null
        ? actual.copyWith(clearRecorrido: true)
        : actual.copyWith(recorridoId: id, recorridoNombre: nombre);
    if (_isTracking) await _publicar();
  }

  Future<void> _publicar() async {
    final actual = _current;
    if (actual == null || !_isTracking || !_hasFix || !_connected) return;

    final ref = _db.child(actual.uid);
    try {
      await ref.set({
        ...actual.copyWith(conectado: true).toJson(),
        // El sello lo pone el servidor: el reloj del teléfono puede estar mal y
        // el filtro de unidades fantasma depende de esta marca.
        'ts': ServerValue.timestamp,
      });
      _ultimoEnvio.value = DateTime.now();

      // Recién ahora, con el nodo completo ya escrito, se registra el aviso de
      // desconexión. Registrado antes —como estaba— fallaba siempre: las
      // reglas validan el `update` contra un nodo que todavía no existe y le
      // faltan los campos obligatorios. Y como se esperaba sin try/catch, la
      // excepción dejaba el botón de turno girando para siempre.
      if (!_onDisconnectArmed && _isTracking) {
        _onDisconnectArmed = true;
        unawaited(
          ref
              .onDisconnect()
              .update({'conectado': false, 'ts': ServerValue.timestamp})
              .catchError((Object e) {
                _onDisconnectArmed = false;
                debugPrint('Telemetría: no se registró el onDisconnect: $e');
              }),
        );
      }
    } catch (e) {
      debugPrint('Telemetría: no se pudo publicar la posición: $e');
      SessionLogService.instance.logEvent('NETWORK_FAIL', {
        'error': e.toString(),
      });
    }
  }

  /// Deja de transmitir y borra el nodo.
  ///
  /// Hay que **esperarlo** antes de cerrar sesión: el borrado necesita el token
  /// todavía vigente. La espera está acotada: sin red, Realtime Database no
  /// confirma nunca, y antes eso dejaba el botón "Terminar turno" (y el cierre
  /// de sesión, que espera a este método) colgados hasta recuperar señal. Si
  /// se agota el plazo, el borrado sigue en la cola del SDK y, si nunca llega,
  /// el filtro de antigüedad saca a la unidad del mapa a los tres minutos.
  Future<void> detenerTracking() async {
    _isTracking = false;
    await _positionSub?.cancel();
    _positionSub = null;
    await _connectedSub?.cancel();
    _connectedSub = null;
    _connected = false;
    _hasFix = false;
    _onDisconnectArmed = false;
    _ultimoEnvio.value = null;
    _conectado.value = true;

    final actual = _current;
    _current = null;
    if (actual == null) return;

    final ref = _db.child(actual.uid);
    try {
      await Future.wait([
        ref.onDisconnect().cancel(),
        ref.remove(),
      ]).timeout(const Duration(seconds: 4));
    } on TimeoutException {
      debugPrint('Telemetría: sin confirmación del borrado; queda en cola.');
    } catch (e) {
      debugPrint('Telemetría: no se pudo remover el vehículo: $e');
    }
  }
}
