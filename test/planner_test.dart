import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';

import 'package:taxi1/models/bus_stop.dart';
import 'package:taxi1/models/recorrido.dart';
import 'package:taxi1/services/osrm_client.dart';
import 'package:taxi1/services/stop_planner.dart';
import 'package:taxi1/utils/polyline.dart';

/// Tests del recomendador de paraderos y de las utilidades de ruteo.
///
/// Todo con datos inyectados: `StopPlanner.suggest` acepta las listas por
/// parámetro justamente para poder verificar el criterio sin Firestore ni red.
void main() {
  // Una malla simple sobre Quilpué. A esta latitud, 0.001° ≈ 111 m en latitud
  // y ≈ 93 m en longitud, suficiente para razonar sobre las distancias.
  BusStop stop(String id, double lat, double lng) =>
      BusStop(id: id, name: id, address: id, location: LatLng(lat, lng));

  final cerca = stop('cerca', -33.0470, -71.4425);
  final lejos = stop('lejos', -33.0700, -71.4425);
  final juntoAlDestino = stop('junto-destino', -33.0800, -71.4425);
  final aMedias = stop('a-medias', -33.0600, -71.4425);

  const usuario = LatLng(-33.0472, -71.4425);
  const destino = LatLng(-33.0805, -71.4425);

  group('StopPlanner', () {
    test('prefiere el paradero cuya línea deja más cerca del destino', () {
      // Las dos subidas están a la misma distancia del usuario, pero sólo una
      // pertenece a una línea que pasa junto al destino.
      final sinSalida = stop('sin-salida', -33.0471, -71.4425);

      final recorridos = [
        Recorrido(
          id: 'r-buena',
          garitaId: 'g1',
          nombre: 'Línea buena',
          colorValue: 0xFF4A3F9E,
          paraderoIds: [cerca.id, juntoAlDestino.id],
        ),
        Recorrido(
          id: 'r-mala',
          garitaId: 'g1',
          nombre: 'Línea mala',
          colorValue: 0xFF4A3F9E,
          paraderoIds: [sinSalida.id, aMedias.id],
        ),
      ];

      final result = StopPlanner.suggest(
        user: usuario,
        destino: destino,
        stops: [cerca, sinSalida, aMedias, juntoAlDestino],
        recorridos: recorridos,
      );

      expect(result.first.stop, cerca);
      expect(result.first.recorrido?.id, 'r-buena');
      expect(result.first.bajada, juntoAlDestino);
    });

    test('el promedio equilibra los dos tramos a pie', () {
      // Una subida lejísimos que deja pegado al destino no debería ganarle a
      // una razonable en ambos tramos: es el punto del promedio.
      final recorridos = [
        Recorrido(
          id: 'r1',
          garitaId: 'g1',
          nombre: 'A',
          colorValue: 0,
          paraderoIds: [cerca.id, aMedias.id],
        ),
        Recorrido(
          id: 'r2',
          garitaId: 'g1',
          nombre: 'B',
          colorValue: 0,
          paraderoIds: [lejos.id, juntoAlDestino.id],
        ),
      ];

      final result = StopPlanner.suggest(
        user: usuario,
        destino: destino,
        stops: [cerca, lejos, aMedias, juntoAlDestino],
        recorridos: recorridos,
      );

      for (final s in result) {
        expect(
          s.score,
          closeTo((s.metersToUser + s.metersToDestination) / 2, 0.001),
        );
      }
      // Ordenado de mejor a peor, sin excepciones.
      for (var i = 1; i < result.length; i++) {
        expect(result[i - 1].score, lessThanOrEqualTo(result[i].score));
      }
    });

    test('ignora los paraderos que ninguna línea sirve', () {
      final huerfano = stop('huerfano', -33.0473, -71.4426);
      final recorridos = [
        Recorrido(
          id: 'r1',
          garitaId: 'g1',
          nombre: 'A',
          colorValue: 0,
          paraderoIds: [cerca.id, juntoAlDestino.id],
        ),
      ];

      final result = StopPlanner.suggest(
        user: usuario,
        destino: destino,
        stops: [cerca, huerfano, juntoAlDestino],
        recorridos: recorridos,
      );

      // `huerfano` está más cerca del usuario que nada, pero no lleva a ningún
      // lado: proponerlo sería mentir.
      expect(result.map((s) => s.stop.id), isNot(contains('huerfano')));
    });

    test(
      'sin recorridos cargados degrada a cercanía en vez de no dar nada',
      () {
        final result = StopPlanner.suggest(
          user: usuario,
          destino: destino,
          stops: [cerca, aMedias, juntoAlDestino],
          recorridos: const [],
        );

        expect(result, isNotEmpty);
        // Se marca como aproximación: sin línea no se puede prometer un viaje.
        expect(result.every((s) => s.recorrido == null), isTrue);
        expect(result.first.stop, juntoAlDestino);
      },
    );

    test('un recorrido desactivado no se propone', () {
      final recorridos = [
        Recorrido(
          id: 'r1',
          garitaId: 'g1',
          nombre: 'Suspendida',
          colorValue: 0,
          paraderoIds: [cerca.id, juntoAlDestino.id],
          activo: false,
        ),
      ];

      final result = StopPlanner.suggest(
        user: usuario,
        destino: destino,
        stops: [cerca, juntoAlDestino],
        recorridos: recorridos,
      );

      expect(result.every((s) => s.recorrido == null), isTrue);
    });

    test('no devuelve más sugerencias de las que se pueden leer', () {
      final muchos = [
        for (var i = 0; i < 30; i++) stop('p$i', -33.05 - i * 0.001, -71.44),
      ];
      final result = StopPlanner.suggest(
        user: usuario,
        destino: destino,
        stops: muchos,
        recorridos: const [],
      );
      expect(result.length, StopPlanner.maxSuggestions);
    });

    test('nunca propone bajarse donde uno se sube', () {
      // El destino está junto a la subida: la parada de la línea más cercana
      // al destino es la propia subida. Antes eso se proponía como "toma la
      // línea y bájate en el mismo paradero".
      final recorridos = [
        Recorrido(
          id: 'r1',
          garitaId: 'g1',
          nombre: 'A',
          colorValue: 0,
          paraderoIds: [cerca.id, lejos.id],
        ),
      ];

      final result = StopPlanner.suggest(
        user: usuario,
        destino: cerca.location,
        stops: [cerca, lejos],
        recorridos: recorridos,
      );

      for (final s in result) {
        if (s.bajada != null) expect(s.bajada, isNot(s.stop));
      }
    });

    test('sin paraderos no revienta', () {
      expect(
        StopPlanner.suggest(
          user: usuario,
          destino: destino,
          stops: const [],
          recorridos: const [],
        ),
        isEmpty,
      );
    });
  });

  group('Polilíneas y OSRM', () {
    tearDown(() => OsrmClient.debugClient = http.Client());

    test('decodifica las coordenadas negativas de Quilpué', () {
      // Cadena de referencia del algoritmo de Google/OSRM, precisión 6. Todas
      // las coordenadas de Quilpué son negativas: es el caso que fallaba en la
      // web, donde `~` devuelve enteros de 32 bits sin signo.
      const encoded = r'~h``~@fcoggCosEwyE';
      final puntos = decodePolyline(encoded);

      expect(puntos, hasLength(2));
      expect(puntos[0].latitude, closeTo(-33.0472, 1e-9));
      expect(puntos[0].longitude, closeTo(-71.4425, 1e-9));
      expect(puntos[1].latitude, closeTo(-33.0438, 1e-9));
      expect(puntos[1].longitude, closeTo(-71.4390, 1e-9));
      expect(
        encodePolyline(puntos),
        encoded,
        reason: 'codificar tiene que dar la misma cadena que OSRM',
      );
    });

    test('codificar y decodificar una polilínea es ida y vuelta', () {
      const puntos = [
        LatLng(-33.047213, -71.442512),
        LatLng(-33.043801, -71.439004),
        LatLng(-33.051002, -71.448013),
      ];
      final decoded = decodePolyline(encodePolyline(puntos));
      expect(decoded, hasLength(3));
      for (var i = 0; i < puntos.length; i++) {
        expect(decoded[i].latitude, closeTo(puntos[i].latitude, 1e-6));
        expect(decoded[i].longitude, closeTo(puntos[i].longitude, 1e-6));
      }
    });

    test('trocea las líneas largas en tramos que se solapan', () {
      // Antes se cortaba en silencio en el paradero 25.
      final puntos = [
        for (var i = 0; i < 60; i++) LatLng(-33.0 - i * 0.001, -71.44),
      ];
      final tramos = chunkWaypoints(puntos, OsrmClient.maxWaypoints);

      expect(tramos.every((t) => t.length <= OsrmClient.maxWaypoints), isTrue);
      expect(tramos.first.first, puntos.first);
      expect(tramos.last.last, puntos.last);
      for (var i = 1; i < tramos.length; i++) {
        expect(tramos[i].first, tramos[i - 1].last);
      }
    });

    test('cose los tramos sin repetir el punto de unión', () async {
      var peticiones = 0;
      OsrmClient.debugClient = MockClient((request) async {
        peticiones++;
        // Responde con una "ruta" que une exactamente los puntos pedidos.
        final coords = request.url.pathSegments.last
            .split(';')
            .map((c) => c.split(',').map(double.parse).toList())
            .map((c) => LatLng(c[1], c[0]))
            .toList();
        return http.Response(
          jsonEncode({
            'code': 'Ok',
            'routes': [
              {
                'geometry': encodePolyline(coords),
                'distance': 100.0 * (coords.length - 1),
                'duration': 10.0 * (coords.length - 1),
              },
            ],
          }),
          200,
        );
      });

      final puntos = [
        for (var i = 0; i < 30; i++) LatLng(-33.0 - i * 0.001, -71.44),
      ];
      final ruta = await OsrmClient.route(puntos);

      expect(peticiones, 2);
      expect(ruta, isNotNull);
      expect(ruta!.points, hasLength(30));
      expect(ruta.distanceMeters, closeTo(2900, 1e-6));
    });

    test('si un tramo falla, la ruta entera falla', () async {
      OsrmClient.debugClient = MockClient(
        (_) async => http.Response('error', 500),
      );
      expect(
        await OsrmClient.route(const [
          LatLng(-33.04, -71.44),
          LatLng(-33.05, -71.45),
        ]),
        isNull,
      );
    });

    test('decodifica una polilínea de ida y vuelta', () {
      // Referencia clásica del algoritmo de Google, con precisión 5.
      final points = decodePolyline(
        '_p~iF~ps|U_ulLnnqC_mqNvxq`@',
        precision: 5,
      );
      expect(points, hasLength(3));
      expect(points[0].latitude, closeTo(38.5, 0.001));
      expect(points[0].longitude, closeTo(-120.2, 0.001));
      expect(points[2].latitude, closeTo(43.252, 0.001));
      expect(points[2].longitude, closeTo(-126.453, 0.001));
    });

    test('descarta coordenadas que romperían el mapa', () {
      expect(isValidLatLng(const LatLng(-33.05, -71.44)), isTrue);
      expect(isValidLatLng(LatLng(double.nan, -71.44)), isFalse);
      expect(isValidLatLng(LatLng(double.infinity, 0)), isFalse);
    });
  });

  group('Recorrido', () {
    test('necesita al menos dos paraderos para describir un trayecto', () {
      const uno = Recorrido(
        id: 'r',
        garitaId: 'g',
        nombre: 'A',
        colorValue: 0,
        paraderoIds: ['a'],
      );
      expect(uno.isValid, isFalse);
      expect(uno.copyWith(paraderoIds: ['a', 'b']).isValid, isTrue);
    });

    test('sin nombre no es válido aunque tenga paraderos', () {
      const sinNombre = Recorrido(
        id: 'r',
        garitaId: 'g',
        nombre: '   ',
        colorValue: 0,
        paraderoIds: ['a', 'b'],
      );
      expect(sinNombre.isValid, isFalse);
    });

    test('una geometría corrupta no se dibuja: se recalcula', () {
      // Latitud 200 no existe. Antes esos puntos se dibujaban igual, fuera del
      // mapa; ahora el recorrido queda sin trazado guardado y se recalcula.
      final corrupta = encodePolyline(const [
        LatLng(200, -71.44),
        LatLng(201, -71.45),
      ]);
      expect(
        Recorrido.fromMap('r', {'nombre': 'A', 'geometria': corrupta}).trazado,
        isEmpty,
      );

      final buena = encodePolyline(const [
        LatLng(-33.04, -71.44),
        LatLng(-33.05, -71.45),
      ]);
      expect(
        Recorrido.fromMap('r', {'nombre': 'A', 'geometria': buena}).trazado,
        hasLength(2),
      );
    });

    test('sobrevive al viaje por Firestore', () {
      const original = Recorrido(
        id: 'r1',
        garitaId: 'g1',
        nombre: 'Línea 5',
        colorValue: 0xFF4A3F9E,
        paraderoIds: ['a', 'b', 'c'],
      );
      final restaurado = Recorrido.fromMap('r1', original.toMap());
      expect(restaurado, original);
      expect(restaurado.nombre, 'Línea 5');
      expect(restaurado.paraderoIds, ['a', 'b', 'c']);
      expect(restaurado.colorValue, 0xFF4A3F9E);
    });
  });
}
