import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:taxi1/models/app_user.dart';
import 'package:taxi1/models/garita.dart';
import 'package:taxi1/services/firestore_writes.dart';
import 'package:taxi1/utils/patente.dart';

/// Dónde está la sesión.
///
/// `registrando` y `sinPerfil` no son estados teóricos: Firebase deja al
/// usuario **autenticado en el instante** en que se crea la cuenta, así que
/// entre `createUserWithEmailAndPassword` y la escritura del documento en
/// Firestore la app está autenticada y sin perfil. Sin nombrar ese hueco, la
/// interfaz se reconstruye a mitad del registro mostrando un rol equivocado.
enum AuthStatus { desconocido, invitado, registrando, conSesion, sinPerfil }

/// Motivo de fallo, ya reducido a los casos que la interfaz sabe explicar.
enum AuthErrorCode {
  /// Patente/correo o contraseña incorrectos.
  ///
  /// Es **un solo caso a propósito**: los proyectos de Firebase traen activada
  /// la protección contra enumeración de correos, que colapsa `user-not-found`
  /// y `wrong-password` en `invalid-credential`. Distinguirlos es imposible, y
  /// además decir "esa patente no existe" sería justo lo que esa protección
  /// busca evitar.
  credencialesInvalidas,
  cuentaEnUso,
  claveDebil,
  patenteInvalida,
  codigoInvalido,
  cuentaDeshabilitada,
  sinConexion,
  desconocido,
}

class AuthFailure implements Exception {
  const AuthFailure(this.code, [this.detail]);
  final AuthErrorCode code;
  final String? detail;

  @override
  String toString() => 'AuthFailure(${code.name})';
}

/// Resultado de leer el perfil de Firestore.
///
/// Antes la lectura sólo dejaba `_profile` en `null` o no, y quien la llamaba
/// no podía distinguir *por qué*: un chofer deshabilitado o sin red veía
/// "patente o contraseña incorrecta".
enum ProfileResult { ok, missing, disabled, network }

/// Fuente de verdad del rol del usuario.
///
/// Sigue el patrón del resto del proyecto: singleton [ChangeNotifier], sin
/// framework de inyección. Las instancias de Firebase se resuelven **de forma
/// perezosa** en getters y no en campos: así un test de widget puede fijar un
/// perfil con [debugSetProfile] sin que se inicialice Firebase.
class AuthService extends ChangeNotifier {
  AuthService._();
  static final AuthService instance = AuthService._();

  static const _keyCachedProfile = 'cached_profile';

  static const _colUsuarios = 'usuarios';
  static const _colCodigos = 'codigos_acceso';
  static const _colGaritas = 'garitas';

  FirebaseAuth get _auth => FirebaseAuth.instance;
  FirebaseFirestore get _db => FirebaseFirestore.instance;

  StreamSubscription<User?>? _authSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _profileSub;
  String? _watchedUid;
  AuthStatus _status = AuthStatus.desconocido;
  AppUser? _profile;

  /// Durante `_signIn` la sesión cambia a mitad de camino; el listener de
  /// `authStateChanges` no debe lanzar una segunda lectura del perfil en
  /// paralelo con la del propio inicio de sesión.
  bool _signingIn = false;

  /// Gancho que se ejecuta **antes** de cerrar sesión.
  ///
  /// Lo usa el servicio de turno para detener la telemetría: borrar el nodo del
  /// vehículo en Realtime Database exige estar autenticado, así que si se
  /// cerrara la sesión primero el borrado daría permiso denegado y el marcador
  /// del chofer quedaría colgado en el mapa de todos los pasajeros hasta que
  /// expirara el `onDisconnect`.
  ///
  /// Es un gancho y no una dependencia directa para no acoplar la
  /// autenticación con la telemetría.
  Future<void> Function()? onBeforeSignOut;

  AuthStatus get status => _status;
  AppUser? get profile => _profile;
  UserRole get role => _profile?.rol ?? UserRole.invitado;
  bool get isColectivero => role == UserRole.colectivero;
  bool get isAdmin => role == UserRole.administrador;
  bool get isSignedIn => _profile != null;
  String? get uid => _profile?.uid;
  String? get garitaId => _profile?.garitaId;

