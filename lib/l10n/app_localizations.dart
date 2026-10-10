import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_es.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[Locale('es')];

  /// No description provided for @navMap.
  ///
  /// In es, this message translates to:
  /// **'Mapa'**
  String get navMap;

  /// No description provided for @navRoutes.
  ///
  /// In es, this message translates to:
  /// **'Recorridos'**
  String get navRoutes;

  /// No description provided for @navPreferences.
  ///
  /// In es, this message translates to:
  /// **'Preferencias'**
  String get navPreferences;

  /// No description provided for @calculatingRoute.
  ///
  /// In es, this message translates to:
  /// **'Calculando ruta…'**
  String get calculatingRoute;

  /// No description provided for @searchingLocation.
  ///
  /// In es, this message translates to:
  /// **'Buscando ubicación…'**
  String get searchingLocation;

  /// No description provided for @closeRoute.
  ///
  /// In es, this message translates to:
  /// **'Cerrar ruta'**
  String get closeRoute;

  /// No description provided for @tapToGoStop.
  ///
  /// In es, this message translates to:
  /// **'Tocar para ver recorrido'**
  String get tapToGoStop;

  /// No description provided for @coordsLabel.
  ///
  /// In es, this message translates to:
  /// **'Lat: {lat}, Lng: {lng}'**
  String coordsLabel(String lat, String lng);

  /// No description provided for @routeErrorDefault.
  ///
  /// In es, this message translates to:
  /// **'No se pudo obtener la ruta. Inténtalo de nuevo.'**
  String get routeErrorDefault;

  /// No description provided for @reorientMap.
  ///
  /// In es, this message translates to:
  /// **'Orientar al norte'**
  String get reorientMap;

  /// No description provided for @recenterActive.
  ///
  /// In es, this message translates to:
  /// **'Seguimiento activo'**
  String get recenterActive;

  /// No description provided for @recenterInactive.
  ///
  /// In es, this message translates to:
  /// **'Centrar en mi ubicación'**
  String get recenterInactive;

  /// No description provided for @stopSemanticLabel.
  ///
  /// In es, this message translates to:
  /// **'Recorrido {name}, {address}'**
  String stopSemanticLabel(String name, String address);

  /// No description provided for @telemetryUnavailable.
  ///
  /// In es, this message translates to:
  /// **'No se pudo cargar la posición de los colectivos.'**
  String get telemetryUnavailable;

  /// No description provided for @mapLayers.
  ///
  /// In es, this message translates to:
  /// **'Capas del mapa'**
  String get mapLayers;

  /// No description provided for @moreSettings.
  ///
  /// In es, this message translates to:
  /// **'Más ajustes'**
  String get moreSettings;

  /// No description provided for @calculateRouteTitle.
  ///
  /// In es, this message translates to:
  /// **'Recorridos'**
  String get calculateRouteTitle;

  /// No description provided for @originLabel.
  ///
  /// In es, this message translates to:
  /// **'Origen (Mi ubicación actual)'**
  String get originLabel;

  /// No description provided for @searchStopHint.
  ///
  /// In es, this message translates to:
  /// **'Buscar por calle, sector o punto de interés…'**
  String get searchStopHint;

  /// No description provided for @whereToGo.
  ///
  /// In es, this message translates to:
  /// **'Recorridos disponibles'**
  String get whereToGo;

  /// No description provided for @noResults.
  ///
  /// In es, this message translates to:
  /// **'Sin recorridos para \"{query}\"'**
  String noResults(String query);

  /// No description provided for @noResultsHint.
  ///
  /// In es, this message translates to:
  /// **'Prueba con otra calle, avenida o sector de Quilpué.'**
  String get noResultsHint;

  /// No description provided for @goToNearestStop.
  ///
  /// In es, this message translates to:
  /// **'Línea más cercana'**
  String get goToNearestStop;

  /// No description provided for @locationUnavailable.
  ///
  /// In es, this message translates to:
  /// **'Tu ubicación aún no está disponible. Activa el GPS o espera unos segundos.'**
  String get locationUnavailable;

  /// No description provided for @veryClose.
  ///
  /// In es, this message translates to:
  /// **'Muy cerca'**
  String get veryClose;

  /// No description provided for @closeDistance.
  ///
  /// In es, this message translates to:
  /// **'Cerca'**
  String get closeDistance;

  /// No description provided for @mediumDistance.
  ///
  /// In es, this message translates to:
  /// **'A media distancia'**
  String get mediumDistance;

  /// No description provided for @far.
  ///
  /// In es, this message translates to:
  /// **'Lejos'**
  String get far;

  /// No description provided for @distanceUnavailable.
  ///
  /// In es, this message translates to:
  /// **'Distancia no disponible'**
  String get distanceUnavailable;

  /// No description provided for @enableLocationForSorting.
  ///
  /// In es, this message translates to:
  /// **'Activa la ubicación para ordenar las líneas por cercanía.'**
  String get enableLocationForSorting;

  /// No description provided for @recentStops.
  ///
  /// In es, this message translates to:
  /// **'Consultadas recientemente'**
  String get recentStops;

  /// No description provided for @allStops.
  ///
  /// In es, this message translates to:
  /// **'Todas las líneas'**
  String get allStops;

  /// No description provided for @locationOffMessage.
  ///
  /// In es, this message translates to:
  /// **'Activa el GPS del teléfono para ver tu posición y los recorridos cercanos.'**
  String get locationOffMessage;

  /// No description provided for @locationDeniedMessage.
  ///
  /// In es, this message translates to:
  /// **'ColeTotal necesita acceso a tu ubicación para calcular las líneas más cercanas.'**
  String get locationDeniedMessage;

  /// No description provided for @locationDisabledByPreference.
  ///
  /// In es, this message translates to:
  /// **'Tienes el rastreo de ubicación desactivado en Preferencias.'**
  String get locationDisabledByPreference;

  /// No description provided for @openSettings.
  ///
  /// In es, this message translates to:
  /// **'Abrir ajustes'**
  String get openSettings;

  /// No description provided for @retry.
  ///
  /// In es, this message translates to:
  /// **'Reintentar'**
  String get retry;

  /// No description provided for @preferencesTitle.
  ///
  /// In es, this message translates to:
  /// **'Preferencias'**
  String get preferencesTitle;

  /// No description provided for @mapNormal.
  ///
  /// In es, this message translates to:
  /// **'Calles'**
  String get mapNormal;

  /// No description provided for @mapNormalDesc.
  ///
  /// In es, this message translates to:
  /// **'Mapa estándar'**
  String get mapNormalDesc;

  /// No description provided for @satellite.
  ///
  /// In es, this message translates to:
  /// **'Satélite'**
  String get satellite;

  /// No description provided for @satelliteDesc.
  ///
  /// In es, this message translates to:
  /// **'Foto aérea · requiere conexión'**
  String get satelliteDesc;

  /// No description provided for @sectionAppearance.
  ///
  /// In es, this message translates to:
  /// **'Apariencia'**
  String get sectionAppearance;

  /// No description provided for @themeLabel.
  ///
  /// In es, this message translates to:
  /// **'Tema'**
  String get themeLabel;

  /// No description provided for @themeSystemShort.
  ///
  /// In es, this message translates to:
  /// **'Auto'**
  String get themeSystemShort;

  /// No description provided for @themeLightShort.
  ///
  /// In es, this message translates to:
  /// **'Claro'**
  String get themeLightShort;

  /// No description provided for @themeDarkShort.
  ///
  /// In es, this message translates to:
  /// **'Oscuro'**
  String get themeDarkShort;

  /// No description provided for @themeSystem.
  ///
  /// In es, this message translates to:
  /// **'Automático (según el sistema)'**
  String get themeSystem;

  /// No description provided for @themeLight.
  ///
  /// In es, this message translates to:
  /// **'Tema claro'**
  String get themeLight;

  /// No description provided for @themeDark.
  ///
  /// In es, this message translates to:
  /// **'Tema oscuro'**
  String get themeDark;

  /// No description provided for @fontSize.
  ///
  /// In es, this message translates to:
  /// **'Tamaño de fuente'**
  String get fontSize;

  /// No description provided for @fontSizePreviewHint.
  ///
  /// In es, this message translates to:
  /// **'Así se verán los paraderos'**
  String get fontSizePreviewHint;

  /// No description provided for @compactMode.
  ///
  /// In es, this message translates to:
  /// **'Modo compacto'**
  String get compactMode;

  /// No description provided for @compactModeDesc.
  ///
  /// In es, this message translates to:
  /// **'Filas más juntas, cabe más en pantalla'**
  String get compactModeDesc;

  /// No description provided for @animations.
  ///
  /// In es, this message translates to:
  /// **'Animaciones'**
  String get animations;

  /// No description provided for @animationsDesc.
  ///
  /// In es, this message translates to:
  /// **'Transiciones y pulso de los paraderos'**
  String get animationsDesc;

  /// No description provided for @sectionPrivacy.
  ///
  /// In es, this message translates to:
  /// **'Privacidad'**
  String get sectionPrivacy;

  /// No description provided for @locationTracking.
  ///
  /// In es, this message translates to:
  /// **'Rastreo de ubicación'**
  String get locationTracking;

  /// No description provided for @locationTrackingDesc.
  ///
  /// In es, this message translates to:
  /// **'Necesario para centrar el mapa y calcular rutas'**
  String get locationTrackingDesc;

  /// No description provided for @disableTrackingTitle.
  ///
  /// In es, this message translates to:
  /// **'Deshabilitar rastreo'**
  String get disableTrackingTitle;

  /// No description provided for @disableTrackingMessage.
  ///
  /// In es, this message translates to:
  /// **'¿Estás seguro? El mapa necesita tu ubicación para funcionar correctamente.'**
  String get disableTrackingMessage;

  /// No description provided for @saveHistory.
  ///
  /// In es, this message translates to:
  /// **'Guardar historial'**
  String get saveHistory;

  /// No description provided for @saveHistoryDesc.
  ///
  /// In es, this message translates to:
  /// **'Recuerda los últimos {count} paraderos consultados'**
  String saveHistoryDesc(String count);

  /// No description provided for @clearHistory.
  ///
  /// In es, this message translates to:
  /// **'Borrar'**
  String get clearHistory;

  /// No description provided for @historyCleared.
  ///
  /// In es, this message translates to:
  /// **'Historial borrado.'**
  String get historyCleared;

  /// No description provided for @cancel.
  ///
  /// In es, this message translates to:
  /// **'Cancelar'**
  String get cancel;

  /// No description provided for @confirm.
  ///
  /// In es, this message translates to:
  /// **'Confirmar'**
  String get confirm;

  /// No description provided for @sectionAbout.
  ///
  /// In es, this message translates to:
  /// **'Acerca de'**
  String get sectionAbout;

  /// No description provided for @aboutVersion.
  ///
  /// In es, this message translates to:
  /// **'ColeTotal versión {version}'**
  String aboutVersion(String version);

  /// No description provided for @aboutSubtitle.
  ///
  /// In es, this message translates to:
  /// **'Rutas y paraderos de Transportes Serrano, Quilpué.'**
  String get aboutSubtitle;

  /// No description provided for @updateCheck.
  ///
  /// In es, this message translates to:
  /// **'Buscar actualizaciones'**
  String get updateCheck;

  /// No description provided for @updateUpToDate.
  ///
  /// In es, this message translates to:
  /// **'Tienes la versión más reciente ({version})'**
  String updateUpToDate(String version);

  /// No description provided for @updateTitle.
  ///
  /// In es, this message translates to:
  /// **'¡Nueva versión disponible!'**
  String get updateTitle;

  /// No description provided for @updateVersions.
  ///
  /// In es, this message translates to:
  /// **'Versión {nueva} (instalada: {instalada})'**
  String updateVersions(String nueva, String instalada);

  /// No description provided for @updateChangelogTitle.
  ///
  /// In es, this message translates to:
  /// **'Novedades y mejoras:'**
  String get updateChangelogTitle;

  /// No description provided for @updateDefaultChangelog.
  ///
  /// In es, this message translates to:
  /// **'Nueva versión con mejoras operacionales.'**
  String get updateDefaultChangelog;

  /// No description provided for @updateMandatory.
  ///
  /// In es, this message translates to:
  /// **'Esta actualización es obligatoria para continuar operando en la garita.'**
  String get updateMandatory;

  /// No description provided for @updateLater.
  ///
  /// In es, this message translates to:
  /// **'Recordar más tarde'**
  String get updateLater;

  /// No description provided for @updateNow.
  ///
  /// In es, this message translates to:
  /// **'Actualizar ahora'**
  String get updateNow;

  /// No description provided for @updateOpenFailed.
  ///
  /// In es, this message translates to:
  /// **'No se pudo abrir el enlace de descarga del APK.'**
  String get updateOpenFailed;

  /// No description provided for @errInvalidCoords.
  ///
  /// In es, this message translates to:
  /// **'Origen o destino inválido (coordenadas fuera de rango).'**
  String get errInvalidCoords;

  /// No description provided for @errNoRoute.
  ///
  /// In es, this message translates to:
  /// **'No se pudo obtener la ruta. Verifica tu conexión.'**
  String get errNoRoute;

  /// No description provided for @errProvider.
  ///
  /// In es, this message translates to:
  /// **'El servicio de rutas no respondió correctamente.'**
  String get errProvider;

  /// No description provided for @errGeneric.
  ///
  /// In es, this message translates to:
  /// **'Ocurrió un error al calcular la ruta.'**
  String get errGeneric;

  /// No description provided for @distanceKm.
  ///
  /// In es, this message translates to:
  /// **'{value} km'**
  String distanceKm(String value);

  /// No description provided for @distanceM.
  ///
  /// In es, this message translates to:
  /// **'{value} m'**
  String distanceM(String value);

  /// No description provided for @durationMin.
  ///
  /// In es, this message translates to:
  /// **'{minutes} min'**
  String durationMin(String minutes);

  /// No description provided for @durationHour.
  ///
  /// In es, this message translates to:
  /// **'{h} h'**
  String durationHour(String h);

  /// No description provided for @durationHourMin.
  ///
  /// In es, this message translates to:
  /// **'{h} h {m} min'**
  String durationHourMin(String h, String m);

  /// No description provided for @navTurno.
  ///
  /// In es, this message translates to:
  /// **'Turno'**
  String get navTurno;

  /// No description provided for @navFlota.
  ///
  /// In es, this message translates to:
  /// **'Flota'**
  String get navFlota;

  /// No description provided for @navGarita.
  ///
  /// In es, this message translates to:
  /// **'Garita'**
  String get navGarita;

  /// No description provided for @navStops.
  ///
  /// In es, this message translates to:
  /// **'Gestión de paraderos'**
  String get navStops;

  /// No description provided for @navRecorridos.
  ///
  /// In es, this message translates to:
  /// **'Recorridos'**
  String get navRecorridos;

  /// No description provided for @navDrivers.
  ///
  /// In es, this message translates to:
  /// **'Choferes'**
  String get navDrivers;

  /// No description provided for @roleGuest.
  ///
  /// In es, this message translates to:
  /// **'Invitado'**
  String get roleGuest;

  /// No description provided for @roleColectivero.
  ///
  /// In es, this message translates to:
  /// **'Colectivero'**
  String get roleColectivero;

  /// No description provided for @roleAdmin.
  ///
  /// In es, this message translates to:
  /// **'Administrador'**
  String get roleAdmin;

  /// No description provided for @roleGuestSubtitle.
  ///
  /// In es, this message translates to:
  /// **'Estás usando ColeTotal sin cuenta'**
  String get roleGuestSubtitle;

  /// No description provided for @roleColectiveroSubtitle.
  ///
  /// In es, this message translates to:
  /// **'Transmites tu posición a la garita'**
  String get roleColectiveroSubtitle;

  /// No description provided for @roleAdminSubtitle.
  ///
  /// In es, this message translates to:
  /// **'Gestionas los datos de la garita'**
  String get roleAdminSubtitle;

  /// No description provided for @openMenu.
  ///
  /// In es, this message translates to:
  /// **'Abrir menú'**
  String get openMenu;

  /// No description provided for @drawerDriverSection.
  ///
  /// In es, this message translates to:
  /// **'Mi jornada'**
  String get drawerDriverSection;

  /// No description provided for @drawerAdminSection.
  ///
  /// In es, this message translates to:
  /// **'Garita'**
  String get drawerAdminSection;

  /// No description provided for @signIn.
  ///
  /// In es, this message translates to:
  /// **'Iniciar sesión'**
  String get signIn;

  /// No description provided for @createAccount.
  ///
  /// In es, this message translates to:
  /// **'Crear cuenta'**
  String get createAccount;

  /// No description provided for @signOut.
  ///
  /// In es, this message translates to:
  /// **'Cerrar sesión'**
  String get signOut;

  /// No description provided for @signOutMessage.
  ///
  /// In es, this message translates to:
  /// **'Volverás al modo invitado y dejarás de transmitir tu ubicación.'**
  String get signOutMessage;

  /// No description provided for @authLoginTitle.
  ///
  /// In es, this message translates to:
  /// **'Iniciar sesión'**
  String get authLoginTitle;

  /// No description provided for @authRegisterTitle.
  ///
  /// In es, this message translates to:
  /// **'Crear cuenta'**
  String get authRegisterTitle;

  /// No description provided for @authRoleQuestion.
  ///
  /// In es, this message translates to:
  /// **'¿Cómo vas a entrar?'**
  String get authRoleQuestion;

  /// No description provided for @authPatente.
  ///
  /// In es, this message translates to:
  /// **'Patente'**
  String get authPatente;

  /// No description provided for @authPatenteHint.
  ///
  /// In es, this message translates to:
  /// **'BBBB12'**
  String get authPatenteHint;

  /// No description provided for @authEmail.
  ///
  /// In es, this message translates to:
  /// **'Correo electrónico'**
  String get authEmail;

  /// No description provided for @authPassword.
  ///
  /// In es, this message translates to:
  /// **'Contraseña'**
  String get authPassword;

  /// No description provided for @authPasswordConfirm.
  ///
  /// In es, this message translates to:
  /// **'Repite la contraseña'**
  String get authPasswordConfirm;

  /// No description provided for @authName.
  ///
  /// In es, this message translates to:
  /// **'Nombre'**
  String get authName;

  /// No description provided for @authNameHint.
  ///
  /// In es, this message translates to:
  /// **'Como quieres que te vean en la garita'**
  String get authNameHint;

  /// No description provided for @authCodigo.
  ///
  /// In es, this message translates to:
  /// **'Código de garita'**
  String get authCodigo;

  /// No description provided for @authCodigoHelp.
  ///
  /// In es, this message translates to:
  /// **'Te lo entrega el administrador de tu garita.'**
  String get authCodigoHelp;

  /// No description provided for @authCodigoChecking.
  ///
  /// In es, this message translates to:
  /// **'Comprobando código…'**
  String get authCodigoChecking;

  /// No description provided for @authCodigoValid.
  ///
  /// In es, this message translates to:
  /// **'Código válido para {garita}'**
  String authCodigoValid(String garita);

  /// No description provided for @authCodigoInvalid.
  ///
  /// In es, this message translates to:
  /// **'Ese código no existe, no está habilitado o no corresponde a este rol.'**
  String get authCodigoInvalid;

  /// No description provided for @authSubmitLogin.
  ///
  /// In es, this message translates to:
  /// **'Entrar'**
  String get authSubmitLogin;

  /// No description provided for @authSubmitRegister.
  ///
  /// In es, this message translates to:
  /// **'Crear cuenta'**
  String get authSubmitRegister;

  /// No description provided for @authNoAccount.
  ///
  /// In es, this message translates to:
  /// **'¿No tienes cuenta? Regístrate'**
  String get authNoAccount;

  /// No description provided for @authHasAccount.
  ///
  /// In es, this message translates to:
  /// **'¿Ya tienes cuenta? Inicia sesión'**
  String get authHasAccount;

  /// No description provided for @authRequired.
  ///
  /// In es, this message translates to:
  /// **'Completa este campo'**
  String get authRequired;

  /// No description provided for @authPatenteInvalid.
  ///
  /// In es, this message translates to:
  /// **'Patente inválida. Debe ser como BBBB12 o AB1234.'**
  String get authPatenteInvalid;

  /// No description provided for @authEmailInvalid.
  ///
  /// In es, this message translates to:
  /// **'Escribe un correo válido.'**
  String get authEmailInvalid;

  /// No description provided for @authPasswordShort.
  ///
  /// In es, this message translates to:
  /// **'Mínimo 6 caracteres.'**
  String get authPasswordShort;

  /// No description provided for @authPasswordMismatch.
  ///
  /// In es, this message translates to:
  /// **'Las contraseñas no coinciden.'**
  String get authPasswordMismatch;

  /// No description provided for @authPasswordNote.
  ///
  /// In es, this message translates to:
  /// **'Guarda bien tu contraseña: la patente no es un correo real, así que no se puede recuperar por email. Si la pierdes, tendrás que pedírselo a tu garita.'**
  String get authPasswordNote;

  /// No description provided for @authShowPassword.
  ///
  /// In es, this message translates to:
  /// **'Mostrar contraseña'**
  String get authShowPassword;

  /// No description provided for @authHidePassword.
  ///
  /// In es, this message translates to:
  /// **'Ocultar contraseña'**
  String get authHidePassword;

  /// No description provided for @authWelcome.
  ///
  /// In es, this message translates to:
  /// **'Hola, {nombre}'**
  String authWelcome(String nombre);

  /// No description provided for @authGuestHint.
  ///
  /// In es, this message translates to:
  /// **'El invitado no necesita cuenta: cierra esta pantalla y sigue usando el mapa.'**
  String get authGuestHint;

  /// No description provided for @errAuthCredentials.
  ///
  /// In es, this message translates to:
  /// **'Patente o contraseña incorrecta.'**
  String get errAuthCredentials;

  /// No description provided for @errAuthCredentialsEmail.
  ///
  /// In es, this message translates to:
  /// **'Correo o contraseña incorrecta.'**
  String get errAuthCredentialsEmail;

  /// No description provided for @errAuthAccountInUse.
  ///
  /// In es, this message translates to:
  /// **'Ya existe una cuenta registrada con esos datos.'**
  String get errAuthAccountInUse;

  /// No description provided for @errAuthWeakPassword.
  ///
  /// In es, this message translates to:
  /// **'La contraseña es muy débil: usa al menos 6 caracteres.'**
  String get errAuthWeakPassword;

  /// No description provided for @errAuthPatenteInvalid.
  ///
  /// In es, this message translates to:
  /// **'Patente inválida.'**
  String get errAuthPatenteInvalid;

  /// No description provided for @errAuthCodigoInvalid.
  ///
  /// In es, this message translates to:
  /// **'Código de garita inválido para ese rol.'**
  String get errAuthCodigoInvalid;

  /// No description provided for @errAuthDisabled.
  ///
  /// In es, this message translates to:
  /// **'Tu cuenta está deshabilitada. Habla con tu garita.'**
  String get errAuthDisabled;

  /// No description provided for @errAuthNetwork.
  ///
  /// In es, this message translates to:
  /// **'Sin conexión. Revisa tu red e inténtalo de nuevo.'**
  String get errAuthNetwork;

  /// No description provided for @errAuthUnknown.
  ///
  /// In es, this message translates to:
  /// **'No se pudo completar la operación. Inténtalo de nuevo.'**
  String get errAuthUnknown;

  /// No description provided for @sectionAccount.
  ///
  /// In es, this message translates to:
  /// **'Cuenta'**
  String get sectionAccount;

  /// No description provided for @turnoTitle.
  ///
  /// In es, this message translates to:
  /// **'Turno'**
  String get turnoTitle;

  /// No description provided for @turnoOn.
  ///
  /// In es, this message translates to:
  /// **'En servicio'**
  String get turnoOn;

  /// No description provided for @turnoOff.
  ///
  /// In es, this message translates to:
  /// **'Fuera de servicio'**
  String get turnoOff;

  /// No description provided for @turnoOnDesc.
  ///
  /// In es, this message translates to:
  /// **'Los pasajeros ven tu posición en el mapa.'**
  String get turnoOnDesc;

  /// No description provided for @turnoOffDesc.
  ///
  /// In es, this message translates to:
  /// **'No se transmite nada. Nadie ve dónde estás.'**
  String get turnoOffDesc;

  /// No description provided for @turnoStart.
  ///
  /// In es, this message translates to:
  /// **'Iniciar turno'**
  String get turnoStart;

  /// No description provided for @turnoEnd.
  ///
  /// In es, this message translates to:
  /// **'Terminar turno'**
  String get turnoEnd;

  /// No description provided for @turnoCapacity.
  ///
  /// In es, this message translates to:
  /// **'Capacidad'**
  String get turnoCapacity;

  /// No description provided for @turnoCapacityHelp.
  ///
  /// In es, this message translates to:
  /// **'Cambia el color de tu marcador para los pasajeros y la garita.'**
  String get turnoCapacityHelp;

  /// No description provided for @capacityAvailable.
  ///
  /// In es, this message translates to:
  /// **'Disponible'**
  String get capacityAvailable;

  /// No description provided for @capacityHalf.
  ///
  /// In es, this message translates to:
  /// **'Medio lleno'**
  String get capacityHalf;

  /// No description provided for @capacityFull.
  ///
  /// In es, this message translates to:
  /// **'Lleno'**
  String get capacityFull;

  /// No description provided for @capacityAvailableLong.
  ///
  /// In es, this message translates to:
  /// **'Disponible (con asientos)'**
  String get capacityAvailableLong;

  /// No description provided for @capacityHalfLong.
  ///
  /// In es, this message translates to:
  /// **'Medio lleno (pocos cupos)'**
  String get capacityHalfLong;

  /// No description provided for @capacityFullLong.
  ///
  /// In es, this message translates to:
  /// **'Lleno (sin cupos)'**
  String get capacityFullLong;

  /// No description provided for @colectivoTitle.
  ///
  /// In es, this message translates to:
  /// **'Colectivo {patente}'**
  String colectivoTitle(String patente);

  /// No description provided for @colectivoNoRoute.
  ///
  /// In es, this message translates to:
  /// **'Sin recorrido informado'**
  String get colectivoNoRoute;

  /// No description provided for @colectivoLastSignal.
  ///
  /// In es, this message translates to:
  /// **'Última señal hace {tiempo}'**
  String colectivoLastSignal(String tiempo);

  /// No description provided for @colectivoNoSignal.
  ///
  /// In es, this message translates to:
  /// **'Sin señal'**
  String get colectivoNoSignal;

  /// No description provided for @colectivoSemanticLabel.
  ///
  /// In es, this message translates to:
  /// **'Colectivo {patente}, {estado}'**
  String colectivoSemanticLabel(String patente, String estado);

  /// No description provided for @turnoVehicle.
  ///
  /// In es, this message translates to:
  /// **'Mi vehículo'**
  String get turnoVehicle;

  /// No description provided for @turnoLastSent.
  ///
  /// In es, this message translates to:
  /// **'Última posición enviada hace {tiempo}'**
  String turnoLastSent(String tiempo);

  /// No description provided for @turnoNoSignal.
  ///
  /// In es, this message translates to:
  /// **'Aún no se ha enviado ninguna posición.'**
  String get turnoNoSignal;

  /// No description provided for @turnoIssueTracking.
  ///
  /// In es, this message translates to:
  /// **'Tienes el rastreo de ubicación desactivado en Preferencias. Actívalo para poder iniciar tu turno.'**
  String get turnoIssueTracking;

  /// No description provided for @turnoIssueInactive.
  ///
  /// In es, this message translates to:
  /// **'Tu cuenta está deshabilitada por la garita. Habla con el administrador.'**
  String get turnoIssueInactive;

  /// No description provided for @turnoIssueLocation.
  ///
  /// In es, this message translates to:
  /// **'No se pudo acceder al GPS. Revisa que esté encendido y que la app tenga permiso.'**
  String get turnoIssueLocation;

  /// No description provided for @turnoConsent.
  ///
  /// In es, this message translates to:
  /// **'Al iniciar el turno compartes tu ubicación en tiempo real con los pasajeros y con tu garita, mientras el turno esté activo. Puedes detenerlo cuando quieras (Ley 19.628).'**
  String get turnoConsent;

  /// No description provided for @turnoOnlyDrivers.
  ///
  /// In es, this message translates to:
  /// **'Esta sección es para los colectiveros de la garita.'**
  String get turnoOnlyDrivers;

  /// No description provided for @turnoNotificationTitle.
  ///
  /// In es, this message translates to:
  /// **'ColeTotal — en servicio'**
  String get turnoNotificationTitle;

  /// No description provided for @turnoNotificationText.
  ///
  /// In es, this message translates to:
  /// **'Transmitiendo tu posición a los pasajeros'**
  String get turnoNotificationText;

  /// No description provided for @turnoOffline.
  ///
  /// In es, this message translates to:
  /// **'Sin señal: tu posición se enviará apenas vuelva la conexión.'**
  String get turnoOffline;

  /// No description provided for @turnoRoute.
  ///
  /// In es, this message translates to:
  /// **'Recorrido'**
  String get turnoRoute;

  /// No description provided for @turnoRouteNone.
  ///
  /// In es, this message translates to:
  /// **'Sin recorrido asignado'**
  String get turnoRouteNone;

  /// No description provided for @turnoRoutePick.
  ///
  /// In es, this message translates to:
  /// **'Elegir recorrido'**
  String get turnoRoutePick;

  /// No description provided for @turnoRouteHelp.
  ///
  /// In es, this message translates to:
  /// **'Los pasajeros ven tu línea al tocar tu colectivo en el mapa.'**
  String get turnoRouteHelp;

  /// No description provided for @turnoRouteEmpty.
  ///
  /// In es, this message translates to:
  /// **'Tu garita todavía no tiene recorridos activos.'**
  String get turnoRouteEmpty;

  /// No description provided for @agoSeconds.
  ///
  /// In es, this message translates to:
  /// **'{n} s'**
  String agoSeconds(String n);

  /// No description provided for @agoMinutes.
  ///
  /// In es, this message translates to:
  /// **'{n} min'**
  String agoMinutes(String n);

  /// No description provided for @save.
  ///
  /// In es, this message translates to:
  /// **'Guardar'**
  String get save;

  /// No description provided for @delete.
  ///
  /// In es, this message translates to:
  /// **'Eliminar'**
  String get delete;

  /// No description provided for @adminOnly.
  ///
  /// In es, this message translates to:
  /// **'Esta sección es para los administradores de garita.'**
  String get adminOnly;

  /// No description provided for @adminMetricUnits.
  ///
  /// In es, this message translates to:
  /// **'En servicio'**
  String get adminMetricUnits;

  /// No description provided for @adminMetricStops.
  ///
  /// In es, this message translates to:
  /// **'Paraderos'**
  String get adminMetricStops;

  /// No description provided for @adminMetricRoutes.
  ///
  /// In es, this message translates to:
  /// **'Recorridos'**
  String get adminMetricRoutes;

  /// No description provided for @adminStopsDesc.
  ///
  /// In es, this message translates to:
  /// **'Agrega, mueve o da de baja paraderos'**
  String get adminStopsDesc;

  /// No description provided for @adminRoutesDesc.
  ///
  /// In es, this message translates to:
  /// **'Define los recorridos de la línea'**
  String get adminRoutesDesc;

  /// No description provided for @adminDriversDesc.
  ///
  /// In es, this message translates to:
  /// **'Habilita o deshabilita a tus choferes'**
  String get adminDriversDesc;

  /// No description provided for @adminFleetDesc.
  ///
  /// In es, this message translates to:
  /// **'Dónde está cada unidad ahora mismo'**
  String get adminFleetDesc;

  /// No description provided for @adminSectionData.
  ///
  /// In es, this message translates to:
  /// **'Datos de la línea'**
  String get adminSectionData;

  /// No description provided for @adminSectionOps.
  ///
  /// In es, this message translates to:
  /// **'Operación'**
  String get adminSectionOps;

  /// No description provided for @stopAdd.
  ///
  /// In es, this message translates to:
  /// **'Añadir paradero'**
  String get stopAdd;

  /// No description provided for @stopEdit.
  ///
  /// In es, this message translates to:
  /// **'Editar paradero'**
  String get stopEdit;

  /// No description provided for @stopName.
  ///
  /// In es, this message translates to:
  /// **'Nombre'**
  String get stopName;

  /// No description provided for @stopAddress.
  ///
  /// In es, this message translates to:
  /// **'Dirección'**
  String get stopAddress;

  /// No description provided for @stopActive.
  ///
  /// In es, this message translates to:
  /// **'Visible para los pasajeros'**
  String get stopActive;

  /// No description provided for @stopDeleteTitle.
  ///
  /// In es, this message translates to:
  /// **'Dar de baja el paradero'**
  String get stopDeleteTitle;

  /// No description provided for @stopDeleteMessage.
  ///
  /// In es, this message translates to:
  /// **'{nombre} dejará de aparecer en el mapa y en las búsquedas. No se borra: los recorridos y el historial que lo referencian siguen funcionando.'**
  String stopDeleteMessage(String nombre);

  /// No description provided for @stopDeactivate.
  ///
  /// In es, this message translates to:
  /// **'Dar de baja'**
  String get stopDeactivate;

  /// No description provided for @stopSaved.
  ///
  /// In es, this message translates to:
  /// **'Paradero guardado.'**
  String get stopSaved;

  /// No description provided for @stopDeleted.
  ///
  /// In es, this message translates to:
  /// **'Paradero dado de baja.'**
  String get stopDeleted;

  /// No description provided for @stopPickOnMap.
  ///
  /// In es, this message translates to:
  /// **'Mantén pulsado el mapa para mover el paradero'**
  String get stopPickOnMap;

  /// No description provided for @stopSearchHint.
  ///
  /// In es, this message translates to:
  /// **'Buscar paradero…'**
  String get stopSearchHint;

  /// No description provided for @stopsEmpty.
  ///
  /// In es, this message translates to:
  /// **'Todavía no hay paraderos cargados.'**
  String get stopsEmpty;

  /// No description provided for @stopsImportSeed.
  ///
  /// In es, this message translates to:
  /// **'Importar paraderos de ejemplo'**
  String get stopsImportSeed;

  /// No description provided for @stopsImported.
  ///
  /// In es, this message translates to:
  /// **'Se importaron {count} paraderos.'**
  String stopsImported(String count);

  /// No description provided for @stopsSeedNotice.
  ///
  /// In es, this message translates to:
  /// **'Estos son paraderos de referencia, todavía no están en la base de datos de tu garita. Impórtalos una vez para poder editarlos.'**
  String get stopsSeedNotice;

  /// No description provided for @stopInactive.
  ///
  /// In es, this message translates to:
  /// **'Dado de baja'**
  String get stopInactive;

  /// No description provided for @stopReactivate.
  ///
  /// In es, this message translates to:
  /// **'Reactivar'**
  String get stopReactivate;

  /// No description provided for @stopReactivated.
  ///
  /// In es, this message translates to:
  /// **'Paradero reactivado.'**
  String get stopReactivated;

  /// No description provided for @savedOffline.
  ///
  /// In es, this message translates to:
  /// **'Guardado sin conexión: se sincronizará al recuperar la señal.'**
  String get savedOffline;

  /// No description provided for @routeGeometryUpdated.
  ///
  /// In es, this message translates to:
  /// **'Se actualizó el trazado de {count} recorridos.'**
  String routeGeometryUpdated(String count);

  /// No description provided for @fleetEmpty.
  ///
  /// In es, this message translates to:
  /// **'Ninguna unidad en servicio ahora mismo.'**
  String get fleetEmpty;

  /// No description provided for @fleetEmptyHint.
  ///
  /// In es, this message translates to:
  /// **'Aparecerán aquí en cuanto un chofer inicie su turno.'**
  String get fleetEmptyHint;

  /// No description provided for @fleetSeenNow.
  ///
  /// In es, this message translates to:
  /// **'Ahora mismo'**
  String get fleetSeenNow;

  /// No description provided for @fleetSeenAgo.
  ///
  /// In es, this message translates to:
  /// **'Hace {minutos} min'**
  String fleetSeenAgo(String minutos);

  /// No description provided for @fleetUnitsInService.
  ///
  /// In es, this message translates to:
  /// **'{count} en servicio'**
  String fleetUnitsInService(String count);

  /// No description provided for @fleetAllGaritas.
  ///
  /// In es, this message translates to:
  /// **'Todas las garitas'**
  String get fleetAllGaritas;

  /// No description provided for @routeAdd.
  ///
  /// In es, this message translates to:
  /// **'Nuevo recorrido'**
  String get routeAdd;

  /// No description provided for @routeEdit.
  ///
  /// In es, this message translates to:
  /// **'Editar recorrido'**
  String get routeEdit;

  /// No description provided for @routeName.
  ///
  /// In es, this message translates to:
  /// **'Nombre del recorrido'**
  String get routeName;

  /// No description provided for @routeColor.
  ///
  /// In es, this message translates to:
  /// **'Color en el mapa'**
  String get routeColor;

  /// No description provided for @routeStops.
  ///
  /// In es, this message translates to:
  /// **'Paraderos del recorrido'**
  String get routeStops;

  /// No description provided for @routeStopsHelp.
  ///
  /// In es, this message translates to:
  /// **'Arrastra para reordenar: el trazado sigue este orden.'**
  String get routeStopsHelp;

  /// No description provided for @routeAddStop.
  ///
  /// In es, this message translates to:
  /// **'Agregar paradero'**
  String get routeAddStop;

  /// No description provided for @routeActive.
  ///
  /// In es, this message translates to:
  /// **'Recorrido activo'**
  String get routeActive;

  /// No description provided for @routeSaved.
  ///
  /// In es, this message translates to:
  /// **'Recorrido guardado.'**
  String get routeSaved;

  /// No description provided for @routeDeleted.
  ///
  /// In es, this message translates to:
  /// **'Recorrido eliminado.'**
  String get routeDeleted;

  /// No description provided for @routesEmpty.
  ///
  /// In es, this message translates to:
  /// **'Todavía no hay recorridos definidos.'**
  String get routesEmpty;

  /// No description provided for @routeStopCount.
  ///
  /// In es, this message translates to:
  /// **'{count} paraderos'**
  String routeStopCount(String count);

  /// No description provided for @routeNeedsStops.
  ///
  /// In es, this message translates to:
  /// **'Un recorrido necesita al menos dos paraderos.'**
  String get routeNeedsStops;

  /// No description provided for @routeDeleteTitle.
  ///
  /// In es, this message translates to:
  /// **'Eliminar recorrido'**
  String get routeDeleteTitle;

  /// No description provided for @routeDeleteMessage.
  ///
  /// In es, this message translates to:
  /// **'Se eliminará {nombre}. Los paraderos no se tocan.'**
  String routeDeleteMessage(String nombre);

  /// No description provided for @routeTraceHint.
  ///
  /// In es, this message translates to:
  /// **'El trazado se calcula siguiendo las calles entre los paraderos, en el orden de la lista.'**
  String get routeTraceHint;

  /// No description provided for @driversEmpty.
  ///
  /// In es, this message translates to:
  /// **'Todavía no hay choferes registrados en tu garita.'**
  String get driversEmpty;

  /// No description provided for @driversEmptyHint.
  ///
  /// In es, this message translates to:
  /// **'Entrégales el código de garita para que se registren.'**
  String get driversEmptyHint;

  /// No description provided for @driverInService.
  ///
  /// In es, this message translates to:
  /// **'En servicio'**
  String get driverInService;

  /// No description provided for @driverEnableHelp.
  ///
  /// In es, this message translates to:
  /// **'Un chofer deshabilitado no puede iniciar turno ni transmitir su posición.'**
  String get driverEnableHelp;

  /// No description provided for @driversNoPasswordReset.
  ///
  /// In es, this message translates to:
  /// **'No se pueden restablecer contraseñas desde la app: la patente no es un correo real. Si un chofer pierde la suya, deshabilita su cuenta y entrégale un código nuevo para que se registre otra vez.'**
  String get driversNoPasswordReset;

  /// No description provided for @driverSaved.
  ///
  /// In es, this message translates to:
  /// **'Cambios guardados.'**
  String get driverSaved;

  /// No description provided for @sortNearest.
  ///
  /// In es, this message translates to:
  /// **'Cercanos'**
  String get sortNearest;

  /// No description provided for @sortRecent.
  ///
  /// In es, this message translates to:
  /// **'Recientes'**
  String get sortRecent;

  /// No description provided for @sortRecentEmpty.
  ///
  /// In es, this message translates to:
  /// **'Todavía no has consultado ningún paradero.'**
  String get sortRecentEmpty;

  /// No description provided for @stopLinesTitle.
  ///
  /// In es, this message translates to:
  /// **'Colectivos que pasan por aquí'**
  String get stopLinesTitle;

  /// No description provided for @stopLinesEmpty.
  ///
  /// In es, this message translates to:
  /// **'Todavía no hay colectivos asignados a este paradero.'**
  String get stopLinesEmpty;

  /// No description provided for @stopLinesEmptyHint.
  ///
  /// In es, this message translates to:
  /// **'La garita aún no ha cargado sus recorridos.'**
  String get stopLinesEmptyHint;

  /// No description provided for @stopWalkHere.
  ///
  /// In es, this message translates to:
  /// **'Cómo llegar'**
  String get stopWalkHere;

  /// No description provided for @lineOnMap.
  ///
  /// In es, this message translates to:
  /// **'Recorrido de {nombre}'**
  String lineOnMap(String nombre);

  /// No description provided for @clearLine.
  ///
  /// In es, this message translates to:
  /// **'Quitar recorrido'**
  String get clearLine;

  /// No description provided for @loadingLine.
  ///
  /// In es, this message translates to:
  /// **'Trazando el recorrido…'**
  String get loadingLine;

  /// No description provided for @searchAddressHint.
  ///
  /// In es, this message translates to:
  /// **'¿A qué dirección vas?'**
  String get searchAddressHint;

  /// No description provided for @searchNoResults.
  ///
  /// In es, this message translates to:
  /// **'No se encontró esa dirección.'**
  String get searchNoResults;

  /// No description provided for @searchSearching.
  ///
  /// In es, this message translates to:
  /// **'Buscando…'**
  String get searchSearching;

  /// No description provided for @searchClear.
  ///
  /// In es, this message translates to:
  /// **'Limpiar'**
  String get searchClear;

  /// No description provided for @suggestTitle.
  ///
  /// In es, this message translates to:
  /// **'Mejores paraderos para tu destino'**
  String get suggestTitle;

  /// No description provided for @suggestSubtitle.
  ///
  /// In es, this message translates to:
  /// **'Ordenados por lo que caminas en total'**
  String get suggestSubtitle;

  /// No description provided for @suggestWalkToStop.
  ///
  /// In es, this message translates to:
  /// **'{d} hasta el paradero'**
  String suggestWalkToStop(String d);

  /// No description provided for @suggestWalkFromStop.
  ///
  /// In es, this message translates to:
  /// **'{d} desde la bajada'**
  String suggestWalkFromStop(String d);

  /// No description provided for @suggestTakeLine.
  ///
  /// In es, this message translates to:
  /// **'Toma {linea}'**
  String suggestTakeLine(String linea);

  /// No description provided for @suggestGetOff.
  ///
  /// In es, this message translates to:
  /// **'Bájate en {paradero}'**
  String suggestGetOff(String paradero);

  /// No description provided for @suggestTotal.
  ///
  /// In es, this message translates to:
  /// **'{d} a pie en total'**
  String suggestTotal(String d);

  /// No description provided for @suggestNoRoutes.
  ///
  /// In es, this message translates to:
  /// **'La garita todavía no ha cargado sus recorridos, así que estos paraderos se ordenan sólo por cercanía.'**
  String get suggestNoRoutes;

  /// No description provided for @suggestEmpty.
  ///
  /// In es, this message translates to:
  /// **'No hay paraderos que sirvan para ese destino.'**
  String get suggestEmpty;

  /// No description provided for @suggestLocationNeeded.
  ///
  /// In es, this message translates to:
  /// **'Necesitamos tu ubicación para recomendarte un paradero.'**
  String get suggestLocationNeeded;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['es'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'es':
      return AppLocalizationsEs();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
