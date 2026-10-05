import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import 'package:taxi1/config/map_config.dart';

/// Capa de teselas común a los tres mapas de la app (pasajero, flota y editor
/// de paraderos).
///
/// Antes cada pantalla armaba su propio `TileLayer` y habían divergido: sólo
/// uno usaba retina, sólo dos tenían respaldo y cada uno se identificaba con
/// un User-Agent distinto.
///
/// Es `StatefulWidget` para crear **un solo** `NetworkTileProvider`. Si no se
/// pasa uno, `TileLayer` crea uno nuevo, con su propio cliente HTTP, en cada
/// reconstrucción. El mapa se reconstruye con cada posición GPS y cada
/// colectivo que se mueve, y cada cliente nuevo pierde las conexiones ya
/// abiertas con el servidor de teselas.
class AppTileLayer extends StatefulWidget {
  const AppTileLayer({super.key, this.style = MapStyle.normal});

  final MapStyle style;

  @override
  State<AppTileLayer> createState() => _AppTileLayerState();
}

class _AppTileLayerState extends State<AppTileLayer> {
  // No se libera acá: `TileLayer` libera su proveedor al desmontarse.
  final TileProvider _tileProvider = NetworkTileProvider();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return TileLayer(
      urlTemplate: mapTileUrlTemplate(widget.style, isDark: isDark),
      fallbackUrl: fallbackTileUrlTemplate(widget.style, isDark: isDark),
      userAgentPackageName: kTileUserAgentPackage,
      retinaMode: RetinaMode.isHighDensity(context),
      tileProvider: _tileProvider,
    );
  }
}
