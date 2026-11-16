import 'package:flutter_test/flutter_test.dart';

import 'package:taxi1/models/colectivo_activo.dart';
import 'package:taxi1/services/firebase_telemetria_service.dart';

void main() {
  final ahora = DateTime(2026, 10, 5, 12);

  ColectivoActivo conEdad(Duration edad, {bool conectado = true}) =>
      ColectivoActivo(
        uid: 'u-${edad.inSeconds}',
        idVehiculo: 'BBCC12',
        latitud: -33.0,
        longitud: -71.0,
        conectado: conectado,
        ts: ahora.subtract(edad).millisecondsSinceEpoch,
      );

  group('parseSnapshot', () {
    test('un nodo ilegible no tumba a los demás', () {
      final parsed = FirebaseTelemetriaService.parseSnapshot({
        'u1': {
          'uid': 'u1',
          'idVehiculo': 'BBCC12',
          'latitud': -33.0,
          'longitud': -71.0,
          'estado': 'lleno',
          'ts': 1,
        },
        // Lo que dejaba un `onDisconnect` sobre un nodo ya borrado.
        'u2': {'conectado': false, 'ts': 2},
        'u3': 'basura',
      });
      expect(parsed.map((c) => c.uid), ['u1']);
    });

    test('sin datos devuelve una lista vacía', () {
      expect(FirebaseTelemetriaService.parseSnapshot(null), isEmpty);
    });
  });

  group('antigüedad', () {
    test('las unidades viejas se descartan según la hora del servidor', () {
      final vigentes = FirebaseTelemetriaService.vigentes([
        conEdad(const Duration(seconds: 10)),
        conEdad(const Duration(minutes: 5)),
      ], ahora);
      expect(vigentes.map((c) => c.uid), ['u-10']);
    });

    test('un teléfono con el reloj adelantado sigue viendo la flota', () {
      // Comparar contra el reloj local hacía que un teléfono tres minutos
      // adelantado no viera ningún colectivo. Con la hora del servidor (el
      // reloj local corregido por `.info/serverTimeOffset`) sí los ve.
      final colectivo = conEdad(const Duration(seconds: 20));
      final relojLocalAdelantado = ahora.add(const Duration(minutes: 4));
      expect(colectivo.isStale(relojLocalAdelantado), isTrue);
      expect(colectivo.isStale(ahora), isFalse);
    });

    test('sin señal reciente se ve atenuado antes de desaparecer', () {
      expect(conEdad(const Duration(seconds: 10)).seemsOffline(ahora), isFalse);
      expect(conEdad(const Duration(seconds: 60)).seemsOffline(ahora), isTrue);
      expect(
        conEdad(
          const Duration(seconds: 5),
          conectado: false,
        ).seemsOffline(ahora),
        isTrue,
        reason: 'el servidor ya detectó la desconexión',
      );
    });
  });

  group('ColectivoActivo', () {
    test('se puede quitar el recorrido asignado', () {
      const conLinea = ColectivoActivo(
        uid: 'u1',
        idVehiculo: 'BBCC12',
        latitud: -33.0,
        longitud: -71.0,
        recorridoId: 'r1',
        recorridoNombre: 'Línea 1',
      );
      final sinLinea = conLinea.copyWith(clearRecorrido: true);
      expect(sinLinea.recorridoId, isNull);
      expect(sinLinea.toJson().containsKey('recorridoId'), isFalse);
    });

    test('un nodo sin "conectado" cuenta como conectado', () {
      final viejo = ColectivoActivo.fromJson({
        'uid': 'u1',
        'latitud': -33.0,
        'longitud': -71.0,
      });
      expect(viejo.conectado, isTrue);
    });
  });
}
