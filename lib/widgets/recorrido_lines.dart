import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import 'package:taxi1/models/recorrido.dart';
import 'package:taxi1/services/puntos_de_sena.dart';
import 'package:taxi1/theme/app_colors.dart';
import 'package:taxi1/utils/polyline.dart';
import 'package:taxi1/widgets/app_map.dart';

/// Las líneas de mapa que dibujan [recorrido]: las líneas de los colectivos
/// cercanos o la línea elegida en el mapa del pasajero, la del chofer, la de la
/// consola de flota y la del editor.
///
/// Sin [sentido] van los dos, cada uno por su carril: corridos a la derecha de
/// su marcha, como los autos, quedan lado a lado donde comparten la calle y
/// cada uno por la suya donde no. Con [destacado], ése va entero y el otro
/// tenue: es el sentido en que el pasajero eligió tomarlo.
///
/// Con [sentido], sólo ése, al centro de la calle (es el que lleva al destino
/// del pasajero). Si además viene [tramo] —de qué metro a qué metro de la
/// línea se viaja—, ese trozo va entero y el resto del sentido, tenue.
///
/// Con [badge], una de las líneas lleva la insignia de la línea (con su
/// variante si tiene cartola, p. ej. "10 T"); con [arrows], flechas quietas
/// hacia donde va. [onTap] es para tocar la línea o su insignia.
List<MapLine> recorridoLines(
  Recorrido recorrido,
  AppStatusColors status, {
  Sentido? sentido,
  Sentido? destacado,
  ({double desde, double hasta})? tramo,
  bool badge = false,
  bool arrows = false,
  VoidCallback? onTap,
}) {
  final color = Color(recorrido.colorValue).withValues(alpha: 1);
  final tenue = color.withValues(alpha: 0.4);
  final insignia = badge
      ? LineBadge(
          text: PuntosDeSena.etiqueta(recorrido),
          color: color,
          textColor:
              ThemeData.estimateBrightnessForColor(color) == Brightness.dark
              ? Colors.white
              : Colors.black,
          borderColor: status.routeLineCasing,
        )
      : null;

  // Sola por su calle: ancha, con su contorno y su sombra.
  MapLine entera(List<LatLng> puntos) => MapLine(
    points: puntos,
    color: color,
    width: 6,
    borderColor: _contorno,
    borderWidth: 1.5,
    shadow: true,
    badge: insignia,
    arrows: arrows,
    onTap: onTap,
  );

  if (sentido != null) {
    final t = recorrido.trayecto(sentido);
    if (t == null || !t.dibujable) return const [];
    final viaje = tramo == null
        ? const <LatLng>[]
        : subLinea(t.trazado, tramo.desde, tramo.hasta);
    if (viaje.isEmpty) return [entera(t.trazado)];
    return [
      // Por dónde sigue la línea antes y después del viaje: referencia.
      MapLine(points: t.trazado, color: tenue, width: 4, onTap: onTap),
      entera(viaje),
    ];
  }

  final sentidos = recorrido.trayectos.toList(growable: false);
  if (sentidos.length < 2) {
    return [for (final (_, t) in sentidos) entera(t.trazado)];
  }

  bool fuerte(Sentido s) => destacado == null || destacado == s;
  // La insignia, en una sola de las dos: la destacada o, sin destacada, la
  // ida. En las dos se repetiría el doble a lo largo de la misma calle.
  final conInsignia = destacado ?? Sentido.ida;
  MapLine carril(Sentido s, Trayecto t) => MapLine(
    points: t.trazado,
    color: fuerte(s) ? color : tenue,
    width: MapLine.laneWidth,
    // La tenue conserva el ancho del borde, sin pintarlo: así queda en su
    // carril, pegada a la otra, y se funde con el mapa.
    borderColor: fuerte(s) ? _contorno : const Color(0x00000000),
    borderWidth: MapLine.laneBorder,
    lane: true,
    shadow: fuerte(s),
    badge: s == conInsignia ? insignia : null,
    arrows: arrows && fuerte(s),
    onTap: onTap,
  );
  return [
    // La tenue primero y, entre iguales, el regreso: en un cruce la que
    // importa queda encima.
    for (final (s, t) in sentidos.reversed)
      if (!fuerte(s)) carril(s, t),
    for (final (s, t) in sentidos.reversed)
      if (fuerte(s)) carril(s, t),
  ];
}

/// El contorno de una línea de colectivos: blanco en cualquier tema. Los
/// colores de las líneas son tonos oscuros (`kRecorridoColors`), y con un
/// contorno oscuro —el del tema oscuro— se perdían contra el mapa oscuro y
/// contra la foto del satélite.
const Color _contorno = Color(0xFFFFFFFF);
