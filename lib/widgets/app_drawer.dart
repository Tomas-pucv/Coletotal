import 'package:flutter/material.dart';

import 'package:taxi1/l10n/app_localizations.dart';
import 'package:taxi1/models/app_user.dart';
import 'package:taxi1/navigation/app_destination.dart';
import 'package:taxi1/screens/admin/choferes_admin_screen.dart';
import 'package:taxi1/screens/admin/paraderos_admin_screen.dart';
import 'package:taxi1/screens/admin/recorridos_admin_screen.dart';
import 'package:taxi1/screens/auth/login_screen.dart';
import 'package:taxi1/screens/auth/register_screen.dart';
import 'package:taxi1/screens/main_screen.dart';
import 'package:taxi1/screens/preferences_screen.dart';
import 'package:taxi1/services/auth_service.dart';
import 'package:taxi1/theme/app_colors.dart';
import 'package:taxi1/theme/app_spacing.dart';
import 'package:taxi1/utils/patente.dart';
import 'package:taxi1/utils/role_format.dart';

/// Menú lateral de ColeTotal.
///
/// Es el lugar donde el usuario ve *quién es* y *qué puede hacer*: la cabecera
/// resuelve la identidad y el cuerpo, la lista completa de destinos del rol. La
/// barra inferior sigue existiendo para lo que se usa a diario, pero sólo caben
/// tres cosas ahí y los roles tienen más.
///
/// Es `StatefulWidget` y escucha a [AuthService] por su cuenta: [MainScreen] lo
/// pasa como widget constante, así que si dependiera del `setState` del padre,
/// Flutter cortocircuitaría la reconstrucción (`identical(old, new)`) y el menú
/// se quedaría mostrando el rol anterior tras iniciar o cerrar sesión.
class AppDrawer extends StatefulWidget {
  const AppDrawer({super.key});

  @override
  State<AppDrawer> createState() => _AppDrawerState();
}

class _AppDrawerState extends State<AppDrawer> {
  final _auth = AuthService.instance;
  final _nav = MainNavigationController.instance;

  @override
  void initState() {
    super.initState();
    _auth.addListener(_onChanged);
    _nav.addListener(_onChanged);
  }

  @override
  void dispose() {
    _auth.removeListener(_onChanged);
    _nav.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  /// Cierra el menú y ejecuta la acción en el frame siguiente.
  ///
  /// Empujar una ruta con el drawer todavía animándose deja la transición a
  /// medias y, peor, el menú abierto detrás de la pantalla nueva.
  void _closeThen(VoidCallback action) {
    _nav.closeDrawer();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) action();
    });
  }

  void _push(Widget screen) {
    _closeThen(() {
      Navigator.of(
        context,
      ).push(MaterialPageRoute<void>(builder: (_) => screen));
    });
  }

  /// Pantalla apilada de cada destino que no es pestaña.
  ///
  /// Sólo cubre los de [Destinations.roleSectionFor]; el resto llega por otro
  /// camino, así que el caso por defecto no debería ocurrir y devuelve
  /// Preferencias en vez de reventar.
  Widget _screenFor(AppDestination destination) => switch (destination) {
    AppDestination.paraderos => const ParaderosAdminScreen(),
    AppDestination.recorridos => const RecorridosAdminScreen(),
    AppDestination.choferes => const ChoferesAdminScreen(),
    _ => const PreferencesScreen(showBackButton: true),
  };

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
    if (confirmed ?? false) await _auth.signOut();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final role = _auth.role;
    final tabs = Destinations.barFor(role);
    final roleSection = Destinations.roleSectionFor(role);
    final isGuest = role == UserRole.invitado;
    final showPreferences = !Destinations.isTab(
      AppDestination.preferencias,
      role,
    );

    return NavigationDrawer(
      selectedIndex: Destinations.tabIndex(_nav.destination, role),
      onDestinationSelected: (index) {
        final destination = tabs[index];
        _closeThen(() => _nav.go(destination));
      },
      children: [
        _AccountHeader(
          profile: _auth.profile,
          role: role,
          onSignIn: () => _push(const LoginScreen()),
          onRegister: () => _push(const RegisterScreen()),
        ),

        // Sólo las pestañas son `NavigationDrawerDestination`. El resto van
        // como `ListTile` a propósito: `NavigationDrawer` calcula
        // `selectedIndex` contando *únicamente* sus hijos de tipo destino, así
        // que mezclar acciones descuadraría el resaltado de todo lo que viene
        // después.
        for (final d in tabs)
          NavigationDrawerDestination(
            icon: Icon(d.icon),
            selectedIcon: Icon(d.selectedIcon),
            label: Text(d.label(l10n)),
          ),

        if (roleSection.isNotEmpty) ...[
          const _DrawerDivider(),
          _DrawerHeadline(
            role == UserRole.colectivero
                ? l10n.drawerDriverSection
                : l10n.drawerAdminSection,
          ),
          for (final d in roleSection)
            _DrawerAction(
              icon: d.icon,
              label: d.label(l10n),
              onTap: () => _push(_screenFor(d)),
            ),
        ],

        // Para el invitado, Preferencias ya es una pestaña y aparece arriba, e
        // "Iniciar sesión" está en la cabecera: no queda nada que poner acá.
        if (showPreferences || !isGuest) ...[
          const _DrawerDivider(),
          if (showPreferences)
            _DrawerAction(
              icon: AppDestination.preferencias.icon,
              label: l10n.navPreferences,
              onTap: () => _push(const PreferencesScreen(showBackButton: true)),
            ),
          if (!isGuest)
            _DrawerAction(
              icon: Icons.logout,
              label: l10n.signOut,
              onTap: () => _closeThen(() => _confirmSignOut(l10n)),
            ),
        ],

        const SizedBox(height: AppSpacing.lg),
      ],
    );
  }
}

