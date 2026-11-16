import 'package:taxi1/models/app_user.dart';

/// Terminal de una línea de colectivos (informe §7.3.2: "entidad garita
/// aparte"). Sólo metadatos públicos: los códigos de acceso viven en su propia
/// colección, ver [CodigoAcceso].
class Garita {
  const Garita({required this.id, required this.nombre, this.comuna = ''});

  final String id;
  final String nombre;
  final String comuna;

  factory Garita.fromMap(String id, Map<String, dynamic> data) => Garita(
    id: id,
    nombre: (data['nombre'] as String?) ?? id,
    comuna: (data['comuna'] as String?) ?? '',
  );

  Map<String, dynamic> toMap() => {'nombre': nombre, 'comuna': comuna};
}

/// Código de enrolamiento que la garita entrega a sus choferes y
/// administradores.
///
/// Vive en `codigos_acceso/{CODIGO}` — **el id del documento es el código**.
/// Eso es lo que permite validarlo antes de crear la cuenta sin exponer la
/// lista: las reglas de Firestore distinguen `get` (un documento por id) de
/// `list` (consulta), así que con `allow get: if true; allow list: if false;`
/// hay que conocer el código exacto para llegar al documento.
///
/// Los códigos, por lo tanto, tienen que ser largos y no adivinables.
class CodigoAcceso {
  const CodigoAcceso({
    required this.codigo,
    required this.garitaId,
    required this.rol,
    this.activo = true,
  });

  final String codigo;
  final String garitaId;
  final UserRole rol;

  /// Interruptor de revocación. Es lo único que se puede hacer sin Admin SDK:
  /// no hay forma segura de llevar la cuenta de usos desde el cliente.
  final bool activo;

  factory CodigoAcceso.fromMap(String codigo, Map<String, dynamic> data) =>
      CodigoAcceso(
        codigo: codigo,
        garitaId: (data['garitaId'] as String?) ?? '',
        rol: UserRole.fromWire(data['rol'] as String?),
        activo: (data['activo'] as bool?) ?? true,
      );

  /// Un código sirve si está habilitado, apunta a una garita y concede un rol
  /// que realmente requiere cuenta (nunca "invitado").
  bool get isUsable => activo && garitaId.isNotEmpty && rol.requiresAccount;
}
