/// Capacidad reportada por el chofer.
///
/// Es la "semaforización" que pide el informe §7.3.1-C: el administrador
/// diagnostica de un vistazo la oferta de la línea por el color de los
/// marcadores. Los tres tonos ya existen en `AppStatusColors`.
enum EstadoCapacidad {
  disponible,
  medioLleno,
  lleno;

  String get wireName => switch (this) {
    EstadoCapacidad.disponible => 'disponible',
    EstadoCapacidad.medioLleno => 'medioLleno',
    EstadoCapacidad.lleno => 'lleno',
  };

  static EstadoCapacidad fromWire(String? value) => switch (value) {
    'medioLleno' => EstadoCapacidad.medioLleno,
    'lleno' => EstadoCapacidad.lleno,
    _ => EstadoCapacidad.disponible,
  };
}

/// Una unidad transmitiendo su posición en Realtime Database.
///
/// El nodo se guarda en `colectivos_activos/{uid}` — **la clave es el uid de
/// Firebase Auth**, no un identificador elegido por el cliente. Ese cambio es
/// lo que hace posible la regla `auth.uid === $uid`: antes cualquiera podía
/// escribir el nodo de cualquier vehículo.
class ColectivoActivo {
  const ColectivoActivo({
    required this.uid,
    required this.idVehiculo,
    required this.latitud,
    required this.longitud,
    this.garitaId = '',
    this.estado = EstadoCapacidad.disponible,
    this.recorridoId,
    this.recorridoNombre,
    this.ts,
  });

  /// Clave del nodo y dueño de la escritura.
  final String uid;

  /// Patente. Es lo que se muestra: un uid no le dice nada a nadie.
  final String idVehiculo;

  final String garitaId;
  final double latitud;
  final double longitud;
  final EstadoCapacidad estado;

  /// ID del recorrido que está cubriendo actualmente (ej. 'recorrido-101-valencia-hospital').
  final String? recorridoId;

  /// Nombre amigable de la línea (ej. 'Línea 101: Valencia - Hospital').
  final String? recorridoNombre;

  /// Marca de tiempo del servidor, en milisegundos. Nula en los nodos escritos
  /// por versiones anteriores de la app.
  final int? ts;

  /// Cuánto tiempo sin noticias antes de dar por muerta a una unidad.
  ///
  /// `onDisconnect` de Firebase no se dispara al instante cuando se cae la red:
  /// espera a que expire la conexión TCP, lo que puede tardar minutos. Sin este
  /// filtro quedan "colectivos fantasma" clavados en el mapa, que es el fallo
  /// más visible que puede tener una demo.
  static const Duration maxAntiguedad = Duration(seconds: 180);

  /// Si la última posición ya es demasiado vieja para mostrarla.
  ///
  /// [ahora] se inyecta para poder testearlo sin depender del reloj. Un nodo
  /// sin `ts` (formato antiguo) se considera vigente: es preferible mostrar de
  /// más que hacer desaparecer unidades reales tras una migración.
  bool isStale([DateTime? ahora]) {
    if (ts == null) return false;
    final now = (ahora ?? DateTime.now()).millisecondsSinceEpoch;
    return now - ts! > maxAntiguedad.inMilliseconds;
  }

  factory ColectivoActivo.fromJson(Map<String, dynamic> json) {
    // `uid` no existía en el formato anterior, donde la clave era un id
    // generado en el teléfono y guardado en `idVehiculo`. Se cae a ese valor
    // para que los nodos viejos sigan parseando en vez de tirar el stream
    // entero al suelo.
    final id = (json['uid'] as String?) ?? (json['idVehiculo'] as String? ?? '');
    return ColectivoActivo(
      uid: id,
      idVehiculo: (json['idVehiculo'] as String?) ?? id,
      garitaId: (json['garitaId'] as String?) ?? '',
      latitud: (json['latitud'] as num).toDouble(),
      longitud: (json['longitud'] as num).toDouble(),
      estado: EstadoCapacidad.fromWire(json['estado'] as String?),
      recorridoId: json['recorridoId'] as String?,
      recorridoNombre: json['recorridoNombre'] as String?,
      ts: (json['ts'] as num?)?.toInt(),
    );
  }

  /// Payload sin `ts`: la marca de tiempo la pone el servidor y se añade en el
  /// servicio, porque `ServerValue.timestamp` es un centinela, no un número.
  Map<String, dynamic> toJson() => {
    'uid': uid,
    'idVehiculo': idVehiculo,
    'garitaId': garitaId,
    'latitud': latitud,
    'longitud': longitud,
    'estado': estado.wireName,
    if (recorridoId != null) 'recorridoId': recorridoId,
    if (recorridoNombre != null) 'recorridoNombre': recorridoNombre,
  };

  ColectivoActivo copyWith({
    double? latitud,
    double? longitud,
    EstadoCapacidad? estado,
    String? recorridoId,
    String? recorridoNombre,
    int? ts,
  }) => ColectivoActivo(
    uid: uid,
    idVehiculo: idVehiculo,
    garitaId: garitaId,
    latitud: latitud ?? this.latitud,
    longitud: longitud ?? this.longitud,
    estado: estado ?? this.estado,
    recorridoId: recorridoId ?? this.recorridoId,
    recorridoNombre: recorridoNombre ?? this.recorridoNombre,
    ts: ts ?? this.ts,
  );
}
