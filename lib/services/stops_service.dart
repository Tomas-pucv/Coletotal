import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'package:taxi1/models/bus_stop.dart';
import 'package:taxi1/services/firestore_writes.dart';

/// Fuente única de paraderos para toda la app.
///
/// Reemplaza a las tres lecturas directas de la constante `quilpueBusStops`
/// (`map_screen`, `routes_screen` y `stop_history_service`), que era lo que
/// impedía que el administrador pudiera agregar un paradero: no había dónde
/// escribirlo.
///
/// **La lista se siembra en el constructor, de forma sincrónica.** No es un
/// detalle de estilo:
///
///  * la app dibuja paraderos en el primer frame, sin esperar a la red, y
///    sigue funcionando sin cobertura (RF-07-01);
///  * los tests que ya existían siguen pasando sin Firebase, porque abrir el
///    listener es una llamada aparte ([startListening]) que sólo hace `main()`.
class StopsService extends ChangeNotifier {
  StopsService._();
  static final StopsService instance = StopsService._();

  static const _collection = 'paraderos';

  /// Arranca con la semilla local; el primer snapshot no vacío la reemplaza.
  List<BusStop> _stops = List.unmodifiable(quilpueBusStops);

  /// Índice por id. `byId` se llama dentro de bucles (recorridos, historial,
  /// planificador) y antes recorría la lista entera en cada llamada.
  Map<String, BusStop> _byId = {for (final s in quilpueBusStops) s.id: s};

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _sub;
  bool _hasRemoteData = false;

  List<BusStop> get stops => _stops;

  /// Si lo que se está mostrando viene de Firestore o sigue siendo la semilla.
  bool get hasRemoteData => _hasRemoteData;

  BusStop? byId(String id) => _byId[id];

  /// Búsqueda por nombre, sólo para migrar historiales guardados antes de que
  /// los paraderos tuvieran id.
  BusStop? byName(String name) {
    for (final stop in _stops) {
      if (stop.name == name) return stop;
    }
    return null;
  }

  FirebaseFirestore get _db => FirebaseFirestore.instance;

  /// Abre el listener de Firestore. Se llama una sola vez, desde `main()`.
  void startListening() {
    if (_sub != null) return;
    _sub = _db
        .collection(_collection)
        .where('activo', isEqualTo: true)
        .snapshots()
        .listen(
          (snapshot) {
            // Una colección vacía **no** reemplaza la semilla: significa que
            // todavía nadie cargó los paraderos reales, y dejar al usuario sin
            // un solo paradero sería peor que mostrarle los de referencia. La
            // excepción es que ya hubiera datos reales y el servidor confirme
            // que no queda ninguno activo: eso sí hay que reflejarlo.
            if (snapshot.docs.isEmpty &&
                (!_hasRemoteData || snapshot.metadata.isFromCache)) {
              return;
            }

            final remote = snapshot.docs
                .map((doc) => BusStop.fromMap(doc.id, doc.data()))
                .toList(growable: false);

            // Reemplazo, nunca fusión: mezclarlos duplicaría cada paradero que
            // exista tanto en la semilla como en Firestore.
            _setStops(remote);
            _hasRemoteData = true;
            notifyListeners();
          },
          onError: (Object e) {
            debugPrint('StopsService: no se pudo leer paraderos: $e');
          },
        );
  }

  Future<void> stopListening() async {
    await _sub?.cancel();
    _sub = null;
  }

  void _setStops(List<BusStop> stops) {
    _stops = List.unmodifiable(stops);
    _byId = {for (final s in stops) s.id: s};
  }

  // --- Vista del administrador -----------------------------------------------

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _garitaSub;
  String? _garitaId;
  List<BusStop> _garitaStops = const [];
  bool _garitaLoaded = false;

  /// Todos los paraderos de la garita del administrador, **incluidos los dados
  /// de baja**: la lista pública sólo trae los activos, y con ella un paradero
  /// dado de baja desaparecía del panel y ya no había cómo reactivarlo.
  List<BusStop> get garitaStops => _garitaStops;
  bool get garitaStopsLoaded => _garitaLoaded;

