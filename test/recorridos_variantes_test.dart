import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:taxi1/data/serrano_recorridos.dart';
import 'package:taxi1/models/recorrido.dart';
import 'package:taxi1/models/variante.dart';
import 'package:taxi1/services/recorridos_service.dart';
import 'package:taxi1/services/turno_service.dart';
import 'package:taxi1/utils/polyline.dart';

void main() {
  group('Variantes de Serrano', () {
    test('catálogo oficial contiene las 3 variantes de Transportes Serrano', () {
      expect(kVariantesSerrano.length, 3);
      final ids = kVariantesSerrano.map((v) => v.id).toList();
      expect(ids, containsAll(['belloto-2000', 'las-rosas', 'mirador']));
    });

    test('varianteById resuelve variante correcta o null', () {
      final v1 = varianteById('belloto-2000');
      expect(v1, isNotNull);
      expect(v1!.nombre, 'Belloto 2000');

      final v2 = varianteById('las-rosas');
      expect(v2, isNotNull);
      expect(v2!.nombre, 'Las Rosas');

      final v3 = varianteById('mirador');
      expect(v3, isNotNull);
      expect(v3!.nombre, 'El Mirador / Cumming');

      expect(varianteById('inexistente'), isNull);
      expect(varianteById(null), isNull);
    });
  });

  group('distanceToPolyline (distancia ortogonal geodésica)', () {
    final polilinea = [
      const LatLng(-33.0450, -71.4400),
      const LatLng(-33.0450, -71.4500),
    ];

    test('punto exactamente sobre la línea tiene distancia cercana a cero', () {
      const puntoSobre = LatLng(-33.0450, -71.4450);
      final d = distanceToPolyline(puntoSobre, polilinea);
      expect(d, lessThan(1.0));
    });

    test('punto perpendicular a 111 metros (aprox 0.001 deg latitud)', () {
      const puntoOffset = LatLng(-33.0460, -71.4450);
      final d = distanceToPolyline(puntoOffset, polilinea);
      expect(d, inInclusiveRange(100.0, 125.0));
    });

    test('polilínea vacía devuelve infinito', () {
      const punto = LatLng(-33.0450, -71.4450);
      expect(distanceToPolyline(punto, const []), double.infinity);
    });

    test('polilínea de un solo punto devuelve distancia directa haversine', () {
      const p1 = LatLng(-33.0450, -71.4400);
      const punto = LatLng(-33.0460, -71.4400);
      final d = distanceToPolyline(punto, [p1]);
      expect(d, inInclusiveRange(100.0, 125.0));
    });
  });

  group('Modelo Recorrido con Cartolas y Variantes', () {
    const r = Recorrido(
      id: 'r101',
      garitaId: 'serrano',
      nombre: 'Línea 101 - Variante Belloto 2000',
      varianteId: 'belloto-2000',
      varianteNombre: 'Belloto 2000',
      callesIda: ['Garita Serrano', 'Freire', 'Av. Valparaíso', 'Baden Powell'],
      callesVuelta: ['Baden Powell', 'Av. Valparaíso', 'Freire', 'Garita Serrano'],
      colorValue: 0xFF1E88E5,
      trazado: [LatLng(-33.0440, -71.4390), LatLng(-33.0460, -71.4450)],
      trazadoVuelta: [LatLng(-33.0460, -71.4450), LatLng(-33.0440, -71.4390)],
    );

    test('todasLasCalles unifica ida y vuelta sin duplicados repetidos', () {
      final todas = r.todasLasCalles;
      expect(todas.length, 4);
      expect(todas, containsAll(['Garita Serrano', 'Freire', 'Av. Valparaíso', 'Baden Powell']));
    });

    test('matchesQuery busca por nombre, variante o cualquier calle de la cartola', () {
      expect(r.matchesQuery('101'), isTrue);
      expect(r.matchesQuery('belloto'), isTrue);
      expect(r.matchesQuery('Freire'), isTrue);
      expect(r.matchesQuery('baden powell'), isTrue);
      expect(r.matchesQuery('Valparaíso'), isTrue);
      expect(r.matchesQuery('valparaiso'), isTrue); // Sin tilde
      expect(r.matchesQuery('Santiago'), isFalse);
    });

    test('distanceFrom evalúa cercanía al trazado de la línea', () {
      final d = r.distanceFrom(const LatLng(-33.0450, -71.4420));
      expect(d, lessThan(200.0));
    });

    test('serialización toMap y fromMap preserva campos de variante y cartolas', () {
      final map = r.toMap();
      expect(map['varianteId'], 'belloto-2000');
      expect(map['varianteNombre'], 'Belloto 2000');
      expect(map['callesIda'], hasLength(4));
      expect(map['callesVuelta'], hasLength(4));

      final reconstruido = Recorrido.fromMap('r101', map);
      expect(reconstruido.id, 'r101');
      expect(reconstruido.varianteId, 'belloto-2000');
      expect(reconstruido.varianteNombre, 'Belloto 2000');
      expect(reconstruido.callesIda, ['Garita Serrano', 'Freire', 'Av. Valparaíso', 'Baden Powell']);
      expect(reconstruido.callesVuelta, ['Baden Powell', 'Av. Valparaíso', 'Freire', 'Garita Serrano']);
    });
  });

  group('Semilla Serrano y RecorridosService', () {
    test('semilla kSerranoRecorridosSeed contiene líneas oficiales con cartolas', () {
      expect(kSerranoRecorridosSeed.length, greaterThanOrEqualTo(5));
      for (final rec in kSerranoRecorridosSeed) {
        expect(rec.varianteId.isNotEmpty, isTrue);
        expect(rec.callesIda.isNotEmpty, isTrue);
        expect(rec.callesVuelta.isNotEmpty, isTrue);
        expect(rec.trazado.isNotEmpty, isTrue);
        expect(rec.trazadoVuelta.isNotEmpty, isTrue);
      }
    });

    test('RecorridosService filtra por variante', () {
      final s = RecorridosService.instance;
      final belloto = s.porVariante('belloto-2000');
      expect(belloto.isNotEmpty, isTrue);
      for (final r in belloto) {
        expect(r.varianteId, 'belloto-2000');
      }

      final rosas = s.porVariante('las-rosas');
      expect(rosas.isNotEmpty, isTrue);
      for (final r in rosas) {
        expect(r.varianteId, 'las-rosas');
      }
    });

    test('RecorridosService ordena por cercanía a posición de usuario', () {
      final s = RecorridosService.instance;
      // Posición en Belloto 2000 (cerca de Línea 101)
      const userPos = LatLng(-33.0500, -71.4330);
      final ordenados = s.filtrar(userLocation: userPos);
      expect(ordenados.isNotEmpty, isTrue);
      // La primera debe tener menor distancia que la última
      final dFirst = ordenados.first.distanceFrom(userPos);
      final dLast = ordenados.last.distanceFrom(userPos);
      expect(dFirst, lessThanOrEqualTo(dLast));
    });
  });

  group('TurnoService sentido de marcha', () {
    test('alternar sentido entre Ida y Vuelta', () {
      final turno = TurnoService.instance;
      turno.setSentidoIda(true);
      expect(turno.sentidoIda, isTrue);
      expect(turno.sentidoLabel, 'Ida');

      turno.setSentidoIda(false);
      expect(turno.sentidoIda, isFalse);
      expect(turno.sentidoLabel, 'Vuelta');
    });
  });
}
