import 'package:flutter/widgets.dart';

/// Compone la preferencia de tamaño de fuente de la app con el ajuste de
/// accesibilidad del sistema operativo.
///
/// Antes el multiplicador se aplicaba a mano (`fontSize: 14 * prefs
/// .fontSizeMultiplier`) en cada `TextStyle`, con dos consecuencias:
///
///  * solo llegaba a la pantalla de Preferencias y a las etiquetas de la barra
///    de navegación — Mapa y Rutas lo ignoraban por completo;
///  * era incompatible con el ajuste de tamaño de fuente del sistema.
///
/// Aplicado una sola vez en el `builder` de `MaterialApp`, alcanza a todo texto
/// que use el `TextTheme`, y **multiplica** el escalado del SO en vez de
/// pisarlo: quien tenga el teléfono en 1.3x y la app en 1.2x obtiene 1.56x.
@immutable
class AppTextScaler extends TextScaler {
  const AppTextScaler(this.base, this.factor);

  /// Escalador del sistema (ajuste de accesibilidad del SO).
  final TextScaler base;

  /// Preferencia de la app (`PreferencesService.fontSizeMultiplier`).
  final double factor;

  @override
  double scale(double fontSize) => base.scale(fontSize * factor);

  // `TextScaler.textScaleFactor` está deprecado pero sigue siendo abstracto,
  // así que implementarlo es obligatorio.
  @Deprecated(
    'Use of textScaleFactor was deprecated in preparation for the upcoming '
    'nonlinear text scaling support. '
    'This feature was deprecated after v3.12.0-2.0.pre.',
  )
  @override
  // ignore: deprecated_member_use
  double get textScaleFactor => base.textScaleFactor * factor;

  @override
  bool operator ==(Object other) =>
      other is AppTextScaler && other.base == base && other.factor == factor;

  @override
  int get hashCode => Object.hash(base, factor);

  @override
  String toString() => 'AppTextScaler($base x $factor)';
}
