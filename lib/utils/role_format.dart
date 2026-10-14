import 'package:flutter/material.dart';

import 'package:taxi1/l10n/app_localizations.dart';
import 'package:taxi1/models/app_user.dart';

/// Presentación de [UserRole]: etiqueta, icono y color de la insignia.
///
/// Vive en `utils/` y no en el modelo por la misma razón que
/// `distance_format.dart`: el modelo se mantiene en Dart puro y serializable,
/// y todo lo que dependa de Flutter o de las traducciones queda acá.
String roleLabel(UserRole role, AppLocalizations l10n) => switch (role) {
  UserRole.invitado => l10n.roleGuest,
  UserRole.colectivero => l10n.roleColectivero,
  UserRole.administrador => l10n.roleAdmin,
};

/// Qué hace el usuario con su rol, o `null` si no hay nada que contar: para el
/// invitado, "Invitado" ya lo dice todo.
String? roleSubtitle(UserRole role, AppLocalizations l10n) => switch (role) {
  UserRole.invitado => null,
  UserRole.colectivero => l10n.roleColectiveroSubtitle,
  UserRole.administrador => l10n.roleAdminSubtitle,
};

/// Colores del avatar de la cuenta, en el menú lateral y en Preferencias.
///
/// Es el amarillo del letrero del colectivo en ambos temas y para todos los
/// roles (el rol lo dice la insignia): de día es `primaryContainer`; de noche
/// ese contenedor es oliva oscuro y el amarillo es `primary`.
({Color background, Color foreground}) accountAvatarColors(
  ColorScheme scheme,
) => scheme.brightness == Brightness.light
    ? (
        background: scheme.primaryContainer,
        foreground: scheme.onPrimaryContainer,
      )
    : (background: scheme.primary, foreground: scheme.onPrimary);

IconData roleIcon(UserRole role) => switch (role) {
  UserRole.invitado => Icons.person_outline,
  UserRole.colectivero => Icons.local_taxi,
  UserRole.administrador => Icons.apartment,
};

/// Fondo y color de texto de la insignia de rol.
///
/// Se toman roles del [ColorScheme] en vez de inventar colores nuevos: azul,
/// verde, ámbar y rojo están reservados (ver `theme/app_colors.dart`) para la
/// ubicación del usuario y la semaforización de capacidad, y un cuarto color de
/// marca competiría con ellos sobre el mapa.
({Color background, Color foreground}) roleBadgeColors(
  UserRole role,
  ColorScheme scheme,
) => switch (role) {
  UserRole.invitado => (
    background: scheme.surfaceContainerHighest,
    foreground: scheme.onSurfaceVariant,
  ),
  UserRole.colectivero => (
    background: scheme.secondaryContainer,
    foreground: scheme.onSecondaryContainer,
  ),
  UserRole.administrador => (
    background: scheme.tertiaryContainer,
    foreground: scheme.onTertiaryContainer,
  ),
};
