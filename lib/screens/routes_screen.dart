import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import 'package:taxi1/l10n/app_localizations.dart';
import 'package:taxi1/models/bus_stop.dart';
import 'package:taxi1/screens/main_screen.dart';
import 'package:taxi1/services/location_service.dart';
import 'package:taxi1/services/route_service.dart';
import 'package:taxi1/services/stop_history_service.dart';
import 'package:taxi1/services/stops_service.dart';
import 'package:taxi1/theme/app_colors.dart';
import 'package:taxi1/theme/app_spacing.dart';
import 'package:taxi1/theme/breakpoints.dart';
import 'package:taxi1/utils/distance_format.dart';
import 'package:taxi1/utils/route_error.dart';
import 'package:taxi1/utils/text_search.dart';
import 'package:taxi1/widgets/metric_chip.dart';
import 'package:taxi1/widgets/paradero_sheet.dart';
import 'package:taxi1/widgets/settings_section.dart';
import 'package:taxi1/widgets/state_views.dart';

/// Cómo se ordena la lista de paraderos.
///
/// Las dos maneras en que alguien busca un paradero: el que tiene al lado, o
/// el que usa siempre.
enum _SortMode { cercanos, recientes }

class RoutesScreen extends StatefulWidget {
  const RoutesScreen({super.key});

  @override
  State<RoutesScreen> createState() => _RoutesScreenState();
}

class _RoutesScreenState extends State<RoutesScreen> {
  /// Cuánto hay que moverse para volver a ordenar la lista. Reordenar con
  /// cada punto del GPS haría saltar las filas bajo el dedo del usuario.
  static const double _metrosParaReordenar = 50;

  bool _fetchingRoute = false;
  List<BusStop> _sortedStops = [];
  LatLng? _sortedFrom;
  String _searchQuery = '';
  _SortMode _sortMode = _SortMode.cercanos;

