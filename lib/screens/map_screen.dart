import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_animations/flutter_map_animations.dart';
import 'package:latlong2/latlong.dart';

import 'package:taxi1/config/map_config.dart';
import 'package:taxi1/l10n/app_localizations.dart';
import 'package:taxi1/models/bus_stop.dart';
import 'package:taxi1/models/colectivo_activo.dart';
import 'package:taxi1/models/place_result.dart';
import 'package:taxi1/screens/main_screen.dart';
import 'package:taxi1/services/auth_service.dart';
import 'package:taxi1/services/firebase_telemetria_service.dart';
import 'package:taxi1/services/location_service.dart';
import 'package:taxi1/services/preferences_service.dart';
import 'package:taxi1/services/recorridos_service.dart';
import 'package:taxi1/services/route_service.dart';
import 'package:taxi1/services/stop_history_service.dart';
import 'package:taxi1/services/stop_planner.dart';
import 'package:taxi1/services/stops_service.dart';
import 'package:taxi1/services/turno_service.dart';
import 'package:taxi1/theme/app_colors.dart';
import 'package:taxi1/theme/app_spacing.dart';
import 'package:taxi1/utils/distance_format.dart';
import 'package:taxi1/utils/estado_format.dart';
import 'package:taxi1/utils/patente.dart';
import 'package:taxi1/widgets/app_tile_layer.dart';
import 'package:taxi1/widgets/map_overlay_card.dart';
import 'package:taxi1/widgets/map_search_bar.dart';
import 'package:taxi1/widgets/map_style_sheet.dart';
import 'package:taxi1/widgets/metric_chip.dart';
import 'package:taxi1/widgets/paradero_sheet.dart';
import 'package:taxi1/widgets/state_views.dart';
import 'package:taxi1/widgets/stop_suggestions_sheet.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> with TickerProviderStateMixin {
  late final AnimatedMapController _mapController;

  bool _followUser = true;
  bool _showBusStops = true;
  bool _mapReady = false;

  final routeService = RouteService.instance;
  final prefs = PreferencesService.instance;
  final recorridos = RecorridosService.instance;
  final location = LocationService.instance;

  /// Dirección buscada por el usuario, si la hay. Es el destino *final* del
  /// viaje, distinto del paradero (que es sólo dónde se toma el colectivo).
  PlaceResult? _destino;

  late final AnimationController _centerBtnController;
  late final Animation<double> _centerScale;

  @override
  void initState() {
    super.initState();

    _mapController = AnimatedMapController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeInOut,
    );

    // Sólo lo que cambia la estructura de la pantalla la reconstruye entera.
    // La posición del GPS, los paraderos y la flota en vivo los escuchan sus
    // propias capas (`_UserLocationLayer`, `_StopsLayer`, `_ColectivosLayer`):
    // antes cada movimiento de cada colectivo volvía a construir las teselas,
    // todos los paraderos y todos los controles flotantes.
    prefs.addListener(_onChanged);
    routeService.addListener(_onChanged);
    recorridos.addListener(_onChanged);
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
    recorridos.removeListener(_onChanged);
    location.removeListener(_onLocationChanged);
    _centerBtnController.dispose();
    _mapController.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
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
    if (_followUser && _mapReady) {
      _mapController.mapController.move(
        position,
        _mapController.mapController.camera.zoom,
      );
    }
  }

  void _onMapReady() {
    _mapReady = true;
    final position = location.position;
    if (_followUser && position != null) {
      _mapController.mapController.move(
        position,
        _mapController.mapController.camera.zoom,
      );
    }
  }

  /// Centra la cámara respetando la preferencia "Animaciones".
  Future<void> _centerOn(LatLng point, {double? zoom}) async {
    if (!_mapReady) return;
    if (prefs.animationsEnabled) {
      await _mapController.centerOnPoint(point, zoom: zoom);
    } else {
      _mapController.mapController.move(
        point,
        zoom ?? _mapController.mapController.camera.zoom,
      );
    }
  }

  /// El usuario eligió una dirección en el buscador.
  ///
  /// A partir de ahí la app no pregunta "¿qué paradero quieres?", sino que lo
  /// propone: cruza la posición del usuario con los recorridos de la garita y
  /// ordena los paraderos por lo que hay que caminar en total (ver
  /// [StopPlanner]).
  Future<void> _onDestinationSelected(PlaceResult place) async {
    final l10n = AppLocalizations.of(context)!;
    setState(() {
      _destino = place;
      _followUser = false;
    });
    unawaited(_centerOn(place.location, zoom: 15));

    final origin = location.position ?? routeService.origin;
    if (origin == null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(l10n.suggestLocationNeeded)));
      return;
    }

    final sugerencias = StopPlanner.suggest(
      user: origin,
      destino: place.location,
    );

    if (!mounted) return;
    final elegido = await showStopSuggestionsSheet(
      context,
      destino: place.name,
      suggestions: sugerencias,
    );
    if (elegido == null || !mounted) return;

    // El paradero elegido pasa a ser el destino de la ruta a pie, y su línea
    // se dibuja para que se vea a dónde lleva.
    recorridos.clearSelection();
    routeService.setDestination(elegido.stop);
    StopHistoryService.instance.record(elegido.stop);
    // Desde donde el usuario está *ahora*: elegir en la hoja puede tomar un
    // rato, y antes la ruta salía del primer punto GPS de la sesión.
    await routeService.fetchRoute(location.position ?? origin, elegido.stop);

    final linea = elegido.recorrido;
    if (linea != null && mounted) await recorridos.select(linea);
  }

  void _clearDestino() {
    setState(() => _destino = null);
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
    await _centerOn(position, zoom: 16.0);
    _centerBtnController.reverse();
    if (mounted) setState(() => _followUser = true);
  }

  Future<void> _reorient() => _mapController.animatedRotateReset();

  /// Tocar un paradero abre su ficha, igual que en la pestaña Paraderos: qué
  /// colectivos pasan por aquí, y desde ahí ver una línea o cómo llegar.
  Future<void> _onTapStop(BusStop stop) async {
    // Se registra en el historial al consultarlo, no sólo al rutear: abrir la
    // ficha ya es interactuar con el paradero, que es lo que ordena la lista
    // en modo "Recientes".
    StopHistoryService.instance.record(stop);
    // Sin esto, el siguiente punto del GPS devolvía la cámara al usuario y el
    // paradero tocado se salía de la pantalla.
    setState(() => _followUser = false);
    await _centerOn(stop.location, zoom: 16.0);
    if (!mounted) return;
    await showParaderoSheet(context, stop);
  }

  Future<void> _onTapColectivo(ColectivoActivo colectivo) async {
    // Si informa un recorrido, se ilumina su trazado. Sin esperar al trazado:
    // la ficha tiene que abrirse al instante.
    if (colectivo.recorridoId case final id?) {
      final linea = recorridos.byId(id);
      if (linea != null) unawaited(recorridos.select(linea));
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
    final status = AppStatusColors.of(context);

    final destination = routeService.destination;
    final linea = recorridos.selected;
    final trazado = recorridos.trazadoSeleccionado;

    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController.mapController,
            options: MapOptions(
              initialCenter: location.position ?? kQuilpueCenter,
              initialZoom: kInitialZoom,
              interactionOptions: const InteractionOptions(
                flags:
                    InteractiveFlag.drag |
                    InteractiveFlag.pinchMove |
                    InteractiveFlag.pinchZoom |
                    InteractiveFlag.doubleTapZoom |
                    InteractiveFlag.flingAnimation |
                    InteractiveFlag.rotate,
                enableMultiFingerGestureRace: true,
                rotationThreshold: 30.0,
              ),
              onMapReady: _onMapReady,
              onPositionChanged: (camera, hasGesture) {
                if (hasGesture && _followUser) {
                  setState(() => _followUser = false);
                }
              },
            ),
            children: [
              AppTileLayer(style: MapStyle.fromPref(prefs.mapType)),

              // Recorrido de una línea de colectivos. Va debajo de la ruta a
              // pie: es contexto ("por aquí pasa la 5"), no la indicación que
              // el usuario tiene que seguir ahora.
              if (linea != null && trazado.length > 1)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: trazado,
                      strokeWidth: 6.0,
                      color: Color(linea.colorValue).withValues(alpha: 0.85),
                      borderColor: status.routeLineCasing,
                      borderStrokeWidth: 1.5,
                    ),
                  ],
                ),

              // La ruta va antes que los marcadores para que no los tape.
              if (destination != null && routeService.routePoints.isNotEmpty)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: routeService.routePoints,
                      strokeWidth: 5.0,
                      // Deja de ser `scheme.primary`, que era el mismo azul del
                      // punto "tú estás aquí".
                      color: status.routeLine,
                      borderColor: status.routeLineCasing,
                      borderStrokeWidth: 1.5,
                    ),
                  ],
                ),

              // Bandera del destino final buscado. No es un paradero: es la
              // dirección a la que el usuario quiere llegar caminando después
              // de bajarse.
              if (_destino case final destino?)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: destino.location,
                      width: AppSpacing.minTapTarget,
                      height: AppSpacing.minTapTarget,
                      child: Tooltip(
                        message: destino.name,
                        child: Icon(
                          Icons.flag,
                          size: 34,
                          color: Theme.of(context).colorScheme.primary,
                          shadows: const [
                            Shadow(color: Color(0x80000000), blurRadius: 6),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),

              const _UserLocationLayer(dot: false),
              _ColectivosLayer(onTap: _onTapColectivo),
              const _UserLocationLayer(dot: true),
              if (_showBusStops) _StopsLayer(onTap: _onTapStop),
            ],
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
                    // Sólo con una ruta activa: paradero, distancia y tiempo
                    // a pie. Sin ruta no hay tarjeta abajo.
                    if (destination != null) ...[
                      const SizedBox(height: AppSpacing.md),
                      _StatusCard(
                        destination: destination,
                        routeInfo: routeService.routeInfo,
                        provider: routeService.activeProvider,
                        onClose: routeService.clearDestination,
                        onTap: () {
                          setState(() => _followUser = false);
                          _centerOn(destination.location, zoom: 16.0);
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
        // Primera fila: menú y buscador de direcciones, al estilo de cualquier
        // app de mapas. El buscador va arriba del todo porque es el punto de
        // partida real del pasajero: sabe a dónde va, no qué paradero tomar.
        Row(
          children: [
            // El mapa no tiene AppBar (la cartografía ocupa la pantalla
            // entera), así que el acceso al menú es este botón flotante.
            FloatingActionButton.small(
              heroTag: 'menu',
              tooltip: l10n.openMenu,
              onPressed: MainNavigationController.instance.openDrawer,
              child: const Icon(Icons.menu),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: MapSearchBar(
                onSelected: _onDestinationSelected,
                destinationLabel: _destino?.name,
                onCleared: _clearDestino,
              ),
            ),
          ],
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
              // Qué línea se está viendo dibujada, con su color y una X.
              if (recorridos.selected case final linea?) ...[
                MapOverlayCard(
                  child: Row(
                    children: [
                      if (recorridos.loadingTrazado)
                        const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      else
                        Icon(
                          Icons.directions_car,
                          color: Color(linea.colorValue),
                        ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Text(
                          recorridos.loadingTrazado
                              ? l10n.loadingLine
                              : l10n.lineOnMap(linea.nombre),
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
                const SizedBox(height: AppSpacing.sm),
              ],
              if (routeService.loadingRoute) ...[
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
                const SizedBox(height: AppSpacing.sm),
              ],
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
            FloatingActionButton.small(
              heroTag: 'reorient',
              tooltip: l10n.reorientMap,
              onPressed: _reorient,
              child: const Icon(Icons.explore),
            ),
            const SizedBox(height: AppSpacing.sm),
            FloatingActionButton.small(
              heroTag: 'toggle_stops',
              tooltip: _showBusStops ? l10n.hideStops : l10n.showStops,
              onPressed: () => setState(() => _showBusStops = !_showBusStops),
              child: Icon(
                _showBusStops ? Icons.location_on : Icons.location_off_outlined,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            // Cambiar entre calles y satélite es el ajuste que más se toca con
            // el mapa a la vista; tenerlo solo en Preferencias obligaba a salir
            // del mapa para volver a entrar.
            FloatingActionButton.small(
              heroTag: 'map_layers',
              tooltip: l10n.mapLayers,
              onPressed: () => showMapStyleSheet(context),
              child: const Icon(Icons.layers_outlined),
            ),
          ],
        ),
      ],
    );
  }

  Widget _recenterButton(AppLocalizations l10n) {
    final scheme = Theme.of(context).colorScheme;
    final button = FloatingActionButton(
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
// Capas del mapa que escuchan sus propios datos
// ---------------------------------------------------------------------------

/// Halo de precisión ([dot] en `false`) o punto azul del usuario.
///
/// Son dos capas y no una para que los colectivos queden entre ambas, como
/// estaban.
class _UserLocationLayer extends StatelessWidget {
  const _UserLocationLayer({required this.dot});

  final bool dot;

  @override
  Widget build(BuildContext context) {
    final location = LocationService.instance;
    final auth = AuthService.instance;
    final turno = TurnoService.instance;

    return ListenableBuilder(
      listenable: Listenable.merge([location, auth, turno]),
      builder: (context, _) {
        final position = location.position;
        // El chofer en turno ya aparece como su propio colectivo: un punto azul
        // encima sería un segundo marcador para la misma persona. Fuera de
        // turno, en cambio, sí ve dónde está.
        if (position == null || (auth.isColectivero && turno.enTurno)) {
          return const SizedBox.shrink();
        }
        final status = AppStatusColors.of(context);

        if (!dot) {
          // Halo de precisión real del GPS (antes eran 50 px fijos).
          return CircleLayer(
            circles: [
              CircleMarker(
                point: position,
                radius: (location.accuracy ?? 30).clamp(10, 200),
                useRadiusInMeter: true,
                color: status.userLocation.withValues(alpha: 0.15),
                borderColor: status.userLocation.withValues(alpha: 0.5),
                borderStrokeWidth: 2,
              ),
            ],
          );
        }

        return MarkerLayer(
          markers: [
            Marker(
              point: position,
              width: 24,
              height: 24,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: status.userLocation,
                  shape: BoxShape.circle,
                  border: Border.all(color: status.markerBorder, width: 3),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x40000000),
                      blurRadius: 4,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Colectivos en vivo, con la semaforización de capacidad.
class _ColectivosLayer extends StatelessWidget {
  const _ColectivosLayer({required this.onTap});

  final ValueChanged<ColectivoActivo> onTap;

  /// Con muchas unidades sólo se dibujan las de este radio alrededor del
  /// usuario (o del centro de Quilpué si no hay posición).
  static const double radioKm = 6.0;

  /// Con pocas unidades se muestran todas; con más, sólo las cercanas, salvo
  /// que ninguna lo esté.
  static List<ColectivoActivo> visiblesCerca(
    List<ColectivoActivo> todos,
    LatLng centro,
  ) {
    final validos = todos
        .where((c) => !(c.latitud == 0.0 && c.longitud == 0.0))
        .toList(growable: false);
    if (validos.length <= 4) return validos;
    const distance = Distance();
    final cerca = validos
        .where(
          (c) =>
              distance.as(
                LengthUnit.Kilometer,
                centro,
                LatLng(c.latitud, c.longitud),
              ) <=
              radioKm,
        )
        .toList(growable: false);
    return cerca.isEmpty ? validos : cerca;
  }

  @override
  Widget build(BuildContext context) {
    final telemetria = FirebaseTelemetriaService.instance;
    final location = LocationService.instance;
    final auth = AuthService.instance;

    return ListenableBuilder(
      listenable: Listenable.merge([telemetria.state, location, auth]),
      builder: (context, _) {
        final l10n = AppLocalizations.of(context)!;
        final status = AppStatusColors.of(context);
        final scheme = Theme.of(context).colorScheme;
        final ahora = telemetria.serverNow();
        final visibles = visiblesCerca(
          telemetria.state.value.colectivos,
          location.position ?? kQuilpueCenter,
        );

        return MarkerLayer(
          markers: [
            for (final colectivo in visibles)
              _marker(
                colectivo,
                isMe: auth.isColectivero && colectivo.uid == auth.uid,
                offline: colectivo.seemsOffline(ahora),
                status: status,
                primary: scheme.primary,
                l10n: l10n,
              ),
          ],
        );
      },
    );
  }

  Marker _marker(
    ColectivoActivo colectivo, {
    required bool isMe,
    required bool offline,
    required AppStatusColors status,
    required Color primary,
    required AppLocalizations l10n,
  }) {
    // Semaforización de capacidad (informe §7.3.1-C): el color lo reporta el
    // chofer desde su pantalla de turno.
    final color = isMe ? primary : status.forEstado(colectivo.estado);
    final onColor = AppStatusColors.onColorFor(color);
    final size = isMe ? 46.0 : 40.0;

    return Marker(
      point: LatLng(colectivo.latitud, colectivo.longitud),
      width: size,
      height: size,
      child: Semantics(
        button: true,
        label: l10n.colectivoSemanticLabel(
          formatPatente(colectivo.idVehiculo),
          offline
              ? l10n.colectivoNoSignal
              : estadoLabel(colectivo.estado, l10n),
        ),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => onTap(colectivo),
          // Sin señal se atenúa en vez de desaparecer: la unidad existe, pero
          // su posición puede estar desfasada (túnel, cerro sin cobertura).
          child: Opacity(
            opacity: offline ? 0.45 : 1,
            child: Container(
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(
                  color: status.markerBorder,
                  width: isMe ? 3 : 2,
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x59000000),
                    blurRadius: 6,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Icon(
                Icons.directions_car,
                color: onColor,
                size: isMe ? 24 : 20,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Paraderos, coloreados por cercanía a la posición **actual** del usuario.
///
/// Antes el color se calculaba contra el primer punto GPS de la sesión: tras
/// caminar un kilómetro, el paradero de al lado seguía marcado "lejos".
class _StopsLayer extends StatelessWidget {
  const _StopsLayer({required this.onTap});

  final ValueChanged<BusStop> onTap;

  @override
  Widget build(BuildContext context) {
    final stops = StopsService.instance;
    final location = LocationService.instance;
    final route = RouteService.instance;
    final prefs = PreferencesService.instance;

    return ListenableBuilder(
      listenable: Listenable.merge([stops, location, route, prefs]),
      builder: (context, _) {
        final l10n = AppLocalizations.of(context)!;
        final status = AppStatusColors.of(context);
        final origin = location.position ?? route.origin;
        final destination = route.destination;

        return MarkerLayer(
          markers: [
            for (final stop in stops.stops)
              Marker(
                point: stop.location,
                width: AppSpacing.minTapTarget,
                height: AppSpacing.minTapTarget,
                child: Semantics(
                  button: true,
                  label: l10n.stopSemanticLabel(stop.name, stop.address),
                  child: GestureDetector(
                    onTap: () => onTap(stop),
                    child: _BusStopPin(
                      color: proximityColor(
                        proximityOf(
                          origin == null ? null : stop.distanceFrom(origin),
                        ),
                        status,
                      ),
                      borderColor: status.markerBorder,
                      selected: destination == stop,
                      animate: prefs.animationsEnabled,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Widgets auxiliares
// ---------------------------------------------------------------------------

class _BusStopPin extends StatefulWidget {
  const _BusStopPin({
    required this.color,
    required this.borderColor,
    required this.selected,
    required this.animate,
  });

  final Color color;
  final Color borderColor;
  final bool selected;

  /// Respeta la preferencia "Animaciones", que este pin ignoraba: el pulso tipo
  /// radar latía indefinidamente aunque el usuario las hubiera desactivado.
  final bool animate;

  @override
  State<_BusStopPin> createState() => _BusStopPinState();
}

class _BusStopPinState extends State<_BusStopPin>
    with SingleTickerProviderStateMixin {
  /// Se crea recién cuando el paradero se selecciona. Antes cada uno de los
  /// paraderos del mapa tenía su propio controlador de animación aunque nunca
  /// fuera a latir.
  AnimationController? _pulse;
  Animation<double>? _pulseScale;
  Animation<double>? _pulseOpacity;

  bool get _shouldPulse => widget.selected && widget.animate;

  @override
  void initState() {
    super.initState();
    _syncPulse();
  }

  @override
  void didUpdateWidget(covariant _BusStopPin oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncPulse();
  }

  void _syncPulse() {
    if (_shouldPulse) {
      final pulse = _pulse ??= _createPulse();
      if (!pulse.isAnimating) pulse.repeat();
    } else if (_pulse?.isAnimating ?? false) {
      _pulse!
        ..stop()
        ..reset();
    }
  }

  AnimationController _createPulse() {
    final controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _pulseScale = Tween<double>(
      begin: 1.0,
      end: 2.2,
    ).animate(CurvedAnimation(parent: controller, curve: Curves.easeOut));
    _pulseOpacity = Tween<double>(
      begin: 0.55,
      end: 0.0,
    ).animate(CurvedAnimation(parent: controller, curve: Curves.easeIn));
    return controller;
  }

  @override
  void dispose() {
    _pulse?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    final size = selected ? 40.0 : 28.0;
    final iconSize = selected ? 22.0 : 16.0;
    final onColor = AppStatusColors.onColorFor(widget.color);
    final pulse = _pulse;

    return SizedBox(
      width: AppSpacing.minTapTarget,
      height: AppSpacing.minTapTarget,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          if (_shouldPulse && pulse != null)
            AnimatedBuilder(
              animation: pulse,
              builder: (context, _) => Transform.scale(
                scale: _pulseScale!.value,
                child: Opacity(
                  opacity: _pulseOpacity!.value,
                  child: Container(
                    width: size,
                    height: size,
                    decoration: BoxDecoration(
                      color: widget.color,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
            ),
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: widget.color,
              shape: BoxShape.circle,
              border: Border.all(
                color: widget.borderColor,
                width: selected ? 4 : 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: Color(selected ? 0x66000000 : 0x40000000),
                  blurRadius: selected ? 8 : 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Icon(Icons.directions_bus, color: onColor, size: iconSize),
          ),
        ],
      ),
    );
  }
}

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

/// Tarjeta de la ruta a pie activa: paradero, distancia y tiempo caminando.
class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.destination,
    required this.routeInfo,
    required this.provider,
    required this.onClose,
    required this.onTap,
  });

  final BusStop destination;
  final RouteResult? routeInfo;
  final String? provider;
  final VoidCallback onClose;

  /// Al tocar la tarjeta, el mapa se centra en el paradero.
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final status = AppStatusColors.of(context);
    final l10n = AppLocalizations.of(context)!;

    return MapOverlayCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.place, color: status.distanceVeryClose),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      destination.name,
                      style: theme.textTheme.titleSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      destination.address,
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
                onPressed: onClose,
                tooltip: l10n.closeRoute,
              ),
            ],
          ),
          if (routeInfo != null) ...[
            const SizedBox(height: AppSpacing.sm),
            // Wrap y no Row: con la fuente al 140% las métricas pasan a una
            // segunda línea en vez de desbordar.
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                MetricChip(
                  icon: Icons.straighten,
                  label: formatDistance(routeInfo!.distanceMeters, l10n),
                  color: scheme.primary,
                ),
                MetricChip(
                  icon: Icons.directions_walk,
                  label: formatDurationSeconds(
                    routeInfo!.durationSeconds,
                    l10n,
                  ),
                  color: scheme.tertiary,
                ),
                if (provider != null)
                  Text(
                    l10n.viaProvider(provider!),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
              ],
            ),
          ],
          const SizedBox(height: AppSpacing.xs),
          Text(
            l10n.tapToGoStop,
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
