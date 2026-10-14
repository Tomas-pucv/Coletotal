import 'dart:async';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import 'package:taxi1/config/map_config.dart';
import 'package:taxi1/l10n/app_localizations.dart';
import 'package:taxi1/models/colectivo_activo.dart';
import 'package:taxi1/models/place_result.dart';
import 'package:taxi1/models/recorrido.dart';
import 'package:taxi1/navigation/app_destination.dart';
import 'package:taxi1/screens/main_screen.dart';
import 'package:taxi1/services/auth_service.dart';
import 'package:taxi1/services/firebase_telemetria_service.dart';
import 'package:taxi1/services/line_planner.dart';
import 'package:taxi1/services/location_service.dart';
import 'package:taxi1/services/preferences_service.dart';
import 'package:taxi1/services/recorridos_service.dart';
import 'package:taxi1/services/route_service.dart';
import 'package:taxi1/services/turno_service.dart';
import 'package:taxi1/theme/app_colors.dart';
import 'package:taxi1/theme/app_spacing.dart';
import 'package:taxi1/utils/distance_format.dart';
import 'package:taxi1/utils/estado_format.dart';
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

class _MapScreenState extends State<MapScreen> with TickerProviderStateMixin {
  final _mapController = AppMapController();

  bool _followUser = true;
  bool _mapReady = false;

  /// Hacia dónde mira el mapa (grados desde el norte). Cambia en cada cuadro
  /// mientras se rota: sólo lo escucha la brújula, no toda la pantalla.
  final _rumbo = ValueNotifier<double>(0);

  final routeService = RouteService.instance;
  final prefs = PreferencesService.instance;
  final recorridos = RecorridosService.instance;
  final location = LocationService.instance;

  /// Dirección buscada por el usuario, si la hay. Es el destino *final* del
  /// viaje, distinto del punto de la línea donde se toma el colectivo.
  PlaceResult? _destino;

  /// El viaje elegido para llegar a [_destino]: qué línea, en qué sentido,
  /// dónde subirse y dónde bajarse.
  LineSuggestion? _viaje;

  late final AnimationController _centerBtnController;
  late final Animation<double> _centerScale;

