import 'package:flutter/material.dart';

import 'package:taxi1/models/recorrido.dart';
import 'package:taxi1/theme/app_colors.dart';
import 'package:taxi1/widgets/app_map.dart';

/// Las líneas de mapa que dibujan [recorrido]: la línea elegida en el mapa del
/// pasajero, la del chofer, la de la consola de flota y la del editor.
///
/// Sin [sentido] van los dos: la ida continua, ancha y con borde, y el regreso
/// a trazos, para que se distingan donde van por calles distintas. Con
/// [sentido], sólo ése, continuo (es el que lleva al destino del pasajero).
///
/// Ninguna línea se dibuja si nadie la eligió: el mapa del pasajero muestra un
/// punto de seña por línea, no los recorridos encimados.
///
/// Con [badge], cada sentido lleva la insignia de la línea; con [arrows],
/// flechas quietas hacia donde va. [onTap] es para tocar la línea o su
/// insignia.
List<MapLine> recorridoLines(
  Recorrido recorrido,
  AppStatusColors status, {
  Sentido? sentido,
  bool badge = false,
  bool arrows = false,
  VoidCallback? onTap,
}) {
  final color = Color(recorrido.colorValue).withValues(alpha: 1);
  final insignia = badge
      ? LineBadge(
          text: recorrido.sigla,
          color: color,
          textColor:
              ThemeData.estimateBrightnessForColor(color) == Brightness.dark
              ? Colors.white
              : Colors.black,
          borderColor: status.routeLineCasing,
        )
      : null;
  MapLine linea(Trayecto t, {required bool regreso}) => MapLine(
    points: t.trazado,
    color: color,
    width: regreso ? 4.0 : 5.5,
    borderColor: status.routeLineCasing,
    borderWidth: regreso ? 0.0 : 1.5,
    dashed: regreso,
    badge: insignia,
    arrows: arrows,
    onTap: onTap,
  );

  if (sentido != null) {
    final t = recorrido.trayecto(sentido);
    return [if (t != null && t.dibujable) linea(t, regreso: false)];
  }
  final vuelta = recorrido.vuelta;
  return [
    // El regreso primero: donde coinciden, la ida queda encima.
    if (vuelta != null && vuelta.dibujable) linea(vuelta, regreso: true),
    if (recorrido.ida.dibujable) linea(recorrido.ida, regreso: false),
  ];
}
