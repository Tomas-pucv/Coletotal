import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart' show kTouchSlop;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;
import 'package:latlong2/latlong.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as ml;

import 'package:taxi1/config/map_config.dart';
import 'package:taxi1/services/basemap_service.dart';
import 'package:taxi1/utils/polyline.dart';
import 'package:taxi1/widgets/map_attribution.dart';

// ---------------------------------------------------------------------------
// Lo que las pantallas dibujan sobre el mapa
// ---------------------------------------------------------------------------

/// Una imagen que la app dibuja y le entrega a MapLibre: el mapa es una vista
/// nativa y no puede llevar widgets adentro.
abstract interface class MapImage {
  /// Nombre de la imagen en el estilo: dos imágenes iguales comparten una.
  String get key;

  /// La imagen en PNG, a la densidad de la pantalla.
  Future<Uint8List> toPng(double devicePixelRatio);
}

/// Ícono de un marcador. La app lo dibuja una vez y se lo entrega a MapLibre
/// como imagen: el mapa es una vista nativa y no puede llevar widgets adentro.
///
/// Reproduce los marcadores que antes eran widgets de Flutter: un círculo de
/// color con borde, sombra y un ícono de Material al centro, o un ícono solo.
/// [tapTarget] agranda la imagen con borde transparente: MapLibre detecta el
/// toque sobre la imagen entera, así que el área táctil sigue midiendo lo que
/// medía el widget aunque el dibujo sea más chico.
@immutable
class MarkerIcon implements MapImage {
  const MarkerIcon.circle({
    required double this.diameter,
    required this.color,
    required Color this.borderColor,
    required this.borderWidth,
    this.glyph,
    this.glyphColor,
    this.glyphSize = 0,
    this.shadow,
    this.tapTarget = 0,
  }) : glyphShadows = const [];

  const MarkerIcon.glyph({
    required IconData this.glyph,
    required this.glyphSize,
    required this.color,
    this.glyphShadows = const [],
    this.tapTarget = 0,
  }) : diameter = null,
       borderColor = null,
       borderWidth = 0,
       glyphColor = null,
       shadow = null;

  /// Del círculo; `null` en un ícono solo.
  final double? diameter;
  final Color color;
  final Color? borderColor;
  final double borderWidth;
  final IconData? glyph;
  final Color? glyphColor;
  final double glyphSize;
  final BoxShadow? shadow;
  final List<Shadow> glyphShadows;
  final double tapTarget;

  @override
  String get key => [
    diameter ?? 'g',
    color.toARGB32(),
    borderColor?.toARGB32(),
    borderWidth,
    glyph?.codePoint,
    glyphColor?.toARGB32(),
    glyphSize,
    if (shadow case final s?) ...[
      s.color.toARGB32(),
      s.blurRadius,
      s.offset.dx,
      s.offset.dy,
    ],
    for (final s in glyphShadows) ...[s.color.toARGB32(), s.blurRadius],
    tapTarget,
  ].join('_');

  double get _contenido => diameter ?? glyphSize;

  double get _margenSombra {
    final s = shadow;
    if (s != null) {
      return s.blurRadius +
          s.spreadRadius +
          math.max(s.offset.dx.abs(), s.offset.dy.abs());
    }
    return glyphShadows.fold(0, (m, s) => math.max(m, s.blurRadius));
  }

  /// Lado de la imagen, en píxeles lógicos.
  double get extent =>
      math.max(tapTarget, _contenido + 2 * _margenSombra).ceilToDouble();

  @override
  Future<Uint8List> toPng(double devicePixelRatio) async {
    final lado = extent;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..scale(devicePixelRatio);
    pintar(canvas, Offset(lado / 2, lado / 2));
    final pixeles = lado * devicePixelRatio;
    return _aPng(recorder.endRecording(), pixeles, pixeles);
  }

  /// Dibuja el marcador con su centro en [centro].
  void pintar(Canvas canvas, Offset centro) {
    if (diameter case final diametro?) {
      final radio = diametro / 2;
      if (shadow case final s?) {
        canvas.drawCircle(
          centro + s.offset,
          radio + s.spreadRadius,
          Paint()
            ..color = s.color
            ..maskFilter = MaskFilter.blur(
              BlurStyle.normal,
              Shadow.convertRadiusToSigma(s.blurRadius),
            ),
        );
      }
      canvas.drawCircle(centro, radio, Paint()..color = color);
      // Como `Border.all` sobre un círculo: el borde va por dentro.
      canvas.drawCircle(
        centro,
        radio - borderWidth / 2,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = borderWidth
          ..color = borderColor!,
      );
    }
    if (glyph case final g?) {
      final painter = TextPainter(
        textDirection: TextDirection.ltr,
        text: TextSpan(
          text: String.fromCharCode(g.codePoint),
          style: TextStyle(
            fontFamily: g.fontFamily,
            package: g.fontPackage,
            fontSize: glyphSize,
            height: 1,
            color: glyphColor ?? color,
            shadows: glyphShadows,
          ),
        ),
      )..layout();
      painter.paint(
        canvas,
        centro - Offset(painter.width / 2, painter.height / 2),
      );
      painter.dispose();
    }
  }
}

/// Un colectivo visto desde arriba, con la trompa hacia arriba de la imagen:
/// MapLibre lo gira con su rumbo (ver [MapVehicle]). Va sobre un disco con un
/// anillo del color de su capacidad; como es redondo, no cambia al girar.
@immutable
class CarIcon implements MapImage {
  const CarIcon({
    required this.bodyColor,
    required this.signColor,
    required this.ringColor,
    required this.borderColor,
    this.diameter = 44,
    this.tapTarget = 0,
  });

  /// La carrocería y el letrero del techo.
  final Color bodyColor;
  final Color signColor;

  /// El anillo y el tinte del disco: la capacidad que informa el chofer.
  final Color ringColor;

  /// El fondo del disco y el filete que lo separa del mapa.
  final Color borderColor;

  /// Del disco; el auto mide lo que cabe adentro.
  final double diameter;
  final double tapTarget;

  @override
  String get key => [
    'auto',
    bodyColor.toARGB32(),
    signColor.toARGB32(),
    ringColor.toARGB32(),
    borderColor.toARGB32(),
    diameter,
    tapTarget,
  ].join('_');

  /// Lado de la imagen, en píxeles lógicos. Es cuadrada y lleva el auto al
  /// centro, para que gire sobre sí mismo.
  double get extent => math.max(tapTarget, diameter + 2).ceilToDouble();

  @override
  Future<Uint8List> toPng(double devicePixelRatio) {
    final lado = extent;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..scale(devicePixelRatio);
    _pintar(canvas, Offset(lado / 2, lado / 2));
    final pixeles = lado * devicePixelRatio;
    return _aPng(recorder.endRecording(), pixeles, pixeles);
  }

  void _pintar(Canvas canvas, Offset c) {
    final radio = diameter / 2;
    // Las medidas del auto son las de un disco de 44 px.
    final u = diameter / 44;

    // El disco: un fondo que despega al auto de lo que haya debajo (calles,
    // la foto del satélite), teñido con el color de la capacidad, y su anillo.
    canvas
      ..drawCircle(c, radio, Paint()..color = borderColor)
      ..drawCircle(
        c,
        radio - 1.2,
        Paint()..color = Color.lerp(borderColor, ringColor, 0.22)!,
      )
      ..drawCircle(
        c,
        radio - 1.2 - 1.5 * u,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3 * u
          ..color = ringColor,
      );

    final ancho = 17 * u;
    final largo = 34 * u;
    final frente = c.dy - largo / 2;
    final cola = c.dy + largo / 2;
    final izquierda = c.dx - ancho / 2;
    final derecha = c.dx + ancho / 2;
    RRect caja(
      double left,
      double top,
      double right,
      double bottom,
      double radio,
    ) => RRect.fromRectAndRadius(
      Rect.fromLTRB(left, top, right, bottom),
      Radius.circular(radio),
    );

    // La carrocería: más redonda en la trompa que en la cola.
    final cuerpo = RRect.fromRectAndCorners(
      Rect.fromLTRB(izquierda, frente, derecha, cola),
      topLeft: Radius.elliptical(6.5 * u, 8 * u),
      topRight: Radius.elliptical(6.5 * u, 8 * u),
      bottomLeft: Radius.elliptical(5.5 * u, 5 * u),
      bottomRight: Radius.elliptical(5.5 * u, 5 * u),
    );
    // Los espejos, a la altura del parabrisas.
    final espejos = [
      caja(
        izquierda - 1.7 * u,
        frente + 9.4 * u,
        izquierda + u,
        frente + 11.8 * u,
        u,
      ),
      caja(
        derecha - u,
        frente + 9.4 * u,
        derecha + 1.7 * u,
        frente + 11.8 * u,
        u,
      ),
    ];
    // Un filete claro alrededor de todo, para que el auto negro se lea sobre
    // el mapa oscuro y sobre su propio disco.
    final filete = Paint()..color = const Color(0xFFFFFFFF);
    final carroceria = Paint()..color = bodyColor;
    canvas.drawRRect(
      cuerpo.inflate(0.6),
      Paint()
        ..color = const Color(0x80000000)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 1.8 * u),
    );
    for (final espejo in espejos) {
      canvas.drawRRect(espejo.inflate(1), filete);
    }
    canvas.drawRRect(cuerpo.inflate(1), filete);
    for (final espejo in espejos) {
      canvas.drawRRect(espejo, carroceria);
    }
    canvas.drawRRect(cuerpo, carroceria);

