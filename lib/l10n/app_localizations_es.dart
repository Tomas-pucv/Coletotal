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
  String get navRoutes => 'Paraderos';

  @override
  String get navPreferences => 'Preferencias';

  @override
  String get calculatingRoute => 'Calculando ruta…';

  @override
  String get searchingLocation => 'Buscando ubicación…';

  @override
  String get closeRoute => 'Cerrar ruta';

  @override
  String get tapToGoStop => 'Tocar para ir al paradero';

  @override
  String coordsLabel(String lat, String lng) {
    return 'Lat: $lat, Lng: $lng';
  }

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
  String stopSemanticLabel(String name, String address) {
    return 'Paradero $name, $address';
  }

  @override
  String get telemetryUnavailable =>
      'No se pudo cargar la posición de los colectivos.';

  @override
  String get mapLayers => 'Capas del mapa';

  @override
  String get moreSettings => 'Más ajustes';

  @override
  String get calculateRouteTitle => 'Calcular Ruta';

  @override
  String get originLabel => 'Origen (Mi ubicación actual)';

  @override
  String get searchStopHint => 'Buscar paradero por nombre o dirección…';

  @override
  String get whereToGo => '¿A dónde quieres ir?';

  @override
  String noResults(String query) {
    return 'Sin resultados para \"$query\"';
  }

  @override
  String get noResultsHint => 'Prueba con otro nombre o revisa la ortografía.';

  @override
  String get goToNearestStop => 'Ir al paradero más cercano';

  @override
  String get locationUnavailable =>
      'Tu ubicación aún no está disponible. Activa el GPS o espera unos segundos.';

  @override
  String get veryClose => 'Muy cerca';

  @override
  String get closeDistance => 'Cerca';

  @override
  String get mediumDistance => 'A media distancia';

  @override
  String get far => 'Lejos';

  @override
  String get distanceUnavailable => 'Distancia no disponible';

  @override
  String get enableLocationForSorting =>
      'Activa la ubicación para ordenar los paraderos por cercanía.';

  @override
  String get recentStops => 'Consultados recientemente';

  @override
  String get allStops => 'Todos los paraderos';

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
  String get saveHistory => 'Guardar historial';

  @override
  String saveHistoryDesc(String count) {
    return 'Recuerda los últimos $count paraderos consultados';
  }

  @override
  String get clearHistory => 'Borrar';

  @override
  String get historyCleared => 'Historial borrado.';

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
  String get navStops => 'Gestión de paraderos';

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
  String get roleGuestSubtitle => 'Estás usando ColeTotal sin cuenta';

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
  String get turnoOnDesc => 'Los pasajeros ven tu posición en el mapa.';

  @override
  String get turnoOffDesc => 'No se transmite nada. Nadie ve dónde estás.';

  @override
  String get turnoStart => 'Iniciar turno';

  @override
  String get turnoEnd => 'Terminar turno';

  @override
  String get turnoCapacity => 'Capacidad';

  @override
  String get turnoCapacityHelp =>
      'Cambia el color de tu marcador para los pasajeros y la garita.';

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
  String get turnoVehicle => 'Mi vehículo';

  @override
  String turnoLastSent(String tiempo) {
    return 'Última posición enviada hace $tiempo';
  }

  @override
  String get turnoNoSignal => 'Aún no se ha enviado ninguna posición.';

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
  String get turnoRoute => 'Recorrido';

  @override
  String get turnoRouteNone => 'Sin recorrido asignado';

  @override
  String get turnoRoutePick => 'Elegir recorrido';

  @override
  String get turnoRouteHelp =>
      'Los pasajeros ven tu línea al tocar tu colectivo en el mapa.';

  @override
  String get turnoRouteEmpty =>
      'Tu garita todavía no tiene recorridos activos.';

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
  String get adminMetricStops => 'Paraderos';

  @override
  String get adminMetricRoutes => 'Recorridos';

  @override
  String get adminStopsDesc => 'Agrega, mueve o da de baja paraderos';

  @override
  String get adminRoutesDesc => 'Define los recorridos de la línea';

  @override
  String get adminDriversDesc => 'Habilita o deshabilita a tus choferes';

  @override
  String get adminFleetDesc => 'Dónde está cada unidad ahora mismo';

  @override
  String get adminSectionData => 'Datos de la línea';

  @override
  String get adminSectionOps => 'Operación';

  @override
  String get stopAdd => 'Añadir paradero';

  @override
  String get stopEdit => 'Editar paradero';

  @override
  String get stopName => 'Nombre';

  @override
  String get stopAddress => 'Dirección';

  @override
  String get stopActive => 'Visible para los pasajeros';

  @override
  String get stopDeleteTitle => 'Dar de baja el paradero';

  @override
  String stopDeleteMessage(String nombre) {
    return '$nombre dejará de aparecer en el mapa y en las búsquedas. No se borra: los recorridos y el historial que lo referencian siguen funcionando.';
  }

  @override
  String get stopDeactivate => 'Dar de baja';

  @override
  String get stopSaved => 'Paradero guardado.';

  @override
  String get stopDeleted => 'Paradero dado de baja.';

  @override
  String get stopPickOnMap => 'Mantén pulsado el mapa para mover el paradero';

  @override
  String get stopSearchHint => 'Buscar paradero…';

  @override
  String get stopsEmpty => 'Todavía no hay paraderos cargados.';

  @override
  String get stopsImportSeed => 'Importar paraderos de ejemplo';

  @override
  String stopsImported(String count) {
    return 'Se importaron $count paraderos.';
  }

  @override
  String get stopsSeedNotice =>
      'Estos son paraderos de referencia, todavía no están en la base de datos de tu garita. Impórtalos una vez para poder editarlos.';

  @override
  String get stopInactive => 'Dado de baja';

  @override
  String get stopReactivate => 'Reactivar';

  @override
  String get stopReactivated => 'Paradero reactivado.';

  @override
  String get savedOffline =>
      'Guardado sin conexión: se sincronizará al recuperar la señal.';

  @override
  String routeGeometryUpdated(String count) {
    return 'Se actualizó el trazado de $count recorridos.';
  }

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
  String get routeAdd => 'Nuevo recorrido';

  @override
  String get routeEdit => 'Editar recorrido';

  @override
  String get routeName => 'Nombre del recorrido';

  @override
  String get routeColor => 'Color en el mapa';

  @override
  String get routeStops => 'Paraderos del recorrido';

  @override
  String get routeStopsHelp =>
      'Arrastra para reordenar: el trazado sigue este orden.';

  @override
  String get routeAddStop => 'Agregar paradero';

  @override
  String get routeActive => 'Recorrido activo';

  @override
  String get routeSaved => 'Recorrido guardado.';

  @override
  String get routeDeleted => 'Recorrido eliminado.';

  @override
  String get routesEmpty => 'Todavía no hay recorridos definidos.';

  @override
  String routeStopCount(String count) {
    return '$count paraderos';
  }

  @override
  String get routeNeedsStops => 'Un recorrido necesita al menos dos paraderos.';

  @override
  String get routeDeleteTitle => 'Eliminar recorrido';

  @override
  String routeDeleteMessage(String nombre) {
    return 'Se eliminará $nombre. Los paraderos no se tocan.';
  }

  @override
  String get routeTraceHint =>
      'El trazado se calcula siguiendo las calles entre los paraderos, en el orden de la lista.';

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
  String get sortNearest => 'Cercanos';

  @override
  String get sortRecent => 'Recientes';

  @override
  String get sortRecentEmpty => 'Todavía no has consultado ningún paradero.';

  @override
  String get stopLinesTitle => 'Colectivos que pasan por aquí';

  @override
  String get stopLinesEmpty =>
      'Todavía no hay colectivos asignados a este paradero.';

  @override
  String get stopLinesEmptyHint =>
      'La garita aún no ha cargado sus recorridos.';

  @override
  String get stopWalkHere => 'Cómo llegar';

  @override
  String lineOnMap(String nombre) {
    return 'Recorrido de $nombre';
  }

  @override
  String get clearLine => 'Quitar recorrido';

  @override
  String get loadingLine => 'Trazando el recorrido…';

  @override
  String get searchAddressHint => '¿A qué dirección vas?';

  @override
  String get searchNoResults => 'No se encontró esa dirección.';

  @override
  String get searchSearching => 'Buscando…';

  @override
  String get searchClear => 'Limpiar';

  @override
  String get suggestTitle => 'Mejores paraderos para tu destino';

  @override
  String get suggestSubtitle => 'Ordenados por lo que caminas en total';

  @override
  String suggestWalkToStop(String d) {
    return '$d hasta el paradero';
  }

  @override
  String suggestWalkFromStop(String d) {
    return '$d desde la bajada';
  }

  @override
  String suggestTakeLine(String linea) {
    return 'Toma $linea';
  }

  @override
  String suggestGetOff(String paradero) {
    return 'Bájate en $paradero';
  }

  @override
  String suggestTotal(String d) {
    return '$d a pie en total';
  }

  @override
  String get suggestNoRoutes =>
      'La garita todavía no ha cargado sus recorridos, así que estos paraderos se ordenan sólo por cercanía.';

  @override
  String get suggestEmpty => 'No hay paraderos que sirvan para ese destino.';

  @override
  String get suggestLocationNeeded =>
      'Necesitamos tu ubicación para recomendarte un paradero.';
}