/// Cabecera de identidad: quién eres y con qué permisos.
///
/// Va sobre una tarjeta gris y el amarillo queda sólo en el avatar, el
/// letrero del colectivo. Antes la tarjeta entera era del color de
/// `primaryContainer`, que con la paleta negro y amarillo es amarillo pleno:
/// quedaba pegada a la fila seleccionada, también amarilla, y la insignia
/// "Colectivero" (amarilla) desaparecía contra ella.
class _AccountHeader extends StatelessWidget {
  const _AccountHeader({
    required this.profile,
    required this.role,
    required this.onSignIn,
    required this.onRegister,
  });

  final AppUser? profile;
  final UserRole role;
  final VoidCallback onSignIn;
  final VoidCallback onRegister;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final badge = roleBadgeColors(role, scheme);
    final isGuest = role == UserRole.invitado;
    // El amarillo del letrero en ambos temas: de noche `primaryContainer` es
    // oliva oscuro y el amarillo es `primary`.
    final (avatarFondo, avatarTinta) = scheme.brightness == Brightness.light
        ? (scheme.primaryContainer, scheme.onPrimaryContainer)
        : (scheme.primary, scheme.onPrimary);

    return Container(
      margin: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: avatarFondo,
                foregroundColor: avatarTinta,
                child: isGuest
                    ? Icon(roleIcon(role), size: 26)
                    : Text(
                        profile!.initials,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: avatarTinta,
                          fontWeight: FontWeight.w700,
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
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: scheme.onSurface,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    // La insignia dice "te llamas X y tu rol es Y". Para el
                    // invitado el nombre ya es el rol, así que repetirlo
                    // justo debajo sólo añade ruido.
                    if (!isGuest) ...[
                      const SizedBox(height: AppSpacing.xs),
                      // Wrap y no Row: con la fuente al 140% la insignia y la
                      // patente pasan a dos líneas en vez de desbordar.
                      Wrap(
                        spacing: AppSpacing.sm,
                        runSpacing: AppSpacing.xs,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          _RoleBadge(
                            label: roleLabel(role, l10n),
                            icon: roleIcon(role),
                            background: badge.background,
                            foreground: badge.foreground,
                          ),
                          if (profile?.patente case final patente?)
                            _Patente(formatPatente(patente)),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          // A todo el ancho y no al lado del avatar: ahí no cabía y la última
          // palabra quedaba sola en una segunda línea.
          const SizedBox(height: AppSpacing.md),
          Text(
            roleSubtitle(role, l10n),
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),

          // El invitado no tiene nada que gestionar en el menú, así que la
          // cabecera es justamente el lugar donde ofrecerle entrar: es lo
          // primero que ve al abrirlo. Uno debajo del otro y a lo ancho: lado
          // a lado no cabían y cada texto se partía en dos líneas.
          if (isGuest) ...[
            const SizedBox(height: AppSpacing.lg),
            FilledButton.icon(
              onPressed: onSignIn,
              icon: const Icon(Icons.login, size: 18),
              label: Text(l10n.signIn),
            ),
            const SizedBox(height: AppSpacing.sm),
            OutlinedButton(
              onPressed: onRegister,
              child: Text(l10n.createAccount),
            ),
          ],
        ],
      ),
    );
  }
}

class _RoleBadge extends StatelessWidget {
  const _RoleBadge({
    required this.label,
    required this.icon,
    required this.background,
    required this.foreground,
  });

  final String label;
  final IconData icon;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        // El borde la separa del fondo aunque los dos sean del mismo tono.
        border: Border.all(color: foreground.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: foreground),
          const SizedBox(width: AppSpacing.xs),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: foreground,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// La patente del colectivo dibujada como la placa chilena: blanca, con letras
/// negras y borde oscuro. Es blanca también en el tema oscuro, porque así es la
/// placa de verdad y así la reconoce el chofer de un vistazo.
class _Patente extends StatelessWidget {
  const _Patente(this.texto);

  final String texto;

  static const _placa = Colors.white;
  static const _letras = kColeTotalInk;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: _placa,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: _letras, width: 1.5),
      ),
      child: Text(
        texto,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: _letras,
          fontWeight: FontWeight.w700,
          fontFeatures: const [FontFeature.tabularFigures()],
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

/// Encabezado de grupo dentro del menú, con el mismo tratamiento tipográfico
/// que [SettingsSection] para que las dos superficies se lean como una sola app.
class _DrawerHeadline extends StatelessWidget {
  const _DrawerHeadline(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: Text(
        label.toUpperCase(),
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _DrawerDivider extends StatelessWidget {
  const _DrawerDivider();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(
      horizontal: AppSpacing.lg,
      vertical: AppSpacing.sm,
    ),
    child: Divider(),
  );
}

/// Entrada del menú que ejecuta una acción o abre una pantalla apilada, en vez
/// de cambiar de pestaña. Replica el aspecto de `NavigationDrawerDestination`
/// sin participar de su índice de selección.
class _DrawerAction extends StatelessWidget {
  const _DrawerAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: ListTile(
        leading: Icon(icon),
        title: Text(label, style: theme.textTheme.labelLarge),
        onTap: onTap,
        shape: const StadiumBorder(),
      ),
    );
  }
}