    // Los vidrios: una cabina más clara y, encima, el techo; lo que asoma por
    // delante es el parabrisas y por detrás, la luneta, más angosta.
    canvas
      ..drawRRect(
        caja(
          izquierda + 1.7 * u,
          frente + 8.4 * u,
          derecha - 1.7 * u,
          cola - 5.4 * u,
          3.2 * u,
        ),
        Paint()..color = Color.lerp(bodyColor, const Color(0xFFC4D4E3), 0.5)!,
      )
      ..drawRRect(
        caja(
          izquierda + 2.9 * u,
          frente + 14.2 * u,
          derecha - 2.9 * u,
          cola - 9 * u,
          2.2 * u,
        ),
        Paint()..color = Color.lerp(bodyColor, const Color(0xFFFFFFFF), 0.07)!,
      );

    // El letrero del techo, atravesado: lo que distingue a un colectivo.
    final letrero = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(c.dx, c.dy + 1.4 * u),
        width: 9.4 * u,
        height: 3.8 * u,
      ),
      Radius.circular(1.2 * u),
    );
    canvas
      ..drawRRect(letrero, Paint()..color = signColor)
      ..drawRRect(
        letrero.deflate(0.3),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.6
          ..color = const Color(0x99000000),
      );

    // Faros adelante y luces rojas atrás: dicen para dónde va aunque el auto
    // se vea chico.
    final faros = Paint()..color = const Color(0xFFFFF1B8);
    final luces = Paint()..color = const Color(0xFFE5484D);
    for (final lado in const [-1.0, 1.0]) {
      canvas
        ..drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
              center: Offset(c.dx + lado * 5 * u, frente + 2.3 * u),
              width: 3.6 * u,
              height: 1.8 * u,
            ),
            Radius.circular(0.9 * u),
          ),
          faros,
        )
        ..drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
              center: Offset(c.dx + lado * 5.2 * u, cola - 1.7 * u),
              width: 3.2 * u,
              height: 1.5 * u,
            ),
            Radius.circular(0.7 * u),
          ),
          luces,
        );
    }
  }
}

/// Un marcador de [MarkerIcon.circle] con una etiqueta chica debajo (el nombre
/// de un terminal: "Alto el Yugo"). El círculo sigue en el centro de la
/// imagen, que es el punto del mapa: la etiqueta no lo corre.
@immutable
class TaggedIcon implements MapImage {
  const TaggedIcon({
    required this.base,
    required this.tag,
    required this.tagColor,
    required this.tagTextColor,
  });

  final MarkerIcon base;
  final String tag;
  final Color tagColor;
  final Color tagTextColor;

  static const double _altoEtiqueta = 16;
  static const double _separacion = 2;

  @override
  String get key => [
    base.key,
    'etiqueta',
    tag,
    tagColor.toARGB32(),
    tagTextColor.toARGB32(),
  ].join('_');

  @override
  Future<Uint8List> toPng(double devicePixelRatio) {
    final texto = TextPainter(
      textDirection: TextDirection.ltr,
      text: TextSpan(
        text: tag,
        style: TextStyle(
          fontSize: 11,
          height: 1,
          fontWeight: FontWeight.w800,
          color: tagTextColor,
        ),
      ),
    )..layout();
    final anchoEtiqueta = texto.width + 10;
    final radio = (base.diameter ?? base.glyphSize) / 2;
    // Simétrica en alto: el círculo queda en el centro.
    final abajo = radio + _separacion + _altoEtiqueta + 2;
    final alto = 2 * math.max(abajo, base.extent / 2);
    final ancho = math.max(base.extent, anchoEtiqueta + 4);
    final centro = Offset(ancho / 2, alto / 2);

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..scale(devicePixelRatio);
    base.pintar(canvas, centro);
    final caja = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: centro.translate(0, radio + _separacion + _altoEtiqueta / 2),
        width: anchoEtiqueta,
        height: _altoEtiqueta,
      ),
      const Radius.circular(_altoEtiqueta / 2),
    );
    canvas
      ..drawRRect(caja, Paint()..color = tagColor)
      ..drawRRect(
        caja.deflate(0.5),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = const Color(0xFFFFFFFF),
      );
    texto
      ..paint(canvas, caja.center - Offset(texto.width / 2, texto.height / 2))
      ..dispose();
    return _aPng(
      recorder.endRecording(),
      ancho * devicePixelRatio,
      alto * devicePixelRatio,
    );
  }
}

/// Un punto de seña: una píldora del color de la línea con su [label] en
/// negrita y [detail] más chico ("10 T · Hacia el centro"), y abajo una punta
/// que termina en un punto blanco, justo en el centro de la imagen: ahí, en el
/// mapa, se le hace la seña al colectivo.
@immutable
class HailBadge implements MapImage {
  const HailBadge({
    required this.label,
    required this.detail,
    required this.color,
    required this.textColor,
  });

  final String label;
  final String detail;
  final Color color;
  final Color textColor;

  static const double _alto = 26;
  static const double _punta = 7;
  static const double _sombra = 3;

  @override
  String get key =>
      ['sena', label, detail, color.toARGB32(), textColor.toARGB32()].join('_');

  @override
  Future<Uint8List> toPng(double devicePixelRatio) {
    TextPainter pintor(String texto, double tamano, FontWeight peso) =>
        TextPainter(
          textDirection: TextDirection.ltr,
          text: TextSpan(
            text: texto,
            style: TextStyle(
              fontSize: tamano,
              height: 1,
              fontWeight: peso,
              color: textColor,
            ),
          ),
        )..layout();
    final rotulo = pintor(label, 14, FontWeight.w800);
    final detalle = detail.isEmpty ? null : pintor(detail, 12, FontWeight.w600);
    final anchoPildora =
        10 + rotulo.width + (detalle == null ? 0 : 6 + detalle.width) + 10;
    // La píldora y la punta van en la mitad de arriba; la de abajo, vacía,
    // deja la punta en el centro.
    final mitad = _sombra + _alto + _punta;
    final ancho = anchoPildora + 2 * _sombra;
    final alto = 2 * mitad;
    final centro = Offset(ancho / 2, mitad);

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..scale(devicePixelRatio);
    final caja = RRect.fromRectAndRadius(
      Rect.fromLTWH(_sombra, _sombra, anchoPildora, _alto),
      const Radius.circular(_alto / 2),
    );
    final punta = ui.Path()
      ..moveTo(centro.dx - 6, _sombra + _alto - 1)
      ..lineTo(centro.dx + 6, _sombra + _alto - 1)
      ..lineTo(centro.dx, centro.dy - 3)
      ..close();
    final sombra = Paint()
      ..color = const Color(0x59000000)
      ..maskFilter = MaskFilter.blur(
        BlurStyle.normal,
        Shadow.convertRadiusToSigma(_sombra - 1),
      );
    final relleno = Paint()..color = color;
    canvas
      ..drawRRect(caja.shift(const Offset(0, 1)), sombra)
      ..drawRRect(caja, relleno)
      ..drawPath(punta, relleno)
      ..drawRRect(
        caja.deflate(0.75),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = const Color(0xFFFFFFFF),
      )
      ..drawCircle(centro, 4.5, Paint()..color = const Color(0xFFFFFFFF))
      ..drawCircle(centro, 3, relleno);
    var x = _sombra + 10;
    final medio = _sombra + _alto / 2;
    rotulo.paint(canvas, Offset(x, medio - rotulo.height / 2));
    x += rotulo.width + 6;
    detalle?.paint(canvas, Offset(x, medio - detalle.height / 2));
    rotulo.dispose();
    detalle?.dispose();
    return _aPng(
      recorder.endRecording(),
      ancho * devicePixelRatio,
      alto * devicePixelRatio,
    );
  }
}

/// Pasa a PNG un dibujo de [ancho] por [alto] píxeles físicos.
Future<Uint8List> _aPng(ui.Picture picture, double ancho, double alto) async {
  final image = await picture.toImage(ancho.ceil(), alto.ceil());
  picture.dispose();
  try {
    final datos = await image.toByteData(format: ui.ImageByteFormat.png);
    return datos!.buffer.asUint8List();
  } finally {
    image.dispose();
  }
}

/// Insignia de una línea de colectivos: su rótulo corto sobre su color. Se
/// repite a lo largo del trazado, como el escudo de una carretera.
@immutable
class LineBadge implements MapImage {
  const LineBadge({
    required this.text,
    required this.color,
    required this.textColor,
    required this.borderColor,
  });

  final String text;
  final Color color;
  final Color textColor;
  final Color borderColor;

  static const double _alto = 22;
  static const double _relleno = 6;
  static const double _borde = 1.5;
  static const double _sombra = 3;

  @override
  String get key => [
    'insignia',
    text,
    color.toARGB32(),
    textColor.toARGB32(),
    borderColor.toARGB32(),
  ].join('_');

  @override
  Future<Uint8List> toPng(double devicePixelRatio) {
    final texto = TextPainter(
      textDirection: TextDirection.ltr,
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: 13,
          height: 1,
          fontWeight: FontWeight.w800,
          color: textColor,
        ),
      ),
    )..layout();
    final ancho = math.max(_alto, texto.width + 2 * _relleno);
    final caja = RRect.fromRectAndRadius(
      Rect.fromLTWH(_sombra, _sombra, ancho, _alto),
      const Radius.circular(6),
    );
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..scale(devicePixelRatio);
    canvas
      ..drawRRect(
        caja.shift(const Offset(0, 1)),
        Paint()
          ..color = const Color(0x59000000)
          ..maskFilter = MaskFilter.blur(
            BlurStyle.normal,
            Shadow.convertRadiusToSigma(_sombra - 1),
          ),
      )
      ..drawRRect(caja, Paint()..color = color)
      ..drawRRect(
        caja.deflate(_borde / 2),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = _borde
          ..color = borderColor,
      );
    texto
      ..paint(canvas, caja.center - Offset(texto.width / 2, texto.height / 2))
      ..dispose();
    return _aPng(
      recorder.endRecording(),
      (ancho + 2 * _sombra) * devicePixelRatio,
      (_alto + 2 * _sombra) * devicePixelRatio,
    );
  }
}

