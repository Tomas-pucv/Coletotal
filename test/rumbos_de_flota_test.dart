import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:taxi1/models/colectivo_activo.dart';
import 'package:taxi1/services/rumbos_de_flota.dart';
import 'package:taxi1/utils/polyline.dart';

/// Hacia dónde va cada colectivo: se deduce en el teléfono de quien mira el
/// mapa, comparando cada posición con la anterior. La telemetría no lo trae.
void main() {
  // A esta latitud, 0.0001° son unos 11 m en latitud y 9,3 m en longitud.
  const lat = -33.0472;
  const lng = -71.4425;

  ColectivoActivo en(double latitud, double longitud, {String uid = 'u1'}) =>
      ColectivoActivo(
        uid: uid,
        idVehiculo: 'BBCC12',
        latitud: latitud,
        longitud: longitud,
      );

  double? rumbo(RumbosDeFlota rumbos, ColectivoActivo c) =>
      rumbos.aplicar([c]).single.rumbo;

  test('recién aparecido no tiene rumbo: todavía no se movió', () {
    expect(rumbo(RumbosDeFlota(), en(lat, lng)), isNull);
  });

  test('al avanzar, apunta hacia donde va', () {
    final rumbos = RumbosDeFlota();
    rumbo(rumbos, en(lat, lng));
    // Unos 28 m al este.
    expect(rumbo(rumbos, en(lat, lng + 0.0003)), closeTo(90, 0.5));
    // Y de ahí unos 33 m al sur.
    expect(rumbo(rumbos, en(lat - 0.0003, lng + 0.0003)), closeTo(180, 0.5));
  });

  test('detenido conserva el rumbo: el ruido del GPS no lo hace girar', () {
    final rumbos = RumbosDeFlota();
    rumbo(rumbos, en(lat, lng));
    rumbo(rumbos, en(lat, lng + 0.0003));
    // Unos 5 m hacia el norte: menos que el mínimo.
    expect(rumbo(rumbos, en(lat + 0.00005, lng + 0.0003)), closeTo(90, 0.5));
  });

  test('a paso lento, el rumbo sale cuando junta el mínimo', () {
    final rumbos = RumbosDeFlota();
    rumbo(rumbos, en(lat, lng));
    // Dos avances de unos 6 m al norte: el primero no alcanza; con el segundo
    // ya se movió 12 m desde donde se lo vio primero.
    expect(rumbo(rumbos, en(lat + 0.000055, lng)), isNull);
    expect(rumbo(rumbos, en(lat + 0.00011, lng)), closeTo(0, 0.5));
  });

  test('cada unidad tiene el suyo, y la que se va se olvida', () {
    final rumbos = RumbosDeFlota();
    rumbos.aplicar([en(lat, lng), en(lat, lng, uid: 'u2')]);
    final flota = rumbos.aplicar([
      en(lat, lng + 0.0003),
      en(lat + 0.0003, lng, uid: 'u2'),
    ]);
    expect(flota[0].rumbo, closeTo(90, 0.5));
    expect(flota[1].rumbo, closeTo(0, 0.5));

    // u2 termina su turno y más tarde vuelve: parte sin rumbo.
    rumbos.aplicar([en(lat, lng + 0.0003)]);
    final vuelve = rumbos.aplicar([
      en(lat, lng + 0.0003),
      en(lat + 0.0003, lng, uid: 'u2'),
    ]);
    expect(vuelve[0].rumbo, closeTo(90, 0.5));
    expect(vuelve[1].rumbo, isNull);
  });

  test('el rumbo no se publica: las reglas no lo conocen', () {
    final conRumbo = en(lat, lng).copyWith(rumbo: 90);
    expect(conRumbo.rumbo, 90);
    expect(conRumbo.toJson().containsKey('rumbo'), isFalse);
  });

  test('rumboEntre mide desde el norte, en sentido horario', () {
    const origen = LatLng(lat, lng);
    expect(rumboEntre(origen, const LatLng(lat + 0.001, lng)), closeTo(0, 0.1));
    expect(
      rumboEntre(origen, const LatLng(lat, lng + 0.001)),
      closeTo(90, 0.1),
    );
    expect(
      rumboEntre(origen, const LatLng(lat - 0.001, lng)),
      closeTo(180, 0.1),
    );
    expect(
      rumboEntre(origen, const LatLng(lat, lng - 0.001)),
      closeTo(270, 0.1),
    );
  });
}
