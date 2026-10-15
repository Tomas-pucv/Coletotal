import 'package:flutter/material.dart';

import 'package:taxi1/l10n/app_localizations.dart';
import 'package:taxi1/models/recorrido.dart';
import 'package:taxi1/navigation/app_destination.dart';
import 'package:taxi1/screens/main_screen.dart';
import 'package:taxi1/services/firebase_telemetria_service.dart';
import 'package:taxi1/services/line_planner.dart';
import 'package:taxi1/services/location_service.dart';
import 'package:taxi1/services/recorridos_service.dart';
import 'package:taxi1/theme/app_spacing.dart';
import 'package:taxi1/theme/breakpoints.dart';
import 'package:taxi1/utils/distance_format.dart';
import 'package:taxi1/utils/text_search.dart';
import 'package:taxi1/widgets/state_views.dart';

/// La pestaña Líneas: las líneas activas de la garita, de la que pasa más
/// cerca a la más lejos.
///
/// Reemplaza a la pestaña Paraderos. Los colectivos no tienen paraderos
/// —paran donde se les hace la seña—, así que lo que el pasajero necesita
/// saber es qué líneas pasan cerca y por dónde van. Tocar una la dibuja en el
/// mapa.
class LineasScreen extends StatefulWidget {
  const LineasScreen({super.key});

  @override
  State<LineasScreen> createState() => _LineasScreenState();
}

class _LineasScreenState extends State<LineasScreen> {
  final _recorridos = RecorridosService.instance;
  final _location = LocationService.instance;
  final _telemetria = FirebaseTelemetriaService.instance;
  final _busqueda = TextEditingController();

  @override
  void initState() {
    super.initState();
    _recorridos.addListener(_onChanged);
    _location.addListener(_onChanged);
    _telemetria.state.addListener(_onChanged);
    _busqueda.addListener(_onChanged);
  }

  @override
  void dispose() {
    _recorridos.removeListener(_onChanged);
    _location.removeListener(_onChanged);
    _telemetria.state.removeListener(_onChanged);
    _busqueda.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  void _verEnMapa(Recorrido linea) {
    _recorridos.select(linea, encuadrar: true);
    MainNavigationController.instance.showMap();
  }

  /// Las líneas a mostrar, filtradas por la búsqueda: con ubicación, de la más
  /// cercana a la más lejana; sin ella, por nombre.
  List<({Recorrido linea, double? metros, int enServicio})> _filas() {
    final posicion = _location.position;
    final query = _busqueda.text;
    final colectivos = _telemetria.state.value.colectivos;
    final filas = [
      for (final linea in _recorridos.publicas)
        if (matchesAllTokens(query, [
          linea.nombre,
          linea.linea,
          linea.codigoVariante,
          linea.nombreVariante,
          ...linea.callesIda,
          ...linea.callesVuelta,
        ]))
          (
            linea: linea,
            metros: posicion == null
                ? null
                : LinePlanner.metrosHasta(linea, posicion),
            enServicio: colectivos
                .where((c) => c.recorridoId == linea.id)
                .length,
          ),
    ];
    if (posicion != null) {
      filas.sort(
        (a, b) => (a.metros ?? double.infinity).compareTo(
          b.metros ?? double.infinity,
        ),
      );
    }
    return filas;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final hayLineas = _recorridos.publicas.isNotEmpty;
    final filas = _filas();

    final Widget cuerpo;
    if (!_recorridos.loaded) {
      cuerpo = const Center(child: CircularProgressIndicator());
    } else if (!hayLineas) {
      cuerpo = StatusMessageView(
        icon: Icons.route_outlined,
        title: l10n.linesEmpty,
      );
    } else {
      cuerpo = Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.sm,
              AppSpacing.lg,
              AppSpacing.sm,
            ),
            child: TextField(
              controller: _busqueda,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: l10n.linesSearchHint,
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _busqueda.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close),
                        tooltip: l10n.searchClear,
                        onPressed: _busqueda.clear,
                      ),
              ),
            ),
          ),
          Expanded(
            child: filas.isEmpty
                ? StatusMessageView(
                    icon: Icons.search_off,
                    title: l10n.linesNoMatch,
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg,
                      AppSpacing.sm,
                      AppSpacing.lg,
                      AppSpacing.xxl,
                    ),
                    itemCount: filas.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: AppSpacing.sm),
                    itemBuilder: (context, i) => _LineaTile(
                      linea: filas[i].linea,
                      metros: filas[i].metros,
                      enServicio: filas[i].enServicio,
                      onTap: () => _verEnMapa(filas[i].linea),
                    ),
                  ),
          ),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(AppDestination.rutas.label(l10n)),
        leading: IconButton(
          icon: const Icon(Icons.menu),
          tooltip: l10n.openMenu,
          onPressed: MainNavigationController.instance.openDrawer,
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: Breakpoints.maxContentWidth,
          ),
          child: cuerpo,
        ),
      ),
    );
  }
}

class _LineaTile extends StatelessWidget {
  const _LineaTile({
    required this.linea,
    required this.metros,
    required this.enServicio,
    required this.onTap,
  });

  final Recorrido linea;
  final double? metros;
  final int enServicio;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final detalles = [
      if (metros case final m?) l10n.linesPassesAt(formatDistance(m, l10n)),
      if (enServicio > 0) l10n.fleetUnitsInService('$enServicio'),
      if (linea.vuelta == null) l10n.linesOnlyIda,
    ];

    return Card(
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          backgroundColor: Color(linea.colorValue),
          child: const Icon(Icons.directions_car, color: Colors.white),
        ),
        title: Text(linea.nombre),
        subtitle: detalles.isEmpty ? null : Text(detalles.join(' · ')),
        trailing: Icon(Icons.map_outlined, semanticLabel: l10n.lineShowOnMap),
      ),
    );
  }
}