  @override
  void initState() {
    super.initState();

    // Sólo lo que cambia la estructura de la pantalla la reconstruye entera.
    // La posición del GPS y la flota en vivo las escucha `_MapaPasajero`:
    // antes cada movimiento de cada colectivo volvía a construir también todos
    // los controles flotantes.
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

  /// Cambió la línea dibujada. Si la eligieron en la pestaña Líneas, se
  /// muestra entera; si el viaje armado dependía de otra línea (o de una que
  /// el administrador borró), el viaje se cierra.
  void _onRecorridosChanged() {
    final linea = recorridos.selected;
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
    if (mounted) setState(() {});
  }

  /// Mueve la cámara para que [puntos] quepan en la parte del mapa que no
  /// tapan el buscador ni las tarjetas de abajo.
  Future<void> _encuadrar(List<LatLng> puntos) async {
    if (!_mapReady || puntos.isEmpty) return;
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

  /// El usuario eligió una dirección en el buscador.
  ///
  /// A partir de ahí la app no pregunta "¿qué colectivo tomo?", sino que lo
  /// propone: cruza la posición del usuario con las líneas de la garita y
  /// ordena las formas de llegar por lo que hay que caminar (ver
  /// [LinePlanner]). Los colectivos paran donde se les hace la seña, así que
  /// la subida es el punto de la línea más cercano al usuario.
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

    // El viaje se arma antes de dibujar su línea: el listener de recorridos
    // cierra cualquier viaje cuya línea deja de estar dibujada.
    setState(() => _viaje = elegido);
    recorridos.select(elegido.recorrido, sentido: elegido.sentido);
    final subida = WalkTarget(location: elegido.subida, label: l10n.boardHere);
    routeService.setDestination(subida);
    // Desde donde el usuario está *ahora*: elegir en la hoja puede tomar un
    // rato, y antes la ruta salía del primer punto GPS de la sesión.
    final desde = location.position ?? origin;
    unawaited(
      _encuadrar([desde, elegido.subida, elegido.bajada, place.location]),
    );
    await routeService.fetchRoute(desde, subida);
  }

  void _clearDestino() {
    setState(() {
      _destino = null;
      _viaje = null;
    });
    routeService.clearDestination();
    recorridos.clearSelection();
  }

  Future<void> _recenter() async {
    final position = location.position;
    if (position == null) {
      // Sin posición el botón no puede centrar: en vez de no hacer nada,
      // reintenta obtenerla (por ejemplo, tras encender el GPS).
      await location.retry();
      return;
    }
    _centerBtnController.forward(from: 0);
    await _centerOn(position, zoom: kStreetZoom);
    _centerBtnController.reverse();
    if (mounted) setState(() => _followUser = true);
  }

  /// Respeta la preferencia "Animaciones", que este botón ignoraba (ver la
  /// auditoría del 5 de octubre).
  Future<void> _reorient() =>
      _mapController.resetBearing(animate: prefs.animationsEnabled);

  Future<void> _onTapColectivo(ColectivoActivo colectivo) async {
    // Si informa una línea, se dibuja. Salvo con un viaje armado: dibujar otra
    // línea lo cerraría, y sólo se quería ver la ficha del colectivo.
    if (_viaje == null) {
      if (colectivo.recorridoId case final id?) {
        final linea = recorridos.byId(id);
        if (linea != null) recorridos.select(linea);
      }
    }
    if (!mounted) return;

    final ahora = FirebaseTelemetriaService.instance.serverNow();
    await showModalBottomSheet<void>(
      context: context,
      builder: (context) => _ColectivoSheet(colectivo: colectivo, ahora: ahora),
    );
  }

  /// Tocaron una línea o su insignia en el mapa: se elige, sin mover la
  /// cámara (ya está a la vista). Con un viaje armado sólo se dice cuál es:
  /// elegir otra cerraría el viaje.
  void _onTapLinea(Recorrido linea) {
    if (_viaje != null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(linea.nombre)));
      return;
    }
    recorridos.select(linea);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    final linea = recorridos.selected;
    final viaje = _viaje;
    final mapStyle = MapStyle.fromPref(prefs.mapType);