/// Flecha que muestra hacia dónde va una línea. Apunta a la derecha, que en
/// una imagen colocada sobre una línea es hacia adelante: MapLibre la gira con
/// cada tramo. Una punta blanca rellena, con un contorno oscuro, para que se
/// vea sobre cualquier color de línea y sobre el mapa claro u oscuro. Es del
/// ancho de un carril ([MapLine.laneWidth]): no pisa al del sentido contrario.
class _Galon implements MapImage {
  const _Galon();

  static const double _lado = 12;

  @override
  String get key => 'flecha_carril';

  @override
  Future<Uint8List> toPng(double devicePixelRatio) {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..scale(devicePixelRatio);
    final punta = ui.Path()
      ..moveTo(4.3, 3.7)
      ..lineTo(8.1, 6)
      ..lineTo(4.3, 8.3)
      ..close();
    // El trazo redondea las esquinas de la punta.
    Paint trazo(Color color, double ancho) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = ancho
      ..strokeJoin = StrokeJoin.round
      ..color = color;
    canvas
      ..drawPath(punta, trazo(const Color(0x52000000), 2.2))
      ..drawPath(punta, trazo(const Color(0xFFFFFFFF), 0.9))
      ..drawPath(punta, Paint()..color = const Color(0xFFFFFFFF));
    final pixeles = _lado * devicePixelRatio;
    return _aPng(recorder.endRecording(), pixeles, pixeles);
  }
}

/// Un marcador. El orden de la lista es el orden de dibujo: los últimos van
/// encima.
@immutable
class MapMarker {
  const MapMarker({
    required this.id,
    required this.point,
    required this.icon,
    this.opacity = 1,
    this.collides = false,
    this.onTap,
    this.semanticLabel,
  });

  final String id;
  final LatLng point;
  final MapImage icon;
  final double opacity;

  /// Si otro marcador con [collides] ya ocupa su lugar, MapLibre lo esconde
  /// hasta que haya espacio (al acercar el mapa). Los que no, se ven siempre,
  /// encima de éstos.
  final bool collides;
  final VoidCallback? onTap;

  /// Lo que lee el lector de pantalla (ver `_AppMapState._semanticas`).
  final String? semanticLabel;
}

/// Un colectivo en el mapa: un auto visto desde arriba que apunta hacia donde
/// va y, cuando llega una posición nueva, se desliza hasta ella en vez de
/// saltar. Los vehículos van encima de los marcadores.
@immutable
class MapVehicle {
  const MapVehicle({
    required this.id,
    required this.point,
    required this.icon,
    this.heading = 0,
    this.tag,
    this.opacity = 1,
    this.onTap,
    this.semanticLabel,
  });

  final String id;
  final LatLng point;
  final CarIcon icon;

  /// Hacia dónde apunta, en grados desde el norte (en sentido horario).
  final double heading;

  /// Etiqueta debajo del auto (su línea: "10 T"). No gira con él.
  final LineBadge? tag;
  final double opacity;
  final VoidCallback? onTap;

  /// Lo que lee el lector de pantalla (ver `_AppMapState._semanticas`).
  final String? semanticLabel;
}

/// Una línea con borde (el trazado de un recorrido, la ruta a pie).
@immutable
class MapLine {
  const MapLine({
    required this.points,
    required this.color,
    required this.width,
    this.borderColor = const Color(0x00000000),
    this.borderWidth = 0,
    this.dotted = false,
    this.lane = false,
    this.shadow = false,
    this.badge,
    this.badgeOpacity = 1,
    this.arrows = false,
    this.onTap,
  });

  /// Ancho y borde de una línea que va por su carril ([lane]).
  static const double laneWidth = 5;
  static const double laneBorder = 1;

  /// Cuánto se corre un carril del eje de su calle: la mitad de lo que mide
  /// con sus bordes. Sus flechas se corren lo mismo.
  static const double laneOffset = laneWidth / 2 + laneBorder;

  final List<LatLng> points;
  final Color color;

  /// En el zoom de calle (z15). Más lejos el mapa la dibuja más angosta y más
  /// cerca más ancha, con su borde, para que siempre ocupe parecido de la
  /// calle por la que va.
  final double width;
  final Color borderColor;

  /// Cuánto sobresale el borde a cada lado, como en flutter_map.
  final double borderWidth;

  /// Punteada: para lo que se recorre a pie, distinto de la línea continua
  /// de los colectivos. Cada punto es un círculo de [width] con su borde.
  final bool dotted;

  /// Por su carril: corrida a la derecha de su sentido (el orden de [points])
  /// la mitad de su ancho, como un auto por su pista. Con la del sentido
  /// contrario por la misma calle quedan lado a lado en vez de taparse. Tiene
  /// que medir [laneWidth] con un borde de [laneBorder].
  final bool lane;

  /// Con una sombra suave debajo, que la despega del mapa.
  final bool shadow;

  /// Insignia repetida a lo largo de la línea, por encima de los nombres de
  /// calles. Si dos se topan, MapLibre muestra sólo una.
  final LineBadge? badge;
  final double badgeOpacity;

  /// Flechas chicas a lo largo de la línea, en el orden de [points]: hacia
  /// dónde va el colectivo. Quietas: sólo en la línea elegida, no en todas.
  final bool arrows;

  /// Al tocar la línea o su insignia.
  final VoidCallback? onTap;

  /// El punto con que se dibuja una línea [dotted].
  MarkerIcon get dotIcon => MarkerIcon.circle(
    diameter: width + 2 * borderWidth,
    color: color,
    borderColor: borderColor,
    borderWidth: borderWidth,
  );
}

/// Un círculo medido en metros (el halo de precisión del GPS).
@immutable
class MapCircle {
  const MapCircle({
    required this.center,
    required this.radiusMeters,
    required this.color,
    required this.borderColor,
    required this.borderWidth,
  });

  final LatLng center;
  final double radiusMeters;
  final Color color;
  final Color borderColor;
  final double borderWidth;
}

/// El pulso tipo radar del paradero elegido.
@immutable
class MapPulse {
  const MapPulse({
    required this.point,
    required this.color,
    required this.fromRadius,
    required this.toRadius,
  });

  final LatLng point;
  final Color color;
  final double fromRadius;
  final double toRadius;
}

/// Cómo sigue la cámara a la flecha de navegación ([MapNavigation]).
enum MapFollow {
  /// La cámara queda donde el usuario la deje.
  none,

  /// Sigue la posición, plana y con el norte arriba.
  position,

  /// Navegación, como en Google Maps: sigue la posición y el rumbo, inclinada,
  /// con la flecha en la parte de abajo de la pantalla.
  navigation,
}

/// Un arreglo del GPS para la flecha de navegación.
@immutable
class MapUserFix {
  const MapUserFix({
    required this.point,
    required this.time,
    this.heading,
    this.speed,
    this.accuracy,
  });

  final LatLng point;
  final DateTime time;

  /// Hacia dónde apunta la flecha, en grados desde el norte.
  final double? heading;

  /// En m/s.
  final double? speed;

  /// En metros.
  final double? accuracy;

  @override
  bool operator ==(Object other) =>
      other is MapUserFix &&
      other.point == point &&
      other.time == time &&
      other.heading == heading &&
      other.speed == speed &&
      other.accuracy == accuracy;

  @override
  int get hashCode => Object.hash(point, time, heading, speed, accuracy);
}

/// La flecha de navegación del chofer y la cámara que la sigue.
///
/// La flecha es la de MapLibre (su "location component"), alimentada con las
/// posiciones de la app en vez de con su propio GPS: MapLibre la desliza entre
/// un arreglo y otro, y su cámara la sigue sin saltos.
@immutable
class MapNavigation {
  const MapNavigation({
    this.fix,
    this.follow = MapFollow.none,
    this.zoom = 16,
    this.tilt = 50,
    this.insets = EdgeInsets.zero,
  });

  /// La última posición; `null` mientras no hay ninguna (no se dibuja flecha).
  final MapUserFix? fix;
  final MapFollow follow;

  /// Zoom mientras sigue a la flecha.
  final double zoom;

  /// Inclinación en [MapFollow.navigation], en grados (hasta 60).
  final double tilt;

  /// Margen de la cámara en [MapFollow.navigation]: con margen arriba, la
  /// flecha queda más abajo en la pantalla y se ve más camino por delante.
  final EdgeInsets insets;
}

// ---------------------------------------------------------------------------
// Controlador
// ---------------------------------------------------------------------------

/// Mueve la cámara del [AppMap] al que se le pasa.
class AppMapController {
  ml.MapLibreMapController? _map;

  bool get isReady => _map != null;

  /// Sin animación: para seguir al usuario con cada punto del GPS.
  Future<void> moveTo(LatLng point, {double? zoom}) async {
    final map = _map;
    if (map == null) return;
    await map.moveCamera(_actualizacion(point, zoom));
  }

  Future<void> animateTo(
    LatLng point, {
    double? zoom,
    Duration duration = const Duration(milliseconds: 500),
  }) async {
    final map = _map;
    if (map == null) return;
    await map.animateCamera(_actualizacion(point, zoom), duration: duration);
  }

