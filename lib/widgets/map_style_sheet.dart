import 'package:flutter/material.dart';

import 'package:taxi1/config/map_config.dart';
import 'package:taxi1/l10n/app_localizations.dart';
import 'package:taxi1/screens/main_screen.dart';
import 'package:taxi1/services/preferences_service.dart';
import 'package:taxi1/theme/app_spacing.dart';
import 'package:taxi1/widgets/map_style_thumbnail.dart';
import 'package:taxi1/widgets/option_card_picker.dart';

/// Hoja de capas del mapa.
///
/// Cambiar entre calles y satélite es, de lejos, el ajuste que más se toca
/// mientras se usa el mapa, así que se elige acá, sobre el propio mapa, y no
/// en Preferencias, donde estaba repetido. La hoja tiene un atajo al resto
/// de los ajustes.
Future<void> showMapStyleSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) => const _MapStyleSheet(),
  );
}

class _MapStyleSheet extends StatefulWidget {
  const _MapStyleSheet();

  @override
  State<_MapStyleSheet> createState() => _MapStyleSheetState();
}

class _MapStyleSheetState extends State<_MapStyleSheet> {
  final prefs = PreferencesService.instance;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

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
            Text(l10n.mapLayers, style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.lg),
            OptionCardPicker<MapStyle>(
              value: MapStyle.fromPref(prefs.mapType),
              onChanged: (style) async {
                await prefs.setMapType(style.prefValue);
                if (mounted) setState(() {});
              },
              options: [
                OptionCard(
                  value: MapStyle.normal,
                  label: l10n.mapNormal,
                  description: l10n.mapNormalDesc,
                  preview: const MapStyleThumbnail(style: MapStyle.normal),
                ),
                OptionCard(
                  value: MapStyle.satellite,
                  label: l10n.satellite,
                  description: l10n.satelliteDesc,
                  preview: const MapStyleThumbnail(style: MapStyle.satellite),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.tune),
              title: Text(l10n.moreSettings),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                // Se captura el Navigator raíz antes de cerrar la hoja: el
                // `context` de este ListTile deja de estar montado en cuanto se
                // hace `pop`, y `openPreferences` puede necesitarlo para apilar
                // la pantalla (chofer y administrador no tienen Preferencias
                // como pestaña).
                final root = Navigator.of(context, rootNavigator: true).context;
                Navigator.pop(context);
                MainNavigationController.instance.openPreferences(root);
              },
            ),
          ],
        ),
      ),
    );
  }
}
