import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';

import 'package:taxi1/models/place_result.dart';
import 'package:taxi1/utils/text_search.dart';

/// Índice offline de las calles de la Región de Valparaíso.
///
/// Sale de OpenStreetMap junto con el mapa base (`scripts/mapa_base/build.js`):
/// unas 25 mil calles, cada una con su comuna y un punto sobre ella. Con él el
/// buscador encuentra calles sin señal; antes sólo los 26 POIs de
/// `quilpue_pois.dart` funcionaban sin red.
///
/// Las calles no traen numeración: para "Freire 1234" sigue haciendo falta
/// Photon, que se consulta después si hay conexión.
abstract final class StreetIndex {
  static const String asset = 'assets/map/calles_valparaiso.json';
  static const String intersectionsAsset =
      'assets/map/intersecciones_valparaiso.json';

  static Future<List<_Calle>>? _calles;
  static Map<String, List<_Calle>>? _porComuna;
  static Future<Map<String, List<LatLng>>>? _intersecciones;

  /// Lee el índice en segundo plano. Se llama al arrancar, sin esperarla,
  /// para que la primera búsqueda no tenga que esperar a que se cargue.
  static Future<void> preload() => _cargar();

  /// Calles que contienen todas las palabras de [query], ordenadas por
  /// relevancia vial y cercanía a [near].
  static Future<List<PlaceResult>> search(
    String query, {
    required LatLng near,
    int limit = 6,
    bool exactWords = false,
    double? maxDistanceMeters,
  }) async {
    final parsedQuery = parseStreetQuery(query);
    final tokens = searchTokens(query);
    if (tokens.isEmpty || parsedQuery.baseTokens.isEmpty) return const [];

    final calles = await _cargar();
    final evaluadas = <(_Calle calle, double score)>[];
    for (final calle in calles) {
      if (exactWords) {
        if (!_matchesExactTokens(
          calle.tokensConComuna,
          parsedQuery.baseTokens,
        )) {
          continue;
        }
      } else {
        if (!containsAllTokens(calle.texto, tokens) &&
            !_matchesExactTokens(
              calle.tokensConComuna,
              parsedQuery.baseTokens,
            )) {
          continue;
        }
      }

      final dist = _distanciaMetros(near, calle);
      if (maxDistanceMeters != null && dist > maxDistanceMeters) continue;

      final score = _scoreCalle(
        calle,
        parsedQuery,
        dist,
        exactWords: exactWords,
      );
      evaluadas.add((calle, score));
    }

    evaluadas.sort((a, b) => a.$2.compareTo(b.$2));
    return [for (final item in evaluadas.take(limit)) item.$1.toPlace()];
  }

  /// Obtiene candidatos viales filtrados para pasos de cartola MTT: coincidencia
  /// por palabra completa, exclusión de vías menores salvo indicación explícita
  /// y acotación espacial a [maxDistanceMeters] dentro de [preferredComuna].
  static Future<List<PlaceResult>> searchCartolaCandidates(
    String nombreCalle, {
    required LatLng near,
    double maxDistanceMeters = 5500,
    String preferredComuna = 'Quilpué',
  }) async {
    final parsedQuery = parseStreetQuery(nombreCalle);
    if (parsedQuery.baseTokens.isEmpty) return const [];

    final comunaObj = normalizeForSearch(preferredComuna);
    final todas = await _cargar();
    final List<_Calle> calles;
    if (comunaObj.isNotEmpty) {
      final agrupadas = _agruparPorComuna(todas);
      calles = agrupadas[comunaObj] ?? const [];
    } else {
      calles = todas;
    }
    final evaluadas = <(_Calle calle, double score)>[];
    for (final calle in calles) {
      if (calle.esViaMenor && !parsedQuery.explicitMinorType) continue;
      if (!_matchesExactTokens(
        calle.parsed.baseTokens,
        parsedQuery.baseTokens,
      )) {
        continue;
      }

      final dist = _distanciaMetros(near, calle);
      if (dist > maxDistanceMeters) continue;

      final score = _scoreCalle(
        calle,
        parsedQuery,
        dist,
        exactWords: true,
      );
      evaluadas.add((calle, score));
    }

    evaluadas.sort((a, b) => a.$2.compareTo(b.$2));
    return [for (final item in evaluadas.take(10)) item.$1.toPlace()];
  }

  /// Consulta puntos de cruce precalculados entre [calleA] y [calleB] dentro
  /// de [comuna] en `assets/map/intersecciones_valparaiso.json`.
  static Future<List<LatLng>> findPrecomputedIntersections(
    String calleA,
    String calleB, {
    String comuna = 'Quilpué',
  }) async {
    final a = parseStreetQuery(calleA).baseTokens.join(' ');
    final b = parseStreetQuery(calleB).baseTokens.join(' ');
    if (a.isEmpty || b.isEmpty || a == b) return const [];

    final mapa = await _cargarIntersecciones();
    if (mapa.isEmpty) return const [];

    final comunaKey = normalizeForSearch(comuna);
    final clave = a.compareTo(b) < 0
        ? '$comunaKey|$a|$b'
        : '$comunaKey|$b|$a';
    return mapa[clave] ?? const [];
  }

  @visibleForTesting
  static void debugReset() {
    _calles = null;
    _porComuna = null;
    _intersecciones = null;
  }

  static Future<List<_Calle>> _cargar() => _calles ??= _leer();

  static Map<String, List<_Calle>> _agruparPorComuna(List<_Calle> todas) {
    final cached = _porComuna;
    if (cached != null) return cached;
    final map = <String, List<_Calle>>{};
    for (final c in todas) {
      (map[c.comunaNorm] ??= []).add(c);
    }
    return _porComuna = map;
  }

