import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:taxi1/config/garita_config.dart';
import 'package:taxi1/models/recorrido.dart';
import 'package:taxi1/models/route_path.dart';
import 'package:taxi1/services/hybrid_route_optimizer.dart';
import 'package:taxi1/services/line_planner.dart';
import 'package:taxi1/utils/polyline.dart';

void main() {
  setUp(() {
    HybridRouteOptimizer.clearCache();
  });

  Recorrido buildRecorrido({
    required String id,
    required List<LatLng> idaPoints,
    List<LatLng>? vueltaPoints,
    bool activo = true,
  }) => Recorrido(
    id: id,
    garitaId: kGaritaPublica,
    nombre: 'Línea $id',
    colorValue: kRecorridoColors.first,
    activo: activo,
    ida: Trayecto(
      puntos: [idaPoints.first, idaPoints.last],
      geometria: encodePolyline(idaPoints),
      trazado: idaPoints,
    ),
    vuelta: vueltaPoints == null
        ? null
        : Trayecto(
            puntos: [vueltaPoints.first, vueltaPoints.last],
            geometria: encodePolyline(vueltaPoints),
            trazado: vueltaPoints,
          ),
  );

  group('Optimizador Híbrido — Pruebas obligatorias de especificación', () {
    test(
      '1. Filtro estricto DS 212: rechaza sentido inverso (j <= i) y avance < 100 m',
      () {
        // Caso 1A: Ruta solo de ida Oeste -> Este (5 km aprox).
        // Origen al Este (-71.425) y destino al Oeste (-71.465): todo par
        // dentro de W_max o W_fallback queda con j <= i.
        final rutaOesteEste = buildRecorrido(
          id: 'ds212_dir',
          idaPoints: const [
            LatLng(-33.045, -71.470),
            LatLng(-33.045, -71.420),
          ],
        );

        final resSentidoInverso = HybridRouteOptimizer.optimize(
          origin: const LatLng(-33.045, -71.425),
          destination: const LatLng(-33.045, -71.465),
          recorridos: [rutaOesteEste],
        );
        expect(resSentidoInverso.status, HybridPlanStatus.noFeasibleRoute);
        expect(resSentidoInverso.best, isNull);
        expect(resSentidoInverso.topCandidates, isEmpty);

        // Caso 1B: Ruta válida en dirección, pero largo total < 100 m (~89 m).
        final rutaCorta = buildRecorrido(
          id: 'ds212_short',
          idaPoints: const [
            LatLng(-33.04500, -71.4450),
            LatLng(-33.04580, -71.4450),
          ],
        );

        final resTramoCorto = HybridRouteOptimizer.optimize(
          origin: const LatLng(-33.04500, -71.4451),
          destination: const LatLng(-33.04580, -71.4451),
          recorridos: [rutaCorta],
          enableFallback: false,
        );
        expect(resTramoCorto.topCandidates, isEmpty);
        expect(resTramoCorto.best, isNull);

        // Caso 1C: Cuando hay candidatos válidos, todos cumplen j > i y veh >= 100 m.
        final resValido = HybridRouteOptimizer.optimize(
          origin: const LatLng(-33.045, -71.465),
          destination: const LatLng(-33.045, -71.425),
          recorridos: [rutaOesteEste],
        );
        expect(resValido.status, HybridPlanStatus.optimalFound);
        for (final c in resValido.topCandidates) {
          expect(c.downIndex, greaterThan(c.upIndex));
          expect(
            c.vehMeters,
            greaterThanOrEqualTo(HybridRouteOptimizer.kMinVehicularMeters),
          );
        }
      },
    );

    test(
      '2. Acoplamiento de 3 tramos: evita esquina más cercana si viola sentido o empeora Z',
      () {
        // Recorrido en U:
        // Tramo 1 (Oeste, baja al Sur): (-33.040,-71.4450) -> (-33.052,-71.4450)
        // Tramo 2 (Giro al Este):        (-33.052,-71.4450) -> (-33.052,-71.4435)
        // Tramo 3 (Este, sube al Norte): (-33.052,-71.4435) -> (-33.040,-71.4435)
        //
        // El origen (-33.0410, -71.4440) está a ~47 m del Tramo 3 (final del recorrido)
        // y a ~93 m del Tramo 1 (inicio del recorrido).
        // El destino (-33.0510, -71.4452) está al final del Tramo 1.
        // La esquina más cercana al origen está en Tramo 3 (después del destino),
        // por lo que el algoritmo debe acoplar los 3 tramos y subir en Tramo 1.
        final rutaEnU = buildRecorrido(
          id: 'u_route',
          idaPoints: const [
            LatLng(-33.0400, -71.4450),
            LatLng(-33.0520, -71.4450),
            LatLng(-33.0520, -71.4435),
            LatLng(-33.0400, -71.4435),
          ],
        );

        const origin = LatLng(-33.0410, -71.4440);
        const destination = LatLng(-33.0510, -71.4452);

        // El heurístico ingenuo de punto único más cercano fallaba aquí porque
        // proyectaba al origen en Tramo 3 (después de la bajada en Tramo 1).
        final nearestNaive = nearestOnPolyline(rutaEnU.ida.trazado, origin)!;
        expect(nearestNaive.punto.longitude, closeTo(-71.4435, 1e-4));

        final plan = HybridRouteOptimizer.optimize(
          origin: origin,
          destination: destination,
          recorridos: [rutaEnU],
        );

        expect(plan.status, HybridPlanStatus.optimalFound);
        expect(plan.best, isNotNull);
        final best = plan.best!;
        // Debe subir en el Tramo 1 (lon -71.4450), antes del destino en Tramo 1.
        expect(best.boardingNode.longitude, closeTo(-71.4450, 1e-4));
        expect(best.alightingNode.longitude, closeTo(-71.4450, 1e-4));
        expect(best.downIndex, greaterThan(best.upIndex));
        expect(best.totalCost, lessThan(plan.directWalkCost));

        // También LinePlanner.suggest debe entregar la sugerencia válida.
        final suggestions = LinePlanner.suggest(
          user: origin,
          destino: destination,
          recorridos: [rutaEnU],
        );
        expect(suggestions, hasLength(1));
        expect(suggestions.single.subida.longitude, closeTo(-71.4450, 1e-4));

        // Subcaso 2B: la esquina más cercana sí cumple j > i, pero obliga a
        // recorrer un rodeo largo; debe preferir otra esquina con menor Z global.
        final rutaConRodeo = buildRecorrido(
          id: 'loop_detour',
          idaPoints: const [
            LatLng(-33.0400, -71.4450),
            LatLng(-33.0450, -71.4450),
            LatLng(-33.0450, -71.4480),
            LatLng(-33.0406, -71.4480),
            LatLng(-33.0406, -71.4455),
            LatLng(-33.0550, -71.4455),
          ],
        );
        const originRodeo = LatLng(-33.0403, -71.4452);
        const destRodeo = LatLng(-33.0540, -71.4455);

        final planRodeo = HybridRouteOptimizer.optimize(
          origin: originRodeo,
          destination: destRodeo,
          recorridos: [rutaConRodeo],
        );
        expect(planRodeo.status, HybridPlanStatus.optimalFound);
        final bestRodeo = planRodeo.best!;
        // Evita subir en el primer tramo (lon -71.4450, ~19 m) por el rodeo de
        // ~1,5 km y sube en el tramo directo hacia el destino (lon -71.4455).
        expect(bestRodeo.boardingNode.longitude, closeTo(-71.4455, 1e-4));
        expect(bestRodeo.vehMeters, lessThan(1650.0));
      },
    );

    test(
      '3. Discretización de tramo recto largo (~500 m): nodos cada <= 60 m y progresivas consistentes',
      () {
        const pStart = LatLng(-33.0450, -71.4450);
        const pEnd = LatLng(-33.0495, -71.4450); // ~500.4 m al sur
        final expectedTotal = HybridRouteOptimizer.haversineMeters(pStart, pEnd);
        expect(expectedTotal, closeTo(500.4, 2.0));

        final rutaRecta = buildRecorrido(
          id: 'recta_500',
          idaPoints: const [pStart, pEnd],
        );
        final lut = DirectedRouteLut.fromPolyline(
          recorrido: rutaRecta,
          sentido: Sentido.ida,
          polyline: rutaRecta.ida.trazado,
        );

        final expectedSteps =
            (expectedTotal / HybridRouteOptimizer.kDiscretizationStepMeters)
                .ceil();
        expect(lut.nodes, hasLength(expectedSteps + 1));
        expect(lut.nodes.first, pStart);
        expect(lut.nodes.last, pEnd);
        expect(lut.cumulativeMeters.first, 0.0);
        expect(lut.totalLengthMeters, closeTo(expectedTotal, 0.5));

        for (var i = 1; i < lut.nodes.length; i++) {
          final segLen = HybridRouteOptimizer.haversineMeters(
            lut.nodes[i - 1],
            lut.nodes[i],
          );
          expect(
            segLen,
            lessThanOrEqualTo(
              HybridRouteOptimizer.kDiscretizationStepMeters + 1e-6,
            ),
          );
          expect(
            lut.cumulativeMeters[i],
            greaterThan(lut.cumulativeMeters[i - 1]),
          );
        }
      },
    );

    test(
      '4. Caminata directa: origen y destino a ~150 m activa recomendación directa',
      () {
        final ruta = buildRecorrido(
          id: 'direct_walk',
          idaPoints: const [
            LatLng(-33.0400, -71.4450),
            LatLng(-33.0500, -71.4450),
          ],
        );
        // Separados ~150 m en paralelo a la línea (~75 m al oeste del trazado).
        const origin = LatLng(-33.04500, -71.4458);
        const destination = LatLng(-33.04635, -71.4458);

        final distDirecta = HybridRouteOptimizer.haversineMeters(
          origin,
          destination,
        );
        expect(distDirecta, closeTo(150.1, 2.0));

        final plan = HybridRouteOptimizer.optimize(
          origin: origin,
          destination: destination,
          recorridos: [ruta],
        );

        expect(plan.status, HybridPlanStatus.directWalkPreferred);
        expect(plan.recommendDirectWalk, isTrue);
        expect(plan.hasRoute, isFalse);
        if (plan.best != null) {
          expect(
            plan.best!.totalCost,
            greaterThanOrEqualTo(plan.directWalkCost),
          );
        }

        final suggestions = LinePlanner.suggest(
          user: origin,
          destino: destination,
          recorridos: [ruta],
        );
        expect(suggestions, isEmpty);
      },
    );

    test(
      '5. Fallback > 1000 m: usuario a ~1300 m subrogados usa radio extendido sin fallar',
      () {
        // Ruta Norte -> Sur por lon -71.4450.
        final ruta = buildRecorrido(
          id: 'fallback_line',
          idaPoints: const [
            LatLng(-33.0400, -71.4450),
            LatLng(-33.0750, -71.4450),
          ],
        );
        // ~1040 m reales al oeste -> ~1300 m subrogados (1040 * 1.25).
        const origin = LatLng(-33.0420, -71.45615);
        const destination = LatLng(-33.0690, -71.4450);

        final plan = HybridRouteOptimizer.optimize(
          origin: origin,
          destination: destination,
          recorridos: [ruta],
        );

        expect(plan.status, HybridPlanStatus.optimalFound);
        expect(plan.isLongWalkFallback, isTrue);
        expect(plan.best, isNotNull);
        expect(plan.best!.walkAccessMeters, greaterThan(1000.0));
        expect(plan.best!.walkAccessMeters, lessThanOrEqualTo(2000.0));

        // Sin fallback habilitado, no encuentra ruta dentro de 1000 m.
        final sinFallback = HybridRouteOptimizer.optimize(
          origin: origin,
          destination: destination,
          recorridos: [ruta],
          enableFallback: false,
        );
        expect(sinFallback.status, HybridPlanStatus.noFeasibleRoute);
        expect(sinFallback.isLongWalkFallback, isFalse);

        // Si está más allá de 2000 m subrogados (~2500 m), retorna noFeasibleRoute sin lanzar excepción.
        final muyLejos = HybridRouteOptimizer.optimize(
          origin: const LatLng(-33.0420, -71.4700),
          destination: destination,
          recorridos: [ruta],
        );
        expect(muyLejos.status, HybridPlanStatus.noFeasibleRoute);
        expect(muyLejos.isLongWalkFallback, isTrue);
        expect(muyLejos.best, isNull);
      },
    );

    test(
      '6. Precisión Haversine: Estación Quilpué – Hospital de Quilpué y p1 == p2 -> 0.0 sin NaN',
      () {
        const estacionQuilpue = LatLng(-33.0456, -71.4450);
        const hospitalQuilpue = LatLng(-33.0497, -71.4307);

        final dist = HybridRouteOptimizer.haversineMeters(
          estacionQuilpue,
          hospitalQuilpue,
        );
        final distWalk = HybridRouteOptimizer.surrogateWalkMeters(
          estacionQuilpue,
          hospitalQuilpue,
        );

        // Distancia geodésica real entre ambos hitos (~1408 m).
        expect(dist, inInclusiveRange(1390.0, 1425.0));
        expect(
          distWalk,
          closeTo(dist * HybridRouteOptimizer.kTauTortuosity, 1e-6),
        );

        // Caso p1 == p2: exactamente 0.0 y jamás NaN.
        final mismoPunto = HybridRouteOptimizer.haversineMeters(
          estacionQuilpue,
          estacionQuilpue,
        );
        expect(mismoPunto.isNaN, isFalse);
        expect(mismoPunto, 0.0);
        expect(
          HybridRouteOptimizer.surrogateWalkMeters(
            estacionQuilpue,
            estacionQuilpue,
          ),
          0.0,
        );
      },
    );

    test(
      '7. Relay Nivel 1 -> Nivel 2 (verifyWithValhalla): consulta solo tramo peatonal y preserva cartola',
      () async {
        final ruta = buildRecorrido(
          id: 'relay_test',
          idaPoints: const [
            LatLng(-33.0400, -71.4450),
            LatLng(-33.0600, -71.4450),
          ],
        );
        const origin = LatLng(-33.0420, -71.4455);
        const destination = LatLng(-33.0580, -71.4455);

        final plan = HybridRouteOptimizer.optimize(
          origin: origin,
          destination: destination,
          recorridos: [ruta],
        );
        expect(plan.hasRoute, isTrue);
        final best = plan.best!;

        final calls = <(LatLng, LatLng)>[];
        final verified = await HybridRouteOptimizer.verifyWithValhalla(
          origin: origin,
          destination: destination,
          candidate: best,
          includeEgress: true,
          walkRouter: (from, to) async {
            calls.add((from, to));
            return RoutePath(
              points: [from, to],
              distanceMeters: 77.0,
              durationSeconds: 59.0,
              provider: 'Valhalla',
            );
          },
        );

        expect(calls, hasLength(2));
        expect(calls[0], (origin, best.boardingNode));
        expect(calls[1], (best.alightingNode, destination));
        expect(verified.exactWalkAccessMeters, 77.0);
        expect(verified.exactWalkEgressMeters, 77.0);
        expect(verified.vehicularSegment.first, best.boardingNode);
        expect(verified.vehicularSegment.last, best.alightingNode);
        expect(
          verified.vehicularSegment,
          hasLength(best.downIndex - best.upIndex + 1),
        );
      },
    );
  });
}
