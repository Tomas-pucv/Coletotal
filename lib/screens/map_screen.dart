import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_animations/flutter_map_animations.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import 'package:taxi1/config/map_config.dart';
import 'package:taxi1/l10n/app_localizations.dart';
import 'package:taxi1/models/bus_stop.dart';
import 'package:taxi1/models/colectivo_activo.dart';
import 'package:taxi1/screens/main_screen.dart';
import 'package:taxi1/services/auth_service.dart';
import 'package:taxi1/services/firebase_telemetria_service.dart';
import 'package:taxi1/services/geocoding_service.dart';
import 'package:taxi1/services/preferences_service.dart';
import 'package:taxi1/services/recorridos_service.dart';
import 'package:taxi1/services/route_service.dart';
import 'package:taxi1/services/stop_history_service.dart';
import 'package:taxi1/services/stop_planner.dart';
import 'package:taxi1/services/stops_service.dart';
import 'package:taxi1/theme/app_colors.dart';
import 'package:taxi1/theme/app_spacing.dart';
import 'package:taxi1/utils/distance_format.dart';
import 'package:taxi1/widgets/map_overlay_card.dart';
import 'package:taxi1/widgets/map_search_bar.dart';
import 'package:taxi1/widgets/map_style_sheet.dart';
import 'package:taxi1/widgets/metric_chip.dart';
import 'package:taxi1/widgets/paradero_sheet.dart';
import 'package:taxi1/widgets/state_views.dart';
import 'package:taxi1/widgets/stop_suggestions_sheet.dart';

