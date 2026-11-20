import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:taxi1/config/garita_config.dart';
import 'package:taxi1/l10n/app_localizations.dart';
import 'package:taxi1/models/app_user.dart';
import 'package:taxi1/models/colectivo_activo.dart';
import 'package:taxi1/models/recorrido.dart';
import 'package:taxi1/screens/driver/turno_screen.dart';
import 'package:taxi1/services/auth_service.dart';
import 'package:taxi1/services/firebase_telemetria_service.dart';
import 'package:taxi1/services/location_service.dart';
import 'package:taxi1/services/preferences_service.dart';
import 'package:taxi1/services/recorridos_service.dart';
import 'package:taxi1/services/turno_service.dart';
import 'package:taxi1/theme/app_colors.dart';
import 'package:taxi1/theme/app_theme.dart';
import 'package:taxi1/utils/polyline.dart';
import 'package:taxi1/widgets/app_map.dart';

const _chofer = AppUser(
  uid: 'yo',
  rol: UserRole.colectivero,
  nombre: 'Juan Pérez',
  garitaId: kGaritaPublica,
  patente: 'ABCD12',
);

Recorrido _linea() {
  final puntos = [
    for (var i = 0; i <= 10; i++) LatLng(-33.040 - i * 0.005, -71.4425),
  ];
  return Recorrido(
    id: 'l1',
    garitaId: kGaritaPublica,
    nombre: 'Línea 1',
    colorValue: kRecorridoColors.first,
    ida: Trayecto(
      puntos: [puntos.first, puntos.last],
      geometria: encodePolyline(puntos),
      trazado: puntos,
    ),
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
  home: const TurnoScreen(),
);

AppMap _mapa(WidgetTester tester) => tester.widget<AppMap>(find.byType(AppMap));

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await PreferencesService.instance.load();
  });

  setUp(() {
    AuthService.instance.debugSetProfile(_chofer);
    RecorridosService.instance.debugSetRecorridos([_linea()]);
    LocationService.instance.debugSetPosition(
      const LatLng(-33.047, -71.4425),
      speed: 0,
      heading: 90,
    );
  });

  tearDown(() {
    TurnoService.instance.debugSetEnTurno(false);
    AuthService.instance.debugSetProfile(null);
    RecorridosService.instance.debugSetRecorridos(const []);
    RecorridosService.instance.clearSelection();
    FirebaseTelemetriaService.instance.debugSetColectivos(const []);
    LocationService.instance.debugSetPosition(null);
  });

  testWidgets('fuera de turno: el mapa sigue al chofer y abajo está "Iniciar '
      'turno"', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pump();

    expect(find.text('Fuera de servicio'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Iniciar turno'), findsOneWidget);
    expect(find.text('Sin recorrido asignado'), findsOneWidget);
    expect(find.byTooltip('Terminar turno'), findsNothing);
    expect(find.text('Medio lleno'), findsNothing);
    // Fuera de turno el mapa ya es plano: no hay botón 2D/3D.
    expect(find.text('2D'), findsNothing);
    // El aviso de lo que se comparte no ocupa el panel: está en la (i).
    expect(find.textContaining('Ley 19.628'), findsNothing);
    await tester.tap(find.byTooltip('Tu ubicación durante el turno'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Ley 19.628'), findsOneWidget);

    final nav = _mapa(tester).navigation!;
    expect(nav.follow, MapFollow.position);
    expect(nav.fix?.point, const LatLng(-33.047, -71.4425));
    expect(nav.fix?.heading, 90);
  });

  testWidgets('en turno: navegación inclinada, recorrido visible y '
      '"Terminar turno"', (tester) async {
    TurnoService.instance.debugSetEnTurno(true);
    await tester.pumpWidget(_app());
    await tester.pump();

    expect(find.text('En servicio'), findsOneWidget);
    for (final texto in ['Disponible', 'Medio lleno', 'Lleno']) {
      expect(find.text(texto), findsNothing);
    }
    expect(find.text('Sin recorrido asignado'), findsOneWidget);
    expect(find.byTooltip('Terminar turno'), findsOneWidget);
    expect(find.text('Iniciar turno'), findsNothing);
    // Arriba sólo "En servicio": la hora del último envío ya no se muestra.
    expect(find.textContaining('Última posición'), findsNothing);

    final nav = _mapa(tester).navigation!;
    expect(nav.follow, MapFollow.navigation);
    // La flecha queda abajo: hay margen arriba y el panel debajo.
    expect(nav.insets.top, greaterThan(0));
    expect(nav.insets.bottom, greaterThan(0));
  });

  testWidgets('en turno, 2D aplana el mapa con el norte arriba y 3D vuelve '
      'a la navegación', (tester) async {
    TurnoService.instance.debugSetEnTurno(true);
    await tester.pumpWidget(_app());
    await tester.pump();
    expect(_mapa(tester).navigation!.follow, MapFollow.navigation);

    await tester.tap(find.text('2D'));
    await tester.pump();
    expect(_mapa(tester).navigation!.follow, MapFollow.position);

    // Con la cámara suelta, cambiar de vista también vuelve a la flecha.
    _mapa(tester).onUserGesture!();
    await tester.pump();
    await tester.tap(find.text('3D'));
    await tester.pump();
    expect(_mapa(tester).navigation!.follow, MapFollow.navigation);
    expect(find.text('Volver a centrar'), findsNothing);
  });

  testWidgets('terminar turno pide confirmación antes de salir', (
    tester,
  ) async {
    TurnoService.instance.debugSetEnTurno(true);
    await tester.pumpWidget(_app());
    await tester.pump();

    // Un toque en el botón de terminar no termina: pregunta primero.
    await tester.tap(find.byTooltip('Terminar turno'));
    await tester.pumpAndSettle();
    expect(find.text('¿Terminar el turno?'), findsOneWidget);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(TurnoService.instance.enTurno, isTrue);
  });

  testWidgets('un gesto suelta la cámara y "Volver a centrar" la retoma', (
    tester,
  ) async {
    TurnoService.instance.debugSetEnTurno(true);
    await tester.pumpWidget(_app());
    await tester.pump();
    expect(find.text('Volver a centrar'), findsNothing);

    _mapa(tester).onUserGesture!();
    await tester.pump();
    expect(_mapa(tester).navigation!.follow, MapFollow.none);

    await tester.tap(find.text('Volver a centrar'));
    await tester.pump();
    expect(_mapa(tester).navigation!.follow, MapFollow.navigation);
    expect(find.text('Volver a centrar'), findsNothing);
  });

  testWidgets('se ven los demás colectivos, pero no el propio: el chofer es '
      'la flecha', (tester) async {
    FirebaseTelemetriaService.instance.debugSetColectivos(const [
      ColectivoActivo(
        uid: 'yo',
        idVehiculo: 'ABCD12',
        latitud: -33.047,
        longitud: -71.4425,
      ),
      ColectivoActivo(
        uid: 'otro',
        idVehiculo: 'EFGH34',
        latitud: -33.050,
        longitud: -71.4425,
      ),
    ]);
    await tester.pumpWidget(_app());
    await tester.pump();

    final ids = _mapa(tester).vehicles.map((v) => v.id);
    expect(ids, contains('colectivo_otro'));
    expect(ids, isNot(contains('colectivo_yo')));
    // Son autos, no marcadores: giran con su rumbo y se deslizan.
    expect(_mapa(tester).markers, isEmpty);
  });

  testWidgets('el chofer ve sólo su línea: sin línea, nada dibujado; la '
      'elegida en Líneas, sola y con su tarjeta para volver', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pump();
    expect(_mapa(tester).lines, isEmpty);
    expect(find.text('Recorrido de Línea 1'), findsNothing);

    RecorridosService.instance.select(_linea());
    await tester.pump();
    expect(_mapa(tester).lines, isNotEmpty);
    expect(_mapa(tester).lines.every((l) => l.arrows), isTrue);
    expect(find.text('Recorrido de Línea 1'), findsOneWidget);

    await tester.tap(find.byTooltip('Quitar recorrido'));
    await tester.pump();
    expect(RecorridosService.instance.selected, isNull);
    expect(_mapa(tester).lines, isEmpty);
  });

  testWidgets('los demás colectivos llevan la etiqueta de su línea', (
    tester,
  ) async {
    FirebaseTelemetriaService.instance.debugSetColectivos(const [
      ColectivoActivo(
        uid: 'con-linea',
        idVehiculo: 'EFGH34',
        latitud: -33.050,
        longitud: -71.4425,
        recorridoId: 'l1',
      ),
      ColectivoActivo(
        uid: 'sin-linea',
        idVehiculo: 'IJKL56',
        latitud: -33.052,
        longitud: -71.4425,
      ),
    ]);
    await tester.pumpWidget(_app());
    await tester.pump();

    final etiquetas = {for (final v in _mapa(tester).vehicles) v.id: v.tag};
    expect(etiquetas['colectivo_con-linea']?.text, '1');
    expect(etiquetas.containsKey('colectivo_sin-linea'), isTrue);
    expect(etiquetas['colectivo_sin-linea'], isNull);
  });

  testWidgets('un colectivo apunta hacia donde va; detenido en su línea, como '
      'ella', (tester) async {
    FirebaseTelemetriaService.instance.debugSetColectivos(const [
      // Ya se movió: se sabe hacia dónde va.
      ColectivoActivo(
        uid: 'andando',
        idVehiculo: 'EFGH34',
        latitud: -33.050,
        longitud: -71.4425,
        recorridoId: 'l1',
        rumbo: 270,
      ),
      // Detenido sobre la Línea 1, que baja hacia el sur.
      ColectivoActivo(
        uid: 'detenido',
        idVehiculo: 'IJKL56',
        latitud: -33.060,
        longitud: -71.4425,
        recorridoId: 'l1',
      ),
      // Detenido lejos de su línea, o sin línea: no hay de dónde sacarlo.
      ColectivoActivo(
        uid: 'lejos',
        idVehiculo: 'MNOP78',
        latitud: -33.060,
        longitud: -71.4300,
        recorridoId: 'l1',
      ),
      ColectivoActivo(
        uid: 'sin-linea',
        idVehiculo: 'QRST90',
        latitud: -33.052,
        longitud: -71.4425,
      ),
    ]);
    await tester.pumpWidget(_app());
    await tester.pump();

    final rumbos = {for (final v in _mapa(tester).vehicles) v.id: v.heading};
    expect(rumbos['colectivo_andando'], 270);
    expect(rumbos['colectivo_detenido'], closeTo(180, 1e-6));
    expect(rumbos['colectivo_lejos'], 0);
    expect(rumbos['colectivo_sin-linea'], 0);
  });

  testWidgets('el anillo del auto es del color de su línea; sin línea, el '
      'verde de "en servicio"', (tester) async {
    FirebaseTelemetriaService.instance.debugSetColectivos(const [
      ColectivoActivo(
        uid: 'con-linea',
        idVehiculo: 'EFGH34',
        latitud: -33.050,
        longitud: -71.4425,
        recorridoId: 'l1',
      ),
      ColectivoActivo(
        uid: 'sin-linea',
        idVehiculo: 'IJKL56',
        latitud: -33.052,
        longitud: -71.4425,
      ),
    ]);
    await tester.pumpWidget(_app());
    await tester.pump();

    final autos = {for (final v in _mapa(tester).vehicles) v.id: v.icon};
    expect(
      autos['colectivo_con-linea']!.ringColor,
      Color(kRecorridoColors.first),
    );
    expect(
      autos['colectivo_sin-linea']!.ringColor,
      AppStatusColors.light.disponible,
    );
    // El disco es blanco en cualquier tema: los colores de las líneas son
    // oscuros y sobre un disco oscuro no se distinguían.
    expect(autos.values.every((a) => a.borderColor == Colors.white), isTrue);
  });

  testWidgets('sin perfil de chofer, el mensaje de siempre y sin mapa', (
    tester,
  ) async {
    AuthService.instance.debugSetProfile(null);
    await tester.pumpWidget(_app());
    await tester.pump();

    expect(
      find.text('Esta sección es para los conductores de la garita.'),
      findsOneWidget,
    );
    expect(find.byType(AppMap), findsNothing);
  });
}
