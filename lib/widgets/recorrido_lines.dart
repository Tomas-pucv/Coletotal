import 'package:flutter/material.dart';

import 'package:taxi1/models/recorrido.dart';
import 'package:taxi1/theme/app_colors.dart';
import 'package:taxi1/widgets/app_map.dart';

/// Cuánto resalta una línea en el mapa.
enum LineEmphasis {
  /// La que el usuario eligió: opaca, ancha y con borde.
  selected,

  /// Sin ninguna elegida, todas a la vista: semitransparentes.
  normal,

  /// Hay otra elegida: apenas se insinúan.
  faded,
}

/// Las líneas de mapa que dibujan [recorrido], para el mapa del pasajero, la
/// consola de flota y el editor de la garita.
///
/// Sin [sentido] se dibujan los dos: la ida con el color de la línea y, debajo,
/// la vuelta más clara, para que se distingan donde van por calles distintas.
/// Con [sentido], sólo ése (es el que lleva al destino del pasajero).
///
/// Con [badge], cada sentido lleva la insignia de la línea; con [arrows],
/// flechas hacia donde va. [onTap] es para tocar la línea o su insignia.
List<MapLine> recorridoLines(
  Recorrido recorrido,
  AppStatusColors status, {
  Sentido? sentido,
  LineEmphasis emphasis = LineEmphasis.selected,
  bool badge = false,
  bool arrows = false,
  VoidCallback? onTap,
}) {
  final color = Color(recorrido.colorValue);
  final insignia = badge
      ? LineBadge(
          text: recorrido.sigla,
          color: color.withValues(alpha: 1),
          textColor:
              ThemeData.estimateBrightnessForColor(color) == Brightness.dark
              ? Colors.white
              : Colors.black,
          borderColor: status.routeLineCasing,
        )
      : null;
  MapLine linea(Trayecto t, {required bool principal}) {
    final (alfa, ancho, borde) = switch (emphasis) {
      LineEmphasis.selected => principal ? (0.85, 6.0, 1.5) : (0.45, 4.0, 1.0),
      LineEmphasis.normal => principal ? (0.55, 4.5, 0.0) : (0.35, 3.5, 0.0),
      LineEmphasis.faded => principal ? (0.22, 3.0, 0.0) : (0.14, 2.5, 0.0),
    };
    return MapLine(
      points: t.trazado,
      color: color.withValues(alpha: alfa),
      width: ancho,
      borderColor: status.routeLineCasing,
      borderWidth: borde,
      badge: insignia,
      badgeOpacity: emphasis == LineEmphasis.faded ? 0.6 : 1,
      arrows: arrows,
      onTap: onTap,
    );
  }

  if (sentido != null) {
    final t = recorrido.trayecto(sentido);
    return [if (t != null && t.dibujable) linea(t, principal: true)];
  }
  final vuelta = recorrido.vuelta;
  return [
    // La vuelta primero: donde coinciden, la ida queda encima.
    if (vuelta != null && vuelta.dibujable) linea(vuelta, principal: false),
    if (recorrido.ida.dibujable) linea(recorrido.ida, principal: true),
  ];
}

/// Todas las [lineas] para el mapa del pasajero, siempre a la vista: así se
/// ve por dónde pasan los colectivos antes de buscar nada.
///
/// Sin ninguna [elegida], todas semitransparentes y con flechas. Con una
/// elegida, ésa resalta (sólo su [sentido], si lo hay) y las demás casi
/// desaparecen; sólo la elegida lleva flechas. Las insignias van en todas,
/// para poder elegir otra tocándola ([onTap]).
List<MapLine> lineasDelMapa(
  List<Recorrido> lineas,
  AppStatusColors status, {
  Recorrido? elegida,
  Sentido? sentido,
  required ValueChanged<Recorrido> onTap,
}) => [
  for (final r in lineas)
    if (r.id != elegida?.id)
      ...recorridoLines(
        r,
        status,
        emphasis: elegida == null ? LineEmphasis.normal : LineEmphasis.faded,
        badge: true,
        arrows: elegida == null,
        onTap: () => onTap(r),
      ),
  // La elegida al final: queda encima de las demás y su insignia gana.
  if (elegida != null)
    ...recorridoLines(
      elegida,
      status,
      sentido: sentido,
      badge: true,
      arrows: true,
      onTap: () => onTap(elegida),
    ),
];
