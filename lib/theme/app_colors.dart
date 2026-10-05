import 'package:flutter/material.dart';

import 'package:taxi1/models/colectivo_activo.dart';

/// Semilla de marca de ColeTotal.
///
/// La elección no es arbitraria. El mapa ya tiene dos escalas de color
/// reservadas que no se pueden pisar:
///
///  * **Azul** = "mi ubicación" (convención de Google/Apple Maps, y el punto
///    del pasajero en [MapScreen] la usa).
///  * **Verde / ámbar / rojo** = semaforización de capacidad de las unidades,
///    exigida por el informe (§7.3.1-C "marcadores de semáforos que cambian de
///    color según la capacidad reportada por los choferes").
///
/// Semilla de marca de ColeTotal: Amarillo ligeramente anaranjado cálido
/// inspirado en la estética tradicional del letrero y cúpula de techo del colectivo chileno.
const Color kColeTotalSeed = Color(0xFFE58A00);

/// Colores semánticos que el [ColorScheme] de Material 3 no cubre.
///
/// Van en un [ThemeExtension] —y no como literales `Colors.green` desperdigados
/// por las pantallas— para que tengan variante clara y oscura, interpolen en
/// los cambios de tema y se puedan auditar en un solo lugar.
@immutable
class AppStatusColors extends ThemeExtension<AppStatusColors> {
  const AppStatusColors({
    required this.disponible,
    required this.medioLleno,
    required this.lleno,
    required this.distanceVeryClose,
    required this.distanceClose,
    required this.distanceMedium,
    required this.distanceFar,
    required this.distanceUnknown,
    required this.userLocation,
    required this.routeLine,
    required this.routeLineCasing,
    required this.markerBorder,
  });

  /// Semaforización de capacidad (informe §7.3.1-C).
  final Color disponible;
  final Color medioLleno;
  final Color lleno;

  /// Escala de proximidad a un paradero. Cuatro tonos claramente distintos
  /// entre sí, ninguno azul (reservado para la ubicación del usuario).
  final Color distanceVeryClose;
  final Color distanceClose;
  final Color distanceMedium;
  final Color distanceFar;

  /// Sin posición conocida: no se puede afirmar cercanía.
  final Color distanceUnknown;

  /// Punto "tú estás aquí". Azul por convención cartográfica.
  final Color userLocation;

  /// Trazado de la ruta y su contorno (para que se lea sobre satélite).
  final Color routeLine;
  final Color routeLineCasing;

  /// Borde de los marcadores sobre el mapa, para separarlos del fondo.
  final Color markerBorder;

  /// Color de la semaforización para la capacidad [estado].
  ///
  /// Reemplaza tres `switch` idénticos que vivían en el mapa, en la consola de
  /// flota y en la ficha del colectivo.
  Color forEstado(EstadoCapacidad estado) => switch (estado) {
    EstadoCapacidad.disponible => disponible,
    EstadoCapacidad.medioLleno => medioLleno,
    EstadoCapacidad.lleno => lleno,
  };

  /// Color de texto/icono legible sobre [background].
  ///
  /// Evita tener que declarar un `onX` por cada color de estado.
  static Color onColorFor(Color background) =>
      background.computeLuminance() > 0.45
      ? const Color(0xFF1B1B1F)
      : const Color(0xFFFFFFFF);

  /// Paleta de estado para tema claro. Todos los tonos cumplen contraste AA
  /// (>= 4.5:1) sobre superficies claras.
  static const AppStatusColors light = AppStatusColors(
    disponible: Color(0xFF1B7A3D),
    medioLleno: Color(0xFFA65A00),
    lleno: Color(0xFFB3261E),
    distanceVeryClose: Color(0xFF1B7A3D),
    distanceClose: Color(0xFF00796B),
    distanceMedium: Color(0xFFA65A00),
    distanceFar: Color(0xFFB3261E),
    distanceUnknown: Color(0xFF6F6F78),
    userLocation: Color(0xFF1A73E8),
    routeLine: Color(0xFF4A3F9E),
    routeLineCasing: Color(0xFFFFFFFF),
    markerBorder: Color(0xFFFFFFFF),
  );

  /// Paleta de estado para tema oscuro: los mismos matices, aclarados para
  /// mantener contraste AA sobre superficies oscuras.
  static const AppStatusColors dark = AppStatusColors(
    disponible: Color(0xFF6DD98C),
    medioLleno: Color(0xFFF5B95C),
    lleno: Color(0xFFF2B8B5),
    distanceVeryClose: Color(0xFF6DD98C),
    distanceClose: Color(0xFF4DD0C1),
    distanceMedium: Color(0xFFF5B95C),
    distanceFar: Color(0xFFF2B8B5),
    distanceUnknown: Color(0xFF97979F),
    userLocation: Color(0xFF8AB4F8),
    routeLine: Color(0xFFB9AEFF),
    routeLineCasing: Color(0xFF1B1B1F),
    markerBorder: Color(0xFF1B1B1F),
  );

  static AppStatusColors of(BuildContext context) =>
      Theme.of(context).extension<AppStatusColors>() ?? light;

  @override
  AppStatusColors copyWith({
    Color? disponible,
    Color? medioLleno,
    Color? lleno,
    Color? distanceVeryClose,
    Color? distanceClose,
    Color? distanceMedium,
    Color? distanceFar,
    Color? distanceUnknown,
    Color? userLocation,
    Color? routeLine,
    Color? routeLineCasing,
    Color? markerBorder,
  }) {
    return AppStatusColors(
      disponible: disponible ?? this.disponible,
      medioLleno: medioLleno ?? this.medioLleno,
      lleno: lleno ?? this.lleno,
      distanceVeryClose: distanceVeryClose ?? this.distanceVeryClose,
      distanceClose: distanceClose ?? this.distanceClose,
      distanceMedium: distanceMedium ?? this.distanceMedium,
      distanceFar: distanceFar ?? this.distanceFar,
      distanceUnknown: distanceUnknown ?? this.distanceUnknown,
      userLocation: userLocation ?? this.userLocation,
      routeLine: routeLine ?? this.routeLine,
      routeLineCasing: routeLineCasing ?? this.routeLineCasing,
      markerBorder: markerBorder ?? this.markerBorder,
    );
  }

  @override
  AppStatusColors lerp(ThemeExtension<AppStatusColors>? other, double t) {
    if (other is! AppStatusColors) return this;
    return AppStatusColors(
      disponible: Color.lerp(disponible, other.disponible, t)!,
      medioLleno: Color.lerp(medioLleno, other.medioLleno, t)!,
      lleno: Color.lerp(lleno, other.lleno, t)!,
      distanceVeryClose: Color.lerp(
        distanceVeryClose,
        other.distanceVeryClose,
        t,
      )!,
      distanceClose: Color.lerp(distanceClose, other.distanceClose, t)!,
      distanceMedium: Color.lerp(distanceMedium, other.distanceMedium, t)!,
      distanceFar: Color.lerp(distanceFar, other.distanceFar, t)!,
      distanceUnknown: Color.lerp(distanceUnknown, other.distanceUnknown, t)!,
      userLocation: Color.lerp(userLocation, other.userLocation, t)!,
      routeLine: Color.lerp(routeLine, other.routeLine, t)!,
      routeLineCasing: Color.lerp(routeLineCasing, other.routeLineCasing, t)!,
      markerBorder: Color.lerp(markerBorder, other.markerBorder, t)!,
    );
  }
}
