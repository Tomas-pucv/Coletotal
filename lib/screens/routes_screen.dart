import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import 'package:taxi1/l10n/app_localizations.dart';
import 'package:taxi1/models/recorrido.dart';
import 'package:taxi1/models/variante.dart';
import 'package:taxi1/screens/main_screen.dart';
import 'package:taxi1/services/location_service.dart';
import 'package:taxi1/services/recorridos_service.dart';
import 'package:taxi1/theme/app_colors.dart';
import 'package:taxi1/theme/app_spacing.dart';
import 'package:taxi1/theme/breakpoints.dart';
import 'package:taxi1/utils/distance_format.dart';
import 'package:taxi1/widgets/metric_chip.dart';
import 'package:taxi1/widgets/state_views.dart';

/// Pantalla de Recorridos de taxis colectivos de Quilpué.
///
/// Muestra la lista de todas las líneas de la garita ordenadas de la más cercana
/// a la más lejana (calculando la distancia ortogonal mínima a su traza vial).
/// Permite buscar por cualquier calle o punto de interés que forme parte de
/// sus cartolas oficiales de ida y vuelta, y filtrar por variante operacional.
class RoutesScreen extends StatefulWidget {
  const RoutesScreen({super.key});

  @override
  State<RoutesScreen> createState() => _RoutesScreenState();
}

class _RoutesScreenState extends State<RoutesScreen> {
  static const double _metrosParaReordenar = 40;

  final _recorridosService = RecorridosService.instance;
  final _location = LocationService.instance;
  final _searchController = TextEditingController();

  String _searchQuery = '';
  String? _selectedVarianteId;
  LatLng? _sortedFrom;

  @override
  void initState() {
    super.initState();
    _recorridosService.addListener(_onChanged);
    _location.addListener(_onLocationChanged);
  }

