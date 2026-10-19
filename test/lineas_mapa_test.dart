import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:taxi1/config/garita_config.dart';
import 'package:taxi1/models/recorrido.dart';
import 'package:taxi1/theme/app_colors.dart';
import 'package:taxi1/utils/polyline.dart';
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

  group('recorridoLines', () {
    const status = AppStatusColors.light;
    final uno = linea('1');

    test('los dos sentidos: regreso a trazos debajo, ida continua encima', () {
      final lineas = recorridoLines(uno, status, badge: true, arrows: true);
      expect(lineas, hasLength(2));
      final [regreso, ida] = lineas;
      expect(regreso.points.first, uno.vuelta!.trazado.first);
      expect(regreso.dashed, isTrue);
      expect(regreso.borderWidth, 0);
      expect(ida.dashed, isFalse);
      expect(ida.borderWidth, greaterThan(0));
      expect(ida.width, greaterThan(regreso.width));
      for (final l in lineas) {
        expect(l.color.a, 1);
        expect(l.badge?.text, '1');
        expect(l.arrows, isTrue);
      }
    });

    test('con un sentido, sólo ése y continuo, aunque sea el regreso', () {
      final lineas = recorridoLines(uno, status, sentido: Sentido.vuelta);
      expect(lineas, hasLength(1));
      expect(lineas.single.points.first, uno.vuelta!.trazado.first);
      expect(lineas.single.dashed, isFalse);
    });

    test('tocar la línea o su insignia avisa', () {
      var tocada = 0;
      for (final l in recorridoLines(uno, status, onTap: () => tocada++)) {
        l.onTap!();
      }
      expect(tocada, 2);
    });
  });

  test('la consola de flota sigue viendo la línea sola, sin insignias', () {
    final lineas = recorridoLines(linea('1'), AppStatusColors.light);
    expect(lineas, hasLength(2));
    expect(lineas.every((l) => l.badge == null && !l.arrows), isTrue);
    expect(lineas.map((l) => l.dashed), [true, false]); // regreso, ida
  });
}