  /// Deja el norte arriba; sin [animate], de golpe.
  Future<void> resetBearing({bool animate = true}) async {
    final map = _map;
    if (map == null) return;
    if (animate) {
      await map.animateCamera(
        ml.CameraUpdate.bearingTo(0),
        duration: const Duration(milliseconds: 500),
      );
    } else {
      await map.moveCamera(ml.CameraUpdate.bearingTo(0));
    }
  }

  /// Plana y con el norte arriba: para mostrar una zona entera después de
  /// navegar con la cámara inclinada.
  Future<void> animateToOverview(
    LatLng point, {
    required double zoom,
    Duration duration = const Duration(milliseconds: 700),
  }) async {
    final map = _map;
    if (map == null) return;
    await map.animateCamera(
      ml.CameraUpdate.newCameraPosition(
        ml.CameraPosition(target: _ml(point), zoom: zoom),
      ),
      duration: duration,
    );
  }

  static ml.CameraUpdate _actualizacion(LatLng point, double? zoom) =>
      zoom == null
      ? ml.CameraUpdate.newLatLng(_ml(point))
      : ml.CameraUpdate.newLatLngZoom(_ml(point), zoom);
}

ml.LatLng _ml(LatLng p) => ml.LatLng(p.latitude, p.longitude);

/// El rumbo a una fracción [t] del giro de [desde] a [hasta], en grados, por
/// el lado corto: de 350° a 10° pasa por el norte, no da la vuelta entera.
@visibleForTesting
double girarHacia(double desde, double hasta, double t) {
  final diferencia = (hasta - desde + 540) % 360 - 180;
  return (desde + diferencia * t + 360) % 360;
}

/// Por dónde va dibujado un vehículo: el camino entre donde estaba dibujado
/// al llegar su posición nueva y esa posición.
class _Deslizamiento {
  const _Deslizamiento({
    required this.desde,
    required this.hasta,
    required this.rumboDesde,
    required this.rumboHasta,
    required this.inicio,
    required this.duracion,
  });

  /// Ya en su lugar: un vehículo recién aparecido, o uno que no se anima.
  const _Deslizamiento.quieto(LatLng punto, double rumbo, this.inicio)
    : desde = punto,
      hasta = punto,
      rumboDesde = rumbo,
      rumboHasta = rumbo,
      duracion = Duration.zero;

  /// Lo que tarda en girar: un auto dobla en la esquina, no a lo largo de
  /// toda la cuadra.
  static const giro = Duration(milliseconds: 600);

  final LatLng desde;
  final LatLng hasta;
  final double rumboDesde;
  final double rumboHasta;

  /// Cuándo llegó la posición [hasta].
  final DateTime inicio;
  final Duration duracion;

  bool terminado(DateTime ahora) => ahora.difference(inicio) >= duracion;

  /// Dónde va y hacia dónde apunta en el momento [ahora].
  (LatLng, double) en(DateTime ahora) {
    if (terminado(ahora)) return (hasta, rumboHasta);
    final pasado = ahora.difference(inicio).inMicroseconds;
    // A velocidad pareja: entre una posición y la siguiente el auto no frena.
    final t = (pasado / duracion.inMicroseconds).clamp(0.0, 1.0);
    final g = (pasado / math.min(duracion.inMicroseconds, giro.inMicroseconds))
        .clamp(0.0, 1.0);
    return (
      LatLng(
        desde.latitude + (hasta.latitude - desde.latitude) * t,
        desde.longitude + (hasta.longitude - desde.longitude) * t,
      ),
      girarHacia(rumboDesde, rumboHasta, Curves.easeOut.transform(g)),
    );
  }
}

/// Radio en píxeles, en el zoom 0, de un círculo de [meters] metros en la
/// [latitude] dada. En MapLibre el mundo mide 512 px en el zoom 0 y el doble
/// en cada nivel siguiente; Mercator estira las distancias por 1/cos(lat).
@visibleForTesting
double circleRadiusAtZoom0(double meters, double latitude) =>
    meters * 512 / (40075016.686 * math.cos(latitude * math.pi / 180));

// ---------------------------------------------------------------------------
// El mapa
// ---------------------------------------------------------------------------

/// Mapa común a las pantallas de la app (pasajero, flota y editor de
/// paraderos), dibujado por MapLibre con la GPU.
///
/// El mapa base sale de los archivos offline ([BasemapService]); la vista
/// satelital es la única que necesita conexión. Encima, la app dibuja lo suyo
/// con capas propias: [lines], [circles], [markers] y [vehicles], en ese
/// orden. Cambiar cualquiera de esas listas sólo actualiza sus datos, sin
/// volver a dibujar el mapa base.
class AppMap extends StatefulWidget {
  const AppMap({
    super.key,
    this.controller,
    required this.initialCenter,
    this.initialZoom = kInitialZoom,
    this.style = MapStyle.normal,
    this.markers = const [],
    this.vehicles = const [],
    this.animateVehicles = true,
    this.lines = const [],
    this.circles = const [],
    this.pulse,
    this.navigation,
    this.rotateGesturesEnabled = true,
    this.attributionAlignment = Alignment.bottomLeft,
    this.onMapReady,
    this.onUserGesture,
    this.onLongPress,
    this.onBearingChanged,
    this.onCameraIdle,
  });

  final AppMapController? controller;
  final LatLng initialCenter;
  final double initialZoom;
  final MapStyle style;
  final List<MapMarker> markers;

  /// Los colectivos: autos que giran con su rumbo, encima de los marcadores.
  final List<MapVehicle> vehicles;

  /// Si los [vehicles] se deslizan de una posición a la siguiente. Sin esto
  /// saltan: para la preferencia "Animaciones" y para un mapa que no se está
  /// viendo (otra pestaña), donde deslizarlos sería trabajo perdido.
  final bool animateVehicles;
  final List<MapLine> lines;
  final List<MapCircle> circles;
  final MapPulse? pulse;

  /// La flecha de navegación y cómo la sigue la cámara (pantalla de turno).
  /// Tiene que estar desde que se crea el mapa: MapLibre arma su flecha al
  /// crearse.
  final MapNavigation? navigation;
  final bool rotateGesturesEnabled;
  final Alignment attributionAlignment;

  /// Cuando ya se puede mover la cámara.
  final VoidCallback? onMapReady;

  /// El usuario arrastró o pellizcó el mapa (para dejar de seguirlo). Con
  /// [navigation], también cuando un gesto le quitó la cámara a la flecha.
  final VoidCallback? onUserGesture;

  final ValueChanged<LatLng>? onLongPress;

  /// Hacia dónde mira el mapa, en grados desde el norte (en sentido horario),
  /// mientras se rota: para la brújula del pasajero.
  final ValueChanged<double>? onBearingChanged;

  /// El centro del mapa cada vez que la cámara se detiene: el pasajero lo usa
  /// como foco de los puntos de seña cuando se aleja de su posición.
  final ValueChanged<LatLng>? onCameraIdle;

  /// MapLibre funciona en Android, iOS y la web; en el escritorio y en los
  /// tests de widgets el mapa queda sólo con su fondo.
  static bool get supported => kIsWeb || Platform.isAndroid || Platform.isIOS;

  @override
  State<AppMap> createState() => _AppMapState();
}

class _AppMapState extends State<AppMap> with TickerProviderStateMixin {
  static const _lineas = 'app_lineas';
  static const _insignias = 'app_insignias';
  static const _circulos = 'app_circulos';
  static const _pulso = 'app_pulso';
  static const _marcadores = 'app_marcadores';
  static const _ocultables = 'app_marcadores_ocultables';
  static const _vehiculos = 'app_vehiculos';
  static const _etiquetas = 'app_vehiculos_etiquetas';

  static const _galon = _Galon();

  /// Entre una flecha y la siguiente, en píxeles lógicos: las reparte
  /// MapLibre a lo largo de la línea, a esta distancia en cualquier zoom.
  static const double _espacioFlechas = 75;

  /// Entre una insignia de línea y la siguiente, en píxeles lógicos.
  static const double _espacioInsignias = 420;

  /// Cuánto baja la etiqueta de un vehículo desde su centro, en píxeles
  /// lógicos: justo debajo del disco del auto.
  static const double _bajoElAuto = 21;

  /// Entre un cuadro y el siguiente de los vehículos que se deslizan: veinte
  /// por segundo, porque cada uno es una llamada al mapa nativo.
  static const _cuadro = Duration(milliseconds: 50);

  /// Un vehículo que aparece a más de esto de donde estaba (volvió la señal
  /// después de un túnel) salta: deslizarlo lo haría cruzar manzanas.
  static const double _saltoMaximo = 300;

  /// Imágenes ya dibujadas, por ícono y densidad: se reusan entre mapas y al
  /// recargar el estilo.
  static final Map<String, Future<Uint8List>> _png = {};

  final BasemapService _basemap = BasemapService.instance;
  ml.MapLibreMapController? _map;

  /// El estilo pedido a MapLibre y si ya terminó de cargar con nuestras capas.
  String? _estilo;
  bool _estiloListo = false;

  /// La capa de nombres del estilo bajo la que van las líneas, el halo y el
  /// pulso, para que no tapen los nombres de calles y ciudades. Los
  /// marcadores van encima de todo.
  String? _debajoDe;

  /// Distancia entre los puntos de una línea punteada, en píxeles lógicos.
  /// Con los puntos de 8 px de la ruta a pie quedan 4 px entre uno y otro.
  static const double _espacioPuntos = 12;

  /// Imágenes agregadas al estilo actual (se pierden al cambiarlo).
  final Set<String> _imagenes = {};

  /// Sube con cada estilo cargado: un envío que empezó con el estilo anterior
  /// no anota nada como enviado al nuevo.
  int _generacion = 0;

