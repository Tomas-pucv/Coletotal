// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Spanish Castilian (`es`).
class AppLocalizationsEs extends AppLocalizations {
  AppLocalizationsEs([String locale = 'es']) : super(locale);

  @override
  String get navMap => 'Mapa';

  @override
  String get navRoutes => 'Líneas';

  @override
  String get navPreferences => 'Preferencias';

  @override
  String get calculatingRoute => 'Calculando ruta…';

  @override
  String get closeRoute => 'Cerrar ruta';

  @override
  String get routeErrorDefault =>
      'No se pudo obtener la ruta. Inténtalo de nuevo.';

  @override
  String get reorientMap => 'Orientar al norte';

  @override
  String get recenterActive => 'Seguimiento activo';

  @override
  String get recenterInactive => 'Centrar en mi ubicación';

  @override
  String get telemetryUnavailable =>
      'No se pudo cargar la posición de los colectivos.';

  @override
  String get mapLayers => 'Capas del mapa';

  @override
  String get moreSettings => 'Más ajustes';

  @override
  String get veryClose => 'Muy cerca';

  @override
  String get closeDistance => 'Cerca';

  @override
  String get mediumDistance => 'A media distancia';

  @override
  String get far => 'Lejos';

  @override
  String get recentStops => 'Consultados recientemente';

  @override
  String get locationOffMessage =>
      'Activa el GPS del teléfono para ver tu posición y los paraderos cercanos.';

  @override
  String get locationDeniedMessage =>
      'ColeTotal necesita acceso a tu ubicación para calcular rutas y mostrarte los paraderos más cercanos.';

  @override
  String get locationDisabledByPreference =>
      'Tienes el rastreo de ubicación desactivado en Preferencias.';

  @override
  String get openSettings => 'Abrir ajustes';

  @override
  String get retry => 'Reintentar';

  @override
  String get preferencesTitle => 'Preferencias';

  @override
  String get mapNormal => 'Calles';

  @override
  String get mapNormalDesc => 'Mapa estándar';

  @override
  String get satellite => 'Satélite';

  @override
  String get satelliteDesc => 'Foto aérea · requiere conexión';

  @override
  String get sectionAppearance => 'Apariencia';

  @override
  String get themeLabel => 'Tema';

  @override
  String get themeSystemShort => 'Auto';

  @override
  String get themeLightShort => 'Claro';

  @override
  String get themeDarkShort => 'Oscuro';

  @override
  String get themeSystem => 'Automático (según el sistema)';

  @override
  String get themeLight => 'Tema claro';

  @override
  String get themeDark => 'Tema oscuro';

  @override
  String get fontSize => 'Tamaño de fuente';

  @override
  String get fontSizePreviewHint => 'Así se verán los paraderos';

  @override
  String get compactMode => 'Modo compacto';

  @override
  String get compactModeDesc => 'Filas más juntas, cabe más en pantalla';

  @override
  String get animations => 'Animaciones';

  @override
  String get animationsDesc => 'Transiciones y pulso de los paraderos';

  @override
  String get sectionPrivacy => 'Privacidad';

  @override
  String get locationTracking => 'Rastreo de ubicación';

  @override
  String get locationTrackingDesc =>
      'Necesario para centrar el mapa y calcular rutas';

  @override
  String get disableTrackingTitle => 'Deshabilitar rastreo';

  @override
  String get disableTrackingMessage =>
      '¿Estás seguro? El mapa necesita tu ubicación para funcionar correctamente.';

  @override
  String get cancel => 'Cancelar';

  @override
  String get confirm => 'Confirmar';

  @override
  String get sectionAbout => 'Acerca de';

  @override
  String aboutVersion(String version) {
    return 'ColeTotal versión $version';
  }

  @override
  String get aboutSubtitle =>
      'Rutas y paraderos de Transportes Serrano, Quilpué.';

  @override
  String get updateCheck => 'Buscar actualizaciones';

  @override
  String updateUpToDate(String version) {
    return 'Tienes la versión más reciente ($version)';
  }

