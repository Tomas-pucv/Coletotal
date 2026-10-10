import 'dart:convert';

/// Rol con el que alguien usa ColeTotal.
///
/// El informe (§7.3.2) pide explícitamente "juntar 3 usuarios en 1 entidad":
/// hay una sola colección `usuarios` con un campo `rol`, no tres colecciones
/// paralelas. [UserRole.invitado] es justamente la *ausencia* de documento —
/// del invitado no se persiste nada, que es lo que le permite entrar sin
/// registrarse.
enum UserRole {
  invitado,
  colectivero,
  administrador;

  /// Valor que viaja a Firestore.
  ///
  /// Se escribe explícito en vez de usar `name` para que renombrar un valor del
  /// enum no invalide en silencio los documentos ya guardados.
  String get wireName => switch (this) {
    UserRole.invitado => 'invitado',
    UserRole.colectivero => 'colectivero',
    UserRole.administrador => 'administrador',
  };

  static UserRole fromWire(String? value) => switch (value) {
    'colectivero' => UserRole.colectivero,
    'administrador' => UserRole.administrador,
    _ => UserRole.invitado,
  };

  /// Si hace falta cuenta para ejercer este rol. Sólo el invitado no la
  /// necesita, y por eso es el único que nunca tiene documento en Firestore.
  bool get requiresAccount => this != UserRole.invitado;
}

/// Perfil persistido de quien inició sesión.
///
/// Deliberadamente sin dependencias de Flutter: se serializa a JSON para
/// cachearlo en `SharedPreferences` y poder pintar la cabecera del menú en el
/// arranque en frío, sin esperar la ida y vuelta a Firestore.
class AppUser {
  const AppUser({
    required this.uid,
    required this.rol,
    required this.nombre,
    required this.garitaId,
    this.patente,
    this.email,
    this.activo = true,
    this.varianteId,
  });

  final String uid;
  final UserRole rol;
  final String nombre;
  final String garitaId;

  /// Variante operacional asignada al chofer (ej. 'belloto-2000', 'las-rosas', 'mirador').
  final String? varianteId;

  /// Sólo colectivero. Normalizada (ver `utils/patente.dart`).
  final String? patente;

  /// Sólo administrador; el colectivero entra con un correo sintético que no
  /// existe como buzón, así que no se guarda.
  final String? email;

  /// Interruptor de la garita. En `false` el chofer no puede transmitir.
  final bool activo;

  /// Lo que se muestra en el menú cuando no hay nombre: la patente identifica
  /// al chofer mejor que un uid.
  String get displayName =>
      nombre.trim().isNotEmpty ? nombre.trim() : (patente ?? email ?? uid);

  /// Iniciales para el avatar. Dos letras como mucho, en mayúscula.
  String get initials {
    final parts = displayName
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) {
      return parts.first.substring(0, 1).toUpperCase();
    }
    return (parts.first.substring(0, 1) + parts[1].substring(0, 1))
        .toUpperCase();
  }

  factory AppUser.fromMap(String uid, Map<String, dynamic> data) {
    return AppUser(
      uid: uid,
      rol: UserRole.fromWire(data['rol'] as String?),
      nombre: (data['nombre'] as String?) ?? '',
      garitaId: (data['garitaId'] as String?) ?? '',
      patente: data['patente'] as String?,
      email: data['email'] as String?,
      // Ausente cuenta como habilitado: un documento viejo sin el campo no debe
      // dejar a su dueño fuera de la app.
      activo: (data['activo'] as bool?) ?? true,
      varianteId: (data['varianteId'] as String?) ?? (data['varianteAsignada'] as String?),
    );
  }

  /// Campos que el cliente escribe al registrarse.
  ///
  /// `codigo` queda guardado a propósito: es lo que la regla de `create` de
  /// Firestore vuelve a leer para verificar que el `rol` reclamado es el que
  /// ese código concede. Sin él, el rol sería una simple afirmación del cliente.
  Map<String, dynamic> toCreateMap({required String codigo}) => {
    'rol': rol.wireName,
    'nombre': nombre,
    'garitaId': garitaId,
    if (patente != null) 'patente': patente,
    if (email != null) 'email': email,
    'activo': activo,
    'codigo': codigo,
    if (varianteId != null) 'varianteId': varianteId,
  };

  AppUser copyWith({
    String? nombre,
    bool? activo,
    String? varianteId,
    bool clearVariante = false,
  }) => AppUser(
    uid: uid,
    rol: rol,
    nombre: nombre ?? this.nombre,
    garitaId: garitaId,
    patente: patente,
    email: email,
    activo: activo ?? this.activo,
    varianteId: clearVariante ? null : (varianteId ?? this.varianteId),
  );

  String toJson() => jsonEncode({
    'uid': uid,
    'rol': rol.wireName,
    'nombre': nombre,
    'garitaId': garitaId,
    'patente': patente,
    'email': email,
    'activo': activo,
    if (varianteId != null) 'varianteId': varianteId,
  });

  static AppUser? fromJson(String? source) {
    if (source == null || source.isEmpty) return null;
    try {
      final data = jsonDecode(source) as Map<String, dynamic>;
      final uid = data['uid'] as String?;
      if (uid == null) return null;
      return AppUser.fromMap(uid, data);
    } catch (_) {
      // Caché corrupta o de un formato anterior: se descarta en silencio y se
      // vuelve a pedir el perfil a Firestore.
      return null;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is AppUser &&
      other.uid == uid &&
      other.rol == rol &&
      other.nombre == nombre &&
      other.garitaId == garitaId &&
      other.patente == patente &&
      other.email == email &&
      other.activo == activo &&
      other.varianteId == varianteId;

  @override
  int get hashCode =>
      Object.hash(uid, rol, nombre, garitaId, patente, email, activo, varianteId);
}
