import 'package:flutter/material.dart';

import 'package:taxi1/theme/app_colors.dart';
import 'package:taxi1/theme/app_spacing.dart';

/// Superficie flotante sobre el mapa.
///
/// El `cardTheme` global es plano y con borde, pensado para tarjetas dentro de
/// una lista. Sobre la cartografía hace falta lo contrario: elevación y sombra
/// reales para despegar del mapa. Antes cada uno de estos casos ponía
/// `elevation: 4` a mano en su call site.
class MapOverlayCard extends StatelessWidget {
  const MapOverlayCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(AppSpacing.md),
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Material(
      color: scheme.mapControl,
      elevation: 4,
      shadowColor: Colors.black.withValues(alpha: 0.3),
      surfaceTintColor: Colors.transparent,
      borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}
