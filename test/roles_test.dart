import 'package:flutter_test/flutter_test.dart';

import 'package:taxi1/models/app_user.dart';
import 'package:taxi1/models/colectivo_activo.dart';
import 'package:taxi1/navigation/app_destination.dart';
import 'package:taxi1/screens/main_screen.dart';
import 'package:taxi1/utils/patente.dart';

/// Tests de los roles de usuario y de todo lo que cuelga de ellos.
///
/// Ninguno toca Firebase: el rol, la patente, los destinos y el payload de
/// telemetría viven en modelos y funciones puras justamente para poder
/// verificarlos sin red. Es lo que reemplaza al viejo test del selector
/// "Pasajero / Chofer" de Preferencias, que probaba precisamente el diseño que
/// este cambio vino a eliminar.
void main() {
  group('destinos por rol', () {
    test('cada rol tiene exactamente tres pestañas', () {
      // El `IndexedStack` de MainScreen es esta misma lista, así que si un rol
      // tuviera otra cantidad el índice podría quedar fuera de rango.
      for (final role in UserRole.values) {
        expect(
          Destinations.barFor(role),
          hasLength(3),
          reason: 'la barra del rol ${role.wireName} no tiene tres destinos',
        );
      }
    });

    test('el invitado conserva la navegación previa a los roles', () {
      expect(Destinations.barFor(UserRole.invitado), [
        AppDestination.mapa,
        AppDestination.rutas,
        AppDestination.preferencias,
      ]);
    });

    test('cada rol con cuenta gana su destino propio', () {
      expect(
        Destinations.barFor(UserRole.colectivero),
        contains(AppDestination.turno),
      );
      expect(
        Destinations.barFor(UserRole.administrador),
        contains(AppDestination.garita),
      );
    });

    test('preferencias sale de la barra pero sigue alcanzable', () {
      for (final role in [UserRole.colectivero, UserRole.administrador]) {
        expect(Destinations.isTab(AppDestination.preferencias, role), isFalse);
        expect(
          Destinations.extrasFor(role),
          contains(AppDestination.preferencias),
        );
      }
    });

    test('tabIndex nunca devuelve un índice fuera de rango', () {
      for (final role in UserRole.values) {
        for (final destination in AppDestination.values) {
          expect(
            Destinations.tabIndex(destination, role),
            inInclusiveRange(0, 2),
          );
        }
      }
    });
  });

  group('reconciliación al cambiar de rol', () {
    final nav = MainNavigationController.instance;

    tearDown(() => nav.go(AppDestination.mapa));

    test('vuelve al mapa si el destino ya no existe en el rol nuevo', () {
      // Un administrador mirando la flota cierra sesión: "Flota" no existe para
      // el invitado y la app quedaría en una pestaña inalcanzable.
      nav.go(AppDestination.flota);
      expect(nav.destination, AppDestination.flota);

      nav.reconcile(UserRole.invitado);
      expect(nav.destination, AppDestination.mapa);
    });

    test('conserva el destino si el rol nuevo también lo tiene', () {
      nav.go(AppDestination.rutas);
      nav.reconcile(UserRole.colectivero);
      expect(nav.destination, AppDestination.rutas);
    });
  });

  group('patentes', () {
    test('las variantes de escritura dan el mismo correo sintético', () {
      // Es la propiedad crítica de todo el inicio de sesión del chofer: la
      // patente *es* la identidad de la cuenta y no hay recuperación por
      // correo, así que si dos formas de escribirla dieran correos distintos,
      // el chofer quedaría fuera de su propia cuenta sin salida.
      const esperado = 'bbcc12@chofer.coletotal.app';
      for (final entrada in ['BBCC12', 'bbcc12', 'BB-CC-12', 'bb cc 12']) {
        expect(patenteToEmail(entrada), esperado, reason: entrada);
      }
    });

    test('acepta los dos formatos chilenos', () {
      expect(isValidPatente('BBBB12'), isTrue, reason: 'formato actual');
      expect(isValidPatente('AB1234'), isTrue, reason: 'formato antiguo');
    });

    test('rechaza lo que no puede ser una patente', () {
      expect(isValidPatente(''), isFalse);
      expect(isValidPatente('AB12'), isFalse, reason: 'muy corta');
      expect(isValidPatente('ABCD1234'), isFalse, reason: 'muy larga');
      expect(isValidPatente('ABCDEF'), isFalse, reason: 'sin dígitos');
      expect(isValidPatente('123456'), isFalse, reason: 'sin letras');
    });

    test('patenteToEmail no fabrica cuentas irrecuperables', () {
      expect(() => patenteToEmail('AB12'), throwsArgumentError);
    });

    test('formatPatente separa el bloque de letras del de dígitos', () {
      expect(formatPatente('BBBB12'), 'BBBB·12');
      expect(formatPatente('AB1234'), 'AB·1234');
    });
  });

  group('perfil de usuario', () {
    const perfil = AppUser(
      uid: 'u1',
      rol: UserRole.colectivero,
      nombre: 'Tomás Moraga',
      garitaId: 'g1',
      patente: 'BBCC12',
    );

    test('las iniciales salen del nombre, no del uid', () {
      expect(perfil.initials, 'TM');
      expect(
        const AppUser(
          uid: 'u2',
          rol: UserRole.administrador,
          nombre: 'Ana',
          garitaId: 'g1',
        ).initials,
        'A',
      );
    });

    test('sin nombre cae a la patente, que sí identifica al chofer', () {
      const sinNombre = AppUser(
        uid: 'u3',
        rol: UserRole.colectivero,
        nombre: '   ',
        garitaId: 'g1',
        patente: 'BBCC12',
      );
      expect(sinNombre.displayName, 'BBCC12');
    });

    test('sobrevive al viaje por la caché de arranque', () {
      expect(AppUser.fromJson(perfil.toJson()), perfil);
    });

    test('una caché corrupta no tumba el arranque', () {
      expect(AppUser.fromJson('{no es json'), isNull);
      expect(AppUser.fromJson(null), isNull);
      expect(AppUser.fromJson('{}'), isNull, reason: 'sin uid no hay perfil');
    });

    test('un rol desconocido se degrada a invitado en vez de reventar', () {
      expect(
        AppUser.fromMap('u4', {'rol': 'presidente'}).rol,
        UserRole.invitado,
      );
    });

    test('el rol viaja con un nombre estable, no con el índice del enum', () {
      expect(UserRole.colectivero.wireName, 'colectivero');
      expect(UserRole.fromWire('administrador'), UserRole.administrador);
    });

    test('el código usado se guarda: es lo que verifican las reglas', () {
      final map = perfil.toCreateMap(codigo: 'QLP-CHO-9XZ4');
      expect(map['codigo'], 'QLP-CHO-9XZ4');
      expect(map['rol'], 'colectivero');
    });
  });

  group('telemetría', () {
    test('un nodo del formato antiguo sigue parseando', () {
      // Antes la clave era un id generado en el teléfono y no existían `uid`,
      // `estado` ni `ts`. Esos nodos siguen en la base hasta que expiren, y si
      // reventaran al parsear se caería el stream entero.
      final viejo = ColectivoActivo.fromJson({
        'idVehiculo': 'chofer_abc123',
        'latitud': -33.0472,
        'longitud': -71.4425,
      });
      expect(viejo.uid, 'chofer_abc123');
      expect(viejo.estado, EstadoCapacidad.disponible);
      expect(viejo.isStale(), isFalse, reason: 'sin ts no se puede afirmar');
    });

    test('descarta las unidades más viejas que el umbral', () {
      // `onDisconnect` puede tardar minutos en dispararse cuando se cae la red:
      // sin este filtro quedan colectivos fantasma clavados en el mapa.
      final ahora = DateTime(2026, 9, 1, 12);
      ColectivoActivo conEdad(Duration edad) => ColectivoActivo(
        uid: 'u1',
        idVehiculo: 'BBCC12',
        latitud: -33.0,
        longitud: -71.0,
        ts: ahora.subtract(edad).millisecondsSinceEpoch,
      );

      expect(conEdad(const Duration(seconds: 10)).isStale(ahora), isFalse);
      expect(conEdad(const Duration(minutes: 5)).isStale(ahora), isTrue);
    });

    test('el payload no lleva ts: la marca la pone el servidor', () {
      const c = ColectivoActivo(
        uid: 'u1',
        idVehiculo: 'BBCC12',
        latitud: -33.0,
        longitud: -71.0,
        estado: EstadoCapacidad.lleno,
      );
      final json = c.toJson();
      expect(json.containsKey('ts'), isFalse);
      expect(json['uid'], 'u1');
      expect(json['estado'], 'lleno');
    });

    test('el estado viaja con un nombre estable', () {
      for (final estado in EstadoCapacidad.values) {
        expect(EstadoCapacidad.fromWire(estado.wireName), estado);
      }
      expect(
        EstadoCapacidad.fromWire('otra-cosa'),
        EstadoCapacidad.disponible,
        reason: 'ante la duda, la unidad se muestra disponible',
      );
    });
  });
}