  static Future<Map<String, List<LatLng>>> _cargarIntersecciones() =>
      _intersecciones ??= _leerIntersecciones();

  static Future<List<_Calle>> _leer() async {
    try {
      final json = await rootBundle.loadString(asset);
      // Son 1,2 MB de JSON y 25 mil textos que normalizar: fuera del hilo de
      // la interfaz, o el teclado se traba en la primera búsqueda.
      return await compute(_parsear, json);
    } catch (e) {
      debugPrint('StreetIndex: no se pudo leer el índice de calles: $e');
      // Sin índice el buscador sigue con los POIs y Photon. Se olvida el
      // fallo para volver a intentarlo en la próxima búsqueda.
      _calles = null;
      return const [];
    }
  }

  static Future<Map<String, List<LatLng>>> _leerIntersecciones() async {
    try {
      final json = await rootBundle.loadString(intersectionsAsset);
      return await compute(_parsearIntersecciones, json);
    } catch (e) {
      debugPrint('StreetIndex: sin índice de intersecciones: $e');
      return const {};
    }
  }

  static List<_Calle> _parsear(String json) {
    final filas = jsonDecode(json) as List<dynamic>;
    final resultado = <_Calle>[];
    for (final (i, fila) in filas.indexed) {
      if (fila case [
        final String nombre,
        final String comuna,
        final num lat,
        final num lon,
        ...final List<dynamic> resto,
      ]) {
        final prioridad = resto.isNotEmpty && resto.first is num
            ? (resto.first as num).toInt()
            : 3;
        resultado.add(
          _Calle(
            id: i,
            nombre: nombre,
            comuna: comuna,
            latitud: lat.toDouble(),
            longitud: lon.toDouble(),
            prioridad: prioridad,
          ),
        );
      }
    }
    return resultado;
  }

  static Map<String, List<LatLng>> _parsearIntersecciones(String json) {
    final raw = jsonDecode(json);
    if (raw is! Map<String, dynamic>) return const {};
    final resultado = <String, List<LatLng>>{};
    for (final entry in raw.entries) {
      final lista = entry.value;
      if (lista is! List) continue;
      final puntos = <LatLng>[];
      for (final item in lista) {
        if (item case [final num lat, final num lon]) {
          puntos.add(LatLng(lat.toDouble(), lon.toDouble()));
        }
      }
      if (puntos.isNotEmpty) resultado[entry.key] = puntos;
    }
    return resultado;
  }

  static double _distanciaMetros(LatLng near, _Calle calle) {
    const radio = 6371000.0;
    final cosLat = math.cos(near.latitude * math.pi / 180.0);
    final dx = (calle.longitud - near.longitude) * (math.pi / 180.0) * cosLat;
    final dy = (calle.latitud - near.latitude) * (math.pi / 180.0);
    return math.sqrt(dx * dx + dy * dy) * radio;
  }

  static bool _matchesExactTokens(
    List<String> haystackTokens,
    List<String> needleTokens,
  ) {
    if (needleTokens.isEmpty) return true;
    if (haystackTokens.length < needleTokens.length) return false;
    if (needleTokens.length == 1) {
      return haystackTokens.contains(needleTokens.first);
    }
    if (!haystackTokens.contains(needleTokens.first)) return false;

    final usados = List<bool>.filled(haystackTokens.length, false);
    for (final q in needleTokens) {
      var encontrado = false;
      for (var i = 0; i < haystackTokens.length; i++) {
        if (!usados[i] && haystackTokens[i] == q) {
          usados[i] = true;
          encontrado = true;
          break;
        }
      }
      if (!encontrado) return false;
    }
    return true;
  }

  static double _scoreCalle(
    _Calle calle,
    NormalizedStreetQuery query,
    double distMetros, {
    required bool exactWords,
  }) {
    var score = distMetros;
    if (calle.esViaMenor && !query.explicitMinorType) {
      score += 2500.0;
    }
    final mismosTokens =
        calle.parsed.baseTokens.length == query.baseTokens.length &&
        _matchesExactTokens(calle.parsed.baseTokens, query.baseTokens);
    if (mismosTokens) {
      score -= 800.0;
    } else if (!exactWords &&
        _matchesExactTokens(calle.parsed.baseTokens, query.baseTokens)) {
      score -= 300.0;
    }
    score += (calle.prioridad - 3) * 150.0;
    return score;
  }
}

class _Calle {
  _Calle({
    required this.id,
    required this.nombre,
    required this.comuna,
    required this.latitud,
    required this.longitud,
    required this.prioridad,
  }) : texto = normalizeForSearch('$nombre $comuna'),
       parsed = parseStreetQuery(nombre),
       comunaNorm = normalizeForSearch(comuna),
       comunaTokens = parseStreetQuery(comuna).allTokens {
    esViaMenor = parsed.explicitMinorType;
    tokensConComuna = [...parsed.allTokens, ...comunaTokens];
  }

  final int id;
  final String nombre;
  final String comuna;
  final double latitud;
  final double longitud;
  final int prioridad;

  /// Nombre y comuna normalizados una sola vez, al cargar.
  final String texto;
  final NormalizedStreetQuery parsed;
  final String comunaNorm;
  final List<String> comunaTokens;
  late final bool esViaMenor;
  late final List<String> tokensConComuna;

  PlaceResult toPlace() => PlaceResult(
    id: 'calle_$id',
    name: nombre,
    address: '$comuna, Región de Valparaíso',
    location: LatLng(latitud, longitud),
  );
}
