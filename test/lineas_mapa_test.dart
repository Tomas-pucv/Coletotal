import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:taxi1/config/garita_config.dart';
import 'package:taxi1/models/recorrido.dart';
import 'package:taxi1/theme/app_colors.dart';
import 'package:taxi1/utils/polyline.dart';
import 'package:taxi1/widgets/app_map.dart';
import 'package:taxi1/widgets/recorrido_lines.dart';

/// Las líneas a la vista en el mapa del pasajero: sus dos sentidos lado a
/// lado, insignias, flechas y cuánto resalta cada una.
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

    test('los dos sentidos van lado a lado, cada uno por su carril', () {
      final lineas = recorridoLines(uno, status, badge: true, arrows: true);
      expect(lineas, hasLength(2));
      // El regreso primero: en un cruce, la ida queda encima.
      final [regreso, ida] = lineas;
      expect(regreso.points.first, uno.vuelta!.trazado.first);
      expect(ida.points.first, uno.ida.trazado.first);
      for (final l in lineas) {
        expect(l.lane, isTrue);
        // Las flechas se corren medio carril: tienen que medir lo mismo.
        expect(l.width, MapLine.laneWidth);
        expect(l.borderWidth, MapLine.laneBorder);
        expect(l.color.a, 1);
        expect(l.arrows, isTrue);
        expect(l.shadow, isTrue);
        expect(l.dotted, isFalse);
      }
      // La insignia en una sola: en las dos se repetiría el doble.
      expect(ida.badge?.text, '1');
      expect(regreso.badge, isNull);
    });

    test('el sentido destacado va entero y encima; el otro, tenue y sin '
        'flechas', () {
      final lineas = recorridoLines(
        uno,
        status,
        destacado: Sentido.vuelta,
        badge: true,
        arrows: true,
      );
      final [ida, regreso] = lineas;
      expect(ida.points.first, uno.ida.trazado.first);
      expect(ida.color.a, lessThan(1));
      expect(ida.borderColor.a, 0);
      expect(ida.arrows, isFalse);
      expect(ida.shadow, isFalse);
      expect(ida.badge, isNull);
      expect(regreso.color.a, 1);
      expect(regreso.arrows, isTrue);
      expect(regreso.badge?.text, '1');
      // Las dos siguen en su carril y miden lo mismo: quedan pegadas una a
      // la otra.
      expect(lineas.every((l) => l.lane), isTrue);
      expect(ida.width, regreso.width);
      expect(ida.borderWidth, regreso.borderWidth);
    });

    test('con un sentido, sólo ése y por el medio de la calle, aunque sea el '
        'regreso', () {
      final lineas = recorridoLines(uno, status, sentido: Sentido.vuelta);
      expect(lineas, hasLength(1));
      expect(lineas.single.points.first, uno.vuelta!.trazado.first);
      expect(lineas.single.lane, isFalse);
      expect(lineas.single.color.a, 1);
    });

    test('una línea sin regreso va sola, por el medio de la calle', () {
      final lineas = recorridoLines(linea('2', conVuelta: false), status);
      expect(lineas, hasLength(1));
      expect(lineas.single.lane, isFalse);
    });

    test('en un viaje, el tramo que se recorre va entero sobre el resto del '
        'sentido, tenue', () {
      // La ida mide unos 5,56 km: de los 1.000 a los 3.000 m.
      final lineas = recorridoLines(
        uno,
        status,
        sentido: Sentido.ida,
        tramo: (desde: 1000, hasta: 3000),
        badge: true,
        arrows: true,
      );
      expect(lineas, hasLength(2));
      final [resto, viaje] = lineas;
      expect(resto.points, uno.ida.trazado);
      expect(resto.color.a, lessThan(1));
      expect(resto.arrows, isFalse);
      expect(resto.badge, isNull);
      expect(viaje.color.a, 1);
      expect(viaje.arrows, isTrue);
      expect(viaje.badge?.text, '1');
      expect(viaje.width, greaterThan(resto.width));
      expect(polylineLength(viaje.points), closeTo(2000, 5));
      // Empieza en la subida, no en el vértice anterior del trazado.
      expect(
        nearestOnPolyline(uno.ida.trazado, viaje.points.first)!.desdeInicio,
        closeTo(1000, 5),
      );
    });

    test('un tramo sin largo no deja la línea sin dibujar', () {
      final lineas = recorridoLines(
        uno,
        status,
        sentido: Sentido.ida,
        tramo: (desde: 2000, hasta: 2000),
      );
      expect(lineas, hasLength(1));
      expect(lineas.single.points, uno.ida.trazado);
    });

    test('el contorno es claro también en el tema oscuro', () {
      // Los colores de las líneas son oscuros: con el contorno oscuro del
      // tema oscuro se perdían contra el mapa oscuro y el satélite.
      for (final tema in [AppStatusColors.light, AppStatusColors.dark]) {
        final ida = recorridoLines(uno, tema).last;
        expect(ida.borderColor.computeLuminance(), greaterThan(0.9));
      }
    });

    test('tocar la línea o su insignia avisa', () {
      var tocada = 0;
      for (final l in recorridoLines(uno, status, onTap: () => tocada++)) {
        l.onTap!();
      }
      expect(tocada, 2);
    });
  });

  test('sin pedirlas, la línea va sin insignias ni flechas', () {
    final lineas = recorridoLines(linea('1'), AppStatusColors.light);
    expect(lineas, hasLength(2));
    expect(lineas.every((l) => l.badge == null && !l.arrows), isTrue);
  });

  group('subLinea', () {
    final trazado = recto(-33.040, -33.090).trazado;

    test('corta entre dos distancias, sin pasarse de los extremos', () {
      final entera = subLinea(trazado, -50, 99999);
      expect(entera.first, trazado.first);
      expect(entera.last, trazado.last);
      expect(polylineLength(entera), closeTo(polylineLength(trazado), 1e-6));
    });

    test('sin nada entre medio, vacía', () {
      expect(subLinea(trazado, 3000, 1000), isEmpty);
      expect(subLinea(trazado, 99999, 100000), isEmpty);
      expect(subLinea(const [], 0, 100), isEmpty);
    });
  });
}
