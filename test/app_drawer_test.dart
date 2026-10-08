import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:taxi1/l10n/app_localizations.dart';
import 'package:taxi1/models/app_user.dart';
import 'package:taxi1/services/auth_service.dart';
import 'package:taxi1/services/preferences_service.dart';
import 'package:taxi1/theme/app_theme.dart';
import 'package:taxi1/utils/patente.dart';
import 'package:taxi1/widgets/app_drawer.dart';

Future<void> _abrirMenu(WidgetTester tester, AppUser? perfil) async {
  tester.view.physicalSize = const Size(412, 915);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  AuthService.instance.debugSetProfile(perfil);
  addTearDown(() => AuthService.instance.debugSetProfile(null));

  final llave = GlobalKey<ScaffoldState>();
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
      home: Scaffold(key: llave, drawer: const AppDrawer()),
    ),
  );
  llave.currentState!.openDrawer();
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await PreferencesService.instance.load();
  });

  testWidgets('el invitado ve entrar y crear cuenta una sola vez, a lo ancho', (
    tester,
  ) async {
    await _abrirMenu(tester, null);

    // Antes "Iniciar sesión" estaba en la cabecera y otra vez al final.
    expect(find.text('Iniciar sesión'), findsOneWidget);
    expect(find.text('Crear cuenta'), findsOneWidget);

    final entrar = find.widgetWithText(FilledButton, 'Iniciar sesión');
    final crear = find.widgetWithText(OutlinedButton, 'Crear cuenta');
    // Uno debajo del otro y a lo ancho de la tarjeta: lado a lado, cada texto
    // se partía en dos líneas. (El alto no se compara: la fuente de los tests
    // es más ancha que Roboto y parte el texto igual.)
    expect(tester.getSize(entrar).width, tester.getSize(crear).width);
    expect(
      tester.getTopLeft(crear).dy,
      greaterThan(tester.getTopLeft(entrar).dy),
    );
    expect(
      tester.getSize(entrar).width,
      greaterThan(tester.getSize(find.byType(NavigationDrawer)).width * 0.75),
    );
  });

  testWidgets('el chofer ve su patente como placa y puede cerrar sesión', (
    tester,
  ) async {
    await _abrirMenu(
      tester,
      const AppUser(
        uid: 'u1',
        rol: UserRole.colectivero,
        nombre: 'Juan Pérez',
        garitaId: 'g1',
        patente: 'ABCD12',
      ),
    );

    expect(find.text('Juan Pérez'), findsOneWidget);
    expect(find.text('Colectivero'), findsOneWidget);
    final placa = find.text(formatPatente('ABCD12'));
    expect(placa, findsOneWidget);
    // Blanca como la placa de verdad, con borde.
    final caja = tester.widget<Container>(
      find.ancestor(of: placa, matching: find.byType(Container)).first,
    );
    final decoracion = caja.decoration! as BoxDecoration;
    expect(decoracion.color, Colors.white);
    expect(decoracion.border, isNotNull);

    expect(find.text('Cerrar sesión'), findsOneWidget);
    expect(find.text('Iniciar sesión'), findsNothing);
  });
}
