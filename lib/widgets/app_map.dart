import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart' show kTouchSlop;
import 'package:flutter/material.dart';
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
    final centro = Offset(lado / 2, lado / 2);

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

    final pixeles = lado * devicePixelRatio;
    return _aPng(recorder.endRecording(), pixeles, pixeles);
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

/// Galón que muestra hacia dónde va una línea. Apunta al norte: el mapa lo
/// gira con el rumbo de cada tramo. Blanco con un contorno oscuro, para que se
/// vea sobre cualquier color de línea y sobre el mapa claro u oscuro.
class _Galon implements MapImage {
  const _Galon();

  static const double _lado = 14;

  @override
  String get key => 'galon_linea';

  @override
  Future<Uint8List> toPng(double devicePixelRatio) {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..scale(devicePixelRatio);
    final galon = ui.Path()
      ..moveTo(3, 9.5)
      ..lineTo(7, 5)
      ..lineTo(11, 9.5);
    Paint trazo(Color color, double ancho) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = ancho
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = color;
    canvas
      ..drawPath(galon, trazo(const Color(0x59000000), 4.2))
      ..drawPath(galon, trazo(const Color(0xFFFFFFFF), 2.2));
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
    this.onTap,
    this.semanticLabel,
  });

  final String id;
  final LatLng point;
  final MarkerIcon icon;
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
    this.badge,
    this.badgeOpacity = 1,
    this.arrows = false,
    this.onTap,
  });

  final List<LatLng> points;
  final Color color;
  final double width;
  final Color borderColor;

  /// Cuánto sobresale el borde a cada lado, como en flutter_map.
  final double borderWidth;

  /// Punteada: para lo que se recorre a pie, distinto de la línea continua
  /// de los colectivos. Cada punto es un círculo de [width] con su borde.
  final bool dotted;

  /// Insignia repetida a lo largo de la línea, por encima de los nombres de
  /// calles. Si dos se topan, MapLibre muestra sólo una.
  final LineBadge? badge;
  final double badgeOpacity;

  /// Flechas que avanzan por la línea en el orden de [points] (quietas si el
  /// [AppMap] no las anima): hacia dónde va el colectivo.
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

/// Radio en píxeles, en el zoom 0, de un círculo de [meters] metros en la
/// [latitude] dada. En MapLibre el mundo mide 512 px en el zoom 0 y el doble
/// en cada nivel siguiente; Mercator estira las distancias por 1/cos(lat).
@visibleForTesting
double circleRadiusAtZoom0(double meters, double latitude) =>
    meters * 512 / (40075016.686 * math.cos(latitude * math.pi / 180));

/// Metros que mide un píxel lógico en el [zoom] dado, en la [latitude] dada.
@visibleForTesting
double metersPerPixel(double latitude, double zoom) =>
    1 / (circleRadiusAtZoom0(1, latitude) * math.pow(2, zoom));

// ---------------------------------------------------------------------------
// El mapa
// ---------------------------------------------------------------------------

/// Mapa común a las pantallas de la app (pasajero, flota y editor de
/// paraderos), dibujado por MapLibre con la GPU.
///
/// El mapa base sale de los archivos offline ([BasemapService]); la vista
/// satelital es la única que necesita conexión. Encima, la app dibuja lo suyo
/// con capas propias: [lines], [circles] y [markers], en ese orden. Cambiar
/// cualquiera de esas listas sólo actualiza sus datos, sin volver a dibujar el
/// mapa base.
class AppMap extends StatefulWidget {
  const AppMap({
    super.key,
    this.controller,
    required this.initialCenter,
    this.initialZoom = kInitialZoom,
    this.style = MapStyle.normal,
    this.markers = const [],
    this.lines = const [],
    this.circles = const [],
    this.pulse,
    this.animateArrows = true,
    this.navigation,
    this.rotateGesturesEnabled = true,
    this.attributionAlignment = Alignment.bottomLeft,
    this.onMapReady,
    this.onUserGesture,
    this.onLongPress,
    this.onBearingChanged,
  });

  final AppMapController? controller;
  final LatLng initialCenter;
  final double initialZoom;
  final MapStyle style;
  final List<MapMarker> markers;
  final List<MapLine> lines;
  final List<MapCircle> circles;
  final MapPulse? pulse;

  /// Si las flechas de las líneas con [MapLine.arrows] avanzan. Sin
  /// animaciones (la preferencia, o el mapa fuera de la vista), quedan quietas.
  final bool animateArrows;

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

