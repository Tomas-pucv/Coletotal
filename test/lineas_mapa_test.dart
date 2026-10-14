import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:taxi1/config/garita_config.dart';
import 'package:taxi1/models/recorrido.dart';
import 'package:taxi1/theme/app_colors.dart';
import 'package:taxi1/utils/polyline.dart';
import 'package:taxi1/widgets/app_map.dart';
import 'package:taxi1/widgets/recorrido_lines.dart';

/// Las líneas a la vista en el mapa del pasajero: insignias, flechas y cuánto
/// resalta cada una.
void main() {
  const lng = -71.4425;

  Trayecto recto(double desde, double hasta) {
    final puntos = [
      for (var i = 0; i <= 10; i++)
        LatLng(desde + (hasta - desde) * i / 10, lng),
    ];
    return Trayecto(
      puntos: [puntos.first, puntos.last],
      geometria: encodePolyline(puntos),
      trazado: puntos,
    );
  }

  Recorrido linea(String id, {String? nombre, bool conVuelta = true}) =>
      Recorrido(
        id: id,
        garitaId: kGaritaPublica,
        nombre: nombre ?? 'Línea $id',
        colorValue: kRecorridoColors.first,
        ida: recto(-33.040, -33.090),
        vuelta: conVuelta ? recto(-33.090, -33.040) : null,
      );

  group('Recorrido.sigla', () {
    String sigla(String nombre) => linea('x', nombre: nombre).sigla;

    test('toma la primera palabra con un número', () {
      expect(sigla('PRUEBA 1: Centro – El Belloto'), '1');
      expect(sigla('Línea 12a Centro'), '12A');
      expect(sigla('105'), '105');
      expect(sigla('Variante 2B – Pompeya'), '2B');
    });

    test('corta a cuatro caracteres', () {
      expect(sigla('Recorrido 123456'), '1234');
    });

    test('sin números, las iniciales sin artículos', () {
      expect(sigla('El Belloto – Centro'), 'BC');
      expect(sigla('Hospital de Quilpué'), 'HQ');
      expect(sigla('Ñuñoa'), 'Ñ');
    });
  });

  group('puntosCada', () {
    // 0,01° de latitud ≈ 1112 m, hacia el sur.
    final alSur = [const LatLng(-33.04, lng), const LatLng(-33.05, lng)];

    test('reparte puntos a la distancia pedida, desde el inicio', () {
      final puntos = puntosCada(alSur, 100, desde: 50);
      expect(puntos, hasLength(11));
      expect(
        polylineLength([alSur.first, puntos.first.punto]),
        closeTo(50, 0.5),
      );
      expect(
        polylineLength([puntos[0].punto, puntos[1].punto]),
        closeTo(100, 0.5),
      );
    });

    test('el rumbo es el del tramo, en grados desde el norte', () {
      expect(puntosCada(alSur, 300).first.rumbo, closeTo(180, 0.01));
      final alEste = [const LatLng(-33.04, lng), const LatLng(-33.04, -71.43)];
      expect(puntosCada(alEste, 300).first.rumbo, closeTo(90, 0.01));
      final alNoroeste = [
        const LatLng(-33.04, lng),
        LatLng(-33.03, lng - 0.01 / 0.8387),
      ];
      expect(puntosCada(alNoroeste, 300).first.rumbo, closeTo(315, 0.5));
    });

    test('sigue la línea por sus quiebres', () {
      final enL = [
        const LatLng(-33.04, lng),
        const LatLng(-33.041, lng), // 111 m al sur
        const LatLng(-33.041, -71.4415), // y 93 m al este
      ];
      final puntos = puntosCada(enL, 50);
      // A 0, 50 y 100 m, hacia el sur; a 150 y 200 m, ya hacia el este.
      expect(puntos.map((p) => p.rumbo.round()), [180, 180, 180, 90, 90]);
    });

    test('sin puntos si la línea o el paso no sirven', () {
      expect(puntosCada(alSur, 0), isEmpty);
      expect(puntosCada(alSur, double.nan), isEmpty);
      expect(puntosCada([alSur.first], 10), isEmpty);
      expect(puntosCada([alSur.first, alSur.first], 10), isEmpty);
    });
  });

  test('metersPerPixel: en el zoom 15 de Quilpué, unos 2 m por píxel', () {
    expect(metersPerPixel(-33.05, 15), closeTo(2.0, 0.05));
    expect(
      metersPerPixel(-33.05, 14) / metersPerPixel(-33.05, 15),
      closeTo(2, 1e-9),
    );
  });

  group('lineasDelMapa', () {
    const status = AppStatusColors.light;
    final uno = linea('1');
    final dos = linea('2', conVuelta: false);

    test('sin elegida: todas semitransparentes, con insignia y flechas', () {
      final lineas = lineasDelMapa([uno, dos], status, onTap: (_) {});
      expect(lineas, hasLength(3)); // ida y vuelta de la 1, ida de la 2
      for (final l in lineas) {
        expect(l.color.a, lessThan(0.6));
        expect(l.borderWidth, 0);
        expect(l.badge?.text, isNotNull);
        expect(l.arrows, isTrue);
      }
    });

    test('con una elegida, va al final, resalta y sólo ella lleva flechas', () {
      final lineas = lineasDelMapa(
        [uno, dos],
        status,
        elegida: uno,
        onTap: (_) {},
      );
      expect(lineas, hasLength(3));
      final elegida = lineas.last;
      expect(elegida.badge?.text, '1');
      expect(elegida.color.a, closeTo(0.85, 0.01));
      expect(elegida.arrows, isTrue);
      final otra = lineas.first;
      expect(otra.badge?.text, '2');
      expect(otra.color.a, lessThan(0.3));
      expect(otra.badgeOpacity, lessThan(1));
      expect(otra.arrows, isFalse);
    });

    test('con un sentido, de la elegida sólo ése', () {
      final lineas = lineasDelMapa(
        [uno, dos],
        status,
        elegida: uno,
        sentido: Sentido.vuelta,
        onTap: (_) {},
      );
      expect(lineas, hasLength(2));
      expect(lineas.last.points.first, uno.vuelta!.trazado.first);
    });

    test('tocar una línea o su insignia avisa cuál es', () {
      final tocadas = <String>[];
      final lineas = lineasDelMapa(
        [uno, dos],
        status,
        elegida: dos,
        onTap: (r) => tocadas.add(r.id),
      );
      for (final l in lineas) {
        l.onTap!();
      }
      expect(tocadas, ['1', '1', '2']);
    });
  });

  test('la consola de flota sigue viendo la línea sola, sin insignias', () {
    final lineas = recorridoLines(linea('1'), AppStatusColors.light);
    expect(lineas, hasLength(2));
    expect(lineas.every((l) => l.badge == null && !l.arrows), isTrue);
  });
}
