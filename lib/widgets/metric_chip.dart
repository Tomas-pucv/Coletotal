import 'package:flutter/material.dart';

import 'package:taxi1/theme/app_spacing.dart';

/// Píldora compacta de métrica o estado (distancia, duración, cercanía).
///
/// Unifica dos implementaciones del mismo patrón: `_MetricChip` en
/// `map_screen.dart` y el badge de cercanía en `routes_screen.dart`.
///
/// No usa el `Chip` de Material a propósito: `Chip` reserva altura y padding
/// para acciones que acá no existen, y estas píldoras van dentro de una tarjeta
/// flotante sobre el mapa donde el alto es caro.
class MetricChip extends StatelessWidget {
  const MetricChip({
    super.key,
    required this.label,
    required this.color,
    this.icon,
  });

  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Fondo teñido con el color de estado; el texto va en el color pleno, que
    // es el que cumple contraste AA (un relleno al 15% no sirve como fondo).
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.22 : 0.14),
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: color),
            const SizedBox(width: AppSpacing.xs),
          ],
          // Flexible: con la fuente al 140% la etiqueta debe recortarse en vez
          // de desbordar la fila que la contiene.
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