  @override
  void dispose() {
    _recorridosService.removeListener(_onChanged);
    _location.removeListener(_onLocationChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  void _onLocationChanged() {
    final pos = _location.position;
    final from = _sortedFrom;
    final moved =
        pos != null &&
        (from == null ||
            const Distance().as(LengthUnit.Meter, from, pos) >
                _metrosParaReordenar);
    if (moved) {
      _sortedFrom = pos;
      if (mounted) setState(() {});
    } else if (mounted) {
      setState(() {});
    }
  }

  List<Recorrido> get _recorridos {
    final pos = _location.position;
    return _recorridosService.filtrar(
      varianteId: _selectedVarianteId,
      searchQuery: _searchQuery,
      userLocation: pos,
    );
  }

  double? _metersTo(Recorrido recorrido) {
    final pos = _location.position;
    if (pos == null) return null;
    final d = recorrido.distanceFrom(pos);
    return d.isFinite ? d : null;
  }

  void _selectAndShowMap(Recorrido recorrido) {
    _recorridosService.select(recorrido);
    MainNavigationController.instance.showMap();
  }

  void _showCartolaDetails(Recorrido recorrido) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final meters = _metersTo(recorrido);

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.7,
          maxChildSize: 0.95,
          minChildSize: 0.4,
          builder: (context, scrollController) {
            return ListView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                0,
                AppSpacing.lg,
                AppSpacing.xxl,
              ),
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: Color(recorrido.colorValue),
                      foregroundColor: Colors.white,
                      child: const Icon(Icons.local_taxi, size: 20),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            recorrido.nombre,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (recorrido.varianteNombre.isNotEmpty)
                            Text(
                              'Variante ${recorrido.varianteNombre}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.primary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                if (meters != null) ...[
                  Card(
                    color: theme.colorScheme.surfaceContainerHighest,
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: Row(
                        children: [
                          const Icon(Icons.near_me_outlined, size: 20),
                          const SizedBox(width: AppSpacing.sm),
                          Text(
                            'Traza más cercana a ${formatDistance(meters, l10n)} de ti',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                ],
                FilledButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    _selectAndShowMap(recorrido);
                  },
                  icon: const Icon(Icons.map),
                  label: const Text('Ver recorrido en el mapa'),
                ),
                const SizedBox(height: AppSpacing.xl),
                Text(
                  'Cartola de Ida',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                if (recorrido.callesIda.isEmpty)
                  Text(
                    'Itinerario según trazado vial oficial.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  )
                else
                  for (final (i, calle) in recorrido.callesIda.indexed)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 22,
                            height: 22,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: Color(recorrido.colorValue).withValues(alpha: 0.15),
                              shape: BoxShape.circle,
                            ),
                            child: Text(
                              '${i + 1}',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Color(recorrido.colorValue),
                              ),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: Text(
                              calle,
                              style: theme.textTheme.bodyMedium,
                            ),
                          ),
                        ],
                      ),
                    ),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  'Cartola de Vuelta',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                if (recorrido.callesVuelta.isEmpty)
                  Text(
                    'Itinerario según trazado vial de retorno.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  )
                else
                  for (final (i, calle) in recorrido.callesVuelta.indexed)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 22,
                            height: 22,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: Colors.grey.withValues(alpha: 0.2),
                              shape: BoxShape.circle,
                            ),
                            child: Text(
                              '${i + 1}',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: Text(
                              calle,
                              style: theme.textTheme.bodyMedium,
                            ),
                          ),
                        ],
                      ),
                    ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final recorridos = _recorridos;
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
                      leading: IconButton(
                        icon: const Icon(Icons.menu),
                        tooltip: l10n.openMenu,
                        onPressed: MainNavigationController.instance.openDrawer,
                      ),
                      actions: [
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
                    if (recorridos.isEmpty)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: StatusMessageView(
                          icon: Icons.search_off,
                          title: searching
                              ? l10n.noResults(_searchQuery)
                              : 'No hay líneas disponibles para esta variante.',
                          message: searching
                              ? l10n.noResultsHint
                              : 'Selecciona "Todas" para ver toda la flota.',
                          actionLabel: searching || _selectedVarianteId != null
                              ? 'Ver todas las líneas'
                              : null,
                          onAction: () => setState(() {
                            _selectedVarianteId = null;
                            _searchQuery = '';
                            _searchController.clear();
                          }),
                        ),
                      )
                    else ...[
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.lg,
                          0,
                          AppSpacing.lg,
                          AppSpacing.lg,
                        ),
                        sliver: SliverList.separated(
                          itemCount: recorridos.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: AppSpacing.sm),
                          itemBuilder: (context, index) {
                            final r = recorridos[index];
                            return _RecorridoTile(
                              recorrido: r,
                              meters: _metersTo(r),
                              onTap: () => _showCartolaDetails(r),
                              onSelect: () => _selectAndShowMap(r),
                            );
                          },
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              _nearestRouteButton(l10n, recorridos),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(AppLocalizations l10n) {
    final position = _location.position;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.md,
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
          const SizedBox(height: AppSpacing.md),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                FilterChip(
                  label: const Text('Todas'),
                  selected: _selectedVarianteId == null,
                  onSelected: (s) => setState(() => _selectedVarianteId = null),
                ),
                const SizedBox(width: AppSpacing.sm),
                for (final v in kVariantesSerrano) ...[
                  FilterChip(
                    label: Text(v.nombre),
                    selected: _selectedVarianteId == v.id,
                    onSelected: (s) => setState(
                      () => _selectedVarianteId = s ? v.id : null,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget? _locationNotice(AppLocalizations l10n) {
    return switch (_location.issue) {
      LocationIssue.serviceDisabled => InlineNotice(
        icon: Icons.location_off_outlined,
        message: l10n.locationOffMessage,
        actionLabel: l10n.openSettings,
        onAction: _location.openLocationSettings,
      ),
      LocationIssue.denied => InlineNotice(
        icon: Icons.lock_outline,
        message: l10n.locationDeniedMessage,
        actionLabel: l10n.openSettings,
        onAction: _location.openAppSettings,
      ),
      LocationIssue.disabledByPreference => InlineNotice(
        icon: Icons.location_disabled,
        message: l10n.enableLocationForSorting,
        actionLabel: l10n.preferencesTitle,
        onAction: () =>
            MainNavigationController.instance.openPreferences(context),
      ),
      LocationIssue.none when _location.position == null => InlineNotice(
        icon: Icons.location_searching,
        message: l10n.searchingLocation,
        tone: StatusTone.neutral,
      ),
      LocationIssue.none => null,
    };
  }

  Widget _nearestRouteButton(
    AppLocalizations l10n,
    List<Recorrido> recorridos,
  ) {
    if (_location.position == null || recorridos.isEmpty) {
      return const SizedBox.shrink();
    }

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: FilledButton.icon(
          onPressed: () => _selectAndShowMap(recorridos.first),
          icon: const Icon(Icons.near_me),
          label: Text(l10n.goToNearestStop),
        ),
      ),
    );
  }
}

class _RecorridoTile extends StatelessWidget {
  const _RecorridoTile({
    required this.recorrido,
    required this.meters,
    required this.onTap,
    required this.onSelect,
  });

  final Recorrido recorrido;
  final double? meters;
  final VoidCallback onTap;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final status = AppStatusColors.of(context);

    final bucket = proximityOf(meters);
    final color = proximityColor(bucket, status);
    final closeness = proximityLabel(bucket, l10n);

    final idaResumen = recorrido.callesIda.isNotEmpty
        ? recorrido.callesIda.take(3).join(' → ')
        : 'Itinerario oficial';
    final vueltaResumen = recorrido.callesVuelta.isNotEmpty
        ? recorrido.callesVuelta.take(3).join(' → ')
        : null;

    return Card(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: Color(recorrido.colorValue).withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.local_taxi,
                      size: 24,
                      color: Color(recorrido.colorValue),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          recorrido.nombre,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (recorrido.varianteNombre.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            'Variante: ${recorrido.varianteNombre}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  if (closeness == null)
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
              const SizedBox(height: AppSpacing.sm),
              Container(
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.arrow_forward, size: 14),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            'Ida: $idaResumen',
                            style: theme.textTheme.bodySmall,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    if (vueltaResumen != null) ...[
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          const Icon(Icons.arrow_back, size: 14),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              'Vuelta: $vueltaResumen',
                              style: theme.textTheme.bodySmall,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
