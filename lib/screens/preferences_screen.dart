import 'package:flutter/material.dart';

import 'package:taxi1/config/app_version.dart';
import 'package:taxi1/l10n/app_localizations.dart';
import 'package:taxi1/models/app_user.dart';
import 'package:taxi1/screens/auth/login_screen.dart';
import 'package:taxi1/screens/main_screen.dart';
import 'package:taxi1/services/app_update_service.dart';
import 'package:taxi1/services/auth_service.dart';
import 'package:taxi1/services/preferences_service.dart';
import 'package:taxi1/services/stop_history_service.dart';
import 'package:taxi1/theme/app_spacing.dart';
import 'package:taxi1/theme/breakpoints.dart';
import 'package:taxi1/utils/role_format.dart';
import 'package:taxi1/widgets/app_update_dialog.dart';
import 'package:taxi1/widgets/setting_tile.dart';
import 'package:taxi1/widgets/settings_section.dart';
import 'package:taxi1/widgets/state_views.dart';

/// Identifica el fade de entrada de la pantalla, para poder verificar en tests
/// que nunca queda en opacidad 0 (ver [_PreferencesScreenState.initState]).
const Key preferencesFadeKey = ValueKey('preferences-fade');

class PreferencesScreen extends StatefulWidget {
  const PreferencesScreen({super.key, this.showBackButton = false});

  /// Para el chofer y el administrador, Preferencias no es una pestaña sino una
  /// pantalla apilada que se abre desde el menú, así que necesita botón de
  /// volver en vez del de menú.
  final bool showBackButton;

  @override
  State<PreferencesScreen> createState() => _PreferencesScreenState();
}