  @override
  String get updateTitle => '¡Nueva versión disponible!';

  @override
  String updateVersions(String nueva, String instalada) {
    return 'Versión $nueva (instalada: $instalada)';
  }

  @override
  String get updateChangelogTitle => 'Novedades y mejoras:';

  @override
  String get updateDefaultChangelog =>
      'Nueva versión con mejoras operacionales.';

  @override
  String get updateMandatory =>
      'Esta actualización es obligatoria para continuar operando en la garita.';

  @override
  String get updateLater => 'Recordar más tarde';

  @override
  String get updateNow => 'Actualizar ahora';

  @override
  String get updateOpenFailed =>
      'No se pudo abrir el enlace de descarga del APK.';

  @override
  String get errInvalidCoords =>
      'Origen o destino inválido (coordenadas fuera de rango).';

  @override
  String get errNoRoute => 'No se pudo obtener la ruta. Verifica tu conexión.';

  @override
  String get errProvider => 'El servicio de rutas no respondió correctamente.';

  @override
  String get errGeneric => 'Ocurrió un error al calcular la ruta.';

  @override
  String distanceKm(String value) {
    return '$value km';
  }

  @override
  String distanceM(String value) {
    return '$value m';
  }

  @override
  String durationMin(String minutes) {
    return '$minutes min';
  }

  @override
  String durationHour(String h) {
    return '$h h';
  }

  @override
  String durationHourMin(String h, String m) {
    return '$h h $m min';
  }

  @override
  String get navTurno => 'Turno';

  @override
  String get navFlota => 'Flota';

  @override
  String get navGarita => 'Garita';

  @override
  String get navRecorridos => 'Recorridos';

  @override
  String get navDrivers => 'Choferes';

  @override
  String get roleGuest => 'Invitado';

  @override
  String get roleColectivero => 'Colectivero';

  @override
  String get roleAdmin => 'Administrador';

  @override
  String get roleColectiveroSubtitle => 'Transmites tu posición a la garita';

  @override
  String get roleAdminSubtitle => 'Gestionas los datos de la garita';

  @override
  String get openMenu => 'Abrir menú';

  @override
  String get drawerDriverSection => 'Mi jornada';

  @override
  String get drawerAdminSection => 'Garita';

  @override
  String get signIn => 'Iniciar sesión';

  @override
  String get createAccount => 'Crear cuenta';

  @override
  String get signOut => 'Cerrar sesión';

  @override
  String get signOutShort => 'Salir';

  @override
  String get signOutMessage =>
      'Volverás al modo invitado y dejarás de transmitir tu ubicación.';

  @override
  String get authLoginTitle => 'Iniciar sesión';

  @override
  String get authRegisterTitle => 'Crear cuenta';

  @override
  String get authRoleQuestion => '¿Cómo vas a entrar?';

  @override
  String get authPatente => 'Patente';

  @override
  String get authPatenteHint => 'BBBB12';

  @override
  String get authEmail => 'Correo electrónico';

  @override
  String get authPassword => 'Contraseña';

  @override
  String get authPasswordConfirm => 'Repite la contraseña';

  @override
  String get authName => 'Nombre';

  @override
  String get authNameHint => 'Como quieres que te vean en la garita';

  @override
  String get authCodigo => 'Código de garita';

  @override
  String get authCodigoHelp => 'Te lo entrega el administrador de tu garita.';

  @override
  String get authCodigoChecking => 'Comprobando código…';

  @override
  String authCodigoValid(String garita) {
    return 'Código válido para $garita';
  }

  @override
  String get authCodigoInvalid =>
      'Ese código no existe, no está habilitado o no corresponde a este rol.';

  @override
  String get authSubmitLogin => 'Entrar';

  @override
  String get authSubmitRegister => 'Crear cuenta';

  @override
  String get authNoAccount => '¿No tienes cuenta? Regístrate';

  @override
  String get authHasAccount => '¿Ya tienes cuenta? Inicia sesión';

  @override
  String get authRequired => 'Completa este campo';

  @override
  String get authPatenteInvalid =>
      'Patente inválida. Debe ser como BBBB12 o AB1234.';