  /// Lo último enviado a cada fuente, para no reenviar lo que no cambió.
  final Map<String, String> _enviado = {};
  bool _sincronizando = false;
  bool _pendiente = false;

  late final AnimationController _animacion;
  bool _pintandoPulso = false;

  /// Por dónde va dibujado cada vehículo, y el reloj que los mueve mientras
  /// alguno no llega a su lugar.
  final Map<String, _Deslizamiento> _deslizamientos = {};
  late final Ticker _reloj;
  Duration _ultimoCuadro = Duration.zero;
  bool _pintandoVehiculos = false;
  bool _vehiculosPendientes = false;

  /// Lo último que se le aplicó a la flecha de navegación y a su cámara.
  MapUserFix? _fixEnviado;
  MapFollow _seguimiento = MapFollow.none;
  double? _zoomSeguimiento;
  EdgeInsets? _margen;
  bool _navegando = false;
  bool _navegacionPendiente = false;

  /// Cuándo la app cambió el seguimiento por su cuenta: MapLibre avisa que se
  /// soltó el seguimiento también cuando lo suelta la app, y eso no es un
  /// gesto del usuario.
  DateTime _cambioPropio = DateTime.fromMillisecondsSinceEpoch(0);

  double _densidad = 1;
  bool _accesible = false;
  List<({String texto, VoidCallback alTocar, Offset punto})> _semanticas =
      const [];

  Offset? _inicioGesto;
  bool _gestoAvisado = false;

  /// Último rumbo avisado: los movimientos de cámara llegan en cada cuadro y
  /// la mayoría no cambia el rumbo.
  double _rumbo = 0;

  @override
  void initState() {
    super.initState();
    _animacion = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..addListener(_pintarPulso);
    _reloj = createTicker(_alAvanzar);
    _actualizarVehiculos();
    _basemap.addListener(_onBasemapChanged);
    if (!_basemap.isReady) unawaited(_basemap.load());
  }

  @override
  void dispose() {
    _basemap.removeListener(_onBasemapChanged);
    _animacion.dispose();
    _reloj.dispose();
    widget.controller?._map = null;
    final map = _map;
    if (map != null) map.onFeatureTapped.remove(_alTocar);
    super.dispose();
  }

