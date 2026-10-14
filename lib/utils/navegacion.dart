/// Zoom de la cámara de navegación del chofer, por tramos de velocidad: más
/// rápido, más lejos, para ver más camino por delante.
const List<double> kZoomsNavegacion = [17, 16.3, 15.7];

/// Bordes entre los tramos de [kZoomsNavegacion], en km/h.
const List<double> _bordesKmh = [20, 45];

/// Cuánto hay que pasarse de un borde para cambiar de tramo, en km/h: sin
/// esto, andar a 20 km/h justo hacía saltar el zoom a cada rato.
const double _margenKmh = 5;

/// El zoom para ir a [kmh], partiendo del zoom [actual]. Sin velocidad
/// conocida se queda en el [actual].
double zoomParaVelocidad(double? kmh, double actual) {
  // El tramo del zoom actual: el de [kZoomsNavegacion] más parecido.
  var tramo = 0;
  for (var i = 1; i < kZoomsNavegacion.length; i++) {
    if ((kZoomsNavegacion[i] - actual).abs() <
        (kZoomsNavegacion[tramo] - actual).abs()) {
      tramo = i;
    }
  }
  if (kmh == null || !kmh.isFinite || kmh < 0) return kZoomsNavegacion[tramo];

  final piso = tramo == 0 ? double.negativeInfinity : _bordesKmh[tramo - 1];
  final techo = tramo == _bordesKmh.length
      ? double.infinity
      : _bordesKmh[tramo];
  if (kmh >= piso - _margenKmh && kmh < techo + _margenKmh) {
    return kZoomsNavegacion[tramo];
  }
  var nuevo = 0;
  while (nuevo < _bordesKmh.length && kmh >= _bordesKmh[nuevo]) {
    nuevo++;
  }
  return kZoomsNavegacion[nuevo];
}
