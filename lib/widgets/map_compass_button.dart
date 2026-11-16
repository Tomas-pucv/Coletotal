import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Brújula del mapa: aparece sólo con el mapa girado, como en Google Maps, y
/// su aguja gira con el mapa apuntando al norte. Al tocarla, el mapa vuelve al
/// norte y la brújula se va.
///
/// Es un botón de Flutter y no la brújula nativa de MapLibre: ésa se ubica
/// en píxeles desde la esquina del mapa, sin saber dónde quedan los demás
/// botones (que se mueven con el tamaño de letra), y no tendría su tamaño ni
/// su aspecto.
class MapCompassButton extends StatelessWidget {
  const MapCompassButton({
    super.key,
    required this.bearing,
    required this.tooltip,
    required this.onPressed,
    this.animate = true,
  });

  /// Hacia dónde mira el mapa, en grados desde el norte (en sentido horario).
  final ValueListenable<double> bearing;
  final String tooltip;
  final VoidCallback onPressed;

  /// La preferencia "Animaciones": sin ella aparece y desaparece de golpe.
  final bool animate;

  /// Por debajo de esto el mapa ya mira al norte: MapLibre deja restos de
  /// décimas de grado al volver a cero.
  static const double _tolerance = 0.5;

  static bool facesNorth(double degrees) {
    final normalized = degrees % 360;
    return normalized < _tolerance || normalized > 360 - _tolerance;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final duration = animate
        ? const Duration(milliseconds: 200)
        : Duration.zero;

    return ValueListenableBuilder<double>(
      valueListenable: bearing,
      builder: (context, degrees, _) {
        final visible = !facesNorth(degrees);
        return ExcludeSemantics(
          excluding: !visible,
          child: IgnorePointer(
            ignoring: !visible,
            child: AnimatedOpacity(
              opacity: visible ? 1 : 0,
              duration: duration,
              child: AnimatedScale(
                scale: visible ? 1 : 0.6,
                duration: duration,
                child: FloatingActionButton.small(
                  heroTag: 'reorient',
                  tooltip: tooltip,
                  onPressed: onPressed,
                  // La aguja apunta al norte: si el mapa mira al este, el
                  // norte queda a la izquierda.
                  child: Transform.rotate(
                    angle: -degrees * math.pi / 180,
                    child: CustomPaint(
                      size: const Size(10, 24),
                      painter: _NeedlePainter(
                        north: const Color(0xFFE53935),
                        south: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// La aguja: un rombo con la mitad norte roja.
class _NeedlePainter extends CustomPainter {
  const _NeedlePainter({required this.north, required this.south});

  final Color north;
  final Color south;

  @override
  void paint(Canvas canvas, Size size) {
    final middle = size.height / 2;
    Path half(double tip) => Path()
      ..moveTo(size.width / 2, tip)
      ..lineTo(size.width, middle)
      ..lineTo(0, middle)
      ..close();
    canvas.drawPath(half(0), Paint()..color = north);
    canvas.drawPath(half(size.height), Paint()..color = south);
  }

  @override
  bool shouldRepaint(_NeedlePainter oldDelegate) =>
      oldDelegate.north != north || oldDelegate.south != south;
}
