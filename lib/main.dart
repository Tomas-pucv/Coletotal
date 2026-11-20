import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:maplibre_gl/maplibre_gl.dart' show MapLibreMap;

import 'package:taxi1/config/app_version.dart';
import 'package:taxi1/config/map_config.dart';
import 'package:taxi1/firebase_options.dart';
import 'package:taxi1/l10n/app_localizations.dart';
import 'package:taxi1/screens/main_screen.dart';
import 'package:taxi1/services/auth_service.dart';
import 'package:taxi1/services/basemap_service.dart';
import 'package:taxi1/services/firebase_telemetria_service.dart';
import 'package:taxi1/services/garita_service.dart';
import 'package:taxi1/services/location_service.dart';
import 'package:taxi1/services/preferences_service.dart';
import 'package:taxi1/services/recorridos_service.dart';
import 'package:taxi1/services/simulacion_flota_service.dart';
import 'package:taxi1/services/turno_service.dart';
import 'package:taxi1/services/street_index.dart';
import 'package:taxi1/theme/app_text_scaler.dart';
import 'package:taxi1/theme/app_theme.dart';

/// Activa la simulación local de flota y posición por defecto en Quilpué
/// únicamente cuando se compila con `--dart-define=DEMO_MODE=true`.
const bool kDemoMode = bool.fromEnvironment('DEMO_MODE');

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Usa Hybrid Composition (TextureView) para integrar la vista nativa de
  // MapLibre en el árbol de widgets de Flutter sin errores de ciclo de vida
  // al rotar la pantalla o redimensionar la ventana en Android.
  MapLibreMap.useHybridComposition = true;

  // Inicia en paralelo la extracción y verificación de las teselas offline
  // del mapa base (PMTiles, estilos, fuentes y grafo de ruteo) sin bloquear
  // el arranque de la interfaz.
  unawaited(BasemapService.instance.load());

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Habilita persistencia offline ilimitada en Firestore para que las líneas
  // y metadatos sigan disponibles en sectores con baja cobertura móvil.
  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: true,
    cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
  );

  // Carga la versión real instalada desde los metadatos del paquete (APK).
  await AppVersion.load();

  // Inicializa la sesión antes de construir el árbol de widgets, ya que el
  // rol activo determina las pantallas y destinos de navegación disponibles.
  await AuthService.instance.init();

  // Vincula el ciclo de vida del turno a la sesión para detener la telemetría
  // en Realtime Database antes de revocar el token al cerrar sesión.
  await TurnoService.instance.bind();

  // Activa las suscripciones de gestión de garita únicamente cuando la sesión
  // pertenece a un administrador autenticado.
  GaritaService.instance.bind();

  await PreferencesService.instance.load();

  // Escucha el catálogo de recorridos para pasajeros, conductores y garita.
  RecorridosService.instance.startListening();

  // Mantiene una única suscripción compartida a la telemetría de flota en vivo
  // para todas las vistas de la aplicación.
  FirebaseTelemetriaService.instance.startListening();

  // Modo de demostración opcional (desactivado por omisión en producción):
  // fija una ubicación de respaldo en Quilpué e inyecta 3 unidades simuladas
  // cuando se ejecuta con `--dart-define=DEMO_MODE=true`.
  if (kDemoMode) {
    LocationService.instance.setDefaultPassengerPosition(kQuilpueCenter);
    SimulacionFlotaService.instance.start(centro: kQuilpueCenter);
  }

  runApp(const ColeTotalApp());

  // Inicia el servicio único de GPS tras renderizar el primer cuadro (para que
  // el diálogo de permisos cuente con una Activity activa) y precarga en un
  // isolate secundario el índice offline de calles.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(LocationService.instance.start());
    unawaited(StreetIndex.preload());
  });
}

class ColeTotalApp extends StatefulWidget {
  const ColeTotalApp({super.key});

  @override
  State<ColeTotalApp> createState() => _ColeTotalAppState();
}

class _ColeTotalAppState extends State<ColeTotalApp> {
  final _prefs = PreferencesService.instance;

  /// Memoiza los temas generados por `(brightness, compactMode)` para evitar
  /// recalcular `ColorScheme.fromSeed` cuando cambian otras preferencias.
  final Map<(Brightness, bool), ThemeData> _themeCache = {};

  @override
  void initState() {
    super.initState();
    _prefs.addListener(_onPrefsChanged);
  }

  @override
  void dispose() {
    _prefs.removeListener(_onPrefsChanged);
    super.dispose();
  }

  void _onPrefsChanged() {
    if (mounted) setState(() {});
  }

  ThemeData _theme(Brightness brightness) => _themeCache.putIfAbsent((
    brightness,
    _prefs.compactMode,
  ), () => buildAppTheme(brightness: brightness, compact: _prefs.compactMode));

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ColeTotal',
      debugShowCheckedModeBanner: false,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      themeMode: _prefs.themeMode,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],

      // Usa la lista de locales generada por AppLocalizations como única
      // fuente de verdad para evitar desajustes en dispositivos configurados
      // en otros idiomas.
      supportedLocales: AppLocalizations.supportedLocales,

      // Aplica el factor de escala tipográfica de forma transversal en la raíz
      // de MediaQuery para que alcance a todas las pantallas y componentes.
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        return MediaQuery(
          data: mq.copyWith(
            textScaler: AppTextScaler(
              mq.textScaler,
              _prefs.fontSizeMultiplier,
            ),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },

      home: const MainScreen(),
    );
  }
}
