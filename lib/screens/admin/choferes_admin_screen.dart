import 'package:flutter/material.dart';

import 'package:taxi1/l10n/app_localizations.dart';
import 'package:taxi1/models/app_user.dart';
import 'package:taxi1/navigation/app_destination.dart';
import 'package:taxi1/services/firestore_writes.dart';
import 'package:taxi1/services/auth_service.dart';
import 'package:taxi1/services/firebase_telemetria_service.dart';
import 'package:taxi1/services/garita_service.dart';
import 'package:taxi1/theme/app_colors.dart';
import 'package:taxi1/theme/app_spacing.dart';
import 'package:taxi1/theme/breakpoints.dart';
import 'package:taxi1/utils/patente.dart';
import 'package:taxi1/widgets/state_views.dart';

/// Gestión de choferes de la garita.
///
/// Deliberadamente **lista + interruptor**, y nada más. No hay restablecer
/// contraseña ni borrar cuentas, y no es una omisión: el chofer entra con su
/// patente convertida en un correo sintético que no recibe mensajes, y cambiar
/// la contraseña de otra cuenta exige el Admin SDK, que no existe en un cliente
/// móvil. El flujo real de "perdí mi contraseña" es deshabilitar aquí y
/// entregar un código de garita nuevo.
class ChoferesAdminScreen extends StatefulWidget {
  const ChoferesAdminScreen({super.key});

  @override
  State<ChoferesAdminScreen> createState() => _ChoferesAdminScreenState();
}

class _ChoferesAdminScreenState extends State<ChoferesAdminScreen> {
  final _garita = GaritaService.instance;
  final _auth = AuthService.instance;
  final _telemetria = FirebaseTelemetriaService.instance;

  @override
  void initState() {
    super.initState();
    _garita.addListener(_onChanged);
    // Cruzar el padrón con la telemetría en vivo es lo que convierte una lista
    // de nombres en información útil: quién está trabajando ahora.
    _telemetria.state.addListener(_onChanged);
  }

  @override
  void dispose() {
    _garita.removeListener(_onChanged);
    _telemetria.state.removeListener(_onChanged);
    super.dispose();
  }

  Set<String> get _enServicio =>
      _telemetria.state.value.colectivos.map((c) => c.uid).toSet();

  void _onChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _toggle(AppUser chofer, bool activo) async {
    final l10n = AppLocalizations.of(context)!;
    try {
      final outcome = await _garita.setChoferActivo(chofer, activo);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              outcome == WriteOutcome.queuedOffline
                  ? l10n.savedOffline
                  : l10n.driverSaved,
            ),
          ),
        );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(l10n.errAuthUnknown)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final choferes = _garita.choferes;
    final enServicio = _enServicio;

    return Scaffold(
      appBar: AppBar(title: Text(AppDestination.choferes.label(l10n))),
      body: !_auth.isAdmin
          ? StatusMessageView(
              icon: Icons.lock_outline,
              title: AppDestination.choferes.label(l10n),
              message: l10n.adminOnly,
            )
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: Breakpoints.maxContentWidth,
                ),
                child: _garita.loading
                    ? const LoadingView()
                    : choferes.isEmpty
                    ? StatusMessageView(
                        icon: Icons.badge_outlined,
                        title: l10n.driversEmpty,
                        message: l10n.driversEmptyHint,
                      )
                    : ListView(
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        children: [
                          InlineNotice(
                            icon: Icons.info_outline,
                            message: l10n.driversNoPasswordReset,
                            tone: StatusTone.neutral,
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          for (final chofer in choferes) ...[
                            _ChoferTile(
                              chofer: chofer,
                              enServicio: enServicio.contains(chofer.uid),
                              onChanged: (v) => _toggle(chofer, v),
                            ),
                            const SizedBox(height: AppSpacing.sm),
                          ],
                          const SizedBox(height: AppSpacing.md),
                          Text(
                            l10n.driverEnableHelp,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                          ),
                        ],
                      ),
              ),
            ),
    );
  }
}

class _ChoferTile extends StatelessWidget {
  const _ChoferTile({
    required this.chofer,
    required this.enServicio,
    required this.onChanged,
  });

  final AppUser chofer;
  final bool enServicio;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final status = AppStatusColors.of(context);
    final l10n = AppLocalizations.of(context)!;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: chofer.activo
                  ? scheme.secondaryContainer
                  : scheme.surfaceContainerHighest,
              foregroundColor: chofer.activo
                  ? scheme.onSecondaryContainer
                  : scheme.onSurfaceVariant,
              child: Text(chofer.initials),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    chofer.nombre.trim().isEmpty
                        ? chofer.displayName
                        : chofer.nombre,
                    style: theme.textTheme.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.xs,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (chofer.patente case final patente?)
                        Text(
                          formatPatente(patente),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                            letterSpacing: 1.1,
                          ),
                        ),
                      if (enServicio)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.circle,
                              size: 10,
                              color: status.disponible,
                            ),
                            const SizedBox(width: AppSpacing.xs),
                            Text(
                              l10n.driverInService,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: status.disponible,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ],
              ),
            ),
            Switch(value: chofer.activo, onChanged: onChanged),
          ],
        ),
      ),
    );
  }
}