  /// MapLibre funciona en Android, iOS y la web; en el escritorio y en los
  /// tests de widgets el mapa queda sólo con su fondo.
  static bool get supported => kIsWeb || Platform.isAndroid || Platform.isIOS;

  @override
  State<AppMap> createState() => _AppMapState();
}

class _AppMapState extends State<AppMap> with TickerProviderStateMixin {
  static const _lineas = 'app_lineas';
  static const _insignias = 'app_insignias';
  static const _flechas = 'app_flechas';
  static const _circulos = 'app_circulos';
  static const _pulso = 'app_pulso';
  static const _marcadores = 'app_marcadores';

  static const _galon = _Galon();

  /// Las flechas avanzan sin mover nada en el mapa: cada una está dibujada en
  /// [_fases] posiciones seguidas, una capa por posición, y la animación sólo
  /// cambia qué capa se ve (la opacidad de una capa es un valor de pintura:
  /// cambiarla no obliga a MapLibre a rehacer las teselas).
  static const _fases = 8;

  /// Entre una flecha y la siguiente, en píxeles lógicos.
  static const double _espacioFlechas = 56;

  /// Tope de flechas por envío, por si una línea muy larga cae en la zona.
  static const _maxFlechas = 3000;

  static final List<double> _flechasQuietas = [
    for (var f = 0; f < _fases; f++) f == 0 ? 1.0 : 0.0,
  ];

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

  /// Una vuelta: cada flecha avanza hasta donde estaba la siguiente.
  late final AnimationController _flujo;

  /// Opacidad de cada fase de las flechas: la que tiene el mapa y la que se
  /// quiere ahora.
  final List<double> _opacidadFlechas = List.of(_flechasQuietas);
  List<double> _objetivoFlechas = _flechasQuietas;
  bool _pintandoFlechas = false;

