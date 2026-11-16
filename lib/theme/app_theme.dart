import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:taxi1/theme/app_colors.dart';
import 'package:taxi1/theme/app_spacing.dart';

/// Construye el tema de ColeTotal.
///
/// Una sola función para ambos brillos: antes había dos builders de ~60 líneas
/// en `main.dart` que solo diferían en `brightness`, con el riesgo evidente de
/// que el tema oscuro se quedara atrás cada vez que se tocaba el claro.
///
/// La función es **pura**: no lee `PreferencesService`. El tamaño de fuente ya
/// no se multiplica dentro del tema (eso lo hace `AppTextScaler` a nivel de
/// `MediaQuery`, y así alcanza a toda la app y no solo a la barra de nav).
ThemeData buildAppTheme({
  required Brightness brightness,
  bool compact = false,
}) {
  final scheme = buildColorScheme(brightness);
  final isDark = brightness == Brightness.dark;
  final text = _buildTextTheme(scheme);
  final status = isDark ? AppStatusColors.dark : AppStatusColors.light;

  // La barra de navegación del sistema tiene que verse como la continuación
  // de la barra de pestañas (o del fondo de la pantalla), que es `surface`.
  //  * Hasta Android 14 se pinta del color que se le pide.
  //  * Desde Android 15 ese color se ignora: la app se dibuja detrás de la
  //    barra y, con navegación de tres botones, Android le pone encima un velo
  //    blanco o negro "para que se lean los botones". Ese velo era la franja
  //    de otro color bajo las pestañas. Sin el velo se ve lo que la app dibuja
  //    debajo, que ya es la barra de pestañas, y los botones se leen igual
  //    porque su brillo se ajusta al tema.
  final overlayStyle =
      (isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark)
          .copyWith(
            statusBarColor: Colors.transparent,
            systemNavigationBarColor: scheme.surface,
            systemNavigationBarDividerColor: scheme.surface,
            systemNavigationBarIconBrightness: isDark
                ? Brightness.light
                : Brightness.dark,
            systemNavigationBarContrastEnforced: false,
          );

  final shapeMd = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
  );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    textTheme: text,
    scaffoldBackgroundColor: scheme.surface,
    extensions: <ThemeExtension<dynamic>>[status],

    // El modo compacto aprieta la interfaz un punto, no dos: VisualDensity
    // .compact (-2) baja los targets a 40dp y rompería el mínimo de 48dp.
    visualDensity: compact
        ? const VisualDensity(horizontal: -1, vertical: -1)
        : VisualDensity.standard,
    materialTapTargetSize: MaterialTapTargetSize.padded,

    appBarTheme: AppBarThemeData(
      centerTitle: false,
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: text.titleLarge,
      systemOverlayStyle: overlayStyle,
    ),

    // Tarjeta visible: surfaceContainer + borde. Antes era elevation 0 con
    // color surface, es decir invisible contra el scaffold, y cada pantalla lo
    // compensaba a mano con elevation 4 o un Container con borde propio.
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: scheme.surfaceContainer,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        side: BorderSide(color: scheme.outlineVariant),
      ),
    ),

    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: shapeMd,
        minimumSize: const Size(0, AppSpacing.minTapTarget),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xl,
          vertical: AppSpacing.md,
        ),
        textStyle: text.labelLarge,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: shapeMd,
        minimumSize: const Size(0, AppSpacing.minTapTarget),
        textStyle: text.labelLarge,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        shape: shapeMd,
        minimumSize: const Size(0, AppSpacing.minTapTarget),
        textStyle: text.labelLarge,
      ),
    ),

    // Los FABs del mapa venían con Colors.white / Colors.black87 fijos, lo que
    // los dejaba como manchas blancas en tema oscuro. Ahora siguen el fondo de
    // los controles del mapa, que sí cambia con el tema.
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: scheme.mapControl,
      foregroundColor: scheme.onSurface,
      elevation: 3,
      focusElevation: 4,
      hoverElevation: 4,
      highlightElevation: 6,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      ),
      smallSizeConstraints: const BoxConstraints.tightFor(
        width: AppSpacing.minTapTarget,
        height: AppSpacing.minTapTarget,
      ),
    ),

    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: scheme.secondaryContainer,
      elevation: 0,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return text.labelMedium!.copyWith(
          fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
          color: selected ? scheme.onSurface : scheme.onSurfaceVariant,
        );
      }),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return IconThemeData(
          size: 24,
          color: selected
              ? scheme.onSecondaryContainer
              : scheme.onSurfaceVariant,
        );
      }),
    ),

    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: scheme.surface,
      indicatorColor: scheme.secondaryContainer,
      elevation: 0,
      labelType: NavigationRailLabelType.all,
      selectedLabelTextStyle: text.labelMedium!.copyWith(
        fontWeight: FontWeight.w600,
        color: scheme.onSurface,
      ),
      unselectedLabelTextStyle: text.labelMedium!.copyWith(
        color: scheme.onSurfaceVariant,
      ),
      selectedIconTheme: IconThemeData(
        size: 24,
        color: scheme.onSecondaryContainer,
      ),
      unselectedIconTheme: IconThemeData(
        size: 24,
        color: scheme.onSurfaceVariant,
      ),
    ),

    // El menú lateral era el único componente grande que el tema no cubría, y
    // por defecto viene con `surfaceContainerLow` y una tipografía distinta a
    // la de la barra inferior: las dos superficies de navegación tienen que
    // leerse como la misma app.
    navigationDrawerTheme: NavigationDrawerThemeData(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: scheme.secondaryContainer,
      elevation: 1,
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return text.labelLarge!.copyWith(
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          color: selected ? scheme.onSecondaryContainer : scheme.onSurface,
        );
      }),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return IconThemeData(
          size: 24,
          color: selected
              ? scheme.onSecondaryContainer
              : scheme.onSurfaceVariant,
        );
      }),
    ),

    // Antes los dos TextField contiguos de RoutesScreen tenían radios 4 y 12 y
    // relleno distinto, porque cada uno se estilaba en su propio call site.
    inputDecorationTheme: InputDecorationThemeData(
      filled: true,
      fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        borderSide: BorderSide(color: scheme.primary, width: 2),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        borderSide: BorderSide(
          color: scheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      prefixIconColor: scheme.onSurfaceVariant,
      suffixIconColor: scheme.onSurfaceVariant,
      hintStyle: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
      labelStyle: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
    ),

    // minTileHeight garantiza el target de 48dp incluso en modo compacto.
    listTileTheme: ListTileThemeData(
      minTileHeight: compact ? AppSpacing.minTapTarget : 56,
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      iconColor: scheme.onSurfaceVariant,
      titleTextStyle: text.bodyLarge,
      subtitleTextStyle: text.bodySmall?.copyWith(
        color: scheme.onSurfaceVariant,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      ),
    ),

    dividerTheme: DividerThemeData(
      color: scheme.outlineVariant,
      thickness: 1,
      space: 1,
    ),

    // Antes cada SnackBar repetía behavior: SnackBarBehavior.floating.
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: scheme.inverseSurface,
      contentTextStyle: text.bodyMedium?.copyWith(
        color: scheme.onInverseSurface,
      ),
      actionTextColor: scheme.inversePrimary,
      insetPadding: const EdgeInsets.all(AppSpacing.lg),
      shape: shapeMd,
    ),

    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surfaceContainerHigh,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: text.headlineSmall,
      contentTextStyle: text.bodyMedium,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
      ),
    ),

    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: scheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppSpacing.radiusXl),
        ),
      ),
    ),

    tooltipTheme: TooltipThemeData(
      textStyle: text.bodySmall?.copyWith(color: scheme.onInverseSurface),
      decoration: BoxDecoration(
        color: scheme.inverseSurface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
    ),
  );
}

/// Escala tipográfica de Material 3 con títulos y etiquetas algo más firmes.
///
/// Antes no existía `textTheme` y las pantallas escribían `TextStyle(fontSize:
/// 10/12/13/14/14.5)` a mano, lo que además impedía que el ajuste de tamaño de
/// fuente llegara a Mapa y Rutas.
TextTheme _buildTextTheme(ColorScheme scheme) {
  final typography = Typography.material2021(colorScheme: scheme);
  final base = typography.englishLike.merge(
    scheme.brightness == Brightness.dark ? typography.white : typography.black,
  );

  return base.copyWith(
    titleLarge: base.titleLarge?.copyWith(fontWeight: FontWeight.w600),
    titleMedium: base.titleMedium?.copyWith(fontWeight: FontWeight.w600),
    titleSmall: base.titleSmall?.copyWith(fontWeight: FontWeight.w600),
    labelLarge: base.labelLarge?.copyWith(fontWeight: FontWeight.w600),
  );
}
