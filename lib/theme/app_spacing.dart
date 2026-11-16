import 'package:flutter/widgets.dart';

/// Escala de espaciado y radios del design system de ColeTotal.
///
/// Antes de esta clase el proyecto mezclaba 4/6/8/10/12/14/16/20/28/32 px de
/// forma ad-hoc en cada pantalla. Todo espaciado nuevo debe salir de acá.
abstract final class AppSpacing {
  /// 4 — separación mínima entre elementos muy relacionados (icono + texto).
  static const double xs = 4;

  /// 8 — separación dentro de un mismo bloque.
  static const double sm = 8;

  /// 12 — padding interno de tarjetas y tiles.
  static const double md = 12;

  /// 16 — margen estándar de pantalla.
  static const double lg = 16;

  /// 24 — separación entre secciones.
  static const double xl = 24;

  /// 32 — separación mayor / respiro final de scroll.
  static const double xxl = 32;

  // --- Radios -------------------------------------------------------------

  static const double radiusSm = 8;
  static const double radiusMd = 12;
  static const double radiusLg = 16;

  /// 28 — radio "full pill" de M3 para FABs y chips grandes.
  static const double radiusXl = 28;

  /// Área táctil mínima recomendada por WCAG 2.1 AA / Material Design.
  static const double minTapTarget = 48;

  // --- Insets de uso frecuente -------------------------------------------

  /// Margen horizontal estándar de pantalla.
  static const EdgeInsets pageHorizontal = EdgeInsets.symmetric(horizontal: lg);

  /// Padding interno de tarjetas.
  static const EdgeInsets card = EdgeInsets.all(md);

  /// Padding de una pantalla con scroll vertical.
  static const EdgeInsets pageScroll = EdgeInsets.fromLTRB(lg, lg, lg, xxl);
}
