import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:taxi1/config/garita_config.dart';
import 'package:taxi1/config/map_config.dart';
import 'package:taxi1/l10n/app_localizations.dart';
import 'package:taxi1/models/recorrido.dart';
import 'package:taxi1/screens/map_screen.dart';
import 'package:taxi1/services/location_service.dart';
import 'package:taxi1/services/preferences_service.dart';
import 'package:taxi1/services/puntos_de_sena.dart';
import 'package:taxi1/services/recorridos_service.dart';
import 'package:taxi1/services/route_service.dart';
import 'package:taxi1/theme/app_theme.dart';
import 'package:taxi1/utils/polyline.dart';
import 'package:taxi1/widgets/app_map.dart';

/// El mapa del pasajero sin recorridos encimados: un ícono fijo por variante,
/// y la variante dibujada entera al tocarlo.
void main() {
  final centro = kQuilpueCenter;

  Trayecto recto(double lon) {
    final puntos = [
      for (var i = 0; i <= 10; i++) LatLng(-33.040 - i * 0.005, lon),
    ];
    return Trayecto(
      puntos: [puntos.first, puntos.last],
      geometria: encodePolyline(puntos),
      trazado: puntos,
    );
  }

  Trayecto invertido(Trayecto t) => Trayecto(
    puntos: t.puntos.reversed.toList(),
    geometria: encodePolyline(t.trazado.reversed.toList()),
    trazado: t.trazado.reversed.toList(),
  );

  // Dos variantes de la Línea 10 cerca del centro de Quilpué. La T vuelve
  // por otra calle, cuatro cuadras más allá.
  final t = Recorrido(
    id: 't',
    garitaId: kGaritaPublica,
    nombre: 'Línea 10 T · Belloto 2000',
    colorValue: 0xFFB0338A,
    linea: 'Línea 10',
    codigoVariante: 'T',
    nombreVariante: 'Belloto 2000',
    ida: recto(centro.longitude + 0.001),
    vuelta: invertido(recto(centro.longitude + 0.005)),
    callesIda: const ['QUILPUÉ', 'SERRANO', 'ALTO EL YUGO'],
    callesVuelta: const ['ALTO EL YUGO', 'SERRANO', 'QUILPUÉ'],
  );
  final v1 = Recorrido(
    id: 'v1',
    garitaId: kGaritaPublica,
    nombre: 'Línea 10 V-1 · Troncos Viejos',
    colorValue: 0xFF00727C,
    linea: 'Línea 10',
    codigoVariante: 'V-1',
    nombreVariante: 'Troncos Viejos',
    ida: recto(centro.longitude + 0.002),
  );

  Widget app() => MaterialApp(
    theme: buildAppTheme(brightness: Brightness.light),
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: const MapScreen(),
  );

  AppMap mapa(WidgetTester tester) =>
      tester.widget<AppMap>(find.byType(AppMap));
  Iterable<MapMarker> iconosDeVariante(WidgetTester tester) =>
      mapa(tester).markers.where((m) => m.id.startsWith('variante_'));
  MapMarker marcador(WidgetTester tester, String id) =>
      mapa(tester).markers.firstWhere((m) => m.id == id);

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await PreferencesService.instance.load();
  });

  setUp(() {
    // Sin GPS: el foco es el centro de Quilpué, y no se pide ninguna ruta a
    // pie por la red.
    LocationService.instance.debugSetPosition(null);
    RecorridosService.instance.debugSetRecorridos([t, v1]);
  });

  tearDown(() {
    RecorridosService.instance.clearSelection();
    RecorridosService.instance.debugSetRecorridos(const []);
    RouteService.instance.clearDestination();
  });

  testWidgets('sin línea elegida: un ícono fijo por variante y ningún '
      'recorrido', (tester) async {
    await tester.pumpWidget(app());
    await tester.pump();

    expect(mapa(tester).lines, isEmpty);
    expect(iconosDeVariante(tester), hasLength(2));
    final lugares = PuntosDeSena.lugaresDeIconos([t, v1]);
    final iconoT = marcador(tester, 'variante_t');
    final iconoV1 = marcador(tester, 'variante_v1');
    expect((iconoT.icon as HailBadge).label, '10 T');
    expect((iconoV1.icon as HailBadge).label, '10 V-1');
    expect(iconoT.point, lugares['t']);
    expect(iconoV1.point, lugares['v1']);
    // Muy alejado el mapa, el que se tapa con otro se esconde.
    expect(iconoT.collides, isTrue);
    // Ya no hay aviso de que ninguna pasa cerca.
    expect(find.text('Ninguna línea pasa cerca'), findsNothing);
  });

  testWidgets('los íconos no se mueven con el pasajero', (tester) async {
    await tester.pumpWidget(app());
    await tester.pump();
    Map<String, LatLng> lugares() => {
      for (final m in iconosDeVariante(tester)) m.id: m.point,
    };
    final antes = lugares();

    // En Valparaíso, a unos 15 km de la Línea 10.
    LocationService.instance.debugSetPosition(const LatLng(-33.0458, -71.6197));
    await tester.pump();
    expect(lugares(), antes);
    LocationService.instance.debugSetPosition(
      LatLng(centro.latitude - 0.01, centro.longitude),
    );
    await tester.pump();
    expect(lugares(), antes);
    expect(find.text('Ninguna línea pasa cerca'), findsNothing);
  });

  testWidgets('elegida desde lejos, no propone caminar 15 km: dice a cuánto '
      'pasa', (tester) async {
    LocationService.instance.debugSetPosition(const LatLng(-33.0458, -71.6197));
    await tester.pumpWidget(app());
    await tester.pump();

    RecorridosService.instance.select(t);
    await tester.pump();
    expect(mapa(tester).lines, isNotEmpty);
    expect(RouteService.instance.destination, isNull);
    expect(find.textContaining('km de ti'), findsOneWidget);
  });

  testWidgets('al tocarlo se dibuja la variante, con un punto de seña por '
      'sentido; las demás siguen a la vista para cambiar', (tester) async {
    await tester.pumpWidget(app());
    await tester.pump();
    final lugarV1 = marcador(tester, 'variante_v1').point;

    marcador(tester, 'variante_t').onTap!();
    await tester.pump();

    expect(RecorridosService.instance.selected?.id, 't');
    expect(mapa(tester).lines, isNotEmpty);
    final ids = mapa(tester).markers.map((m) => m.id);
    expect(ids, containsAll(['sena_ida', 'sena_vuelta']));
    // La elegida ya no tiene su ícono de variante; la otra sigue, donde
    // estaba.
    expect(ids, isNot(contains('variante_t')));
    expect(marcador(tester, 'variante_v1').point, lugarV1);
    HailBadge icono(String id) => marcador(tester, id).icon as HailBadge;
    // El sentido más cercano (la ida) dice hacia dónde va; el otro va
    // compacto, para que no se tapen.
    expect(icono('sena_ida').detail, 'Hacia Alto el Yugo');
    expect(icono('sena_vuelta').detail, isEmpty);
    expect(find.textContaining('Hazle seña aquí'), findsOneWidget);
    // Sin GPS no hay desde dónde caminar.
    expect(RouteService.instance.destination, isNull);

    // El otro sentido se elige desde la tarjeta.
    await tester.tap(find.byTooltip('Tomarlo en el otro sentido'));
    await tester.pump();
    expect(icono('sena_vuelta').detail, 'Hacia el centro');
    expect(icono('sena_ida').detail, isEmpty);

    // Tocar la otra variante la elige en su lugar.
    marcador(tester, 'variante_v1').onTap!();
    await tester.pump();
    expect(RecorridosService.instance.selected?.id, 'v1');
    expect(
      mapa(tester).markers.map((m) => m.id),
      containsAll(['sena_ida', 'variante_t']),
    );

    // La X vuelve al mapa limpio.
    await tester.tap(find.byTooltip('Quitar recorrido'));
    await tester.pump();
    expect(RecorridosService.instance.selected, isNull);
    expect(RouteService.instance.destination, isNull);
    expect(mapa(tester).lines, isEmpty);
    expect(iconosDeVariante(tester), hasLength(2));
  });
}
