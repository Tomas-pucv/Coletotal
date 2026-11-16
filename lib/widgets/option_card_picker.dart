import 'package:flutter/material.dart';

import 'package:taxi1/theme/app_spacing.dart';

/// Una opción del [OptionCardPicker].
class OptionCard<T> {
  const OptionCard({
    required this.value,
    required this.label,
    required this.preview,
    this.description,
  });

  final T value;
  final String label;
  final String? description;

  /// Contenido visual de la opción: una miniatura real, un icono grande, una
  /// muestra de color. Es lo que hace que se elija mirando y no leyendo.
  final Widget preview;
}

/// Selector de opciones en forma de tarjetas con vista previa.
///
/// Sustituye a las listas de radios donde la diferencia entre opciones es
/// *visual* (estilo de mapa, rol de usuario): leer "Satélite" obliga a
/// imaginarse el resultado, mientras que ver la foto aérea no.
///
/// Sigue siendo accesible: cada tarjeta es un botón con estado seleccionado
/// expuesto a lectores de pantalla y área táctil holgada.
class OptionCardPicker<T> extends StatelessWidget {
  const OptionCardPicker({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final T value;
  final List<OptionCard<T>> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < options.length; i++) ...[
          if (i > 0) const SizedBox(width: AppSpacing.md),
          Expanded(
            child: _OptionTile(
              option: options[i],
              selected: options[i].value == value,
              onTap: () => onChanged(options[i].value),
            ),
          ),
        ],
      ],
    );
  }
}

class _OptionTile<T> extends StatelessWidget {
  const _OptionTile({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final OptionCard<T> option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Semantics(
      button: true,
      selected: selected,
      label: option.label,
      hint: option.description,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // La previsualización lleva el anillo de selección: es el elemento
            // que el usuario está comparando.
            AspectRatio(
              aspectRatio: 1,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  border: Border.all(
                    color: selected ? scheme.primary : scheme.outlineVariant,
                    width: selected ? 3 : 1,
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    option.preview,
                    if (selected)
                      Positioned(
                        right: AppSpacing.xs,
                        bottom: AppSpacing.xs,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: scheme.primary,
                            shape: BoxShape.circle,
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(2),
                            child: Icon(
                              Icons.check,
                              size: 16,
                              color: scheme.onPrimary,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              option.label,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: selected ? scheme.primary : scheme.onSurface,
              ),
            ),
            if (option.description != null)
              Text(
                option.description!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
