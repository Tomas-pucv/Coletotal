import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:taxi1/l10n/app_localizations.dart';
import 'package:taxi1/models/app_user.dart';
import 'package:taxi1/navigation/app_destination.dart';
import 'package:taxi1/screens/map_screen.dart';
import 'package:taxi1/screens/admin/choferes_admin_screen.dart';
import 'package:taxi1/screens/admin/flota_screen.dart';
import 'package:taxi1/screens/admin/garita_hub_screen.dart';
import 'package:taxi1/screens/admin/recorridos_admin_screen.dart';
import 'package:taxi1/screens/driver/turno_screen.dart';
import 'package:taxi1/screens/preferences_screen.dart';
import 'package:taxi1/screens/routes_screen.dart';
import 'package:taxi1/services/app_update_service.dart';
import 'package:taxi1/services/auth_service.dart';
import 'package:taxi1/theme/breakpoints.dart';
import 'package:taxi1/widgets/app_drawer.dart';
import 'package:taxi1/widgets/app_update_dialog.dart';

/// Controller ligero que permite cambiar de pestaña desde cualquier pantalla
/// (por ejemplo, desde [RoutesScreen] cuando se elige un paradero).
///
/// Se expone como singleton para no acoplar las pantallas con `BuildContext`
/// ni tener que pasar callbacks por todo el árbol de widgets.
class MainNavigationController extends ChangeNotifier {
  MainNavigationController._();
  static final MainNavigationController instance = MainNavigationController._();

  /// El menú lateral vive en el [Scaffold] de [MainScreen], pero las pantallas
  /// internas tienen `Scaffold` propio: un `Scaffold.of(context)` desde
  /// [MapScreen] encuentra el interno, que no tiene drawer. Con la key se
  /// alcanza el correcto desde cualquier punto del árbol.
  final scaffoldKey = GlobalKey<ScaffoldState>();

  AppDestination _destination = AppDestination.mapa;
  AppDestination get destination => _destination;

  void go(AppDestination destination) {
    if (destination == _destination) return;
    _destination = destination;
    notifyListeners();
  }

  /// Devuelve la navegación a un lugar existente cuando cambia el rol.
  ///
  /// Sin esto, un administrador parado en "Flota" que cierra sesión se queda en
  /// una pestaña que el invitado no tiene.
  void reconcile(UserRole role) {
    if (Destinations.isTab(_destination, role)) return;
    _destination = AppDestination.mapa;
    notifyListeners();
  }

  void openDrawer() => scaffoldKey.currentState?.openDrawer();

  void closeDrawer() {
    final state = scaffoldKey.currentState;
    if (state != null && state.isDrawerOpen) state.closeDrawer();
  }

  /// Atajos semánticos: llevan al usuario a una pestaña concreta sin que quien
  /// llama tenga que conocer el orden de los destinos.
  void showMap() => go(AppDestination.mapa);
  void showRoutes() => go(AppDestination.rutas);

