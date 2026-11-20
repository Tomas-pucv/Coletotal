import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:taxi1/models/app_user.dart';
import 'package:taxi1/models/recorrido.dart';
import 'package:taxi1/services/auth_service.dart';
import 'package:taxi1/services/firebase_telemetria_service.dart';
import 'package:taxi1/services/location_service.dart';
import 'package:taxi1/services/preferences_service.dart';
import 'package:taxi1/services/recorridos_service.dart';
import 'package:taxi1/services/session_log_service.dart';

/// Por qué no se pudo entrar en servicio.
enum TurnoIssue {
  none,

  /// El usuario apagó el rastreo en Preferencias.
  trackingDisabled,

  /// La garita deshabilitó a este chofer.
  cuentaInactiva,

  /// GPS apagado o permiso denegado.
  ubicacionNoDisponible,
}

/// Servicio gestor del estado de jornada (turno) del conductor.
///
/// Centraliza el ciclo de vida de la transmisión GPS fuera de las pantallas
/// para que el turno activo persista al navegar entre pestañas y se detenga
/// de forma ordenada al cerrar sesión o revocar permisos.
class TurnoService extends ChangeNotifier {
  TurnoService._();
  static final TurnoService instance = TurnoService._();

  /// Identificador del último recorrido seleccionado por el conductor.
  static const _keyRecorrido = 'turno_recorrido_id';

  final _telemetria = FirebaseTelemetriaService.instance;
  final _location = LocationService.instance;
  final _auth = AuthService.instance;
  final _prefs = PreferencesService.instance;
  final _recorridos = RecorridosService.instance;

  bool _enTurno = false;
  TurnoIssue _issue = TurnoIssue.none;
  bool _busy = false;
  bool _bound = false;
  bool _cancelRequested = false;
  String? _recorridoId;

  bool get enTurno => _enTurno;
  TurnoIssue get issue => _issue;
  bool get busy => _busy;

  /// Momento de la última posición confirmada por el servidor.
  ValueListenable<DateTime?> get ultimoEnvio => _telemetria.ultimoEnvio;

  /// Si el teléfono tiene conexión con el servidor de telemetría.
  ValueListenable<bool> get conectado => _telemetria.conectado;

  /// La línea que el chofer dice estar cubriendo, si sigue existiendo y activa
  /// en su garita.
  Recorrido? get recorridoAsignado {
    final id = _recorridoId;
    if (id == null) return null;
    final recorrido = _recorridos.byId(id);
    if (recorrido == null || !recorrido.activo) return null;
    if (recorrido.garitaId != _auth.garitaId) return null;
    return recorrido;
  }

  /// Líneas activas de la garita del chofer: lo que puede elegir.
  List<Recorrido> get recorridosDisponibles {
    final garitaId = _auth.garitaId;
    if (garitaId == null) return const [];
    return _recorridos
        .porGarita(garitaId)
        .where((r) => r.activo)
        .toList(growable: false)
      ..sort((a, b) => a.nombre.compareTo(b.nombre));
  }

  /// Conecta el servicio con la sesión. Se llama una vez desde `main()`.
  Future<void> bind() async {
    if (_bound) return;
    _bound = true;
    // Registra la detención del turno antes del cierre de sesión para remover
    // el nodo en Realtime Database mientras el token de Auth sigue vigente.
    _auth.onBeforeSignOut = terminarTurno;
    _auth.addListener(_onAuthChanged);
    _prefs.addListener(_onPrefsChanged);
    _recorridos.addListener(_onRecorridosChanged);

    try {
      final sp = await SharedPreferences.getInstance();
      _recorridoId = sp.getString(_keyRecorrido);
    } catch (_) {}

    // Recupera cualquier sesión de turno interrumpida y sincroniza pendientes.
    final log = SessionLogService.instance;
    unawaited(
      log.recuperarSesionHuerfana().then(
        (_) => log.sincronizarSesionesPendientes(uid: _auth.uid),
      ),
    );
  }

  void _onAuthChanged() {
    // Dejó de ser chofer (cerró sesión, cambió de cuenta, lo deshabilitaron):
    // no puede seguir emitiendo.
    final profile = _auth.profile;
    if (_enTurno &&
        (profile == null ||
            profile.rol != UserRole.colectivero ||
            !profile.activo)) {
      unawaited(terminarTurno());
    }
    // Al iniciar sesión se suben los turnos que este chofer dejó pendientes.
    if (profile != null && profile.rol == UserRole.colectivero) {
      unawaited(
        SessionLogService.instance.sincronizarSesionesPendientes(
          uid: profile.uid,
        ),
      );
    }
    notifyListeners();
  }

