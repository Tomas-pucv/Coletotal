import 'package:flutter_test/flutter_test.dart';
import 'package:taxi1/data/quilpue_pois.dart';
import 'package:taxi1/services/geocoding_service.dart';

void main() {
  group('Catálogo de Puntos de Interés de Quilpué (POIs)', () {
    test('El catálogo tiene más de 20 POIs registrados', () {
      expect(kQuilpuePois.length, greaterThanOrEqualTo(20));
    });

    test('Todos los POIs tienen coordenadas geográficas válidas dentro de la V Región', () {
      for (final poi in kQuilpuePois) {
        expect(poi.id, isNotEmpty);
        expect(poi.name, isNotEmpty);
        // Quilpué latitud aprox [-33.20, -32.95]
        expect(poi.location.latitude, inInclusiveRange(-33.20, -32.95));
        // Quilpué longitud aprox [-71.55, -71.35]
        expect(poi.location.longitude, inInclusiveRange(-71.55, -71.35));
      }
    });

    test('Búsqueda local de GeocodingService encuentra Líder Belloto', () async {
      final matchNombre = await GeocodingService.search('Líder');
      expect(matchNombre, isNotEmpty);
      expect(matchNombre.any((p) => p.name.contains('Líder')), isTrue);
    });

    test('Búsqueda local de GeocodingService encuentra hospital', () async {
      final matches = await GeocodingService.search('hospital');
      expect(matches, isNotEmpty);
      expect(matches.any((p) => p.name.contains('Hospital')), isTrue);
    });
  });
}
