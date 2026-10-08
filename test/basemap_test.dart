import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:taxi1/config/map_config.dart';
import 'package:taxi1/data/quilpue_pois.dart';
import 'package:taxi1/models/bus_stop.dart';

/// El mapa base offline que viaja en el APK (ver `scripts/mapa_base/`).
///
/// Estos tests abren los archivos de verdad: si alguien regenera el mapa con
/// otra región, otro zoom o un estilo que apunte a un archivo que no está,
/// falla acá y no en el teléfono de un chofer, donde MapLibre sólo dejaría el
/// mapa en blanco o sin nombres.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<Uint8List> asset(String nombre) async {
    final datos = await rootBundle.load('assets/map/$nombre');
    return datos.buffer.asUint8List(datos.offsetInBytes, datos.lengthInBytes);
  }

  Future<bool> existe(String nombre) async {
    try {
      await rootBundle.load('assets/map/$nombre');
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>> json(String nombre) async =>
      jsonDecode(await rootBundle.loadString('assets/map/$nombre'))
          as Map<String, dynamic>;

  group('archivos PMTiles', () {
    late _Cabecera chile;
    late _Cabecera valparaiso;

    setUpAll(() async {
      chile = _Cabecera(await asset('chile.pmtiles'));
      valparaiso = _Cabecera(await asset('valparaiso.pmtiles'));
    });

    test('son teselas vectoriales con los zooms de cada capa', () {
      expect(chile.esPmtilesV3, isTrue);
      expect(valparaiso.esPmtilesV3, isTrue);
      expect(chile.tipo, _Cabecera.mvt);
      expect(valparaiso.tipo, _Cabecera.mvt);
      // La general hasta z10 y el detalle desde z11: los estilos esconden las
      // etiquetas de la general dentro de la región justo desde ese zoom.
      expect((chile.minZoom, chile.maxZoom), (0, 10));
      expect((valparaiso.minZoom, valparaiso.maxZoom), (11, 15));
    });

    test('la vista general cubre todo kChileBounds (más el mar al oeste)', () {
      // La cámara no sale de kChileBounds: si el archivo cubriera menos,
      // quedarían rincones de Chile en blanco.
      expect(chile.limites.containsBounds(kChileBounds), isTrue);
      expect(chile.limites.west, lessThan(kChileBounds.west));
    });

    test('el detalle cubre exactamente kDetailBounds', () {
      // kDetailBounds acota al buscador: tiene que ser la misma región.
      expect(valparaiso.limites.south, closeTo(kDetailBounds.south, 1e-5));
      expect(valparaiso.limites.west, closeTo(kDetailBounds.west, 1e-5));
      expect(valparaiso.limites.north, closeTo(kDetailBounds.north, 1e-5));
      expect(valparaiso.limites.east, closeTo(kDetailBounds.east, 1e-5));
    });

    test('todos los POIs y paraderos semilla caen en el mapa con calles', () {
      for (final poi in kQuilpuePois) {
        expect(kDetailBounds.contains(poi.location), isTrue, reason: poi.name);
      }
      for (final stop in quilpueBusStops) {
        expect(
          kDetailBounds.contains(stop.location),
          isTrue,
          reason: stop.name,
        );
      }
    });
  });

  group('manifiesto', () {
    test('anota el tamaño real de cada archivo de teselas', () async {
      // La app decide si recopiar el mapa mirando el manifiesto: si quedara
      // desfasado, se quedaría con la copia vieja o copiaría en cada arranque.
      final manifiesto = await json('basemap.json');
      final archivos = manifiesto['archivos'] as Map<String, dynamic>;
      for (final nombre in [
        'chile.pmtiles',
        'valparaiso.pmtiles',
        'ruteo_valparaiso.tar',
      ]) {
        expect(archivos[nombre], (await asset(nombre)).lengthInBytes);
      }
      expect(manifiesto['build'], matches(RegExp(r'^\d{8}$')));
    });

    test('los datos de ruteo son un tar de Valhalla con su índice', () async {
      // Valhalla abre el tar en el teléfono y busca las teselas en el índice
      // (`index.bin`), que tiene que ser el primer archivo.
      final tar = await asset('ruteo_valparaiso.tar');
      final primero = String.fromCharCodes(
        tar.sublist(0, 100).takeWhile((b) => b != 0),
      );
      expect(primero, 'index.bin');
      // Las teselas de la región, en los tres niveles de Valhalla.
      final texto = latin1.decode(tar, allowInvalid: true);
      for (final nivel in ['0/', '1/', '2/']) {
        expect(
          RegExp(
            '$nivel'
            r'\d{3}/',
          ).hasMatch(texto),
          isTrue,
          reason: 'nivel $nivel',
        );
      }
    });

    test('lista íconos y tipografías que existen en el APK', () async {
      final recursos =
          (await json('basemap.json'))['recursos'] as Map<String, dynamic>;
      final archivos = (recursos['archivos'] as List).cast<String>();
      expect(recursos['huella'], isNotEmpty);
      expect(archivos, isNotEmpty);
      for (final nombre in archivos) {
        expect(await existe(nombre), isTrue, reason: nombre);
      }
    });
  });

  group('estilos de MapLibre', () {
    const estilos = [
      'style_light.json',
      'style_dark.json',
      'style_satellite.json',
    ];

    for (final nombre in estilos) {
      test('$nombre apunta a archivos que vienen en el APK', () async {
        final estilo = await json(nombre);
        expect(estilo['version'], 8);

        final sources = estilo['sources'] as Map<String, dynamic>;
        expect(
          (sources['general'] as Map)['url'],
          'pmtiles://mapa-base://chile.pmtiles',
        );
        expect(
          (sources['detalle'] as Map)['url'],
          'pmtiles://mapa-base://valparaiso.pmtiles',
        );

        // Íconos: MapLibre pide `nombre.json` o `nombre@2x.json` según la
        // pantalla.
        final sprite = estilo['sprite'] as String;
        expect(sprite, startsWith('mapa-base://sprites/'));
        final base = sprite.replaceFirst('mapa-base://', '');
        for (final sufijo in ['.json', '.png', '@2x.json', '@2x.png']) {
          expect(await existe('$base$sufijo'), isTrue, reason: '$base$sufijo');
        }

        // Tipografías: cada una que usa una capa tiene su carpeta, al menos
        // con el bloque del latín (tildes y ñ incluidas).
        expect(estilo['glyphs'], 'mapa-base://fonts/{fontstack}/{range}.pbf');
        final fuentes = RegExp(r'"(noto-sans-[a-z]+)"')
            .allMatches(jsonEncode(estilo['layers']))
            .map((m) => m.group(1)!)
            .toSet();
        expect(fuentes, isNotEmpty);
        for (final fuente in fuentes) {
          expect(
            await existe('fonts/$fuente/0-255.pbf'),
            isTrue,
            reason: fuente,
          );
        }
        // Ninguna con el nombre original de Protomaps, que no se empaqueta.
        expect(jsonEncode(estilo['layers']), isNot(contains('Noto Sans')));

        // Cada capa usa una fuente que existe.
        for (final capa in (estilo['layers'] as List).cast<Map>()) {
          if (capa['source'] case final String fuente) {
            expect(sources, contains(fuente), reason: '${capa['id']}');
          }
        }
      });
    }

    test('la capa de detalle no pinta fondo encima de la general', () async {
      // Un fondo en el detalle taparía con gris liso a la general en todo
      // Chile fuera de la región.
      for (final nombre in estilos) {
        final capas = ((await json(nombre))['layers'] as List).cast<Map>();
        final fondos = capas.where((c) => c['type'] == 'background');
        expect(fondos.length, lessThanOrEqualTo(1), reason: nombre);
        // La general va debajo del detalle.
        final ultimaGeneral = capas.lastIndexWhere(
          (c) => c['source'] == 'general',
        );
        final primeraDetalle = capas.indexWhere(
          (c) => c['source'] == 'detalle',
        );
        expect(ultimaGeneral, lessThan(primeraDetalle), reason: nombre);
      }
    });

    test(
      'en la vista satelital las etiquetas de la general no se repiten',
      () async {
        // Sin tierra del detalle que las tape, dentro de la región cada
        // nombre salía dos veces: la general las esconde ahí desde z11.
        final capas = ((await json('style_satellite.json'))['layers'] as List)
            .cast<Map>();
        final etiquetas = capas.where(
          (c) =>
              c['source'] == 'general' &&
              c['type'] == 'symbol' &&
              ((c['maxzoom'] as num?) ?? 24) > 11,
        );
        expect(etiquetas, isNotEmpty);
        for (final capa in etiquetas) {
          final filtro = jsonEncode(capa['filter']);
          expect(filtro, contains('"within"'), reason: '${capa['id']}');
          expect(
            filtro,
            contains('["<",["zoom"],11]'),
            reason: '${capa['id']}',
          );
        }
      },
    );

    test(
      'en la de calles el detalle tapa la general con tierra opaca',
      () async {
        // Por eso ahí no hace falta el filtro (que pesaba 280 KB por estilo):
        // las etiquetas de la general quedan debajo de la tierra del detalle.
        for (final nombre in ['style_light.json', 'style_dark.json']) {
          final capas = ((await json(nombre))['layers'] as List).cast<Map>();
          final tierra = capas.firstWhere((c) => c['id'] == 'detalle_earth');
          expect(tierra['type'], 'fill', reason: nombre);
          final opacidad = (tierra['paint'] as Map?)?['fill-opacity'];
          expect(opacidad == null || opacidad == 1, isTrue, reason: nombre);
          expect(
            jsonEncode(capas),
            isNot(contains('"within"')),
            reason: nombre,
          );
        }
      },
    );

    test('sin íconos de comercios ni numeración de casas', () async {
      // Tapaban los nombres de las calles: en el centro casi no se veían.
      for (final nombre in estilos) {
        final ids = ((await json(nombre))['layers'] as List).cast<Map>().map(
          (c) => c['id'] as String,
        );
        expect(
          ids.where(
            (id) => id.endsWith('_pois') || id.endsWith('_address_label'),
          ),
          isEmpty,
          reason: nombre,
        );
        // Los nombres de las calles siguen.
        expect(ids, contains('detalle_roads_labels_minor'), reason: nombre);
      }
    });

    test('la foto aérea es la misma de la miniatura del selector', () async {
      final sources =
          (await json('style_satellite.json'))['sources']
              as Map<String, dynamic>;
      expect((sources['esri'] as Map)['tiles'], [kSatelliteTileUrlTemplate]);
    });

    test('hay miniatura del mapa de calles para cada tema', () async {
      expect(await existe('preview_light.png'), isTrue);
      expect(await existe('preview_dark.png'), isTrue);
    });
  });
}

/// La cabecera de un archivo PMTiles v3: 127 bytes al inicio, en
/// little-endian (https://github.com/protomaps/PMTiles/blob/main/spec/v3).
class _Cabecera {
  _Cabecera(Uint8List bytes) : _datos = ByteData.sublistView(bytes, 0, 127);

  static const mvt = 1;

  final ByteData _datos;

  bool get esPmtilesV3 =>
      String.fromCharCodes(
            Uint8List.sublistView(_datos.buffer.asUint8List(), 0, 7),
          ) ==
          'PMTiles' &&
      _datos.getUint8(7) == 3;

  int get tipo => _datos.getUint8(99);
  int get minZoom => _datos.getUint8(100);
  int get maxZoom => _datos.getUint8(101);

  double _grados(int offset) =>
      _datos.getInt32(offset, Endian.little) / 10000000;

  GeoBounds get limites => GeoBounds(
    west: _grados(102),
    south: _grados(106),
    east: _grados(110),
    north: _grados(114),
  );
}
