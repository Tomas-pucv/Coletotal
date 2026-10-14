import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:latlong2/latlong.dart';

import 'package:taxi1/utils/polyline.dart';

/// Sentido de un recorrido: de la garita hacia afuera, o de vuelta.
///
/// Van por separado porque los colectivos no siempre vuelven por las mismas
/// calles (los sentidos de tránsito lo impiden), y porque es lo que permite
/// saber si un colectivo que pasa por la esquina va hacia donde uno quiere ir.
enum Sentido {
  ida,
  vuelta;

  String get wireName => name;
}

/// Un sentido de un recorrido: los puntos que marcó la garita y el trazado por
/// calle que se calculó a partir de ellos.
class Trayecto {
  const Trayecto({
    this.puntos = const [],
    this.geometria = '',
    this.trazado = const [],
  });

  /// Puntos que la garita fue marcando en el editor, en orden. Se guardan para
  /// poder seguir editando el trayecto; el mapa dibuja [trazado].
  final List<LatLng> puntos;

  /// [trazado] codificado en polyline6, tal como se guarda en Firestore.
  final String geometria;

  /// El recorrido real, siguiendo las calles y sus sentidos de tránsito.
  final List<LatLng> trazado;

  /// Un trayecto con menos de dos puntos de trazado no lleva a ninguna parte.
  bool get dibujable => trazado.length >= 2;

  factory Trayecto.fromMap(Map<String, dynamic>? data) {
    if (data == null) return const Trayecto();
    final geometria = (data['geometria'] as String?) ?? '';
    return Trayecto(
      puntos: [
        for (final p in (data['puntos'] as List?) ?? const [])
          if (p is GeoPoint && isValidLatLng(LatLng(p.latitude, p.longitude)))
            LatLng(p.latitude, p.longitude),
      ],
      geometria: geometria,
      trazado: _decodificar(geometria),
    );
  }

  /// Decodifica [geometria] y descarta lo que no sea una coordenada válida:
  /// una geometría corrupta no se dibuja fuera del mapa. Si no quedan al menos
  /// dos puntos, se trata como si no hubiera trazado.
  static List<LatLng> _decodificar(String geometria) {
    if (geometria.isEmpty) return const [];
    try {
      final puntos = decodePolyline(
        geometria,
        precision: 6,
      ).where(isValidLatLng).toList(growable: false);
      return puntos.length >= 2 ? puntos : const [];
    } catch (_) {
      return const [];
    }
  }

  Map<String, dynamic> toMap() => {
    'puntos': [for (final p in puntos) GeoPoint(p.latitude, p.longitude)],
    'geometria': geometria,
  };
}

/// Una línea de colectivos: su nombre, su color y su recorrido de ida y de
/// vuelta.
///
/// Se llama **recorrido** y no "ruta" a propósito: en este proyecto `ruta` es
/// otra cosa —`RouteService` calcula el camino *a pie* del pasajero—, y
/// "recorrido" es además la palabra que se usa en el transporte chileno.
///
/// No tiene paraderos. Los colectivos paran donde se les hace la seña, a lo
/// largo de todo el recorrido; los paraderos que tuvo la app hasta el
/// 10 de octubre de 2026 eran datos de prueba inventados.
class Recorrido {
  const Recorrido({
    required this.id,
    required this.garitaId,
    required this.nombre,
    required this.colorValue,
    this.ida = const Trayecto(),
    this.vuelta,
    this.activo = true,
  });

  final String id;
  final String garitaId;
  final String nombre;

  /// Color ARGB con el que se dibuja en el mapa.
  final int colorValue;

  final Trayecto ida;

  /// `null` mientras la garita no la haya dibujado.
  final Trayecto? vuelta;

  final bool activo;

  /// Lo mínimo para mostrársela a un pasajero: un nombre y una ida dibujable.
  bool get isValid => nombre.trim().isNotEmpty && ida.dibujable;

  /// Rótulo corto para la insignia de la línea en el mapa.
  ///
  /// Es la primera palabra del nombre que lleve un número ("PRUEBA 1: Centro"
  /// → "1", "Línea 12A" → "12A"). Si no hay, las iniciales de las primeras
  /// palabras, sin artículos ("El Belloto – Centro" → "BC").
  String get sigla {
    final palabras = nombre
        .split(RegExp(r'[\s:;,.·/()–—-]+'))
        .where((p) => p.isNotEmpty)
        .toList(growable: false);
    for (final p in palabras) {
      if (p.contains(RegExp(r'\d'))) {
        return p.length <= 4
            ? p.toUpperCase()
            : p.substring(0, 4).toUpperCase();
      }
    }
    const articulos = {'de', 'del', 'la', 'las', 'el', 'los', 'y', 'a', 'al'};
    final iniciales = palabras
        .where((p) => !articulos.contains(p.toLowerCase()))
        .take(3)
        .map((p) => String.fromCharCode(p.runes.first).toUpperCase())
        .join();
    return iniciales.isNotEmpty ? iniciales : '?';
  }

  Trayecto? trayecto(Sentido sentido) => switch (sentido) {
    Sentido.ida => ida,
    Sentido.vuelta => vuelta,
  };

  /// Los sentidos que tienen trazado, en orden: ida y después vuelta.
  Iterable<(Sentido, Trayecto)> get trayectos sync* {
    if (ida.dibujable) yield (Sentido.ida, ida);
    final v = vuelta;
    if (v != null && v.dibujable) yield (Sentido.vuelta, v);
  }

  factory Recorrido.fromMap(String id, Map<String, dynamic> data) {
    final vuelta = data['vuelta'];
    return Recorrido(
      id: id,
      garitaId: (data['garitaId'] as String?) ?? '',
      nombre: (data['nombre'] as String?) ?? '',
      colorValue: (data['color'] as num?)?.toInt() ?? kRecorridoColors.first,
      ida: Trayecto.fromMap(data['ida'] as Map<String, dynamic>?),
      vuelta: vuelta is Map<String, dynamic> ? Trayecto.fromMap(vuelta) : null,
      activo: (data['activo'] as bool?) ?? true,
    );
  }

  Map<String, dynamic> toMap() => {
    'garitaId': garitaId,
    'nombre': nombre,
    'color': colorValue,
    'activo': activo,
    'ida': ida.toMap(),
    if (vuelta case final v?) 'vuelta': v.toMap(),
  };

  Recorrido copyWith({
    String? nombre,
    int? colorValue,
    Trayecto? ida,
    Trayecto? vuelta,
    bool? activo,
  }) => Recorrido(
    id: id,
    garitaId: garitaId,
    nombre: nombre ?? this.nombre,
    colorValue: colorValue ?? this.colorValue,
    ida: ida ?? this.ida,
    vuelta: vuelta ?? this.vuelta,
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
/// sobre el mapa se leería como "hay cupo". Tampoco el morado de la ruta a pie.
/// Ver `theme/app_colors.dart`.
const List<int> kRecorridoColors = [
  0xFFB0338A, // magenta
  0xFF00727C, // teal oscuro
  0xFF7B3FA0, // violeta
  0xFF5D4037, // café
  0xFF37474F, // gris azulado
  0xFF827717, // oliva
];
