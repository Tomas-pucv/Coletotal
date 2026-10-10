import 'package:flutter/material.dart';

import 'package:taxi1/l10n/app_localizations.dart';
import 'package:taxi1/models/app_user.dart';

/// Cada lugar al que se puede navegar dentro del contenedor principal.
///
/// Sustituye a los índices enteros que usaba `MainNavigationController`. Con
/// tres roles y tres listas de destinos distintas, un `int` deja de significar
/// lo mismo según quién haya iniciado sesión: `setIndex(2)` era "Preferencias"
/// para el invitado y otra cosa para el administrador. Un enum no se puede
/// desalinear.
enum AppDestination {
  mapa,
  rutas,
  preferencias,

  // Colectivero
  turno,

  // Administrador de garita
  flota,
  garita,
  recorridos,
  choferes;

  IconData get icon => switch (this) {
    AppDestination.mapa => Icons.map_outlined,
    AppDestination.rutas => Icons.alt_route_outlined,
    AppDestination.preferencias => Icons.settings_outlined,
    AppDestination.turno => Icons.local_taxi_outlined,
    AppDestination.flota => Icons.travel_explore_outlined,
    AppDestination.garita => Icons.apartment_outlined,
    AppDestination.recorridos => Icons.timeline_outlined,
    AppDestination.choferes => Icons.badge_outlined,
  };

  IconData get selectedIcon => switch (this) {
    AppDestination.mapa => Icons.map,
    AppDestination.rutas => Icons.alt_route,
    AppDestination.preferencias => Icons.settings,
    AppDestination.turno => Icons.local_taxi,
    AppDestination.flota => Icons.travel_explore,
    AppDestination.garita => Icons.apartment,
    AppDestination.recorridos => Icons.timeline,
    AppDestination.choferes => Icons.badge,
  };

  String label(AppLocalizations l10n) => switch (this) {
    AppDestination.mapa => l10n.navMap,
    AppDestination.rutas => l10n.navRoutes,
    AppDestination.preferencias => l10n.navPreferences,
    AppDestination.turno => l10n.navTurno,
    AppDestination.flota => l10n.navFlota,
    AppDestination.garita => l10n.navGarita,
    AppDestination.recorridos => l10n.navRecorridos,
    AppDestination.choferes => l10n.navDrivers,
  };
}

/// Qué destinos ve cada rol.
///
/// Se declara acá y no en la pantalla para poder testear el mapeo sin montar
/// widgets ni inicializar Firebase.
abstract final class Destinations {
  /// Pestañas de la barra inferior (o del rail en pantallas anchas).
  ///
  /// **Siempre tres**, a propósito. Material 3 desaconseja más, con la fuente
  /// al 140% una cuarta etiqueta ya no entra, y —lo importante— al ser el
  /// `IndexedStack` exactamente esta lista, el índice seleccionado nunca puede
  /// quedar fuera de rango al cambiar de rol.
  ///
  /// El invitado conserva exactamente la navegación que la app tenía antes de
  /// existir los roles: quien ya la usa no nota ningún cambio.
  static List<AppDestination> barFor(UserRole role) => switch (role) {
    UserRole.invitado => const [
      AppDestination.mapa,
      AppDestination.rutas,
      AppDestination.preferencias,
    ],
    UserRole.colectivero => const [
      AppDestination.mapa,
      AppDestination.rutas,
      AppDestination.turno,
    ],
    UserRole.administrador => const [
      AppDestination.mapa,
      AppDestination.flota,
      AppDestination.garita,
    ],
  };

  /// Destinos que sólo viven en el menú lateral y se abren **apilados**
  /// (`Navigator.push`), no como pestaña.
  ///
  /// Son pantallas de detalle a las que se entra y de las que se vuelve, no
  /// lugares donde uno se queda: el administrador edita recorridos y regresa a
  /// supervisar la flota.
  static List<AppDestination> extrasFor(UserRole role) => switch (role) {
    UserRole.invitado => const [],
    UserRole.colectivero => const [AppDestination.preferencias],
    UserRole.administrador => const [
      AppDestination.recorridos,
      AppDestination.choferes,
      AppDestination.preferencias,
    ],
  };

  /// Los extras propios del rol, agrupados bajo su encabezado en el menú.
  /// Preferencias queda fuera: va en el pie, junto al cierre de sesión.
  static List<AppDestination> roleSectionFor(UserRole role) => extrasFor(
    role,
  ).where((d) => d != AppDestination.preferencias).toList(growable: false);

  /// Si [destination] es una de las pestañas de [role].
  static bool isTab(AppDestination destination, UserRole role) =>
      barFor(role).contains(destination);

  /// Índice de [destination] dentro de la barra de [role]. Devuelve 0 cuando no
  /// es una pestaña, que sólo puede pasar transitoriamente al cambiar de rol
  /// (ver `MainNavigationController.reconcile`).
  static int tabIndex(AppDestination destination, UserRole role) {
    final index = barFor(role).indexOf(destination);
    return index < 0 ? 0 : index;
  }
}
