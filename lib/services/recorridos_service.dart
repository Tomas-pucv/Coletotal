import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import 'package:taxi1/models/bus_stop.dart';
import 'package:taxi1/models/recorrido.dart';
import 'package:taxi1/services/osrm_client.dart';
import 'package:taxi1/services/stops_service.dart';

/// Los recorridos de la línea, para **todo el mundo**.
///
/// Antes sólo existían dentro de `GaritaService`, que únicamente escucha cuando
/// hay un administrador en sesión. Pero el pasajero también los necesita: son
/// la respuesta a "¿qué colectivos pasan por este paradero?" y "¿por dónde va
/// esa línea?". Mismo reparto que con los paraderos: la lectura pública vive
/// acá y `GaritaService` se queda sólo con las escrituras del administrador.
class RecorridosService extends ChangeNotifier {
  RecorridosService._();
  static final RecorridosService instance = RecorridosService._();

  static const _collection = 'recorridos';

  FirebaseFirestore get _db => FirebaseFirestore.instance;

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _sub;
  List<Recorrido> _recorridos = const [];

  /// Trazados ya calculados, por id de recorrido.
  ///
  /// El trazado se deriva de los paraderos llamando a OSRM, que es una petición
  /// de red por línea: sin caché, volver a abrir la misma línea la pediría otra
  /// vez. Se invalida entera cuando cambian los paraderos, porque mover uno
  /// cambia el trazado de todas las líneas que lo incluyen.
  final Map<String, List<LatLng>> _trazados = {};

  Recorrido? _selected;
  bool _loadingTrazado = false;

  List<Recorrido> get recorridos => _recorridos;

  /// Recorrido que el usuario está viendo dibujado en el mapa.
  Recorrido? get selected => _selected;
  bool get loadingTrazado => _loadingTrazado;

  /// Puntos del recorrido seleccionado. Vacío mientras se calcula.
  List<LatLng> get trazadoSeleccionado {
    if (_selected == null) return const [];
    final cached = _trazados[_selected!.id];
    if (cached != null) return cached;
    if (_selected!.trazado.length >= 2) return _selected!.trazado;
    return const [];
  }

  /// Las líneas que sirven a [paraderoId], que es lo que se le muestra al
  /// pasajero cuando toca un paradero.
  List<Recorrido> porParadero(String paraderoId) => _recorridos
      .where((r) => r.activo && r.paraderoIds.contains(paraderoId))
      .toList(growable: false);

  /// Todas las líneas de una garita, activas o no.
  ///
  /// Es lo que ve su administrador: para él un recorrido desactivado sigue
  /// existiendo y tiene que poder volver a encenderlo.
  List<Recorrido> porGarita(String garitaId) => _recorridos
      .where((r) => r.garitaId == garitaId)
      .toList(growable: false);

  Recorrido? byId(String id) {
    for (final r in _recorridos) {
      if (r.id == id) return r;
    }
    return null;
  }

  /// Abre el listener. Se llama una vez desde `main()`.
  void startListening() {
    if (_sub != null) return;
    _sub = _db.collection(_collection).snapshots().listen(
      (snapshot) {
        _recorridos = snapshot.docs
            .map((doc) => Recorrido.fromMap(doc.id, doc.data()))
            .toList(growable: false);

        // Un recorrido editado puede tener otros paraderos: su trazado viejo ya
        // no lo describe.
        _trazados.clear();
        if (_selected != null) {
          final fresh = byId(_selected!.id);
          // Si el administrador lo eliminó, se deja de dibujar en vez de
          // mostrar una línea que ya no existe.
          _selected = fresh;
          if (fresh != null) unawaited(_ensureTrazado(fresh));
        }
        notifyListeners();
      },
      onError: (Object e) {
        debugPrint('RecorridosService: no se pudo leer recorridos: $e');
      },
    );

    // Mover un paradero cambia el trazado de todas las líneas que lo tocan.
    StopsService.instance.addListener(_onStopsChanged);
  }

  void _onStopsChanged() {
    _trazados.clear();
    final current = _selected;
    if (current != null) unawaited(_ensureTrazado(current));
  }

  Future<void> stopListening() async {
    await _sub?.cancel();
    _sub = null;
    StopsService.instance.removeListener(_onStopsChanged);
  }

  // --- Selección y trazado -------------------------------------------------

  Future<void> select(Recorrido recorrido) async {
    if (_selected?.id == recorrido.id) return;
    _selected = recorrido;
    notifyListeners();
    await _ensureTrazado(recorrido);
  }

  void clearSelection() {
    if (_selected == null) return;
    _selected = null;
    _loadingTrazado = false;
    notifyListeners();
  }

  /// Puntos de los paraderos de [recorrido], en orden y saltándose los que ya
  /// no existan.
  List<LatLng> puntosDe(Recorrido recorrido) {
    final stops = StopsService.instance;
    final points = <LatLng>[];
    for (final id in recorrido.paraderoIds) {
      final stop = stops.byId(id);
      if (stop != null) points.add(stop.location);
    }
    return points;
  }

  List<BusStop> paraderosDe(Recorrido recorrido) {
    final stops = StopsService.instance;
    final result = <BusStop>[];
    for (final id in recorrido.paraderoIds) {
      final stop = stops.byId(id);
      if (stop != null) result.add(stop);
    }
    return result;
  }

  Future<void> _ensureTrazado(Recorrido recorrido) async {
    if (_trazados.containsKey(recorrido.id)) return;

    // Si el recorrido ya tiene una geometría precomputada válida que respeta
    // las calles y sentidos de tránsito, la usamos de inmediato:
    // 0 latencia, offline total y trazado exacto sin depender de OSRM en caliente.
    if (recorrido.trazado.length >= 2) {
      _trazados[recorrido.id] = recorrido.trazado;
      notifyListeners();
      return;
    }

    final puntos = puntosDe(recorrido);
    if (puntos.length < 2) {
      _trazados[recorrido.id] = const [];
      notifyListeners();
      return;
    }

    _loadingTrazado = true;
    notifyListeners();

    final trazado = await OsrmClient.routeThrough(puntos);

    // Si OSRM no responde se unen los paraderos con rectas. Es menos bonito,
    // pero deja ver por dónde va la línea, que es lo que se estaba preguntando;
    // no dibujar nada sería el peor de los resultados.
    _trazados[recorrido.id] = trazado ?? puntos;
    _loadingTrazado = false;
    notifyListeners();
  }

  @visibleForTesting
  void debugSetRecorridos(List<Recorrido> recorridos) {
    _recorridos = List.unmodifiable(recorridos);
    _trazados.clear();
    notifyListeners();
  }
}
