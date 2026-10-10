import 'package:flutter/material.dart';

import 'package:taxi1/l10n/app_localizations.dart';
import 'package:taxi1/navigation/app_destination.dart';
import 'package:taxi1/screens/admin/choferes_admin_screen.dart';
import 'package:taxi1/screens/admin/recorridos_admin_screen.dart';
import 'package:taxi1/screens/main_screen.dart';
import 'package:taxi1/services/auth_service.dart';
import 'package:taxi1/services/firebase_telemetria_service.dart';
import 'package:taxi1/services/garita_service.dart';
import 'package:taxi1/services/recorridos_service.dart';
import 'package:taxi1/theme/app_spacing.dart';
import 'package:taxi1/theme/breakpoints.dart';
import 'package:taxi1/widgets/settings_section.dart';
import 'package:taxi1/widgets/state_views.dart';

/// Portada del administrador de garita.
///
/// Responde de un vistazo "¿cómo va la línea ahora?" con tres números, y desde
/// ahí se entra a cada herramienta. Las secciones de gestión son pantallas
/// apiladas y no pestañas porque se entra a hacer algo y se vuelve, no son
/// lugares donde uno se queda.
class GaritaHubScreen extends StatefulWidget {
  const GaritaHubScreen({super.key});

  @override
  State<GaritaHubScreen> createState() => _GaritaHubScreenState();
}

class _GaritaHubScreenState extends State<GaritaHubScreen> {
  final _auth = AuthService.instance;
  final _garita = GaritaService.instance;
  final _recorridos = RecorridosService.instance;
  final _telemetria = FirebaseTelemetriaService.instance;

  @override
  void initState() {
    super.initState();
    _auth.addListener(_onChanged);
    _garita.addListener(_onChanged);
    _recorridos.addListener(_onChanged);
    // La flota la lee una sola suscripción compartida por toda la app; acá
    // sólo se cuenta.
    _telemetria.state.addListener(_onChanged);
  }

  @override
  void dispose() {
    _auth.removeListener(_onChanged);
    _garita.removeListener(_onChanged);
    _recorridos.removeListener(_onChanged);
    _telemetria.state.removeListener(_onChanged);
    super.dispose();
  }

  /// Unidades en servicio de esta garita.
  int get _unidades {
    final gid = _auth.garitaId;
    final todas = _telemetria.state.value.colectivos;
    return gid == null
        ? todas.length
        : todas.where((c) => c.garitaId == gid).length;
  }

  int get _choferesCount => _garita.choferes.length;

  void _onChanged() {
    if (mounted) setState(() {});
  }

  void _push(Widget screen) => Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => screen));

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        title: Text(AppDestination.garita.label(l10n)),
        leading: IconButton(
          icon: const Icon(Icons.menu),
          tooltip: l10n.openMenu,
          onPressed: MainNavigationController.instance.openDrawer,
        ),
      ),
      body: !_auth.isAdmin
          ? StatusMessageView(
              icon: Icons.apartment_outlined,
              title: AppDestination.garita.label(l10n),
              message: l10n.adminOnly,
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
                    _metrics(l10n),
                    const SizedBox(height: AppSpacing.xl),
                    SettingsSection(
                      icon: Icons.alt_route,
                      title: l10n.adminRoutesDesc,
                      children: [
                        _tile(
                          icon: AppDestination.recorridos.icon,
                          title: AppDestination.recorridos.label(l10n),
                          subtitle: 'Líneas oficiales y cartolas de ida y vuelta',
                          onTap: () => _push(const RecorridosAdminScreen()),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    SettingsSection(
                      icon: Icons.groups_outlined,
                      title: l10n.adminSectionOps,
                      children: [
                        _tile(
                          icon: AppDestination.choferes.icon,
                          title: AppDestination.choferes.label(l10n),
                          subtitle: l10n.adminDriversDesc,
                          onTap: () => _push(const ChoferesAdminScreen()),
                        ),
                        _tile(
                          icon: AppDestination.flota.icon,
                          title: AppDestination.flota.label(l10n),
                          subtitle: l10n.adminFleetDesc,
                          onTap: () => MainNavigationController.instance.go(
                            AppDestination.flota,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _metrics(AppLocalizations l10n) {
    return Padding(
      padding: AppSpacing.pageHorizontal,
      child: Row(
        children: [
          Expanded(
            child: _MetricTile(
              icon: Icons.local_taxi,
              value: '$_unidades',
              label: l10n.adminMetricUnits,
              highlight: _unidades > 0,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: _MetricTile(
              icon: Icons.badge_outlined,
              value: '$_choferesCount',
              label: 'Choferes',
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: _MetricTile(
              icon: Icons.alt_route,
              value: '${_recorridos.porGarita(_auth.garitaId ?? '').length}',
              label: l10n.adminMetricRoutes,
            ),
          ),
        ],
      ),
    );
  }

  Widget _tile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.xs,
      ),
      child: Card(
        child: ListTile(
          leading: Icon(icon),
          title: Text(title),
          subtitle: Text(subtitle),
          trailing: const Icon(Icons.chevron_right),
          onTap: onTap,
        ),
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.icon,
    required this.value,
    required this.label,
    this.highlight = false,
  });

  final IconData icon;
  final String value;
  final String label;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Card(
      color: highlight ? scheme.primaryContainer : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.lg,
        ),
        child: Column(
          children: [
            Icon(
              icon,
              color: highlight ? scheme.onPrimaryContainer : scheme.primary,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              value,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: highlight ? scheme.onPrimaryContainer : scheme.onSurface,
              ),
            ),
            Text(
              label,
              textAlign: TextAlign.center,
              style: theme.textTheme.labelSmall?.copyWith(
                color: highlight
                    ? scheme.onPrimaryContainer
                    : scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
