import 'dart:math' as math;

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
    this.conectado = true,
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

  /// `false` cuando el servidor detectó que el teléfono del chofer perdió la
  /// conexión: lo escribe el `onDisconnect` registrado al iniciar el turno.
  /// Ausente en los nodos antiguos, que cuentan como conectados.
  final bool conectado;

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

  /// Desde cuánto sin noticias una unidad se dibuja atenuada, como "sin
  /// señal", antes de desaparecer a los [maxAntiguedad]. Con un envío cada
  /// pocos segundos, 45 s de silencio ya son un túnel o un cerro.
  static const Duration sinSenal = Duration(seconds: 45);

  /// Si la última posición ya es demasiado vieja para mostrarla.
  ///
  /// [ahora] debe ser la hora **del servidor** (ver
  /// `FirebaseTelemetriaService.serverNow`), porque `ts` la pone el servidor:
  /// comparar contra el reloj del teléfono hacía que un teléfono adelantado
  /// tres minutos no viera ningún colectivo, y uno atrasado viera fantasmas.
  /// Un nodo sin `ts` (formato antiguo) se considera vigente: es preferible
  /// mostrar de más que hacer desaparecer unidades reales tras una migración.
  bool isStale([DateTime? ahora]) {
    final age = antiguedad(ahora);
    return age != null && age > maxAntiguedad;
  }

  /// Si la unidad sigue en el mapa pero perdió la señal: el servidor la marcó
  /// desconectada o lleva más de [sinSenal] sin enviar posición.
  bool seemsOffline([DateTime? ahora]) {
    if (!conectado) return true;
    final age = antiguedad(ahora);
    return age != null && age > sinSenal;
  }

  /// Tiempo desde la última posición, o `null` si el nodo no trae `ts`.
  Duration? antiguedad([DateTime? ahora]) {
    if (ts == null) return null;
    final now = (ahora ?? DateTime.now()).millisecondsSinceEpoch;
    return Duration(milliseconds: math.max(0, now - ts!));
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
      conectado: (json['conectado'] as bool?) ?? true,
      ts: (json['ts'] as num?)?.toInt(),
    );
  }

  /// Payload sin `ts`: la marca de tiempo la pone el servidor y se añade en el
  /// servicio, porque `ServerValue.timestamp` es un centinela, no un número.
  ///
  /// Cada clave tiene que estar permitida en `database.rules.json`, que
  /// rechaza cualquier hijo desconocido. Antes `recorridoId`,
  /// `recorridoNombre` y `conectado` no lo estaban; lo vigila el test de
  /// contrato de reglas.
  Map<String, dynamic> toJson() => {
    'uid': uid,
    'idVehiculo': idVehiculo,
    'garitaId': garitaId,
    'latitud': latitud,
    'longitud': longitud,
    'estado': estado.wireName,
    'recorridoId': ?recorridoId,
    'recorridoNombre': ?recorridoNombre,
    'conectado': conectado,
  };

  /// [clearRecorrido] quita la línea asignada: con `??` no había forma de
  /// volver a `null` cuando el chofer elige "Sin recorrido".
  ColectivoActivo copyWith({
    double? latitud,
    double? longitud,
    EstadoCapacidad? estado,
    String? recorridoId,
    String? recorridoNombre,
    bool clearRecorrido = false,
    bool? conectado,
    int? ts,
  }) => ColectivoActivo(
    uid: uid,
    idVehiculo: idVehiculo,
    garitaId: garitaId,
    latitud: latitud ?? this.latitud,
    longitud: longitud ?? this.longitud,
    estado: estado ?? this.estado,
    recorridoId: clearRecorrido ? null : (recorridoId ?? this.recorridoId),
    recorridoNombre: clearRecorrido
        ? null
        : (recorridoNombre ?? this.recorridoNombre),
    conectado: conectado ?? this.conectado,
    ts: ts ?? this.ts,
  );
}
