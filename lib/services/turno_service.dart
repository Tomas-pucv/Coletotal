import 'package:flutter/foundation.dart';

import 'package:taxi1/models/app_user.dart';
import 'package:taxi1/models/colectivo_activo.dart';
import 'package:taxi1/models/recorrido.dart';
import 'package:taxi1/services/auth_service.dart';
import 'package:taxi1/services/firebase_telemetria_service.dart';
import 'package:taxi1/services/preferences_service.dart';
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

/// Dueño del estado de jornada del colectivero.
///
/// Existe para que **nadie más** decida cuándo se transmite. Antes esa lógica
/// vivía en `MapScreen`: arrancaba el tracking desde `initState` y lo detenía
/// desde `dispose()`. Funcionaba de casualidad, porque el `IndexedStack`
/// mantenía la pantalla montada para siempre; en cuanto la lista de pantallas
/// pasó a depender del rol, cambiar de rol habría destruido ese elemento y
/// cortado la transmisión sin que nadie se enterara.
///
/// Como servicio, además, el turno sobrevive a la navegación: el chofer puede
/// irse a Rutas o al mapa sin dejar de emitir.
class TurnoService extends ChangeNotifier {
  TurnoService._();
  static final TurnoService instance = TurnoService._();

  final _telemetria = FirebaseTelemetriaService.instance;
  final _auth = AuthService.instance;
  final _prefs = PreferencesService.instance;

  bool _enTurno = false;
  EstadoCapacidad _estado = EstadoCapacidad.disponible;
  TurnoIssue _issue = TurnoIssue.none;
  bool _busy = false;
  Recorrido? _recorridoAsignado;

  bool get enTurno => _enTurno;
  EstadoCapacidad get estado => _estado;
  TurnoIssue get issue => _issue;
  bool get busy => _busy;
  Recorrido? get recorridoAsignado => _recorridoAsignado;
  DateTime? get ultimoEnvio => _telemetria.ultimoEnvio;

  void setRecorridoAsignado(Recorrido? recorrido) {
    _recorridoAsignado = recorrido;
    notifyListeners();
  }

  /// Conecta el servicio con la sesión. Se llama una vez desde `main()`.
  void bind() {
    // Cerrar sesión tiene que detener la telemetría **primero**: borrar el nodo
    // en Realtime Database exige el token todavía vigente.
    _auth.onBeforeSignOut = terminarTurno;
    _auth.addListener(_onAuthChanged);
    _prefs.addListener(_onPrefsChanged);
    SessionLogService.instance.sincronizarSesionesPendientes();
  }

  void _onAuthChanged() {
    // Dejó de ser chofer (cerró sesión, cambió de cuenta, lo deshabilitaron):
    // no puede seguir emitiendo.
    if (_enTurno && _auth.role != UserRole.colectivero) {
      terminarTurno();
    }
  }

  void _onPrefsChanged() {
    // Apagar el rastreo en Preferencias tiene que bajar el turno: si no, la
    // preferencia de privacidad sería mentira para el rol que más la necesita.
    if (_enTurno && !_prefs.locationTracking) {
      terminarTurno();
      _issue = TurnoIssue.trackingDisabled;
      notifyListeners();
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
    _issue = TurnoIssue.none;
    notifyListeners();

    await _telemetria.iniciarTracking(
      uid: profile.uid,
      patente: profile.patente ?? profile.uid,
      garitaId: profile.garitaId,
      estado: _estado,
      recorridoId: _recorridoAsignado?.id,
      recorridoNombre: _recorridoAsignado?.nombre,
    );

    // `iniciarTracking` se rinde en silencio si falta el GPS o el permiso, así
    // que el resultado real se lee de su propio estado y no se asume.
    _enTurno = _telemetria.isTracking;
    if (_enTurno) {
      _issue = TurnoIssue.none;
      await SessionLogService.instance.iniciarSesionTurno(
        uid: profile.uid,
        patente: profile.patente ?? profile.uid,
        garitaId: profile.garitaId,
        recorridoId: _recorridoAsignado?.id,
        recorridoNombre: _recorridoAsignado?.nombre,
      );
    } else {
      _issue = TurnoIssue.ubicacionNoDisponible;
    }
    _busy = false;
    notifyListeners();
  }

  Future<void> terminarTurno() async {
    if (!_enTurno && !_telemetria.isTracking) return;
    _busy = true;
    notifyListeners();

    await _telemetria.detenerTracking();
    await SessionLogService.instance.finalizarSesionTurno();

    _enTurno = false;
    _busy = false;
    notifyListeners();
  }

  Future<void> setEstado(EstadoCapacidad estado) async {
    if (estado == _estado) return;
    _estado = estado;
    notifyListeners();
    SessionLogService.instance.logEvent('STATE_CHANGED', {'estado': estado.name});
    await _telemetria.setEstado(estado);
  }
}
