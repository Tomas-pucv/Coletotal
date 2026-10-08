import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import 'package:taxi1/config/map_config.dart';
import 'package:taxi1/l10n/app_localizations.dart';
import 'package:taxi1/models/colectivo_activo.dart';
import 'package:taxi1/models/garita.dart';
import 'package:taxi1/navigation/app_destination.dart';
import 'package:taxi1/screens/main_screen.dart';
import 'package:taxi1/services/auth_service.dart';
import 'package:taxi1/services/firebase_telemetria_service.dart';
import 'package:taxi1/services/garita_service.dart';
import 'package:taxi1/services/recorridos_service.dart';
import 'package:taxi1/theme/app_colors.dart';
import 'package:taxi1/theme/app_spacing.dart';
import 'package:taxi1/utils/estado_format.dart';
import 'package:taxi1/utils/patente.dart';
import 'package:taxi1/widgets/app_map.dart';
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

class _FlotaScreenState extends State<FlotaScreen> {
  final _mapController = AppMapController();
  final _auth = AuthService.instance;
  final _nav = MainNavigationController.instance;
  final _telemetria = FirebaseTelemetriaService.instance;
  final _recorridos = RecorridosService.instance;

  TelemetriaState _estado = const TelemetriaState();
  String? _selected;

  /// Garitas para el filtro. Antes eran cuatro chips escritos a mano en esta
  /// pantalla, con ids fijos y un caso especial para unidades sin garita.
  List<Garita> _garitas = const [];

  /// Garita filtrada; `null` es "todas". Arranca en la del administrador: es
  /// la que gestiona y la que las reglas le dejan administrar.
  String? _filtroGarita;

  bool get _visible => _nav.destination == AppDestination.flota;

  List<ColectivoActivo> get _unidadesFiltradas {
    final filtro = _filtroGarita;
    if (filtro == null) return _estado.colectivos;
    return _estado.colectivos
        .where((c) => c.garitaId == filtro)
        .toList(growable: false);
  }

  @override
  void initState() {
    super.initState();
    _filtroGarita = _auth.garitaId;
    _estado = _telemetria.state.value;

    _auth.addListener(_onChanged);
    _recorridos.addListener(_onChanged);
    _nav.addListener(_onNavChanged);
    _telemetria.state.addListener(_onTelemetria);

    GaritaService.instance.loadGaritas().then((garitas) {
      if (mounted) setState(() => _garitas = garitas);
    });
  }