  @override
  String get authEmailInvalid => 'Escribe un correo válido.';

  @override
  String get authPasswordShort => 'Mínimo 6 caracteres.';

  @override
  String get authPasswordMismatch => 'Las contraseñas no coinciden.';

  @override
  String get authPasswordNote =>
      'Guarda bien tu contraseña: la patente no es un correo real, así que no se puede recuperar por email. Si la pierdes, tendrás que pedírselo a tu garita.';

  @override
  String get authShowPassword => 'Mostrar contraseña';

  @override
  String get authHidePassword => 'Ocultar contraseña';

  @override
  String authWelcome(String nombre) {
    return 'Hola, $nombre';
  }

  @override
  String get authGuestHint =>
      'El invitado no necesita cuenta: cierra esta pantalla y sigue usando el mapa.';

  @override
  String get errAuthCredentials => 'Patente o contraseña incorrecta.';

  @override
  String get errAuthCredentialsEmail => 'Correo o contraseña incorrecta.';

  @override
  String get errAuthAccountInUse =>
      'Ya existe una cuenta registrada con esos datos.';

  @override
  String get errAuthWeakPassword =>
      'La contraseña es muy débil: usa al menos 6 caracteres.';

  @override
  String get errAuthPatenteInvalid => 'Patente inválida.';

  @override
  String get errAuthCodigoInvalid => 'Código de garita inválido para ese rol.';

  @override
  String get errAuthDisabled =>
      'Tu cuenta está deshabilitada. Habla con tu garita.';

  @override
  String get errAuthNetwork =>
      'Sin conexión. Revisa tu red e inténtalo de nuevo.';

  @override
  String get errAuthUnknown =>
      'No se pudo completar la operación. Inténtalo de nuevo.';

  @override
  String get sectionAccount => 'Cuenta';

  @override
  String get turnoTitle => 'Turno';

  @override
  String get turnoOn => 'En servicio';

  @override
  String get turnoOff => 'Fuera de servicio';

  @override
  String get turnoStart => 'Iniciar turno';

  @override
  String get turnoEnd => 'Terminar turno';

  @override
  String get capacityAvailable => 'Disponible';

  @override
  String get capacityHalf => 'Medio lleno';

  @override
  String get capacityFull => 'Lleno';

  @override
  String get capacityAvailableLong => 'Disponible (con asientos)';

  @override
  String get capacityHalfLong => 'Medio lleno (pocos cupos)';

  @override
  String get capacityFullLong => 'Lleno (sin cupos)';

  @override
  String colectivoTitle(String patente) {
    return 'Colectivo $patente';
  }

  @override
  String get colectivoNoRoute => 'Sin recorrido informado';

  @override
  String colectivoLastSignal(String tiempo) {
    return 'Última señal hace $tiempo';
  }

  @override
  String get colectivoNoSignal => 'Sin señal';

  @override
  String colectivoSemanticLabel(String patente, String estado) {
    return 'Colectivo $patente, $estado';
  }

  @override
  String get turnoIssueTracking =>
      'Tienes el rastreo de ubicación desactivado en Preferencias. Actívalo para poder iniciar tu turno.';

  @override
  String get turnoIssueInactive =>
      'Tu cuenta está deshabilitada por la garita. Habla con el administrador.';

  @override
  String get turnoIssueLocation =>
      'No se pudo acceder al GPS. Revisa que esté encendido y que la app tenga permiso.';

  @override
  String get turnoConsent =>
      'Al iniciar el turno compartes tu ubicación en tiempo real con los pasajeros y con tu garita, mientras el turno esté activo. Puedes detenerlo cuando quieras (Ley 19.628).';

  @override
  String get turnoOnlyDrivers =>
      'Esta sección es para los colectiveros de la garita.';

  @override
  String get turnoNotificationTitle => 'ColeTotal — en servicio';

  @override
  String get turnoNotificationText =>
      'Transmitiendo tu posición a los pasajeros';

  @override
  String get turnoOffline =>
      'Sin señal: tu posición se enviará apenas vuelva la conexión.';