  /// Zoom y zona (tres veces la pantalla) con que se repartieron las flechas:
  /// su separación en metros depende del zoom.
  ({double zoom, ml.LatLngBounds zona})? _vista;

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
  List<(MapMarker, Offset)> _semanticas = const [];

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
    // Unos 13 px por segundo: un avance tranquilo, que indica el sentido sin
    // llamar la atención (a 40 px/s se veía apurado).
    _flujo = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4200),
    )..addListener(_pintarFlechas);
    _basemap.addListener(_onBasemapChanged);
    if (!_basemap.isReady) unawaited(_basemap.load());
  }

  @override
  void dispose() {
    _basemap.removeListener(_onBasemapChanged);
    _animacion.dispose();
    _flujo.dispose();
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
    _sincronizar();
    _sincronizarNavegacion();
    _actualizarPulso();
    _actualizarFlujo();
    if (_vista == null) unawaited(_actualizarVista());
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
    // Las capas de flechas nacen así (ver `_agregarCapas`).
    _opacidadFlechas.setAll(0, _flechasQuietas);
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
    _actualizarFlujo();
    unawaited(_actualizarVista());
    if (_accesible) unawaited(_actualizarSemanticas());
  }

  /// Capas de la app. Las líneas, sus flechas, el halo y el pulso van debajo
  /// de [debajoDe], la primera capa de nombres del mapa base; las insignias de
  /// las líneas y los marcadores, encima de todo.
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

    await map.addGeoJsonSource(_lineas, vacio);
    await map.addLineLayer(
      _lineas,
      '${_lineas}_borde',
      ml.LineLayerProperties(
        lineColor: ['get', 'colorBorde'],
        lineWidth: [
          '+',
          ['get', 'ancho'],
          [
            '*',
            2,
            ['get', 'borde'],
          ],
        ],
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
        lineWidth: ['get', 'ancho'],
        lineJoin: 'round',
        lineCap: 'round',
        lineSortKey: ordenado,
      ),
      belowLayerId: debajoDe,
      filter: continua,
      // Tocar una línea la elige (ver `MapLine.onTap`).
      enableInteraction: true,
    );
    // Las flechas, encima de las líneas y debajo de la ruta a pie: son
    // contexto, no la indicación que hay que seguir.
    await map.addGeoJsonSource(_flechas, vacio);
    for (var fase = 0; fase < _fases; fase++) {
      await map.addSymbolLayer(
        _flechas,
        '${_flechas}_$fase',
        _propiedadesFlecha(_flechasQuietas[fase]),
        belowLayerId: debajoDe,
        filter: [
          '==',
          ['get', 'fase'],
          fase,
        ],
        // Más lejos, en una línea de pocos píxeles, serían puro ruido.
        minzoom: 12,
        enableInteraction: false,
      );
    }
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
        symbolSpacing: 280,
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
    if (layerId != _marcadores) return;
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
    unawaited(_actualizarVista());
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
      _marcadores: _marcadoresGeoJson(markers),
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

    // Repartir las flechas recorre las líneas enteras: sólo se hace si
    // cambiaron las líneas que las llevan o la vista.
    final firma = _firmaFlechas();
    if (_enviado[_flechas] != firma) {
      final datos = _flechasGeoJson(widget.lines, _vista);
      if (!vigente()) return;
      await map.setGeoJsonSource(_flechas, datos);
      if (!vigente()) return;
      _enviado[_flechas] = firma;
    }
  }

  String _firmaFlechas() {
    final vista = _vista;
    final firma = StringBuffer(
      vista == null
          ? '-'
          : '${vista.zoom} ${vista.zona.southwest} ${vista.zona.northeast}',
    );
    for (final l in widget.lines) {
      if (!l.arrows || l.points.isEmpty) continue;
      firma.write(' ${l.points.length} ${l.points.first} ${l.points.last}');
    }
    return firma.toString();
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

  /// Las flechas de las líneas con [MapLine.arrows] que caen en la zona de
  /// [vista], cada [_espacioFlechas] píxeles en su zoom. Entre una y otra van
  /// sus otras [_fases] - 1 posiciones, una por capa.
  static Map<String, dynamic> _flechasGeoJson(
    List<MapLine> lines,
    ({double zoom, ml.LatLngBounds zona})? vista,
  ) {
    final features = <Map<String, dynamic>>[];
    if (vista != null) {
      final sur = vista.zona.southwest;
      final norte = vista.zona.northeast;
      bool dentro(LatLng p) =>
          p.latitude >= sur.latitude &&
          p.latitude <= norte.latitude &&
          p.longitude >= sur.longitude &&
          p.longitude <= norte.longitude;
      final paso =
          metersPerPixel((sur.latitude + norte.latitude) / 2, vista.zoom) *
          _espacioFlechas /
          _fases;
      todas:
      for (final line in lines) {
        if (!line.arrows) continue;
        final puntos = puntosCada(
          [
            for (final p in line.points)
              if (_finito(p)) p,
          ],
          paso,
          desde: paso / 2,
        );
        for (final (i, p) in puntos.indexed) {
          if (!dentro(p.punto)) continue;
          features.add({
            'type': 'Feature',
            'properties': {
              'fase': i % _fases,
              'rumbo': (p.rumbo * 10).roundToDouble() / 10,
            },
            'geometry': {
              'type': 'Point',
              'coordinates': [p.punto.longitude, p.punto.latitude],
            },
          });
          if (features.length >= _maxFlechas) break todas;
        }
      }
    }
    return {'type': 'FeatureCollection', 'features': features};
  }

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

  // --- Flechas -------------------------------------------------------------

  /// Toma lo que se ve del mapa para repartir las flechas. Sólo cambia algo si
  /// cambió el zoom o la cámara salió de la zona que ya tiene flechas.
  Future<void> _actualizarVista() async {
    final map = _map;
    if (map == null || !_estiloListo || !_hayFlechas) return;
    final zoom = map.cameraPosition?.zoom;
    if (zoom == null) return;
    final ml.LatLngBounds visible;
    try {
      visible = await map.getVisibleRegion();
    } catch (_) {
      return;
    }
    final vista = _vista;
    if (!mounted ||
        (vista != null &&
            (vista.zoom - zoom).abs() < 0.25 &&
            _contiene(vista.zona, visible))) {
      return;
    }
    // La pantalla y otra más hacia cada lado: al arrastrar el mapa ya hay
    // flechas antes de que la cámara se detenga.
    final alto = visible.northeast.latitude - visible.southwest.latitude;
    final ancho = visible.northeast.longitude - visible.southwest.longitude;
    _vista = (
      zoom: zoom,
      zona: ml.LatLngBounds(
        southwest: ml.LatLng(
          visible.southwest.latitude - alto,
          visible.southwest.longitude - ancho,
        ),
        northeast: ml.LatLng(
          visible.northeast.latitude + alto,
          visible.northeast.longitude + ancho,
        ),
      ),
    );
    _sincronizar();
  }

  static bool _contiene(ml.LatLngBounds afuera, ml.LatLngBounds adentro) =>
      adentro.southwest.latitude >= afuera.southwest.latitude &&
      adentro.southwest.longitude >= afuera.southwest.longitude &&
      adentro.northeast.latitude <= afuera.northeast.latitude &&
      adentro.northeast.longitude <= afuera.northeast.longitude;

  void _actualizarFlujo() {
    final hay = _estiloListo && _hayFlechas;
    final animar = hay && widget.animateArrows;
    if (animar && !_flujo.isAnimating) {
      _flujo.repeat();
    } else if (!animar && _flujo.isAnimating) {
      _flujo
        ..stop()
        ..reset();
    }
    if (hay && !animar) _pedirOpacidades(_flechasQuietas);
  }

  /// Un cuadro de las flechas: la fase actual se apaga mientras se enciende la
  /// siguiente, así que cada flecha parece deslizarse hacia adelante.
  void _pintarFlechas() {
    final t = _flujo.value * _fases;
    final fase = t.floor() % _fases;
    final avance = t - t.floor();
    _pedirOpacidades([
      for (var f = 0; f < _fases; f++)
        f == fase
            ? 1 - avance
            : f == (fase + 1) % _fases
            ? avance
            : 0,
    ]);
  }

  /// Lleva las capas de flechas a [objetivo]. Si todavía va un envío, éste
  /// termina mandando lo último que se pidió: nunca se acumulan llamadas, y el
  /// estado final (por ejemplo, quietas al apagar las animaciones) siempre
  /// llega.
  void _pedirOpacidades(List<double> objetivo) {
    _objetivoFlechas = objetivo;
    if (_pintandoFlechas) return;
    _pintandoFlechas = true;
    unawaited(() async {
      try {
        while (mounted && _estiloListo) {
          final map = _map;
          final objetivo = _objetivoFlechas;
          final cambios = [
            for (var f = 0; f < _fases; f++)
              if ((objetivo[f] - _opacidadFlechas[f]).abs() > 0.01) f,
          ];
          if (map == null || cambios.isEmpty) break;
          final generacion = _generacion;
          await Future.wait([
            for (final f in cambios)
              map.setLayerProperties(
                '${_flechas}_$f',
                _propiedadesFlecha(objetivo[f]),
              ),
          ]);
          // Con otro estilo las capas son nuevas y parten quietas.
          if (generacion != _generacion) break;
          for (final f in cambios) {
            _opacidadFlechas[f] = objetivo[f];
          }
        }
      } catch (_) {
        // El estilo cambió a mitad del envío; su carga deja las flechas quietas.
      } finally {
        _pintandoFlechas = false;
      }
    }());
  }

  /// Todas las propiedades de una capa de flechas: `setLayerProperties` deja
  /// en su valor por omisión las que no se le pasan. Repetir las mismas no
  /// cuesta nada; MapLibre sólo aplica lo que cambia.
  static ml.SymbolLayerProperties _propiedadesFlecha(double opacidad) =>
      ml.SymbolLayerProperties(
        iconImage: _galon.key,
        iconRotate: ['get', 'rumbo'],
        iconRotationAlignment: 'map',
        iconAllowOverlap: true,
        iconIgnorePlacement: true,
        iconOpacity: opacidad,
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

  /// Con TalkBack activo, un botón invisible encima de cada marcador con su
  /// descripción: los marcadores son imágenes dentro del mapa nativo y el
  /// lector de pantalla no los ve. Se ubican cada vez que la cámara se detiene.
  Future<void> _actualizarSemanticas() async {
    final map = _map;
    if (map == null || !_estiloListo) return;
    final conEtiqueta = [
      for (final m in widget.markers)
        if (m.semanticLabel != null && m.onTap != null) m,
    ];
    List<math.Point<num>> puntos;
    try {
      puntos = await map.toScreenLocationBatch(
        conEtiqueta.map((m) => _ml(m.point)),
      );
    } catch (_) {
      return;
    }
    if (!mounted) return;
    // En Android llegan en píxeles físicos; en iOS y la web, lógicos.
    final escala = !kIsWeb && Platform.isAndroid ? _densidad : 1.0;
    setState(() {
      _semanticas = [
        for (final (i, m) in conEtiqueta.indexed)
          (m, Offset(puntos[i].x / escala, puntos[i].y / escala)),
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
            // sólo si alguien quiere el rumbo, o el zoom para las flechas.
            trackCameraPosition: widget.onBearingChanged != null || _hayFlechas,
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
        for (final (marker, punto) in _semanticas)
          Positioned(
            left: punto.dx - 24,
            top: punto.dy - 24,
            width: 48,
            height: 48,
            child: Semantics(
              button: true,
              label: marker.semanticLabel,
              onTap: marker.onTap,
              child: const SizedBox.expand(),
            ),
          ),
        atribucion,
      ],
    );
  }
}