  @override
  void dispose() {
    _auth.removeListener(_onChanged);
    _recorridos.removeListener(_onChanged);
    _nav.removeListener(_onNavChanged);
    _telemetria.state.removeListener(_onTelemetria);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  /// La pestaña sigue montada aunque no se vea (el `IndexedStack` conserva su
  /// estado). Mientras está oculta no se redibuja con cada movimiento de la
  /// flota; al volver a ella se pone al día de una vez.
  void _onTelemetria() {
    if (!_visible || !mounted) return;
    setState(() => _estado = _telemetria.state.value);
  }

  void _onNavChanged() {
    if (_visible && mounted) {
      setState(() => _estado = _telemetria.state.value);
    }
  }

  void _focus(ColectivoActivo unidad) {
    setState(() => _selected = unidad.uid);
    _mapController.animateTo(
      LatLng(unidad.latitud, unidad.longitud),
      zoom: kStreetZoom,
    );
  }

  ColectivoActivo? get _unidadSeleccionada {
    for (final c in _estado.colectivos) {
      if (c.uid == _selected) return c;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final status = AppStatusColors.of(context);

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

    final unidades = _unidadesFiltradas;
    final ahora = _telemetria.serverNow();
    final seleccionada = _unidadSeleccionada;
    final linea = seleccionada?.recorridoId == null
        ? null
        : _recorridos.byId(seleccionada!.recorridoId!);
    final trazado = linea == null
        ? const <LatLng>[]
        : (linea.trazado.length >= 2
              ? linea.trazado
              : _recorridos.puntosDe(linea));

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
                l10n.fleetUnitsInService('${unidades.length}'),
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
          _filtroGarita == null && _garitas.isEmpty
              ? const SizedBox.shrink()
              : _garitaChips(l10n),
          Expanded(
            flex: 3,
            child: Stack(
              children: [
                AppMap(
                  controller: _mapController,
                  initialCenter: kQuilpueCenter,
                  // Al elegir una unidad se ilumina la línea que informa estar
                  // cubriendo.
                  lines: [
                    if (linea != null && trazado.length > 1)
                      MapLine(
                        points: trazado,
                        width: 5,
                        color: Color(linea.colorValue).withValues(alpha: 0.85),
                        borderColor: status.routeLineCasing,
                        borderWidth: 1.5,
                      ),
                  ],
                  markers: [
                    for (final unidad in unidades)
                      _marcador(
                        unidad,
                        status: status,
                        selected: _selected == unidad.uid,
                        offline: unidad.seemsOffline(ahora),
                      ),
                  ],
                ),
                if (_estado.failed)
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
            child: unidades.isEmpty
                ? (_estado.loaded
                      ? StatusMessageView(
                          icon: Icons.local_taxi_outlined,
                          title: l10n.fleetEmpty,
                          message: l10n.fleetEmptyHint,
                        )
                      : const LoadingView())
                : ListView.separated(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    itemCount: unidades.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: AppSpacing.sm),
                    itemBuilder: (context, index) {
                      final unidad = unidades[index];
                      final color = status.forEstado(unidad.estado);
                      return MapOverlayCard(
                        onTap: () => _focus(unidad),
                        child: Row(
                          children: [
                            Icon(Icons.directions_car, color: color),
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
                                    unidad.seemsOffline(ahora)
                                        ? l10n.colectivoNoSignal
                                        : estadoLabel(unidad.estado, l10n),
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: unidad.seemsOffline(ahora)
                                          ? theme.colorScheme.onSurfaceVariant
                                          : color,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              _seenLabel(unidad, ahora, l10n),
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

  Widget _garitaChips(AppLocalizations l10n) {
    final theme = Theme.of(context);
    final propia = _auth.garitaId;
    // La propia garita aparece aunque la lista no se haya podido leer.
    final garitas = [
      ..._garitas,
      if (propia != null && !_garitas.any((g) => g.id == propia))
        Garita(id: propia, nombre: propia),
    ];
    final opciones = <(String?, String)>[
      (null, l10n.fleetAllGaritas),
      for (final g in garitas) (g.id, g.nombre),
    ];

    return Container(
      height: 48,
      color: theme.colorScheme.surface,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: 6,
        ),
        itemCount: opciones.length,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
        itemBuilder: (context, i) {
          final (gid, nombre) = opciones[i];
          final isSel = _filtroGarita == gid;
          return ChoiceChip(
            selected: isSel,
            showCheckmark: false,
            label: Text(nombre),
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
    );
  }

  /// Una unidad en el mapa. Sin señal reciente se atenúa, igual que en el mapa
  /// del pasajero.
  MapMarker _marcador(
    ColectivoActivo unidad, {
    required AppStatusColors status,
    required bool selected,
    required bool offline,
  }) {
    final color = status.forEstado(unidad.estado);
    return MapMarker(
      id: unidad.uid,
      point: LatLng(unidad.latitud, unidad.longitud),
      icon: MarkerIcon.circle(
        diameter: selected ? 40 : 32,
        color: color,
        borderColor: status.markerBorder,
        borderWidth: selected ? 4 : 2,
        glyph: Icons.directions_car,
        glyphColor: AppStatusColors.onColorFor(color),
        glyphSize: selected ? 22 : 18,
        shadow: const BoxShadow(
          color: Color(0x59000000),
          blurRadius: 6,
          offset: Offset(0, 2),
        ),
        tapTarget: 44,
      ),
      opacity: offline ? 0.45 : 1,
      onTap: () => _focus(unidad),
    );
  }

  /// "Ahora mismo" o "Hace N min", medido contra la hora del servidor: el
  /// reloj del teléfono del administrador puede estar desfasado.
  static String _seenLabel(
    ColectivoActivo unidad,
    DateTime ahora,
    AppLocalizations l10n,
  ) {
    final age = unidad.antiguedad(ahora);
    if (age == null || age.inMinutes < 1) return l10n.fleetSeenNow;
    return l10n.fleetSeenAgo('${age.inMinutes}');
  }
}
