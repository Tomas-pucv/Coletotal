import 'dart:async';

import 'package:flutter/material.dart';

import 'package:taxi1/l10n/app_localizations.dart';
import 'package:taxi1/models/app_user.dart';
import 'package:taxi1/models/colectivo_activo.dart';
import 'package:taxi1/models/recorrido.dart';
import 'package:taxi1/models/variante.dart';
import 'package:taxi1/screens/main_screen.dart';
import 'package:taxi1/services/auth_service.dart';
import 'package:taxi1/services/turno_service.dart';
import 'package:taxi1/theme/app_colors.dart';
import 'package:taxi1/theme/app_spacing.dart';
import 'package:taxi1/theme/breakpoints.dart';
import 'package:taxi1/utils/distance_format.dart';
import 'package:taxi1/utils/patente.dart';
import 'package:taxi1/widgets/settings_section.dart';
import 'package:taxi1/widgets/state_views.dart';

/// Pantalla de jornada del colectivero — el "módulo conductor" del informe
/// (§7.3.1-A).
///
/// Pocos controles, porque quien la usa está manejando: un interruptor grande
/// de turno, el recorrido que cubre y un selector de capacidad de un solo
/// toque. Todo lo demás es información de confirmación, para que el chofer
/// sepa sin dudar si está transmitiendo o no.
class TurnoScreen extends StatefulWidget {
  const TurnoScreen({super.key});

  @override
  State<TurnoScreen> createState() => _TurnoScreenState();
}

class _TurnoScreenState extends State<TurnoScreen> {
  final _turno = TurnoService.instance;
  final _auth = AuthService.instance;

  @override
  void initState() {
    super.initState();
    _turno.addListener(_onChanged);
    _auth.addListener(_onChanged);
  }

