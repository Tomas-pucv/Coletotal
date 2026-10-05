import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:taxi1/data/quilpue_pois.dart';
import 'package:taxi1/services/geocoding_service.dart';

void main() {
  // Ningún test sale a la red: antes estos llamaban de verdad a MapTiler y a
  // Photon, gastaban cuota y dependían de tener conexión.
  late List<Uri> peticiones;

  void responder(Future<http.Response> Function(http.Request) handler) {
    GeocodingService.debugClient = MockClient((request) {
      peticiones.add(request.url);
      return handler(request);
    });
  }

  setUp(() {
    peticiones = [];
    responder((_) async => http.Response('{"features": []}', 200));
  });

  group('Catálogo de Puntos de Interés de Quilpué (POIs)', () {
    test('El catálogo tiene más de 20 POIs registrados', () {
      expect(kQuilpuePois.length, greaterThanOrEqualTo(20));
    });

    test('Todos los POIs tienen coordenadas válidas dentro de la V Región', () {
      for (final poi in kQuilpuePois) {
        expect(poi.id, isNotEmpty);
        expect(poi.name, isNotEmpty);
        expect(poi.location.latitude, inInclusiveRange(-33.20, -32.95));
        expect(poi.location.longitude, inInclusiveRange(-71.55, -71.35));
      }
    });

    test('los ids no se repiten', () {
      final ids = kQuilpuePois.map((p) => p.id).toSet();
      expect(ids, hasLength(kQuilpuePois.length));
    });
  });

  group('GeocodingService', () {
    test('encuentra "Líder" escrito sin tilde', () async {
      final matches = await GeocodingService.search('lider');
      expect(matches.any((p) => p.name.contains('Líder')), isTrue);
    });

    test('encuentra el hospital aunque se escriba en otro orden', () async {
      final matches = await GeocodingService.search('quilpue hospital');
      expect(matches.any((p) => p.name == 'Hospital de Quilpué'), isTrue);
    });

    test('con dos letras no gasta red', () async {
      await GeocodingService.search('pl');
      expect(peticiones, isEmpty);
    });

    test('si MapTiler falla, complementa con Photon', () async {
      responder((request) async {
        if (request.url.host == 'api.maptiler.com') {
          return http.Response('cuota agotada', 429);
        }
        return http.Response.bytes(
          utf8.encode(
            jsonEncode({
              'features': [
                {
                  'geometry': {
                    'coordinates': [-71.44, -33.05],
                  },
                  'properties': {
                    'name': 'Calle Ñuñoa',
                    'city': 'Quilpué',
                    'osm_id': 1,
                  },
                },
              ],
            }),
          ),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final results = await GeocodingService.search('calle nunoa');
      expect(peticiones.map((u) => u.host), [
        'api.maptiler.com',
        'photon.komoot.io',
      ]);
      // Sin `charset` en la cabecera, `res.body` habría entregado "Ã'uÃ±oa".
      expect(results.single.name, 'Calle Ñuñoa');
      expect(results.single.address, contains('Quilpué'));
    });

    test('Photon queda acotado a la Quinta Región', () async {
      responder((request) async => request.url.host == 'api.maptiler.com'
          ? http.Response('', 500)
          : http.Response('{"features": []}', 200));

      await GeocodingService.search('avenida los carrera');
      final photon = peticiones.firstWhere(
        (u) => u.host == 'photon.komoot.io',
      );
      expect(photon.queryParameters['bbox'], isNotNull);
    });
  });
}
