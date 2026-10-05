import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:taxi1/config/map_config.dart';
import 'package:taxi1/l10n/app_localizations.dart';
import 'package:taxi1/models/bus_stop.dart';
import 'package:taxi1/screens/preferences_screen.dart';
import 'package:taxi1/services/preferences_service.dart';
import 'package:taxi1/services/stop_history_service.dart';
import 'package:taxi1/theme/app_colors.dart';
import 'package:taxi1/theme/app_text_scaler.dart';
import 'package:taxi1/theme/app_theme.dart';
import 'package:taxi1/utils/distance_format.dart';
import 'package:taxi1/utils/tile_coords.dart';
import 'package:taxi1/widgets/option_card_picker.dart';

/// Envuelve un widget con lo mínimo que necesitan las pantallas: tema,
/// delegates de localización y, opcionalmente, un escalador de texto.
Widget _wrap(
  Widget child, {
  Brightness brightness = Brightness.light,
  double textScale = 1.0,
}) {
  return MaterialApp(
    theme: buildAppTheme(brightness: brightness),
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    builder: (context, inner) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(textScale)),
      child: inner!,
    ),
    home: child,
  );
}

/// Pantalla alta para los tests de Preferencias.
///
/// La pantalla es un `CustomScrollView` y los slivers montan sus hijos de forma
/// perezosa: en un viewport de 800px las últimas secciones no existen en el
/// árbol y `find.text` no las encuentra. Con un viewport alto se monta todo y
/// los tests pueden interactuar sin ir haciendo scroll a mano.
void _useTallScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(420, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await PreferencesService.instance.load();
    await StopHistoryService.instance.load();
  });

  group('buildAppTheme', () {
    test('produce Material 3 en ambos brillos con la extensión de estado', () {
      for (final brightness in Brightness.values) {
        final theme = buildAppTheme(brightness: brightness);
        expect(theme.useMaterial3, isTrue);
        expect(theme.brightness, brightness);
        expect(theme.colorScheme.brightness, brightness);
        expect(
          theme.extension<AppStatusColors>(),
          isNotNull,
          reason: 'la semaforización debe estar disponible en ambos temas',
        );
      }
    });

    test('el modo compacto no baja el alto de fila por debajo de 48dp', () {
      final compact = buildAppTheme(
        brightness: Brightness.light,
        compact: true,
      );
      expect(compact.listTileTheme.minTileHeight, greaterThanOrEqualTo(48));
    });

    test('define un textTheme (antes no existía)', () {
      final theme = buildAppTheme(brightness: Brightness.light);
      expect(theme.textTheme.bodyMedium?.fontSize, isNotNull);
      expect(theme.textTheme.titleMedium?.fontWeight, FontWeight.w600);
    });
  });

  group('AppTextScaler', () {
    test('compone la preferencia de la app con el ajuste del sistema', () {
      const system = TextScaler.linear(1.3);
      const scaler = AppTextScaler(system, 1.2);
      // 1.3 del SO x 1.2 de la app: se multiplican, no se pisan.
      expect(scaler.scale(10), closeTo(15.6, 0.001));
    });

    test('es transparente con factor 1.0', () {
      const scaler = AppTextScaler(TextScaler.noScaling, 1.0);
      expect(scaler.scale(14), 14);
    });
  });

  group('distancias', () {
    test('sin posición conocida el bucket es unknown, no "muy cerca"', () {
      expect(proximityOf(null), ProximityBucket.unknown);
      expect(proximityOf(double.nan), ProximityBucket.unknown);
    });

    test('clasifica por los umbrales de siempre', () {
      expect(proximityOf(100), ProximityBucket.veryClose);
      expect(proximityOf(900), ProximityBucket.close);
      expect(proximityOf(2000), ProximityBucket.medium);
      expect(proximityOf(9000), ProximityBucket.far);
    });
  });

  group('teselas y estilo de mapa', () {
    test('el origen cae en la esquina de las cuatro teselas de z=1', () {
      final tile = tileIndexFor(const LatLng(0, 0), 1);
      expect((tile.x, tile.y, tile.z), (1, 1, 1));
    });

    test('la tesela de Quilpué contiene efectivamente a Quilpué', () {
      const zoom = 14;
      final tile = tileIndexFor(kQuilpueCenter, zoom);
      final n = 1 << zoom;
      final lonLeft = tile.x / n * 360.0 - 180.0;
      final lonRight = (tile.x + 1) / n * 360.0 - 180.0;

      expect(kQuilpueCenter.longitude, greaterThanOrEqualTo(lonLeft));
      expect(kQuilpueCenter.longitude, lessThan(lonRight));
      expect(tile.y, inInclusiveRange(0, n - 1));
    });

    test('el basemap oscuro es un estilo distinto del claro', () {
      final light = mapTileUrlTemplate(MapStyle.normal, isDark: false);
      final dark = mapTileUrlTemplate(MapStyle.normal, isDark: true);
      expect(light, isNot(dark));
      expect(dark, contains('basic-v2-dark'));
    });

    test('el satelital no cambia con el tema (la foto aérea es la misma)', () {
      expect(
        mapTileUrlTemplate(MapStyle.satellite, isDark: false),
        mapTileUrlTemplate(MapStyle.satellite, isDark: true),
      );
    });

    test('pide teselas de 256 px con retina del servidor ({r})', () {
      // Sin `{r}` flutter_map simulaba el modo retina pidiendo cuatro teselas
      // por casilla: cuatro veces más cuota de MapTiler y texto diminuto.
      for (final style in MapStyle.values) {
        final url = mapTileUrlTemplate(style, isDark: false);
        expect(url, contains('/256/{z}/{x}/{y}{r}.'));
      }
      expect(
        fallbackTileUrlTemplate(MapStyle.normal, isDark: true),
        contains('{r}'),
      );
    });

    test('la miniatura usa el mismo estilo que el mapa real', () {
      // Si divergieran, la vista previa mentiría sobre lo que se va a ver.
      expect(
        mapTileThumbnailUrl(MapStyle.satellite, isDark: false),
        contains('hybrid'),
      );
    });
  });

  group('historial de paraderos', () {
    setUp(() async {
      await StopHistoryService.instance.clear();
      await PreferencesService.instance.setHistoryEnabled(true);
    });

    test('recuerda lo consultado, lo más reciente primero', () async {
      final history = StopHistoryService.instance;
      await history.record(quilpueBusStops[0]);
      await history.record(quilpueBusStops[1]);

      expect(history.recentStops.first.name, quilpueBusStops[1].name);
      expect(history.recentStops.length, 2);
    });

    test('no duplica: volver a consultar lo sube al principio', () async {
      final history = StopHistoryService.instance;
      await history.record(quilpueBusStops[0]);
      await history.record(quilpueBusStops[1]);
      await history.record(quilpueBusStops[0]);

      expect(history.recentStops.length, 2);
      expect(history.recentStops.first.name, quilpueBusStops[0].name);
    });

    test('respeta el tope de entradas', () async {
      final history = StopHistoryService.instance;
      for (final stop in quilpueBusStops) {
        await history.record(stop);
      }
      expect(
        history.recentStops.length,
        lessThanOrEqualTo(StopHistoryService.maxEntries),
      );
    });

    test('con la preferencia apagada no registra ni expone nada', () async {
      final history = StopHistoryService.instance;
      await history.record(quilpueBusStops[0]);
      expect(history.recentStops, isNotEmpty);

      // Apagar oculta el historial sin destruirlo...
      await PreferencesService.instance.setHistoryEnabled(false);
      expect(history.recentStops, isEmpty);
      await history.record(quilpueBusStops[3]);

      // ...y volver a encenderlo devuelve lo de antes, sin la consulta hecha
      // mientras estaba apagado.
      await PreferencesService.instance.setHistoryEnabled(true);
      expect(history.recentStops.length, 1);
      expect(history.recentStops.first.name, quilpueBusStops[0].name);
    });
  });

  group('localización', () {
    testWidgets('un locale no soportado cae a español en vez de reventar', (
      tester,
    ) async {
      // Antes `main.dart` declaraba supportedLocales [en, es] mientras el
      // delegate solo soporta es: en un teléfono en inglés
      // `AppLocalizations.of(context)!` devolvía null y la app crasheaba.
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => Text(AppLocalizations.of(context)!.navMap),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Mapa'), findsOneWidget);
    });
  });

  group('PreferencesScreen', () {
    testWidgets('sigue visible con las animaciones desactivadas', (
      tester,
    ) async {
      // Regresión: el AnimationController solo hacía forward() si las
      // animaciones estaban activadas, así que el FadeTransition se quedaba en
      // opacidad 0 y la pantalla entera desaparecía — incluido el interruptor
      // necesario para volver a activarlas.
      _useTallScreen(tester);
      await PreferencesService.instance.setAnimationsEnabled(false);
      await tester.pumpWidget(_wrap(const PreferencesScreen()));
      await tester.pumpAndSettle();

      final fade = tester.widget<FadeTransition>(
        find.byKey(preferencesFadeKey),
      );
      expect(fade.opacity.value, 1.0);
      expect(find.text('APARIENCIA'), findsOneWidget);

      await PreferencesService.instance.setAnimationsEnabled(true);
    });

    testWidgets('no desborda con la fuente al 140%', (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_wrap(const PreferencesScreen(), textScale: 1.4));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets('el tema se elige con un SegmentedButton de tres opciones', (
      tester,
    ) async {
      _useTallScreen(tester);
      final prefs = PreferencesService.instance;
      await prefs.setTheme('light');

      await tester.pumpWidget(_wrap(const PreferencesScreen()));
      await tester.pumpAndSettle();

      expect(find.byType(SegmentedButton<String>), findsOneWidget);

      await tester.ensureVisible(find.text('Oscuro'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Oscuro'));
      await tester.pumpAndSettle();
      expect(prefs.themeMode, ThemeMode.dark);

      await tester.tap(find.text('Auto'));
      await tester.pumpAndSettle();
      // `ThemeMode.system` era inalcanzable antes de este trabajo.
      expect(prefs.themeMode, ThemeMode.system);
    });

    testWidgets('el estilo de mapa se elige con tarjetas de vista previa', (
      tester,
    ) async {
      _useTallScreen(tester);
      final prefs = PreferencesService.instance;
      await prefs.setMapType('normal');

      await tester.pumpWidget(_wrap(const PreferencesScreen()));
      await tester.pumpAndSettle();

      expect(find.byType(OptionCardPicker<MapStyle>), findsOneWidget);

      await tester.ensureVisible(find.text('Satélite'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Satélite'));
      await tester.pumpAndSettle();
      expect(prefs.mapType, 'satellite');

      await prefs.setMapType('normal');
    });

    // El antiguo test "el rol se elige con tarjetas" desapareció con el
    // selector Pasajero/Chofer que probaba. Aquel selector era el bug: el rol
    // era una preferencia local que cualquiera cambiaba para empezar a
    // transmitir GPS. Ahora el rol es identidad y se prueba en el grupo
    // "roles y navegación", sin red.
    testWidgets('la sección de cuenta ofrece iniciar sesión al invitado', (
      tester,
    ) async {
      _useTallScreen(tester);

      await tester.pumpWidget(_wrap(const PreferencesScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Cuenta'.toUpperCase()), findsOneWidget);
      expect(find.text('Invitado'), findsOneWidget);
      expect(find.text('Iniciar sesión'), findsOneWidget);
    });

    testWidgets('la fila entera del switch es tappable, no solo el control', (
      tester,
    ) async {
      _useTallScreen(tester);
      final prefs = PreferencesService.instance;
      await prefs.setCompactMode(false);

      await tester.pumpWidget(_wrap(const PreferencesScreen()));
      await tester.pumpAndSettle();

      // Se toca la etiqueta, no el Switch: antes esto no hacía nada porque el
      // control estaba en una Row donde solo el Switch respondía.
      await tester.ensureVisible(find.text('Modo compacto'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Modo compacto'));
      await tester.pumpAndSettle();
      expect(prefs.compactMode, isTrue);

      await prefs.setCompactMode(false);
    });

    testWidgets('ya no ofrece interruptores sin nada detrás', (tester) async {
      _useTallScreen(tester);
      await tester.pumpWidget(_wrap(const PreferencesScreen()));
      await tester.pumpAndSettle();

      // "Habilitar notificaciones" se guardaba en disco sin que existiera
      // ningún módulo de notificaciones; se eliminó en vez de fingir.
      expect(find.text('Habilitar notificaciones'), findsNothing);
      expect(find.text('Próximamente'), findsNothing);
    });
  });
}
