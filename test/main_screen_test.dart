import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:taxi1/l10n/app_localizations.dart';
import 'package:taxi1/screens/main_screen.dart';
import 'package:taxi1/screens/map_screen.dart';
import 'package:taxi1/services/preferences_service.dart';
import 'package:taxi1/theme/app_theme.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await PreferencesService.instance.load();
  });

  testWidgets('girar el teléfono traslada las pestañas en vez de recrearlas', (
    tester,
  ) async {
    // Al girar, las pestañas pasan de ser el `body` a ir al lado del riel de
    // navegación. Recrearlas destruía el mapa justo cuando el motor tenía en
    // cola el aviso del cambio de tamaño, y la app se cerraba.
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(412, 915);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(brightness: Brightness.light),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: const MainScreen(),
      ),
    );
    await tester.pump();
    expect(find.byType(NavigationBar), findsOneWidget);
    final mapa = tester.state(find.byType(MapScreen));

    tester.view.physicalSize = const Size(915, 412);
    await tester.pump();
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(tester.state(find.byType(MapScreen)), same(mapa));

    tester.view.physicalSize = const Size(412, 915);
    await tester.pump();
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(tester.state(find.byType(MapScreen)), same(mapa));
  });
}
