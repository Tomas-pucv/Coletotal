import 'package:taxi1/l10n/app_localizations.dart';
import 'package:taxi1/services/auth_service.dart';

/// Traduce un [AuthErrorCode] al mensaje que ve el usuario.
///
/// Mismo patrón que `route_error.dart`: el servicio devuelve códigos y la capa
/// de presentación decide las palabras, para que los servicios no dependan de
/// las traducciones.
///
/// [isDriver] sólo cambia si el mensaje habla de "patente" o de "correo": es la
/// única diferencia perceptible entre los dos formularios de acceso.
String authErrorMessage(
  AuthErrorCode code,
  AppLocalizations l10n, {
  required bool isDriver,
}) => switch (code) {
  AuthErrorCode.credencialesInvalidas =>
    isDriver ? l10n.errAuthCredentials : l10n.errAuthCredentialsEmail,
  AuthErrorCode.cuentaEnUso => l10n.errAuthAccountInUse,
  AuthErrorCode.claveDebil => l10n.errAuthWeakPassword,
  AuthErrorCode.patenteInvalida => l10n.errAuthPatenteInvalid,
  AuthErrorCode.codigoInvalido => l10n.errAuthCodigoInvalid,
  AuthErrorCode.cuentaDeshabilitada => l10n.errAuthDisabled,
  AuthErrorCode.sinConexion => l10n.errAuthNetwork,
  AuthErrorCode.desconocido => l10n.errAuthUnknown,
};