  /// Preferencias es pestaña para el invitado, pero no para el chofer ni el
  /// administrador: sus tres pestañas están ocupadas por lo que usan a diario.
  /// Este método resuelve las dos formas de llegar, así los llamadores no
  /// tienen que saber cuál corresponde.
  void openPreferences(BuildContext context) {
    final role = AuthService.instance.role;
    if (Destinations.isTab(AppDestination.preferencias, role)) {
      go(AppDestination.preferencias);
    } else {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => const PreferencesScreen(showBackButton: true),
        ),
      );
    }
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  /// Ancho de la franja del borde izquierdo desde la que deslizar abre el menú.
  ///
  /// Con la navegación por gestos de Android, el borde mismo es del sistema
  /// (deslizar desde ahí es "atrás") y el valor por omisión del Scaffold, 20 dp,
  /// queda entero dentro de esa zona: nunca abriría. La franja se extiende
  /// [drawerSwipeStrip] más allá de lo que reserve el sistema o el notch. Es
  /// angosta a propósito: el mapa no se puede arrastrar desde ella.
  static double drawerSwipeWidth(BuildContext context) {
    // Sólo esos dos datos: con `MediaQuery.of` el menú se reconstruiría con
    // cada cuadro de la animación del teclado.
    final gestos = MediaQuery.systemGestureInsetsOf(context).left;
    final notch = MediaQuery.paddingOf(context).left;
    return (gestos > notch ? gestos : notch) + drawerSwipeStrip;
  }

  static const double drawerSwipeStrip = 24;

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  final _nav = MainNavigationController.instance;
  final _auth = AuthService.instance;

  /// Las pantallas se cachean por destino para que el `IndexedStack` conserve
  /// su estado (el mapa, sobre todo: recrearlo perdería la posición, el zoom y
  /// la suscripción al GPS).
  final _screens = <AppDestination, Widget>{};

  /// Al girar el teléfono las pestañas cambian de lugar en el árbol: en
  /// vertical son el `body` del Scaffold y en horizontal van dentro de un
  /// `Row`, al lado del riel de navegación. Sin esta llave Flutter las
  /// destruía y las volvía a crear, y el mapa con ellas: perdía la cámara y,
  /// peor, la app se cerraba. El motor de Flutter (3.44) libera la superficie
  /// del mapa al destruirlo, pero deja en cola el aviso del cambio de tamaño
  /// del giro, que después la lee (`NullPointerException` en
  /// `SurfaceProducerPlatformViewRenderTarget.getWidth`). Con la llave Flutter
  /// las traslada en vez de recrearlas.
  final _tabsKey = GlobalKey(debugLabel: 'pestañas');

  @override
  void initState() {
    super.initState();
    _nav.addListener(_onNavChanged);
    _auth.addListener(_onAuthChanged);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAppUpdate();
    });
  }

  Future<void> _checkAppUpdate() async {
    final updateService = AppUpdateService.instance;
    await updateService.checkForUpdates();
    if (mounted && updateService.shouldShowDialog) {
      await AppUpdateDialog.showIfAvailable(
        context,
        updateService.availableUpdate!,
      );
    }
  }

  // La app abre directamente en el mapa. Hubo aquí una pantalla de bienvenida
  // que presentaba los tres perfiles en el primer arranque; se quitó porque
  // interponía algo entre el usuario y lo único que la mayoría viene a ver. El
  // acceso a las cuentas vive en la cabecera del menú lateral, que es donde se
  // busca, y el invitado no necesita ninguna.

  @override
  void dispose() {
    _nav.removeListener(_onNavChanged);
    _auth.removeListener(_onAuthChanged);
    super.dispose();
  }

  void _onNavChanged() {
    if (mounted) setState(() {});
  }

  void _onAuthChanged() {
    // El rol cambió: la lista de pestañas es otra y el destino actual puede ya
    // no existir.
    _nav.reconcile(_auth.role);
    if (mounted) setState(() {});
  }

  Widget _screenFor(AppDestination destination) => _screens.putIfAbsent(
    destination,
    () => switch (destination) {
      AppDestination.mapa => const MapScreen(),
      AppDestination.rutas => const RoutesScreen(),
      AppDestination.preferencias => const PreferencesScreen(),
      AppDestination.turno => const TurnoScreen(),
      AppDestination.flota => const FlotaScreen(),
      AppDestination.garita => const GaritaHubScreen(),
      AppDestination.recorridos => const RecorridosAdminScreen(),
      AppDestination.choferes => const ChoferesAdminScreen(),
    },
  );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final role = _auth.role;
    final destinations = Destinations.barFor(role);
    final selectedIndex = Destinations.tabIndex(_nav.destination, role);

    // El estilo de las barras del sistema se define una sola vez, en
    // `appBarTheme`. Se reaplica acá con un AnnotatedRegion porque MapScreen no
    // tiene AppBar y, sin esto, la barra de estado quedaría con los colores del
    // tema anterior sobre la pantalla principal de la app.
    final overlayStyle =
        theme.appBarTheme.systemOverlayStyle ??
        (theme.brightness == Brightness.dark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark);

    final body = IndexedStack(
      key: _tabsKey,
      index: selectedIndex,
      children: [for (final d in destinations) _screenFor(d)],
    );

    void onSelected(int index) => _nav.go(destinations[index]);

    // RF-04-01: en pantallas anchas (tablet, y también teléfono en horizontal,
    // donde el alto es escaso) la navegación pasa al costado.
    final wide = !Breakpoints.isCompact(context);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlayStyle,
      child: Scaffold(
        key: _nav.scaffoldKey,
        drawer: const AppDrawer(),
        // Deslizar desde el borde izquierdo abre el menú, también sobre el
        // mapa: la franja gana el arrastre horizontal y el resto de la
        // pantalla sigue moviendo la cartografía.
        drawerEdgeDragWidth: MainScreen.drawerSwipeWidth(context),
        body: wide
            ? Row(
                children: [
                  SafeArea(
                    child: SingleChildScrollView(
                      child: IntrinsicHeight(
                        child: NavigationRail(
                          selectedIndex: selectedIndex,
                          onDestinationSelected: onSelected,
                          leading: Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: IconButton(
                              icon: const Icon(Icons.menu),
                              tooltip: l10n.openMenu,
                              onPressed: _nav.openDrawer,
                            ),
                          ),
                          destinations: [
                            for (final d in destinations)
                              NavigationRailDestination(
                                icon: Icon(d.icon),
                                selectedIcon: Icon(d.selectedIcon),
                                label: Text(d.label(l10n)),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  VerticalDivider(
                    width: 1,
                    color: theme.colorScheme.outlineVariant,
                  ),
                  Expanded(child: body),
                ],
              )
            : body,
        bottomNavigationBar: wide
            ? null
            : NavigationBar(
                selectedIndex: selectedIndex,
                onDestinationSelected: onSelected,
                // La altura por defecto (80) recorta las etiquetas cuando el
                // usuario sube el tamaño de fuente, así que crece con el
                // escalador de texto.
                height: _navBarHeight(context),
                destinations: [
                  for (final d in destinations)
                    NavigationDestination(
                      icon: Icon(d.icon),
                      selectedIcon: Icon(d.selectedIcon),
                      label: d.label(l10n),
                    ),
                ],
              ),
      ),
    );
  }

  double _navBarHeight(BuildContext context) {
    final scaled = MediaQuery.textScalerOf(context).scale(12);
    return (56 + scaled * 1.6).clamp(80.0, 124.0);
  }
}
