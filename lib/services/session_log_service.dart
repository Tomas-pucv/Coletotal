import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:taxi1/config/app_version.dart';
import 'package:taxi1/services/firestore_writes.dart';

/// Evento individual capturado durante el turno de un conductor.
class SessionLogEvent {
  const SessionLogEvent({
    required this.tipo,
    required this.timestamp,
    this.datos = const {},
  });

  /// Tipo de evento: SHIFT_START, SHIFT_END, GPS_LOST, NETWORK_LOST,
  /// NETWORK_FAIL, STATE_CHANGED, ROUTE_CHANGED.
  final String tipo;
  final int timestamp;
  final Map<String, dynamic> datos;

  Map<String, dynamic> toMap() => {'tipo': tipo, 'ts': timestamp, 'datos': datos};

  factory SessionLogEvent.fromMap(Map<String, dynamic> map) => SessionLogEvent(
    tipo: (map['tipo'] as String?) ?? 'UNKNOWN',
    timestamp:
        (map['ts'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch,
    datos: (map['datos'] as Map?)?.cast<String, dynamic>() ?? const {},
  );
}

/// Servicio de auditoría y diagnóstico de turnos en terreno.
///
/// Registra las incidencias de cada chofer (pérdidas de GPS y de señal,
/// cambios de capacidad y de recorrido) en un búfer local y las sube a
/// Firestore, en un solo documento por turno, al terminarlo:
/// `garitas/{garitaId}/auditoria_turnos/{sessionId}`.
class SessionLogService {
  SessionLogService._();
  static final SessionLogService instance = SessionLogService._();

  static const _kCurrentSessionKey = 'coletotal_current_shift_session';
  static const _kPendingSessionsKey = 'coletotal_pending_shift_sessions';

  /// Tope de eventos por turno. Sin él, un turno largo en una zona sin señal
  /// (un `NETWORK_FAIL` cada pocos segundos) superaba el máximo de 1 MiB de un
  /// documento de Firestore, la subida fallaba y se reintentaba para siempre.
  /// Las reglas aceptan hasta 500, así que queda margen.
  static const int maxEventos = 300;

  /// Tope de turnos guardados a la espera de red.
  static const int maxPendientes = 20;

  /// Fallas repetidas dentro de esta ventana se cuentan en el evento anterior
  /// (`repeticiones`) en vez de agregar uno nuevo.
  static const Duration _ventanaAgrupado = Duration(seconds: 60);

  static const _repetibles = {'GPS_LOST', 'NETWORK_LOST', 'NETWORK_FAIL'};
  static const _siempre = {'SHIFT_START', 'SHIFT_END'};

  String? _currentSessionId;
  String? _currentUid;
  String? _currentPatente;
  String? _currentGaritaId;
  String? _currentRecorridoId;
  int? _inicioTs;
  int _descartados = 0;
  final List<SessionLogEvent> _eventos = [];
  Timer? _guardadoProgramado;

  bool get hasActiveSession => _currentSessionId != null;
  String? get currentSessionId => _currentSessionId;

  /// Eventos del turno en curso. Sólo para tests.
  @visibleForTesting
  List<SessionLogEvent> get debugEventos => List.unmodifiable(_eventos);

  /// Inicia el registro de una sesión de turno para el colectivero.
  Future<void> iniciarSesionTurno({
    required String uid,
    required String patente,
    required String garitaId,
    String? recorridoId,
    String? recorridoNombre,
  }) async {
    final now = DateTime.now();
    _currentSessionId = 'shift_${patente}_${now.millisecondsSinceEpoch}';
    _currentUid = uid;
    _currentPatente = patente;
    _currentGaritaId = garitaId;
    _currentRecorridoId = recorridoId;
    _inicioTs = now.millisecondsSinceEpoch;
    _descartados = 0;
    _eventos.clear();

    logEvent('SHIFT_START', {
      'uid': uid,
      'patente': patente,
      'garitaId': garitaId,
      'recorridoId': recorridoId,
      'recorridoNombre': recorridoNombre,
      'appVersion': AppVersion.label,
      'plataforma': defaultTargetPlatform.name,
    });

    await _guardarSesionActivaLocal();
  }

  /// Registra un evento operacional del turno en curso.
  ///
  /// Sin turno no hace nada: antes los eventos de fuera del turno se
  /// acumulaban y terminaban mezclados en el turno siguiente, o se perdían.
  void logEvent(String tipo, [Map<String, dynamic> datos = const {}]) {
    if (_currentSessionId == null) return;
    final now = DateTime.now().millisecondsSinceEpoch;

    if (_repetibles.contains(tipo) && _eventos.isNotEmpty) {
      final last = _eventos.last;
      final ultimaVez = (last.datos['ultimoTs'] as int?) ?? last.timestamp;
      if (last.tipo == tipo && now - ultimaVez <= _ventanaAgrupado.inMilliseconds) {
        _eventos[_eventos.length - 1] = SessionLogEvent(
          tipo: tipo,
          timestamp: last.timestamp,
          datos: {
            ...last.datos,
            'repeticiones': ((last.datos['repeticiones'] as int?) ?? 1) + 1,
            'ultimoTs': now,
          },
        );
        _programarGuardado();
        return;
      }
    }

    if (_eventos.length >= maxEventos && !_siempre.contains(tipo)) {
      _descartados++;
      return;
    }

    _eventos.add(SessionLogEvent(tipo: tipo, timestamp: now, datos: datos));
    debugPrint('[SessionLog] $tipo: $datos');

    if (_siempre.contains(tipo) || tipo == 'GPS_LOST') {
      unawaited(_guardarSesionActivaLocal());
    } else {
      _programarGuardado();
    }
  }

  /// Finaliza el turno y envía el informe consolidado a Firestore.
  ///
  /// Sin red no se queda esperando: tras unos segundos la sesión queda en la
  /// cola local y en la del SDK, y este método termina. Antes esperaba la
  /// confirmación del servidor sin plazo, y con él quedaba colgado el botón
  /// "Terminar turno".
  Future<void> finalizarSesionTurno() async {
    final sessionId = _currentSessionId;
    if (sessionId == null) return;

    final now = DateTime.now();
    logEvent('SHIFT_END', {
      'duracionSegundos': _inicioTs != null
          ? (now.millisecondsSinceEpoch - _inicioTs!) ~/ 1000
          : 0,
      'totalEventos': _eventos.length + 1,
      'eventosDescartados': _descartados,
    });

    final payload = _payload(finTs: now.millisecondsSinceEpoch);
    final garitaId = _currentGaritaId;

    var confirmado = false;
    if (garitaId != null && garitaId.isNotEmpty) {
      try {
        final outcome = await confirmOrQueue(
          _docRef(garitaId, sessionId).set({
            ...payload,
            'sincronizadoEn': FieldValue.serverTimestamp(),
          }),
          label: 'auditoría $sessionId',
        );
        confirmado = outcome == WriteOutcome.confirmed;
      } catch (e) {
        debugPrint('[SessionLog] No se pudo subir la sesión (se encola): $e');
      }
    }

    // También se encola cuando quedó en la cola del SDK: esa cola es de la
    // sesión de Firebase Auth, y si el chofer cierra sesión antes de recuperar
    // señal, se pierde. Si las dos llegan, la segunda es un `update` que las
    // reglas rechazan y se descarta sin daño.
    if (!confirmado) await _encolarSesionPendiente(payload);

    _guardadoProgramado?.cancel();
    _guardadoProgramado = null;
    _currentSessionId = null;
    _currentUid = null;
    _currentPatente = null;
    _currentGaritaId = null;
    _currentRecorridoId = null;
    _inicioTs = null;
    _descartados = 0;
    _eventos.clear();

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kCurrentSessionKey);
  }

  /// Rescata el turno que quedó a medias si la app se cerró en pleno turno.
  ///
  /// El turno en curso se guarda en el teléfono a medida que avanza, pero hasta
  /// ahora nadie volvía a leerlo: si Android mataba la app (el escenario de
  /// teléfonos con poca memoria que motivó la auditoría), la jornada se perdía
  /// entera. Se llama al arrancar, antes de sincronizar los pendientes.
  Future<void> recuperarSesionHuerfana() async {
    if (_currentSessionId != null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kCurrentSessionKey);
      if (raw == null) return;

      try {
        final data = jsonDecode(raw) as Map<String, dynamic>;
        final eventos = (data['eventos'] as List?) ?? const [];
        final ultimoTs = eventos.isNotEmpty && eventos.last is Map
            ? (eventos.last as Map)['ts']
            : data['inicioTs'];
        await _encolarSesionPendiente({
          ...data,
          'finTs': ultimoTs,
          'interrumpida': true,
        });
        debugPrint('[SessionLog] Turno interrumpido ${data['sessionId']} recuperado.');
      } catch (e) {
        debugPrint('[SessionLog] Turno interrumpido ilegible, se descarta: $e');
      }
      await prefs.remove(_kCurrentSessionKey);
    } catch (e) {
      debugPrint('[SessionLog] Error al recuperar turno interrumpido: $e');
    }
  }