  @override
  String get turnoRouteNone => 'Sin recorrido asignado';

  @override
  String get turnoRoutePick => 'Elegir recorrido';

  @override
  String get turnoRouteEmpty =>
      'Tu garita todavía no tiene recorridos activos.';

  @override
  String get turnoRecenter => 'Volver a centrar';

  @override
  String get turnoEndConfirmTitle => '¿Terminar el turno?';

  @override
  String get turnoEndConfirmBody =>
      'Los pasajeros dejarán de ver tu colectivo en el mapa.';

  @override
  String get turnoConsentTitle => 'Tu ubicación durante el turno';

  @override
  String get turnoView2d => 'Vista plana, con el norte arriba';

  @override
  String get turnoView3d => 'Vista de navegación';

  @override
  String get turnoXiaomiTitle => 'Para que tu turno no se corte';

  @override
  String get turnoXiaomiBody =>
      'En los teléfonos Xiaomi, abre los ajustes de ColeTotal, deja «Ahorro de batería» en «Sin restricciones» y activa el «Inicio automático». Si no, el teléfono corta la conexión al bloquear la pantalla y los pasajeros dejan de ver tu colectivo.';

  @override
  String get turnoXiaomiOpen => 'Abrir ajustes';

  @override
  String get turnoXiaomiLater => 'Ahora no';

  @override
  String agoSeconds(String n) {
    return '$n s';
  }

  @override
  String agoMinutes(String n) {
    return '$n min';
  }

  @override
  String get save => 'Guardar';

  @override
  String get delete => 'Eliminar';

  @override
  String get adminOnly => 'Esta sección es para los administradores de garita.';

  @override
  String get adminMetricUnits => 'En servicio';

  @override
  String get adminMetricRoutes => 'Líneas activas';

  @override
  String get adminRoutesDesc => 'Dibuja la ida y la vuelta de cada línea';

  @override
  String get adminDriversDesc => 'Habilita o deshabilita a tus choferes';

  @override
  String get adminFleetDesc => 'Dónde está cada unidad ahora mismo';

  @override
  String get adminSectionData => 'Datos de la línea';

  @override
  String get adminSectionOps => 'Operación';

  @override
  String get savedOffline =>
      'Guardado sin conexión: se sincronizará al recuperar la señal.';

  @override
  String get fleetEmpty => 'Ninguna unidad en servicio ahora mismo.';

  @override
  String get fleetEmptyHint =>
      'Aparecerán aquí en cuanto un chofer inicie su turno.';

  @override
  String get fleetSeenNow => 'Ahora mismo';

  @override
  String fleetSeenAgo(String minutos) {
    return 'Hace $minutos min';
  }

  @override
  String fleetUnitsInService(String count) {
    return '$count en servicio';
  }

  @override
  String get fleetAllGaritas => 'Todas las garitas';

  @override
  String get routeAdd => 'Nueva línea';

  @override
  String get routeEdit => 'Editar línea';

  @override
  String get routeName => 'Nombre de la línea';

  @override
  String get routeActive => 'Línea activa';

  @override
  String get routeSaved => 'Línea guardada.';

  @override
  String get routeDeleted => 'Línea eliminada.';

  @override
  String get routesEmpty => 'Todavía no hay líneas.';

  @override
  String get routeDeleteTitle => 'Eliminar línea';

  @override
  String routeDeleteMessage(String nombre) {
    return 'Se eliminará $nombre, con su ida y su vuelta.';
  }

  @override
  String get routeTraceHint =>
      'Mantén presionado el mapa para marcar el recorrido punto por punto. La app lo ajusta a las calles y a sus sentidos de tránsito.';

  @override
  String get driversEmpty =>
      'Todavía no hay choferes registrados en tu garita.';

  @override
  String get driversEmptyHint =>
      'Entrégales el código de garita para que se registren.';

  @override
  String get driverInService => 'En servicio';

  @override
  String get driverEnableHelp =>
      'Un chofer deshabilitado no puede iniciar turno ni transmitir su posición.';

