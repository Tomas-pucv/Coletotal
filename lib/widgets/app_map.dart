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
import 'package:taxi1/widgets/map_attribution.dart';

// ---------------------------------------------------------------------------
// Lo que las pantallas dibujan sobre el mapa
// ---------------------------------------------------------------------------

/// Ícono de un marcador. La app lo dibuja una vez y se lo entrega a MapLibre
/// como imagen: el mapa es una vista nativa y no puede llevar widgets adentro.
///
/// Reproduce los marcadores que antes eran widgets de Flutter: un círculo de
/// color con borde, sombra y un ícono de Material al centro, o un ícono solo.
/// [tapTarget] agranda la imagen con borde transparente: MapLibre detecta el
/// toque sobre la imagen entera, así que el área táctil sigue midiendo lo que
/// medía el widget aunque el dibujo sea más chico.
@immutable
class MarkerIcon {
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

  /// Nombre de la imagen en el estilo: dos marcadores iguales comparten una.
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

  /// La imagen en PNG, a la densidad de la pantalla.
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

    final picture = recorder.endRecording();
    final pixeles = (lado * devicePixelRatio).ceil();
    final image = await picture.toImage(pixeles, pixeles);
    picture.dispose();
    try {
      final datos = await image.toByteData(format: ui.ImageByteFormat.png);
      return datos!.buffer.asUint8List();
    } finally {
      image.dispose();
    }
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
  final bool rotateGesturesEnabled;
  final Alignment attributionAlignment;

  /// Cuando ya se puede mover la cámara.
  final VoidCallback? onMapReady;

  /// El usuario arrastró o pellizcó el mapa (para dejar de seguirlo).
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

class _AppMapState extends State<AppMap> with SingleTickerProviderStateMixin {
  static const _lineas = 'app_lineas';
  static const _circulos = 'app_circulos';
  static const _pulso = 'app_pulso';
  static const _marcadores = 'app_marcadores';

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
    _basemap.addListener(_onBasemapChanged);
    if (!_basemap.isReady) unawaited(_basemap.load());
  }

  @override
  void dispose() {
    _basemap.removeListener(_onBasemapChanged);
    _animacion.dispose();
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
    _actualizarPulso();
    if (_accesible) unawaited(_actualizarSemanticas());
  }

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
    _actualizarPulso();
    if (_accesible) unawaited(_actualizarSemanticas());
  }

  /// Capas de la app. Las líneas, el halo y el pulso van debajo de
  /// [debajoDe], la primera capa de nombres del mapa base; los marcadores,
  /// encima de todo.
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
    final iconos = [
      for (final marker in markers) marker.icon,
      for (final line in widget.lines)
        if (line.dotted) line.dotIcon,
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
            // sólo si alguien quiere el rumbo.
            trackCameraPosition: widget.onBearingChanged != null,
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
