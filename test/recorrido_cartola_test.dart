import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:taxi1/models/recorrido.dart';
import 'package:taxi1/utils/polyline.dart';
import 'package:taxi1/utils/text_search.dart';

void main() {
  const puntosPrueba = [
    LatLng(-33.0483, -71.4429),
    LatLng(-33.0508, -71.4421),
    LatLng(-33.0504, -71.4371),
  ];
  final trayectoPrueba = Trayecto(
    puntos: puntosPrueba,
    geometria: encodePolyline(puntosPrueba),
    trazado: puntosPrueba,
  );

  group('Recorrido Cartola MTT - Modelo y Serialización', () {
    test('serializa y deserializa correctamente los 5 campos de cartola MTT', () {
      final recorrido = Recorrido(
        id: 'rec_10_t',
        garitaId: 'garita_quilpue',
        nombre: 'Línea 10 [T] Belloto 2000 - Las Rosas',
        linea: 'Línea 10',
        codigoVariante: 'T',
        nombreVariante: 'Belloto 2000 - Las Rosas',
        callesIda: const [
          'SERRANO',
          'COVADONGA',
          'SAN MARTIN',
          'BAQUEDANO',
          'LATORRE',
        ],
        callesVuelta: const [
          'ALTO EL YUGO',
          'PANGUIPULLI',
          'JOTABECHE',
          'AV. RAMON FREIRE',
        ],
        colorValue: 0xFF1E88E5,
        activo: true,
        ida: trayectoPrueba,
        vuelta: trayectoPrueba,
      );

      final map = recorrido.toMap();

      expect(map['linea'], 'Línea 10');
      expect(map['codigoVariante'], 'T');
      expect(map['nombreVariante'], 'Belloto 2000 - Las Rosas');
      expect(map['callesIda'], [
        'SERRANO',
        'COVADONGA',
        'SAN MARTIN',
        'BAQUEDANO',
        'LATORRE',
      ]);
      expect(map['callesVuelta'], [
        'ALTO EL YUGO',
        'PANGUIPULLI',
        'JOTABECHE',
        'AV. RAMON FREIRE',
      ]);

      final recuperado = Recorrido.fromMap('rec_10_t', map);

      expect(recuperado.id, 'rec_10_t');
      expect(recuperado.linea, 'Línea 10');
      expect(recuperado.codigoVariante, 'T');
      expect(recuperado.nombreVariante, 'Belloto 2000 - Las Rosas');
      expect(recuperado.callesIda, [
        'SERRANO',
        'COVADONGA',
        'SAN MARTIN',
        'BAQUEDANO',
        'LATORRE',
      ]);
      expect(recuperado.callesVuelta, [
        'ALTO EL YUGO',
        'PANGUIPULLI',
        'JOTABECHE',
        'AV. RAMON FREIRE',
      ]);
      expect(recuperado.calles(Sentido.ida), recuperado.callesIda);
      expect(recuperado.calles(Sentido.vuelta), recuperado.callesVuelta);
    });

    test('sigla prefiere codigoVariante cuando existe', () {
      final conVariante = Recorrido(
        id: '1',
        garitaId: 'g',
        nombre: 'Línea 10 Variante Cumming',
        colorValue: 0xFF1E88E5,
        codigoVariante: 'V-2',
        nombreVariante: 'Cumming',
        ida: trayectoPrueba,
      );
      expect(conVariante.sigla, 'V-2');

      final sinVariante = Recorrido(
        id: '2',
        garitaId: 'g',
        nombre: 'Línea 12A Directo',
        colorValue: 0xFF1E88E5,
        ida: trayectoPrueba,
      );
      expect(sinVariante.sigla, '12A');
    });

    test('copyWith preserva o reemplaza los campos de la cartola', () {
      final base = Recorrido(
        id: '1',
        garitaId: 'g',
        nombre: 'Línea 10 [T]',
        colorValue: 0xFF1E88E5,
        linea: 'Línea 10',
        codigoVariante: 'T',
        nombreVariante: 'Troncal',
        callesIda: const ['SERRANO'],
        callesVuelta: const ['FREIRE'],
        ida: trayectoPrueba,
      );

      final clon = base.copyWith(
        codigoVariante: 'V-1',
        nombreVariante: 'Troncos Viejos',
        callesIda: const ['ISIDORA', 'TRONCOS VIEJOS'],
      );

      expect(clon.linea, 'Línea 10');
      expect(clon.codigoVariante, 'V-1');
      expect(clon.nombreVariante, 'Troncos Viejos');
      expect(clon.callesIda, ['ISIDORA', 'TRONCOS VIEJOS']);
      expect(clon.callesVuelta, ['FREIRE']);
    });
  });

  group('Búsqueda Predictiva de Líneas por Calles y Cartola', () {
    final linea10Troncal = Recorrido(
      id: 'r1',
      garitaId: 'g1',
      nombre: 'Línea 10 [T] Belloto 2000 - Las Rosas',
      colorValue: 0xFF1E88E5,
      linea: 'Línea 10',
      codigoVariante: 'T',
      nombreVariante: 'Belloto 2000 - Las Rosas',
      callesIda: const ['SERRANO', 'COVADONGA', 'SAN MARTIN', 'BLANCO ENCALADA'],
      callesVuelta: const ['ALTO EL YUGO', 'PANGUIPULLI', 'RAMON FREIRE'],
      ida: trayectoPrueba,
    );

    final linea10Variante1 = Recorrido(
      id: 'r2',
      garitaId: 'g1',
      nombre: 'Línea 10 [V-1] Troncos Viejos',
      colorValue: 0xFF1E88E5,
      linea: 'Línea 10',
      codigoVariante: 'V-1',
      nombreVariante: 'Troncos Viejos',
      callesIda: const ['ISIDORA', 'TRONCOS VIEJOS', 'VALENCIA'],
      callesVuelta: const ['VALENCIA', 'CAMINO TRONCAL', 'ISIDORA'],
      ida: trayectoPrueba,
    );

    final linea10Variante2 = Recorrido(
      id: 'r3',
      garitaId: 'g1',
      nombre: 'Línea 10 [V-2] Cumming',
      colorValue: 0xFF1E88E5,
      linea: 'Línea 10',
      codigoVariante: 'V-2',
      nombreVariante: 'Cumming',
      callesIda: const ['RICARDO CUMMING', 'CONDOR', 'ANIBAL PINTO'],
      callesVuelta: const ['MIRADOR', 'CUMMING', 'CENTENARIO'],
      ida: trayectoPrueba,
    );

    final lista = [linea10Troncal, linea10Variante1, linea10Variante2];

    List<Recorrido> buscar(String query) {
      return [
        for (final l in lista)
          if (matchesAllTokens(query, [
            l.nombre,
            l.linea,
            l.codigoVariante,
            l.nombreVariante,
            ...l.callesIda,
            ...l.callesVuelta,
          ]))
            l,
      ];
    }

    test('encuentra por código de variante específico', () {
      expect(buscar('V-1'), [linea10Variante1]);
      expect(buscar('V-2'), [linea10Variante2]);
      expect(buscar('[T]'), [linea10Troncal]);
    });

    test('encuentra por nombre de calle oficial de ida', () {
      final res = buscar('covadonga');
      expect(res, [linea10Troncal]);

      final resTroncos = buscar('troncos viejos');
      expect(resTroncos, [linea10Variante1]);
    });

    test('encuentra por nombre de calle oficial de vuelta', () {
      final res = buscar('panguipulli');
      expect(res, [linea10Troncal]);

      final resMirador = buscar('mirador');
      expect(resMirador, [linea10Variante2]);
    });

    test('encuentra por nombre de calle sin tildes ni mayúsculas', () {
      final res = buscar('san martin');
      expect(res, [linea10Troncal]);

      final resCumming = buscar('cumming');
      expect(resCumming, [linea10Variante2]);
    });
  });

  group('Pruebas de Estrés y Rendimiento (Stress Testing)', () {
    test('Estrés 1: Procesamiento masivo de 1.000 recorridos con 100 calles cada uno (100.000 calles)', () {
      final stopwatch = Stopwatch()..start();

      final random = Random(42);
      final nombresCalles = [
        'SERRANO', 'COVADONGA', 'SAN MARTIN', 'BAQUEDANO', 'LATORRE',
        'FREIRE', 'LOS CARRERA', 'BLANCO', 'CUMMING', 'VALENCIA',
        'TRONCOS VIEJOS', 'ISIDORA', 'PANGUIPULLI', 'JOTABECHE', 'ALTO EL YUGO',
      ];

      final recorridos = <Recorrido>[];
      for (var i = 0; i < 1000; i++) {
        final callesIda = List.generate(50, (_) => nombresCalles[random.nextInt(nombresCalles.length)]);
        final callesVuelta = List.generate(50, (_) => nombresCalles[random.nextInt(nombresCalles.length)]);

        recorridos.add(
          Recorrido(
            id: 'rec_$i',
            garitaId: 'garita_${i % 10}',
            nombre: 'Línea ${i % 20} [V-${i % 5}] Sector $i',
            colorValue: 0xFF1E88E5,
            linea: 'Línea ${i % 20}',
            codigoVariante: 'V-${i % 5}',
            nombreVariante: 'Sector $i',
            callesIda: callesIda,
            callesVuelta: callesVuelta,
            ida: trayectoPrueba,
            vuelta: trayectoPrueba,
          ),
        );
      }

      // Serialización masiva (toMap)
      final mapas = recorridos.map((r) => r.toMap()).toList();
      expect(mapas.length, 1000);

      // Deserialización masiva (fromMap)
      final recuperados = [
        for (var i = 0; i < mapas.length; i++)
          Recorrido.fromMap('rec_$i', mapas[i]),
      ];
      expect(recuperados.length, 1000);

      // Búsqueda en los 1.000 recorridos por una calle
      final coincidencias = [
        for (final r in recuperados)
          if (matchesAllTokens('san martin', [
            r.nombre,
            r.linea,
            r.codigoVariante,
            r.nombreVariante,
            ...r.callesIda,
            ...r.callesVuelta,
          ]))
            r,
      ];

      stopwatch.stop();

      // Verificar que se ejecutó sin errores
      expect(coincidencias.isNotEmpty, isTrue);
      // El benchmark debe ser ultrarrápido (menos de 1000ms para 100.000 operaciones en memoria)
      expect(stopwatch.elapsedMilliseconds, lessThan(1000));
    });

    test('Estrés 2: Parsing de cartola con 10.000 calles en ráfaga', () {
      final buffer = StringBuffer();
      for (var i = 0; i < 10000; i++) {
        buffer.write('CALLE_OFICIAL_$i; ');
      }
      final inputMasivo = buffer.toString();

      final stopwatch = Stopwatch()..start();
      final separadas = inputMasivo
          .split(RegExp(r'[;\n\r]+'))
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      stopwatch.stop();

      expect(separadas.length, 10000);
      expect(separadas.first, 'CALLE_OFICIAL_0');
      expect(separadas.last, 'CALLE_OFICIAL_9999');
      expect(stopwatch.elapsedMilliseconds, lessThan(200));
    });

    test('Estrés 3: Simulación de las 3 Cartolas Oficiales de la Línea 10 (PDF MTT)', () {
      // Cartola 1: Variante 2 (Alto El Yugo / Cumming)
      const cartolaV2Ida = 'ALTO EL YUGO; PANGUIPULLI; JOTABECHE; RAMON FREIRE; '
          'BLANCO ENCALADA; SAN MARTIN; SERRANO; RICARDO CUMMING; MIRADOR';
      const cartolaV2Vuelta = 'MIRADOR; RICARDO CUMMING; SERRANO; SAN MARTIN; '
          'BLANCO ENCALADA; RAMON FREIRE; JOTABECHE; PANGUIPULLI; ALTO EL YUGO';

      // Cartola 2: Troncal T (Alto El Yugo / Belloto 2000 / Las Rosas)
      const cartolaTIda = 'ALTO EL YUGO; PANGUIPULLI; JOTABECHE; RAMON FREIRE; '
          'AV. LOS CARRERA; LAS ROSAS; BELLOTO 2000; COVADONGA; SERRANO';
      const cartolaTVuelta = 'SERRANO; COVADONGA; BELLOTO 2000; LAS ROSAS; '
          'AV. LOS CARRERA; RAMON FREIRE; JOTABECHE; PANGUIPULLI; ALTO EL YUGO';

      // Cartola 3: Variante 1 (Isidora / Troncos Viejos)
      const cartolaV1Ida = 'ISIDORA; TRONCOS VIEJOS; VALENCIA; CAMINO TRONCAL; '
          'RAMON FREIRE; BLANCO ENCALADA; SAN MARTIN';
      const cartolaV1Vuelta = 'SAN MARTIN; BLANCO ENCALADA; RAMON FREIRE; '
          'CAMINO TRONCAL; VALENCIA; TRONCOS VIEJOS; ISIDORA';

      List<String> parsear(String txt) => txt
          .split(RegExp(r'[;\n\r]+'))
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();

      final recV2 = Recorrido(
        id: 'rec_linea10_v2',
        garitaId: 'garita_10',
        nombre: 'Línea 10 [V-2] Cumming - Alto El Yugo',
        colorValue: 0xFF1E88E5,
        linea: 'Línea 10',
        codigoVariante: 'V-2',
        nombreVariante: 'Cumming - Alto El Yugo',
        callesIda: parsear(cartolaV2Ida),
        callesVuelta: parsear(cartolaV2Vuelta),
        ida: trayectoPrueba,
        vuelta: trayectoPrueba,
      );

      final recT = Recorrido(
        id: 'rec_linea10_t',
        garitaId: 'garita_10',
        nombre: 'Línea 10 [T] Belloto 2000 - Las Rosas',
        colorValue: 0xFF1E88E5,
        linea: 'Línea 10',
        codigoVariante: 'T',
        nombreVariante: 'Belloto 2000 - Las Rosas',
        callesIda: parsear(cartolaTIda),
        callesVuelta: parsear(cartolaTVuelta),
        ida: trayectoPrueba,
        vuelta: trayectoPrueba,
      );

      final recV1 = Recorrido(
        id: 'rec_linea10_v1',
        garitaId: 'garita_10',
        nombre: 'Línea 10 [V-1] Troncos Viejos',
        colorValue: 0xFF1E88E5,
        linea: 'Línea 10',
        codigoVariante: 'V-1',
        nombreVariante: 'Troncos Viejos',
        callesIda: parsear(cartolaV1Ida),
        callesVuelta: parsear(cartolaV1Vuelta),
        ida: trayectoPrueba,
        vuelta: trayectoPrueba,
      );

      final lineasOficiales = [recV2, recT, recV1];

      for (final l in lineasOficiales) {
        expect(l.linea, 'Línea 10');
        expect(l.codigoVariante, isNotEmpty);
        expect(l.nombreVariante, isNotEmpty);
        expect(l.callesIda.length, greaterThanOrEqualTo(7));
        expect(l.callesVuelta.length, greaterThanOrEqualTo(7));
        expect(l.sigla, l.codigoVariante);
      }
    });
  });
}
