import 'package:latlong2/latlong.dart';

import 'package:taxi1/models/colectivo_activo.dart';
import 'package:taxi1/utils/polyline.dart';

/// Hacia dónde va cada colectivo, deducido de por dónde venía.
///
/// La telemetría publica sólo la posición, una cada tres segundos. El rumbo
/// sale de comparar cada posición con la anterior, en el teléfono de quien mira
/// el mapa: así el colectivo se dibuja como un auto que apunta hacia donde va,
/// sin escribir nada nuevo en la base de datos ni depender de la versión de la
/// app que tenga el chofer.
class RumbosDeFlota {
  /// Lo mínimo que tiene que moverse una unidad para creerle el rumbo. Menos
  /// es el ruido del GPS de un auto detenido, que lo haría girar al azar en
  /// cada semáforo.
  static const double minimoMetros = 10;

  /// Por unidad, desde dónde se mide su próximo movimiento y el último rumbo
  /// que se le conoció.
  final Map<String, ({LatLng ancla, double? rumbo})> _porUid = {};

  /// [flota] con el rumbo de cada unidad que ya se movió lo suficiente. Una
  /// unidad detenida conserva el que traía; una recién aparecida no tiene
  /// ninguno hasta que avanza.
  List<ColectivoActivo> aplicar(List<ColectivoActivo> flota) {
    final vigentes = <String>{};
    final resultado = <ColectivoActivo>[];
    for (final colectivo in flota) {
      vigentes.add(colectivo.uid);
      final aqui = LatLng(colectivo.latitud, colectivo.longitud);
      final antes = _porUid[colectivo.uid];
      var rumbo = antes?.rumbo;
      if (antes == null) {
        _porUid[colectivo.uid] = (ancla: aqui, rumbo: null);
      } else if (metrosEntre(antes.ancla, aqui) >= minimoMetros) {
        rumbo = rumboEntre(antes.ancla, aqui);
        _porUid[colectivo.uid] = (ancla: aqui, rumbo: rumbo);
      }
      resultado.add(
        rumbo == null ? colectivo : colectivo.copyWith(rumbo: rumbo),
      );
    }
    // Una unidad que terminó su turno y vuelve más tarde parte sin rumbo: el
    // que tenía ya no dice nada.
    _porUid.removeWhere((uid, _) => !vigentes.contains(uid));
    return resultado;
  }
}
