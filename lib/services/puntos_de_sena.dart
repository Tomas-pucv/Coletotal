import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import 'package:taxi1/config/map_config.dart';
import 'package:taxi1/models/recorrido.dart';
import 'package:taxi1/services/line_planner.dart';
import 'package:taxi1/utils/polyline.dart';

/// Dónde hacerle seña a un sentido de una línea: el punto de su trazado más
/// cercano a un foco (el pasajero, o el centro del mapa si se alejó).
///
/// Los colectivos no tienen paraderos: paran donde se les hace la seña. Este
/// punto hace de paradero virtual, el más a mano en ese momento.
class PuntoDeSena {
  const PuntoDeSena({
    required this.recorrido,
    required this.sentido,
    required this.punto,
    required this.metros,
  });

  final Recorrido recorrido;
  final Sentido sentido;
  final LatLng punto;

  /// Desde el foco, en línea recta.
  final double metros;

  DestinoSena? get destino => PuntosDeSena.destino(recorrido, sentido);
}

/// Hacia dónde va un sentido: un lugar de la cartola o el centro (la garita).
/// Sin cartola no se sabe, y se dice "ida" o "regreso".
class DestinoSena {
  const DestinoSena.centro() : lugar = null;
  const DestinoSena.lugar(String this.lugar);

  /// `null` si es el centro.
  final String? lugar;

  bool get esCentro => lugar == null;

  @override
  bool operator ==(Object other) =>
      other is DestinoSena && other.lugar == lugar;

  @override
  int get hashCode => lugar.hashCode;
}

/// Un extremo de una línea: donde empieza o termina uno de sus sentidos.
class Terminal {
  const Terminal({required this.punto, this.lugar});

  final LatLng punto;

  /// Cómo lo llama la cartola, o `null` si la línea no la tiene.
  final DestinoSena? lugar;
}

/// Los puntos de seña de las líneas, y dónde va el ícono de cada variante en
/// el mapa del pasajero. En vez de dibujar todos los recorridos encima (con las
/// tres variantes de la Línea 10 por las mismas calles, el mapa se volvía
/// ilegible), un ícono fijo por variante; al tocarlo se dibuja entera.
abstract final class PuntosDeSena {
  /// Hasta dónde un punto de seña queda a una caminata razonable: más lejos no
  /// se propone la ruta a pie.
  static const double radio = LinePlanner.maxCaminata;

  /// Desde qué distancia de las demás líneas un tramo cuenta como propio de
  /// una variante: ahí su ícono ya no se confunde con el de otra.
  static const double soledad = 400;

  /// Cada cuántos metros se miran los trazados para ubicar los íconos.
  static const double _paso = 50;

  /// Desde dónde se buscan los puntos de seña: la posición del pasajero, salvo
  /// que haya movido el mapa a más de [alejado] metros de ella (está mirando
  /// otra parte de la ciudad); entonces, el centro del mapa. Sin posición,
  /// también el centro.
  static LatLng foco({
    LatLng? posicion,
    LatLng? centroMapa,
    required bool siguiendo,
    double alejado = 1000,
  }) {
    if (posicion == null) return centroMapa ?? kQuilpueCenter;
    if (!siguiendo &&
        centroMapa != null &&
        const Distance().as(LengthUnit.Meter, posicion, centroMapa) > alejado) {
      return centroMapa;
    }
    return posicion;
  }

  /// El punto de seña de cada sentido de [recorrido], primero la ida.
  static List<PuntoDeSena> deVariante(Recorrido recorrido, LatLng foco) => [
    for (final (sentido, trayecto) in recorrido.trayectos)
      if (nearestOnPolyline(trayecto.trazado, foco) case final cerca?)
        PuntoDeSena(
          recorrido: recorrido,
          sentido: sentido,
          punto: cerca.punto,
          metros: cerca.metros,
        ),
  ];

  /// Dónde va el ícono de cada variante de [lineas], por id: en el tramo donde
  /// va más sola, a [soledad] metros o más de las demás si puede, para que los
  /// íconos no se tapen y cada uno insinúe hacia dónde va su variante. De esos
  /// tramos, en el punto más cercano al centro de la red: así se ven sin tener
  /// que alejar tanto el mapa.
  ///
  /// Depende sólo de los trazados: el ícono no se mueve con el pasajero ni con
  /// el mapa.
  static Map<String, LatLng> lugaresDeIconos(List<Recorrido> lineas) {
    final todos = [
      for (final r in lineas)
        for (final (_, t) in r.trayectos) ...t.trazado,
    ];
    if (todos.isEmpty) return const {};
    // En metros, sobre un plano: a la escala de una ciudad el error no se
    // nota, y medir es mucho más rápido que sobre la esfera.
    final kx = 111320 * math.cos(todos.first.latitude * math.pi / 180);
    const ky = 110540.0;
    math.Point<double> plano(LatLng p) =>
        math.Point(p.longitude * kx, p.latitude * ky);

    final muestras = {
      for (final r in lineas)
        r.id: [
          for (final (_, t) in r.trayectos)
            ..._muestrear([for (final p in t.trazado) plano(p)]),
        ],
    };
    final red = [for (final m in muestras.values) ...m];
    final centro = math.Point(
      red.fold(0.0, (suma, p) => suma + p.x) / red.length,
      red.fold(0.0, (suma, p) => suma + p.y) / red.length,
    );

    final lugares = <String, LatLng>{};
    for (final r in lineas) {
      final otras = [
        for (final o in lineas)
          if (o.id != r.id) ...muestras[o.id]!,
      ];
      math.Point<double>? mejor;
      var mejorSoledad = -1.0;
      var mejorAlCentro = double.infinity;
      for (final p in muestras[r.id]!) {
        // Al cuadrado y con tope: pasado el tope, todas valen lo mismo y
        // decide la cercanía al centro.
        var sola = soledad * soledad;
        for (final q in otras) {
          final d = p.squaredDistanceTo(q);
          if (d < sola) sola = d;
        }
        final alCentro = p.squaredDistanceTo(centro);
        if (sola > mejorSoledad ||
            (sola == mejorSoledad && alCentro < mejorAlCentro)) {
          mejor = p;
          mejorSoledad = sola;
          mejorAlCentro = alCentro;
        }
      }
      if (mejor != null) lugares[r.id] = LatLng(mejor.y / ky, mejor.x / kx);
    }
    return lugares;
  }

