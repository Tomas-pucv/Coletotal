import 'package:flutter/material.dart';

import 'package:taxi1/config/map_config.dart';

/// Miniatura real del estilo de mapa, centrada en Quilpué: la misma
/// cartografía que verá el usuario.
///
/// Degrada con dignidad: el informe insiste en que la app debe seguir siendo
/// usable con conectividad intermitente (RNF-03-01), así que si la foto aérea
/// no llega, el selector muestra un marcador de posición en vez de un hueco
/// roto.
class MapStyleThumbnail extends StatelessWidget {
  const MapStyleThumbnail({super.key, required this.style});

  final MapStyle style;

  @override
  Widget build(BuildContext context) => switch (style) {
    MapStyle.normal => const _StreetsPreview(),
    MapStyle.satellite => const _SatellitePreview(),
  };
}

/// Una captura del mapa de calles en Quilpué, en el tema que corresponda.
///
/// Es una imagen y no un mapa: MapLibre es una vista nativa, y abrir una sólo
/// para un recuadro de 2 cm costaría memoria y un parpadeo al aparecer. Las
/// capturas se toman de la app misma (ver "Mapa base offline" en el README),
/// así que muestran el mismo estilo que los mapas.
class _StreetsPreview extends StatelessWidget {
  const _StreetsPreview();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Image.asset(
      isDark ? 'assets/map/preview_dark.png' : 'assets/map/preview_light.png',
      fit: BoxFit.cover,
    );
  }
}

/// La foto aérea es lo único que sigue viniendo de la red: basta pedir una
/// sola tesela.
class _SatellitePreview extends StatelessWidget {
  const _SatellitePreview();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Image.network(
      satelliteThumbnailUrl(),
      fit: BoxFit.cover,
      // Sin esto la imagen aparece de golpe y el selector "parpadea".
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (wasSynchronouslyLoaded) return child;
        return AnimatedOpacity(
          opacity: frame == null ? 0 : 1,
          duration: const Duration(milliseconds: 200),
          child: child,
        );
      },
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return ColoredBox(
          color: scheme.surfaceContainerHighest,
          child: const Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        );
      },
      errorBuilder: (context, error, stack) => const _SatellitePlaceholder(),
    );
  }
}

/// Sustituto cuando no hay red: sugiere la foto aérea con icono y color en
/// vez de dejar el recuadro vacío.
class _SatellitePlaceholder extends StatelessWidget {
  const _SatellitePlaceholder();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return ColoredBox(
      color: scheme.inverseSurface,
      child: Center(
        child: Icon(
          Icons.satellite_alt,
          size: 32,
          color: scheme.onInverseSurface,
        ),
      ),
    );
  }
}
