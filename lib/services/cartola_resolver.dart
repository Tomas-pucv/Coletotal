import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import 'package:taxi1/config/map_config.dart';
import 'package:taxi1/models/place_result.dart';
import 'package:taxi1/services/street_index.dart';

/// Representa un paso individual dentro de la secuencia de calles de una cartola MTT.
class PasoCartola {
  const PasoCartola({
    required this.id,
    required this.nombre,
    this.coordenadaManual,
    this.coordenadaResuelta,
    this.heading,
  });

  final String id;
  final String nombre;
  final LatLng? coordenadaManual;
  final LatLng? coordenadaResuelta;
  final double? heading;

  LatLng? get coordenada => coordenadaManual ?? coordenadaResuelta;
  bool get resuelto => coordenada != null;

  PasoCartola copyWith({
    String? nombre,
    LatLng? coordenadaManual,
    LatLng? coordenadaResuelta,
    double? heading,
    bool clearResuelta = false,
  }) => PasoCartola(
    id: id,
    nombre: nombre ?? this.nombre,
    coordenadaManual: coordenadaManual ?? this.coordenadaManual,
    coordenadaResuelta: clearResuelta
        ? null
        : (coordenadaResuelta ?? this.coordenadaResuelta),
    heading: clearResuelta ? null : (heading ?? this.heading),
  );
}

/// Resultado de resolver una secuencia completa de cartola.
class SecuenciaCartolaResuelta {
  const SecuenciaCartolaResuelta({
    required this.pasos,
    required this.waypoints,
    required this.headings,
  });

  final List<PasoCartola> pasos;
  final List<LatLng> waypoints;
  final List<double?> headings;
}

/// Resuelve secuencias de calles de cartola aisladas de POIs, usando cruces
/// precalculados, continuidad espacial sin arrastre ante calles inexistentes
/// y cálculo de rumbos (`heading`) para evitar giros en U en Valhalla/OSRM.
abstract final class CartolaResolver {
  static const double maxRadioPasoMetros = 5500;
  static const double minDistanciaCruceInteriorMetros = 40;
  static const double maxDistanciaCruceHeuristicoMetros = 120;
  static const double minSeparacionWaypointsMetros = 15;
  static const Distance _geo = Distance();

