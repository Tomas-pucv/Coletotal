import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';

import 'package:taxi1/services/osrm_client.dart';
import 'package:taxi1/services/routing.dart';
import 'package:taxi1/services/valhalla_client.dart';
import 'package:taxi1/utils/polyline.dart';

/// Lo que la app le pidió al Valhalla del teléfono.
Map<String, dynamic> _consulta(String pedido) =>
    jsonDecode(pedido) as Map<String, dynamic>;

/// Responde con una "ruta" que une en línea recta los puntos pedidos, un
/// tramo (`leg`) por par de paraderos, como hace Valhalla.
String _ecoValhalla(String pedido) {
  final puntos = [
    for (final l in (_consulta(pedido)['locations'] as List).cast<Map>())
      LatLng((l['lat'] as num).toDouble(), (l['lon'] as num).toDouble()),
  ];
  return jsonEncode({
    'trip': {
      'legs': [
        for (var i = 1; i < puntos.length; i++)
          {
            'shape': encodePolyline([puntos[i - 1], puntos[i]]),
          },
      ],
      'summary': {'length': 0.1 * (puntos.length - 1), 'time': 10.0},
    },
  });
}

http.Response _osrm(List<LatLng> puntos) => http.Response(
  jsonEncode({
    'code': 'Ok',
    'routes': [
      {'geometry': encodePolyline(puntos), 'distance': 900, 'duration': 120},
    ],
  }),
  200,
);

void main() {
  tearDown(() {
    ValhallaClient.debugLocal = null;
    OsrmClient.debugClient = http.Client();
  });

  const paraderos = [
    LatLng(-33.0472, -71.4425),
    LatLng(-33.0438, -71.4390),
    LatLng(-33.0510, -71.4480),
  ];

  test('en auto, los paraderos sólo se enganchan a calles públicas', () async {
    // Con OSRM el paradero de Villa Olímpica se enganchaba a las huellas de
    // los cerros sobre el zoológico: 2 km de línea por donde no pasa nadie.
    late String pedido;
    ValhallaClient.debugLocal = (consulta) async {
      pedido = consulta;
      return _ecoValhalla(consulta);
    };

    await ValhallaClient.route(paraderos, costing: ValhallaCosting.auto);

    final consulta = _consulta(pedido);
    expect(consulta['costing'], 'auto');
    expect(consulta['directions_type'], 'none');
    for (final l in (consulta['locations'] as List).cast<Map>()) {
      expect(l['type'], 'break');
      expect(l['search_filter'], {'min_road_class': 'residential'});
    }
  });

  test('a pie no se filtran senderos', () async {
    late String pedido;
    ValhallaClient.debugLocal = (consulta) async {
      pedido = consulta;
      return _ecoValhalla(consulta);
    };

    await ValhallaClient.route(
      paraderos.take(2).toList(),
      costing: ValhallaCosting.pedestrian,
    );

    final consulta = _consulta(pedido);
    expect(consulta['costing'], 'pedestrian');
    for (final l in (consulta['locations'] as List).cast<Map>()) {
      expect(l.containsKey('search_filter'), isFalse);
    }
  });

  test('une los tramos sin repetir paraderos y pasa los km a metros', () async {
    ValhallaClient.debugLocal = (consulta) async => _ecoValhalla(consulta);

    final ruta = await ValhallaClient.route(
      paraderos,
      costing: ValhallaCosting.auto,
    );

    expect(ruta, isNotNull);
    expect(ruta!.points, hasLength(3));
    expect(ruta.distanceMeters, closeTo(200, 1e-6));
    expect(ruta.provider, 'Valhalla');
  });

  test(
    'una línea con más paraderos que el máximo se pide por tramos',
    () async {
      var consultas = 0;
      ValhallaClient.debugLocal = (consulta) async {
        consultas++;
        expect(
          (_consulta(consulta)['locations'] as List).length,
          lessThanOrEqualTo(ValhallaClient.maxLocations),
        );
        return _ecoValhalla(consulta);
      };

      final puntos = [
        for (var i = 0; i < 30; i++) LatLng(-33.0 - i * 0.001, -71.44),
      ];
      final ruta = await ValhallaClient.route(
        puntos,
        costing: ValhallaCosting.auto,
      );

      expect(consultas, 2);
      expect(ruta!.points, hasLength(30));
      expect(ruta.points.first, puntos.first);
      expect(ruta.points.last, puntos.last);
    },
  );

  test('sin Valhalla en el teléfono no se usa la red', () async {
    // iOS, la web, la primera copia en curso o un punto fuera de la región:
    // ValhallaClient no tiene servidor de respaldo, eso lo decide Routing.
    ValhallaClient.debugLocal = (_) async => null;
    expect(
      await ValhallaClient.route(paraderos, costing: ValhallaCosting.auto),
      isNull,
    );
  });

  test('una respuesta rara no rompe nada', () async {
    for (final respuesta in [
      '{"error_code":171,"error":"No suitable edges"}',
      'no es json',
      '{"trip":{"legs":[]}}',
    ]) {
      ValhallaClient.debugLocal = (_) async => respuesta;
      expect(
        await ValhallaClient.route(paraderos, costing: ValhallaCosting.auto),
        isNull,
        reason: respuesta,
      );
    }
  });

  group('Routing', () {
    test('con Valhalla en el teléfono, OSRM no se usa', () async {
      ValhallaClient.debugLocal = (consulta) async => _ecoValhalla(consulta);
      var aOsrm = 0;
      OsrmClient.debugClient = MockClient((_) async {
        aOsrm++;
        return _osrm(paraderos);
      });

      final ruta = await Routing.linePath(paraderos);

      expect(ruta!.provider, 'Valhalla');
      expect(aOsrm, 0);
    });

    test('si Valhalla no encuentra ruta, el trazado sale de OSRM', () async {
      ValhallaClient.debugLocal = (_) async => null;
      OsrmClient.debugClient = MockClient((_) async => _osrm(paraderos));

      final ruta = await Routing.linePath(paraderos);

      expect(ruta!.provider, 'OSRM');
      expect(ruta.points, hasLength(3));
    });

    test('el trazado guardado es la polilínea de la ruta', () async {
      ValhallaClient.debugLocal = (consulta) async => _ecoValhalla(consulta);

      final guardado = await Routing.encodedLinePath(paraderos);

      final puntos = decodePolyline(guardado!);
      expect(puntos, hasLength(3));
      expect(puntos.first.latitude, closeTo(paraderos.first.latitude, 1e-6));
    });

    test('sin ningún enrutador no hay trazado', () async {
      ValhallaClient.debugLocal = (_) async => null;
      OsrmClient.debugClient = MockClient(
        (_) async => http.Response('caído', 503),
      );

      expect(await Routing.linePath(paraderos), isNull);
    });
  });
}