  final routeService = RouteService.instance;
  final history = StopHistoryService.instance;
  final stopsService = StopsService.instance;
  final location = LocationService.instance;
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    routeService.addListener(_onChanged);
    history.addListener(_onChanged);
    // Los paraderos son datos vivos: el administrador puede agregar o dar de
    // baja uno mientras esta pantalla está abierta.
    stopsService.addListener(_resort);
    // La posición también: antes se pedía una sola vez al abrir la app, así que
    // tras caminar unas cuadras "Cercanos" seguía ordenado desde el punto de
    // partida. Y mientras esa única lectura llegaba (en interiores, decenas de
    // segundos), un spinner a pantalla completa tapaba la lista entera.
    location.addListener(_onLocationChanged);
    _sortedStops = _sortStops(stopsService.stops);
  }

  @override
  void dispose() {
    routeService.removeListener(_onChanged);
    history.removeListener(_onChanged);
    stopsService.removeListener(_resort);
    location.removeListener(_onLocationChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  void _onLocationChanged() {
    final position = location.position;
    final from = _sortedFrom;
    final moved =
        position != null &&
        (from == null ||
            const Distance().as(LengthUnit.Meter, from, position) >
                _metrosParaReordenar);
    if (moved) {
      _resort();
    } else if (mounted) {
      // Igual hay que redibujar: cambian las distancias y el aviso de GPS.
      setState(() {});
    }
  }

  void _resort() {
    if (!mounted) return;
    setState(() => _sortedStops = _sortStops(stopsService.stops));
  }

  /// Copia la lista y la ordena por cercanía si hay posición conocida.
  ///
  /// Ordenar es una función y no un efecto secundario del arranque: los
  /// paraderos y la posición cambian mientras la pantalla está abierta.
  List<BusStop> _sortStops(List<BusStop> source) {
    final sorted = List.of(source);
    final position = location.position;
    _sortedFrom = position;
    if (position != null) {
      sorted.sort(
        (a, b) => a.distanceFrom(position).compareTo(b.distanceFrom(position)),
      );
    }
    return sorted;
  }

  /// Selección + cálculo de ruta + cambio de tab al mapa.
  Future<void> _selectStop(BusStop stop) async {
    if (_fetchingRoute) return;
    final l10n = AppLocalizations.of(context)!;

    final origin = location.position;
    if (origin == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.locationUnavailable)));
      return;
    }

    routeService.setDestination(stop);
    setState(() => _fetchingRoute = true);
    final ok = await routeService.fetchRoute(origin, stop);
    if (!mounted) return;
    setState(() => _fetchingRoute = false);

    if (ok) {
      // Da contenido real a la preferencia "Guardar historial".
      history.record(stop);
      // Cambiar de tab (no Navigator.push) para preservar el estado del mapa.
      MainNavigationController.instance.showMap();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(routeErrorMessage(routeService.lastError, l10n)),
        ),
      );
    }
  }

  /// La lista según el orden elegido, ya filtrada por el buscador.
  ///
  /// Buscar por texto ignora el modo a propósito: si el usuario escribe un
  /// nombre, quiere ese paradero, no los que ha visitado antes. La búsqueda no
  /// distingue tildes ni el orden de las palabras.
  List<BusStop> get _filteredStops {
    final base = _sortMode == _SortMode.recientes && _searchQuery.isEmpty
        ? history.recentStops
        : _sortedStops;

    if (_searchQuery.isEmpty) return base;
    return base
        .where((s) => matchesAllTokens(_searchQuery, [s.name, s.address]))
        .toList();
  }

  double? _metersTo(BusStop stop) {
    final position = location.position;
    return position == null ? null : stop.distanceFrom(position);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final stops = _filteredStops;
    final searching = _searchQuery.isNotEmpty;

    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: Breakpoints.maxContentWidth,
          ),
          child: Column(
            children: [
              Expanded(
                child: CustomScrollView(
                  slivers: [
                    SliverAppBar.large(
                      title: Text(l10n.calculateRouteTitle),
                      // Con Scaffolds anidados Flutter no detecta solo que haya
                      // un drawer más arriba: el botón de menú va explícito.
                      leading: IconButton(
                        icon: const Icon(Icons.menu),
                        tooltip: l10n.openMenu,
                        onPressed: MainNavigationController.instance.openDrawer,
                      ),
                      actions: [
                        // Acceso directo a Preferencias: antes había que ir a
                        // la tercera pestaña a mano.
                        IconButton(
                          icon: const Icon(Icons.tune),
                          tooltip: l10n.preferencesTitle,
                          onPressed: () => MainNavigationController.instance
                              .openPreferences(context),
                        ),
                      ],
                    ),
                    SliverToBoxAdapter(child: _header(l10n)),
                    if (_locationNotice(l10n) case final notice?)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(
                            AppSpacing.lg,
                            0,
                            AppSpacing.lg,
                            AppSpacing.md,
                          ),
                          child: notice,
                        ),
                      ),

                    if (stops.isEmpty)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        // "Sin resultados para ''" no significaba nada cuando la
                        // lista está vacía por estar en modo Recientes y no por
                        // una búsqueda.
                        child: searching
                            ? StatusMessageView(
                                icon: Icons.search_off,
                                title: l10n.noResults(_searchQuery),
                                message: l10n.noResultsHint,
                              )
                            : StatusMessageView(
                                icon: Icons.history,
                                title: l10n.sortRecentEmpty,
                                actionLabel: l10n.sortNearest,
                                onAction: () => setState(
                                  () => _sortMode = _SortMode.cercanos,
                                ),
                              ),
                      )
                    else ...[
                      SliverToBoxAdapter(
                        child: SettingsSection(
                          icon: Icons.directions_bus_outlined,
                          title: switch ((searching, _sortMode)) {
                            (true, _) => l10n.whereToGo,
                            (false, _SortMode.recientes) => l10n.recentStops,
                            (false, _SortMode.cercanos) => l10n.allStops,
                          },
                          children: const [],
                        ),
                      ),
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.lg,
                          0,
                          AppSpacing.lg,
                          AppSpacing.lg,
                        ),
                        sliver: SliverList.separated(
                          itemCount: stops.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: AppSpacing.sm),
                          itemBuilder: (context, index) {
                            final stop = stops[index];
                            return _StopTile(
                              stop: stop,
                              meters: _metersTo(stop),
                              // Ya no se calcula la ruta a pie al tocar: primero
                              // se muestra qué colectivos pasan por el paradero,
                              // que es la pregunta real, y desde ahí se elige.
                              onTap: () => showParaderoSheet(context, stop),
                              showLoading:
                                  _fetchingRoute &&
                                  routeService.destination == stop,
                            );
                          },
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              _nearestStopButton(l10n),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(AppLocalizations l10n) {
    // Ambos campos heredan radio, relleno y bordes del `inputDecorationTheme`.
    final position = location.position;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            readOnly: true,
            decoration: InputDecoration(
              labelText: l10n.originLabel,
              prefixIcon: const Icon(Icons.my_location),
              hintText: position != null
                  ? l10n.coordsLabel(
                      position.latitude.toStringAsFixed(5),
                      position.longitude.toStringAsFixed(5),
                    )
                  : l10n.searchingLocation,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _searchController,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: l10n.searchStopHint,
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchQuery.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear),
                      tooltip: l10n.cancel,
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _searchQuery = '');
                      },
                    ),
            ),
            onChanged: (value) => setState(() => _searchQuery = value.trim()),
          ),

          // Con una búsqueda activa el orden no se aplica (manda el texto), así
          // que mostrar el selector sugeriría un control que no hace nada.
          if (_searchQuery.isEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            SegmentedButton<_SortMode>(
              showSelectedIcon: false,
              selected: {_sortMode},
              onSelectionChanged: (s) => setState(() => _sortMode = s.first),
              segments: [
                ButtonSegment(
                  value: _SortMode.cercanos,
                  icon: const Icon(Icons.near_me_outlined, size: 18),
                  label: Text(l10n.sortNearest),
                ),
                ButtonSegment(
                  value: _SortMode.recientes,
                  icon: const Icon(Icons.history, size: 18),
                  label: Text(l10n.sortRecent),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// Aviso en línea cuando no hay posición: la lista sigue siendo útil, pero el
  /// usuario tiene que saber por qué no está ordenada por cercanía.
  Widget? _locationNotice(AppLocalizations l10n) {
    return switch (location.issue) {
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
      LocationIssue.disabledByPreference => InlineNotice(
        icon: Icons.location_disabled,
        message: l10n.enableLocationForSorting,
        actionLabel: l10n.preferencesTitle,
        onAction: () =>
            MainNavigationController.instance.openPreferences(context),
      ),
      LocationIssue.none when location.position == null => InlineNotice(
        icon: Icons.location_searching,
        message: l10n.searchingLocation,
        tone: StatusTone.neutral,
      ),
      LocationIssue.none => null,
    };
  }

  Widget _nearestStopButton(AppLocalizations l10n) {
    // Sin posición no existe "el más cercano": la lista está sin ordenar y el
    // botón elegiría un paradero arbitrario.
    if (location.position == null || _sortedStops.isEmpty) {
      return const SizedBox.shrink();
    }

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: FilledButton.icon(
          onPressed: _fetchingRoute
              ? null
              : () => _selectStop(_sortedStops.first),
          icon: const Icon(Icons.near_me),
          label: Text(l10n.goToNearestStop),
        ),
      ),
    );
  }
}

class _StopTile extends StatelessWidget {
  const _StopTile({
    required this.stop,
    required this.meters,
    required this.onTap,
    required this.showLoading,
  });

  final BusStop stop;

  /// `null` cuando no se conoce la posición del usuario.
  final double? meters;
  final VoidCallback onTap;
  final bool showLoading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final status = AppStatusColors.of(context);

    final bucket = proximityOf(meters);
    final color = proximityColor(bucket, status);
    final closeness = proximityLabel(bucket, l10n);

    return Card(
      child: InkWell(
        onTap: showLoading ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              // Punto de cercanía sobre un fondo teñido: se lee como un
              // indicador de estado y no como una viñeta suelta.
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.directions_bus, size: 20, color: color),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(stop.name, style: theme.textTheme.titleSmall),
                    const SizedBox(height: 2),
                    Text(
                      stop.address,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              if (showLoading)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else if (closeness == null)
                // Sin ubicación no se inventa una distancia.
                Text(
                  l10n.distanceUnavailable,
                  textAlign: TextAlign.end,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                )
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      formatDistance(meters, l10n),
                      style: theme.textTheme.labelLarge,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    MetricChip(label: closeness, color: color),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}
