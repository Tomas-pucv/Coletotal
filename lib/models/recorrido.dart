import 'package:latlong2/latlong.dart';
import 'package:taxi1/utils/polyline.dart';
import 'package:taxi1/utils/text_search.dart';

/// Un recorrido de la línea: el trayecto fijo que hacen los colectivos.
///
/// En el transporte público menor chileno (taxis colectivos), no existen
/// paraderos fijos; los recorridos se estructuran a través de **Cartolas**
/// oficiales del MTT, que definen la secuencia de calles de ida y de vuelta
/// dentro de una **Variante** operacional de la garita.
class Recorrido {
  const Recorrido({
    required this.id,
    required this.garitaId,
    required this.nombre,
    required this.colorValue,
    this.varianteId = '',
    this.varianteNombre = '',
    this.callesIda = const [],
    this.callesVuelta = const [],
    this.paraderoIds = const [],
    this.geometria,
    this.geometriaVuelta,
    this.trazado = const [],
    this.trazadoVuelta = const [],
    this.activo = true,
  });

  final String id;
  final String garitaId;
  final String nombre;

  /// Variante operacional a la que pertenece este recorrido
  /// (ej. 'belloto-2000', 'las-rosas', 'mirador').
  final String varianteId;

  /// Nombre legible de la variante (ej. 'Belloto 2000', 'Las Rosas').
  final String varianteNombre;

  /// Secuencia ordenada de calles o hitos principales de la **Cartola de Ida**.
  final List<String> callesIda;

  /// Secuencia ordenada de calles o hitos principales de la **Cartola de Vuelta**.
  final List<String> callesVuelta;

  /// Color ARGB con el que se dibuja en el mapa.
  final int colorValue;

  /// Paraderos históricos (se conservan por compatibilidad, pero ya no se usan
  /// para renderizado de pines).
  final List<String> paraderoIds;

  /// Geometría codificada en polyline6 del trazado de Ida (o trazado completo).
  final String? geometria;

  /// Geometría codificada en polyline6 del trazado de Vuelta.
  final String? geometriaVuelta;

  /// Puntos decodificados de la polilínea de Ida para renderizado en mapa.
  final List<LatLng> trazado;

  /// Puntos decodificados de la polilínea de Vuelta para renderizado en mapa.
  final List<LatLng> trazadoVuelta;

  final bool activo;

  /// Un recorrido es válido si tiene nombre y tiene calles en su cartola o
  /// puntos de trazado.
  bool get isValid =>
      nombre.trim().isNotEmpty &&
      (callesIda.isNotEmpty || paraderoIds.length >= 2 || trazado.length >= 2);

  /// Todas las calles de ida y vuelta unificadas sin duplicados consecutivos.
  List<String> get todasLasCalles {
    final list = <String>[...callesIda];
    for (final c in callesVuelta) {
      if (!list.contains(c)) list.add(c);
    }
    return list;
  }

  /// Distancia mínima en metros desde [point] hasta cualquier segmento vial
  /// de este recorrido (evalúa tanto el trazado de ida como el de vuelta).
  double distanceFrom(LatLng point) {
    var minD = double.infinity;
    if (trazado.isNotEmpty) {
      final d = distanceToPolyline(point, trazado);
      if (d < minD) minD = d;
    }
    if (trazadoVuelta.isNotEmpty) {
      final d = distanceToPolyline(point, trazadoVuelta);
      if (d < minD) minD = d;
    }
    return minD;
  }

  /// Comprueba si [query] coincide con el nombre de la línea, la variante o
  /// cualquiera de las calles de la cartola.
  bool matchesQuery(String query) {
    final q = query.trim();
    if (q.isEmpty) return true;
    final campos = <String>[
      nombre,
      varianteNombre,
      ...callesIda,
      ...callesVuelta,
    ];
    return matchesAllTokens(q, campos);
  }

