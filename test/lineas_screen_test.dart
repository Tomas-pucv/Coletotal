import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:taxi1/config/garita_config.dart';
import 'package:taxi1/l10n/app_localizations.dart';
import 'package:taxi1/models/recorrido.dart';
import 'package:taxi1/screens/admin/recorridos_admin_screen.dart';
import 'package:taxi1/screens/lineas_screen.dart';
import 'package:taxi1/services/location_service.dart';
import 'package:taxi1/services/preferences_service.dart';
import 'package:taxi1/services/recorridos_service.dart';
import 'package:taxi1/theme/app_theme.dart';
import 'package:taxi1/utils/polyline.dart';

/// Una línea recta por el meridiano [lon], de norte a sur.
Recorrido _linea(
  String nombre, {
  required double lon,
  bool activo = true,
  String garitaId = kGaritaPublica,
  bool conVuelta = true,
}) {
  final puntos = [
    for (var i = 0; i <= 10; i++) LatLng(-33.040 - i * 0.005, lon),
  ];
  final ida = Trayecto(
    puntos: [puntos.first, puntos.last],
    geometria: encodePolyline(puntos),
    trazado: puntos,
  );
  final vuelta = Trayecto(
    puntos: [puntos.last, puntos.first],
    geometria: encodePolyline(puntos.reversed.toList()),
    trazado: puntos.reversed.toList(),
  );
  return Recorrido(
    id: nombre,
    garitaId: garitaId,
    nombre: nombre,
    colorValue: kRecorridoColors.first,
    ida: ida,
    vuelta: conVuelta ? vuelta : null,
    activo: activo,
  );
}

Widget _app() => MaterialApp(
  theme: buildAppTheme(brightness: Brightness.light),
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  home: const LineasScreen(),
);

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await PreferencesService.instance.load();
  });

  tearDown(() {
    RecorridosService.instance.debugSetRecorridos(const []);
    LocationService.instance.debugSetPosition(null);
  });

  testWidgets('muestra sólo las líneas activas de la garita, la más cercana '
      'primero', (tester) async {
    RecorridosService.instance.debugSetRecorridos([
      _linea('Lejana', lon: -71.4600),
      _linea('Cercana', lon: -71.4430, conVuelta: false),
      _linea('Apagada', lon: -71.4425, activo: false),
      _linea('De otra garita', lon: -71.4425, garitaId: 'otra'),
    ]);
    LocationService.instance.debugSetPosition(const LatLng(-33.047, -71.4425));

    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    expect(find.text('Apagada'), findsNothing);
    expect(find.text('De otra garita'), findsNothing);
    final cercana = tester.getTopLeft(find.text('Cercana')).dy;
    final lejana = tester.getTopLeft(find.text('Lejana')).dy;
    expect(cercana, lessThan(lejana));
    // A cuánto pasa, y que la cercana sólo tiene ida.
    expect(find.textContaining('Pasa a 47 m de ti'), findsOneWidget);
    expect(find.textContaining('Sólo ida'), findsOneWidget);
  });

  testWidgets('la búsqueda filtra por nombre, sin tildes', (tester) async {
    RecorridosService.instance.debugSetRecorridos([
      _linea('Línea Belloto', lon: -71.4430),
      _linea('Línea Valencia', lon: -71.4600),
    ]);

    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'linea vale');
    await tester.pumpAndSettle();

    expect(find.text('Línea Valencia'), findsOneWidget);
    expect(find.text('Línea Belloto'), findsNothing);
  });

  testWidgets('sin líneas publicadas lo dice, en vez de una lista vacía', (
    tester,
  ) async {
    RecorridosService.instance.debugSetRecorridos(const []);
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    expect(
      find.text('La garita todavía no ha publicado sus líneas.'),
      findsOneWidget,
    );
  });

  test('la vuelta parte de la ida, al revés', () {
    const ida = [
      LatLng(-33.04, -71.44),
      LatLng(-33.05, -71.44),
      LatLng(-33.05, -71.45),
    ];
    final vuelta = RecorridoEditorScreen.vueltaDesdeIda(ida);
    expect(vuelta, ida.reversed.toList());
    // Es una lista nueva y editable: corregirla no toca la ida.
    vuelta.removeLast();
    expect(ida, hasLength(3));
  });
}
