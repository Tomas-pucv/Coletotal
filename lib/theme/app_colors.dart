import 'package:flutter/material.dart';

/// Negro de marca: la carrocería del colectivo chileno.
const Color kColeTotalInk = Color(0xFF1C1B1A);

/// Amarillo de marca: el letrero del techo del colectivo.
const Color kColeTotalYellow = Color(0xFFFFCC00);

/// Paleta de ColeTotal: negro y amarillo de colectivo sobre grises neutros.
///
/// La interfaz es gris neutro y lo único con color sobre el mapa son los
/// marcadores y las líneas, que son los que significan algo. Lo principal
/// (botones, interruptores, títulos de sección) va en negro en el tema claro y
/// en amarillo en el oscuro; el amarillo marca además lo seleccionado: la
/// pestaña actual, el recentrado mientras sigue al usuario, los botones
/// tonales.
ColorScheme buildColorScheme(Brightness brightness) {
  // Fondos, textos y bordes: la rampa de grises de Material 3, sin tinte.
  final neutral = ColorScheme.fromSeed(
    seedColor: kColeTotalYellow,
    brightness: brightness,
    dynamicSchemeVariant: DynamicSchemeVariant.monochrome,
  );
  return switch (brightness) {
    Brightness.light => neutral.copyWith(
      primary: kColeTotalInk,
      onPrimary: Colors.white,
      primaryContainer: kColeTotalYellow,
      onPrimaryContainer: kColeTotalInk,
      secondaryContainer: kColeTotalYellow,
      onSecondaryContainer: kColeTotalInk,
      // Avisos (InlineNotice, estados de advertencia): amarillo pálido de
      // precaución, distinto del amarillo pleno de lo seleccionado.
      tertiary: const Color(0xFF6B5800),
      onTertiary: Colors.white,
      tertiaryContainer: const Color(0xFFFFF1B8),
      onTertiaryContainer: const Color(0xFF3D3300),
      inversePrimary: const Color(0xFFFFD54A),
    ),
    // De noche el amarillo pasa a ser el color principal, como el letrero
    // encendido. Los contenedores son oliva oscuro para no encandilar.
    Brightness.dark => neutral.copyWith(
      primary: const Color(0xFFFFD54A),
      onPrimary: kColeTotalInk,
      primaryContainer: const Color(0xFF3D3300),
      onPrimaryContainer: const Color(0xFFFFE58A),
      secondaryContainer: const Color(0xFF3D3300),
      onSecondaryContainer: const Color(0xFFFFE58A),
      tertiary: const Color(0xFFE8C66A),
      onTertiary: kColeTotalInk,
      tertiaryContainer: const Color(0xFF4F4416),
      onTertiaryContainer: const Color(0xFFFFE9A8),
      inversePrimary: const Color(0xFF6B5800),
    ),
  };
}

/// Fondo de lo que flota sobre el mapa: el buscador, las tarjetas y los
/// botones redondos.
extension MapControlColors on ColorScheme {
  /// Blanco en el tema claro, como en cualquier app de mapas: el mapa ya es
  /// gris claro y un control gris se perdía contra él. En el oscuro, el gris
  /// elevado, que se separa del mapa sin encandilar.
  Color get mapControl => brightness == Brightness.light
      ? surfaceContainerLowest
      : surfaceContainerHigh;
}

/// Colores semánticos que el [ColorScheme] de Material 3 no cubre.
///
/// Van en un [ThemeExtension] —y no como literales `Colors.green` desperdigados
/// por las pantallas— para que tengan variante clara y oscura, interpolen en
/// los cambios de tema y se puedan auditar en un solo lugar.
@immutable
class AppStatusColors extends ThemeExtension<AppStatusColors> {
  const AppStatusColors({
    required this.disponible,
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

  /// Indicador de unidad o chofer activo / en servicio.
  final Color disponible;

  /// Escala de proximidad peatonal. Cuatro tonos claramente distintos
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
    distanceVeryClose: Color(0xFF6DD98C),
    distanceClose: Color(0xFF4DD0C1),
    distanceMedium: Color(0xFFFFA352),
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
