import 'package:flutter/material.dart';

import 'package:taxi1/l10n/app_localizations.dart';
import 'package:taxi1/models/recorrido.dart';
import 'package:taxi1/services/line_planner.dart';
import 'package:taxi1/theme/app_spacing.dart';
import 'package:taxi1/utils/distance_format.dart';

/// Nombre del sentido, para mostrar.
String sentidoLabel(Sentido sentido, AppLocalizations l10n) =>
    switch (sentido) {
      Sentido.ida => l10n.sentidoIda,
      Sentido.vuelta => l10n.sentidoVuelta,
    };

/// Muestra qué colectivo conviene tomar para llegar al destino buscado.
///
/// Cada tarjeta enseña los tramos del viaje —lo que se camina hasta la línea,
/// lo que se va arriba y lo que se camina desde la bajada—, en vez de un
/// número de ranking opaco: así se ve por qué la primera es la primera.
Future<LineSuggestion?> showLineSuggestionsSheet(
  BuildContext context, {
  required String destino,
  required List<LineSuggestion> suggestions,
}) {
  return showModalBottomSheet<LineSuggestion>(
    context: context,
    isScrollControlled: true,
    builder: (_) =>
        _SuggestionsSheet(destino: destino, suggestions: suggestions),
  );
}

class _SuggestionsSheet extends StatelessWidget {
  const _SuggestionsSheet({required this.destino, required this.suggestions});

  final String destino;
  final List<LineSuggestion> suggestions;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

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
            if (suggestions.isNotEmpty)
              Text(
                l10n.suggestSubtitle,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
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
                    // La primera es la recomendación; las demás, alternativas.
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

  final LineSuggestion suggestion;
  final bool destacado;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final linea = suggestion.recorrido;
    final fg = destacado ? scheme.onPrimaryContainer : null;

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
                  CircleAvatar(
                    radius: 12,
                    backgroundColor: Color(linea.colorValue),
                    child: const Icon(
                      Icons.directions_car,
                      size: 14,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      linea.nombre,
                      style: theme.textTheme.titleSmall?.copyWith(color: fg),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    l10n.suggestTotal(
                      formatDistance(suggestion.metrosAPie, l10n),
                    ),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: fg ?? scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              _Leg(
                icon: Icons.directions_walk,
                text: l10n.suggestWalkToLine(
                  formatDistance(suggestion.metrosHastaLinea, l10n),
                ),
                destacado: destacado,
              ),
              _Leg(
                icon: Icons.directions_car,
                color: Color(linea.colorValue),
                text:
                    '${l10n.suggestTakeLine(linea.nombre, sentidoLabel(suggestion.sentido, l10n).toLowerCase())}'
                    ' · ${l10n.suggestRide(formatDistance(suggestion.metrosEnColectivo, l10n))}',
                destacado: destacado,
              ),
              _Leg(
                icon: Icons.flag_outlined,
                text: l10n.suggestWalkFromLine(
                  formatDistance(suggestion.metrosDesdeLinea, l10n),
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
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
