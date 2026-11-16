import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'package:taxi1/config/map_config.dart';

/// Mapa base offline: las teselas de OpenStreetMap que viajan dentro del APK.
///
/// Reemplaza a MapTiler, que pedía una clave, gastaba cuota en cada vista y
/// dejaba el mapa en blanco sin señal. Son dos archivos PMTiles generados por
/// `scripts/mapa_base/build.js`, que MapLibre lee directamente:
///
/// * `chile.pmtiles`: Chile continental hasta z10 (rutas y ciudades), la vista
///   general que se ve al alejarse o al salir de la región.
/// * `valparaiso.pmtiles`: la Región de Valparaíso de z11 a z15, con todas sus
///   calles. Se dibuja encima; donde no tiene teselas se ve la general.
///
/// MapLibre lee los archivos por tramos y Flutter sólo sabe entregar un asset
/// entero en memoria, así que se copian una vez a la carpeta de soporte de la
/// app, junto con los íconos y las tipografías de los estilos. Los estilos
/// traen esas rutas como `mapa-base://` y aquí se completan con la carpeta.
///
/// También copia los datos de ruteo de Valhalla (`ruteo_valparaiso.tar`), con
/// los que el teléfono calcula rutas sin conexión ([routingTilesPath]).
class BasemapService extends ChangeNotifier {
  BasemapService._();

  static final BasemapService instance = BasemapService._();

  /// Una instancia aparte de la de la app, para probar la copia: [load] se
  /// hace una sola vez por instancia.
  @visibleForTesting
  factory BasemapService.forTesting() => BasemapService._();

  static const _carpetaAssets = 'assets/map';
  static const _teselas = ['chile.pmtiles', 'valparaiso.pmtiles'];
  static const _ruteo = 'ruteo_valparaiso.tar';

  /// Prefijo de las rutas locales en los estilos (ver `build.js`).
  static const _prefijo = 'mapa-base://';

  /// Marca de la copia de íconos y tipografías.
  static const _marcaRecursos = 'recursos.huella';

  Future<void>? _loading;
  bool _ready = false;
  String _build = '';
  late String _light;
  late String _dark;
  late String _satellite;

  /// Por estilo, la capa de nombres bajo la que van las líneas de la app (ver
  /// [labelsLayerId]).
  final Map<String, String?> _capaDeNombres = {};

  /// Si ya se puede dibujar. Antes de eso los mapas muestran sólo su fondo.
  bool get isReady => _ready;

  /// Build de Protomaps del que salieron las teselas (`20261006`).
  String get build => _build;

  /// Ruta en el teléfono del grafo de calles de Valhalla, o `null` mientras
  /// se copia (o en la web, donde no hay Valhalla local). Mientras tanto las
  /// rutas se piden al servidor.
  String? get routingTilesPath => _routingTilesPath;
  String? _routingTilesPath;
  Future<void>? _copiaRuteo;

  /// Termina cuando la copia de los datos de ruteo terminó (o falló).
  @visibleForTesting
  Future<void> get routingCopy => _copiaRuteo ?? Future<void>.value();

  /// El estilo de MapLibre, como JSON, con las rutas de este teléfono.
  String style(MapStyle style, {required bool isDark}) => switch (style) {
    MapStyle.satellite => _satellite,
    MapStyle.normal => isDark ? _dark : _light,
  };

  /// La capa del estilo bajo la que van las líneas de la app, para que no
  /// tapen los nombres de calles y ciudades (`null` si el estilo no tiene).
  String? labelsLayerId(MapStyle style, {required bool isDark}) =>
      _capaDeNombres[this.style(style, isDark: isDark)];

  /// Abre el mapa base. Se llama desde `main()` sin esperarla: la primera vez
  /// tiene que copiar los archivos, y la app no debe quedarse en negro
  /// mientras tanto.
  Future<void> load() => _loading ??= _load();

  Future<void> _load() async {
    try {
      final manifiesto =
          jsonDecode(
                await rootBundle.loadString('$_carpetaAssets/basemap.json'),
              )
              as Map<String, dynamic>;
      final build = manifiesto['build'] as String? ?? '';

      final base = kIsWeb ? _baseWeb() : await _copiar(manifiesto, build);
      final light = await _leerEstilo('style_light.json', base);
      final dark = await _leerEstilo('style_dark.json', base);
      final satellite = await _leerEstilo('style_satellite.json', base);

      _build = build;
      _light = light;
      _dark = dark;
      _satellite = satellite;
      for (final estilo in [light, dark, satellite]) {
        _capaDeNombres[estilo] = _primeraCapaDeNombres(estilo);
      }
      _ready = true;
      notifyListeners();

      if (!kIsWeb) {
        // Después de mostrar el mapa: son otros 65 MB, y el mapa no los
        // necesita.
        unawaited(_copiaRuteo = _copiarRuteo(manifiesto, build));
        unawaited(_borrarCachesViejas());
      }
    } catch (e, stack) {
      // No debería pasar (los archivos vienen en el APK y un test los revisa),
      // pero si pasa el mapa queda con su color de fondo, lo demás sigue
      // funcionando y una llamada posterior a [load] lo vuelve a intentar.
      debugPrint('BasemapService: no se pudo abrir el mapa base: $e\n$stack');
      _loading = null;
    }
  }

  /// En la web no hay carpeta de la app: MapLibre GL JS pide los archivos al
  /// mismo servidor, donde Flutter publica los assets.
  String _baseWeb() => Uri.base.resolve('assets/$_carpetaAssets/').toString();