  /// Puntos sobre [linea] cada [_paso] metros, con sus dos extremos.
  static List<math.Point<double>> _muestrear(List<math.Point<double>> linea) {
    if (linea.isEmpty) return const [];
    final muestras = [linea.first];
    var falta = _paso;
    for (var i = 1; i < linea.length; i++) {
      var desde = linea[i - 1];
      final hasta = linea[i];
      var queda = desde.distanceTo(hasta);
      while (queda >= falta) {
        desde += (hasta - desde) * (falta / queda);
        muestras.add(desde);
        queda -= falta;
        falta = _paso;
      }
      falta -= queda;
    }
    if (muestras.last != linea.last) muestras.add(linea.last);
    return muestras;
  }

  /// El número de la línea ("Línea 10" → "10"); sin número, su sigla.
  static String rotuloDeLinea(Recorrido r) {
    final numero = RegExp(r'\d+[A-Za-z]?').firstMatch(r.linea)?.group(0);
    return numero?.toUpperCase() ?? r.sigla;
  }

  /// La etiqueta de un colectivo que cubre [r]: línea y variante ("10 T").
  static String etiqueta(Recorrido r) {
    final linea = rotuloDeLinea(r);
    final variante = r.codigoVariante.trim();
    return variante.isEmpty || variante == linea ? linea : '$linea $variante';
  }

  /// Hacia dónde va [sentido] de [r], según el último lugar de su cartola. La
  /// cartola termina en la garita ("…; SERRANO; QUILPUÉ") cuando vuelve al
  /// centro. Sin cartola, `null`.
  static DestinoSena? destino(Recorrido r, Sentido sentido) {
    final calles = r.calles(sentido);
    return calles.isEmpty ? null : _lugar(calles.last);
  }

  /// Hasta qué distancia dos extremos son el mismo terminal: donde termina la
  /// ida suele empezar el regreso, a la vuelta de la esquina.
  static const double mismoTerminal = 150;

  /// Los terminales de [r], para marcarlos en el mapa: dónde empieza y dónde
  /// termina cada sentido, con el nombre que les da la cartola (su primer y
  /// su último lugar). Los que quedan a menos de [mismoTerminal] metros son
  /// uno solo, así que una línea de ida y regreso tiene dos.
  static List<Terminal> terminales(Recorrido r) {
    final terminales = <Terminal>[];
    void agregar(LatLng punto, DestinoSena? lugar) {
      for (final (i, t) in terminales.indexed) {
        if (metrosEntre(t.punto, punto) > mismoTerminal) continue;
        // El mismo terminal: queda donde se lo vio primero, con el nombre de
        // quien lo traiga.
        if (t.lugar == null && lugar != null) {
          terminales[i] = Terminal(punto: t.punto, lugar: lugar);
        }
        return;
      }
      terminales.add(Terminal(punto: punto, lugar: lugar));
    }

    for (final (sentido, trayecto) in r.trayectos) {
      final calles = r.calles(sentido);
      agregar(
        trayecto.trazado.first,
        calles.isEmpty ? null : _lugar(calles.first),
      );
      agregar(
        trayecto.trazado.last,
        calles.isEmpty ? null : _lugar(calles.last),
      );
    }
    return terminales;
  }

  /// Un lugar de la cartola: el centro si es la garita ("SERRANO",
  /// "QUILPUÉ"), o su nombre.
  static DestinoSena _lugar(String entrada) {
    final nombre = entrada.trim();
    final clave = _sinTildes(nombre.toUpperCase());
    if (clave == 'QUILPUE' || clave == 'SERRANO') {
      return const DestinoSena.centro();
    }
    return DestinoSena.lugar(_titulo(nombre));
  }

  static const _minusculas = {'de', 'del', 'la', 'las', 'el', 'los', 'y'};

  /// "ALTO EL YUGO" → "Alto el Yugo".
  static String _titulo(String texto) {
    final palabras = texto.toLowerCase().split(RegExp(r'\s+'));
    return [
      for (final (i, p) in palabras.indexed)
        if (p.isEmpty)
          p
        else if (i > 0 && _minusculas.contains(p))
          p
        else
          p[0].toUpperCase() + p.substring(1),
    ].join(' ');
  }

  static String _sinTildes(String s) => s
      .replaceAll('Á', 'A')
      .replaceAll('É', 'E')
      .replaceAll('Í', 'I')
      .replaceAll('Ó', 'O')
      .replaceAll('Ú', 'U');
}