  static Future<SecuenciaCartolaResuelta> resolverSecuencia(
    List<PasoCartola> pasos, {
    LatLng anclaInicial = kQuilpueCenter,
  }) async {
    if (pasos.isEmpty) {
      return const SecuenciaCartolaResuelta(
        pasos: [],
        waypoints: [],
        headings: [],
      );
    }

    // Paso A: candidatos por calle con ancla que NO avanza ante no resueltas.
    var ancla = anclaInicial;
    final candPorPaso = <int, List<PlaceResult>>{};
    final anclaPorPaso = <int, LatLng>{};
    final resueltosIdx = <int>[];

    for (var i = 0; i < pasos.length; i++) {
      final paso = pasos[i];
      anclaPorPaso[i] = ancla;
      if (paso.coordenadaManual != null) {
        final manual = paso.coordenadaManual!;
        candPorPaso[i] = [
          PlaceResult(
            id: 'manual_${paso.id}',
            name: paso.nombre,
            address: 'Manual',
            location: manual,
          ),
        ];
        ancla = manual;
        resueltosIdx.add(i);
        continue;
      }

      final candidatos = await StreetIndex.searchCartolaCandidates(
        paso.nombre,
        near: ancla,
        maxDistanceMeters: maxRadioPasoMetros,
      );
      candPorPaso[i] = candidatos;
      if (candidatos.isNotEmpty) {
        ancla = candidatos.first.location;
        resueltosIdx.add(i);
      }
    }

    if (resueltosIdx.isEmpty) {
      return SecuenciaCartolaResuelta(
        pasos: [for (final p in pasos) p.copyWith(clearResuelta: true)],
        waypoints: const [],
        headings: const [],
      );
    }

    // Paso B: selección de tramos e intersecciones entre calles consecutivas.
    final seleccionados = <int, LatLng>{
      for (final idx in resueltosIdx) idx: candPorPaso[idx]!.first.location,
    };
    final crucesEntre = List<LatLng?>.filled(
      math.max(0, resueltosIdx.length - 1),
      null,
    );

    for (var k = 0; k < resueltosIdx.length - 1; k++) {
      final idxI = resueltosIdx[k];
      final idxJ = resueltosIdx[k + 1];
      final candsI = candPorPaso[idxI]!;
      final candsJ = candPorPaso[idxJ]!;
      final anclaPaso = anclaPorPaso[idxI] ?? anclaInicial;

      final crucePrecalculado = await _buscarCrucePrecalculado(
        pasos[idxI].nombre,
        pasos[idxJ].nombre,
        candsI,
        candsJ,
        anclaPaso,
      );

      if (crucePrecalculado != null) {
        crucesEntre[k] = crucePrecalculado;
        if (pasos[idxI].coordenadaManual == null) {
          seleccionados[idxI] = _masCercano(candsI, crucePrecalculado);
        }
        if (pasos[idxJ].coordenadaManual == null) {
          seleccionados[idxJ] = _masCercano(candsJ, crucePrecalculado);
        }
        continue;
      }

      // Heurística continua por pares de candidatos cuando no hay cruce en JSON.
      var mejorCosto = double.infinity;
      var mejorI = seleccionados[idxI]!;
      var mejorJ = seleccionados[idxJ]!;

      for (final pI in candsI) {
        for (final pJ in candsJ) {
          final costo =
              _geo.distance(pI.location, pJ.location) +
              0.35 * _geo.distance(anclaPaso, pI.location);
          if (costo < mejorCosto) {
            mejorCosto = costo;
            mejorI = pI.location;
            mejorJ = pJ.location;
          }
        }
      }

      if (pasos[idxI].coordenadaManual == null) seleccionados[idxI] = mejorI;
      if (pasos[idxJ].coordenadaManual == null) seleccionados[idxJ] = mejorJ;

      if (_geo.distance(mejorI, mejorJ) <= maxDistanciaCruceHeuristicoMetros) {
        crucesEntre[k] = _puntoMedio(mejorI, mejorJ);
      }
    }

    // Paso C: puntos interiores libres de giros en U y rumbos (heading).
    final coordFinalPorIdx = <int, LatLng>{};
    final headingPorIdx = <int, double?>{};

    for (var k = 0; k < resueltosIdx.length; k++) {
      final idx = resueltosIdx[k];
      final manual = pasos[idx].coordenadaManual;
      final base = seleccionados[idx]!;
      final entrada = k > 0 ? crucesEntre[k - 1] : null;
      final salida = k < resueltosIdx.length - 1 ? crucesEntre[k] : null;

      late final LatLng coord;
      if (manual != null) {
        coord = manual;
      } else if (entrada != null &&
          salida != null &&
          _geo.distance(entrada, salida) >= minDistanciaCruceInteriorMetros) {
        coord = _puntoMedio(entrada, salida);
      } else {
        coord = base;
      }
      coordFinalPorIdx[idx] = coord;

      if (entrada != null &&
          salida != null &&
          _geo.distance(entrada, salida) >= minSeparacionWaypointsMetros) {
        headingPorIdx[idx] = _bearingDegrees(entrada, salida);
      }
    }

    // Completar rumbos para extremos o pasos sin ambos cruces.
    for (var k = 0; k < resueltosIdx.length; k++) {
      final idx = resueltosIdx[k];
      if (headingPorIdx[idx] != null || resueltosIdx.length < 2) continue;

      final actual = coordFinalPorIdx[idx]!;
      if (k == 0) {
        final target = crucesEntre[0] ?? coordFinalPorIdx[resueltosIdx[1]]!;
        if (_geo.distance(actual, target) >= 1) {
          headingPorIdx[idx] = _bearingDegrees(actual, target);
        }
      } else if (k == resueltosIdx.length - 1) {
        final source =
            crucesEntre[k - 1] ?? coordFinalPorIdx[resueltosIdx[k - 1]]!;
        if (_geo.distance(source, actual) >= 1) {
          headingPorIdx[idx] = _bearingDegrees(source, actual);
        }
      } else {
        final prev = coordFinalPorIdx[resueltosIdx[k - 1]]!;
        final next = coordFinalPorIdx[resueltosIdx[k + 1]]!;
        if (_geo.distance(prev, next) >= 1) {
          headingPorIdx[idx] = _bearingDegrees(prev, next);
        }
      }
    }

    final pasosActualizados = <PasoCartola>[];
    for (var i = 0; i < pasos.length; i++) {
      final paso = pasos[i];
      final coord = coordFinalPorIdx[i];
      if (coord == null) {
        pasosActualizados.add(paso.copyWith(clearResuelta: true));
      } else {
        pasosActualizados.add(
          paso.copyWith(
            coordenadaResuelta: coord,
            heading: headingPorIdx[i],
          ),
        );
      }
    }

    final waypoints = <LatLng>[];
    final headings = <double?>[];
    for (final idx in resueltosIdx) {
      final pt = coordFinalPorIdx[idx]!;
      final hd = headingPorIdx[idx];
      if (waypoints.isEmpty ||
          _geo.distance(waypoints.last, pt) >= minSeparacionWaypointsMetros) {
        waypoints.add(pt);
        headings.add(hd);
      }
    }

    return SecuenciaCartolaResuelta(
      pasos: pasosActualizados,
      waypoints: waypoints,
      headings: headings,
    );
  }

  static Future<LatLng?> _buscarCrucePrecalculado(
    String rawA,
    String rawB,
    List<PlaceResult> candsA,
    List<PlaceResult> candsB,
    LatLng near,
  ) async {
    final nombresA = <String>{
      for (final c in candsA) c.name,
      rawA,
    };
    final nombresB = <String>{
      for (final c in candsB) c.name,
      rawB,
    };

    LatLng? mejor;
    var mejorDist = double.infinity;
    for (final a in nombresA) {
      for (final b in nombresB) {
        final cruces = await StreetIndex.findPrecomputedIntersections(a, b);
        for (final pt in cruces) {
          final d = _geo.distance(near, pt);
          if (d <= maxRadioPasoMetros && d < mejorDist) {
            mejorDist = d;
            mejor = pt;
          }
        }
      }
    }
    return mejor;
  }

  static LatLng _masCercano(List<PlaceResult> candidatos, LatLng destino) {
    var mejor = candidatos.first.location;
    var mejorDist = _geo.distance(mejor, destino);
    for (var i = 1; i < candidatos.length; i++) {
      final d = _geo.distance(candidatos[i].location, destino);
      if (d < mejorDist) {
        mejorDist = d;
        mejor = candidatos[i].location;
      }
    }
    return mejor;
  }

  static LatLng _puntoMedio(LatLng a, LatLng b) => LatLng(
    (a.latitude + b.latitude) / 2,
    (a.longitude + b.longitude) / 2,
  );

  static double _bearingDegrees(LatLng from, LatLng to) {
    final lat1 = from.latitudeInRad;
    final lat2 = to.latitudeInRad;
    final dLon = to.longitudeInRad - from.longitudeInRad;
    final y = math.sin(dLon) * math.cos(lat2);
    final x =
        math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLon);
    final deg = math.atan2(y, x) * 180.0 / math.pi;
    return (deg + 360.0) % 360.0;
  }
}
