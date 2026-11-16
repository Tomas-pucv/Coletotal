import 'package:taxi1/l10n/app_localizations.dart';

/// Traduce el código de error de [RouteService.lastError].
///
/// El servicio mezclaba códigos (`provider_error`, `no_route`) con frases en
/// español ya escritas. `map_screen` traducía solo los códigos y `routes_screen`
/// imprimía el valor crudo, así que el usuario podía llegar a leer literalmente
/// "provider_error" en un SnackBar. Ahora el servicio emite siempre códigos y
/// esta función es el único punto donde se convierten en texto.
String routeErrorMessage(String? code, AppLocalizations l10n) {
  return switch (code) {
    'invalid_coords' => l10n.errInvalidCoords,
    'provider_error' => l10n.errProvider,
    'no_route' => l10n.errNoRoute,
    'generic_error' => l10n.errGeneric,
    _ => l10n.routeErrorDefault,
  };
}
