import 'dart:async';

import 'package:latlong2/latlong.dart';

import 'package:taxi1/config/map_config.dart';
import 'package:taxi1/models/colectivo_activo.dart';
import 'package:taxi1/models/recorrido.dart';
import 'package:taxi1/services/firebase_telemetria_service.dart';
import 'package:taxi1/services/recorridos_service.dart';

/// Simulador de flota en movimiento con 3 vehículos de prueba que circulan por
/// las 3 líneas originales de `RecorridosService` (`linea-10-t`, `linea-10-v1`,
/// `linea-10-v2`) para demostrar:
/// 1. El muestreo dinámico de rutas en el radio de 1 km (Modo Radar).
/// 2. La carga y descarga automática de una línea cuando un vehículo entra o
///    sale del radio de 1 km.
/// 3. El Modo Foco al tocar un vehículo (aislamiento de su línea, encuadre de
///    ruta + vehículo y expansión del radio a 2 km).
class SimulacionFlotaService {
  SimulacionFlotaService._();
  static final SimulacionFlotaService instance = SimulacionFlotaService._();

  static const Duration intervaloPaso = Duration(milliseconds: 1800);
  static const Distance _geo = Distance(roundResult: false);

  Timer? _timer;
  LatLng _centroAncla = kQuilpueCenter;
  int _paso = 0;
  bool _activo = false;

  bool get isRunning => _activo;
  int get pasoActual => _paso;

  /// Inicia los 3 vehículos simulados circulando sobre las 3 líneas originales
  /// activas en `RecorridosService.instance.publicas`.
  void start({LatLng? centro, bool conTimer = true}) {
    stop();
    _activo = true;
    _paso = 0;
    _centroAncla = centro ?? kQuilpueCenter;
    RecorridosService.instance.addListener(_onRecorridosChanged);
    _publicarEstadoActual();

    if (conTimer) {
      _timer = Timer.periodic(intervaloPaso, (_) => avanzarPaso());
    }
  }

  /// Detiene la simulación y limpia los colectivos simulados.
  void stop() {
    _timer?.cancel();
    _timer = null;
    if (_activo) {
      RecorridosService.instance.removeListener(_onRecorridosChanged);
      _activo = false;
      FirebaseTelemetriaService.instance.setSimulados(const []);
    }
  }

  /// Avanza un paso discreto en la trayectoria de los 3 vehículos.
  void avanzarPaso() {
    if (!_activo) return;
    _paso++;
    _publicarEstadoActual();
  }

  void _onRecorridosChanged() {
    if (!_activo) return;
    _publicarEstadoActual();
  }

  void _publicarEstadoActual() {
    final publicas = RecorridosService.instance.publicas;
    if (publicas.isEmpty) {
      FirebaseTelemetriaService.instance.setSimulados(const []);
      return;
    }

    final r0 = publicas[0];
    final r1 = publicas.length > 1 ? publicas[1] : publicas[0];
    final r2 = publicas.length > 2 ? publicas[2] : publicas.last;

    // Vehículo 1 (Línea 10 T): circula por el centro de Quilpué dentro del
    // radio de 1 km sobre el trazado de ida de la primera línea original.
    final tramo1 = _tramoDentroDeRadio(
      r0.ida.trazado,
      _centroAncla,
      maxMetros: 900,
    );

    // Vehículo 2 (Línea 10 V-1): circula dentro del radio de 1 km sobre el
    // trazado de vuelta (o ida si no tiene vuelta) de la segunda línea original.
    final base2 = (r1.vuelta != null && r1.vuelta!.dibujable)
        ? r1.vuelta!.trazado
        : r1.ida.trazado;
    final tramo2 = _tramoDentroDeRadio(
      base2,
      _centroAncla,
      maxMetros: 900,
    );

    // Vehículo 3 (Línea 10 V-2): circula sobre el tramo de la tercera línea
    // original que cruza el umbral de 1 km (entre ~500 m y ~1,45 km), mostrando
    // cómo su línea se carga al entrar al radio de 1 km y desaparece al salir.
    final tramo3 = _tramoCruzaUmbral1Km(r2, _centroAncla);

    final v1 = _interpolarPingPong(tramo1, _paso, offset: 1);
    final v2 = _interpolarPingPong(tramo2, _paso, offset: 2);
    final v3 = _interpolarPingPong(tramo3, _paso, offset: 0);

    FirebaseTelemetriaService.instance.setSimulados([
      ColectivoActivo(
        uid: 'sim_vehiculo_1',
        idVehiculo: 'BBCC10',
        garitaId: r0.garitaId,
        latitud: v1.latitude,
        longitud: v1.longitude,
        recorridoId: r0.id,
        recorridoNombre: r0.nombre,
      ),
      ColectivoActivo(
        uid: 'sim_vehiculo_2',
        idVehiculo: 'DDEE11',
        garitaId: r1.garitaId,
        latitud: v2.latitude,
        longitud: v2.longitude,
        recorridoId: r1.id,
        recorridoNombre: r1.nombre,
      ),
      ColectivoActivo(
        uid: 'sim_vehiculo_3',
        idVehiculo: 'FFGG12',
        garitaId: r2.garitaId,
        latitud: v3.latitude,
        longitud: v3.longitude,
        recorridoId: r2.id,
        recorridoNombre: r2.nombre,
      ),
    ]);
  }