  /// Escucha los paraderos de [garitaId], o deja de escuchar con `null`. Lo
  /// llama `GaritaService` al entrar y salir un administrador.
  void watchGarita(String? garitaId) {
    if (garitaId == _garitaId) return;
    _garitaSub?.cancel();
    _garitaSub = null;
    _garitaId = garitaId;
    _garitaStops = const [];
    _garitaLoaded = false;
    if (garitaId == null) {
      notifyListeners();
      return;
    }
    _garitaSub = _db
        .collection(_collection)
        .where('garitaId', isEqualTo: garitaId)
        .snapshots()
        .listen(
          (snapshot) {
            _garitaStops = snapshot.docs
                .map((doc) => BusStop.fromMap(doc.id, doc.data()))
                .toList(growable: false);
            _garitaLoaded = true;
            notifyListeners();
          },
          onError: (Object e) {
            debugPrint('StopsService: paraderos de la garita: $e');
            _garitaLoaded = true;
            notifyListeners();
          },
        );
  }

  // --- Escrituras del administrador ----------------------------------------
  //
  // Todas pasan por `confirmOrQueue`: sin señal, la escritura queda en la cola
  // local de Firestore y el editor puede cerrarse en vez de girar sin fin.

  /// Crea o actualiza un paradero. Devuelve el id resultante y si quedó
  /// confirmado o encolado.
  Future<(String, WriteOutcome)> upsert(BusStop stop) async {
    final data = {
      ...stop.toMap(),
      'actualizadoEn': FieldValue.serverTimestamp(),
    };

    // Un paradero semilla no existe en Firestore: editarlo crea el documento
    // real en vez de fallar con "no such document". El id se genera en el
    // teléfono (`doc()`) para conocerlo sin esperar al servidor: `add()` no
    // lo devuelve hasta que el servidor confirma.
    final isNew = stop.id.isEmpty || stop.id.startsWith('seed-');
    final ref = isNew
        ? _db.collection(_collection).doc()
        : _db.collection(_collection).doc(stop.id);
    final outcome = await confirmOrQueue(ref.set(data), label: 'paradero');
    return (ref.id, outcome);
  }

  /// Baja lógica.
  ///
  /// No se borra el documento: el historial del pasajero y los recorridos del
  /// administrador guardan ids de paraderos, y eliminarlos dejaría referencias
  /// colgando.
  Future<WriteOutcome> desactivar(BusStop stop) => _setActivo(stop, false);

  /// Deshace [desactivar].
  Future<WriteOutcome> reactivar(BusStop stop) => _setActivo(stop, true);

  Future<WriteOutcome> _setActivo(BusStop stop, bool activo) async {
    if (stop.id.isEmpty || stop.id.startsWith('seed-')) {
      return WriteOutcome.confirmed;
    }
    return confirmOrQueue(
      _db.collection(_collection).doc(stop.id).update({
        'activo': activo,
        'actualizadoEn': FieldValue.serverTimestamp(),
      }),
      label: 'paradero activo=$activo',
    );
  }

  /// Carga la semilla en Firestore. Pensado para el primer arranque de una
  /// garita nueva, disparado a mano por el administrador desde su panel.
  Future<(int, WriteOutcome)> importarSemilla(String garitaId) async {
    final batch = _db.batch();
    for (final stop in quilpueBusStops) {
      final ref = _db.collection(_collection).doc();
      batch.set(ref, {
        ...stop.copyWith(garitaId: garitaId).toMap(),
        'actualizadoEn': FieldValue.serverTimestamp(),
      });
    }
    final outcome = await confirmOrQueue(batch.commit(), label: 'semilla');
    return (quilpueBusStops.length, outcome);
  }

  /// Sustituye la lista sin tocar la red. Sólo para tests.
  @visibleForTesting
  void debugSetStops(List<BusStop> stops) {
    _setStops(stops);
    notifyListeners();
  }
}