  void _onBasemapChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(covariant AppMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?._map = null;
      widget.controller?._map = _map;
    }
    _actualizarVehiculos();
    _sincronizar();
    _animarVehiculos();
    _sincronizarNavegacion();
    _actualizarPulso();
    if (_accesible) unawaited(_actualizarSemanticas());
  }

  bool get _hayFlechas => widget.lines.any((l) => l.arrows);

  // --- MapLibre ------------------------------------------------------------

  void _alCrear(ml.MapLibreMapController map) {
    _map = map;
    widget.controller?._map = map;
    map.onFeatureTapped.add(_alTocar);
    widget.onMapReady?.call();
  }

  Future<void> _alCargarEstilo() async {
    final map = _map;
    if (map == null || !mounted) return;
    final estilo = _estilo;
    _generacion++;
    _imagenes.clear();
    _enviado.clear();
    // Con el estilo nuevo MapLibre rearma su flecha: se le vuelve a dar todo.
    _fixEnviado = null;
    _seguimiento = MapFollow.none;
    _zoomSeguimiento = null;
    _margen = null;
    try {
      await _agregarCapas(map, _debajoDe);
    } catch (e) {
      debugPrint('AppMap: no se pudieron agregar las capas: $e');
      return;
    }
    // Si mientras tanto se pidió otro estilo, su propia carga sigue.
    if (!mounted || estilo != _estilo) return;
    _estiloListo = true;
    _sincronizar();
    _sincronizarNavegacion();
    _actualizarPulso();
    if (_accesible) unawaited(_actualizarSemanticas());
  }

  /// [valor] tal cual en el zoom de calle (z15); más lejos se achica y más
  /// cerca se agranda. Así una línea ocupa siempre parecido de su calle, en
  /// vez de taparla de lejos y perderse en ella de cerca.
  static List<Object> _porZoom(Object valor) => [
    'interpolate',
    ['linear'],
    ['zoom'],
    11,
    ['*', 0.55, valor],
    15,
    valor,
    18,
    ['*', 1.5, valor],
  ];

  /// Capas de la app. Las líneas, sus flechas, el halo y el pulso van debajo
  /// de [debajoDe], la primera capa de nombres del mapa base; las insignias de
  /// las líneas, los marcadores y los vehículos, encima de todo.
  Future<void> _agregarCapas(
    ml.MapLibreMapController map,
    String? debajoDe,
  ) async {
    const vacio = {'type': 'FeatureCollection', 'features': <Object>[]};
    final ordenado = ['get', 'orden'];
    const continua = [
      '!',
      ['get', 'punteada'],
    ];
    const porSuCarril = [
      '==',
      ['get', 'carril'],
      true,
    ];
    const conBorde = [
      '+',
      ['get', 'ancho'],
      [
        '*',
        2,
        ['get', 'borde'],
      ],
    ];
    // Un carril va corrido a la derecha de su sentido la mitad de lo que mide:
    // con el del sentido contrario por la misma calle quedan lado a lado, como
    // las dos pistas de la calle.
    final corrida = _porZoom(const [
      'case',
      porSuCarril,
      ['/', conBorde, 2],
      0,
    ]);

    await map.addGeoJsonSource(_lineas, vacio);
    // La sombra: una línea negra desenfocada un poco más ancha, que despega
    // el recorrido del mapa.
    await map.addLineLayer(
      _lineas,
      '${_lineas}_sombra',
      ml.LineLayerProperties(
        lineColor: 'rgba(0, 0, 0, 0.32)',
        lineWidth: _porZoom(const ['+', conBorde, 3]),
        lineBlur: 4,
        lineOffset: corrida,
        lineTranslate: const [0, 1.5],
        lineJoin: 'round',
        lineCap: 'round',
        lineSortKey: ordenado,
      ),
      belowLayerId: debajoDe,
      filter: const [
        'all',
        continua,
        ['get', 'sombra'],
      ],
      enableInteraction: false,
    );
    await map.addLineLayer(
      _lineas,
      '${_lineas}_borde',
      ml.LineLayerProperties(
        lineColor: ['get', 'colorBorde'],
        lineWidth: _porZoom(conBorde),
        lineOffset: corrida,
        lineJoin: 'round',
        lineCap: 'round',
        lineSortKey: ordenado,
      ),
      belowLayerId: debajoDe,
      filter: continua,
      enableInteraction: false,
    );
    await map.addLineLayer(
      _lineas,
      _lineas,
      ml.LineLayerProperties(
        lineColor: ['get', 'color'],
        lineWidth: _porZoom(const ['get', 'ancho']),
        lineOffset: corrida,
        lineJoin: 'round',
        lineCap: 'round',
        lineSortKey: ordenado,
      ),
      belowLayerId: debajoDe,
      filter: continua,
      // Tocar una línea la elige (ver `MapLine.onTap`).
      enableInteraction: true,
    );
    // Las flechas, quietas, encima de las líneas y debajo de la ruta a pie:
    // son contexto, no la indicación que hay que seguir. Las reparte MapLibre
    // a lo largo de la línea y las gira con cada tramo.
    await map.addSymbolLayer(
      _lineas,
      '${_lineas}_flechas',
      ml.SymbolLayerProperties(
        iconImage: _galon.key,
        symbolPlacement: 'line',
        symbolSpacing: _espacioFlechas,
        iconRotationAlignment: 'map',
        iconAllowOverlap: true,
        iconIgnorePlacement: true,
        // Crecen con la línea.
        iconSize: _porZoom(1),
        // Hacia abajo de una flecha que apunta a la derecha es la derecha de
        // su sentido: el lado de su carril. MapLibre multiplica este corrimiento
        // por el tamaño del ícono, así que sigue al carril en cualquier zoom.
        iconOffset: const [
          'case',
          porSuCarril,
          [
            'literal',
            [0, MapLine.laneOffset],
          ],
          [
            'literal',
            [0, 0],
          ],
        ],
      ),
      belowLayerId: debajoDe,
      filter: ['get', 'flechas'],
      // Más lejos, en una línea de pocos píxeles, serían puro ruido.
      minzoom: 13,
      enableInteraction: false,
    );
    // Las punteadas, con un punto (imagen) cada [_espacioPuntos]: un guion de
    // largo cero con extremos redondos también da puntos, pero el borde
    // tendría que ser otra línea punteada, y sus puntos se desalinean
    // (comprobado el 2026-10-08 con MapLibre Native: el anillo blanco no
    // queda alrededor del punto).
    await map.addSymbolLayer(
      _lineas,
      '${_lineas}_puntos',
      const ml.SymbolLayerProperties(
        iconImage: ['get', 'icono'],
        symbolPlacement: 'line',
        symbolSpacing: _espacioPuntos,
        iconRotationAlignment: 'map',
        iconAllowOverlap: true,
        iconIgnorePlacement: true,
      ),
      belowLayerId: debajoDe,
      filter: ['get', 'punteada'],
      enableInteraction: false,
    );
    // Los nombres de calles van encima de las líneas, con un halo opaco para
    // que se lean. Sobre una línea continua el halo casi no se nota, pero
    // sobre la punteada borraba todos los puntos que quedaban bajo un nombre y
    // la ruta a pie parecía cortada. Esta copia invisible de los puntos va
    // encima de los nombres y sí cuenta para colocarlos: MapLibre ya no pone
    // un nombre donde taparía la ruta a pie, sino en otro tramo de la calle.
    await map.addSymbolLayer(
      _lineas,
      '${_lineas}_reserva',
      const ml.SymbolLayerProperties(
        iconImage: ['get', 'icono'],
        symbolPlacement: 'line',
        symbolSpacing: _espacioPuntos,
        iconRotationAlignment: 'map',
        iconAllowOverlap: true,
        iconIgnorePlacement: false,
        iconOpacity: 0,
      ),
      filter: ['get', 'punteada'],
      enableInteraction: false,
    );
    // Las insignias de las líneas, encima de los nombres de calles: donde va
    // una, MapLibre no pone un nombre. Entre ellas tampoco se tapan; si dos se
    // topan, gana la de la línea elegida (la última de la lista).
    await map.addSymbolLayer(
      _lineas,
      _insignias,
      ml.SymbolLayerProperties(
        iconImage: ['get', 'insignia'],
        iconOpacity: ['get', 'opacidadInsignia'],
        symbolPlacement: 'line',
        symbolSpacing: _espacioInsignias,
        iconRotationAlignment: 'viewport',
        iconPadding: 6,
        symbolSortKey: ['-', ordenado],
      ),
      filter: ['has', 'insignia'],
      minzoom: 11,
      enableInteraction: true,
    );

    await map.addGeoJsonSource(_circulos, vacio);
    await map.addCircleLayer(
      _circulos,
      _circulos,
      ml.CircleLayerProperties(
        // Metros a píxeles: en MapLibre el mundo mide 512·2^zoom píxeles, así
        // que el radio en píxeles se duplica con cada nivel de zoom.
        // `r0` es el radio en el zoom 0 (ver `_circulosGeoJson`).
        circleRadius: [
          'interpolate',
          ['exponential', 2],
          ['zoom'],
          0,
          ['get', 'r0'],
          24,
          [
            '*',
            ['get', 'r0'],
            16777216,
          ],
        ],
        circleColor: ['get', 'color'],
        circleStrokeColor: ['get', 'colorBorde'],
        circleStrokeWidth: ['get', 'borde'],
        circlePitchAlignment: 'map',
      ),
      belowLayerId: debajoDe,
      enableInteraction: false,
    );

    await map.addGeoJsonSource(_pulso, vacio);
    await map.addCircleLayer(
      _pulso,
      _pulso,
      _propiedadesPulso(0, 0, const Color(0x00000000)),
      belowLayerId: debajoDe,
      enableInteraction: false,
    );

    // Los que se esconden si se tapan, debajo de los que se ven siempre. Sí
    // les quitan el lugar a los nombres de calles.
    await map.addGeoJsonSource(_ocultables, vacio);
    await map.addSymbolLayer(
      _ocultables,
      _ocultables,
      ml.SymbolLayerProperties(
        iconImage: ['get', 'icono'],
        iconOpacity: ['get', 'opacidad'],
        symbolSortKey: ordenado,
      ),
    );

    await map.addGeoJsonSource(_marcadores, vacio);
    await map.addSymbolLayer(
      _marcadores,
      _marcadores,
      ml.SymbolLayerProperties(
        iconImage: ['get', 'icono'],
        iconOpacity: ['get', 'opacidad'],
        iconAllowOverlap: true,
        iconIgnorePlacement: true,
        symbolSortKey: ordenado,
      ),
    );

    // Los vehículos, encima de los marcadores: lo que se mueve no queda
    // debajo de lo que está quieto. El auto gira con su rumbo y va acostado
    // sobre el mapa, también con la cámara inclinada del chofer; su etiqueta
    // es otra capa, que no gira.
    await map.addGeoJsonSource(_vehiculos, vacio);
    await map.addSymbolLayer(
      _vehiculos,
      _vehiculos,
      ml.SymbolLayerProperties(
        iconImage: ['get', 'icono'],
        iconOpacity: ['get', 'opacidad'],
        iconRotate: ['get', 'rumbo'],
        iconRotationAlignment: 'map',
        iconPitchAlignment: 'map',
        iconAllowOverlap: true,
        iconIgnorePlacement: true,
        symbolSortKey: ordenado,
      ),
    );
    await map.addSymbolLayer(
      _vehiculos,
      _etiquetas,
      ml.SymbolLayerProperties(
        iconImage: ['get', 'etiqueta'],
        iconOpacity: ['get', 'opacidad'],
        iconAnchor: 'top',
        iconOffset: const [0, _bajoElAuto],
        iconAllowOverlap: true,
        iconIgnorePlacement: true,
        symbolSortKey: ordenado,
      ),
      filter: ['has', 'etiqueta'],
    );
  }

  void _alTocar(
    math.Point<double> point,
    ml.LatLng coordinates,
    String id,
    String layerId,
    ml.Annotation? annotation,
  ) {
    if (layerId == _lineas || layerId == _insignias) {
      // El id es `linea_<posición en la lista>` (ver `_lineasGeoJson`).
      final lines = widget.lines;
      final i = int.tryParse(id.replaceFirst('linea_', ''));
      if (i != null && i >= 0 && i < lines.length) lines[i].onTap?.call();
      return;
    }
    if (layerId == _vehiculos || layerId == _etiquetas) {
      for (final vehiculo in widget.vehicles) {
        if (vehiculo.id == id) {
          vehiculo.onTap?.call();
          return;
        }
      }
      return;
    }
    if (layerId != _marcadores && layerId != _ocultables) return;
    for (final marker in widget.markers) {
      if (marker.id == id) {
        marker.onTap?.call();
        return;
      }
    }
  }

  void _alMantenerPresionado(math.Point<double> point, ml.LatLng coordinates) {
    widget.onLongPress?.call(
      LatLng(coordinates.latitude, coordinates.longitude),
    );
  }

  void _alQuedarQuieta() {
    if (_accesible) unawaited(_actualizarSemanticas());
    if (_map?.cameraPosition?.target case final c?) {
      widget.onCameraIdle?.call(LatLng(c.latitude, c.longitude));
    }
    // El rumbo final, por si el último movimiento no lo trajo.
    final rumbo = _map?.cameraPosition?.bearing;
    if (rumbo != null) _avisarRumbo(rumbo);
  }

  void _alMoverCamara(ml.CameraPosition posicion) =>
      _avisarRumbo(posicion.bearing);

  void _avisarRumbo(double rumbo) {
    if ((rumbo - _rumbo).abs() < 0.1) return;
    _rumbo = rumbo;
    widget.onBearingChanged?.call(rumbo);
  }

  // --- Datos de la app -----------------------------------------------------

  /// Envía a MapLibre lo que cambió. Las llamadas al mapa son asíncronas: si
  /// llega otro cambio mientras tanto, se envía al terminar, con los datos
  /// más recientes.
  void _sincronizar() {
    if (!_estiloListo || _map == null) return;
    if (_sincronizando) {
      _pendiente = true;
      return;
    }
    _sincronizando = true;
    unawaited(() async {
      try {
        do {
          _pendiente = false;
          await _enviar(_map!);
        } while (_pendiente && mounted && _estiloListo && _map != null);
      } catch (e) {
        // El mapa se cerró o cambió de estilo a mitad del envío; la próxima
        // carga del estilo vuelve a enviar todo.
        debugPrint('AppMap: no se pudo actualizar el mapa: $e');
      } finally {
        _sincronizando = false;
      }
    }());
  }

  Future<void> _enviar(ml.MapLibreMapController map) async {
    final generacion = _generacion;
    bool vigente() => _estiloListo && generacion == _generacion;

    final markers = widget.markers;
    final iconos = <MapImage>[
      for (final marker in markers) marker.icon,
      for (final vehiculo in widget.vehicles) ...[vehiculo.icon, ?vehiculo.tag],
      for (final line in widget.lines) ...[
        if (line.dotted) line.dotIcon,
        ?line.badge,
      ],
      if (_hayFlechas) _galon,
    ];
    for (final icono in iconos) {
      if (_imagenes.contains(icono.key)) continue;
      final png = await _png.putIfAbsent(
        '${icono.key}@$_densidad',
        () => icono.toPng(_densidad),
      );
      if (!vigente()) return;
      await map.addImage(icono.key, png);
      if (!vigente()) return;
      _imagenes.add(icono.key);
    }

    final pulso = widget.pulse;
    final fuentes = {
      _lineas: _lineasGeoJson(widget.lines),
      _circulos: _circulosGeoJson(widget.circles),
      _marcadores: _marcadoresGeoJson([
        for (final m in markers)
          if (!m.collides) m,
      ]),
      _ocultables: _marcadoresGeoJson([
        for (final m in markers)
          if (m.collides) m,
      ]),
      _pulso: {
        'type': 'FeatureCollection',
        'features': [if (pulso != null) _punto('pulso', pulso.point, const {})],
      },
    };
    for (final MapEntry(key: id, value: datos) in fuentes.entries) {
      final texto = jsonEncode(datos);
      if (_enviado[id] == texto) continue;
      if (!vigente()) return;
      await map.setGeoJsonSource(id, datos);
      if (!vigente()) return;
      _enviado[id] = texto;
    }
    // Los vehículos van aparte, porque se mueven solos entre un cambio y
    // otro. Recién ahora están sus imágenes en el mapa.
    _pintarVehiculos();
    _animarVehiculos();
  }

  static Map<String, dynamic> _punto(
    String id,
    LatLng p,
    Map<String, dynamic> properties,
  ) => {
    'type': 'Feature',
    // En Android el id tiene que ir en la raíz: es lo que llega al tocar.
    'id': id,
    'properties': properties,
    'geometry': {
      'type': 'Point',
      'coordinates': [p.longitude, p.latitude],
    },
  };

  /// Un NaN haría fallar el JSON entero, y con él todo lo demás del mapa.
  static bool _finito(LatLng p) => p.latitude.isFinite && p.longitude.isFinite;

  static Map<String, dynamic> _lineasGeoJson(List<MapLine> lines) => {
    'type': 'FeatureCollection',
    'features': [
      for (final (i, line) in lines.indexed)
        if (line.points.where(_finito).length > 1)
          {
            'type': 'Feature',
            'id': 'linea_$i',
            'properties': {
              'color': _css(line.color),
              'colorBorde': _css(line.borderColor),
              'ancho': line.width,
              'borde': line.borderWidth,
              'orden': i,
              'punteada': line.dotted,
              'carril': line.lane,
              'sombra': line.shadow,
              'flechas': line.arrows,
              if (line.dotted) 'icono': line.dotIcon.key,
              if (line.badge case final badge?) ...{
                'insignia': badge.key,
                'opacidadInsignia': line.badgeOpacity,
              },
            },
            'geometry': {
              'type': 'LineString',
              'coordinates': [
                for (final p in line.points)
                  if (_finito(p)) [p.longitude, p.latitude],
              ],
            },
          },
    ],
  };

  static Map<String, dynamic> _circulosGeoJson(List<MapCircle> circles) => {
    'type': 'FeatureCollection',
    'features': [
      for (final (i, c) in circles.indexed)
        if (_finito(c.center))
          _punto('circulo_$i', c.center, {
            'r0': circleRadiusAtZoom0(c.radiusMeters, c.center.latitude),
            'color': _css(c.color),
            'colorBorde': _css(c.borderColor),
            'borde': c.borderWidth,
          }),
    ],
  };

  static Map<String, dynamic> _marcadoresGeoJson(List<MapMarker> markers) => {
    'type': 'FeatureCollection',
    'features': [
      for (final (i, m) in markers.indexed)
        if (_finito(m.point))
          _punto(m.id, m.point, {
            'icono': m.icon.key,
            'opacidad': m.opacity,
            'orden': i,
          }),
    ],
  };

  static String _css(Color c) =>
      'rgba(${(c.r * 255).round()}, ${(c.g * 255).round()}, '
      '${(c.b * 255).round()}, ${c.a.toStringAsFixed(3)})';

  // --- Vehículos -----------------------------------------------------------

  /// Anota hacia dónde tiene que ir cada vehículo. Uno nuevo aparece en su
  /// lugar; uno que ya estaba parte de donde va dibujado en este momento, y
  /// tarda en llegar lo que tardó en llegar su posición nueva: así se mueve
  /// sin detenerse entre una y otra.
  void _actualizarVehiculos() {
    final ahora = DateTime.now();
    final vigentes = <String>{};
    for (final vehiculo in widget.vehicles) {
      vigentes.add(vehiculo.id);
      final antes = _deslizamientos[vehiculo.id];
      if (antes != null &&
          antes.hasta == vehiculo.point &&
          antes.rumboHasta == vehiculo.heading) {
        continue;
      }
      final quieto = _Deslizamiento.quieto(
        vehiculo.point,
        vehiculo.heading,
        ahora,
      );
      if (antes == null || !widget.animateVehicles) {
        _deslizamientos[vehiculo.id] = quieto;
        continue;
      }
      final (desde, rumbo) = antes.en(ahora);
      final salto = metrosEntre(desde, vehiculo.point);
      if (!salto.isFinite || salto > _saltoMaximo) {
        _deslizamientos[vehiculo.id] = quieto;
        continue;
      }
      final espera = ahora.difference(antes.inicio).inMilliseconds;
      _deslizamientos[vehiculo.id] = _Deslizamiento(
        desde: desde,
        hasta: vehiculo.point,
        rumboDesde: rumbo,
        rumboHasta: vehiculo.heading,
        inicio: ahora,
        // Sin moverse sólo gira. Si no, entre 0,8 y 4 s: una posición que
        // demoró más (el auto estuvo detenido) no se alcanza a paso de tortuga.
        duracion: salto == 0
            ? _Deslizamiento.giro
            : Duration(milliseconds: espera.clamp(800, 4000)),
      );
    }
    _deslizamientos.removeWhere((id, _) => !vigentes.contains(id));
  }

  /// Echa a andar el reloj si algún vehículo todavía no llega a su lugar. Sólo
  /// con el mapa listo: en los tests y en el escritorio no hay a quién
  /// enviarle nada, y un reloj andando no los dejaría terminar.
  void _animarVehiculos() {
    if (_map == null || !_estiloListo || _reloj.isActive) return;
    final ahora = DateTime.now();
    if (_deslizamientos.values.every((d) => d.terminado(ahora))) return;
    _ultimoCuadro = Duration.zero;
    _reloj.start();
  }

  void _alAvanzar(Duration transcurrido) {
    if (transcurrido - _ultimoCuadro < _cuadro) return;
    _ultimoCuadro = transcurrido;
    // El último cuadro los deja a todos en su lugar exacto.
    final ahora = DateTime.now();
    if (_deslizamientos.values.every((d) => d.terminado(ahora))) _reloj.stop();
    _pintarVehiculos();
  }

  /// Envía al mapa dónde va cada vehículo en este momento. Si el envío
  /// anterior todavía no termina, queda uno pendiente con lo más reciente: no
  /// se acumulan llamadas.
  void _pintarVehiculos() {
    final map = _map;
    if (map == null || !_estiloListo) return;
    if (_pintandoVehiculos) {
      _vehiculosPendientes = true;
      return;
    }
    final vehiculos = widget.vehicles;
    // Sus imágenes las agrega `_enviar`, que al terminar vuelve a llamar acá.
    for (final v in vehiculos) {
      if (!_imagenes.contains(v.icon.key)) return;
      if (v.tag case final tag? when !_imagenes.contains(tag.key)) return;
    }
    final datos = _vehiculosGeoJson(vehiculos, DateTime.now());
    final texto = jsonEncode(datos);
    if (_enviado[_vehiculos] == texto) return;

    final generacion = _generacion;
    _pintandoVehiculos = true;
    map
        .setGeoJsonSource(_vehiculos, datos)
        .then((_) {
          if (generacion == _generacion) _enviado[_vehiculos] = texto;
        })
        .catchError((Object _) {})
        .whenComplete(() {
          _pintandoVehiculos = false;
          if (_vehiculosPendientes && mounted) {
            _vehiculosPendientes = false;
            _pintarVehiculos();
          }
        });
  }

  Map<String, dynamic> _vehiculosGeoJson(
    List<MapVehicle> vehiculos,
    DateTime ahora,
  ) => {
    'type': 'FeatureCollection',
    'features': [
      for (final (i, v) in vehiculos.indexed)
        if (_deslizamientos[v.id]?.en(ahora) case (
          final punto,
          final rumbo,
        ) when _finito(punto))
          _punto(v.id, punto, {
            'icono': v.icon.key,
            // Con un decimal: el mapa no distingue menos, y el texto que se
            // compara para no reenviar lo mismo queda más corto.
            'rumbo': (rumbo * 10).round() / 10,
            'opacidad': v.opacity,
            'orden': i,
            if (v.tag case final tag?) 'etiqueta': tag.key,
          }),
    ],
  };

  // --- Pulso ---------------------------------------------------------------

  void _actualizarPulso() {
    final animar = widget.pulse != null && _estiloListo;
    if (animar && !_animacion.isAnimating) {
      _animacion.repeat();
    } else if (!animar && _animacion.isAnimating) {
      _animacion
        ..stop()
        ..reset();
    }
  }

  /// Un cuadro del pulso. Si el anterior todavía no llega al mapa, se salta:
  /// así nunca se acumulan llamadas.
  void _pintarPulso() {
    final map = _map;
    final pulso = widget.pulse;
    if (map == null || pulso == null || !_estiloListo || _pintandoPulso) {
      return;
    }
    final t = _animacion.value;
    final radio =
        pulso.fromRadius +
        (pulso.toRadius - pulso.fromRadius) * Curves.easeOut.transform(t);
    final opacidad = 0.55 * (1 - Curves.easeIn.transform(t));
    _pintandoPulso = true;
    map
        .setLayerProperties(
          _pulso,
          _propiedadesPulso(radio, opacidad, pulso.color),
        )
        .catchError((Object _) {})
        .whenComplete(() => _pintandoPulso = false);
  }

  static ml.CircleLayerProperties _propiedadesPulso(
    double radio,
    double opacidad,
    Color color,
  ) => ml.CircleLayerProperties(
    circleRadius: radio,
    circleOpacity: opacidad,
    circleColor: _css(color.withValues(alpha: 1)),
    circlePitchAlignment: 'map',
  );

  // --- Navegación ----------------------------------------------------------

  /// Lleva la flecha y la cámara a lo que pide [AppMap.navigation]. Como las
  /// fuentes: si llega otro cambio mientras tanto, se aplica al terminar.
  void _sincronizarNavegacion() {
    if (!_estiloListo || _map == null || widget.navigation == null) return;
    if (_navegando) {
      _navegacionPendiente = true;
      return;
    }
    _navegando = true;
    unawaited(() async {
      try {
        do {
          _navegacionPendiente = false;
          await _aplicarNavegacion(_map!);
        } while (_navegacionPendiente && mounted && _estiloListo);
      } catch (e) {
        debugPrint('AppMap: no se pudo actualizar la navegación: $e');
      } finally {
        _navegando = false;
      }
    }());
  }

  Future<void> _aplicarNavegacion(ml.MapLibreMapController map) async {
    final nav = widget.navigation;
    if (nav == null) return;
    final generacion = _generacion;
    bool vigente() => mounted && _estiloListo && generacion == _generacion;

    // La posición primero: el seguimiento parte de ella.
    final fix = nav.fix;
    if (fix != null && fix != _fixEnviado) {
      await map.updateManualLocation(
        ml.ManualLocationUpdate(
          target: _ml(fix.point),
          bearing: fix.heading,
          speed: fix.speed,
          horizontalAccuracy: fix.accuracy,
          timestamp: fix.time,
        ),
      );
      if (!vigente()) return;
      _fixEnviado = fix;
    }
    final punto = _fixEnviado?.point;
    if (punto == null) return;

    final navegando = nav.follow == MapFollow.navigation;
    final margen = navegando ? nav.insets : EdgeInsets.zero;
    final cambiaModo = nav.follow != _seguimiento;
    final cambiaZoom =
        nav.follow != MapFollow.none && nav.zoom != _zoomSeguimiento;
    // El panel de abajo cambia de alto al iniciar el turno, por ejemplo.
    final cambiaMargen = nav.follow != MapFollow.none && margen != _margen;
    if (!cambiaModo && !cambiaZoom && !cambiaMargen) return;

    // MapLibre no deja mover la cámara mientras sigue a la flecha (cualquier
    // movimiento suelta el seguimiento; sólo la inclinación tiene su propia
    // llamada). Así que se suelta, se lleva la cámara a donde tiene que estar y
    // se vuelve a seguir. Con el zoom pasa pocas veces: la pantalla lo cambia
    // por tramos de velocidad.
    _cambioPropio = DateTime.now();
    await map.updateMyLocationTrackingMode(ml.MyLocationTrackingMode.none);
    if (!vigente()) return;
    _seguimiento = MapFollow.none;
    if (nav.follow == MapFollow.none) {
      _zoomSeguimiento = null;
      return;
    }

    final rapido = Duration(milliseconds: cambiaModo ? 900 : 700);
    // El margen también es un movimiento de cámara: va con el seguimiento
    // suelto.
    if (margen != _margen) {
      await map.updateContentInsets(margen, true);
      if (!vigente()) return;
      _margen = margen;
    }
    await map.animateCamera(
      cambiaModo
          ? ml.CameraUpdate.newCameraPosition(
              ml.CameraPosition(
                target: _ml(punto),
                zoom: nav.zoom,
                // Al pasar a navegación, de frente hacia donde va; al salir,
                // plano y con el norte arriba.
                bearing: navegando
                    ? (_fixEnviado?.heading ?? map.cameraPosition?.bearing ?? 0)
                    : 0,
                tilt: navegando ? nav.tilt : 0,
              ),
            )
          : ml.CameraUpdate.zoomTo(nav.zoom),
      duration: rapido,
    );
    if (!vigente()) return;
    _cambioPropio = DateTime.now();
    await map.updateMyLocationTrackingMode(
      navegando
          ? ml.MyLocationTrackingMode.trackingGps
          : ml.MyLocationTrackingMode.tracking,
    );
    if (!vigente()) return;
    if (navegando) {
      // Por si volver a seguir la enderezó.
      try {
        await map.setTrackingCameraOptions(
          tilt: nav.tilt.clamp(0, 60).toDouble(),
          duration: const Duration(milliseconds: 300),
        );
      } catch (_) {
        // El seguimiento todavía estaba cambiando: queda la del movimiento.
      }
    }
    if (!vigente()) return;
    _seguimiento = nav.follow;
    _zoomSeguimiento = nav.zoom;
  }

  /// MapLibre soltó el seguimiento. Si no fue la app, fue un gesto que el
  /// [Listener] no alcanzó a ver (un doble toque para acercar, por ejemplo).
  void _alSoltarseSeguimiento() {
    final nav = widget.navigation;
    if (nav == null || nav.follow == MapFollow.none) return;
    if (DateTime.now().difference(_cambioPropio) < const Duration(seconds: 2)) {
      return;
    }
    _seguimiento = MapFollow.none;
    widget.onUserGesture?.call();
  }

  // --- Lector de pantalla --------------------------------------------------

  /// Con TalkBack activo, un botón invisible encima de cada marcador y de cada
  /// vehículo con su descripción: son imágenes dentro del mapa nativo y el
  /// lector de pantalla no las ve. Se ubican cada vez que la cámara se detiene.
  Future<void> _actualizarSemanticas() async {
    final map = _map;
    if (map == null || !_estiloListo) return;
    final conEtiqueta = [
      for (final m in widget.markers)
        if ((m.semanticLabel, m.onTap) case (final texto?, final alTocar?))
          (texto: texto, alTocar: alTocar, donde: m.point),
      for (final v in widget.vehicles)
        if ((v.semanticLabel, v.onTap) case (final texto?, final alTocar?))
          (texto: texto, alTocar: alTocar, donde: v.point),
    ];
    List<math.Point<num>> puntos;
    try {
      puntos = await map.toScreenLocationBatch(
        conEtiqueta.map((e) => _ml(e.donde)),
      );
    } catch (_) {
      return;
    }
    if (!mounted) return;
    // En Android llegan en píxeles físicos; en iOS y la web, lógicos.
    final escala = !kIsWeb && Platform.isAndroid ? _densidad : 1.0;
    setState(() {
      _semanticas = [
        for (final (i, e) in conEtiqueta.indexed)
          (
            texto: e.texto,
            alTocar: e.alTocar,
            punto: Offset(puntos[i].x / escala, puntos[i].y / escala),
          ),
      ];
    });
  }

  // --- Gestos --------------------------------------------------------------

  void _alTocarPantalla(PointerDownEvent event) {
    _inicioGesto = event.position;
    _gestoAvisado = false;
  }

  void _alArrastrar(PointerMoveEvent event) {
    final inicio = _inicioGesto;
    if (inicio == null || _gestoAvisado) return;
    if ((event.position - inicio).distance > kTouchSlop) {
      _gestoAvisado = true;
      widget.onUserGesture?.call();
    }
  }

  // --- Widget --------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    _densidad = MediaQuery.devicePixelRatioOf(context);
    final accesible = MediaQuery.accessibleNavigationOf(context);
    if (accesible != _accesible) {
      _accesible = accesible;
      if (accesible) {
        unawaited(_actualizarSemanticas());
      } else {
        _semanticas = const [];
      }
    }

    final atribucion = MapAttribution(
      style: widget.style,
      alignment: widget.attributionAlignment,
    );
    if (!AppMap.supported || !_basemap.isReady) {
      return Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: scheme.surfaceContainerHighest),
          atribucion,
        ],
      );
    }

    final estilo = _basemap.style(
      widget.style,
      isDark: Theme.of(context).brightness == Brightness.dark,
    );
    if (estilo != _estilo) {
      // MapLibre cambia el estilo en el mismo mapa y avisa al terminar
      // (`_alCargarEstilo`); mientras tanto no se le envía nada.
      _estilo = estilo;
      _debajoDe = _basemap.labelsLayerId(
        widget.style,
        isDark: Theme.of(context).brightness == Brightness.dark,
      );
      _estiloListo = false;
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        Listener(
          onPointerDown: _alTocarPantalla,
          onPointerMove: _alArrastrar,
          child: ml.MapLibreMap(
            styleString: estilo,
            initialCameraPosition: ml.CameraPosition(
              target: _ml(widget.initialCenter),
              zoom: widget.initialZoom,
            ),
            onMapCreated: _alCrear,
            onStyleLoadedCallback: _alCargarEstilo,
            onMapLongClick: _alMantenerPresionado,
            onCameraIdle: _alQuedarQuieta,
            onCameraMove: _alMoverCamara,
            // Los movimientos de cámara cruzan al lado de Dart en cada cuadro:
            // sólo si alguien quiere el rumbo o el centro.
            trackCameraPosition:
                widget.onBearingChanged != null || widget.onCameraIdle != null,
            cameraTargetBounds: ml.CameraTargetBounds(
              ml.LatLngBounds(
                southwest: _ml(kChileBounds.southWest),
                northeast: _ml(kChileBounds.northEast),
              ),
            ),
            minMaxZoomPreference: const ml.MinMaxZoomPreference(
              kMinZoom,
              kMaxZoom,
            ),
            rotateGesturesEnabled: widget.rotateGesturesEnabled,
            tiltGesturesEnabled: false,
            // La pantalla del pasajero tiene su propio botón de brújula.
            compassEnabled: false,
            // La flecha de navegación: la de MapLibre, alimentada con las
            // posiciones de la app (ver [MapNavigation]).
            myLocationEnabled: widget.navigation != null,
            locationSource: widget.navigation != null
                ? const ml.ManualLocationSource()
                : const ml.PlatformLocationSource(),
            myLocationRenderMode: widget.navigation != null
                ? ml.MyLocationRenderMode.gps
                : ml.MyLocationRenderMode.normal,
            onCameraTrackingDismissed: _alSoltarseSeguimiento,
            // El crédito lo muestra [MapAttribution], siempre a la vista; el
            // botón "i" de MapLibre queda fuera de la pantalla.
            attributionButtonMargins: const math.Point(-1000, -1000),
            // Sin las capas de anotaciones de maplibre_gl: la app dibuja con
            // las suyas.
            annotationOrder: const [],
            foregroundLoadColor: scheme.surfaceContainerHighest,
          ),
        ),
        for (final semantica in _semanticas)
          Positioned(
            left: semantica.punto.dx - 24,
            top: semantica.punto.dy - 24,
            width: 48,
            height: 48,
            child: Semantics(
              button: true,
              label: semantica.texto,
              onTap: semantica.alTocar,
              child: const SizedBox.expand(),
            ),
          ),
        atribucion,
      ],
    );
  }
}
