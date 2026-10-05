import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'package:taxi1/config/app_version.dart';
import 'package:taxi1/firebase_options.dart';
import 'package:taxi1/l10n/app_localizations.dart';
import 'package:taxi1/screens/main_screen.dart';
import 'package:taxi1/services/auth_service.dart';
import 'package:taxi1/services/firebase_telemetria_service.dart';
import 'package:taxi1/services/garita_service.dart';
import 'package:taxi1/services/location_service.dart';
import 'package:taxi1/services/preferences_service.dart';
import 'package:taxi1/services/recorridos_service.dart';
import 'package:taxi1/services/route_service.dart';
import 'package:taxi1/services/turno_service.dart';
import 'package:taxi1/services/stop_history_service.dart';
import 'package:taxi1/services/stops_service.dart';
import 'package:taxi1/theme/app_text_scaler.dart';
import 'package:taxi1/theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Caché offline explícita (RF-07-01): los paraderos y recorridos tienen que
  // verse en los tramos sin cobertura de los cerros de Quilpué.
  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: true,
    cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
  );

  // La versión instalada, que compara el actualizador y registra la auditoría
  // de turnos. Se lee del APK en vez de repetirse a mano en el código.
  await AppVersion.load();

  // Antes que las preferencias: el rol decide qué pantallas existen, así que
  // la primera construcción del árbol ya tiene que conocerlo.
  await AuthService.instance.init();

  // Engancha el turno a la sesión: cerrar sesión tiene que detener la
  // telemetría ANTES de perder el token, o el nodo del vehículo queda colgado
  // en el mapa de todos los pasajeros.
  await TurnoService.instance.bind();

  // Los datos de la garita sólo se escuchan cuando hay un administrador en
  // sesión: un listener abierto contra datos que el usuario ya no puede leer
  // sólo produce errores de reglas.
  GaritaService.instance.bind();

  await PreferencesService.instance.load();

  // El listener de paraderos va aparte de la siembra: la lista ya trae los
  // paraderos semilla desde el constructor, así que la app dibuja algo en el
  // primer frame aunque Firestore tarde o no responda.
  StopsService.instance.startListening();

  // Los recorridos los lee todo el mundo, no sólo el administrador: son la
  // respuesta a "qué colectivos pasan por este paradero".
  RecorridosService.instance.startListening();

  // La flota en vivo: una sola suscripción para toda la app. Antes cada
  // pantalla (mapa, flota, portada de garita, choferes) abría la suya.
  FirebaseTelemetriaService.instance.startListening();

  // Si el administrador mueve o da de baja el paradero que el pasajero tiene
  // como destino, la ruta dibujada apuntaría a un fantasma.
  StopsService.instance.addListener(
    () => RouteService.instance.refreshDestination(StopsService.instance.byId),
  );

  // Después de StopsService: el historial guarda ids y los resuelve contra él.
  await StopHistoryService.instance.load();

  runApp(const ColeTotalApp());

  // El GPS se abre una sola vez y para toda la app (ver `LocationService`), y
  // después del primer frame: el diálogo de permiso necesita la actividad ya
  // en pantalla.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(LocationService.instance.start());
  });
}

class ColeTotalApp extends StatefulWidget {
  const ColeTotalApp({super.key});

  @override
  State<ColeTotalApp> createState() => _ColeTotalAppState();
}

class _ColeTotalAppState extends State<ColeTotalApp> {
  final prefs = PreferencesService.instance;

  /// `ColorScheme.fromSeed` hace un cálculo de color no trivial y este widget
  /// se reconstruye ante *cualquier* cambio de preferencia, así que el tema se
  /// memoiza por (brillo, densidad) en vez de recalcularse cada vez.
  final Map<(Brightness, bool), ThemeData> _themeCache = {};

  @override
  void initState() {
    super.initState();
    prefs.addListener(_onPrefsChanged);
  }

  @override
  void dispose() {
    prefs.removeListener(_onPrefsChanged);
    super.dispose();
  }

  void _onPrefsChanged() {
    if (mounted) setState(() {});
  }

  ThemeData _theme(Brightness brightness) => _themeCache.putIfAbsent((
    brightness,
    prefs.compactMode,
  ), () => buildAppTheme(brightness: brightness, compact: prefs.compactMode));

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ColeTotal',
      debugShowCheckedModeBanner: false,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      themeMode: prefs.themeMode,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],

      // Una sola fuente de verdad. Antes acá se declaraba `[Locale('en'),
      // Locale('es')]` mientras el delegate solo soporta `es`: en un teléfono
      // en inglés, Flutter resolvía a `en`, el delegate no cargaba y
      // `AppLocalizations.of(context)!` reventaba al abrir la app.
      supportedLocales: AppLocalizations.supportedLocales,

      // El ajuste de tamaño de fuente se aplica una vez, acá, y así alcanza a
      // todas las pantallas. Antes se multiplicaba a mano en cada `TextStyle`,
      // por lo que Mapa y Rutas lo ignoraban por completo.
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        return MediaQuery(
          data: mq.copyWith(
            textScaler: AppTextScaler(mq.textScaler, prefs.fontSizeMultiplier),
          ),
          child: child!,
        );
      },

      home: const MainScreen(),
    );
  }
}
