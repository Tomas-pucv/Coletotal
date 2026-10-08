import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:taxi1/config/map_config.dart';
import 'package:taxi1/widgets/app_map.dart';

void main() {
  group('MarkerIcon', () {
    MarkerIcon paradero({Color color = Colors.green}) => MarkerIcon.circle(
      diameter: 28,
      color: color,
      borderColor: Colors.white,
      borderWidth: 2,
      glyph: Icons.directions_bus,
      glyphColor: Colors.white,
      glyphSize: 16,
      shadow: const BoxShadow(
        color: Color(0x40000000),
        blurRadius: 4,
        offset: Offset(0, 2),
      ),
      tapTarget: 48,
    );

    test('dos marcadores iguales comparten la imagen', () {
      // Cada imagen distinta es una llamada al mapa nativo: los paraderos del
      // mismo color tienen que reusar la suya.
      expect(paradero().key, paradero().key);
      expect(paradero().key, isNot(paradero(color: Colors.red).key));
    });

    test('el área táctil no se achica por dibujar dentro del mapa', () {
      // MapLibre detecta el toque sobre la imagen entera: el paradero de 28 px
      // conserva los 48 px de área táctil que tenía como widget.
      expect(paradero().extent, 48);
      // Y la sombra no queda cortada: un colectivo de 40 px con sombra de 6
      // necesita más que sus 40.
      final colectivo = MarkerIcon.circle(
        diameter: 40,
        color: Colors.green,
        borderColor: Colors.white,
        borderWidth: 2,
        shadow: const BoxShadow(blurRadius: 6, offset: Offset(0, 2)),
      );
      expect(colectivo.extent, greaterThan(40));
    });

    testWidgets('se dibuja a la densidad de la pantalla', (tester) async {
      await tester.runAsync(() async {
        final png = await paradero().toPng(3);
        final codec = await ui.instantiateImageCodec(png);
        final imagen = (await codec.getNextFrame()).image;
        expect((imagen.width, imagen.height), (144, 144));
        imagen.dispose();
      });
    });
  });

  test('la ruta a pie va punteada, con puntos del ancho de la línea', () {
    const linea = MapLine(
      points: [kQuilpueCenter, kQuilpueCenter],
      color: Color(0xFF4A3F9E),
      width: 5,
      borderColor: Colors.white,
      borderWidth: 1.5,
      dotted: true,
    );
    // Un círculo de 5 px con su borde de 1,5 px a cada lado.
    expect(linea.dotIcon.diameter, 8);
    expect(linea.dotIcon.borderColor, Colors.white);
    // Por omisión, continua: así van las líneas de los colectivos.
    expect(
      const MapLine(
        points: [kQuilpueCenter],
        color: Colors.red,
        width: 6,
      ).dotted,
      isFalse,
    );
  });

  test('el halo del GPS mide en metros lo que mide en el mapa', () {
    // En el zoom 0 de MapLibre el ecuador mide 512 px: un píxel son
    // 40.075 km / 512 ≈ 78,3 km. A 60° de latitud Mercator lo estira al doble.
    expect(circleRadiusAtZoom0(78271.517, 0), closeTo(1, 1e-6));
    expect(circleRadiusAtZoom0(39135.758, 60), closeTo(1, 1e-6));
    // 100 m en Quilpué con el mapa en z15 (una cuadra en pantalla).
    final pixeles = circleRadiusAtZoom0(100, kQuilpueCenter.latitude) * 32768;
    expect(pixeles, inInclusiveRange(45, 55));
  });

  testWidgets('sin MapLibre (escritorio, tests) queda el fondo y el crédito', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: AppMap(initialCenter: kQuilpueCenter)),
    );
    expect(AppMap.supported, isFalse);
    expect(find.text('© OpenStreetMap'), findsOneWidget);
  });
}
