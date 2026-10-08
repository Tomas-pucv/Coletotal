import 'package:latlong2/latlong.dart';
import 'package:taxi1/utils/polyline.dart';

/// Un recorrido de la línea: el trayecto fijo que hacen los colectivos.
///
/// Se llama **recorrido** y no "ruta" a propósito. En este proyecto `ruta` ya
/// significa otra cosa desde antes — `RouteService`, `RouteResult` y
/// `RoutesScreen` son las *indicaciones* desde el pasajero hasta un paradero—,
/// y usar la misma palabra para dos conceptos distintos garantizaba
/// confusiones. "Recorrido" es además la palabra que se usa en el transporte
/// público chileno.
class Recorrido {
  const Recorrido({
    required this.id,
    required this.garitaId,
    required this.nombre,
    required this.colorValue,
    this.paraderoIds = const [],
    this.geometria,
    this.trazado = const [],
    this.activo = true,
  });

  final String id;
  final String garitaId;
  final String nombre;

  /// Color ARGB con el que se dibuja en el mapa.
  final int colorValue;

  /// Paraderos **en orden de recorrido**. El trazado se deriva de esta lista
  /// conectando los paraderos por calle, en vez de dibujarse punto a punto:
  /// reutiliza el mismo enrutador que ya usa el pasajero y hace imposible que
  /// el trazado se desincronice de los paraderos.
  final List<String> paraderoIds;

  /// Geometría codificada en polyline6 que sigue la red vial y sentidos de calle.
  final String? geometria;

  /// Puntos decodificados de la polilínea para renderizado directo en mapa.
  final List<LatLng> trazado;

  final bool activo;

  /// Un recorrido con menos de dos paraderos no describe ningún trayecto.
  bool get isValid => nombre.trim().isNotEmpty && paraderoIds.length >= 2;

  factory Recorrido.fromMap(String id, Map<String, dynamic> data) {
    final rawGeo = data['geometria'] as String?;
    List<LatLng> trazado = const [];
    if (rawGeo != null && rawGeo.isNotEmpty) {
      try {
        // Sólo puntos válidos: una geometría corrupta ya no se dibuja fuera del
        // mapa. Si no quedan al menos dos, se trata como si no hubiera, y el
        // trazado se recalcula siguiendo las calles.
        final puntos = decodePolyline(
          rawGeo,
          precision: 6,
        ).where(isValidLatLng).toList(growable: false);
        trazado = puntos.length >= 2 ? puntos : const [];
      } catch (_) {
        trazado = const [];
      }
    }

    return Recorrido(
      id: id,
      garitaId: (data['garitaId'] as String?) ?? '',
      nombre: (data['nombre'] as String?) ?? '',
      colorValue: (data['color'] as num?)?.toInt() ?? 0xFF4A3F9E,
      paraderoIds:
          (data['paraderoIds'] as List?)?.whereType<String>().toList(
            growable: false,
          ) ??
          const [],
      geometria: rawGeo,
      trazado: trazado,
      activo: (data['activo'] as bool?) ?? true,
    );
  }

  Map<String, dynamic> toMap() => {
    'garitaId': garitaId,
    'nombre': nombre,
    'color': colorValue,
    'paraderoIds': paraderoIds,
    if (geometria != null) 'geometria': geometria,
    'activo': activo,
  };

  Recorrido copyWith({
    String? nombre,
    int? colorValue,
    List<String>? paraderoIds,
    String? geometria,
    List<LatLng>? trazado,
    bool? activo,
  }) => Recorrido(
    id: id,
    garitaId: garitaId,
    nombre: nombre ?? this.nombre,
    colorValue: colorValue ?? this.colorValue,
    paraderoIds: paraderoIds ?? this.paraderoIds,
    geometria: geometria ?? this.geometria,
    trazado: trazado ?? this.trazado,
    activo: activo ?? this.activo,
  );

  @override
  bool operator ==(Object other) => other is Recorrido && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// Paleta para los recorridos.
///
/// Ni azul (ubicación del usuario) ni verde/ámbar/rojo (semaforización de
/// capacidad): esos cuatro están reservados y un recorrido pintado de verde
/// sobre el mapa se leería como "hay cupo". Ver `theme/app_colors.dart`.
const List<int> kRecorridoColors = [
  0xFF4A3F9E, // índigo (la marca original, antes del amarillo colectivo)
  0xFF7B3FA0, // violeta
  0xFFB0338A, // magenta
  0xFF00727C, // teal oscuro
  0xFF5D4037, // café
  0xFF37474F, // gris azulado
];