  /// Extrae el tramo contiguo más largo de [trazado] cuyos puntos están dentro
  /// de [maxMetros] respecto de [centro], interpolado a 12 pasos sobre el
  /// propio trazado para que el avance sea fluido.
  static List<LatLng> _tramoDentroDeRadio(
    List<LatLng> trazado,
    LatLng centro, {
    double maxMetros = 900,
  }) {
    if (trazado.isEmpty) return [centro];
    final runs = <List<LatLng>>[];
    var actual = <LatLng>[];

    for (final p in trazado) {
      final d = _geo.as(LengthUnit.Meter, centro, p);
      if (d <= maxMetros) {
        actual.add(p);
      } else if (actual.isNotEmpty) {
        runs.add(actual);
        actual = <LatLng>[];
      }
    }
    if (actual.isNotEmpty) runs.add(actual);

    List<LatLng> mejor = const [];
    for (final r in runs) {
      if (r.length > mejor.length) mejor = r;
    }
    if (mejor.length < 2) {
      return _interpolarTramo(trazado, 12);
    }
    return _interpolarTramo(mejor, 12);
  }

  /// Extrae un tramo contiguo del recorrido [r] que cruza el umbral de 1 km
  /// (comenzando dentro de <= 650 m y saliendo hasta ~1,45 km, manteniéndose
  /// dentro del radio de 2 km de Modo Foco), interpolado exactamente a 10 pasos
  /// sobre el trazado original.
  static List<LatLng> _tramoCruzaUmbral1Km(Recorrido r, LatLng centro) {
    final candidatos = <List<LatLng>>[
      if (r.vuelta != null && r.vuelta!.dibujable) r.vuelta!.trazado,
      r.ida.trazado,
    ];

    // 1. Buscar un tramo entre 480 m y 1480 m (ej: ramal Av. Ricardo Cumming
    //    de la Línea 10 V-2 en Quilpué).
    final tramoCumming = _buscarTramoQueCruza(
      candidatos,
      centro,
      minMetros: 480,
      maxMetros: 1480,
    );
    if (tramoCumming != null) return _interpolarTramo(tramoCumming, 10);

    // 2. Respaldo general entre 200 m y 1500 m.
    final tramoGeneral = _buscarTramoQueCruza(
      candidatos,
      centro,
      minMetros: 200,
      maxMetros: 1500,
    );
    if (tramoGeneral != null) return _interpolarTramo(tramoGeneral, 10);

    return _interpolarTramo(r.ida.trazado, 10);
  }

  static List<LatLng>? _buscarTramoQueCruza(
    List<List<LatLng>> candidatos,
    LatLng centro, {
    required double minMetros,
    required double maxMetros,
  }) {
    List<LatLng>? mejor;
    for (final trazado in candidatos) {
      var actual = <LatLng>[];
      final runs = <List<LatLng>>[];
      for (final p in trazado) {
        final d = _geo.as(LengthUnit.Meter, centro, p);
        if (d >= minMetros && d <= maxMetros) {
          actual.add(p);
        } else if (actual.isNotEmpty) {
          runs.add(actual);
          actual = <LatLng>[];
        }
      }
      if (actual.isNotEmpty) runs.add(actual);

      for (final run in runs) {
        if (run.length < 2) continue;
        final tieneDentro = run.any(
          (p) => _geo.as(LengthUnit.Meter, centro, p) <= 900,
        );
        final tieneFuera = run.any(
          (p) => _geo.as(LengthUnit.Meter, centro, p) >= 1150,
        );
        if (tieneDentro && tieneFuera) {
          if (mejor == null || run.length < mejor.length) {
            mejor = run;
          }
        }
      }
    }

    if (mejor == null) return null;
    // Asegurar que el paso 0 comience dentro de 1 km y el último punto quede
    // fuera de 1 km (~1,4 km).
    final dInicio = _geo.as(LengthUnit.Meter, centro, mejor.first);
    final dFin = _geo.as(LengthUnit.Meter, centro, mejor.last);
    final orientado = dInicio > dFin
        ? mejor.reversed.toList(growable: false)
        : mejor;

    // Si el tramo pasa primero cerca del centro y luego se aleja, comenzar
    // desde el punto más cercano al centro para que avance monótonamente hacia
    // afuera del umbral de 1 km.
    var idxMin = 0;
    var dMin = double.infinity;
    for (var i = 0; i < orientado.length; i++) {
      final d = _geo.as(LengthUnit.Meter, centro, orientado[i]);
      if (d < dMin) {
        dMin = d;
        idxMin = i;
      }
    }
    final recortado = orientado.sublist(idxMin);
    return recortado.length >= 2 ? recortado : orientado;
  }

  /// Obtiene exactamente [cantidad] puntos distribuidos de forma uniforme a lo
  /// largo de la polilínea [puntos], preservando siempre el trazado original.
  static List<LatLng> _interpolarTramo(List<LatLng> puntos, int cantidad) {
    if (puntos.length <= 1 || cantidad <= 1) return puntos;
    final n = puntos.length - 1;
    final resultado = <LatLng>[];
    for (var i = 0; i < cantidad; i++) {
      final pos = i * n / (cantidad - 1);
      final idx = pos.floor();
      final frac = pos - idx;
      if (idx >= n || frac == 0) {
        resultado.add(puntos[idx.clamp(0, n)]);
      } else {
        final a = puntos[idx];
        final b = puntos[idx + 1];
        resultado.add(
          LatLng(
            a.latitude + (b.latitude - a.latitude) * frac,
            a.longitude + (b.longitude - a.longitude) * frac,
          ),
        );
      }
    }
    return resultado;
  }

  static LatLng _interpolarPingPong(
    List<LatLng> puntos,
    int paso, {
    int offset = 0,
  }) {
    if (puntos.isEmpty) return kQuilpueCenter;
    if (puntos.length == 1) return puntos.first;
    final n = puntos.length - 1;
    final ciclo = 2 * n;
    final k = (paso + offset) % ciclo;
    final idx = k <= n ? k : ciclo - k;
    return puntos[idx];
  }
}
