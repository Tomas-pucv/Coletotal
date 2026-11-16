import 'package:flutter/widgets.dart';

/// Puntos de quiebre responsivos (RF-04-01: "El sistema debe ajustarse
/// responsivamente para cualquier tamaño de pantalla de dispositivo móvil").
///
/// Sigue las window size classes de Material 3.
abstract final class Breakpoints {
  /// Bajo este ancho la navegación va abajo ([NavigationBar]).
  /// Sobre él va al costado ([NavigationRail]): cubre tablets y también
  /// teléfonos en horizontal, donde la barra inferior come demasiado alto.
  static const double medium = 600;

  static const double expanded = 840;

  /// Ancho máximo de una columna de contenido legible. En pantallas anchas el
  /// contenido se centra en vez de estirarse de borde a borde.
  static const double maxContentWidth = 720;

  static bool isCompact(BuildContext context) =>
      MediaQuery.sizeOf(context).width < medium;

  static bool isExpanded(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= expanded;
}