  @override
  String get driversNoPasswordReset =>
      'No se pueden restablecer contraseñas desde la app: la patente no es un correo real. Si un chofer pierde la suya, deshabilita su cuenta y entrégale un código nuevo para que se registre otra vez.';

  @override
  String get driverSaved => 'Cambios guardados.';

  @override
  String lineOnMap(String nombre) {
    return 'Recorrido de $nombre';
  }

  @override
  String get clearLine => 'Quitar recorrido';

  @override
  String get searchAddressHint => '¿A qué dirección vas?';

  @override
  String get searchNoResults => 'No se encontró esa dirección.';

  @override
  String get searchSearching => 'Buscando…';

  @override
  String get searchClear => 'Limpiar';

  @override
  String get suggestTitle => 'Cómo llegar en colectivo';

  @override
  String get suggestSubtitle => 'Ordenadas por lo que caminas en total';

  @override
  String suggestTakeLine(String linea, String sentido) {
    return 'Toma $linea ($sentido)';
  }

  @override
  String suggestTotal(String d) {
    return '$d a pie en total';
  }

  @override
  String get suggestEmpty =>
      'Ninguna línea pasa cerca de ti y de tu destino a la vez.';

  @override
  String get suggestLocationNeeded =>
      'Necesitamos tu ubicación para recomendarte una línea.';

  @override
  String get sentidoIda => 'Ida';

  @override
  String get sentidoVuelta => 'Vuelta';

  @override
  String get routeActiveDesc =>
      'La ven los pasajeros y la pueden elegir los choferes';

  @override
  String get routeInactive => 'Apagada';

  @override
  String routeSummaryBoth(String ida, String vuelta) {
    return 'Ida $ida · vuelta $vuelta';
  }

  @override
  String routeSummaryIdaOnly(String ida) {
    return 'Sólo ida · $ida';
  }

  @override
  String get routeSummaryEmpty => 'Sin recorrido dibujado';

  @override
  String get routeAddPointHint =>
      'Mantén presionado el mapa para agregar el siguiente punto';

  @override
  String get routeUndoPoint => 'Deshacer el último punto';

  @override
  String get routeClearPoints => 'Borrar los puntos de este sentido';

  @override
  String get routeVueltaFromIda => 'Empezar la vuelta desde la ida';

  @override
  String routePointsButton(String count) {
    return 'Puntos ($count)';
  }

  @override
  String routePointLabel(String n) {
    return 'Punto $n';
  }

  @override
  String routeTrayectoSummary(String count, String distancia) {
    return '$count puntos · $distancia';
  }

  @override
  String get routeSnapping => 'Ajustando a las calles…';

  @override
  String get routeSnapFailed =>
      'No se pudo ajustar a las calles. Revisa que los puntos estén sobre calles.';

  @override
  String get routeNeedsIda => 'Marca al menos dos puntos en la ida.';

  @override
  String get linesSearchHint => 'Buscar línea…';

  @override
  String get linesEmpty => 'La garita todavía no ha publicado sus líneas.';

  @override
  String get linesNoMatch => 'Ninguna línea coincide con tu búsqueda.';

  @override
  String linesPassesAt(String d) {
    return 'Pasa a $d de ti';
  }

  @override
  String get linesOnlyIda => 'Sólo ida';

  @override
  String get lineShowOnMap => 'Ver en el mapa';

  @override
  String suggestWalkToLine(String d) {
    return 'Camina $d hasta la línea';
  }

  @override
  String suggestRide(String d) {
    return 'Viaja $d en colectivo';
  }

  @override
  String suggestWalkFromLine(String d) {
    return 'Bájate a $d de tu destino';
  }

  @override
  String get boardHere => 'Súbete aquí';

  @override
  String get alightHere => 'Bájate aquí';

  @override
  String get tripBoardHint => 'Hazle la seña al colectivo en el punto marcado';

  @override
  String get tapToSeeBoarding => 'Tocar para ver dónde subir';

  @override
  String get routePointRemoved => 'Punto eliminado';

  @override
  String get undo => 'Deshacer';
}
