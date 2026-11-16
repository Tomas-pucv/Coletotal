import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:taxi1/config/map_config.dart';
import 'package:taxi1/theme/app_spacing.dart';

/// Crédito de los datos del mapa, sobre una esquina del mapa.
///
/// Lo exige la licencia de OpenStreetMap (ODbL) para todo mapa hecho con sus
/// datos, y Esri para su foto aérea. Antes no se mostraba en ningún mapa,
/// aunque MapTiler también lo pedía.
///
/// Va siempre a la vista, como recomienda la fundación OSM, y en la esquina
/// que se le indique (en el editor de paraderos el aviso "mantén presionado"
/// ocupa todo el borde inferior). Reemplaza al botón "i" de MapLibre, que
/// esconde el crédito detrás de un toque. Al tocarlo abre la página de
/// derechos de OSM.
class MapAttribution extends StatelessWidget {
  const MapAttribution({
    super.key,
    this.style = MapStyle.normal,
    this.alignment = Alignment.bottomLeft,
  });

  final MapStyle style;
  final Alignment alignment;

  static final Uri _osmCopyright = Uri.parse(
    'https://www.openstreetmap.org/copyright',
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final texto = style == MapStyle.satellite
        ? '© OpenStreetMap · Esri'
        : '© OpenStreetMap';

    return SafeArea(
      child: Align(
        alignment: alignment,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xs),
          child: Material(
            color: theme.colorScheme.surface.withValues(alpha: 0.8),
            borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => launchUrl(
                _osmCopyright,
                mode: LaunchMode.externalApplication,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.xs / 2,
                ),
                child: Text(
                  texto,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
