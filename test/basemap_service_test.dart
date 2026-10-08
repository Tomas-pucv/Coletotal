import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:taxi1/config/map_config.dart';
import 'package:taxi1/services/basemap_service.dart';

/// Carpetas de la app dentro de un temporal del test.
class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this.raiz);

  final Directory raiz;

  @override
  Future<String?> getApplicationSupportPath() async => '${raiz.path}/soporte';

  @override
  Future<String?> getTemporaryPath() async => '${raiz.path}/temporal';

  @override
  Future<String?> getApplicationCachePath() async => '${raiz.path}/cache';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory raiz;
  late Directory copias;

  setUp(() async {
    raiz = await Directory.systemTemp.createTemp('basemap_service_test');
    copias = Directory('${raiz.path}/soporte/mapa_base');
    PathProviderPlatform.instance = _FakePathProvider(raiz);
  });

  tearDown(() => raiz.delete(recursive: true));

  File copia(String nombre) => File('${copias.path}/$nombre');

  /// Abre el mapa y espera también la copia de los datos de ruteo, que sigue
  /// en segundo plano: si no, el test borra la carpeta mientras se escribe.
  Future<BasemapService> cargar() async {
    final service = BasemapService.forTesting();
    await service.load();
    await service.routingCopy;
    return service;
  }

  Future<List<String>> recursos() async {
    final manifiesto =
        jsonDecode(await rootBundle.loadString('assets/map/basemap.json'))
            as Map<String, dynamic>;
    return ((manifiesto['recursos'] as Map)['archivos'] as List).cast<String>();
  }

  /// Marca las copias como viejas: si una carga posterior las rehace, su
  /// fecha de modificación cambia.
  Future<void> envejecer() async {
    for (final nombre in ['chile.pmtiles', 'valparaiso.pmtiles']) {
      await copia(nombre).setLastModified(DateTime(2000));
    }
  }

  Future<bool> seRecopio(String nombre) async =>
      (await copia(nombre).lastModified()).year != 2000;

  test('la primera vez copia el mapa del APK y queda lista', () async {
    final service = BasemapService.forTesting();
    var avisos = 0;
    service.addListener(() => avisos++);

    await service.load();
    await service.routingCopy;

    expect(service.isReady, isTrue);
    expect(avisos, 1, reason: 'los mapas se redibujan al quedar lista');
    expect(service.build, matches(RegExp(r'^\d{8}$')));
    for (final nombre in ['chile.pmtiles', 'valparaiso.pmtiles']) {
      expect(await copia(nombre).exists(), isTrue);
      expect(
        await File('${copia(nombre).path}.build').readAsString(),
        startsWith('${service.build}:'),
      );
      expect(await File('${copia(nombre).path}.tmp').exists(), isFalse);
    }
    // MapLibre lee también los íconos y las tipografías desde la carpeta.
    for (final nombre in await recursos()) {
      expect(await copia(nombre).exists(), isTrue, reason: nombre);
    }
  });

  test('copia los datos de ruteo después de dejar listo el mapa', () async {
    final service = BasemapService.forTesting();
    await service.load();
    expect(service.isReady, isTrue);

    // La copia sigue en segundo plano: el mapa no la espera.
    await service.routingCopy;
    final ruta = service.routingTilesPath;
    expect(ruta, isNotNull);
    expect(ruta, copia('ruteo_valparaiso.tar').path);
    final manifiesto =
        jsonDecode(await rootBundle.loadString('assets/map/basemap.json'))
            as Map<String, dynamic>;
    expect(
      await File(ruta!).length(),
      (manifiesto['archivos'] as Map)['ruteo_valparaiso.tar'],
    );
  });

  test('los estilos apuntan a la copia y no a una ruta inventada', () async {
    final service = await cargar();
    final carpeta = Uri.directory(copias.path).toString();

    for (final style in MapStyle.values) {
      for (final isDark in [false, true]) {
        final json = service.style(style, isDark: isDark);
        expect(json, isNot(contains('mapa-base://')));
        final estilo = jsonDecode(json) as Map<String, dynamic>;
        final sources = estilo['sources'] as Map<String, dynamic>;
        expect(
          (sources['detalle'] as Map)['url'],
          'pmtiles://${carpeta}valparaiso.pmtiles',
        );
        expect(estilo['glyphs'], startsWith(carpeta));
        // Y lo que nombran existe en el teléfono.
        final sprite = Uri.parse('${estilo['sprite']}@2x.json');
        expect(await File.fromUri(sprite).exists(), isTrue);
        final glifos = Uri.parse(
          (estilo['glyphs'] as String)
              .replaceFirst('{fontstack}', 'noto-sans-regular')
              .replaceFirst('{range}', '0-255'),
        );
        expect(await File.fromUri(glifos).exists(), isTrue);
      }
    }
    expect(
      service.style(MapStyle.normal, isDark: true),
      isNot(service.style(MapStyle.normal, isDark: false)),
    );
  });

  test(
    'las líneas de la app van bajo los nombres, no bajo la tierra',
    () async {
      // Encima de los nombres los tapaban; debajo de la tierra del detalle
      // quedaban invisibles.
      final service = await cargar();
      for (final style in MapStyle.values) {
        for (final isDark in [false, true]) {
          final id = service.labelsLayerId(style, isDark: isDark);
          final capas =
              ((jsonDecode(service.style(style, isDark: isDark))
                          as Map)['layers']
                      as List)
                  .cast<Map>();
          final i = capas.indexWhere((c) => c['id'] == id);
          expect(i, isNonNegative, reason: '$style $isDark');
          expect(capas[i]['type'], 'symbol');
          // Después de ella no queda tierra, agua ni calles que tapen la línea.
          expect(
            capas.skip(i).where((c) => c['type'] != 'symbol'),
            isEmpty,
            reason: '$style $isDark',
          );
        }
      }
    },
  );

  test('en los arranques siguientes reutiliza la copia', () async {
    await cargar();
    await envejecer();

    final otra = await cargar();

    expect(otra.isReady, isTrue);
    expect(await seRecopio('chile.pmtiles'), isFalse);
    expect(await seRecopio('valparaiso.pmtiles'), isFalse);
  });

  test('si el APK trae otro mapa, la vuelve a copiar', () async {
    await cargar();
    await envejecer();
    // Como si la copia fuera de un build anterior del mapa.
    await File(
      '${copia('valparaiso.pmtiles').path}.build',
    ).writeAsString('20200101:1');

    await cargar();

    expect(await seRecopio('valparaiso.pmtiles'), isTrue);
    expect(await seRecopio('chile.pmtiles'), isFalse);
  });

  test('una copia cortada (otro tamaño) también se rehace', () async {
    await cargar();
    final cortada = copia('chile.pmtiles');
    final bytes = await cortada.readAsBytes();
    await cortada.writeAsBytes(bytes.sublist(0, bytes.length ~/ 2));
    await cortada.setLastModified(DateTime(2000));

    await cargar();

    expect(await seRecopio('chile.pmtiles'), isTrue);
    expect(await cortada.length(), bytes.length);
  });

  test(
    'si cambian los íconos o las tipografías, se vuelven a copiar',
    () async {
      await cargar();
      final fuente = copia((await recursos()).first);
      await fuente.delete();
      // Como si la copia fuera de un APK con otros recursos.
      await copia('recursos.huella').writeAsString('vieja');

      await cargar();

      expect(await fuente.exists(), isTrue);
    },
  );

  test('borra las cachés de flutter_map y vector_map_tiles', () async {
    // Las teselas que guardaban los motores anteriores: ya nadie las lee.
    final viejas = [
      Directory('${raiz.path}/cache/fm_cache'),
      Directory('${raiz.path}/temporal/.vector_map'),
    ];
    for (final carpeta in viejas) {
      await File('${carpeta.path}/tesela.png').create(recursive: true);
    }

    await cargar();
    // El borrado no se espera en el arranque.
    for (var i = 0; i < 50; i++) {
      if (!await viejas[0].exists() && !await viejas[1].exists()) break;
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }

    for (final carpeta in viejas) {
      expect(await carpeta.exists(), isFalse, reason: carpeta.path);
    }
  });
}
