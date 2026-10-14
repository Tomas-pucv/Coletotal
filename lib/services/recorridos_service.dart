import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'package:taxi1/config/garita_config.dart';
import 'package:taxi1/models/recorrido.dart';

/// Las líneas de colectivo, para **todo el mundo**.
///
/// El pasajero y el chofer ven sólo las públicas ([publicas]): las activas de
/// la garita [kGaritaPublica]. El administrador ve todas las de su garita
/// ([porGarita]); las escrituras son de `GaritaService`.
///
/// El trazado de cada sentido viene calculado desde Firestore (lo calcula el
/// editor de la garita al guardar), así que dibujar una línea no pide nada a
/// ningún enrutador: funciona igual sin señal.
class RecorridosService extends ChangeNotifier {
  RecorridosService._();
  static final RecorridosService instance = RecorridosService._();

  static const _collection = 'recorridos';

  FirebaseFirestore get _db => FirebaseFirestore.instance;

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _sub;
  List<Recorrido> _recorridos = const [];

  Recorrido? _selected;
  Sentido? _selectedSentido;
  bool _loaded = false;

  /// Todas las líneas que llegaron, de todas las garitas.
  List<Recorrido> get recorridos => _recorridos;

  /// Si ya llegó el primer snapshot. Mientras no, una lista vacía significa
  /// "todavía no sé", no "no hay líneas".
  bool get loaded => _loaded;

  /// Lo que ven el pasajero y el chofer: las líneas activas y dibujables de la
  /// garita pública, por nombre.
  List<Recorrido> get publicas =>
      _recorridos
          .where((r) => r.garitaId == kGaritaPublica && r.activo && r.isValid)
          .toList(growable: false)
        ..sort((a, b) => a.nombre.compareTo(b.nombre));

  /// Todas las líneas de una garita, activas o no.
  ///
  /// Es lo que ve su administrador: para él una línea apagada sigue existiendo
  /// y tiene que poder volver a encenderla.
  List<Recorrido> porGarita(String garitaId) =>
      _recorridos.where((r) => r.garitaId == garitaId).toList(growable: false);

  /// Línea que el usuario está viendo dibujada en el mapa.
  Recorrido? get selected => _selected;

  /// Sentido elegido de [selected], o `null` para dibujar los dos (cuando se
  /// eligió la línea en la pestaña Líneas y no un viaje).
  Sentido? get selectedSentido => _selectedSentido;

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
            _recorridos = snapshot.docs
                .map((doc) => Recorrido.fromMap(doc.id, doc.data()))
                .toList(growable: false);
            _loaded = true;
            // Si el administrador la editó, se dibuja la versión nueva; si la
            // borró, se deja de dibujar una línea que ya no existe.
            if (_selected != null) {
              _selected = byId(_selected!.id);
              if (_selected == null) _selectedSentido = null;
            }
            notifyListeners();
          },
          onError: (Object e) {
            debugPrint('RecorridosService: no se pudo leer recorridos: $e');
          },
        );
  }

  Future<void> stopListening() async {
    await _sub?.cancel();
    _sub = null;
  }

  /// Dibuja [recorrido] en el mapa: entero, o sólo [sentido].
  ///
  /// Con [encuadrar], el mapa además mueve la cámara para mostrarla completa:
  /// lo pide la pestaña Líneas. Tocar un colectivo en el mapa no lo pide,
  /// porque alejaría la cámara del colectivo que se acaba de tocar.
  void select(Recorrido recorrido, {Sentido? sentido, bool encuadrar = false}) {
    final misma = _selected?.id == recorrido.id && _selectedSentido == sentido;
    if (misma && !encuadrar) return;
    _selected = recorrido;
    _selectedSentido = sentido;
    _encuadrePendiente = encuadrar;
    notifyListeners();
  }

  bool _encuadrePendiente = false;

  /// Si quien eligió la línea pidió mostrarla completa. Devuelve `true` una
  /// sola vez por pedido.
  bool tomarEncuadre() {
    final pendiente = _encuadrePendiente;
    _encuadrePendiente = false;
    return pendiente;
  }

  void clearSelection() {
    if (_selected == null) return;
    _selected = null;
    _selectedSentido = null;
    notifyListeners();
  }

  @visibleForTesting
  void debugSetRecorridos(List<Recorrido> recorridos) {
    _recorridos = List.unmodifiable(recorridos);
    _loaded = true;
    notifyListeners();
  }
}
