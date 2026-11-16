import 'package:flutter/material.dart';

import 'package:taxi1/theme/app_spacing.dart';

/// Bloque de ajustes con el encabezado *fuera* del contenido.
///
/// Reemplaza a la antigua `SectionCard`, que encerraba cada grupo en una caja
/// con borde: con cinco grupos seguidos la pantalla se leía como una pila de
/// cajas y el contenido quedaba comprimido. Sacar el título afuera es el patrón
/// de los Ajustes de Android y deja respirar a las vistas previas.
class SettingsSection extends StatelessWidget {
  const SettingsSection({
    super.key,
    required this.title,
    required this.children,
    this.icon,
    this.action,
  });

  final String title;
  final IconData? icon;
  final List<Widget> children;

  /// Acción opcional alineada a la derecha del encabezado (p. ej. "Borrar").
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            0,
            AppSpacing.sm,
            AppSpacing.sm,
          ),
          child: Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: AppSpacing.sm),
              ],
              Expanded(
                child: Text(
                  title.toUpperCase(),
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
              ?action,
            ],
          ),
        ),
        ...children,
      ],
    );
  }
}
