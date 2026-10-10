import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import 'package:taxi1/data/serrano_recorridos.dart';
import 'package:taxi1/models/bus_stop.dart';
import 'package:taxi1/models/recorrido.dart';
import 'package:taxi1/services/routing.dart';
import 'package:taxi1/services/stops_service.dart';

/// Los recorridos de la línea, para **todo el mundo**.
///
/// En el transporte de taxis colectivos, los recorridos se estructuran por
/// variantes y cartolas de ida/vuelta. Los datos están disponibles fuera de
/// línea con la semilla oficial de Transportes Serrano y se sincronizan en vivo
/// con Firestore si hay red.
class RecorridosService extends ChangeNotifier {
  RecorridosService._();
  static final RecorridosService instance = RecorridosService._();

  static const _collection = 'recorridos';

  FirebaseFirestore get _db => FirebaseFirestore.instance;

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _sub;
  List<Recorrido> _recorridos = List.unmodifiable(kSerranoRecorridosSeed);

  /// Trazados ya calculados, por id de recorrido.
  final Map<String, List<LatLng>> _trazados = {};

  Recorrido? _selected;
  bool _loadingTrazado = false;
  bool _loaded = true;

  List<Recorrido> get recorridos => _recorridos;

  /// Si ya llegó el primer snapshot.
  bool get loaded => _loaded;

  /// Recorrido que el usuario está viendo dibujado en el mapa.
  Recorrido? get selected => _selected;
  bool get loadingTrazado => _loadingTrazado;

  /// Puntos del recorrido seleccionado (trazado de ida o trazado principal).
  List<LatLng> get trazadoSeleccionado {
    if (_selected == null) return const [];
    final cached = _trazados[_selected!.id];
    if (cached != null) return cached;
    if (_selected!.trazado.length >= 2) return _selected!.trazado;
    return const [];
  }

  /// Puntos de la vuelta del recorrido seleccionado.
  List<LatLng> get trazadoVueltaSeleccionado {
    if (_selected == null) return const [];
    return _selected!.trazadoVuelta;
  }

  /// Recorridos que pertenecen a una variante específica.
  List<Recorrido> porVariante(String varianteId) => _recorridos
      .where((r) => r.activo && r.varianteId == varianteId)
      .toList(growable: false);

  /// Filtra y ordena los recorridos por cercanía a la traza vial del usuario.
  List<Recorrido> filtrar({
    String? varianteId,
    String? searchQuery,
    LatLng? userLocation,
  }) {
    var resultado = _recorridos.where((r) => r.activo).toList();

    if (varianteId != null &&
        varianteId.isNotEmpty &&
        varianteId != 'todas' &&
        varianteId != 'all') {
      resultado = resultado.where((r) => r.varianteId == varianteId).toList();
    }

    if (searchQuery != null && searchQuery.trim().isNotEmpty) {
      resultado = resultado.where((r) => r.matchesQuery(searchQuery)).toList();
    }

    if (userLocation != null) {
      resultado.sort((a, b) {
        final da = a.distanceFrom(userLocation);
        final db = b.distanceFrom(userLocation);
        return da.compareTo(db);
      });
    }

    return resultado;
  }

  /// Las líneas que sirven a [paraderoId].
  List<Recorrido> porParadero(String paraderoId) => _recorridos
      .where((r) => r.activo && r.paraderoIds.contains(paraderoId))
      .toList(growable: false);

  /// Todas las líneas de una garita, activas o no.
  List<Recorrido> porGarita(String garitaId) =>
      _recorridos.where((r) => r.garitaId == garitaId).toList(growable: false);

  Recorrido? byId(String id) {
    for (final r in _recorridos) {
      if (r.id == id) return r;
    }
    return null;
  }

  /// Abre el listener. Se llama una vez desde `main()`.
  void startListening() {
    if (_sub != null) return;
    _sub = _db
        .collection(_collection)
        .snapshots()
        .listen(
          (snapshot) {
            if (snapshot.docs.isNotEmpty) {
              _recorridos = snapshot.docs
                  .map((doc) => Recorrido.fromMap(doc.id, doc.data()))
                  .toList(growable: false);
            } else if (_recorridos.isEmpty) {
              _recorridos = List.unmodifiable(kSerranoRecorridosSeed);
            }
            _loaded = true;

            _trazados.clear();
            if (_selected != null) {
              final fresh = byId(_selected!.id);
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
    // 0 latencia, offline total y trazado exacto sin depender de la red.
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

    final trazado = (await Routing.linePath(puntos))?.points;

    // Si ningún enrutador responde se unen los paraderos con rectas. Es menos
    // bonito, pero deja ver por dónde va la línea, que es lo que se estaba
    // preguntando; no dibujar nada sería el peor de los resultados.
    _trazados[recorrido.id] = trazado ?? puntos;
    // Si mientras tanto el usuario eligió otra línea, el indicador de carga es
    // de esa otra petición y no se apaga acá.
    if (_selected?.id == recorrido.id) _loadingTrazado = false;
    notifyListeners();
  }

  @visibleForTesting
  void debugSetRecorridos(List<Recorrido> recorridos) {
    _recorridos = List.unmodifiable(recorridos);
    _loaded = true;
    _trazados.clear();
    notifyListeners();
  }
}
