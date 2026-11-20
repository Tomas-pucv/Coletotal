import 'dart:async';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import 'package:taxi1/config/map_config.dart';
import 'package:taxi1/l10n/app_localizations.dart';
import 'package:taxi1/models/colectivo_activo.dart';
import 'package:taxi1/models/place_result.dart';
import 'package:taxi1/models/recorrido.dart';
import 'package:taxi1/models/route_path.dart';
import 'package:taxi1/navigation/app_destination.dart';
import 'package:taxi1/screens/main_screen.dart';
import 'package:taxi1/services/auth_service.dart';
import 'package:taxi1/services/firebase_telemetria_service.dart';
import 'package:taxi1/services/line_planner.dart';
import 'package:taxi1/services/location_service.dart';
import 'package:taxi1/services/preferences_service.dart';
import 'package:taxi1/services/puntos_de_sena.dart';
import 'package:taxi1/services/recorridos_service.dart';
import 'package:taxi1/services/route_service.dart';
import 'package:taxi1/services/turno_service.dart';
import 'package:taxi1/theme/app_colors.dart';
import 'package:taxi1/theme/app_spacing.dart';
import 'package:taxi1/utils/distance_format.dart';
import 'package:taxi1/utils/patente.dart';
import 'package:taxi1/utils/tile_coords.dart';
import 'package:taxi1/widgets/app_map.dart';
import 'package:taxi1/widgets/colectivo_marker.dart';
import 'package:taxi1/widgets/line_suggestions_sheet.dart';
import 'package:taxi1/widgets/map_compass_button.dart';
import 'package:taxi1/widgets/map_overlay_card.dart';
import 'package:taxi1/widgets/map_search_bar.dart';
import 'package:taxi1/widgets/map_style_sheet.dart';
import 'package:taxi1/widgets/metric_chip.dart';
import 'package:taxi1/widgets/state_views.dart';
import 'package:taxi1/widgets/recorrido_lines.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen>
    with SingleTickerProviderStateMixin {
  final _mapController = AppMapController();

  bool _followUser = true;
  bool _mapReady = false;

  /// Rumbo actual de la cámara (grados desde el norte), observado únicamente
  /// por el botón de brújula para evitar reconstruir toda la pantalla al rotar.
  final _rumbo = ValueNotifier<double>(0);

  final routeService = RouteService.instance;
  final prefs = PreferencesService.instance;
  final recorridos = RecorridosService.instance;
  final location = LocationService.instance;

  /// Destino final buscado por el pasajero.
  PlaceResult? _destino;

  /// Sugerencia de viaje seleccionada para llegar a [_destino].
  LineSuggestion? _viaje;

  /// Último centro del mapa tras detenerse la cámara (foco de puntos de seña
  /// cuando el usuario explora otra zona de la ciudad).
  LatLng? _centroMapa;

  /// Puntos de seña por sentido para la línea actualmente en foco.
  List<PuntoDeSena> _senas = const [];
  Sentido? _sentidoSena;
  String? _senasDe;

  /// Identificador de línea seleccionada al tocar un vehículo, cuando sólo se
  /// desea inspeccionar su trazado sin calcular ruta peatonal.
  String? _sinCaminata;

  /// UID del colectivo seleccionado en el mapa (Modo Foco en vehículo y línea).
  String? _colectivoSeleccionadoUid;

  late final AnimationController _centerBtnController;
  late final Animation<double> _centerScale;

  @override
  void initState() {
    super.initState();

    // Escucha cambios estructurales de la vista. Las actualizaciones de alta
    // frecuencia (GPS y flota en vivo) se delegan a `_MapaPasajero`.
    prefs.addListener(_onChanged);
    routeService.addListener(_onChanged);
    recorridos.addListener(_onRecorridosChanged);
    location.addListener(_onLocationChanged);

    _centerBtnController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    );
    _centerScale = Tween<double>(begin: 1.0, end: 1.12).animate(
      CurvedAnimation(parent: _centerBtnController, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    // La telemetría del chofer no se detiene acá: la gobierna TurnoService.
    prefs.removeListener(_onChanged);
    routeService.removeListener(_onChanged);
    recorridos.removeListener(_onRecorridosChanged);
    location.removeListener(_onLocationChanged);
    _centerBtnController.dispose();
    _rumbo.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  /// Actualiza el estado de la vista cuando cambia la línea seleccionada.
  void _onRecorridosChanged() {
    if (!mounted) return;
    final linea = recorridos.selected;
    if (linea == null) {
      _colectivoSeleccionadoUid = null;
    }
    final viaje = _viaje;
    if (viaje != null && linea?.id != viaje.recorrido.id) {
      _viaje = null;
      _destino = null;
      routeService.clearDestination();
    }
    if (linea != null && recorridos.tomarEncuadre()) {
      _followUser = false;
      unawaited(
        _encuadrar([for (final (_, t) in linea.trayectos) ...t.trazado]),
      );
    }
    _prepararSena();
    if (mounted) setState(() {});
  }

  LatLng _foco() => PuntosDeSena.foco(
    posicion: location.position,
    centroMapa: _centroMapa,
    siguiendo: _followUser,
  );

  /// Al detenerse la cámara, actualiza el centro de referencia si el
  /// desplazamiento supera los 100 metros.
  void _onCameraIdle(LatLng centro) {
    final antes = _centroMapa;
    if (antes != null &&
        const Distance().as(LengthUnit.Meter, antes, centro) < 100) {
      return;
    }
    if (mounted) setState(() => _centroMapa = centro);
  }

  /// Calcula los puntos de seña de la línea seleccionada y solicita la ruta
  /// peatonal hacia el sentido más cercano.
  void _prepararSena() {
    final linea = recorridos.selected;
    if (_viaje != null || linea == null) {
      if (_senasDe != null && _viaje == null) routeService.clearDestination();
      _senas = const [];
      _senasDe = null;
      _sentidoSena = null;
      return;
    }
    if (_senasDe == linea.id) return;
    _senasDe = linea.id;
    _senas = PuntosDeSena.deVariante(linea, _foco());
    if (_senas.isEmpty) {
      _sentidoSena = null;
      return;
    }
    final cercana = _senas.reduce((a, b) => a.metros <= b.metros ? a : b);
    _sentidoSena = cercana.sentido;
    if (_sinCaminata == linea.id) {
      routeService.clearDestination();
      return;
    }
    unawaited(_caminarA(cercana));
  }

  /// Distancia en metros desde la posición del usuario a [punto], o `null` sin GPS.
  double? _metrosDesdeUsuario(LatLng punto) {
    final yo = location.position;
    return yo == null ? null : const Distance().as(LengthUnit.Meter, yo, punto);
  }

  /// Verifica si [sena] se encuentra dentro del radio máximo de caminata.
  bool _aMano(PuntoDeSena sena) {
    final metros = _metrosDesdeUsuario(sena.punto);
    return metros != null && metros <= PuntosDeSena.radio;
  }

  Future<void> _caminarA(PuntoDeSena sena) async {
    if (!mounted) return;
    final desde = location.position;
    if (desde == null || !_aMano(sena)) {
      routeService.clearDestination();
      return;
    }
    final l10n = AppLocalizations.of(context)!;
    final destino = WalkTarget(location: sena.punto, label: l10n.hailHere);
    routeService.setDestination(destino);
    await routeService.fetchRoute(desde, destino);
  }

  /// Cambia el punto de seña activo al sentido opuesto.
  void _cambiarSentidoSena(Sentido sentido) {
    if (sentido == _sentidoSena) return;
    final sena = _senas.where((s) => s.sentido == sentido).firstOrNull;
    if (sena == null) return;
    setState(() => _sentidoSena = sentido);
    unawaited(_caminarA(sena));
  }

  /// Selecciona una variante desde el mapa, calcula sus puntos de seña y
  /// encuadra su trazado completo.
  void _onTapVariante(Recorrido elegida) {
    setState(() {
      _colectivoSeleccionadoUid = null;
      _followUser = false;
    });
    recorridos.select(elegida);
    final sena = _senas.where((s) => s.sentido == _sentidoSena).firstOrNull;
    final desde = location.position;
    unawaited(
      _encuadrar([
        for (final (_, t) in elegida.trayectos) ...t.trazado,
        if (desde != null && sena != null && _aMano(sena)) desde,
      ]),
    );
  }

  /// Ajusta la cámara para que [puntos] entren en el área visible del mapa.
  Future<void> _encuadrar(List<LatLng> puntos) async {
    if (!mounted || !_mapReady || puntos.isEmpty) return;
    final size = MediaQuery.sizeOf(context);
    final vista = encuadre(
      puntos,
      ancho: size.width,
      alto: size.height * 0.55,
      zoomMaximo: kStreetZoom,
    );
    await _centerOn(vista.centro, zoom: vista.zoom);
  }

  /// Seguir al usuario mueve la cámara, pero no reconstruye la pantalla.
  void _onLocationChanged() {
    final position = location.position;
    if (position == null) {
      if (location.issue == LocationIssue.disabledByPreference &&
          _followUser &&
          mounted) {
        setState(() => _followUser = false);
      }
      return;
    }
    if (_followUser && _mapReady) unawaited(_mapController.moveTo(position));
  }

  void _onMapReady() {
    _mapReady = true;
    final position = location.position;
    if (_followUser && position != null) {
      unawaited(_mapController.moveTo(position));
    }
  }

  /// Centra la cámara respetando la preferencia "Animaciones".
  Future<void> _centerOn(LatLng point, {double? zoom}) async {
    if (!_mapReady) return;
    if (prefs.animationsEnabled) {
      await _mapController.animateTo(point, zoom: zoom);
    } else {
      await _mapController.moveTo(point, zoom: zoom);
    }
  }

  /// Planifica un viaje en colectivo hacia [place] ejecutando los 2 niveles
  /// del optimizador híbrido en cascada:
  /// 1. Nivel 1 ([LinePlanner.suggest]): evalúa todas las líneas en RAM con
  ///    métricas subrogadas y tablas LUT.
  /// 2. Nivel 2 ([LinePlanner.verifyWithValhalla]): verifica el tramo peatonal
  ///    de la alternativa elegida sobre el grafo vial real.
  Future<void> _onDestinationSelected(PlaceResult place) async {
    final l10n = AppLocalizations.of(context)!;
    setState(() {
      _destino = place;
      _followUser = false;
    });
    unawaited(_centerOn(place.location, zoom: kPlaceZoom));

    final origin = location.position ?? routeService.origin;
    if (origin == null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(l10n.suggestLocationNeeded)));
      return;
    }

    final sugerencias = LinePlanner.suggest(
      user: origin,
      destino: place.location,
    );

    if (!mounted) return;
    final elegido = await showLineSuggestionsSheet(
      context,
      destino: place.name,
      suggestions: sugerencias,
    );
    if (elegido == null || !mounted) return;

    // Fija el viaje antes de seleccionar la línea para que el listener de
    // recorridos mantenga sincronizado el estado del trayecto activo.
    setState(() => _viaje = elegido);
    recorridos.select(elegido.recorrido, sentido: elegido.sentido);
    final subida = WalkTarget(location: elegido.subida, label: l10n.boardHere);
    routeService.setDestination(subida);
    final desde = location.position ?? origin;
    unawaited(
      _encuadrar([desde, elegido.subida, elegido.bajada, place.location]),
    );
    await LinePlanner.verifyWithValhalla(
      user: desde,
      destino: place.location,
      suggestion: elegido,
      walkRouter: (from, _) async {
        final ok = await routeService.fetchRoute(from, subida);
        final info = routeService.routeInfo;
        if (!ok || info == null) return null;
        return RoutePath(
          points: info.points,
          distanceMeters: info.distanceMeters,
          durationSeconds: info.durationSeconds,
          provider: info.provider,
        );
      },
    );
  }

  void _clearDestino() {
    setState(() {
      _destino = null;
      _viaje = null;
      _colectivoSeleccionadoUid = null;
    });
    routeService.clearDestination();
    recorridos.clearSelection();
  }

  Future<void> _recenter() async {
    final position = location.position;
    if (position == null) {
      await location.retry();
      return;
    }
    _centerBtnController.forward(from: 0);
    await _centerOn(position, zoom: kStreetZoom);
    if (!mounted) return;
    _centerBtnController.reverse();
    setState(() => _followUser = true);
  }

  /// Reorienta el mapa hacia el norte respetando la preferencia de animaciones.
  Future<void> _reorient() =>
      _mapController.resetBearing(animate: prefs.animationsEnabled);

  Future<void> _onTapColectivo(ColectivoActivo colectivo) async {
    final id = colectivo.recorridoId;
    final linea = id == null ? null : recorridos.byId(id);
    final yaEnFoco =
        _colectivoSeleccionadoUid == colectivo.uid &&
        recorridos.selected?.id == linea?.id &&
        linea != null;

    // Al tocar un colectivo con ruta asignada (sin viaje armado), aislamos su
    // línea, expandimos el radio de esa línea a 2 km y ajustamos la cámara para
    // ver tanto la ruta completa como el vehículo sin tapar el mapa con un
    // modal. Un segundo toque sobre el mismo vehículo abre su ficha detallada.
    if (_viaje == null && linea != null && !yaEnFoco) {
      setState(() {
        _colectivoSeleccionadoUid = colectivo.uid;
        _followUser = false;
      });
      _sinCaminata = linea.id;
      recorridos.select(linea);
      _sinCaminata = null;
      final sena = _senas.where((s) => s.sentido == _sentidoSena).firstOrNull;
      final desde = location.position;
      unawaited(
        _encuadrar([
          for (final (_, t) in linea.trayectos) ...t.trazado,
          LatLng(colectivo.latitud, colectivo.longitud),
          if (desde != null && sena != null && _aMano(sena)) desde,
        ]),
      );
      return;
    }

    if (!mounted) return;
    final ahora = FirebaseTelemetriaService.instance.serverNow();
    await showModalBottomSheet<void>(
      context: context,
      builder: (context) => _ColectivoSheet(colectivo: colectivo, ahora: ahora),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    final linea = recorridos.selected;
    final viaje = _viaje;
    final mapStyle = MapStyle.fromPref(prefs.mapType);
    final lineas = recorridos.publicas;

    return Scaffold(
      body: Stack(
        children: [
          _MapaPasajero(
            controller: _mapController,
            style: mapStyle,
            lineas: lineas,
            centroMapa: _centroMapa,
            colectivoSeleccionadoUid: _colectivoSeleccionadoUid,
            linea: linea,
            sentido: recorridos.selectedSentido,
            viaje: viaje,
            destino: _destino,
            senas: _senas,
            sentidoSena: _sentidoSena,
            onMapReady: _onMapReady,
            onCameraIdle: _onCameraIdle,
            onBearingChanged: (rumbo) => _rumbo.value = rumbo,
            onUserGesture: () {
              if (_followUser) setState(() => _followUser = false);
            },
            onTapColectivo: _onTapColectivo,
            onTapVariante: _onTapVariante,
            onTapSentido: _cambiarSentidoSena,
          ),

          // Todos los controles flotantes viven en un solo Column que ocupa la
          // pantalla: el botón de recentrado sube solo cuando la tarjeta de
          // estado crece, ya sea por la info de ruta o por el tamaño de fuente.
          Positioned.fill(
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _topOverlays(l10n),
                    const Spacer(),
                    Align(
                      alignment: Alignment.centerRight,
                      child: _recenterButton(l10n),
                    ),
                    ..._routeCards(l10n),
                    // Sólo con un viaje armado: qué línea tomar y cuánto
                    // caminar. Sin viaje no hay tarjeta abajo.
                    if (viaje != null) ...[
                      const SizedBox(height: AppSpacing.md),
                      _TripCard(
                        viaje: viaje,
                        routeInfo: routeService.routeInfo,
                        onClose: _clearDestino,
                        onTap: () {
                          setState(() => _followUser = false);
                          _centerOn(viaje.subida, zoom: kStreetZoom);
                        },
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _topOverlays(AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Buscador de direcciones en el borde superior del mapa. Como la vista
        // cartográfica ocupa toda la pantalla sin AppBar, el botón del menú
        // lateral se integra dentro de la barra de búsqueda.
        MapSearchBar(
          leading: IconButton(
            icon: const Icon(Icons.menu),
            tooltip: l10n.openMenu,
            onPressed: MainNavigationController.instance.openDrawer,
          ),
          onSelected: _onDestinationSelected,
          destinationLabel: _destino?.name,
          onCleared: _clearDestino,
        ),
        const SizedBox(height: AppSpacing.sm),
        _secondaryOverlays(l10n),
      ],
    );
  }

  Widget _secondaryOverlays(AppLocalizations l10n) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ListenableBuilder(
                listenable: location,
                builder: (context, _) {
                  final notice = _locationNotice(l10n);
                  if (notice == null) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: notice,
                  );
                },
              ),
              ValueListenableBuilder<TelemetriaState>(
                valueListenable: FirebaseTelemetriaService.instance.state,
                builder: (context, state, _) => state.failed
                    ? InlineNotice(
                        icon: Icons.cloud_off,
                        message: l10n.telemetryUnavailable,
                        tone: StatusTone.error,
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Column(
          children: [
            // Cambiar entre calles y satélite es el ajuste que más se toca con
            // el mapa a la vista; tenerlo solo en Preferencias obligaba a salir
            // del mapa para volver a entrar.
            FloatingActionButton.small(
              heroTag: 'map_layers',
              tooltip: l10n.mapLayers,
              onPressed: () => showMapStyleSheet(context),
              child: const Icon(Icons.layers_outlined),
            ),
            // Debajo de las capas, como en Google Maps: al aparecer y
            // desaparecer no mueve a ningún otro botón.
            const SizedBox(height: AppSpacing.sm),
            MapCompassButton(
              bearing: _rumbo,
              tooltip: l10n.reorientMap,
              animate: prefs.animationsEnabled,
              onPressed: _reorient,
            ),
          ],
        ),
      ],
    );
  }

  /// Tarjetas de lo que se está mostrando o calculando: la línea dibujada y
  /// el aviso de ruta en cálculo. Van abajo, junto a la tarjeta de la ruta y
  /// al alcance del pulgar, y dejan la parte de arriba sólo para buscar.
  List<Widget> _routeCards(AppLocalizations l10n) {
    return [
      // La línea elegida: dónde hacerle seña y cuánto caminar, con una X. Con
      // un viaje armado no hace falta: la tarjeta del viaje ya dice todo.
      if (_viaje == null)
        if (recorridos.selected case final linea?) ...[
          const SizedBox(height: AppSpacing.md),
          _SenaCard(
            linea: linea,
            senas: _senas,
            sentido: _sentidoSena,
            colectivoSeleccionado: _colectivoSeleccionadoUid == null
                ? null
                : FirebaseTelemetriaService.instance.state.value.colectivos
                      .where((c) => c.uid == _colectivoSeleccionadoUid)
                      .firstOrNull,
            metrosDesdeTi: _senas
                .where((s) => s.sentido == _sentidoSena)
                .map((s) => _metrosDesdeUsuario(s.punto))
                .firstOrNull,
            routeInfo: routeService.routeInfo,
            onClose: () {
              setState(() => _colectivoSeleccionadoUid = null);
              recorridos.clearSelection();
            },
            onSwitch: _cambiarSentidoSena,
            onTap: () {
              final sena = _senas
                  .where((s) => s.sentido == _sentidoSena)
                  .firstOrNull;
              if (sena == null) return;
              setState(() => _followUser = false);
              _centerOn(sena.punto, zoom: kStreetZoom);
            },
          ),
        ],
      if (routeService.loadingRoute) ...[
        const SizedBox(height: AppSpacing.md),
        MapOverlayCard(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: AppSpacing.md),
              Flexible(
                child: Text(
                  l10n.calculatingRoute,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ],
          ),
        ),
      ],
    ];
  }

  Widget _recenterButton(AppLocalizations l10n) {
    final scheme = Theme.of(context).colorScheme;
    // Mantiene la misma escala compacta que los botones de capas y brújula.
    final button = FloatingActionButton.small(
      heroTag: 'recenter',
      tooltip: _followUser ? l10n.recenterActive : l10n.recenterInactive,
      backgroundColor: _followUser ? scheme.primaryContainer : null,
      foregroundColor: _followUser ? scheme.onPrimaryContainer : null,
      onPressed: _recenter,
      child: Icon(_followUser ? Icons.my_location : Icons.location_searching),
    );

    return prefs.animationsEnabled
        ? ScaleTransition(scale: _centerScale, child: button)
        : button;
  }

  Widget? _locationNotice(AppLocalizations l10n) {
    return switch (location.issue) {
      LocationIssue.none => null,
      LocationIssue.disabledByPreference => InlineNotice(
        icon: Icons.location_disabled,
        message: l10n.locationDisabledByPreference,
        actionLabel: l10n.preferencesTitle,
        onAction: () =>
            MainNavigationController.instance.openPreferences(context),
      ),
      LocationIssue.serviceDisabled => InlineNotice(
        icon: Icons.location_off_outlined,
        message: l10n.locationOffMessage,
        actionLabel: l10n.openSettings,
        onAction: location.openLocationSettings,
      ),
      LocationIssue.denied => InlineNotice(
        icon: Icons.lock_outline,
        message: l10n.locationDeniedMessage,
        actionLabel: l10n.openSettings,
        onAction: location.openAppSettings,
      ),
    };
  }
}

// ---------------------------------------------------------------------------
// Lo que se dibuja sobre el mapa
// ---------------------------------------------------------------------------

/// Vista cartográfica del pasajero.
///
/// Se suscribe directamente a las fuentes de alta frecuencia (GPS y flota en
/// vivo) para actualizar el lienzo de [AppMap] sin reconstruir los controles
/// flotantes de la pantalla principal.
class _MapaPasajero extends StatelessWidget {
  const _MapaPasajero({
    required this.controller,
    required this.style,
    required this.lineas,
    required this.centroMapa,
    required this.colectivoSeleccionadoUid,
    required this.linea,
    required this.sentido,
    required this.viaje,
    required this.destino,
    required this.senas,
    required this.sentidoSena,
    required this.onMapReady,
    required this.onCameraIdle,
    required this.onBearingChanged,
    required this.onUserGesture,
    required this.onTapColectivo,
    required this.onTapVariante,
    required this.onTapSentido,
  });

  final AppMapController controller;
  final MapStyle style;

  /// Líneas activas de la garita pública.
  final List<Recorrido> lineas;

  /// Último centro de la cámara cuando el usuario explora el mapa sin GPS.
  final LatLng? centroMapa;

  /// UID del colectivo tocado para mantenerlo visible en Modo Foco.
  final String? colectivoSeleccionadoUid;

  /// La línea en foco, si el usuario tocó un colectivo o eligió un recorrido.
  final Recorrido? linea;

  /// Sentido de [linea] a dibujar, o `null` para los dos.
  final Sentido? sentido;
  final LineSuggestion? viaje;
  final PlaceResult? destino;

  /// Los puntos de seña de [linea] y el sentido elegido.
  final List<PuntoDeSena> senas;
  final Sentido? sentidoSena;

  final VoidCallback onMapReady;
  final ValueChanged<LatLng> onCameraIdle;
  final ValueChanged<double> onBearingChanged;
  final VoidCallback onUserGesture;
  final ValueChanged<ColectivoActivo> onTapColectivo;
  final ValueChanged<Recorrido> onTapVariante;
  final ValueChanged<Sentido> onTapSentido;

  @override
  Widget build(BuildContext context) {
    final location = LocationService.instance;
    final auth = AuthService.instance;
    final turno = TurnoService.instance;
    final telemetria = FirebaseTelemetriaService.instance;
    final route = RouteService.instance;
    final prefs = PreferencesService.instance;
    final nav = MainNavigationController.instance;

    return ListenableBuilder(
      listenable: Listenable.merge([
        location,
        auth,
        turno,
        telemetria.state,
        route,
        prefs,
        nav,
      ]),
      builder: (context, _) {
        final l10n = AppLocalizations.of(context)!;
        final status = AppStatusColors.of(context);
        final scheme = Theme.of(context).colorScheme;
        final position = location.position;
        final destination = route.destination;

        // El chofer en turno ya aparece como su propio colectivo: un punto azul
        // encima sería un segundo marcador para la misma persona. Fuera de
        // turno, en cambio, sí ve dónde está.
        final verPosicion =
            position != null && !(auth.isColectivero && turno.enTurno);

        final ahora = telemetria.serverNow();
        final linea = this.linea;
        final viaje = this.viaje;
        final destino = this.destino;
        final centroProximidad = position ?? centroMapa ?? kQuilpueCenter;

        // En Modo Radar (sin línea seleccionada): colectivos en un radio de
        // 1 km. En Modo Foco (con línea seleccionada): colectivos de esa misma
        // línea en un radio del doble (2 km).
        final colectivos = colectivosEnRadio(
          telemetria.state.value.colectivos,
          centroProximidad,
          radioKm: linea != null
              ? kRadioLineaSeleccionadaKm
              : kRadioRutasCercanasKm,
          recorridoId: linea?.id,
          incluirUid: colectivoSeleccionadoUid,
        );

        // En Modo Radar se cargan automáticamente las rutas de los colectivos
        // cercanos (dentro de 1 km); si entra uno nuevo se carga su línea, y si
        // sale desaparece.
        final rutasCercanas = linea == null && viaje == null
            ? recorridosDeColectivos(
                colectivos,
                lineas,
                centro: centroProximidad,
              )
            : const <Recorrido>[];

        final senaElegida = senas
            .where((s) => s.sentido == sentidoSena)
            .firstOrNull;
        void avisar(String texto) => ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(texto)));
        return AppMap(
          controller: controller,
          initialCenter: position ?? kQuilpueCenter,
          style: style,
          onMapReady: onMapReady,
          onCameraIdle: onCameraIdle,
          onUserGesture: onUserGesture,
          onBearingChanged: onBearingChanged,
          lines: [
            // Modo Radar (1 km): dibuja las líneas de los colectivos cercanos.
            if (linea == null && viaje == null)
              for (final r in rutasCercanas)
                ...recorridoLines(
                  r,
                  status,
                  badge: true,
                  arrows: false,
                  onTap: () => onTapVariante(r),
                ),
            // Modo Foco (vehículo o línea seleccionada): sólo esa línea, con
            // flechas e insignias. Sin viaje, sus dos sentidos, con el del
            // punto de seña elegido resaltado; en un viaje, su sentido, con el
            // tramo que se recorre arriba del colectivo resaltado.
            if (linea != null)
              ...recorridoLines(
                linea,
                status,
                sentido: sentido,
                destacado: viaje == null ? sentidoSena : null,
                tramo: viaje == null
                    ? null
                    : (desde: viaje.metrosSubida, hasta: viaje.metrosBajada),
                badge: true,
                arrows: true,
              ),
            // Ruta a pie hacia el punto de subida, punteada y con color propio
            // para distinguirla del trazado vehicular y del marcador de posición.
            if (destination != null && route.routePoints.isNotEmpty)
              MapLine(
                points: route.routePoints,
                width: 5,
                color: status.routeLine,
                borderColor: status.routeLineCasing,
                borderWidth: 1.5,
                dotted: true,
              ),
          ],
          // Halo de precisión horizontal reportada por el GPS.
          circles: [
            if (verPosicion)
              MapCircle(
                center: position,
                radiusMeters: (location.accuracy ?? 30).clamp(10, 200),
                color: status.userLocation.withValues(alpha: 0.15),
                borderColor: status.userLocation.withValues(alpha: 0.5),
                borderWidth: 2,
              ),
          ],
          // El pulso tipo radar marca dónde hacerle la seña al colectivo, y
          // respeta la preferencia "Animaciones".
          pulse: !prefs.animationsEnabled
              ? null
              : viaje != null
              ? MapPulse(
                  point: viaje.subida,
                  color: Color(viaje.recorrido.colorValue),
                  fromRadius: 20,
                  toRadius: 44,
                )
              : senaElegida != null
              ? MapPulse(
                  point: senaElegida.punto,
                  color: Color(senaElegida.recorrido.colorValue),
                  fromRadius: 16,
                  toRadius: 38,
                )
              : null,
          // Los colectivos: autos que giran y se deslizan, salvo sin
          // "Animaciones" o mientras se mira otra pestaña.
          vehicles: [
            for (final colectivo in colectivos)
              colectivoMarker(
                colectivo,
                isMe: auth.isColectivero && colectivo.uid == auth.uid,
                offline: colectivo.seemsOffline(ahora),
                primary: scheme.primary,
                l10n: l10n,
                linea: lineaDeColectivo(colectivo),
                onTap: () => onTapColectivo(colectivo),
              ),
          ],
          animateVehicles:
              prefs.animationsEnabled && nav.destination == AppDestination.mapa,
          markers: [
            // Dónde empieza y dónde termina la línea elegida, debajo de todo
            // lo demás. En un viaje no: ahí importan la subida y la bajada.
            if (linea != null && viaje == null)
              for (final (i, terminal) in PuntosDeSena.terminales(
                linea,
              ).indexed)
                _terminal(terminal, i, linea, scheme, l10n),
            // Bandera del destino final buscado: la dirección a la que el
            // usuario quiere llegar caminando después de bajarse.
            if (destino != null)
              MapMarker(
                id: 'destino',
                point: destino.location,
                icon: MarkerIcon.glyph(
                  glyph: Icons.flag,
                  glyphSize: 34,
                  color: scheme.primary,
                  glyphShadows: const [
                    Shadow(color: Color(0x80000000), blurRadius: 6),
                  ],
                  tapTarget: AppSpacing.minTapTarget,
                ),
                semanticLabel: destino.name,
                // Hacía de tooltip: el nombre del destino al tocarlo.
                onTap: () => avisar(destino.name),
              ),
            // Dónde subirse y dónde bajarse, con el color de la línea.
            if (viaje != null) ...[
              _parada(
                viaje.subida,
                id: 'subida',
                glyph: Icons.hail,
                color: Color(viaje.recorrido.colorValue),
                label: l10n.boardHere,
                status: status,
                onTap: () => avisar(l10n.boardHere),
              ),
              _parada(
                viaje.bajada,
                id: 'bajada',
                glyph: Icons.directions_walk,
                color: Color(viaje.recorrido.colorValue),
                label: l10n.alightHere,
                status: status,
                onTap: () => avisar(l10n.alightHere),
              ),
            ],

            // La línea elegida: el punto de seña de cada sentido (uno solo si
            // los dos pasan por el mismo lugar).
            for (final (sena, ambos) in _senasAMostrar(senas, sentidoSena))
              _iconoSentido(
                sena,
                ambos: ambos,
                elegido: ambos || sena.sentido == sentidoSena,
                l10n: l10n,
              ),
            if (verPosicion)
              MapMarker(
                id: 'yo',
                point: position,
                icon: MarkerIcon.circle(
                  diameter: 24,
                  color: status.userLocation,
                  borderColor: status.markerBorder,
                  borderWidth: 3,
                  shadow: const BoxShadow(
                    color: Color(0x40000000),
                    blurRadius: 4,
                    offset: Offset(0, 2),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  /// Un extremo de la línea elegida: un anillo de su color sobre el trazado y,
  /// debajo, el nombre que le da la cartola ("Alto el Yugo", "Centro"). Sin
  /// cartola, el anillo solo.
  MapMarker _terminal(
    Terminal terminal,
    int i,
    Recorrido linea,
    ColorScheme scheme,
    AppLocalizations l10n,
  ) {
    final anillo = MarkerIcon.circle(
      diameter: 16,
      color: const Color(0xFFFFFFFF),
      borderColor: Color(linea.colorValue).withValues(alpha: 1),
      borderWidth: 4,
      shadow: const BoxShadow(
        color: Color(0x59000000),
        blurRadius: 4,
        offset: Offset(0, 1),
      ),
    );
    final nombre = switch (terminal.lugar) {
      null => null,
      DestinoSena(esCentro: true) => l10n.terminalCenter,
      DestinoSena(:final lugar) => lugar,
    };
    return MapMarker(
      id: 'terminal_$i',
      point: terminal.punto,
      // La etiqueta, en negro o en blanco según el tema: no es del color de
      // la línea, para que no se confunda con un punto de seña.
      icon: nombre == null
          ? anillo
          : TaggedIcon(
              base: anillo,
              tag: nombre,
              tagColor: scheme.inverseSurface,
              tagTextColor: scheme.onInverseSurface,
            ),
    );
  }

  MapMarker _iconoSentido(
    PuntoDeSena sena, {
    required bool ambos,
    required bool elegido,
    required AppLocalizations l10n,
  }) {
    final color = Color(sena.recorrido.colorValue).withValues(alpha: 1);
    final hacia = ambos ? l10n.hailBothWays : _destinoTexto(sena, l10n);
    return MapMarker(
      id: 'sena_${sena.sentido.name}',
      point: sena.punto,
      // El sentido elegido dice hacia dónde va; el otro, compacto y más
      // tenue, para que dos íconos cerca no se tapen (el detalle está en la
      // tarjeta). Se puede tocar para cambiar.
      icon: HailBadge(
        label: PuntosDeSena.etiqueta(sena.recorrido),
        detail: elegido ? hacia : '',
        color: color,
        textColor: AppStatusColors.onColorFor(color),
      ),
      opacity: elegido ? 1 : 0.75,
      semanticLabel: '${l10n.hailHere}: $hacia',
      onTap: () => onTapSentido(sena.sentido),
    );
  }

  MapMarker _parada(
    LatLng punto, {
    required String id,
    required IconData glyph,
    required Color color,
    required String label,
    required AppStatusColors status,
    required VoidCallback onTap,
  }) {
    return MapMarker(
      id: id,
      point: punto,
      icon: MarkerIcon.circle(
        diameter: 32,
        color: color,
        borderColor: status.markerBorder,
        borderWidth: 3,
        glyph: glyph,
        glyphColor: AppStatusColors.onColorFor(color),
        glyphSize: 18,
        shadow: const BoxShadow(
          color: Color(0x59000000),
          blurRadius: 6,
          offset: Offset(0, 2),
        ),
        tapTarget: AppSpacing.minTapTarget,
      ),
      semanticLabel: label,
      onTap: onTap,
    );
  }
}

// ---------------------------------------------------------------------------
// Widgets auxiliares
// ---------------------------------------------------------------------------

/// Ficha de detalle de un colectivo seleccionado en el mapa.
class _ColectivoSheet extends StatelessWidget {
  const _ColectivoSheet({required this.colectivo, required this.ahora});

  final ColectivoActivo colectivo;

  /// Hora del servidor al abrir la ficha.
  final DateTime ahora;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final status = AppStatusColors.of(context);
    final offline = colectivo.seemsOffline(ahora);
    final id = colectivo.recorridoId;
    final linea = id == null ? null : RecorridosService.instance.byId(id);
    final estadoColor = linea != null
        ? Color(linea.colorValue).withValues(alpha: 1)
        : status.disponible;
    final antiguedad = colectivo.antiguedad(ahora);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.sm,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: estadoColor.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.directions_car,
                    color: estadoColor,
                    size: 28,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.colectivoTitle(
                          formatPatente(colectivo.idVehiculo),
                        ),
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        colectivo.recorridoNombre ?? l10n.colectivoNoRoute,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              children: [
                MetricChip(
                  icon: Icons.circle,
                  label: l10n.turnoOn,
                  color: status.disponible,
                ),
                if (offline)
                  MetricChip(
                    icon: Icons.signal_cellular_off,
                    label: l10n.colectivoNoSignal,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
              ],
            ),
            if (antiguedad != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                l10n.colectivoLastSignal(formatAgo(antiguedad, l10n)),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
          ],
        ),
      ),
    );
  }
}

/// Hacia dónde va un punto de seña: "Hacia Alto el Yugo", "Hacia el centro"
/// o, sin cartola, "Ida" / "Vuelta".
String _destinoTexto(PuntoDeSena sena, AppLocalizations l10n) {
  final destino = sena.destino;
  if (destino == null) return sentidoLabel(sena.sentido, l10n);
  if (destino.esCentro) return l10n.hailTowardCenter;
  return l10n.hailToward(destino.lugar!);
}

/// Los puntos de seña a marcar, con un booleano que dice si ese punto sirve
/// para los dos sentidos:
/// - a menos de 30 m uno del otro (la misma calle), uno solo, "ida y regreso";
/// - a menos de 150 m (veredas opuestas de una avenida), sólo el del
///   [sentido] elegido: los dos íconos se taparían, y el otro sentido sigue a
///   un toque en la tarjeta;
/// - más lejos, los dos.
List<(PuntoDeSena, bool)> _senasAMostrar(
  List<PuntoDeSena> senas,
  Sentido? sentido,
) {
  if (senas.length == 2) {
    final metros = const Distance().as(
      LengthUnit.Meter,
      senas[0].punto,
      senas[1].punto,
    );
    if (metros < 30) {
      final cercana = senas[0].metros <= senas[1].metros ? senas[0] : senas[1];
      return [(cercana, true)];
    }
    if (metros < 150) {
      return [
        for (final s in senas)
          if (s.sentido == sentido) (s, false),
      ];
    }
  }
  return [for (final s in senas) (s, false)];
}

/// La línea elegida (sin viaje): dónde hacerle seña, cuánto caminar hasta ahí
/// y, si el otro sentido pasa por otra calle, el botón para tomarlo en ese.
class _SenaCard extends StatelessWidget {
  const _SenaCard({
    required this.linea,
    required this.senas,
    required this.sentido,
    this.colectivoSeleccionado,
    required this.metrosDesdeTi,
    required this.routeInfo,
    required this.onClose,
    required this.onSwitch,
    required this.onTap,
  });

  final Recorrido linea;
  final List<PuntoDeSena> senas;
  final Sentido? sentido;
  final ColectivoActivo? colectivoSeleccionado;

  /// A cuánto queda del pasajero el punto de seña elegido (`null` sin GPS).
  final double? metrosDesdeTi;
  final RouteResult? routeInfo;
  final VoidCallback onClose;
  final ValueChanged<Sentido> onSwitch;

  /// Al tocar la tarjeta, el mapa se centra en el punto de seña.
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final color = Color(linea.colorValue).withValues(alpha: 1);
    final elegida = senas.where((s) => s.sentido == sentido).firstOrNull;
    final mostrar = _senasAMostrar(senas, sentido);
    final ambos = mostrar.length == 1 && mostrar.first.$2;
    final otra = ambos
        ? null
        : senas.where((s) => s.sentido != sentido).firstOrNull;

    return MapOverlayCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: color,
                child: Text(
                  linea.sigla,
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: AppStatusColors.onColorFor(color),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      linea.nombre,
                      style: theme.textTheme.titleSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (elegida != null)
                      Text(
                        '${l10n.hailHere} · '
                        '${ambos ? l10n.hailBothWays : _destinoTexto(elegida, l10n)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                tooltip: l10n.clearLine,
                onPressed: onClose,
              ),
            ],
          ),
          if (elegida != null) ...[
            const SizedBox(height: AppSpacing.sm),
            // Wrap y no Row: con la fuente grande pasan a otra línea.
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (colectivoSeleccionado case final col?)
                  MetricChip(
                    icon: Icons.directions_car,
                    label: l10n.colectivoTitle(formatPatente(col.idVehiculo)),
                    color: color,
                  ),
                // Cerca, lo que se camina; lejos (o sin GPS), a cuánto pasa.
                if (routeInfo case final info?)
                  MetricChip(
                    icon: Icons.straighten,
                    label: formatDistance(info.distanceMeters, l10n),
                    color: scheme.primary,
                  )
                else if (metrosDesdeTi case final metros?)
                  MetricChip(
                    icon: Icons.straighten,
                    label: l10n.linesPassesAt(
                      formatDistanciaCorta(metros, l10n),
                    ),
                    color: scheme.primary,
                  ),
                if (routeInfo case final info?)
                  MetricChip(
                    icon: Icons.directions_walk,
                    label: formatDurationSeconds(info.durationSeconds, l10n),
                    color: scheme.tertiary,
                  ),
                if (otra != null)
                  ActionChip(
                    avatar: const Icon(Icons.swap_horiz, size: 18),
                    label: Text(_destinoTexto(otra, l10n)),
                    tooltip: l10n.hailSwitch,
                    visualDensity: VisualDensity.compact,
                    onPressed: () => onSwitch(otra.sentido),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Tarjeta del viaje armado: qué línea tomar y en qué sentido, cuánto caminar
/// hasta ella y cuánto desde la bajada.
class _TripCard extends StatelessWidget {
  const _TripCard({
    required this.viaje,
    required this.routeInfo,
    required this.onClose,
    required this.onTap,
  });

  final LineSuggestion viaje;
  final RouteResult? routeInfo;
  final VoidCallback onClose;

  /// Al tocar la tarjeta, el mapa se centra en el punto de subida.
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final linea = viaje.recorrido;

    return MapOverlayCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: Color(linea.colorValue),
                child: const Icon(
                  Icons.directions_car,
                  size: 16,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${linea.nombre} · ${sentidoLabel(viaje.sentido, l10n)}',
                      style: theme.textTheme.titleSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      l10n.tripBoardHint,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: onClose,
                tooltip: l10n.closeRoute,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          // Wrap y no Row: con la fuente al 140% las métricas pasan a una
          // segunda línea en vez de desbordar.
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              // Mientras se calcula la ruta a pie, la distancia en línea
              // recta hasta la línea.
              MetricChip(
                icon: Icons.straighten,
                label: formatDistance(
                  routeInfo?.distanceMeters ?? viaje.metrosHastaLinea,
                  l10n,
                ),
                color: scheme.primary,
              ),
              if (routeInfo case final info?)
                MetricChip(
                  icon: Icons.directions_walk,
                  label: formatDurationSeconds(info.durationSeconds, l10n),
                  color: scheme.tertiary,
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            l10n.suggestWalkFromLine(
              formatDistance(viaje.metrosDesdeLinea, l10n),
            ),
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            l10n.tapToSeeBoarding,
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.primary,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }
}
