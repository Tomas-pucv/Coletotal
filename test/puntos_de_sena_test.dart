import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:taxi1/config/garita_config.dart';
import 'package:taxi1/config/map_config.dart';
import 'package:taxi1/models/recorrido.dart';
import 'package:taxi1/services/puntos_de_sena.dart';
import 'package:taxi1/utils/distance_format.dart';
import 'package:taxi1/utils/polyline.dart';

/// Los puntos de seña: un ícono por línea en el mapa del pasajero, en el punto
/// de su recorrido más cercano, en vez de los recorridos encimados.
void main() {
  // A esta latitud, 0.001° de longitud son unos 93 m.
  const lat0 = -33.040;
  const lng = -71.4425;

  /// Un trayecto recto por el meridiano [lon], de [desde] a [hasta].
  Trayecto recto(double desde, double hasta, double lon) {
    final puntos = [
      for (var i = 0; i <= 10; i++)
        LatLng(desde + (hasta - desde) * i / 10, lon),
    ];
    return Trayecto(
      puntos: [puntos.first, puntos.last],
      geometria: encodePolyline(puntos),
      trazado: puntos,
    );
  }

  /// Una variante: la ida baja por [lonIda] y el regreso sube por [lonVuelta].
  Recorrido variante(
    String id, {
    String linea = 'Línea 10',
    String codigo = 'T',
    double lonIda = lng,
    double? lonVuelta,
    int color = 0xFFB0338A,
    List<String> callesIda = const [],
    List<String> callesVuelta = const [],
  }) => Recorrido(
    id: id,
    garitaId: kGaritaPublica,
    nombre: '$linea $codigo',
    colorValue: color,
    linea: linea,
    codigoVariante: codigo,
    ida: recto(lat0, -33.090, lonIda),
    vuelta: recto(-33.090, lat0, lonVuelta ?? lonIda),
    callesIda: callesIda,
    callesVuelta: callesVuelta,
  );

  // El pasajero, a unos 93 m al oeste de la Línea 10 T.
  const pasajero = LatLng(-33.060, lng - 0.001);

  group('deVariante', () {
    test('el punto más cercano de cada sentido, primero la ida', () {
      final r = variante('t', lonVuelta: lng + 0.003);
      final senas = PuntosDeSena.deVariante(r, pasajero);
      expect(senas.map((s) => s.sentido), [Sentido.ida, Sentido.vuelta]);
      expect(senas[0].punto.latitude, closeTo(-33.060, 1e-6));
      expect(senas[0].punto.longitude, closeTo(lng, 1e-9));
      expect(senas[0].metros, closeTo(93, 2));
      // El regreso va por otra calle, 4 cuadras más allá.
      expect(senas[1].metros, closeTo(373, 5));
    });
  });

  group('lugaresDeIconos', () {
    Trayecto por(List<LatLng> puntos) => Trayecto(
      puntos: [puntos.first, puntos.last],
      geometria: encodePolyline(puntos),
      trazado: puntos,
    );
    Recorrido rama(String id, String codigo, List<LatLng> puntos) => Recorrido(
      id: id,
      garitaId: kGaritaPublica,
      nombre: 'Línea 10 $codigo',
      colorValue: 0xFFB0338A,
      linea: 'Línea 10',
      codigoVariante: codigo,
      ida: por(puntos),
    );
    // Un tronco común hacia el sur hasta la junta; ahí la T sigue al sur y la
    // V-1 dobla al este.
    const junta = LatLng(-33.070, lng);
    final t = rama('t', 'T', const [
      LatLng(lat0, lng),
      junta,
      LatLng(-33.090, lng),
    ]);
    final v1 = rama('v1', 'V-1', const [
      LatLng(lat0, lng),
      junta,
      LatLng(-33.070, lng + 0.02),
    ]);
    double metros(LatLng p, Recorrido r) =>
        nearestOnPolyline(r.ida.trazado, p)!.metros;

    test('cada ícono va sobre su variante, donde ya va sola, y no en la punta '
        'de su rama', () {
      final lugares = PuntosDeSena.lugaresDeIconos([t, v1]);
      expect(lugares.keys, unorderedEquals(['t', 'v1']));
      for (final (propia, otra) in [(t, v1), (v1, t)]) {
        final lugar = lugares[propia.id]!;
        expect(metros(lugar, propia), lessThan(1));
        // Lo bastante lejos de la otra para no confundirse con ella, pero lo
        // más cerca posible del centro: recién empezada la rama.
        expect(
          metros(lugar, otra),
          inInclusiveRange(
            PuntosDeSena.soledad - 30,
            PuntosDeSena.soledad + 60,
          ),
        );
      }
    });

    test('una variante sola va al medio de su recorrido', () {
      final lugar = PuntosDeSena.lugaresDeIconos([t])['t']!;
      expect(lugar.latitude, closeTo((lat0 - 33.090) / 2, 0.001));
      expect(metros(lugar, t), lessThan(1));
    });

    test('sin líneas, ningún ícono', () {
      expect(PuntosDeSena.lugaresDeIconos(const []), isEmpty);
    });
  });

  test('una línea sin número de línea se rotula con su sigla', () {
    final suelta = Recorrido(
      id: 'x',
      garitaId: kGaritaPublica,
      nombre: 'PRUEBA 7: Centro',
      colorValue: 0xFF00727C,
      ida: recto(lat0, -33.090, lng),
    );
    expect(PuntosDeSena.rotuloDeLinea(suelta), '7');
  });

  test('rótulo y etiqueta: "Línea 10" y su variante', () {
    expect(PuntosDeSena.rotuloDeLinea(variante('a')), '10');
    expect(
      PuntosDeSena.rotuloDeLinea(variante('b', linea: 'Línea 12a')),
      '12A',
    );
    expect(PuntosDeSena.etiqueta(variante('c', codigo: 'V-1')), '10 V-1');
    expect(PuntosDeSena.etiqueta(variante('d', codigo: '')), '10');
  });

  group('destino', () {
    final r = variante(
      't',
      callesIda: const [
        'QUILPUÉ',
        'SERRANO',
        'AV. MARGA MARGA',
        'ALTO EL YUGO',
      ],
      callesVuelta: const ['ALTO EL YUGO', 'MARGA MARGA', 'SERRANO', 'QUILPUÉ'],
    );

    test('la ida va hacia el último lugar de su cartola', () {
      expect(
        PuntosDeSena.destino(r, Sentido.ida),
        const DestinoSena.lugar('Alto el Yugo'),
      );
    });

    test('el regreso que termina en la garita va hacia el centro', () {
      expect(PuntosDeSena.destino(r, Sentido.vuelta)!.esCentro, isTrue);
    });

    test('sin cartola no se sabe', () {
      expect(PuntosDeSena.destino(variante('s'), Sentido.ida), isNull);
    });
  });

  group('foco', () {
    const yo = LatLng(-33.060, -71.4425);
    const cerca = LatLng(-33.061, -71.4425); // ~110 m
    const lejos = LatLng(-33.080, -71.4425); // ~2,2 km

    test('la posición del pasajero mientras el mapa lo sigue', () {
      expect(
        PuntosDeSena.foco(posicion: yo, centroMapa: lejos, siguiendo: true),
        yo,
      );
    });

    test('el centro del mapa si lo movió lejos de su posición', () {
      expect(
        PuntosDeSena.foco(posicion: yo, centroMapa: lejos, siguiendo: false),
        lejos,
      );
      // Moverlo un poco no cuenta: sigue mirando su barrio.
      expect(
        PuntosDeSena.foco(posicion: yo, centroMapa: cerca, siguiendo: false),
        yo,
      );
    });

    test('sin posición, el centro del mapa o Quilpué', () {
      expect(PuntosDeSena.foco(centroMapa: lejos, siguiendo: false), lejos);
      expect(PuntosDeSena.foco(siguiendo: true), kQuilpueCenter);
    });
  });

  test('la distancia de un ícono va redondeada', () {
    expect(redondearMetros(93), 90);
    expect(redondearMetros(176), 200);
    expect(redondearMetros(412), 400);
    expect(redondearMetros(1240), 1200);
    expect(redondearMetros(15240), 15000);
    expect(redondearMetros(double.nan), 0);
  });
}
