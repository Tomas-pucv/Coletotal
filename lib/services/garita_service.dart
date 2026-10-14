import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'package:taxi1/models/app_user.dart';
import 'package:taxi1/models/garita.dart';
import 'package:taxi1/models/recorrido.dart';
import 'package:taxi1/services/auth_service.dart';
import 'package:taxi1/services/firestore_writes.dart';

/// Datos que gestiona el administrador de garita: recorridos y choferes.
///
/// Las líneas las lee todo el mundo, incluido el invitado, así que se escuchan
/// en `RecorridosService`; acá sólo se escriben. Este servicio sólo escucha
/// cuando hay un administrador en sesión, y corta sus suscripciones al
/// cerrarla — si no, un
/// listener de Firestore seguiría abierto contra datos que el usuario ya no
/// tiene permiso de leer, y las reglas empezarían a devolver errores.
class GaritaService extends ChangeNotifier {
  GaritaService._();
  static final GaritaService instance = GaritaService._();

  static const _colRecorridos = 'recorridos';
  static const _colUsuarios = 'usuarios';
  static const _colGaritas = 'garitas';

  FirebaseFirestore get _db => FirebaseFirestore.instance;

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _choferesSub;

  List<AppUser> _choferes = const [];
  String? _garitaId;
  bool _loading = false;
  List<Garita>? _garitas;

  List<AppUser> get choferes => _choferes;

  /// `true` hasta que llega el primer padrón. Antes se apagaba en el mismo
  /// instante en que se encendía, y la pantalla de choferes mostraba "no hay
  /// choferes" mientras la consulta todavía estaba en camino.
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
      _loading = false;
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
    // público porque el pasajero también los necesita. Dos listeners sobre la
    // misma colección serían dos suscripciones cobradas para el mismo dato.
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
            _loading = false;
            notifyListeners();
          },
          onError: (Object e) {
            debugPrint('GaritaService: choferes: $e');
            _loading = false;
            notifyListeners();
          },
        );
  }

  void _stop() {
    _choferesSub?.cancel();
    _choferesSub = null;
  }

  // --- Garitas -------------------------------------------------------------

  /// Las garitas de la línea, para el filtro de la consola de flota.
  ///
  /// Antes los nombres y los ids estaban escritos a mano en la pantalla. Se
  /// leen una vez por sesión: las garitas no cambian en el día.
  Future<List<Garita>> loadGaritas() async {
    final cached = _garitas;
    if (cached != null) return cached;
    try {
      final snap = await _db.collection(_colGaritas).get();
      final garitas =
          snap.docs.map((d) => Garita.fromMap(d.id, d.data())).toList()
            ..sort((a, b) => a.nombre.compareTo(b.nombre));
      _garitas = garitas;
      return garitas;
    } catch (e) {
      debugPrint('GaritaService: no se pudieron leer las garitas: $e');
      return const [];
    }
  }

  // --- Recorridos ----------------------------------------------------------

  /// Crea o actualiza un recorrido. Devuelve su id y si quedó confirmado o
  /// encolado sin red.
  ///
  /// El recorrido llega con el trazado de cada sentido ya calculado: lo hace
  /// el editor, que además se lo muestra a la garita antes de guardar.
  Future<(String, WriteOutcome)> upsertRecorrido(Recorrido recorrido) async {
    final data = {
      ...recorrido.toMap(),
      'actualizadoEn': FieldValue.serverTimestamp(),
    };
    final ref = recorrido.id.isEmpty
        ? _db.collection(_colRecorridos).doc()
        : _db.collection(_colRecorridos).doc(recorrido.id);
    final outcome = await confirmOrQueue(ref.set(data), label: 'recorrido');
    return (ref.id, outcome);
  }

  /// Enciende o apaga una línea sin tocar su trazado. Una línea apagada no la
  /// ven los pasajeros ni la pueden elegir los choferes.
  Future<WriteOutcome> setRecorridoActivo(Recorrido recorrido, bool activo) =>
      confirmOrQueue(
        _db.collection(_colRecorridos).doc(recorrido.id).update({
          'activo': activo,
          'actualizadoEn': FieldValue.serverTimestamp(),
        }),
        label: 'recorrido activo=$activo',
      );

  Future<WriteOutcome> deleteRecorrido(Recorrido recorrido) async {
    if (recorrido.id.isEmpty) return WriteOutcome.confirmed;
    return confirmOrQueue(
      _db.collection(_colRecorridos).doc(recorrido.id).delete(),
      label: 'borrar recorrido',
    );
  }

  // --- Choferes ------------------------------------------------------------

  /// Habilita o deshabilita a un chofer.
  ///
  /// Es lo **único** que el administrador puede hacer sobre una cuenta ajena:
  /// cambiar contraseñas o borrar cuentas necesita el Admin SDK, y la patente
  /// no es un correo real al que mandar un enlace de recuperación. El flujo de
  /// "perdí mi contraseña" es deshabilitar aquí y entregar un código nuevo.
  ///
  /// El chofer lo nota en segundos: su app escucha su propio perfil y, al
  /// verse deshabilitado, cierra la sesión y termina el turno.
  Future<WriteOutcome> setChoferActivo(AppUser chofer, bool activo) =>
      confirmOrQueue(
        _db.collection(_colUsuarios).doc(chofer.uid).update({'activo': activo}),
        label: 'chofer activo=$activo',
      );

  @override
  void dispose() {
    AuthService.instance.removeListener(_onAuthChanged);
    _stop();
    super.dispose();
  }
}