  /// Prepara la sesión antes de `runApp`.
  ///
  /// Espera el primer evento de `authStateChanges` en vez de leer
  /// `currentUser`: la restauración de la sesión persistida es asíncrona y
  /// `currentUser` todavía puede ser `null` recién inicializado Firebase, lo
  /// que provocaría un parpadeo a "invitado" en cada arranque en frío. El
  /// timeout evita que una red mala cuelgue el arranque.
  Future<void> init() async {
    _profile = await _loadCachedProfile();

    User? user;
    try {
      user = await _auth.authStateChanges().first.timeout(
        const Duration(seconds: 3),
        onTimeout: () => _auth.currentUser,
      );
    } catch (e) {
      debugPrint('AuthService.init: no se pudo restaurar la sesión: $e');
      user = null;
    }

    if (user == null) {
      await _clearProfile(notify: false);
      _status = AuthStatus.invitado;
    } else {
      // El perfil cacheado ya pinta el menú; el refresco va en segundo plano
      // para no retrasar el primer frame.
      _status = _profile == null ? AuthStatus.sinPerfil : AuthStatus.conSesion;
      unawaited(_refreshProfile(user.uid));
      _watchProfile(user.uid);
    }

    _authSub = _auth.authStateChanges().listen(_onAuthChanged);
    notifyListeners();
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _profileSub?.cancel();
    super.dispose();
  }

  void _onAuthChanged(User? user) {
    // Durante el registro la sesión cambia a mitad de camino (la cuenta ya
    // existe pero el documento de perfil todavía no). Ese tramo lo gobierna
    // `_register`, no este listener; el inicio de sesión, igual.
    if (_status == AuthStatus.registrando || _signingIn) return;

    if (user == null) {
      _clearProfile();
      return;
    }
    if (_profile?.uid != user.uid) {
      unawaited(_refreshProfile(user.uid));
    }
    _watchProfile(user.uid);
  }

  /// Escucha el propio documento de perfil mientras haya sesión.
  ///
  /// Sin esto, deshabilitar a un chofer desde la garita no tenía efecto hasta
  /// que él reiniciara la app: el perfil sólo se leía al arrancar y al iniciar
  /// sesión, y el chofer seguía transmitiendo. Ahora el cambio llega en
  /// segundos y cierra la sesión, lo que además termina el turno.
  void _watchProfile(String uid) {
    if (_watchedUid == uid && _profileSub != null) return;
    _profileSub?.cancel();
    _watchedUid = uid;
    _profileSub = _db.collection(_colUsuarios).doc(uid).snapshots().listen(
      (snap) {
        final data = snap.data();
        if (!snap.exists || data == null) return;
        // Un evento de un usuario anterior que llega tarde no aplica.
        if (_auth.currentUser?.uid != uid) return;

        final fresh = AppUser.fromMap(snap.id, data);
        if (!fresh.activo) {
          unawaited(signOut());
          return;
        }
        if (fresh == _profile) return;
        _profile = fresh;
        _status = AuthStatus.conSesion;
        unawaited(_cacheProfile(fresh));
        notifyListeners();
      },
      onError: (Object e) =>
          debugPrint('AuthService: no se pudo escuchar el perfil: $e'),
    );
  }

  void _stopWatchingProfile() {
    _profileSub?.cancel();
    _profileSub = null;
    _watchedUid = null;
  }

  // --- Perfil --------------------------------------------------------------

