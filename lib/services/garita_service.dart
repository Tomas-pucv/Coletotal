import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import 'package:taxi1/models/app_user.dart';
import 'package:taxi1/models/recorrido.dart';
import 'package:taxi1/services/auth_service.dart';
import 'package:taxi1/services/osrm_client.dart';
import 'package:taxi1/services/stops_service.dart';

/// Datos que gestiona el administrador de garita: recorridos y choferes.
///
/// Los paraderos **no** están acá: los lee todo el mundo, incluido el invitado,
/// así que viven en `StopsService`. Este servicio sólo escucha cuando hay un
/// administrador en sesión, y corta sus suscripciones al cerrarla — si no, un
/// listener de Firestore seguiría abierto contra datos que el usuario ya no
/// tiene permiso de leer, y las reglas empezarían a devolver errores.
class GaritaService extends ChangeNotifier {
  GaritaService._();
  static final GaritaService instance = GaritaService._();

  static const _colRecorridos = 'recorridos';
  static const _colUsuarios = 'usuarios';

  FirebaseFirestore get _db => FirebaseFirestore.instance;

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _choferesSub;

  List<AppUser> _choferes = const [];
  String? _garitaId;
  bool _loading = false;

  List<AppUser> get choferes => _choferes;
  bool get loading => _loading;
  String? get garitaId => _garitaId;

  /// Se engancha a la sesión una vez, desde `main()`.
  void bind() {
    AuthService.instance.addListener(_onAuthChanged);
    _onAuthChanged();
  }

  void _onAuthChanged() {
    final auth = AuthService.instance;
    final gid = auth.isAdmin ? auth.garitaId : null;
    if (gid == _garitaId) return;

    _garitaId = gid;
    if (gid == null) {
      _stop();
      _choferes = const [];
      notifyListeners();
      return;
    }
    _start(gid);
  }

  void _start(String garitaId) {
    _stop();
    _loading = true;
    notifyListeners();

    // Los recorridos NO se leen aquí: los escucha `RecorridosService`, que es
    // público porque el pasajero también los necesita para saber qué colectivos
    // pasan por un paradero. Dos listeners sobre la misma colección serían dos
    // suscripciones cobradas para el mismo dato.
    _loading = false;

    _choferesSub = _db
        .collection(_colUsuarios)
        .where('garitaId', isEqualTo: garitaId)
        .where('rol', isEqualTo: UserRole.colectivero.wireName)
        // El límite es obligatorio, no una optimización: la regla de `list` de
        // `usuarios` exige `request.query.limit <= 200`, así que una consulta
        // sin límite explícito llega con el límite por defecto de Firestore y
        // las reglas la rechazan entera.
        .limit(200)
        .snapshots()
        .listen(
          (snap) {
            _choferes =
                snap.docs.map((d) => AppUser.fromMap(d.id, d.data())).toList()
                  ..sort((a, b) => a.displayName.compareTo(b.displayName));
            notifyListeners();
          },
          onError: (Object e) => debugPrint('GaritaService: choferes: $e'),
        );
  }

  void _stop() {
    _choferesSub?.cancel();
    _choferesSub = null;
  }

  // --- Recorridos ----------------------------------------------------------

  Future<String> upsertRecorrido(Recorrido recorrido) async {
    String? geometria = recorrido.geometria;
    if (geometria == null || geometria.isEmpty) {
      final stops = StopsService.instance;
      final points = <LatLng>[];
      for (final id in recorrido.paraderoIds) {
        final stop = stops.byId(id);
        if (stop != null) points.add(stop.location);
      }
      if (points.length >= 2) {
        geometria = await OsrmClient.getEncodedRoute(points);
      }
    }

    final data = {
      ...recorrido.toMap(),
      if (geometria != null) 'geometria': geometria,
      'actualizadoEn': FieldValue.serverTimestamp(),
    };
    if (recorrido.id.isEmpty) {
      final ref = await _db.collection(_colRecorridos).add(data);
      return ref.id;
    }
    await _db.collection(_colRecorridos).doc(recorrido.id).set(data);
    return recorrido.id;
  }

  Future<void> deleteRecorrido(Recorrido recorrido) async {
    if (recorrido.id.isEmpty) return;
    await _db.collection(_colRecorridos).doc(recorrido.id).delete();
  }

  // --- Choferes ------------------------------------------------------------

  /// Habilita o deshabilita a un chofer.
  ///
  /// Es lo **único** que el administrador puede hacer sobre una cuenta ajena:
  /// cambiar contraseñas o borrar cuentas necesita el Admin SDK, y la patente
  /// no es un correo real al que mandar un enlace de recuperación. El flujo de
  /// "perdí mi contraseña" es deshabilitar aquí y entregar un código nuevo.
  Future<void> setChoferActivo(AppUser chofer, bool activo) async {
    await _db.collection(_colUsuarios).doc(chofer.uid).update({
      'activo': activo,
    });
  }

  @override
  void dispose() {
    AuthService.instance.removeListener(_onAuthChanged);
    _stop();
    super.dispose();
  }
}
