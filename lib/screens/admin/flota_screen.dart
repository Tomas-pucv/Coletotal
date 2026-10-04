import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_animations/flutter_map_animations.dart';
import 'package:latlong2/latlong.dart';

import 'package:taxi1/config/map_config.dart';
import 'package:taxi1/l10n/app_localizations.dart';
import 'package:taxi1/models/colectivo_activo.dart';
import 'package:taxi1/navigation/app_destination.dart';
import 'package:taxi1/screens/main_screen.dart';
import 'package:taxi1/services/auth_service.dart';
import 'package:taxi1/services/firebase_telemetria_service.dart';
import 'package:taxi1/theme/app_colors.dart';
import 'package:taxi1/theme/app_spacing.dart';
import 'package:taxi1/utils/patente.dart';
import 'package:taxi1/widgets/map_overlay_card.dart';
import 'package:taxi1/widgets/state_views.dart';

/// Monitoreo de flota en vivo (informe §7.3.1-C).
///
/// Mapa arriba, lista abajo. La semaforización de los marcadores es la que
/// reporta cada chofer desde su pantalla de turno, así que el administrador
/// diagnostica la oferta de la línea por color y sin leer nada.
class FlotaScreen extends StatefulWidget {
  const FlotaScreen({super.key});

  @override
  State<FlotaScreen> createState() => _FlotaScreenState();
}

