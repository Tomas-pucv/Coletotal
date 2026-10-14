import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:taxi1/models/app_user.dart';
import 'package:taxi1/models/colectivo_activo.dart';
import 'package:taxi1/models/recorrido.dart';
import 'package:taxi1/services/session_log_service.dart';
import 'package:taxi1/screens/admin/recorridos_admin_screen.dart';
import 'package:taxi1/utils/polyline.dart';

/// Contrato entre lo que escribe el cliente y lo que aceptan las reglas.
///
/// Las reglas viven en archivos aparte y nada avisaba cuando el cliente
/// empezaba a escribir un campo nuevo. Así pasó con `conectado`,
/// `recorridoId` y `recorridoNombre`: `database.rules.json` rechaza todo hijo
/// desconocido, así que el `onDisconnect` fallaba y el botón de turno quedaba
/// girando. Estos tests leen las reglas reales del repositorio.
void main() {
  group('database.rules.json', () {
    late Set<String> permitidas;

    setUpAll(() {
      final rules =
          jsonDecode(File('database.rules.json').readAsStringSync())
              as Map<String, dynamic>;
      final nodo =
          ((rules['rules'] as Map)['colectivos_activos'] as Map)[r'$uid']
              as Map<String, dynamic>;
      permitidas = nodo.keys
          .where((k) => !k.startsWith('.') && !k.startsWith(r'$'))
          .toSet();
    });

    test('acepta cada campo que publica la telemetría', () {
      const completo = ColectivoActivo(
        uid: 'u1',
        idVehiculo: 'BBCC12',
        latitud: -33.0,
        longitud: -71.0,
        garitaId: 'g1',
        estado: EstadoCapacidad.lleno,
        recorridoId: 'r1',
        recorridoNombre: 'Línea 1',
      );
      // `ts` lo agrega el servicio con ServerValue.timestamp.
      expect(permitidas, containsAll({...completo.toJson().keys, 'ts'}));
    });

    test('acepta lo que escribe el aviso de desconexión', () {
      expect(permitidas, containsAll(['conectado', 'ts']));
    });
  });

  group('firestore.rules', () {
    late String rules;

    setUpAll(() => rules = File('firestore.rules').readAsStringSync());

    test('el perfil que se crea al registrarse cabe en hasOnly', () {
      final lista = RegExp(
        r'keys\(\)\.hasOnly\(\s*\[([^\]]*)\]',
      ).firstMatch(rules)!.group(1)!;
      final permitidas = RegExp(
        r"'([^']+)'",
      ).allMatches(lista).map((m) => m.group(1)!).toSet();

      const perfil = AppUser(
        uid: 'u1',
        rol: UserRole.colectivero,
        nombre: 'Ana',
        garitaId: 'g1',
        patente: 'BBCC12',
        email: 'ana@example.com',
      );
      expect(permitidas, containsAll(perfil.toCreateMap(codigo: 'X').keys));
    });

    test('el tope de eventos del cliente cabe en el de las reglas', () {
      final limite = int.parse(
        RegExp(r'eventos\.size\(\) <= (\d+)').firstMatch(rules)!.group(1)!,
      );
      // + SHIFT_START y SHIFT_END, que no cuentan para el tope.
      expect(SessionLogService.maxEventos + 2, lessThanOrEqualTo(limite));
    });

    test('una línea con ida y vuelta tiene la forma que piden las reglas', () {
      const puntos = [LatLng(-33.04, -71.44), LatLng(-33.05, -71.44)];
      final trayecto = Trayecto(
        puntos: puntos,
        geometria: encodePolyline(puntos),
        trazado: puntos,
      );
      final data = Recorrido(
        id: 'r1',
        garitaId: 'g1',
        nombre: 'Línea 1',
        colorValue: kRecorridoColors.first,
        ida: trayecto,
        vuelta: trayecto,
      ).toMap();

      // recorridoValido(): nombre, color entero, activo, ida y vuelta.
      expect(data['nombre'], isA<String>());
      expect(data['color'], isA<int>());
      expect(data['activo'], isA<bool>());
      for (final sentido in ['ida', 'vuelta']) {
        expect(rules, contains('trayectoValido(d.$sentido)'));
        final t = data[sentido] as Map<String, dynamic>;
        // trayectoValido(): puntos (lista) y geometria (texto).
        expect(t.keys, containsAll(['puntos', 'geometria']));
        expect(t['puntos'], isA<List<Object?>>());
        expect(t['geometria'], isA<String>());
      }
      // Los paraderos ya no existen: nada en las reglas los abre.
      expect(rules, isNot(contains('match /paraderos')));
      expect(data.containsKey('paraderoIds'), isFalse);
    });

    test('el tope de puntos del editor cabe en el de las reglas', () {
      final limite = int.parse(
        RegExp(r'puntos\.size\(\) <= (\d+)').firstMatch(rules)!.group(1)!,
      );
      expect(RecorridoEditorScreen.maxPuntos, lessThanOrEqualTo(limite));
    });
  });
}