    return Scaffold(
      body: Stack(
        children: [
          _MapaPasajero(
            controller: _mapController,
            style: mapStyle,
            lineas: recorridos.publicas,
            linea: linea,
            sentido: recorridos.selectedSentido,
            viaje: viaje,
            destino: _destino,
            onMapReady: _onMapReady,
            onBearingChanged: (rumbo) => _rumbo.value = rumbo,
            onUserGesture: () {
              if (_followUser) setState(() => _followUser = false);
            },
            onTapColectivo: _onTapColectivo,
            onTapLinea: _onTapLinea,
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
        // Buscador de direcciones arriba del todo, como en cualquier app de
        // mapas: es el punto de partida real del pasajero, que sabe a dónde va
        // y no qué paradero tomar. El mapa no tiene AppBar (la cartografía
        // ocupa la pantalla entera), así que el menú va dentro de la barra.
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
      // Qué línea se está viendo dibujada, con su color y una X. Con un viaje
      // armado no hace falta: la tarjeta del viaje ya dice qué línea es.
      if (_viaje == null)
        if (recorridos.selected case final linea?) ...[
          const SizedBox(height: AppSpacing.md),
          MapOverlayCard(
            child: Row(
              children: [
                Icon(Icons.directions_car, color: Color(linea.colorValue)),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    l10n.lineOnMap(linea.nombre),
                    style: Theme.of(context).textTheme.bodyMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: l10n.clearLine,
                  onPressed: recorridos.clearSelection,
                ),
              ],
            ),
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
    // Del mismo tamaño que los demás botones del mapa: antes era el único
    // grande y tapaba más mapa del que hacía falta.
    final button = FloatingActionButton.small(
      heroTag: 'recenter',
      tooltip: _followUser ? l10n.recenterActive : l10n.recenterInactive,
      // El seguimiento activo se marca con el color primario en vez de
      // invertir el tema a mano con blanco/negro literales.
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

/// El mapa del pasajero con todo lo que lleva encima.
///
/// Escucha por su cuenta lo que cambia seguido (el GPS y la flota en vivo):
/// antes cada movimiento de cada colectivo reconstruía también los controles
/// flotantes. [AppMap] sólo le reenvía a MapLibre lo que cambió.
class _MapaPasajero extends StatelessWidget {
  const _MapaPasajero({
    required this.controller,
    required this.style,
    required this.lineas,
    required this.linea,
    required this.sentido,
    required this.viaje,
    required this.destino,
    required this.onMapReady,
    required this.onBearingChanged,
    required this.onUserGesture,
    required this.onTapColectivo,
    required this.onTapLinea,
  });

  final AppMapController controller;
  final MapStyle style;

  /// Las líneas que ve el pasajero, dibujadas siempre.
  final List<Recorrido> lineas;

  /// La elegida, resaltada sobre las demás.
  final Recorrido? linea;

  /// Sentido de [linea] a dibujar, o `null` para los dos.
  final Sentido? sentido;
  final LineSuggestion? viaje;
  final PlaceResult? destino;
  final VoidCallback onMapReady;
  final ValueChanged<double> onBearingChanged;
  final VoidCallback onUserGesture;
  final ValueChanged<ColectivoActivo> onTapColectivo;
  final ValueChanged<Recorrido> onTapLinea;

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
        final colectivos = colectivosVisibles(
          telemetria.state.value.colectivos,
          position ?? kQuilpueCenter,
        );

        final linea = this.linea;
        final viaje = this.viaje;
        final destino = this.destino;
        void avisar(String texto) => ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(texto)));
        return AppMap(
          controller: controller,
          initialCenter: position ?? kQuilpueCenter,
          style: style,
          onMapReady: onMapReady,
          onUserGesture: onUserGesture,
          onBearingChanged: onBearingChanged,
          // Las flechas avanzan sólo con el mapa a la vista: la pestaña sigue
          // viva detrás de las otras.
          animateArrows:
              prefs.animationsEnabled && nav.destination == AppDestination.mapa,
          lines: [
            // Las líneas de colectivos, con la elegida encima. Van debajo de la
            // ruta a pie: son contexto ("por aquí pasa la 1"), no la
            // indicación que el usuario tiene que seguir ahora.
            ...lineasDelMapa(
              lineas,
              status,
              elegida: linea,
              sentido: sentido,
              onTap: onTapLinea,
            ),
            // La ruta a pie hasta la línea, punteada: se distingue de un
            // vistazo de la línea continua del colectivo.
            if (destination != null && route.routePoints.isNotEmpty)
              MapLine(
                points: route.routePoints,
                width: 5,
                // Deja de ser `scheme.primary`, que era el mismo azul del punto
                // "tú estás aquí".
                color: status.routeLine,
                borderColor: status.routeLineCasing,
                borderWidth: 1.5,
                dotted: true,
              ),
          ],
          // Halo de precisión real del GPS (antes eran 50 px fijos).
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
          pulse: viaje != null && prefs.animationsEnabled
              ? MapPulse(
                  point: viaje.subida,
                  color: Color(viaje.recorrido.colorValue),
                  fromRadius: 20,
                  toRadius: 44,
                )
              : null,
          markers: [
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
            for (final colectivo in colectivos)
              colectivoMarker(
                colectivo,
                isMe: auth.isColectivero && colectivo.uid == auth.uid,
                offline: colectivo.seemsOffline(ahora),
                status: status,
                primary: scheme.primary,
                l10n: l10n,
                onTap: () => onTapColectivo(colectivo),
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

/// Ficha de un colectivo tocado en el mapa.
///
/// Antes sus textos estaban escritos a mano en la pantalla, fuera del ARB.
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
    final estadoColor = status.forEstado(colectivo.estado);
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
                  label: estadoLabel(colectivo.estado, l10n, detallado: true),
                  color: estadoColor,
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