class _FlotaScreenState extends State<FlotaScreen>
    with TickerProviderStateMixin {
  late final AnimatedMapController _mapController;
  final _auth = AuthService.instance;

  StreamSubscription<List<ColectivoActivo>>? _sub;
  List<ColectivoActivo> _unidades = const [];
  bool _failed = false;
  String? _selected;

  static const _garitasOpciones = [
    ('todas', 'Toda la Flota Serrano'),
    ('garita_quilpue_01', 'Garita Cumming'),
    ('garita_serranos_rosas', 'Garita Las Rosas'),
    ('garita_serranos_belloto2000', 'Garita Belloto 2000'),
  ];
  String _filtroGarita = 'todas';

  List<ColectivoActivo> get _unidadesFiltradas {
    if (_filtroGarita == 'todas') return _unidades;
    return _unidades.where((c) {
      if (c.garitaId.isEmpty && _filtroGarita == 'garita_quilpue_01') return true;
      return c.garitaId == _filtroGarita;
    }).toList(growable: false);
  }

  @override
  void initState() {
    super.initState();
    _mapController = AnimatedMapController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeInOut,
    );
    _auth.addListener(_onChanged);

    _sub = FirebaseTelemetriaService.instance.telemetriaStream.listen(
      (data) {
        if (!mounted) return;
        setState(() {
          _unidades = data;
          _failed = false;
        });
      },
      onError: (Object _) {
        if (mounted) setState(() => _failed = true);
      },
    );
  }

  @override
  void dispose() {
    _auth.removeListener(_onChanged);
    _sub?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  void _focus(ColectivoActivo unidad) {
    setState(() => _selected = unidad.uid);
    _mapController.centerOnPoint(
      LatLng(unidad.latitud, unidad.longitud),
      zoom: 16,
    );
  }

  Color _colorFor(ColectivoActivo unidad, AppStatusColors status) =>
      switch (unidad.estado) {
        EstadoCapacidad.disponible => status.disponible,
        EstadoCapacidad.medioLleno => status.medioLleno,
        EstadoCapacidad.lleno => status.lleno,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final status = AppStatusColors.of(context);
    final isDark = theme.brightness == Brightness.dark;

    if (!_auth.isAdmin) {
      return Scaffold(
        appBar: AppBar(
          title: Text(AppDestination.flota.label(l10n)),
          leading: IconButton(
            icon: const Icon(Icons.menu),
            tooltip: l10n.openMenu,
            onPressed: MainNavigationController.instance.openDrawer,
          ),
        ),
        body: StatusMessageView(
          icon: Icons.lock_outline,
          title: AppDestination.flota.label(l10n),
          message: l10n.adminOnly,
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(AppDestination.flota.label(l10n)),
        leading: IconButton(
          icon: const Icon(Icons.menu),
          tooltip: l10n.openMenu,
          onPressed: MainNavigationController.instance.openDrawer,
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.lg),
            child: Center(
              child: Text(
                l10n.fleetUnitsInService('${_unidadesFiltradas.length}'),
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            height: 48,
            color: theme.colorScheme.surface,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: 6,
              ),
              itemCount: _garitasOpciones.length,
              separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
              itemBuilder: (context, i) {
                final (gid, gNombre) = _garitasOpciones[i];
                final isSel = _filtroGarita == gid;
                return ChoiceChip(
                  selected: isSel,
                  showCheckmark: false,
                  label: Text(gNombre),
                  labelStyle: theme.textTheme.labelMedium?.copyWith(
                    color: isSel
                        ? theme.colorScheme.onPrimary
                        : theme.colorScheme.onSurface,
                    fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                  ),
                  selectedColor: theme.colorScheme.primary,
                  onSelected: (val) {
                    if (val) setState(() => _filtroGarita = gid);
                  },
                );
              },
            ),
          ),
          Expanded(
            flex: 3,
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _mapController.mapController,
                  options: const MapOptions(
                    initialCenter: kQuilpueCenter,
                    initialZoom: kInitialZoom,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: mapTileUrlTemplate(
                        MapStyle.normal,
                        isDark: isDark,
                      ),
                      fallbackUrl: fallbackTileUrlTemplate(
                        MapStyle.normal,
                        isDark: isDark,
                      ),
                      userAgentPackageName: 'cl.coletotal.app',
                    ),
                    MarkerLayer(
                      markers: [
                        for (final unidad in _unidadesFiltradas)
                          Marker(
                            point: LatLng(unidad.latitud, unidad.longitud),
                            width: 44,
                            height: 44,
                            child: GestureDetector(
                              onTap: () => _focus(unidad),
                              child: _UnidadMarker(
                                color: _colorFor(unidad, status),
                                borderColor: status.markerBorder,
                                selected: _selected == unidad.uid,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
                if (_failed)
                  Positioned(
                    left: AppSpacing.lg,
                    right: AppSpacing.lg,
                    top: AppSpacing.lg,
                    child: InlineNotice(
                      icon: Icons.cloud_off,
                      message: l10n.telemetryUnavailable,
                      tone: StatusTone.error,
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: _unidadesFiltradas.isEmpty
                ? StatusMessageView(
                    icon: Icons.local_taxi_outlined,
                    title: l10n.fleetEmpty,
                    message: l10n.fleetEmptyHint,
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    itemCount: _unidadesFiltradas.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: AppSpacing.sm),
                    itemBuilder: (context, index) {
                      final unidad = _unidadesFiltradas[index];
                      return MapOverlayCard(
                        onTap: () => _focus(unidad),
                        child: Row(
                          children: [
                            Icon(
                              Icons.directions_car,
                              color: _colorFor(unidad, status),
                            ),
                            const SizedBox(width: AppSpacing.md),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    formatPatente(unidad.idVehiculo),
                                    style: theme.textTheme.titleSmall?.copyWith(
                                      letterSpacing: 1.2,
                                    ),
                                  ),
                                  if (unidad.recorridoNombre != null) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      unidad.recorridoNombre!,
                                      style: theme.textTheme.labelSmall
                                          ?.copyWith(
                                            color: theme.colorScheme.primary,
                                            fontWeight: FontWeight.w600,
                                          ),
                                    ),
                                  ],
                                  Text(
                                    _estadoLabel(unidad.estado, l10n),
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: _colorFor(unidad, status),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              _seenLabel(unidad, l10n),
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  static String _estadoLabel(EstadoCapacidad estado, AppLocalizations l10n) =>
      switch (estado) {
        EstadoCapacidad.disponible => l10n.capacityAvailable,
        EstadoCapacidad.medioLleno => l10n.capacityHalf,
        EstadoCapacidad.lleno => l10n.capacityFull,
      };

  static String _seenLabel(ColectivoActivo unidad, AppLocalizations l10n) {
    final ts = unidad.ts;
    if (ts == null) return l10n.fleetSeenNow;
    final minutos =
        DateTime.now()
            .difference(DateTime.fromMillisecondsSinceEpoch(ts))
            .inMinutes;
    return minutos < 1 ? l10n.fleetSeenNow : l10n.fleetSeenAgo('$minutos');
  }
}

class _UnidadMarker extends StatelessWidget {
  const _UnidadMarker({
    required this.color,
    required this.borderColor,
    required this.selected,
  });

  final Color color;
  final Color borderColor;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final size = selected ? 40.0 : 32.0;
    return Center(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: borderColor, width: selected ? 4 : 2),
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
          color: AppStatusColors.onColorFor(color),
          size: selected ? 22 : 18,
        ),
      ),
    );
  }
}