  factory Recorrido.fromMap(String id, Map<String, dynamic> data) {
    final rawGeo = data['geometria'] as String?;
    final rawGeoVuelta = data['geometriaVuelta'] as String?;

    List<LatLng> trazado = const [];
    if (rawGeo != null && rawGeo.isNotEmpty) {
      try {
        final puntos = decodePolyline(
          rawGeo,
          precision: 6,
        ).where(isValidLatLng).toList(growable: false);
        trazado = puntos.length >= 2 ? puntos : const [];
      } catch (_) {
        trazado = const [];
      }
    }

    List<LatLng> trazadoVuelta = const [];
    if (rawGeoVuelta != null && rawGeoVuelta.isNotEmpty) {
      try {
        final puntos = decodePolyline(
          rawGeoVuelta,
          precision: 6,
        ).where(isValidLatLng).toList(growable: false);
        trazadoVuelta = puntos.length >= 2 ? puntos : const [];
      } catch (_) {
        trazadoVuelta = const [];
      }
    }

    return Recorrido(
      id: id,
      garitaId: (data['garitaId'] as String?) ?? '',
      nombre: (data['nombre'] as String?) ?? '',
      varianteId: (data['varianteId'] as String?) ?? '',
      varianteNombre: (data['varianteNombre'] as String?) ?? '',
      callesIda:
          (data['callesIda'] as List?)?.whereType<String>().toList(
            growable: false,
          ) ??
          const [],
      callesVuelta:
          (data['callesVuelta'] as List?)?.whereType<String>().toList(
            growable: false,
          ) ??
          const [],
      colorValue: (data['color'] as num?)?.toInt() ?? 0xFF4A3F9E,
      paraderoIds:
          (data['paraderoIds'] as List?)?.whereType<String>().toList(
            growable: false,
          ) ??
          const [],
      geometria: rawGeo,
      geometriaVuelta: rawGeoVuelta,
      trazado: trazado,
      trazadoVuelta: trazadoVuelta,
      activo: (data['activo'] as bool?) ?? true,
    );
  }

  Map<String, dynamic> toMap() => {
    'garitaId': garitaId,
    'nombre': nombre,
    'varianteId': varianteId,
    'varianteNombre': varianteNombre,
    'callesIda': callesIda,
    'callesVuelta': callesVuelta,
    'color': colorValue,
    'paraderoIds': paraderoIds,
    if (geometria != null) 'geometria': geometria,
    if (geometriaVuelta != null) 'geometriaVuelta': geometriaVuelta,
    'activo': activo,
  };

  Recorrido copyWith({
    String? nombre,
    String? varianteId,
    String? varianteNombre,
    List<String>? callesIda,
    List<String>? callesVuelta,
    int? colorValue,
    List<String>? paraderoIds,
    String? geometria,
    String? geometriaVuelta,
    List<LatLng>? trazado,
    List<LatLng>? trazadoVuelta,
    bool? activo,
  }) => Recorrido(
    id: id,
    garitaId: garitaId,
    nombre: nombre ?? this.nombre,
    varianteId: varianteId ?? this.varianteId,
    varianteNombre: varianteNombre ?? this.varianteNombre,
    callesIda: callesIda ?? this.callesIda,
    callesVuelta: callesVuelta ?? this.callesVuelta,
    colorValue: colorValue ?? this.colorValue,
    paraderoIds: paraderoIds ?? this.paraderoIds,
    geometria: geometria ?? this.geometria,
    geometriaVuelta: geometriaVuelta ?? this.geometriaVuelta,
    trazado: trazado ?? this.trazado,
    trazadoVuelta: trazadoVuelta ?? this.trazadoVuelta,
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
  0xFF4A3F9E, // índigo (marca original)
  0xFF7B3FA0, // violeta
  0xFFB0338A, // magenta
  0xFF00727C, // teal oscuro
  0xFF5D4037, // café
  0xFF37474F, // gris azulado
];
