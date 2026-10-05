import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:taxi1/models/bus_stop.dart';
import 'package:taxi1/services/preferences_service.dart';
import 'package:taxi1/services/stops_service.dart';

/// Historial de paraderos consultados.
///
/// Da contenido real a la preferencia "Guardar historial", que hasta ahora era
/// un interruptor que se guardaba en disco y no afectaba absolutamente nada.
///
/// Guarda **ids**, no nombres. Antes bastaba el nombre porque la lista de
/// paraderos era una constante inmutable; ahora la edita el administrador, y un
/// paradero al que se le corrige el nombre habría desaparecido del historial.
class StopHistoryService extends ChangeNotifier {
  StopHistoryService._();
  static final StopHistoryService instance = StopHistoryService._();

  static const _key = 'stop_history';

  /// Cuántos paraderos recientes se recuerdan. Cinco entra sin scroll en la
  /// fila de sugerencias y evita que el historial tape la lista completa.
  static const int maxEntries = 5;

  List<String> _recentIds = const [];
  bool _loaded = false;
  bool _listening = false;

  bool get isLoaded => _loaded;

  Future<void> load() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getStringList(_key) ?? const [];

    final stops = StopsService.instance;
    final migrated = migrateHistory(
      stored,
      byId: stops.byId,
      byName: stops.byName,
    );
    _recentIds = List.unmodifiable(migrated);
    if (!listEquals(migrated, stored)) await prefs.setStringList(_key, migrated);

    // Cuando llegan los paraderos de Firestore, los ids del historial recién
    // se pueden resolver, y la pestaña Paraderos tiene que redibujarse.
    if (!_listening) {
      _listening = true;
      stops.addListener(_onStopsChanged);
    }

    _loaded = true;
    notifyListeners();
  }

  /// Convierte un historial guardado al formato actual.
  ///
  /// Las entradas que resuelven **por nombre** (historiales de cuando se
  /// guardaban nombres) pasan a ser ids. Lo que no resuelve **se conserva**.
  ///
  /// Antes se descartaba, y eso borraba el historial en cada arranque en frío:
  /// `load()` corre cuando sólo están cargados los paraderos semilla, así que
  /// ningún id de Firestore resolvía todavía y la "migración" los eliminaba a
  /// todos y lo guardaba en disco. "Recientes" sólo sobrevivía dentro de una
  /// misma sesión. Los ids que de verdad ya no existen se podan en
  /// [_onStopsChanged], cuando se conocen los paraderos reales.
  @visibleForTesting
  static List<String> migrateHistory(
    List<String> stored, {
    required BusStop? Function(String id) byId,
    required BusStop? Function(String name) byName,
  }) {
    final seen = <String>{};
    final result = <String>[];
    for (final entry in stored) {
      final id = byId(entry) != null ? entry : (byName(entry)?.id ?? entry);
      if (seen.add(id)) result.add(id);
    }
    return result.length > maxEntries ? result.sublist(0, maxEntries) : result;
  }

  void _onStopsChanged() {
    final stops = StopsService.instance;
    if (stops.hasRemoteData) {
      // Con los paraderos reales ya cargados, un id que no resuelve es un
      // paradero dado de baja (o una semilla reemplazada): sobra.
      final vigentes = _recentIds
          .where((id) => stops.byId(id) != null)
          .toList(growable: false);
      if (vigentes.length != _recentIds.length) {
        _recentIds = List.unmodifiable(vigentes);
        SharedPreferences.getInstance().then(
          (prefs) => prefs.setStringList(_key, vigentes),
        );
      }
    }
    notifyListeners();
  }

  /// Paraderos recientes, del más reciente al más antiguo.
  ///
  /// Devuelve vacío si el usuario desactivó el historial, de modo que apagar la
  /// preferencia oculta el historial existente sin borrarlo. Los ids que ya no
  /// resuelven (paraderos dados de baja) se omiten en vez de mostrarse rotos.
  List<BusStop> get recentStops {
    if (!PreferencesService.instance.historyEnabled) return const [];
    final stops = <BusStop>[];
    for (final id in _recentIds) {
      final stop = StopsService.instance.byId(id);
      if (stop != null) stops.add(stop);
    }
    return stops;
  }

  bool get hasHistory => _recentIds.isNotEmpty;

  /// Registra una consulta. No hace nada si el historial está desactivado.
  Future<void> record(BusStop stop) async {
    if (!PreferencesService.instance.historyEnabled) return;

    final updated = [
      stop.id,
      ..._recentIds.where((id) => id != stop.id),
    ].take(maxEntries).toList(growable: false);

    if (listEquals(updated, _recentIds)) return;

    _recentIds = updated;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_key, updated);
    notifyListeners();
  }

  Future<void> clear() async {
    if (_recentIds.isEmpty) return;
    _recentIds = const [];
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
    notifyListeners();
  }
}