class _PreferencesScreenState extends State<PreferencesScreen>
    with SingleTickerProviderStateMixin {
  final prefs = PreferencesService.instance;
  final history = StopHistoryService.instance;
  final auth = AuthService.instance;
  final updates = AppUpdateService.instance;
  late final AnimationController _fadeController;

  @override
  void initState() {
    super.initState();
    prefs.addListener(_onChanged);
    history.addListener(_onChanged);
    auth.addListener(_onChanged);
    updates.addListener(_onChanged);

    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    // Con las animaciones desactivadas el controller nunca avanzaba y el
    // FadeTransition se quedaba en opacidad 0: la pantalla entera quedaba
    // invisible, y como el interruptor para reactivarlas vive justamente acá,
    // no había forma de salir. Ahora el estado sin animación es "ya visible".
    if (prefs.animationsEnabled) {
      _fadeController.forward();
    } else {
      _fadeController.value = 1;
    }
  }

  @override
  void dispose() {
    prefs.removeListener(_onChanged);
    history.removeListener(_onChanged);
    auth.removeListener(_onChanged);
    updates.removeListener(_onChanged);
    _fadeController.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (!prefs.animationsEnabled && _fadeController.value < 1) {
      _fadeController.value = 1;
    }
    if (mounted) setState(() {});
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _confirmDisableTracking(AppLocalizations l10n) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.location_off_outlined),
        title: Text(l10n.disableTrackingTitle),
        content: Text(l10n.disableTrackingMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.confirm),
          ),
        ],
      ),
    );
    if (confirmed ?? false) await prefs.setLocationTracking(false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    if (!prefs.isInitialized) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.preferencesTitle)),
        body: const LoadingView(),
      );
    }

    return Scaffold(
      body: FadeTransition(
        opacity: _fadeController,
        key: preferencesFadeKey,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: Breakpoints.maxContentWidth,
            ),
            child: CustomScrollView(
              slivers: [
                // Título grande de M3: da a Preferencias el mismo encabezado
                // que Rutas, para que las pestañas se lean como una sola app.
                SliverAppBar.large(
                  title: Text(l10n.preferencesTitle),
                  // Con `Scaffold`s anidados Flutter no detecta solo que hay un
                  // drawer más arriba, así que el botón de menú va explícito.
                  leading: widget.showBackButton
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.menu),
                          tooltip: l10n.openMenu,
                          onPressed:
                              MainNavigationController.instance.openDrawer,
                        ),
                ),
                SliverList.list(
                  children: [
                    _accountSection(l10n),
                    const SizedBox(height: AppSpacing.xl),
                    _appearanceSection(l10n),
                    const SizedBox(height: AppSpacing.xl),
                    _privacySection(l10n),
                    const SizedBox(height: AppSpacing.xl),
                    _aboutSection(l10n),
                    const SizedBox(height: AppSpacing.xxl),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // --- Secciones -----------------------------------------------------------

  /// Estado de la cuenta.
  ///
  /// Reemplaza al antiguo selector "Pasajero / Chofer". Aquel era una
  /// *preferencia*: cualquiera lo cambiaba y se ponía a transmitir su GPS a la
  /// garita. El rol pasó a ser identidad, así que esta sección ya no elige
  /// nada, informa: quién eres y por dónde se entra o se sale.
  Widget _accountSection(AppLocalizations l10n) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final role = auth.role;
    final profile = auth.profile;
    final badge = roleBadgeColors(role, scheme);

    return SettingsSection(
      icon: Icons.account_circle_outlined,
      title: l10n.sectionAccount,
      children: [
        Padding(
          padding: AppSpacing.pageHorizontal,
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: badge.background,
                        foregroundColor: badge.foreground,
                        child: profile == null
                            ? Icon(roleIcon(role))
                            : Text(
                                profile.initials,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  color: badge.foreground,
                                ),
                              ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              profile?.displayName ?? l10n.roleGuest,
                              style: theme.textTheme.titleSmall,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            // Para el invitado el nombre *es* el rol, así que
                            // repetirlo debajo sería ruido.
                            if (profile != null)
                              Text(
                                roleLabel(role, l10n),
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    roleSubtitle(role, l10n),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: role == UserRole.invitado
                        ? FilledButton.tonalIcon(
                            onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => const LoginScreen(),
                              ),
                            ),
                            icon: const Icon(Icons.login, size: 18),
                            label: Text(l10n.signIn),
                          )
                        : TextButton.icon(
                            onPressed: () => _confirmSignOut(l10n),
                            icon: const Icon(Icons.logout, size: 18),
                            label: Text(l10n.signOut),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _confirmSignOut(AppLocalizations l10n) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.logout),
        title: Text(l10n.signOut),
        content: Text(l10n.signOutMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.signOut),
          ),
        ],
      ),
    );
    if (confirmed ?? false) await auth.signOut();
  }

  Widget _appearanceSection(AppLocalizations l10n) {
    return SettingsSection(
      icon: Icons.palette_outlined,
      title: l10n.sectionAppearance,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            0,
            AppSpacing.lg,
            AppSpacing.md,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.themeLabel,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: AppSpacing.sm),
              // SegmentedButton en vez de tres radios apilados: las tres
              // opciones son mutuamente excluyentes y cortas, y así se ven de
              // un vistazo en vez de ocupar tres filas.
              SegmentedButton<String>(
                showSelectedIcon: false,
                selected: {prefs.themeName},
                onSelectionChanged: (s) => prefs.setTheme(s.first),
                segments: [
                  ButtonSegment(
                    value: 'system',
                    icon: const Icon(Icons.brightness_auto, size: 18),
                    label: Text(l10n.themeSystemShort),
                    tooltip: l10n.themeSystem,
                  ),
                  ButtonSegment(
                    value: 'light',
                    icon: const Icon(Icons.light_mode, size: 18),
                    label: Text(l10n.themeLightShort),
                    tooltip: l10n.themeLight,
                  ),
                  ButtonSegment(
                    value: 'dark',
                    icon: const Icon(Icons.dark_mode, size: 18),
                    label: Text(l10n.themeDarkShort),
                    tooltip: l10n.themeDark,
                  ),
                ],
              ),
            ],
          ),
        ),
        SettingSliderTile(
          title: l10n.fontSize,
          value: prefs.fontSizeMultiplier,
          min: 0.8,
          max: 1.4,
          divisions: 6,
          valueLabel: '${(prefs.fontSizeMultiplier * 100).round()}%',
          onChanged: prefs.setFontSizeMultiplier,
        ),
        // Muestra en vivo: como el escalador es global, esta tarjeta crece a
        // medida que se arrastra el slider. El usuario ve el resultado sobre
        // contenido real en lugar de tener que adivinar qué significa "120%".
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            0,
            AppSpacing.lg,
            AppSpacing.md,
          ),
          child: _FontSizePreview(hint: l10n.fontSizePreviewHint),
        ),
        SettingSwitchTile(
          title: l10n.compactMode,
          subtitle: l10n.compactModeDesc,
          value: prefs.compactMode,
          onChanged: prefs.setCompactMode,
        ),
        SettingSwitchTile(
          title: l10n.animations,
          subtitle: l10n.animationsDesc,
          value: prefs.animationsEnabled,
          onChanged: prefs.setAnimationsEnabled,
        ),
      ],
    );
  }

  Widget _privacySection(AppLocalizations l10n) {
    return SettingsSection(
      icon: Icons.privacy_tip_outlined,
      title: l10n.sectionPrivacy,
      action: history.hasHistory
          ? TextButton(
              onPressed: () async {
                await history.clear();
                if (mounted) _toast(l10n.historyCleared);
              },
              child: Text(l10n.clearHistory),
            )
          : null,
      children: [
        SettingSwitchTile(
          title: l10n.locationTracking,
          subtitle: l10n.locationTrackingDesc,
          value: prefs.locationTracking,
          onChanged: (value) => value
              ? prefs.setLocationTracking(true)
              : _confirmDisableTracking(l10n),
        ),
        // Ya no es un interruptor decorativo: alimenta la fila "Consultados
        // recientemente" de la pestaña Rutas (ver StopHistoryService).
        SettingSwitchTile(
          title: l10n.saveHistory,
          subtitle: l10n.saveHistoryDesc('${StopHistoryService.maxEntries}'),
          value: prefs.historyEnabled,
          onChanged: prefs.setHistoryEnabled,
        ),
      ],
    );
  }

  Widget _aboutSection(AppLocalizations l10n) {
    return SettingsSection(
      icon: Icons.info_outline,
      title: l10n.sectionAbout,
      children: [
        Padding(
          padding: AppSpacing.pageHorizontal,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // La versión sale del propio APK (`AppVersion`): antes estaba
              // escrita a mano acá y ya no coincidía con la instalada.
              SettingInfoCard(
                title: l10n.aboutVersion(AppVersion.label),
                body: l10n.aboutSubtitle,
              ),
              const SizedBox(height: AppSpacing.sm),
              OutlinedButton.icon(
                onPressed: updates.checking ? null : () => _checkUpdates(l10n),
                icon: updates.checking
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.system_update_rounded),
                label: Text(l10n.updateCheck),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _checkUpdates(AppLocalizations l10n) async {
    await updates.checkForUpdates();
    if (!mounted) return;
    final info = updates.availableUpdate;
    if (updates.hasUpdate && info != null) {
      await AppUpdateDialog.showIfAvailable(context, info);
    } else {
      _toast(l10n.updateUpToDate(AppVersion.label));
    }
  }
}

/// Muestra de contenido real que crece con el ajuste de tamaño de fuente.
class _FontSizePreview extends StatelessWidget {
  const _FontSizePreview({required this.hint});

  final String hint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            Icon(Icons.directions_bus, color: theme.colorScheme.primary),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Plaza de Armas', style: theme.textTheme.titleSmall),
                  Text(
                    hint,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