  /// Reintenta subir los turnos guardados en el teléfono.
  ///
  /// Sólo sube los de [uid]: las reglas exigen que cada chofer escriba sus
  /// propios turnos, y un teléfono compartido puede tener pendientes de otro.
  /// Un rechazo de permisos significa que el documento ya existe (subió por la
  /// cola del SDK) o que ya no corresponde: se descarta en vez de reintentarlo
  /// para siempre.
  Future<void> sincronizarSesionesPendientes({required String? uid}) async {
    if (uid == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final pendientes = prefs.getStringList(_kPendingSessionsKey) ?? const [];
      if (pendientes.isEmpty) return;

      final restantes = <String>[];
      for (final raw in pendientes) {
        Map<String, dynamic> data;
        try {
          data = jsonDecode(raw) as Map<String, dynamic>;
        } catch (_) {
          continue;
        }
        final garitaId = data['garitaId'] as String?;
        final sessionId = data['sessionId'] as String?;
        if (garitaId == null || garitaId.isEmpty || sessionId == null) continue;

        final owner = data['uid'] as String?;
        if (owner != null && owner != uid) {
          restantes.add(raw);
          continue;
        }

        try {
          final outcome = await confirmOrQueue(
            _docRef(garitaId, sessionId).set({
              ...data,
              // Los pendientes de versiones anteriores no traían el uid, que
              // ahora exigen las reglas.
              'uid': uid,
              'sincronizadoEn': FieldValue.serverTimestamp(),
            }),
            label: 'auditoría pendiente $sessionId',
          );
          if (outcome == WriteOutcome.queuedOffline) restantes.add(raw);
        } on FirebaseException catch (e) {
          if (e.code != 'permission-denied') restantes.add(raw);
        } catch (e) {
          restantes.add(raw);
        }
      }

      final recortados = restantes.length > maxPendientes
          ? restantes.sublist(restantes.length - maxPendientes)
          : restantes;
      await prefs.setStringList(_kPendingSessionsKey, recortados);
    } catch (e) {
      debugPrint('[SessionLog] Error en sincronizarSesionesPendientes: $e');
    }
  }