  Future<AppUser?> _loadCachedProfile() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return AppUser.fromJson(prefs.getString(_keyCachedProfile));
    } catch (_) {
      return null;
    }
  }

  Future<void> _cacheProfile(AppUser? profile) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (profile == null) {
        await prefs.remove(_keyCachedProfile);
      } else {
        await prefs.setString(_keyCachedProfile, profile.toJson());
      }
    } catch (_) {
      // La caché es una optimización de arranque; si falla no se pierde nada.
    }
  }

  Future<void> _clearProfile({bool notify = true}) async {
    _stopWatchingProfile();
    _profile = null;
    _status = AuthStatus.invitado;
    await _cacheProfile(null);
    if (notify) notifyListeners();
  }

  Future<ProfileResult> _refreshProfile(String uid) async {
    try {
      final snap = await _db.collection(_colUsuarios).doc(uid).get();
      final data = snap.data();
      if (!snap.exists || data == null) {
        _status = AuthStatus.sinPerfil;
        notifyListeners();
        return ProfileResult.missing;
      }
      final profile = AppUser.fromMap(snap.id, data);

      // Las reglas pueden impedir que un chofer deshabilitado *escriba*, pero
      // no que inicie sesión. El corte tiene que hacerse acá.
      if (!profile.activo) {
        await signOut();
        return ProfileResult.disabled;
      }

      _profile = profile;
      _status = AuthStatus.conSesion;
      await _cacheProfile(profile);
      notifyListeners();
      return ProfileResult.ok;
    } catch (e) {
      // Sin red se sigue con el perfil cacheado: la app tiene que funcionar en
      // los cerros de Quilpué (RF-07-01).
      debugPrint('AuthService: no se pudo refrescar el perfil: $e');
      return ProfileResult.network;
    }
  }

  // --- Consultas públicas --------------------------------------------------

  /// Busca un código de enrolamiento. Devuelve `null` si no existe o no sirve.
  ///
  /// Se puede llamar sin sesión: es lo que permite avisar "código inválido"
  /// *antes* de crear la cuenta, en vez de crearla y tener que borrarla.
  ///
  /// Si no se pudo consultar (sin red), lanza [AuthFailure] con
  /// [AuthErrorCode.sinConexion]: antes devolvía `null` y el usuario leía
  /// "código inválido" con un código perfectamente válido.
  Future<CodigoAcceso?> lookupCodigo(String codigo) async {
    final id = codigo.trim().toUpperCase();
    if (id.isEmpty) return null;
    final DocumentSnapshot<Map<String, dynamic>> snap;
    try {
      // Sólo servidor: un código revocado no debe darse por bueno desde la
      // caché local.
      snap = await _db
          .collection(_colCodigos)
          .doc(id)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 10));
    } catch (e) {
      debugPrint('AuthService.lookupCodigo: $e');
      throw const AuthFailure(AuthErrorCode.sinConexion);
    }
    final data = snap.data();
    if (!snap.exists || data == null) return null;
    final acceso = CodigoAcceso.fromMap(snap.id, data);
    return acceso.isUsable ? acceso : null;
  }

  Future<Garita?> getGarita(String garitaId) async {
    if (garitaId.isEmpty) return null;
    try {
      final snap = await _db.collection(_colGaritas).doc(garitaId).get();
      final data = snap.data();
      if (!snap.exists || data == null) return null;
      return Garita.fromMap(snap.id, data);
    } catch (e) {
      debugPrint('AuthService.getGarita: $e');
      return null;
    }
  }

  // --- Inicio de sesión ----------------------------------------------------

  Future<void> signInColectivero({
    required String patente,
    required String clave,
  }) async {
    if (!isValidPatente(patente)) {
      throw const AuthFailure(AuthErrorCode.patenteInvalida);
    }
    await _signIn(patenteToEmail(patente), clave);
  }

  Future<void> signInAdministrador({
    required String email,
    required String clave,
  }) => _signIn(email.trim(), clave);

  Future<void> _signIn(String email, String clave) async {
    _signingIn = true;
    try {
      final cred = await _auth.signInWithEmailAndPassword(
        email: email,
        password: clave,
      );
      final user = cred.user;
      if (user == null) throw const AuthFailure(AuthErrorCode.desconocido);

      switch (await _refreshProfile(user.uid)) {
        case ProfileResult.ok:
          _watchProfile(user.uid);
        case ProfileResult.disabled:
          // `_refreshProfile` ya cerró la sesión. Antes esto le llegaba al
          // chofer como "patente o contraseña incorrecta".
          throw const AuthFailure(AuthErrorCode.cuentaDeshabilitada);
        case ProfileResult.network:
          await signOut();
          throw const AuthFailure(AuthErrorCode.sinConexion);
        case ProfileResult.missing:
          // Autenticado pero sin documento de perfil: la cuenta quedó a medio
          // registrar. Se cierra para no dejar la app en un estado sin rol.
          await signOut();
          throw const AuthFailure(AuthErrorCode.credencialesInvalidas);
      }
    } on FirebaseAuthException catch (e) {
      throw AuthFailure(_mapAuthError(e.code), e.code);
    } finally {
      _signingIn = false;
    }
  }

  // --- Registro ------------------------------------------------------------

  Future<void> registerColectivero({
    required String nombre,
    required String patente,
    required String clave,
    required String codigo,
  }) async {
    if (!isValidPatente(patente)) {
      throw const AuthFailure(AuthErrorCode.patenteInvalida);
    }
    final normalizada = cleanPatente(patente);
    await _register(
      rol: UserRole.colectivero,
      codigo: codigo,
      email: patenteToEmail(normalizada),
      clave: clave,
      build: (uid, acceso) => AppUser(
        uid: uid,
        rol: UserRole.colectivero,
        nombre: nombre.trim(),
        garitaId: acceso.garitaId,
        patente: normalizada,
      ),
    );
  }

  Future<void> registerAdministrador({
    required String nombre,
    required String email,
    required String clave,
    required String codigo,
  }) async {
    final correo = email.trim();
    await _register(
      rol: UserRole.administrador,
      codigo: codigo,
      email: correo,
      clave: clave,
      build: (uid, acceso) => AppUser(
        uid: uid,
        rol: UserRole.administrador,
        nombre: nombre.trim(),
        garitaId: acceso.garitaId,
        email: correo,
      ),
    );
  }

  Future<void> _register({
    required UserRole rol,
    required String codigo,
    required String email,
    required String clave,
    required AppUser Function(String uid, CodigoAcceso acceso) build,
  }) async {
    // 1. El código primero. Si no sirve se falla acá, sin haber tocado Auth: no
    //    quedan cuentas huérfanas que después haya que salir a borrar.
    final acceso = await lookupCodigo(codigo);
    if (acceso == null || acceso.rol != rol) {
      throw const AuthFailure(AuthErrorCode.codigoInvalido);
    }

    _status = AuthStatus.registrando;
    notifyListeners();

    UserCredential cred;
    try {
      cred = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: clave,
      );
    } on FirebaseAuthException catch (e) {
      _status = AuthStatus.invitado;
      notifyListeners();
      throw AuthFailure(_mapAuthError(e.code), e.code);
    }

    final user = cred.user;
    if (user == null) {
      _status = AuthStatus.invitado;
      notifyListeners();
      throw const AuthFailure(AuthErrorCode.desconocido);
    }

    // 2. El perfil. El `rol` que va acá lo dicta el código, y la regla de
    //    `create` de Firestore lo vuelve a verificar contra ese mismo documento
    //    de código: el cliente no puede declararse administrador por su cuenta.
    final profile = build(user.uid, acceso);
    try {
      await _db
          .collection(_colUsuarios)
          .doc(user.uid)
          .set(profile.toCreateMap(codigo: acceso.codigo));
    } catch (e) {
      // 3. Reversión en la medida de lo posible. `delete()` puede fallar, así
      //    que la sesión se cierra igual: es peor quedar autenticado sin perfil
      //    que dejar una cuenta vacía en Auth.
      try {
        await user.delete();
      } catch (_) {}
      try {
        await _auth.signOut();
      } catch (_) {}
      _status = AuthStatus.invitado;
      notifyListeners();
      throw AuthFailure(AuthErrorCode.desconocido, e.toString());
    }

    _profile = profile;
    _status = AuthStatus.conSesion;
    await _cacheProfile(profile);
    _watchProfile(user.uid);
    notifyListeners();
  }

  // --- Cierre de sesión ----------------------------------------------------

  Future<void> signOut() async {
    // El orden importa: ver [onBeforeSignOut].
    try {
      await onBeforeSignOut?.call();
    } catch (e) {
      debugPrint('AuthService.signOut: falló la limpieza previa: $e');
    }
    try {
      await _auth.signOut();
    } catch (e) {
      debugPrint('AuthService.signOut: $e');
    }
    await _clearProfile();
  }

  /// Actualiza el nombre visible. Es lo único del propio perfil que las reglas
  /// dejan modificar al usuario.
  Future<void> updateNombre(String nombre) async {
    final current = _profile;
    if (current == null) return;
    final limpio = nombre.trim();
    if (limpio.isEmpty || limpio == current.nombre) return;
    await confirmOrQueue(
      _db.collection(_colUsuarios).doc(current.uid).update({'nombre': limpio}),
      label: 'nombre de perfil',
    );
    _profile = current.copyWith(nombre: limpio);
    await _cacheProfile(_profile);
    notifyListeners();
  }

  static AuthErrorCode _mapAuthError(String code) => switch (code) {
    // La protección contra enumeración de correos hace que los tres primeros
    // lleguen como uno solo; se agrupan igual por si estuviera desactivada.
    'invalid-credential' ||
    'wrong-password' ||
    'user-not-found' ||
    'invalid-email' => AuthErrorCode.credencialesInvalidas,
    'email-already-in-use' => AuthErrorCode.cuentaEnUso,
    'weak-password' => AuthErrorCode.claveDebil,
    'user-disabled' => AuthErrorCode.cuentaDeshabilitada,
    'network-request-failed' => AuthErrorCode.sinConexion,
    _ => AuthErrorCode.desconocido,
  };

  /// Fija un perfil sin tocar Firebase. Es la costura que hace testeables las
  /// pantallas que dependen del rol.
  @visibleForTesting
  void debugSetProfile(AppUser? profile, {AuthStatus? status}) {
    _profile = profile;
    _status =
        status ??
        (profile == null ? AuthStatus.invitado : AuthStatus.conSesion);
    notifyListeners();
  }
}
