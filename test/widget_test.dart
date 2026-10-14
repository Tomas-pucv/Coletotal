import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:taxi1/config/map_config.dart';
import 'package:taxi1/l10n/app_localizations.dart';
import 'package:taxi1/models/app_user.dart';
import 'package:taxi1/screens/preferences_screen.dart';
import 'package:taxi1/services/auth_service.dart';
import 'package:taxi1/services/preferences_service.dart';
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

    test('paleta negro y amarillo de colectivo, sobre grises sin tinte', () {
      final claro = buildAppTheme(brightness: Brightness.light).colorScheme;
      final oscuro = buildAppTheme(brightness: Brightness.dark).colorScheme;
      // De día lo principal es negro y lo seleccionado, amarillo.
      expect(claro.primary, kColeTotalInk);
      expect(claro.secondaryContainer, kColeTotalYellow);
      // De noche el amarillo pasa a ser el color principal.
      expect(oscuro.primary, const Color(0xFFFFD54A));
      // Los fondos son grises: antes la semilla naranja los teñía de durazno.
      for (final s in [claro, oscuro]) {
        for (final fondo in [s.surface, s.surfaceContainer, s.mapControl]) {
          expect(fondo.r, fondo.g, reason: '$fondo tiene tinte');
          expect(fondo.g, fondo.b, reason: '$fondo tiene tinte');
        }
      }
    });

    test(
      'los controles del mapa son blancos de día y gris elevado de noche',
      () {
        final claro = buildAppTheme(brightness: Brightness.light);
        final oscuro = buildAppTheme(brightness: Brightness.dark);
        expect(claro.colorScheme.mapControl, Colors.white);
        expect(
          oscuro.colorScheme.mapControl,
          oscuro.colorScheme.surfaceContainerHigh,
        );
        for (final theme in [claro, oscuro]) {
          expect(
            theme.floatingActionButtonTheme.backgroundColor,
            theme.colorScheme.mapControl,
          );
        }
      },
    );

    test('todo texto sobre su fondo cumple contraste AA (4,5:1)', () {
      double contraste(Color a, Color b) {
        final (x, y) = (a.computeLuminance(), b.computeLuminance());
        return (math.max(x, y) + 0.05) / (math.min(x, y) + 0.05);
      }

      for (final brightness in Brightness.values) {
        final s = buildAppTheme(brightness: brightness).colorScheme;
        final pares = {
          'botón principal': (s.onPrimary, s.primary),
          'recentrar siguiendo': (s.onPrimaryContainer, s.primaryContainer),
          'pestaña seleccionada': (
            s.onSecondaryContainer,
            s.secondaryContainer,
          ),
          'aviso': (s.onTertiaryContainer, s.tertiaryContainer),
          'texto': (s.onSurface, s.surface),
          'texto sobre el mapa': (s.onSurface, s.mapControl),
          'título de sección': (s.primary, s.surface),
          'chip de tiempo': (s.tertiary, s.mapControl),
        };
        pares.forEach((nombre, par) {
          expect(
            contraste(par.$1, par.$2),
            greaterThanOrEqualTo(4.5),
            reason: '$nombre en tema $brightness',
          );
        });
      }
    });

    test('"medio lleno" no se confunde con el amarillo del tema oscuro', () {
      final amarillo = buildAppTheme(brightness: Brightness.dark).colorScheme;
      final tono = HSVColor.fromColor(AppStatusColors.dark.medioLleno).hue;
      expect(
        (HSVColor.fromColor(amarillo.primary).hue - tono).abs(),
        greaterThan(15),
      );
    });

    test('la barra de navegación del sistema sigue a la de pestañas', () {
      for (final brightness in Brightness.values) {
        final theme = buildAppTheme(brightness: brightness);
        final barra = theme.appBarTheme.systemOverlayStyle!;
        // Hasta Android 14 se pinta de este color; tiene que ser el de la
        // barra de pestañas que queda justo encima.
        expect(
          barra.systemNavigationBarColor,
          theme.navigationBarTheme.backgroundColor,
        );
        expect(
          barra.systemNavigationBarDividerColor,
          barra.systemNavigationBarColor,
        );
        // Desde Android 15, sin esto la barra de tres botones lleva un velo
        // translúcido encima y queda de otro tono que las pestañas.
        expect(barra.systemNavigationBarContrastEnforced, isFalse);
        expect(
          barra.systemNavigationBarIconBrightness,
          brightness == Brightness.dark ? Brightness.light : Brightness.dark,
        );
      }
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

    test('la foto aérea de Esri va en orden {z}/{y}/{x} y sin clave', () {
      // Esri invierte el orden habitual: con {x}/{y} pedía otra tesela.
      expect(kSatelliteTileUrlTemplate, contains('/tile/{z}/{y}/{x}'));
      expect(kSatelliteTileUrlTemplate, isNot(contains('key=')));
    });

    test('la miniatura satelital es la tesela de Quilpué del mapa real', () {
      // Si divergieran, la vista previa mentiría sobre lo que se va a ver.
      final tile = tileIndexFor(kQuilpueCenter, 14);
      expect(
        satelliteThumbnailUrl(),
        kSatelliteTileUrlTemplate
            .replaceFirst('{z}', '14')
            .replaceFirst('{y}', '${tile.y}')
            .replaceFirst('{x}', '${tile.x}'),
      );
    });

    test(
      'el detalle de la región cae dentro de Chile y contiene a Quilpué',
      () {
        expect(kChileBounds.containsBounds(kDetailBounds), isTrue);
        expect(kDetailBounds.contains(kQuilpueCenter), isTrue);
        expect(kMinZoom, lessThan(kInitialZoom));
        expect(kMaxZoom, greaterThan(kInitialZoom));
      },
    );
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

    testWidgets('el estilo de mapa no está en Preferencias', (tester) async {
      // Se elige en la hoja de capas, sobre el propio mapa
      // (test/map_controls_test.dart). Acá estaba repetido.
      _useTallScreen(tester);
      await tester.pumpWidget(_wrap(const PreferencesScreen()));
      await tester.pumpAndSettle();

      expect(find.byType(OptionCardPicker<MapStyle>), findsNothing);
      expect(find.text('Satélite'), findsNothing);
    });

    // El antiguo test "el rol se elige con tarjetas" desapareció con el
    // selector Pasajero/Chofer que probaba. Aquel selector era el bug: el rol
    // era una preferencia local que cualquiera cambiaba para empezar a
    // transmitir GPS. Ahora el rol es identidad y se prueba en el grupo
    // "roles y navegación", sin red.
    testWidgets(
      'la cuenta del invitado es una fila: nombre y botón para entrar',
      (tester) async {
        _useTallScreen(tester);

        await tester.pumpWidget(_wrap(const PreferencesScreen()));
        await tester.pumpAndSettle();

        expect(find.text('Cuenta'.toUpperCase()), findsOneWidget);
        expect(find.text('Invitado'), findsOneWidget);
        // "Invitado" ya lo dice: el texto de abajo sobraba.
        expect(find.text('Estás usando ColeTotal sin cuenta'), findsNothing);
        final entrar = find.widgetWithText(FilledButton, 'Iniciar sesión');
        expect(entrar, findsOneWidget);
        // En la misma fila que el nombre, a su derecha.
        final nombre = find.text('Invitado');
        expect(
          tester.getCenter(entrar).dy,
          closeTo(tester.getCenter(nombre).dy, 4),
        );
        expect(
          tester.getCenter(entrar).dx,
          greaterThan(tester.getCenter(nombre).dx),
        );
      },
    );

    testWidgets('con letra grande el botón de la cuenta pasa abajo', (
      tester,
    ) async {
      // Al lado del nombre no cabría y el nombre quedaría en "I…".
      _useTallScreen(tester);

      await tester.pumpWidget(_wrap(const PreferencesScreen(), textScale: 1.4));
      await tester.pumpAndSettle();

      expect(
        tester
            .getTopLeft(find.widgetWithText(FilledButton, 'Iniciar sesión'))
            .dy,
        greaterThan(tester.getBottomLeft(find.text('Invitado')).dy),
      );
    });

    testWidgets('con sesión, la fila muestra el rol y el botón para salir', (
      tester,
    ) async {
      _useTallScreen(tester);
      AuthService.instance.debugSetProfile(
        const AppUser(
          uid: 'u1',
          rol: UserRole.colectivero,
          nombre: 'Juan Pérez',
          garitaId: 'g1',
          patente: 'ABCD12',
        ),
      );
      addTearDown(() => AuthService.instance.debugSetProfile(null));

      await tester.pumpWidget(_wrap(const PreferencesScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Juan Pérez'), findsOneWidget);
      expect(find.text('Colectivero'), findsOneWidget);
      expect(find.text('Iniciar sesión'), findsNothing);
      final salir = find.widgetWithText(OutlinedButton, 'Salir');
      expect(salir, findsOneWidget);

      // Salir sigue pidiendo confirmación antes de cerrar la sesión.
      await tester.tap(salir);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Cerrar sesión'),
        ),
        findsWidgets,
      );
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
