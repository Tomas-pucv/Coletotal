import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Evento individual capturado durante el turno de un conductor.
class SessionLogEvent {
  const SessionLogEvent({
    required this.tipo,
    required this.timestamp,
    this.datos = const {},
  });

  /// Tipo de evento: SHIFT_START, GPS_POS, GPS_LOST, STATE_CHANGED, LOW_MEM, SHIFT_END, ERROR
  final String tipo;
  final int timestamp;
  final Map<String, dynamic> datos;

  Map<String, dynamic> toMap() => {
    'tipo': tipo,
    'ts': timestamp,
    'datos': datos,
  };

  factory SessionLogEvent.fromMap(Map<String, dynamic> map) => SessionLogEvent(
    tipo: (map['tipo'] as String?) ?? 'UNKNOWN',
    timestamp: (map['ts'] as int?) ?? DateTime.now().millisecondsSinceEpoch,
    datos: (map['datos'] as Map<String, dynamic>?) ?? {},
  );
}

/// Servicio de auditoría y diagnóstico de turnos en terreno.
///
/// Registra las incidencias de cada chofer (pérdidas de GPS, saltos de antena,
/// cambios de estado y memoria) bufferizándolas de forma local y
/// sincronizándolas en lotes (batch) hacia Firestore al finalizar la jornada o
/// al reconectar la red WiFi.
class SessionLogService {
  SessionLogService._();
  static final SessionLogService instance = SessionLogService._();

  static const _kCurrentSessionKey = 'coletotal_current_shift_session';
  static const _kPendingSessionsKey = 'coletotal_pending_shift_sessions';

  String? _currentSessionId;
  String? _currentPatente;
  String? _currentGaritaId;
  String? _currentRecorridoId;
  int? _inicioTs;
  final List<SessionLogEvent> _eventos = [];

  bool get hasActiveSession => _currentSessionId != null;
  String? get currentSessionId => _currentSessionId;

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
    _currentPatente = patente;
    _currentGaritaId = garitaId;
    _currentRecorridoId = recorridoId;
    _inicioTs = now.millisecondsSinceEpoch;
    _eventos.clear();

    logEvent('SHIFT_START', {
      'uid': uid,
      'patente': patente,
      'garitaId': garitaId,
      'recorridoId': recorridoId,
      'recorridoNombre': recorridoNombre,
      'appVersion': '0.4.3+3',
      'plataforma': defaultTargetPlatform.name,
    });

    await _guardarSesionActivaLocal();
  }

  /// Registra un evento operacional durante el turno.
  void logEvent(String tipo, [Map<String, dynamic> datos = const {}]) {
    final event = SessionLogEvent(
      tipo: tipo,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      datos: datos,
    );
    _eventos.add(event);
    debugPrint('[SessionLog] $tipo: $datos');

    if (tipo == 'SHIFT_START' ||
        tipo == 'SHIFT_END' ||
        tipo == 'GPS_LOST' ||
        tipo == 'LOW_MEMORY') {
      _guardarSesionActivaLocal();
    }
  }

  /// Finaliza el turno y envía el informe consolidado a Firestore.
  Future<void> finalizarSesionTurno() async {
    if (_currentSessionId == null) return;

    final now = DateTime.now();
    logEvent('SHIFT_END', {
      'duracionSegundos':
          _inicioTs != null
              ? (now.millisecondsSinceEpoch - _inicioTs!) ~/ 1000
              : 0,
      'totalEventos': _eventos.length + 1,
    });

    final payload = {
      'sessionId': _currentSessionId,
      'patente': _currentPatente,
      'garitaId': _currentGaritaId,
      'recorridoId': _currentRecorridoId,
      'inicioTs': _inicioTs,
      'finTs': now.millisecondsSinceEpoch,
      'eventos': _eventos.map((e) => e.toMap()).toList(),
      'appVersion': '0.4.3+3',
      'plataforma': defaultTargetPlatform.name,
    };

    bool synced = false;
    try {
      if (_currentGaritaId != null && _currentGaritaId!.isNotEmpty) {
        await FirebaseFirestore.instance
            .collection('garitas')
            .doc(_currentGaritaId)
            .collection('auditoria_turnos')
            .doc(_currentSessionId)
            .set({
              ...payload,
              'sincronizadoEn': FieldValue.serverTimestamp(),
            });
        synced = true;
        debugPrint(
          '[SessionLog] Sesión $_currentSessionId sincronizada con Firestore exitosamente.',
        );
      }
    } catch (e) {
      debugPrint(
        '[SessionLog] Error al sincronizar con Firestore (se encola offline): $e',
      );
    }

    if (!synced) {
      await _encolarSesionPendiente(payload);
    }

    _currentSessionId = null;
    _currentPatente = null;
    _currentGaritaId = null;
    _currentRecorridoId = null;
    _inicioTs = null;
    _eventos.clear();

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kCurrentSessionKey);
  }

  Future<void> _guardarSesionActivaLocal() async {
    if (_currentSessionId == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = {
        'sessionId': _currentSessionId,
        'patente': _currentPatente,
        'garitaId': _currentGaritaId,
        'recorridoId': _currentRecorridoId,
        'inicioTs': _inicioTs,
        'eventos': _eventos.map((e) => e.toMap()).toList(),
      };
      await prefs.setString(_kCurrentSessionKey, jsonEncode(data));
    } catch (e) {
      debugPrint('[SessionLog] Error guardando sesión activa: $e');
    }
  }

  Future<void> _encolarSesionPendiente(Map<String, dynamic> payload) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final pendientesJson = prefs.getStringList(_kPendingSessionsKey) ?? [];
      pendientesJson.add(jsonEncode(payload));
      await prefs.setStringList(_kPendingSessionsKey, pendientesJson);
    } catch (e) {
      debugPrint('[SessionLog] Error encolando sesión pendiente: $e');
    }
  }

  /// Reintenta subir sesiones guardadas en almacenamiento local cuando hay red.
  Future<void> sincronizarSesionesPendientes() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final pendientesJson = prefs.getStringList(_kPendingSessionsKey) ?? [];
      if (pendientesJson.isEmpty) return;

      final remaining = <String>[];
      for (final raw in pendientesJson) {
        try {
          final data = jsonDecode(raw) as Map<String, dynamic>;
          final garitaId = data['garitaId'] as String?;
          final sessionId = data['sessionId'] as String?;
          if (garitaId != null && garitaId.isNotEmpty && sessionId != null) {
            await FirebaseFirestore.instance
                .collection('garitas')
                .doc(garitaId)
                .collection('auditoria_turnos')
                .doc(sessionId)
                .set({
                  ...data,
                  'sincronizadoEn': FieldValue.serverTimestamp(),
                });
            debugPrint('[SessionLog] Sesión pendiente $sessionId sincronizada.');
          }
        } catch (e) {
          debugPrint('[SessionLog] Reintento fallido para una sesión: $e');
          remaining.add(raw);
        }
      }
      await prefs.setStringList(_kPendingSessionsKey, remaining);
    } catch (e) {
      debugPrint('[SessionLog] Error en sincronizarSesionesPendientes: $e');
    }
  }
}