  // --- Interno ---------------------------------------------------------------

  DocumentReference<Map<String, dynamic>> _docRef(
    String garitaId,
    String sessionId,
  ) => FirebaseFirestore.instance
      .collection('garitas')
      .doc(garitaId)
      .collection('auditoria_turnos')
      .doc(sessionId);

  Map<String, dynamic> _payload({int? finTs}) => {
    'sessionId': _currentSessionId,
    'uid': _currentUid,
    'patente': _currentPatente,
    'garitaId': _currentGaritaId,
    'recorridoId': _currentRecorridoId,
    'inicioTs': _inicioTs,
    'finTs': ?finTs,
    'eventos': _eventos.map((e) => e.toMap()).toList(),
    'eventosDescartados': _descartados,
    'appVersion': AppVersion.label,
    'plataforma': defaultTargetPlatform.name,
  };

  /// Guardar en cada evento serializaba la lista entera una y otra vez; ahora
  /// se agrupa en un guardado cada pocos segundos.
  void _programarGuardado() {
    _guardadoProgramado ??= Timer(const Duration(seconds: 10), () {
      _guardadoProgramado = null;
      unawaited(_guardarSesionActivaLocal());
    });
  }

  Future<void> _guardarSesionActivaLocal() async {
    if (_currentSessionId == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kCurrentSessionKey, jsonEncode(_payload()));
    } catch (e) {
      debugPrint('[SessionLog] Error guardando sesión activa: $e');
    }
  }

  Future<void> _encolarSesionPendiente(Map<String, dynamic> payload) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final pendientes = List<String>.of(
        prefs.getStringList(_kPendingSessionsKey) ?? const [],
      )..add(jsonEncode(payload));
      final recortados = pendientes.length > maxPendientes
          ? pendientes.sublist(pendientes.length - maxPendientes)
          : pendientes;
      await prefs.setStringList(_kPendingSessionsKey, recortados);
    } catch (e) {
      debugPrint('[SessionLog] Error encolando sesión pendiente: $e');
    }
  }

  /// Devuelve el servicio a su estado inicial. Sólo para tests.
  @visibleForTesting
  void debugReset() {
    _guardadoProgramado?.cancel();
    _guardadoProgramado = null;
    _currentSessionId = null;
    _currentUid = null;
    _currentPatente = null;
    _currentGaritaId = null;
    _currentRecorridoId = null;
    _inicioTs = null;
    _descartados = 0;
    _eventos.clear();
  }
}
