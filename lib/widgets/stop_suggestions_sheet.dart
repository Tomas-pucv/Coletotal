import 'package:flutter/material.dart';

import 'package:taxi1/l10n/app_localizations.dart';
import 'package:taxi1/services/stop_planner.dart';
import 'package:taxi1/theme/app_spacing.dart';
import 'package:taxi1/utils/distance_format.dart';
import 'package:taxi1/widgets/state_views.dart';

/// Muestra qué paradero conviene tomar para llegar al destino buscado.
///
/// Cada fila enseña **los dos tramos** que se promedian para elegirlo —lo que
/// caminas hasta el paradero y lo que caminas desde la bajada—, en vez de un
/// número de ranking opaco: así se ve por qué el primero es el primero, y se
/// puede discrepar con criterio.
Future<StopSuggestion?> showStopSuggestionsSheet(
  BuildContext context, {
  required String destino,
  required List<StopSuggestion> suggestions,
}) {
  return showModalBottomSheet<StopSuggestion>(
    context: context,
    isScrollControlled: true,
    builder: (_) =>
        _SuggestionsSheet(destino: destino, suggestions: suggestions),
  );
}

class _SuggestionsSheet extends StatelessWidget {
  const _SuggestionsSheet({required this.destino, required this.suggestions});

  final String destino;
  final List<StopSuggestion> suggestions;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    // Cuando la garita no ha cargado recorridos, el planificador cae a ordenar
    // por cercanía y ninguna sugerencia trae línea. Hay que decirlo.
    final sinRecorridos =
        suggestions.isNotEmpty && suggestions.every((s) => s.recorrido == null);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          0,
          AppSpacing.lg,
          AppSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.flag, color: scheme.primary),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.suggestTitle,
                        style: theme.textTheme.titleMedium,
                      ),
                      Text(
                        destino,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              l10n.suggestSubtitle,
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),

            if (sinRecorridos) ...[
              const SizedBox(height: AppSpacing.md),
              InlineNotice(
                icon: Icons.info_outline,
                message: l10n.suggestNoRoutes,
              ),
            ],

            const SizedBox(height: AppSpacing.md),

            if (suggestions.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
                child: Text(
                  l10n.suggestEmpty,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              )
            else
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.5,
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: suggestions.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: AppSpacing.sm),
                  itemBuilder: (context, index) => _SuggestionCard(
                    suggestion: suggestions[index],
                    // El primero es la recomendación; los demás, alternativas.
                    destacado: index == 0,
                    onTap: () => Navigator.of(context).pop(suggestions[index]),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SuggestionCard extends StatelessWidget {
  const _SuggestionCard({
    required this.suggestion,
    required this.destacado,
    required this.onTap,
  });

  final StopSuggestion suggestion;
  final bool destacado;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final recorrido = suggestion.recorrido;

    return Card(
      color: destacado ? scheme.primaryContainer : null,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.pin_drop,
                    color: destacado
                        ? scheme.onPrimaryContainer
                        : scheme.primary,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      suggestion.stop.name,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: destacado ? scheme.onPrimaryContainer : null,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    l10n.suggestTotal(
                      formatDistance(suggestion.metersTotales, l10n),
                    ),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: destacado
                          ? scheme.onPrimaryContainer
                          : scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),

              _Leg(
                icon: Icons.directions_walk,
                text: l10n.suggestWalkToStop(
                  formatDistance(suggestion.metersToUser, l10n),
                ),
                destacado: destacado,
              ),
              if (recorrido != null) ...[
                _Leg(
                  icon: Icons.directions_car,
                  text: l10n.suggestTakeLine(recorrido.nombre),
                  destacado: destacado,
                  color: Color(recorrido.colorValue),
                ),
                if (suggestion.bajada case final bajada?)
                  _Leg(
                    icon: Icons.logout,
                    text: l10n.suggestGetOff(bajada.name),
                    destacado: destacado,
                  ),
              ],
              _Leg(
                icon: Icons.flag_outlined,
                text: l10n.suggestWalkFromStop(
                  formatDistance(suggestion.metersToDestination, l10n),
                ),
                destacado: destacado,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Leg extends StatelessWidget {
  const _Leg({
    required this.icon,
    required this.text,
    required this.destacado,
    this.color,
  });

  final IconData icon;
  final String text;
  final bool destacado;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final fg = destacado ? scheme.onPrimaryContainer : scheme.onSurfaceVariant;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color ?? fg),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(color: fg),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