/// Motivo por el que no hay posición del usuario.
enum _LocationIssue { none, disabledByPreference, serviceDisabled, denied }

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> with TickerProviderStateMixin {
  late final AnimatedMapController _mapController;
  StreamSubscription<Position>? _positionStream;
  StreamSubscription<List<ColectivoActivo>>? _telemetriaStream;

  bool _followUser = true;
  LatLng? _currentPosition;
  double? _currentAccuracy;
  bool _showBusStops = true;
  _LocationIssue _locationIssue = _LocationIssue.none;

  List<ColectivoActivo> _colectivos = const [];
  bool _telemetriaFailed = false;

  final routeService = RouteService.instance;
  final prefs = PreferencesService.instance;
  final auth = AuthService.instance;
  final stopsService = StopsService.instance;
  final recorridos = RecorridosService.instance;

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

    prefs.addListener(_onPrefsChanged);
    routeService.addListener(_onRouteChanged);
    // El rol decide si se dibuja el punto azul del pasajero: al chofer lo
    // representa su propio marcador de vehículo, no un segundo punto encima.
    auth.addListener(_onRouteChanged);
    // Los paraderos ahora son datos vivos: si el administrador agrega uno, el
    // mapa del pasajero tiene que mostrarlo sin reiniciar la app.
    stopsService.addListener(_onRouteChanged);
    recorridos.addListener(_onRouteChanged);

    _centerBtnController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    );
    _centerScale = Tween<double>(begin: 1.0, end: 1.12).animate(
      CurvedAnimation(parent: _centerBtnController, curve: Curves.easeOut),
    );

    // Una sola suscripción en vez de un StreamBuilder: así el fallo del stream
    // se puede mostrar en la interfaz. Antes el builder hacía
    // `if (!snapshot.hasData) return SizedBox.shrink()`, con lo que una caída
    // de Firebase era literalmente invisible.
    _telemetriaStream = FirebaseTelemetriaService.instance.telemetriaStream
        .listen(
          (data) {
            if (!mounted) return;
            setState(() {
              _colectivos = data;
              _telemetriaFailed = false;
            });
          },
          onError: (Object _) {
            if (!mounted) return;
            setState(() => _telemetriaFailed = true);
          },
        );

    _initLocationTracking();
  }

  @override
  void dispose() {
    // La telemetría ya NO se detiene acá. Vivía en esta pantalla y sólo
    // funcionaba porque el IndexedStack la mantenía montada para siempre; con
    // las pantallas dependiendo del rol, cambiar de rol la habría destruido y
    // cortado la transmisión del chofer en silencio. Ahora manda TurnoService.
    prefs.removeListener(_onPrefsChanged);
    routeService.removeListener(_onRouteChanged);
    auth.removeListener(_onRouteChanged);
    stopsService.removeListener(_onRouteChanged);
    recorridos.removeListener(_onRouteChanged);
    _centerBtnController.dispose();
    _positionStream?.cancel();
    _telemetriaStream?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  void _onPrefsChanged() {
    if (!prefs.locationTracking) {
      _positionStream?.cancel();
      _positionStream = null;
      if (mounted) {
        setState(() {
          _followUser = false;
          _locationIssue = _LocationIssue.disabledByPreference;
        });
      }
    } else if (_positionStream == null) {
      _initLocationTracking();
    }
    if (mounted) setState(() {});
  }

  void _onRouteChanged() {
    if (mounted) setState(() {});
  }

  /// El usuario eligió una dirección en el buscador.
  ///
  /// A partir de ahí la app no pregunta "¿qué paradero quieres?", sino que lo
  /// propone: cruza la posición del usuario con los recorridos de la garita y
  /// ordena los paraderos por lo que hay que caminar en total (ver
  /// [StopPlanner]).
  Future<void> _onDestinationSelected(PlaceResult place) async {
    final l10n = AppLocalizations.of(context)!;
    setState(() => _destino = place);

    // Encuadrar destino y usuario juntos da contexto antes de abrir la hoja.
    _mapController.centerOnPoint(place.location, zoom: 15);
    setState(() => _followUser = false);

    final origin = _currentPosition ?? routeService.origin;
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
    routeService.setOrigin(origin);
    routeService.setDestination(elegido.stop);
    StopHistoryService.instance.record(elegido.stop);
    await routeService.fetchRoute(origin, elegido.stop);

    final linea = elegido.recorrido;
    if (linea != null && mounted) await recorridos.select(linea);
  }

  void _clearDestino() {
    setState(() => _destino = null);
    routeService.clearDestination();
    recorridos.clearSelection();
  }

  Future<void> _initLocationTracking() async {
    // Cada salida temprana ahora deja registrado el motivo. Antes eran `return`
    // secos: el mapa simplemente no centraba nunca y el usuario no tenía forma
    // de saber si faltaba un permiso, si el GPS estaba apagado, o si la app
    // estaba rota.
    if (!prefs.locationTracking) {
      _setIssue(_LocationIssue.disabledByPreference);
      _followUser = false;
      return;
    }

    // En plataformas sin geolocator (Windows, web) estas llamadas lanzan; sin
    // el try/catch la excepción quedaba sin manejar y el mapa nunca centraba
    // ni explicaba por qué.
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        _setIssue(_LocationIssue.serviceDisabled);
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        _setIssue(_LocationIssue.denied);
        return;
      }
    } catch (_) {
      _setIssue(_LocationIssue.serviceDisabled);
      return;
    }

    _setIssue(_LocationIssue.none);

    const locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 5,
    );

    _positionStream?.cancel();
    _positionStream =
        Geolocator.getPositionStream(locationSettings: locationSettings).listen(
          (Position position) {
            // En emuladores o antes del primer fix real, Geolocator puede
            // devolver 0,0 o NaN, lo que rompe flutter_map ("LatLng is not
            // finite").
            final lat = position.latitude;
            final lng = position.longitude;
            if (!lat.isFinite || !lng.isFinite) return;
            if (lat == 0.0 && lng == 0.0) return;
            if (!mounted) return;

            setState(() {
              _currentPosition = LatLng(lat, lng);
              _currentAccuracy = position.accuracy;
              if (routeService.origin == null) {
                routeService.setOrigin(_currentPosition!);
              }
              if (_followUser) {
                _mapController.mapController.move(
                  _currentPosition!,
                  _mapController.mapController.camera.zoom,
                );
              }
            });
          },
          onError: (Object _) {
            if (mounted) _setIssue(_LocationIssue.serviceDisabled);
          },
        );
  }

  void _setIssue(_LocationIssue issue) {
    if (!mounted) {
      _locationIssue = issue;
      return;
    }
    setState(() => _locationIssue = issue);
  }

  Future<void> _recenter() async {
    if (_currentPosition == null) {
      // Sin posición el botón no puede centrar: en vez de no hacer nada,
      // reintenta obtenerla.
      await _initLocationTracking();
      return;
    }
    _centerBtnController.forward(from: 0);
    await _mapController.centerOnPoint(_currentPosition!, zoom: 16.0);
    _centerBtnController.reverse();
    if (mounted) setState(() => _followUser = true);
  }

  Future<void> _reorient() => _mapController.animatedRotateReset();

  /// Toca un paradero del mapa: setea destino y pide la ruta.
  /// Tocar un paradero abre su ficha, igual que en la pestaña Paraderos.
  ///
  /// Antes calculaba directo la ruta a pie. Ahora los dos sitios desde los que
  /// se toca un paradero llevan a la misma pregunta —qué colectivos pasan por
  /// aquí—, y desde ahí se elige ver una línea o cómo llegar caminando.
  Future<void> _onTapStop(BusStop stop) async {
    // Se registra en el historial al consultarlo, no sólo al rutear: abrir la
    // ficha ya es interactuar con el paradero, que es lo que ordena la lista
    // en modo "Recientes".
    StopHistoryService.instance.record(stop);
    await _mapController.centerOnPoint(stop.location, zoom: 16.0);
    if (!mounted) return;
    await showParaderoSheet(context, stop);
  }

  Color _stopColor(BusStop stop, AppStatusColors status) {
    final origin = routeService.origin ?? _currentPosition;
    final meters = origin == null ? null : stop.distanceFrom(origin);
    return proximityColor(proximityOf(meters), status);
  }

  /// La construcción de la URL de teselas vive en `config/map_config.dart`,
  /// compartida con las miniaturas del selector de estilo: así la vista previa
  /// no puede quedar mostrando una cartografía distinta de la real.
  String _tileUrl(bool isDark) =>
      mapTileUrlTemplate(MapStyle.fromPref(prefs.mapType), isDark: isDark);

  String _fallbackTileUrl(bool isDark) =>
      fallbackTileUrlTemplate(MapStyle.fromPref(prefs.mapType), isDark: isDark);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final status = AppStatusColors.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final destination = routeService.destination;
    final origin = routeService.origin ?? _currentPosition;

    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController.mapController,
            options: MapOptions(
              initialCenter: kQuilpueCenter,
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
              onPositionChanged: (position, hasGesture) {
                if (hasGesture && _followUser) {
                  setState(() => _followUser = false);
                }
              },
            ),
            children: [
              TileLayer(
                urlTemplate: _tileUrl(isDark),
                fallbackUrl: _fallbackTileUrl(isDark),
                userAgentPackageName: 'cl.coletotal.app',
                retinaMode: RetinaMode.isHighDensity(context),
              ),

              // Recorrido de una línea de colectivos. Va debajo de la ruta a
              // pie: es contexto ("por aquí pasa la 5"), no la indicación que
              // el usuario tiene que seguir ahora.
              if (recorridos.trazadoSeleccionado.length > 1)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: recorridos.trazadoSeleccionado,
                      strokeWidth: 6.0,
                      color: Color(
                        recorridos.selected!.colorValue,
                      ).withValues(alpha: 0.85),
                      borderColor: status.routeLineCasing,
                      borderStrokeWidth: 1.5,
                    ),
                  ],
                ),

              // La ruta va antes que los marcadores para que no los tape.
              if (destination != null &&
                  origin != null &&
                  routeService.routePoints.isNotEmpty)
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

              // Halo de precisión real del GPS (antes eran 50 px fijos).
              if (_currentPosition != null && !auth.isColectivero)
                CircleLayer(
                  circles: [
                    CircleMarker(
                      point: _currentPosition!,
                      radius: (_currentAccuracy ?? 30).clamp(10, 200),
                      useRadiusInMeter: true,
                      color: status.userLocation.withValues(alpha: 0.15),
                      borderColor: status.userLocation.withValues(alpha: 0.5),
                      borderStrokeWidth: 2,
                    ),
                  ],
                ),

              // Colectivos en vivo (telemetría Firebase filtrada por proximidad).
              MarkerLayer(
                markers: [
                  for (final colectivo in _colectivosVisibles())
                    _colectivoMarker(colectivo, status, l10n),
                ],
              ),

              // Marcador del pasajero.
              if (_currentPosition != null && !auth.isColectivero)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _currentPosition!,
                      width: 24,
                      height: 24,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: status.userLocation,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: status.markerBorder,
                            width: 3,
                          ),
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
                ),

              if (_showBusStops)
                MarkerLayer(
                  markers: [
                    for (final stop in stopsService.stops)
                      Marker(
                        point: stop.location,
                        width: AppSpacing.minTapTarget,
                        height: AppSpacing.minTapTarget,
                        child: Semantics(
                          button: true,
                          label: l10n.stopSemanticLabel(
                            stop.name,
                            stop.address,
                          ),
                          child: GestureDetector(
                            onTap: () => _onTapStop(stop),
                            child: _BusStopPin(
                              color: _stopColor(stop, status),
                              borderColor: status.markerBorder,
                              selected: destination == stop,
                              animate: prefs.animationsEnabled,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
            ],
          ),

          // Todos los controles flotantes viven en un solo Column que ocupa la
          // pantalla. Esto elimina los offsets mágicos que había antes
          // (`bottom: destination != null ? 155 : 85`, `top: topPadding + 56`):
          // ahora el botón de recentrado sube solo cuando la tarjeta de estado
          // crece, ya sea por la info de ruta o por el tamaño de fuente.
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
                    const SizedBox(height: AppSpacing.md),
                    _StatusCard(
                      destination: destination,
                      currentPosition: _currentPosition,
                      followUser: _followUser,
                      routeInfo: routeService.routeInfo,
                      provider: routeService.activeProvider,
                      onClose: routeService.clearDestination,
                      onTap: destination == null
                          ? null
                          : () {
                              _mapController.centerOnPoint(
                                destination.location,
                                zoom: 16.0,
                              );
                              setState(() => _followUser = false);
                            },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<ColectivoActivo> _colectivosVisibles() {
    if (_colectivos.length <= 4) return _colectivos;
    final center = _currentPosition ?? kQuilpueCenter;
    const distance = Distance();
    final filtrados = _colectivos.where((c) {
      if (c.latitud == 0.0 && c.longitud == 0.0) return false;
      final km = distance.as(
        LengthUnit.Kilometer,
        center,
        LatLng(c.latitud, c.longitud),
      );
      return km <= 6.0;
    }).toList();
    return filtrados.isEmpty ? _colectivos : filtrados;
  }

  Future<void> _onTapColectivo(ColectivoActivo colectivo) async {
    final status = AppStatusColors.of(context);
    final theme = Theme.of(context);

    // Si tiene un recorrido asignado, seleccionamos e iluminamos su trazado vial en el mapa
    if (colectivo.recorridoId != null) {
      final linea = recorridos.byId(colectivo.recorridoId!);
      if (linea != null) {
        await recorridos.select(linea);
      }
    }

    if (!mounted) return;

    final estadoLabel = switch (colectivo.estado) {
      EstadoCapacidad.disponible => 'Disponible (con asientos)',
      EstadoCapacidad.medioLleno => 'Medio lleno (pocos cupos)',
      EstadoCapacidad.lleno => 'Lleno (sin cupos)',
    };

    final estadoColor = switch (colectivo.estado) {
      EstadoCapacidad.disponible => status.disponible,
      EstadoCapacidad.medioLleno => status.medioLleno,
      EstadoCapacidad.lleno => status.lleno,
    };

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
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
                    child: Icon(Icons.directions_car, color: estadoColor, size: 28),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Colectivo ${colectivo.idVehiculo}',
                          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          colectivo.recorridoNombre ?? 'En servicio activo',
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
              Container(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                decoration: BoxDecoration(
                  color: estadoColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                  border: Border.all(color: estadoColor.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: estadoColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Text(
                      estadoLabel,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: estadoColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
            ],
          ),
        ),
      ),
    );
  }

  Marker _colectivoMarker(
    ColectivoActivo colectivo,
    AppStatusColors status,
    AppLocalizations l10n,
  ) {
    // Antes se comparaba contra un id generado en el teléfono; ahora la clave
    // del nodo es el uid de la sesión, que es también lo que autoriza la
    // escritura en Realtime Database.
    final isMe = auth.isColectivero && colectivo.uid == auth.uid;

    // Semaforización de capacidad (informe §7.3.1-C): el color lo reporta el
    // chofer desde su pantalla de turno.
    final color = isMe
        ? Theme.of(context).colorScheme.primary
        : switch (colectivo.estado) {
            EstadoCapacidad.disponible => status.disponible,
            EstadoCapacidad.medioLleno => status.medioLleno,
            EstadoCapacidad.lleno => status.lleno,
          };
    final onColor = AppStatusColors.onColorFor(color);

    return Marker(
      point: LatLng(colectivo.latitud, colectivo.longitud),
      width: isMe ? 46 : 40,
      height: isMe ? 46 : 40,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _onTapColectivo(colectivo),
        child: Container(
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: status.markerBorder, width: isMe ? 3 : 2),
            boxShadow: const [
              BoxShadow(
                color: Color(0x59000000),
                blurRadius: 6,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Icon(Icons.directions_car, color: onColor, size: isMe ? 24 : 20),
        ),
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
            // entera), así que el acceso al menú es este botón flotante. Va
            // arriba a la izquierda, donde estaría el de una AppBar.
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
              if (routeService.loadingRoute)
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
              if (_locationNotice(l10n) case final notice?) ...[
                if (routeService.loadingRoute)
                  const SizedBox(height: AppSpacing.sm),
                notice,
              ],
              if (_telemetriaFailed) ...[
                const SizedBox(height: AppSpacing.sm),
                InlineNotice(
                  icon: Icons.cloud_off,
                  message: l10n.telemetryUnavailable,
                  tone: StatusTone.error,
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Column(
          children: [
            FloatingActionButton.small(
              heroTag: 'reorient',
              // Antes este botón era el único sin tooltip de los tres.
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
            // el mapa a la vista; tenerlo solo en la tercera pestaña obligaba a
            // salir del mapa para volver a entrar.
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
    return switch (_locationIssue) {
      _LocationIssue.none => null,
      _LocationIssue.disabledByPreference => InlineNotice(
        icon: Icons.location_disabled,
        message: l10n.locationDisabledByPreference,
        actionLabel: l10n.preferencesTitle,
        onAction: () =>
            MainNavigationController.instance.openPreferences(context),
      ),
      _LocationIssue.serviceDisabled => InlineNotice(
        icon: Icons.location_off_outlined,
        message: l10n.locationOffMessage,
        actionLabel: l10n.openSettings,
        onAction: Geolocator.openLocationSettings,
      ),
      _LocationIssue.denied => InlineNotice(
        icon: Icons.lock_outline,
        message: l10n.locationDeniedMessage,
        actionLabel: l10n.openSettings,
        onAction: Geolocator.openAppSettings,
      ),
    };
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
  late final AnimationController _pulseController;
  late final Animation<double> _pulseScale;
  late final Animation<double> _pulseOpacity;

  bool get _shouldPulse => widget.selected && widget.animate;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _pulseScale = Tween<double>(
      begin: 1.0,
      end: 2.2,
    ).animate(CurvedAnimation(parent: _pulseController, curve: Curves.easeOut));
    _pulseOpacity = Tween<double>(
      begin: 0.55,
      end: 0.0,
    ).animate(CurvedAnimation(parent: _pulseController, curve: Curves.easeIn));
    if (_shouldPulse) _pulseController.repeat();
  }

  @override
  void didUpdateWidget(covariant _BusStopPin oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_shouldPulse && !_pulseController.isAnimating) {
      _pulseController.repeat();
    } else if (!_shouldPulse && _pulseController.isAnimating) {
      _pulseController.stop();
      _pulseController.reset();
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    final size = selected ? 40.0 : 28.0;
    final iconSize = selected ? 22.0 : 16.0;
    final onColor = AppStatusColors.onColorFor(widget.color);

    return SizedBox(
      width: AppSpacing.minTapTarget,
      height: AppSpacing.minTapTarget,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          if (_shouldPulse)
            AnimatedBuilder(
              animation: _pulseController,
              builder: (context, _) => Transform.scale(
                scale: _pulseScale.value,
                child: Opacity(
                  opacity: _pulseOpacity.value,
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

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.destination,
    required this.currentPosition,
    required this.followUser,
    required this.routeInfo,
    required this.provider,
    required this.onClose,
    this.onTap,
  });

  final BusStop? destination;
  final LatLng? currentPosition;
  final bool followUser;
  final RouteResult? routeInfo;
  final String? provider;
  final VoidCallback onClose;

  /// Al tocar la tarjeta con destino, el mapa se centra en el paradero.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final status = AppStatusColors.of(context);
    final l10n = AppLocalizations.of(context)!;

    // Sin destino: estado del GPS y coordenadas.
    if (destination == null) {
      final tracking = followUser && currentPosition != null;
      return MapOverlayCard(
        child: Row(
          children: [
            Icon(
              tracking ? Icons.gps_fixed : Icons.gps_off,
              color: tracking ? status.disponible : scheme.onSurfaceVariant,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                currentPosition != null
                    ? l10n.coordsLabel(
                        currentPosition!.latitude.toStringAsFixed(5),
                        currentPosition!.longitude.toStringAsFixed(5),
                      )
                    : l10n.searchingLocation,
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],
        ),
      );
    }

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
                      destination!.name,
                      style: theme.textTheme.titleSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      destination!.address,
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
                  icon: Icons.schedule,
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
          if (onTap != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              l10n.tapToGoStop,
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.primary,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