  /// Copia lo que falte y devuelve la carpeta como URL `file://` con `/` final.
  Future<String> _copiar(Map<String, dynamic> manifiesto, String build) async {
    final soporte = await getApplicationSupportDirectory();
    final carpeta = Directory('${soporte.path}/mapa_base');
    await carpeta.create(recursive: true);

    final tamanos = (manifiesto['archivos'] as Map).cast<String, int>();
    for (final nombre in _teselas) {
      await _copiaAlDia(
        carpeta,
        nombre,
        '$build:${tamanos[nombre]}',
        tamanos[nombre],
      );
    }

    final recursos = manifiesto['recursos'] as Map<String, dynamic>;
    final huella = recursos['huella'] as String;
    final marca = File('${carpeta.path}/$_marcaRecursos');
    if (!await marca.exists() || await marca.readAsString() != huella) {
      for (final nombre in (recursos['archivos'] as List).cast<String>()) {
        final destino = File('${carpeta.path}/$nombre');
        await destino.parent.create(recursive: true);
        await destino.writeAsBytes(await _bytes(nombre), flush: true);
      }
      await marca.writeAsString(huella, flush: true);
      debugPrint('BasemapService: íconos y tipografías copiados ($huella)');
    }

    return Uri.directory(carpeta.path).toString();
  }

  Future<void> _copiarRuteo(
    Map<String, dynamic> manifiesto,
    String build,
  ) async {
    try {
      final tamano = (manifiesto['archivos'] as Map)[_ruteo] as int?;
      if (tamano == null) return; // un APK sin datos de ruteo
      final soporte = await getApplicationSupportDirectory();
      final copia = await _copiaAlDia(
        Directory('${soporte.path}/mapa_base'),
        _ruteo,
        '$build:$tamano',
        tamano,
      );
      _routingTilesPath = copia.path;
    } catch (e) {
      debugPrint('BasemapService: no se copiaron los datos de ruteo: $e');
    }
  }

  /// Copia [nombre] del APK a [carpeta] si todavía no está o si cambió.
  ///
  /// Se compara contra lo que anota el manifiesto (build y tamaño), no contra
  /// la versión de la app: durante el desarrollo el mapa cambia sin que cambie
  /// la versión, y comparar con el asset mismo obligaría a leer 60 MB en cada
  /// arranque.
  Future<File> _copiaAlDia(
    Directory carpeta,
    String nombre,
    String marcaEsperada,
    int? tamano,
  ) async {
    final destino = File('${carpeta.path}/$nombre');
    final marca = File('${carpeta.path}/$nombre.build');
    if (await destino.exists() &&
        await marca.exists() &&
        await marca.readAsString() == marcaEsperada &&
        await destino.length() == tamano) {
      return destino;
    }

    // A un temporal y después se renombra: si la app se cierra a mitad de la
    // copia, no queda un archivo cortado que parezca bueno.
    final temporal = File('${destino.path}.tmp');
    await temporal.writeAsBytes(await _bytes(nombre), flush: true);
    await temporal.rename(destino.path);
    await marca.writeAsString(marcaEsperada, flush: true);
    debugPrint('BasemapService: $nombre copiado ($marcaEsperada)');
    return destino;
  }

  /// La capa de nombres bajo la que la app dibuja sus líneas: la primera de
  /// tipo `symbol` después de la última de tierra, agua o calles. Así la ruta
  /// y el trazado de las líneas quedan sobre las calles pero debajo de sus
  /// nombres y de los de las ciudades, que se siguen leyendo.
  ///
  /// No sirve tomar la primera `symbol` del estilo: la vista general pone sus
  /// nombres antes que la tierra del detalle, que los tapa, y una línea
  /// metida ahí quedaría tapada también.
  static String? _primeraCapaDeNombres(String estilo) {
    final capas = ((jsonDecode(estilo) as Map)['layers'] as List).cast<Map>();
    final ultimaNoNombre = capas.lastIndexWhere((c) => c['type'] != 'symbol');
    for (final capa in capas.skip(ultimaNoNombre + 1)) {
      if (capa['type'] == 'symbol') return capa['id'] as String;
    }
    return null;
  }

  Future<String> _leerEstilo(String nombre, String base) async {
    final json = await rootBundle.loadString('$_carpetaAssets/$nombre');
    return json.replaceAll(_prefijo, base);
  }

  /// Las cachés de los motores anteriores: flutter_map guardaba las teselas
  /// de MapTiler y de Esri, y vector_map_tiles cada tesela que dibujaba. Ya
  /// nadie las lee, y juntas ocupaban decenas de MB.
  Future<void> _borrarCachesViejas() async {
    try {
      final viejas = [
        Directory('${(await getApplicationCacheDirectory()).path}/fm_cache'),
        Directory('${(await getTemporaryDirectory()).path}/.vector_map'),
      ];
      for (final carpeta in viejas) {
        if (await carpeta.exists()) await carpeta.delete(recursive: true);
      }
    } catch (e) {
      debugPrint('BasemapService: no se borraron las cachés viejas: $e');
    }
  }

  static Future<Uint8List> _bytes(String nombre) async {
    final datos = await rootBundle.load('$_carpetaAssets/$nombre');
    return datos.buffer.asUint8List(datos.offsetInBytes, datos.lengthInBytes);
  }
}
