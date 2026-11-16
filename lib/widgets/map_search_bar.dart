import 'dart:async';

import 'package:flutter/material.dart';

import 'package:taxi1/l10n/app_localizations.dart';
import 'package:taxi1/models/place_result.dart';
import 'package:taxi1/services/geocoding_service.dart';
import 'package:taxi1/theme/app_spacing.dart';
import 'package:taxi1/widgets/map_overlay_card.dart';

/// Buscador de direcciones sobre el mapa.
///
/// Cambia la pregunta que responde la app. Hasta ahora el pasajero elegía un
/// paradero de una lista y veía cómo llegar a él; con esto declara *a dónde
/// quiere ir* y la app decide el paradero (ver `StopPlanner`), que es como
/// funciona la cabeza de quien está parado en la calle.
class MapSearchBar extends StatefulWidget {
  const MapSearchBar({
    super.key,
    required this.onSelected,
    this.destinationLabel,
    this.onCleared,
    this.leading,
  });

  /// Se llama con la dirección elegida.
  final ValueChanged<PlaceResult> onSelected;

  /// Texto del destino ya fijado, si lo hay. Cuando no es nulo la barra se
  /// muestra "resuelta", con una X para soltarlo.
  final String? destinationLabel;

  final VoidCallback? onCleared;

  /// Va dentro de la barra, a la izquierda, en lugar de la lupa: el botón del
  /// menú, como en Google Maps. La bandera de un destino fijado se mantiene.
  final Widget? leading;

  @override
  State<MapSearchBar> createState() => _MapSearchBarState();
}

class _MapSearchBarState extends State<MapSearchBar> {
  final _controller = TextEditingController();
  final _focus = FocusNode();

  Timer? _debounce;
  List<PlaceResult> _results = const [];
  bool _searching = false;
  bool _open = false;

  /// Descarta respuestas que llegan tarde: sin esto, una consulta lenta de hace
  /// tres letras puede pisar los resultados de la que el usuario ve ahora.
  int _request = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    final q = value.trim();

    if (q.length < 3) {
      setState(() {
        _results = const [];
        _searching = false;
        _open = false;
      });
      return;
    }

    setState(() {
      _searching = true;
      _open = true;
    });
    // Medio segundo: buscar en cada pulsación satura al servidor público de
    // Photon (que pide un uso moderado) y hace parpadear la lista mientras se
    // escribe.
    _debounce = Timer(const Duration(milliseconds: 500), () => _run(q));
  }

  Future<void> _run(String query) async {
    final request = ++_request;
    final results = await GeocodingService.search(query);
    if (!mounted || request != _request) return;
    setState(() {
      _results = results;
      _searching = false;
    });
  }

  void _select(PlaceResult place) {
    _focus.unfocus();
    _controller.clear();
    setState(() {
      _results = const [];
      _open = false;
      _searching = false;
    });
    widget.onSelected(place);
  }

  void _clear() {
    _debounce?.cancel();
    _controller.clear();
    _focus.unfocus();
    setState(() {
      _results = const [];
      _open = false;
      _searching = false;
    });
    widget.onCleared?.call();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final destino = widget.destinationLabel;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MapOverlayCard(
          padding: EdgeInsets.zero,
          child: Row(
            children: [
              if (widget.leading case final leading?)
                Padding(
                  padding: const EdgeInsets.only(left: AppSpacing.xs),
                  child: leading,
                ),
              if (widget.leading == null || destino != null)
                Padding(
                  padding: EdgeInsets.only(
                    left: widget.leading == null ? AppSpacing.md : 0,
                  ),
                  child: Icon(
                    destino == null ? Icons.search : Icons.flag,
                    color: destino == null
                        ? scheme.onSurfaceVariant
                        : scheme.primary,
                  ),
                ),
              Expanded(
                child: destino == null
                    ? TextField(
                        controller: _controller,
                        focusNode: _focus,
                        onChanged: _onChanged,
                        textInputAction: TextInputAction.search,
                        onSubmitted: (v) {
                          _debounce?.cancel();
                          if (v.trim().length >= 3) _run(v.trim());
                        },
                        decoration: InputDecoration(
                          hintText: l10n.searchAddressHint,
                          // La tarjeta ya aporta el fondo y el borde; el
                          // decorador del tema los duplicaría.
                          filled: false,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.md,
                            vertical: AppSpacing.md,
                          ),
                        ),
                      )
                    : Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md,
                          vertical: AppSpacing.md,
                        ),
                        child: Text(
                          destino,
                          style: theme.textTheme.bodyMedium,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
              ),
              if (destino != null || _controller.text.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: l10n.searchClear,
                  onPressed: _clear,
                ),
            ],
          ),
        ),

        if (_open) ...[
          const SizedBox(height: AppSpacing.sm),
          MapOverlayCard(
            padding: EdgeInsets.zero,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.35,
              ),
              child: _searching
                  ? Padding(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      child: Row(
                        children: [
                          const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          const SizedBox(width: AppSpacing.md),
                          Text(
                            l10n.searchSearching,
                            style: theme.textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    )
                  : _results.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      child: Text(
                        l10n.searchNoResults,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      padding: EdgeInsets.zero,
                      itemCount: _results.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final place = _results[index];
                        return ListTile(
                          dense: true,
                          leading: Icon(
                            place.isPoi
                                ? Icons.stars_rounded
                                : Icons.place_outlined,
                            color: place.isPoi ? scheme.primary : null,
                          ),
                          title: Text(
                            place.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: place.isPoi
                                ? const TextStyle(fontWeight: FontWeight.w600)
                                : null,
                          ),
                          subtitle: place.address.isEmpty
                              ? null
                              : Text(
                                  place.address,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                          onTap: () => _select(place),
                        );
                      },
                    ),
            ),
          ),
        ],
      ],
    );
  }
}
