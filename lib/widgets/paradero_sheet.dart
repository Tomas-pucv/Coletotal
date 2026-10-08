import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import 'package:taxi1/l10n/app_localizations.dart';
import 'package:taxi1/models/bus_stop.dart';
import 'package:taxi1/models/recorrido.dart';
import 'package:taxi1/screens/main_screen.dart';
import 'package:taxi1/services/location_service.dart';
import 'package:taxi1/services/recorridos_service.dart';
import 'package:taxi1/services/route_service.dart';
import 'package:taxi1/services/stop_history_service.dart';
import 'package:taxi1/theme/app_colors.dart';
import 'package:taxi1/theme/app_spacing.dart';
import 'package:taxi1/utils/distance_format.dart';
import 'package:taxi1/utils/route_error.dart';
import 'package:taxi1/widgets/state_views.dart';

/// Abre la ficha de un paradero: qué colectivos pasan por él y cómo llegar.
///
/// Es el paso intermedio que faltaba. Antes, tocar un paradero calculaba
/// directamente la ruta a pie y saltaba al mapa; ahora primero se responde la
/// pregunta que de verdad se hace en la calle — *qué me sirve de los que pasan
/// por aquí* — y desde ahí se elige.
Future<void> showParaderoSheet(BuildContext context, BusStop stop) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _ParaderoSheet(stop: stop),
  );
}

class _ParaderoSheet extends StatefulWidget {
  const _ParaderoSheet({required this.stop});

  final BusStop stop;

  @override
  State<_ParaderoSheet> createState() => _ParaderoSheetState();
}

class _ParaderoSheetState extends State<_ParaderoSheet> {
  final _recorridos = RecorridosService.instance;
  final _routes = RouteService.instance;
  final _location = LocationService.instance;

  bool _fetchingWalk = false;

  @override
  void initState() {
    super.initState();
    _recorridos.addListener(_onChanged);
    _location.addListener(_onChanged);
  }

  @override
  void dispose() {
    _recorridos.removeListener(_onChanged);
    _location.removeListener(_onChanged);
    super.dispose();
  }

  /// Desde dónde se mide y se rutea: la posición **actual**. Antes era el
  /// origen guardado en `RouteService`, que se fijaba con el primer punto GPS
  /// de la sesión, así que "Cómo llegar" trazaba la ruta desde donde el
  /// usuario estaba al abrir la app.
  LatLng? get _origin => _location.position ?? _routes.origin;

  void _onChanged() {
    if (mounted) setState(() {});
  }

  /// Muestra en el mapa por dónde va esa línea.
  Future<void> _verRecorrido(Recorrido recorrido) async {
    Navigator.of(context).pop();
    // La ruta a pie y el recorrido de la línea comparten la capa de polilíneas
    // del mapa: dibujar las dos a la vez sería ilegible.
    _routes.clearDestination();
    await _recorridos.select(recorrido);
    MainNavigationController.instance.showMap();
  }

  /// Ruta a pie desde la posición actual hasta el paradero.
  Future<void> _comoLlegar() async {
    if (_fetchingWalk) return;
    final l10n = AppLocalizations.of(context)!;

    // El messenger y el navigator se capturan **antes** de cerrar la hoja: en
    // cuanto se hace `pop`, el `context` de este widget queda desactivado y
    // buscar el ScaffoldMessenger a través de él es un uso después de la
    // muerte del elemento.
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final origin = _origin;

    if (origin == null) {
      navigator.pop();
      MainNavigationController.instance.showMap();
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(l10n.locationUnavailable)));
      return;
    }

    setState(() => _fetchingWalk = true);
    _recorridos.clearSelection();
    _routes.setDestination(widget.stop);
    final ok = await _routes.fetchRoute(origin, widget.stop);
    if (!mounted) return;

    StopHistoryService.instance.record(widget.stop);
    navigator.pop();
    MainNavigationController.instance.showMap();

    if (!ok) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text(routeErrorMessage(_routes.lastError, l10n))),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final lineas = _recorridos.porParadero(widget.stop.id);

    final origin = _origin;
    final metros = origin == null ? null : widget.stop.distanceFrom(origin);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          0,
          AppSpacing.lg,
          AppSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.pin_drop, color: scheme.primary),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.stop.name, style: theme.textTheme.titleLarge),
                      Text(
                        widget.stop.address,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      if (metros != null) ...[
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          formatDistance(metros, l10n),
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: proximityColor(
                              proximityOf(metros),
                              AppStatusColors.of(context),
                            ),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),

            FilledButton.tonalIcon(
              onPressed: _fetchingWalk ? null : _comoLlegar,
              icon: _fetchingWalk
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.directions_walk),
              label: Text(l10n.stopWalkHere),
            ),

            const SizedBox(height: AppSpacing.xl),
            Text(l10n.stopLinesTitle, style: theme.textTheme.titleSmall),
            const SizedBox(height: AppSpacing.sm),

            if (lineas.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                child: InlineNotice(
                  icon: Icons.info_outline,
                  message: '${l10n.stopLinesEmpty} ${l10n.stopLinesEmptyHint}',
                  tone: StatusTone.neutral,
                ),
              )
            else
              // `shrinkWrap` con la altura acotada: la hoja crece con el
              // contenido pero no pasa de media pantalla, para no tapar el mapa
              // entero cuando una garita tiene muchas líneas.
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.4,
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: lineas.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: AppSpacing.sm),
                  itemBuilder: (context, index) {
                    final linea = lineas[index];
                    return Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Color(linea.colorValue),
                          child: const Icon(
                            Icons.directions_car,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                        title: Text(linea.nombre),
                        subtitle: Text(
                          l10n.routeStopCount('${linea.paraderoIds.length}'),
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _verRecorrido(linea),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
