import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';

import 'package:taxi1/config/garita_config.dart';
import 'package:taxi1/models/recorrido.dart';
import 'package:taxi1/services/line_planner.dart';
import 'package:taxi1/services/osrm_client.dart';
import 'package:taxi1/services/recorridos_service.dart';
import 'package:taxi1/utils/polyline.dart';

/// Tests del planificador de viajes en colectivo y de las utilidades de ruteo.
///
/// Todo con datos inyectados: `LinePlanner.suggest` acepta las líneas por
/// parámetro justamente para poder verificar el criterio sin Firestore ni red.
void main() {
  // A esta latitud, 0.001° ≈ 111 m en latitud y ≈ 93 m en longitud.
  const lng = -71.4425;

  /// Un trayecto recto por el meridiano [lon], de [desde] a [hasta] (latitudes).
  Trayecto recto(double desde, double hasta, {double lon = lng}) {
    final puntos = [
      for (var i = 0; i <= 10; i++)
        LatLng(desde + (hasta - desde) * i / 10, lon),
    ];
    return Trayecto(
      puntos: [puntos.first, puntos.last],
      geometria: encodePolyline(puntos),
      trazado: puntos,
    );
  }

  /// Una línea que baja hacia el sur por [lon] (ida) y vuelve hacia el norte.
  Recorrido linea(
    String id, {
    double lon = lng,
    bool activo = true,
    String garitaId = kGaritaPublica,
    bool conVuelta = true,
  }) => Recorrido(
    id: id,
    garitaId: garitaId,
    nombre: 'Línea $id',
    colorValue: kRecorridoColors.first,
    ida: recto(-33.040, -33.090, lon: lon),
    vuelta: conVuelta ? recto(-33.090, -33.040, lon: lon) : null,
    activo: activo,
  );

  // El usuario, a unos 46 m al oeste de la línea; el destino, 3,7 km al sur.
  const usuario = LatLng(-33.0472, -71.4430);
  const destinoAlSur = LatLng(-33.0805, -71.4420);
  const destinoAlNorte = LatLng(-33.0420, -71.4420);

  group('nearestOnPolyline', () {
    test('proyecta sobre el tramo, no sólo sobre los vértices', () {
      const tramo = [LatLng(-33.04, -71.44), LatLng(-33.04, -71.43)];
      // Un punto 111 m al norte de la mitad del tramo.
      final cerca = nearestOnPolyline(tramo, const LatLng(-33.039, -71.435))!;
      expect(cerca.punto.latitude, closeTo(-33.04, 1e-6));
      expect(cerca.punto.longitude, closeTo(-71.435, 1e-6));
      expect(cerca.metros, closeTo(111.2, 0.5));
      // La mitad de un tramo de unos 933 m.
      expect(cerca.desdeInicio, closeTo(466, 2));
    });

    test('mide lo recorrido a lo largo de la línea', () {
      final t = recto(-33.040, -33.090);
      final inicio = nearestOnPolyline(t.trazado, const LatLng(-33.040, lng))!;
      final fin = nearestOnPolyline(t.trazado, const LatLng(-33.090, lng))!;
      expect(inicio.desdeInicio, closeTo(0, 1e-6));
      // 0.05° de latitud ≈ 5,56 km.
      expect(fin.desdeInicio, closeTo(5560, 10));
    });

    test('una línea vacía no tiene punto cercano', () {
      expect(nearestOnPolyline(const [], usuario), isNull);
    });

    test('si la línea pasa dos veces igual de cerca, gana la primera', () {
      const vaivien = [
        LatLng(-33.04, -71.44),
        LatLng(-33.05, -71.44),
        LatLng(-33.04, -71.44),
      ];
      final cerca = nearestOnPolyline(vaivien, const LatLng(-33.045, -71.439))!;
      expect(cerca.desdeInicio, lessThan(1200));
    });
  });

  group('LinePlanner', () {
    test('se sube en la línea más cercana y en el sentido que lleva', () {
      final s = LinePlanner.suggest(
        user: usuario,
        destino: destinoAlSur,
        recorridos: [linea('1')],
      );
      expect(s, hasLength(1));
      // Hacia el sur va la ida; la vuelta se aleja del destino.
      expect(s.single.sentido, Sentido.ida);
      expect(s.single.metrosHastaLinea, closeTo(46.6, 1));
      expect(s.single.metrosDesdeLinea, closeTo(46.6, 1));
      expect(s.single.metrosEnColectivo, closeTo(3700, 20));
      expect(s.single.subida.longitude, closeTo(lng, 1e-9));
    });

    test('hacia el otro lado toma la vuelta', () {
      final s = LinePlanner.suggest(
        user: usuario,
        destino: destinoAlNorte,
        recorridos: [linea('1')],
      );
      expect(s.single.sentido, Sentido.vuelta);
    });

    test('sin vuelta dibujada, no propone ir contra el sentido de la ida', () {
      final s = LinePlanner.suggest(
        user: usuario,
        destino: destinoAlNorte,
        recorridos: [linea('1', conVuelta: false)],
      );
      expect(s, isEmpty);
    });

    test('ordena por lo que hay que caminar en total', () {
      final s = LinePlanner.suggest(
        user: usuario,
        destino: destinoAlSur,
        recorridos: [linea('lejana', lon: -71.4500), linea('cercana')],
      );
      expect(s.map((x) => x.recorrido.id), ['cercana', 'lejana']);
    });

    test('una línea apagada no se propone', () {
      final s = LinePlanner.suggest(
        user: usuario,
        destino: destinoAlSur,
        recorridos: [linea('1', activo: false)],
      );
      expect(s, isEmpty);
    });

    test('una línea que pasa a más de 1,5 km no es una forma de llegar', () {
      final s = LinePlanner.suggest(
        user: usuario,
        destino: destinoAlSur,
        // ~1,86 km al oeste.
        recorridos: [linea('1', lon: -71.4630)],
      );
      expect(s, isEmpty);
    });

    test('si el destino está a pasos, no manda a tomar colectivo', () {
      final s = LinePlanner.suggest(
        user: usuario,
        destino: const LatLng(-33.0480, -71.4420),
        recorridos: [linea('1')],
      );
      expect(s, isEmpty);
    });

    test('no devuelve más sugerencias de las que se pueden leer', () {
      final s = LinePlanner.suggest(
        user: usuario,
        destino: destinoAlSur,
        recorridos: [
          for (var i = 0; i < 8; i++) linea('$i', lon: lng + i * 0.0005),
        ],
      );
      expect(s, hasLength(LinePlanner.maxSuggestions));
    });

    test('a cuánto pasa una línea, por cualquiera de sus sentidos', () {
      expect(LinePlanner.metrosHasta(linea('1'), usuario), closeTo(46.6, 1));
      const sinTrazado = Recorrido(
        id: 'x',
        garitaId: kGaritaPublica,
        nombre: 'x',
        colorValue: 0,
      );
      expect(LinePlanner.metrosHasta(sinTrazado, usuario), isNull);
    });

    test('el pasajero sólo ve las líneas activas de la garita pública', () {
      final service = RecorridosService.instance;
      service.debugSetRecorridos([
        linea('b'),
        linea('a'),
        linea('apagada', activo: false),
        linea('otra-garita', garitaId: 'otra'),
        const Recorrido(
          id: 'sin-trazado',
          garitaId: kGaritaPublica,
          nombre: 'Sin trazado',
          colorValue: 0,
        ),
      ]);
      addTearDown(() => service.debugSetRecorridos(const []));

      expect(service.publicas.map((r) => r.id), ['a', 'b']);
      // El administrador sí ve las de su garita, apagadas incluidas.
      expect(service.porGarita(kGaritaPublica), hasLength(4));
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
    Map<String, dynamic> trayectoMap(List<LatLng> puntos) => {
      'puntos': [for (final p in puntos) GeoPoint(p.latitude, p.longitude)],
      'geometria': encodePolyline(puntos),
    };

    test('sobrevive al viaje por Firestore, con ida y vuelta', () {
      final original = linea('1');
      final copia = Recorrido.fromMap('1', original.toMap());

      expect(copia.nombre, original.nombre);
      expect(copia.colorValue, original.colorValue);
      expect(copia.garitaId, kGaritaPublica);
      expect(copia.ida.trazado, hasLength(11));
      expect(copia.ida.puntos, hasLength(2));
      expect(copia.vuelta!.trazado.first.latitude, closeTo(-33.090, 1e-6));
      expect(copia.trayectos.map((t) => t.$1), [Sentido.ida, Sentido.vuelta]);
    });

    test('la vuelta es opcional', () {
      final sinVuelta = linea('1', conVuelta: false);
      expect(sinVuelta.toMap().containsKey('vuelta'), isFalse);
      final copia = Recorrido.fromMap('1', sinVuelta.toMap());
      expect(copia.vuelta, isNull);
      expect(copia.trayectos.map((t) => t.$1), [Sentido.ida]);
    });

    test('sin nombre o sin ida dibujable no se le muestra al pasajero', () {
      expect(linea('1').isValid, isTrue);
      expect(
        Recorrido.fromMap('x', {
          'nombre': '  ',
          'ida': trayectoMap(const [
            LatLng(-33.04, -71.44),
            LatLng(-33.05, -71.44),
          ]),
        }).isValid,
        isFalse,
      );
      expect(
        Recorrido.fromMap('x', {
          'nombre': 'Línea',
          'ida': trayectoMap(const [LatLng(-33.04, -71.44)]),
        }).isValid,
        isFalse,
      );
    });

    test('una geometría corrupta no se dibuja fuera del mapa', () {
      final r = Recorrido.fromMap('x', {
        'nombre': 'Línea',
        'ida': {'puntos': const [], 'geometria': '???'},
      });
      expect(r.ida.trazado, isEmpty);
      expect(r.isValid, isFalse);
    });
  });
}
