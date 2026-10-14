import 'package:flutter_test/flutter_test.dart';

import 'package:taxi1/services/firebase_telemetria_service.dart';
import 'package:taxi1/services/location_service.dart';
import 'package:taxi1/utils/navegacion.dart';

/// La navegación del chofer: el zoom según la velocidad, el rumbo de la flecha
/// y el ritmo con que se publica su posición.
void main() {
  group('zoomParaVelocidad', () {
    final [cerca, medio, lejos] = kZoomsNavegacion;

    test('más rápido, más lejos', () {
      expect(zoomParaVelocidad(10, cerca), cerca);
      expect(zoomParaVelocidad(35, cerca), medio);
      expect(zoomParaVelocidad(70, cerca), lejos);
      expect(zoomParaVelocidad(5, lejos), cerca);
    });

    test('cerca del borde entre tramos no salta ida y vuelta', () {
      // De 18 a 23 km/h no se cambia: hay que pasar los 25 para alejar…
      expect(zoomParaVelocidad(23, cerca), cerca);
      expect(zoomParaVelocidad(26, cerca), medio);
      // …y bajar de 15 para volver a acercar.
      expect(zoomParaVelocidad(17, medio), medio);
      expect(zoomParaVelocidad(14, medio), cerca);
      expect(zoomParaVelocidad(48, medio), medio);
      expect(zoomParaVelocidad(51, medio), lejos);
      expect(zoomParaVelocidad(42, lejos), lejos);
      expect(zoomParaVelocidad(39, lejos), medio);
    });

    test('sin velocidad, se queda donde está', () {
      expect(zoomParaVelocidad(null, medio), medio);
      expect(zoomParaVelocidad(double.nan, lejos), lejos);
      expect(zoomParaVelocidad(-1, cerca), cerca);
    });

    test('un zoom que no es de ningún tramo se ajusta al más parecido', () {
      expect(zoomParaVelocidad(null, 16.9), cerca);
      expect(zoomParaVelocidad(30, 16.2), medio);
    });
  });

  group('rumboConfiable', () {
    test('en movimiento, el rumbo del GPS', () {
      expect(rumboConfiable(speed: 8, heading: 92, headingAccuracy: 10), 92);
      expect(rumboConfiable(speed: 8, heading: 360, headingAccuracy: 10), 0);
    });

    test('detenido, conserva el anterior en vez de apuntar al norte', () {
      expect(
        rumboConfiable(
          speed: 0.4,
          heading: 0,
          headingAccuracy: 0,
          anterior: 135,
        ),
        135,
      );
      expect(rumboConfiable(speed: 0, heading: 0, headingAccuracy: 0), isNull);
    });

    test('un rumbo impreciso o inválido no se usa', () {
      expect(
        rumboConfiable(
          speed: 8,
          heading: 200,
          headingAccuracy: 90,
          anterior: 10,
        ),
        10,
      );
      expect(
        rumboConfiable(
          speed: 8,
          heading: double.nan,
          headingAccuracy: 5,
          anterior: 10,
        ),
        10,
      );
      expect(
        rumboConfiable(
          speed: double.nan,
          heading: 50,
          headingAccuracy: 5,
          anterior: 10,
        ),
        10,
      );
    });

    test('precisión no informada (Android viejo) cuenta como buena', () {
      expect(rumboConfiable(speed: 5, heading: 45, headingAccuracy: 0), 45);
    });
  });

  group('ritmo de publicación de la posición', () {
    final t0 = DateTime(2026, 10, 10, 12);
    Duration espera(DateTime? ultima, DateTime ahora) =>
        FirebaseTelemetriaService.esperaParaPublicar(ultima, ahora);

    test('la primera sale de inmediato', () {
      expect(espera(null, t0), Duration.zero);
    });

    test('una cada tres segundos aunque el GPS dé una por segundo', () {
      expect(
        espera(t0, t0.add(const Duration(seconds: 1))),
        const Duration(seconds: 2),
      );
      expect(
        espera(t0, t0.add(const Duration(milliseconds: 2500))),
        const Duration(milliseconds: 500),
      );
      expect(espera(t0, t0.add(const Duration(seconds: 3))), Duration.zero);
      expect(espera(t0, t0.add(const Duration(seconds: 9))), Duration.zero);
    });
  });
}
