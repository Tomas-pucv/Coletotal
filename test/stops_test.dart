import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:taxi1/models/bus_stop.dart';
import 'package:taxi1/services/preferences_service.dart';
import 'package:taxi1/services/stop_history_service.dart';
import 'package:taxi1/services/stops_service.dart';

/// Tests de la identidad de los paraderos.
///
/// Es el punto más delicado de todo el cambio: hasta que los paraderos vinieron
/// de Firestore, la igualdad la daba de regalo la canonicalización de
/// constantes de Dart. Cada snapshot construye instancias nuevas, así que si
/// `==` dejara de funcionar **no habría error de compilación**: simplemente el
/// paradero seleccionado dejaría de resaltarse en el mapa y el spinner de la
/// fila de Rutas no aparecería nunca. Estos tests son ese canario.
void main() {
  group('identidad de BusStop', () {
    const original = BusStop(
      id: 'p1',
      name: 'Plaza de Armas',
      address: 'Av. Valparaíso 700',
      location: LatLng(-33.0472, -71.4425),
    );

    test('mismo id es el mismo paradero aunque cambien sus datos', () {
      // Exactamente lo que pasa cuando el administrador lo mueve o le corrige
      // el nombre: el destino que el pasajero tenía seleccionado sigue siéndolo.
      const movido = BusStop(
        id: 'p1',
        name: 'Plaza de Armas (norte)',
        address: 'Otra dirección',
        location: LatLng(-33.0480, -71.4430),
      );

      expect(movido, original);
      expect(movido.hashCode, original.hashCode);
    });

    test('ids distintos son paraderos distintos aunque coincida todo lo demás', () {
      const gemelo = BusStop(
        id: 'p2',
        name: 'Plaza de Armas',
        address: 'Av. Valparaíso 700',
        location: LatLng(-33.0472, -71.4425),
      );

      expect(gemelo, isNot(original));
    });

    test('funciona dentro de colecciones, que es como se usa', () {
      const listaDeSnapshot = [
        BusStop(
          id: 'p1',
          name: 'Plaza de Armas',
          address: 'x',
          location: LatLng(-33.05, -71.44),
        ),
      ];
      // `destination == stop` en map_screen y routes_screen dependen de esto.
      expect(listaDeSnapshot.contains(original), isTrue);
      expect({original}.contains(listaDeSnapshot.first), isTrue);
    });

    test('sobrevive al viaje por Firestore', () {
      final restaurado = BusStop.fromMap(original.id, original.toMap());
      expect(restaurado, original);
      expect(restaurado.name, original.name);
      expect(restaurado.location.latitude, closeTo(-33.0472, 1e-9));
      expect(restaurado.location.longitude, closeTo(-71.4425, 1e-9));
    });
  });

  group('semilla de paraderos', () {
    test('todos los ids son únicos', () {
      final ids = quilpueBusStops.map((s) => s.id).toSet();
      expect(ids, hasLength(quilpueBusStops.length));
    });

    test('los ids llevan prefijo seed- para no chocar con los de Firestore', () {
      for (final stop in quilpueBusStops) {
        expect(stop.id, startsWith('seed-'), reason: stop.name);
      }
    });

    test('StopsService trae la semilla sin haber tocado la red', () {
      // Sin esta siembra sincrónica el mapa arrancaría vacío y los tests de
      // historial necesitarían Firebase.
      expect(StopsService.instance.stops, isNotEmpty);
      expect(StopsService.instance.hasRemoteData, isFalse);
      expect(
        StopsService.instance.byId('seed-plaza-de-armas')?.name,
        'Plaza de Armas',
      );
    });
  });

  group('migración del historial', () {
    final stops = StopsService.instance;

    test('las entradas guardadas por nombre se convierten a ids', () {
      // Un teléfono que ya tenía la app guardó nombres. Al actualizar, ese
      // historial tiene que seguir significando algo.
      final migrated = StopHistoryService.migrateHistory(
        ['Plaza de Armas', 'Belloto'],
        byId: stops.byId,
        byName: stops.byName,
      );
      expect(migrated, ['seed-plaza-de-armas', 'seed-belloto']);
    });

    test('un id que todavía no resuelve se conserva', () {
      // Regresión: al arrancar sólo están cargados los paraderos semilla, así
      // que los ids de Firestore no resolvían y la "migración" los borraba del
      // disco. El historial de "Recientes" se perdía en cada arranque en frío.
      final migrated = StopHistoryService.migrateHistory(
        ['aB3xYz9QwErTyUiOpAsD', 'seed-el-sol'],
        byId: stops.byId,
        byName: stops.byName,
      );
      expect(migrated, ['aB3xYz9QwErTyUiOpAsD', 'seed-el-sol']);
    });

    test('no duplica ni supera el tope', () {
      final migrated = StopHistoryService.migrateHistory(
        [
          'Plaza de Armas',
          'seed-plaza-de-armas',
          'a',
          'b',
          'c',
          'd',
          'e',
        ],
        byId: stops.byId,
        byName: stops.byName,
      );
      expect(migrated.first, 'seed-plaza-de-armas');
      expect(migrated.toSet(), hasLength(migrated.length));
      expect(migrated.length, StopHistoryService.maxEntries);
    });

    test('el historial resuelve ids contra la lista viva', () async {
      SharedPreferences.setMockInitialValues({'history_enabled': true});
      await PreferencesService.instance.setHistoryEnabled(true);
      await StopHistoryService.instance.clear();
      await StopHistoryService.instance.record(quilpueBusStops.first);

      expect(
        StopHistoryService.instance.recentStops.first,
        quilpueBusStops.first,
      );
    });

    test('un id que no resuelve no se muestra roto', () async {
      SharedPreferences.setMockInitialValues({'history_enabled': true});
      await PreferencesService.instance.setHistoryEnabled(true);
      await StopHistoryService.instance.clear();
      await StopHistoryService.instance.record(
        const BusStop(
          id: 'paradero-de-otra-sesion',
          name: 'X',
          address: 'X',
          location: LatLng(-33.05, -71.44),
        ),
      );
      await StopHistoryService.instance.record(quilpueBusStops.first);

      expect(StopHistoryService.instance.recentStops, [quilpueBusStops.first]);
    });
  });
}