  void _onPrefsChanged() {
    // Apagar el rastreo en Preferencias tiene que bajar el turno: si no, la
    // preferencia de privacidad sería mentira para el rol que más la necesita.
    if (_enTurno && !_prefs.locationTracking) {
      unawaited(terminarTurno());
      _issue = TurnoIssue.trackingDisabled;
      notifyListeners();
    }
  }

  void _onRecorridosChanged() {
    // Si la garita renombra o desactiva la línea en pleno turno, el mapa de los
    // pasajeros tiene que reflejarlo.
    if (_enTurno && _recorridos.loaded) {
      final r = recorridoAsignado;
      final actual = _telemetria.current;
      if (actual != null &&
          (actual.recorridoId != r?.id ||
              actual.recorridoNombre != r?.nombre)) {
        unawaited(_telemetria.setRecorrido(r?.id, r?.nombre));
      }
    }
    notifyListeners();
  }

  /// Elige la línea que se está cubriendo; `null` para ninguna.
  Future<void> setRecorridoAsignado(Recorrido? recorrido) async {
    if (recorrido?.id == _recorridoId) return;
    _recorridoId = recorrido?.id;
    notifyListeners();

    try {
      final sp = await SharedPreferences.getInstance();
      if (_recorridoId == null) {
        await sp.remove(_keyRecorrido);
      } else {
        await sp.setString(_keyRecorrido, _recorridoId!);
      }
    } catch (_) {}

    if (_enTurno) {
      SessionLogService.instance.logEvent('ROUTE_CHANGED', {
        'recorridoId': recorrido?.id,
        'recorridoNombre': recorrido?.nombre,
      });
      await _telemetria.setRecorrido(recorrido?.id, recorrido?.nombre);
    }
  }

  Future<void> iniciarTurno() async {
    if (_busy || _enTurno) return;
    final profile = _auth.profile;
    if (profile == null || profile.rol != UserRole.colectivero) return;

    if (!profile.activo) {
      _issue = TurnoIssue.cuentaInactiva;
      notifyListeners();
      return;
    }
    if (!_prefs.locationTracking) {
      _issue = TurnoIssue.trackingDisabled;
      notifyListeners();
      return;
    }

    _busy = true;
    _cancelRequested = false;
    _issue = TurnoIssue.none;
    notifyListeners();

    try {
      // Configura el GPS en modo conductor (servicio en primer plano) antes de
      // iniciar la publicación de telemetría.
      final locationIssue = await _location.setDriverMode(true);
      final currentProfile = _auth.profile;
      if (_cancelRequested ||
          currentProfile == null ||
          !currentProfile.activo ||
          !_prefs.locationTracking) {
        await _location.setDriverMode(false);
        return;
      }
      if (locationIssue != LocationIssue.none) {
        _issue = TurnoIssue.ubicacionNoDisponible;
        await _location.setDriverMode(false);
        return;
      }

      final recorrido = recorridoAsignado;
      final idVehiculo =
          profile.patente ??
          (profile.uid.length > 12
              ? profile.uid.substring(0, 12)
              : profile.uid);
      await _telemetria.iniciarTracking(
        uid: profile.uid,
        patente: idVehiculo,
        garitaId: profile.garitaId,
        recorridoId: recorrido?.id,
        recorridoNombre: recorrido?.nombre,
      );
      _enTurno = true;

      await SessionLogService.instance.iniciarSesionTurno(
        uid: profile.uid,
        patente: idVehiculo,
        garitaId: profile.garitaId,
        recorridoId: recorrido?.id,
        recorridoNombre: recorrido?.nombre,
      );
    } catch (e) {
      debugPrint('TurnoService: no se pudo iniciar el turno: $e');
      _issue = TurnoIssue.ubicacionNoDisponible;
      _enTurno = false;
      await _telemetria.detenerTracking();
      await _location.setDriverMode(false);
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> terminarTurno() async {
    _cancelRequested = true;
    if (!_enTurno && !_telemetria.isTracking) return;
    _busy = true;
    notifyListeners();

    // Cada etapa aplica un timeout acotado para liberar la interfaz de
    // inmediato incluso sin cobertura de red.
    try {
      await _telemetria.detenerTracking();
      await _location.setDriverMode(false);
      final log = SessionLogService.instance;
      await log.finalizarSesionTurno();
      // Si hay señal, se aprovecha para subir también los turnos anteriores
      // que hubieran quedado en cola. Sin esperar: el chofer ya terminó.
      unawaited(log.sincronizarSesionesPendientes(uid: _auth.uid));
    } catch (e) {
      debugPrint('TurnoService: error al terminar el turno: $e');
    } finally {
      _enTurno = false;
      _busy = false;
      notifyListeners();
    }
  }

  /// Fija si hay turno sin GPS ni Firebase. Sólo para tests de pantallas.
  @visibleForTesting
  void debugSetEnTurno(bool enTurno) {
    _enTurno = enTurno;
    notifyListeners();
  }
}