  @override
  void dispose() {
    _turno.removeListener(_onChanged);
    _auth.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final profile = _auth.profile;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.turnoTitle),
        leading: IconButton(
          icon: const Icon(Icons.menu),
          tooltip: l10n.openMenu,
          onPressed: MainNavigationController.instance.openDrawer,
        ),
      ),
      body: profile == null || profile.rol != UserRole.colectivero
          ? StatusMessageView(
              icon: Icons.local_taxi_outlined,
              title: l10n.turnoTitle,
              message: l10n.turnoOnlyDrivers,
            )
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: Breakpoints.maxContentWidth,
                ),
                child: ListView(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
                  children: [
                    const SizedBox(height: AppSpacing.md),
                    _turnoCard(l10n),
                    const SizedBox(height: AppSpacing.xl),
                    _recorridoSection(l10n),
                    const SizedBox(height: AppSpacing.xl),
                    if (_turno.enTurno) ...[
                      _capacitySection(l10n),
                      const SizedBox(height: AppSpacing.xl),
                    ],
                    _vehicleSection(l10n, profile),
                    const SizedBox(height: AppSpacing.xl),
                    Padding(
                      padding: AppSpacing.pageHorizontal,
                      child: InlineNotice(
                        icon: Icons.privacy_tip_outlined,
                        message: l10n.turnoConsent,
                        tone: StatusTone.neutral,
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  /// El control principal. Ocupa una tarjeta entera y cambia de color: desde el
  /// asiento del conductor tiene que poder leerse de un vistazo si se está
  /// transmitiendo.
  Widget _turnoCard(AppLocalizations l10n) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final status = AppStatusColors.of(context);
    final activo = _turno.enTurno;

    return Padding(
      padding: AppSpacing.pageHorizontal,
      child: Card(
        color: activo ? scheme.primaryContainer : scheme.surfaceContainer,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    activo ? Icons.podcasts : Icons.pause_circle_outline,
                    size: 32,
                    color: activo ? status.disponible : scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          activo ? l10n.turnoOn : l10n.turnoOff,
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: activo
                                ? scheme.onPrimaryContainer
                                : scheme.onSurface,
                          ),
                        ),
                        Text(
                          activo ? l10n.turnoOnDesc : l10n.turnoOffDesc,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: activo
                                ? scheme.onPrimaryContainer
                                : scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              FilledButton.icon(
                onPressed: _turno.busy
                    ? null
                    : (activo ? _turno.terminarTurno : _turno.iniciarTurno),
                style: activo
                    ? FilledButton.styleFrom(
                        backgroundColor: scheme.errorContainer,
                        foregroundColor: scheme.onErrorContainer,
                      )
                    : null,
                icon: _turno.busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(activo ? Icons.stop : Icons.play_arrow),
                label: Text(activo ? l10n.turnoEnd : l10n.turnoStart),
              ),

              if (_issueMessage(l10n) case final message?) ...[
                const SizedBox(height: AppSpacing.md),
                InlineNotice(
                  icon: Icons.warning_amber_outlined,
                  message: message,
                  tone: StatusTone.warning,
                ),
              ],

              if (activo) ...[
                const SizedBox(height: AppSpacing.md),
                _UltimoEnvioLabel(color: scheme.onPrimaryContainer),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// La línea que se está cubriendo. Es lo que ve el pasajero al tocar el
  /// colectivo en el mapa: su trazado se ilumina. Antes no había dónde
  /// elegirla y esa función del mapa nunca se activaba.
  Widget _recorridoSection(AppLocalizations l10n) {
    final theme = Theme.of(context);
    final recorrido = _turno.recorridoAsignado;
    final opciones = _turno.recorridosDisponibles;

    return SettingsSection(
      icon: Icons.timeline_outlined,
      title: l10n.turnoRoute,
      children: [
        Padding(
          padding: AppSpacing.pageHorizontal,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: recorrido == null
                        ? theme.colorScheme.surfaceContainerHighest
                        : Color(recorrido.colorValue),
                    child: Icon(
                      recorrido == null ? Icons.block : Icons.timeline,
                      color: recorrido == null
                          ? theme.colorScheme.onSurfaceVariant
                          : Colors.white,
                      size: 20,
                    ),
                  ),
                  title: Text(recorrido?.nombre ?? l10n.turnoRouteNone),
                  subtitle: recorrido?.varianteNombre.isNotEmpty == true
                      ? Text('Variante: ${recorrido!.varianteNombre}')
                      : null,
                  trailing: const Icon(Icons.chevron_right),
                  enabled: opciones.isNotEmpty,
                  onTap: opciones.isEmpty ? null : () => _pickRecorrido(l10n),
                ),
              ),
              if (recorrido != null) ...[
                const SizedBox(height: AppSpacing.md),
                SegmentedButton<bool>(
                  showSelectedIcon: false,
                  selected: {_turno.sentidoIda},
                  onSelectionChanged: (s) => _turno.setSentidoIda(s.first),
                  segments: const [
                    ButtonSegment(
                      value: true,
                      icon: Icon(Icons.arrow_forward, size: 16),
                      label: Text('Ida'),
                    ),
                    ButtonSegment(
                      value: false,
                      icon: Icon(Icons.arrow_back, size: 16),
                      label: Text('Vuelta'),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Builder(
                  builder: (_) {
                    final calles = _turno.sentidoIda
                        ? recorrido.callesIda
                        : recorrido.callesVuelta;
                    if (calles.isEmpty) return const SizedBox.shrink();
                    return Container(
                      padding: const EdgeInsets.all(AppSpacing.sm),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'Cartola ${_turno.sentidoIda ? "Ida" : "Vuelta"}: ${calles.join(" → ")}',
                        style: theme.textTheme.bodySmall,
                      ),
                    );
                  },
                ),
              ],
              const SizedBox(height: AppSpacing.sm),
              Text(
                opciones.isEmpty ? l10n.turnoRouteEmpty : l10n.turnoRouteHelp,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _pickRecorrido(AppLocalizations l10n) async {
    final opciones = _turno.recorridosDisponibles;
    final actual = _turno.recorridoAsignado;

    final elegido = await showModalBottomSheet<_RecorridoChoice>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Text(
                l10n.turnoRoutePick,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            ListTile(
              leading: const Icon(Icons.block),
              title: Text(l10n.turnoRouteNone),
              selected: actual == null,
              onTap: () => Navigator.pop(context, const _RecorridoChoice(null)),
            ),
            for (final r in opciones)
              ListTile(
                leading: CircleAvatar(
                  radius: 14,
                  backgroundColor: Color(r.colorValue),
                ),
                title: Text(r.nombre),
                subtitle: Text(l10n.routeStopCount('${r.paraderoIds.length}')),
                selected: actual?.id == r.id,
                onTap: () => Navigator.pop(context, _RecorridoChoice(r)),
              ),
          ],
        ),
      ),
    );

    // `null` es cerrar la hoja sin elegir; "Sin recorrido" viene envuelto.
    if (elegido == null) return;
    await _turno.setRecorridoAsignado(elegido.recorrido);
  }

  /// Semaforización del informe §7.3.1-C.
  ///
  /// `SegmentedButton` y no un interruptor binario: sigue siendo un solo toque
  /// —el mismo coste cognitivo que exige el informe— pero permite el estado
  /// intermedio, que es el que hace útil el semáforo para el administrador.
  Widget _capacitySection(AppLocalizations l10n) {
    final status = AppStatusColors.of(context);

    return SettingsSection(
      icon: Icons.event_seat_outlined,
      title: l10n.turnoCapacity,
      children: [
        Padding(
          padding: AppSpacing.pageHorizontal,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SegmentedButton<EstadoCapacidad>(
                selected: {_turno.estado},
                onSelectionChanged: (s) => _turno.setEstado(s.first),
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(
                    value: EstadoCapacidad.disponible,
                    icon: Icon(
                      Icons.circle,
                      size: 14,
                      color: status.disponible,
                    ),
                    label: Text(l10n.capacityAvailable),
                  ),
                  ButtonSegment(
                    value: EstadoCapacidad.medioLleno,
                    icon: Icon(
                      Icons.circle,
                      size: 14,
                      color: status.medioLleno,
                    ),
                    label: Text(l10n.capacityHalf),
                  ),
                  ButtonSegment(
                    value: EstadoCapacidad.lleno,
                    icon: Icon(Icons.circle, size: 14, color: status.lleno),
                    label: Text(l10n.capacityFull),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                l10n.turnoCapacityHelp,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _vehicleSection(AppLocalizations l10n, AppUser profile) {
    final theme = Theme.of(context);
    final variante = varianteById(profile.varianteId);

    return SettingsSection(
      icon: Icons.directions_car_outlined,
      title: l10n.turnoVehicle,
      children: [
        Padding(
          padding: AppSpacing.pageHorizontal,
          child: Card(
            child: ListTile(
              leading: const Icon(Icons.directions_car),
              title: Text(
                profile.patente == null
                    ? profile.displayName
                    : formatPatente(profile.patente!),
                style: theme.textTheme.titleMedium?.copyWith(
                  letterSpacing: 1.5,
                ),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(profile.displayName),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        Icons.alt_route,
                        size: 14,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        variante != null
                            ? 'Variante: ${variante.nombre}'
                            : (profile.varianteId != null &&
                                    profile.varianteId!.isNotEmpty
                                ? 'Variante: ${profile.varianteId}'
                                : 'Sin variante asignada (todas autorizadas)'),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  String? _issueMessage(AppLocalizations l10n) => switch (_turno.issue) {
    TurnoIssue.none => null,
    TurnoIssue.trackingDisabled => l10n.turnoIssueTracking,
    TurnoIssue.cuentaInactiva => l10n.turnoIssueInactive,
    TurnoIssue.ubicacionNoDisponible => l10n.turnoIssueLocation,
  };
}

/// Lo que devuelve la hoja de recorridos. Envolverlo distingue "eligió Sin
/// recorrido" (`recorrido` nulo) de "cerró la hoja" (la hoja devuelve `null`).
class _RecorridoChoice {
  const _RecorridoChoice(this.recorrido);
  final Recorrido? recorrido;
}

/// "Última posición enviada hace X" y, sin conexión, el aviso de que se
/// enviará al volver la señal.
///
/// Antes esta línea sólo se redibujaba cuando cambiaba algo del turno: el
/// envío de posiciones no avisaba a nadie, así que mostraba siempre la misma
/// hora (o "aún no se ha enviado") y el chofer no podía confirmar que estaba
/// transmitiendo. Ahora escucha cada envío y avanza segundo a segundo.
class _UltimoEnvioLabel extends StatefulWidget {
  const _UltimoEnvioLabel({required this.color});

  final Color color;

  @override
  State<_UltimoEnvioLabel> createState() => _UltimoEnvioLabelState();
}

class _UltimoEnvioLabelState extends State<_UltimoEnvioLabel> {
  late final Timer _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final turno = TurnoService.instance;
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return ListenableBuilder(
      listenable: Listenable.merge([turno.ultimoEnvio, turno.conectado]),
      builder: (context, _) {
        final ultimo = turno.ultimoEnvio.value;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              ultimo == null
                  ? l10n.turnoNoSignal
                  : l10n.turnoLastSent(
                      formatAgo(DateTime.now().difference(ultimo), l10n),
                    ),
              style: theme.textTheme.labelSmall?.copyWith(color: widget.color),
            ),
            if (!turno.conectado.value) ...[
              const SizedBox(height: AppSpacing.sm),
              InlineNotice(
                icon: Icons.signal_cellular_connected_no_internet_0_bar,
                message: l10n.turnoOffline,
              ),
            ],
          ],
        );
      },
    );
  }
}
