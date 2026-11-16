import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:taxi1/config/map_config.dart';
import 'package:taxi1/l10n/app_localizations.dart';
import 'package:taxi1/screens/main_screen.dart';
import 'package:taxi1/services/preferences_service.dart';
import 'package:taxi1/theme/app_theme.dart';
import 'package:taxi1/widgets/map_compass_button.dart';
import 'package:taxi1/widgets/map_search_bar.dart';
import 'package:taxi1/widgets/map_style_sheet.dart';
import 'package:taxi1/widgets/option_card_picker.dart';

Widget _app(Widget home) => MaterialApp(
  theme: buildAppTheme(brightness: Brightness.light),
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  home: home,
);

void main() {
  group('Brújula', () {
    late ValueNotifier<double> rumbo;
    late int toques;

    Future<void> montar(WidgetTester tester) async {
      toques = 0;
      await tester.pumpWidget(
        _app(
          Scaffold(
            body: Center(
              child: MapCompassButton(
                bearing: rumbo,
                tooltip: 'Orientar al norte',
                onPressed: () => toques++,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    double opacidad(WidgetTester tester) =>
        tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity;

    setUp(() => rumbo = ValueNotifier(0));
    tearDown(() => rumbo.dispose());

    testWidgets('con el mapa al norte no se ve ni se puede tocar', (
      tester,
    ) async {
      await montar(tester);
      expect(opacidad(tester), 0);
      await tester.tap(find.byType(FloatingActionButton), warnIfMissed: false);
      expect(toques, 0);
      // Tampoco la anuncia el lector de pantalla.
      expect(find.bySemanticsLabel('Orientar al norte'), findsNothing);
    });

    testWidgets('al girar el mapa aparece y la aguja apunta al norte', (
      tester,
    ) async {
      await montar(tester);
      rumbo.value = 90;
      await tester.pumpAndSettle();

      expect(opacidad(tester), 1);
      // El mapa mira al este: el norte queda a la izquierda (-90°).
      final giro = tester.widget<Transform>(
        find.descendant(
          of: find.byType(FloatingActionButton),
          matching: find.byType(Transform),
        ),
      );
      expect(giro.transform.getRotation().entry(0, 1), closeTo(1, 1e-9));

      await tester.tap(find.byType(FloatingActionButton));
      expect(toques, 1);
    });

    test('los restos de décimas de grado cuentan como norte', () {
      // MapLibre no siempre vuelve exactamente a cero.
      expect(MapCompassButton.facesNorth(0.2), isTrue);
      expect(MapCompassButton.facesNorth(359.8), isTrue);
      expect(MapCompassButton.facesNorth(-0.3), isTrue);
      expect(MapCompassButton.facesNorth(3), isFalse);
      expect(MapCompassButton.facesNorth(180), isFalse);
    });
  });

  group('Menú', () {
    testWidgets('el botón del menú va dentro del buscador, en vez de la lupa', (
      tester,
    ) async {
      var abierto = 0;
      Widget barra({String? destino}) => _app(
        Scaffold(
          body: MapSearchBar(
            leading: IconButton(
              icon: const Icon(Icons.menu),
              tooltip: 'Abrir menú',
              onPressed: () => abierto++,
            ),
            destinationLabel: destino,
            onSelected: (_) {},
          ),
        ),
      );

      await tester.pumpWidget(barra());
      final menu = find.byIcon(Icons.menu);
      expect(
        find.ancestor(of: menu, matching: find.byType(MapSearchBar)),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.search), findsNothing);
      await tester.tap(menu);
      expect(abierto, 1);

      // Con un destino fijado, la bandera sigue diciendo hacia dónde se va.
      await tester.pumpWidget(barra(destino: 'Plaza Vieja'));
      expect(find.byIcon(Icons.menu), findsOneWidget);
      expect(find.byIcon(Icons.flag), findsOneWidget);
    });

    testWidgets('deslizar desde el borde abre el menú, fuera de la zona de '
        '"atrás" de Android', (tester) async {
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1;
      // Navegación por gestos: los primeros 30 dp del borde son del sistema.
      tester.view.systemGestureInsets = const FakeViewPadding(left: 30);
      addTearDown(tester.view.reset);

      late double ancho;
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (context) {
              ancho = MainScreen.drawerSwipeWidth(context);
              return Scaffold(
                drawer: const Drawer(child: Text('menú')),
                drawerEdgeDragWidth: ancho,
                body: const SizedBox.expand(),
              );
            },
          ),
        ),
      );
      expect(ancho, 30 + MainScreen.drawerSwipeStrip);

      // El valor por omisión del Scaffold (20 dp) quedaría entero dentro de
      // la zona del sistema; la franja empieza donde termina esa zona.
      await tester.dragFrom(const Offset(40, 400), const Offset(250, 0));
      await tester.pumpAndSettle();
      expect(find.text('menú'), findsOneWidget);
    });

    testWidgets('sin navegación por gestos la franja es la mínima', (
      tester,
    ) async {
      late double ancho;
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (context) {
              ancho = MainScreen.drawerSwipeWidth(context);
              return const SizedBox();
            },
          ),
        ),
      );
      expect(ancho, MainScreen.drawerSwipeStrip);
    });
  });

  testWidgets('calles o satélite se eligen en la hoja de capas del mapa', (
    tester,
  ) async {
    // Es el único lugar donde se elige: Preferencias ya no lo repite.
    SharedPreferences.setMockInitialValues({});
    final prefs = PreferencesService.instance;
    await prefs.load();
    await prefs.setMapType('normal');
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _app(
        Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => showMapStyleSheet(context),
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();

    // Las dos miniaturas grandes, una al lado de la otra, para compararlas.
    expect(find.byType(OptionCardPicker<MapStyle>), findsOneWidget);
    expect(
      tester.getSize(find.byType(AspectRatio).first).width,
      greaterThan(412 * 0.35),
    );
    expect(find.text('Más ajustes'), findsOneWidget);

    await tester.tap(find.text('Satélite'));
    await tester.pumpAndSettle();
    expect(prefs.mapType, 'satellite');
    await prefs.setMapType('normal');
  });
}
