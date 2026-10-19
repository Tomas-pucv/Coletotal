import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'package:taxi1/config/map_config.dart';
import 'package:taxi1/l10n/app_localizations.dart';
import 'package:taxi1/models/app_user.dart';
import 'package:taxi1/models/colectivo_activo.dart';
import 'package:taxi1/models/recorrido.dart';
import 'package:taxi1/navigation/app_destination.dart';
import 'package:taxi1/screens/main_screen.dart';
import 'package:taxi1/services/auth_service.dart';
import 'package:taxi1/services/firebase_telemetria_service.dart';
import 'package:taxi1/services/location_service.dart';
import 'package:taxi1/services/preferences_service.dart';
import 'package:taxi1/services/recorridos_service.dart';
import 'package:taxi1/services/segundo_plano.dart';
import 'package:taxi1/services/turno_service.dart';
import 'package:taxi1/theme/app_colors.dart';
import 'package:taxi1/theme/app_spacing.dart';
import 'package:taxi1/theme/breakpoints.dart';
import 'package:taxi1/utils/navegacion.dart';
import 'package:taxi1/utils/tile_coords.dart';
import 'package:taxi1/widgets/app_map.dart';
import 'package:taxi1/widgets/colectivo_marker.dart';
import 'package:taxi1/widgets/map_overlay_card.dart';
import 'package:taxi1/widgets/map_style_sheet.dart';
import 'package:taxi1/widgets/recorrido_lines.dart';
import 'package:taxi1/widgets/state_views.dart';

/// Pantalla de jornada del colectivero — el "módulo conductor" del informe
/// (§7.3.1-A) —, armada como un navegador: el mapa entero y el chofer como una
/// flecha.
///
/// Fuera de turno, la cámara lo sigue con el norte arriba y abajo está el
/// botón grande de "Iniciar turno". En turno, la cámara se inclina y gira con
/// el sentido de marcha, como en Google Maps, y abajo quedan sólo los controles
/// que se tocan manejando: la capacidad (un toque) y "Terminar turno". Su línea
/// va resaltada, con las flechas de su sentido, y los demás colectivos a la
/// vista.
class TurnoScreen extends StatefulWidget {
  const TurnoScreen({super.key});

  /// Cuánto queda la flecha por encima del panel de abajo, en navegación.
  static const double flechaSobreElPanel = 110;

  /// Alto de los controles del panel de abajo: cómodos de tocar manejando,
  /// en una sola fila.
  static const double altoControles = 48;

  @override
  State<TurnoScreen> createState() => _TurnoScreenState();
}

class _TurnoScreenState extends State<TurnoScreen> {
  final _turno = TurnoService.instance;
  final _auth = AuthService.instance;
  final _recorridos = RecorridosService.instance;
  final _prefs = PreferencesService.instance;
  final _nav = MainNavigationController.instance;
  final _mapController = AppMapController();

  /// Si la cámara sigue a la flecha. Un gesto sobre el mapa la suelta y
  /// "Volver a centrar" la retoma.
  bool _siguiendo = true;
  bool _estabaEnTurno = false;

  /// En turno, la vista de navegación (inclinada, girando con el sentido de
  /// marcha) o la plana con el norte arriba. El botón 2D/3D la cambia; cada
  /// turno empieza en navegación.
  bool _vista3d = true;

  /// Zoom de la navegación ([zoomParaVelocidad]) y cuándo cambió por última
  /// vez: cambia como mucho cada [_esperaZoom], porque cada cambio suelta y
  /// retoma el seguimiento de la cámara.
  double _zoomNavegacion = kZoomsNavegacion.first;
  DateTime _cambioZoom = DateTime.fromMillisecondsSinceEpoch(0);
  static const _esperaZoom = Duration(seconds: 8);

  /// El alto del panel de abajo, para dejar la flecha justo encima.
  final _panelKey = GlobalKey();
  double _altoPanel = 0;

  bool _pantallaEncendida = false;

  @override
  void initState() {
    super.initState();
    _estabaEnTurno = _turno.enTurno;
    _turno.addListener(_onChanged);
    _auth.addListener(_onChanged);
    _prefs.addListener(_onChanged);
    _nav.addListener(_onChanged);
    _recorridos.addListener(_onRecorridosChanged);
    _actualizarPantalla();
  }

  @override
  void dispose() {
    _turno.removeListener(_onChanged);
    _auth.removeListener(_onChanged);
    _prefs.removeListener(_onChanged);
    _nav.removeListener(_onChanged);
    _recorridos.removeListener(_onRecorridosChanged);
    if (_pantallaEncendida) unawaited(_encenderPantalla(false));
    super.dispose();
  }

  void _onChanged() {
    final enTurno = _turno.enTurno;
    if (enTurno != _estabaEnTurno) {
      _estabaEnTurno = enTurno;
      // Al iniciar o terminar el turno la cámara vuelve a la flecha: en
      // navegación, o en la vista de siempre.
      _siguiendo = true;
      _vista3d = true;
    }
    _actualizarPantalla();
    if (mounted) setState(() {});
  }

  /// Una línea elegida en la pestaña Líneas se muestra entera; para volver a
  /// la flecha está "Volver a centrar".
  void _onRecorridosChanged() {
    final linea = _recorridos.selected;
    if (linea != null && _recorridos.tomarEncuadre()) {
      _siguiendo = false;
      unawaited(_encuadrar(linea));
    }
    _onChanged();
  }

  Future<void> _encuadrar(Recorrido linea) async {
    final puntos = [for (final (_, t) in linea.trayectos) ...t.trazado];
    if (puntos.isEmpty || !mounted) return;
    final size = MediaQuery.sizeOf(context);
    final vista = encuadre(
      puntos,
      ancho: size.width,
      alto: size.height * 0.55,
      zoomMaximo: kStreetZoom,
    );
    await _mapController.animateToOverview(vista.centro, zoom: vista.zoom);
  }

  /// La pantalla queda encendida durante el turno, mientras se ve esta
  /// pestaña. Al salir de la app Android la suelta solo.
  void _actualizarPantalla() {
    final encender = _turno.enTurno && _nav.destination == AppDestination.turno;
    if (encender == _pantallaEncendida) return;
    _pantallaEncendida = encender;
    unawaited(_encenderPantalla(encender));
  }

  static Future<void> _encenderPantalla(bool encender) async {
    try {
      await WakelockPlus.toggle(enable: encender);
    } catch (e) {
      // Sin el plugin (pruebas, escritorio) la pantalla sigue su curso.
      debugPrint('TurnoScreen: no se pudo cambiar el bloqueo de pantalla: $e');
    }
  }

  /// Si el chofer ya aceptó compartir su ubicación durante el turno.
  static const _claveConsentimiento = 'turno_consentimiento_aceptado';

  /// El aviso de la Ley 19.628 antes del primer turno: qué se comparte, con
  /// quién y hasta cuándo. Antes iba siempre a la vista en el panel; ahora se
  /// acepta una vez y queda en el botón (i).
  Future<bool> _aceptarConsentimiento(AppLocalizations l10n) async {
    try {
      final sp = await SharedPreferences.getInstance();
      if (sp.getBool(_claveConsentimiento) == true) return true;
    } catch (_) {}
    if (!mounted) return false;
    final acepta = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.privacy_tip_outlined),
        title: Text(l10n.turnoConsentTitle),
        content: Text(l10n.turnoConsent),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.turnoStart),
          ),
        ],
      ),
    );
    if (acepta != true) return false;
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setBool(_claveConsentimiento, true);
    } catch (_) {}
    return true;
  }

  Future<void> _mostrarConsentimiento(AppLocalizations l10n) =>
      showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          icon: const Icon(Icons.privacy_tip_outlined),
          title: Text(l10n.turnoConsentTitle),
          content: Text(l10n.turnoConsent),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(MaterialLocalizations.of(context).okButtonLabel),
            ),
          ],
        ),
      );

  /// Antes de transmitir: el consentimiento la primera vez, y lo que el turno
  /// necesita para seguir con la pantalla bloqueada o en otra app (ver
  /// [SegundoPlano]). En Xiaomi, además, un aviso para dejar la app sin
  /// restricciones, una sola vez.
  Future<void> _iniciarTurno() async {
    if (!await _aceptarConsentimiento(AppLocalizations.of(context)!)) return;
    final avisoXiaomi = await SegundoPlano.preparar();
    if (!mounted) return;
    await _turno.iniciarTurno();
    if (!mounted || !avisoXiaomi || !_turno.enTurno) return;
    await SegundoPlano.marcarAvisoXiaomi();
    if (!mounted) return;
    final l10n = AppLocalizations.of(context)!;
    final abrir = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.battery_alert_outlined),
        title: Text(l10n.turnoXiaomiTitle),
        content: Text(l10n.turnoXiaomiBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.turnoXiaomiLater),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.turnoXiaomiOpen),
          ),
        ],
      ),
    );
    if (abrir == true) await SegundoPlano.abrirAjustes();
  }

  double _zoomPara(double? metrosPorSegundo) {
    final ahora = DateTime.now();
    if (ahora.difference(_cambioZoom) < _esperaZoom) return _zoomNavegacion;
    final zoom = zoomParaVelocidad(
      metrosPorSegundo == null ? null : metrosPorSegundo * 3.6,
      _zoomNavegacion,
    );
    if (zoom != _zoomNavegacion) {
      _zoomNavegacion = zoom;
      _cambioZoom = ahora;
    }
    return _zoomNavegacion;
  }

  void _medirPanel() {
    final alto = _panelKey.currentContext?.size?.height;
    if (alto == null || !mounted) return;
    // Redondeado: un píxel de diferencia no justifica mover la cámara.
    final redondeado = (alto / 8).round() * 8.0;
    if (redondeado != _altoPanel) setState(() => _altoPanel = redondeado);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final profile = _auth.profile;

    if (profile == null || profile.rol != UserRole.colectivero) {
      return Scaffold(
        appBar: AppBar(
          title: Text(l10n.turnoTitle),
          leading: IconButton(
            icon: const Icon(Icons.menu),
            tooltip: l10n.openMenu,
            onPressed: _nav.openDrawer,
          ),
        ),
        body: StatusMessageView(
          icon: Icons.local_taxi_outlined,
          title: l10n.turnoTitle,
          message: l10n.turnoOnlyDrivers,
        ),
      );
    }

    WidgetsBinding.instance.addPostFrameCallback((_) => _medirPanel());
    final enTurno = _turno.enTurno;
    final abajoSeguro = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          // La cámara de navegación se centra entre los márgenes: abajo, el
          // panel; arriba, lo justo para que la flecha quede a
          // [TurnoScreen.flechaSobreElPanel] del panel y se vea el camino.
          final abajo = _altoPanel + AppSpacing.lg + abajoSeguro;
          final arriba = math.max(
            0.0,
            constraints.maxHeight - abajo - 2 * TurnoScreen.flechaSobreElPanel,
          );
          return Stack(
            children: [
              _MapaTurno(
                controller: _mapController,
                style: MapStyle.fromPref(_prefs.mapType),
                follow: !_siguiendo
                    ? MapFollow.none
                    : enTurno && _vista3d
                    ? MapFollow.navigation
                    : MapFollow.position,
                insets: EdgeInsets.only(top: arriba, bottom: abajo),
                zoomPara: _zoomPara,
                onUserGesture: () {
                  if (_siguiendo) setState(() => _siguiendo = false);
                },
              ),
              Positioned.fill(
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // La píldora de estado y, a su lado, los botones
                        // del mapa: una sola franja arriba.
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: _barraEstado(l10n)),
                            const SizedBox(width: AppSpacing.sm),
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                FloatingActionButton.small(
                                  heroTag: 'turno_capas',
                                  tooltip: l10n.mapLayers,
                                  onPressed: () => showMapStyleSheet(context),
                                  child: const Icon(Icons.layers_outlined),
                                ),
                                if (enTurno) ...[
                                  const SizedBox(height: AppSpacing.sm),
                                  FloatingActionButton.small(
                                    heroTag: 'turno_vista',
                                    tooltip: _vista3d
                                        ? l10n.turnoView2d
                                        : l10n.turnoView3d,
                                    // Cambiar de vista también vuelve a la
                                    // flecha, como en Google Maps.
                                    onPressed: () => setState(() {
                                      _vista3d = !_vista3d;
                                      _siguiendo = true;
                                    }),
                                    child: Text(
                                      _vista3d ? '2D' : '3D',
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelLarge
                                          ?.copyWith(
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                        Expanded(
                          child: Align(
                            alignment: Alignment.bottomCenter,
                            // En horizontal el panel puede no caber entero.
                            child: SingleChildScrollView(
                              reverse: true,
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: Breakpoints.maxContentWidth,
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    if (!_siguiendo) ...[
                                      Align(
                                        alignment: Alignment.centerLeft,
                                        child: _BotonRecentrar(
                                          label: l10n.turnoRecenter,
                                          onPressed: () =>
                                              setState(() => _siguiendo = true),
                                        ),
                                      ),
                                      const SizedBox(height: AppSpacing.md),
                                    ],
                                    ..._tarjetaLinea(l10n),
                                    KeyedSubtree(
                                      key: _panelKey,
                                      child: enTurno
                                          ? _panelEnTurno(l10n)
                                          : _panelFueraDeTurno(l10n),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Arriba, siempre a la vista: el menú, si se está transmitiendo y, en
  /// turno, la línea (tocarla la cambia). Desde el asiento del conductor tiene
  /// que leerse de un vistazo, sin tapar el mapa.
  Widget _barraEstado(AppLocalizations l10n) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final status = AppStatusColors.of(context);
    final activo = _turno.enTurno;
    final linea = _turno.recorridoAsignado;
    final puedeCambiar = activo && _turno.recorridosDisponibles.isNotEmpty;

    return MapOverlayCard(
      padding: const EdgeInsets.only(right: AppSpacing.md),
      onTap: puedeCambiar ? () => _pickRecorrido(l10n) : null,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.menu),
                tooltip: l10n.openMenu,
                visualDensity: VisualDensity.compact,
                onPressed: _nav.openDrawer,
              ),
              Icon(
                Icons.circle,
                size: 10,
                color: activo ? status.disponible : scheme.outline,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: activo ? l10n.turnoOn : l10n.turnoOff,
                        style: theme.textTheme.labelLarge,
                      ),
                      if (activo && linea != null)
                        TextSpan(
                          text: ' · ${linea.nombre}',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          if (activo) const _AvisoSinSenal(),
        ],
      ),
    );
  }

  /// La línea que se está viendo, si se eligió otra en la pestaña Líneas. La X
  /// vuelve a la línea del turno.
  List<Widget> _tarjetaLinea(AppLocalizations l10n) {
    final linea = _recorridos.selected;
    if (linea == null) return const [];
    return [
      MapOverlayCard(
        padding: const EdgeInsets.only(left: AppSpacing.md),
        child: Row(
          children: [
            Icon(Icons.circle, size: 10, color: Color(linea.colorValue)),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                l10n.lineOnMap(linea.nombre),
                style: Theme.of(context).textTheme.labelLarge,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 20),
              tooltip: l10n.clearLine,
              visualDensity: VisualDensity.compact,
              onPressed: _recorridos.clearSelection,
            ),
          ],
        ),
      ),
      const SizedBox(height: AppSpacing.sm),
    ];
  }

  /// Fuera de turno, una sola fila: la línea a cubrir, "Iniciar turno" y el
  /// botón que explica qué se comparte.
  Widget _panelFueraDeTurno(AppLocalizations l10n) {
    final theme = Theme.of(context);
    final issue = _issueMessage(l10n);

    return _TarjetaInferior(
      aviso: issue,
      child: Row(
        children: [
          Expanded(child: _chipLinea(l10n)),
          const SizedBox(width: AppSpacing.sm),
          FilledButton.icon(
            onPressed: _turno.busy ? null : _iniciarTurno,
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, TurnoScreen.altoControles),
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              textStyle: theme.textTheme.titleSmall,
            ),
            icon: _turno.busy
                ? const _Girando()
                : const Icon(Icons.navigation, size: 20),
            label: Text(l10n.turnoStart),
          ),
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: l10n.turnoConsentTitle,
            onPressed: () => _mostrarConsentimiento(l10n),
          ),
        ],
      ),
    );
  }

  /// En turno, una sola fila: la capacidad como tres píldoras de semáforo,
  /// que se tocan manejando, y un botón cuadrado para terminar.
  ///
  /// La píldora elegida se rellena con su color; las otras llevan un punto
  /// del suyo. Sin íconos dentro de la elegida, el texto cabe entero: en un
  /// teléfono de 384 dp cada píldora mide unos 90 px.
  Widget _panelEnTurno(AppLocalizations l10n) {
    final scheme = Theme.of(context).colorScheme;
    final status = AppStatusColors.of(context);
    final issue = _issueMessage(l10n);

    Widget pildora(EstadoCapacidad estado, String texto, Color color) =>
        Expanded(
          child: _PildoraCapacidad(
            texto: texto,
            color: color,
            elegida: _turno.estado == estado,
            onTap: () => _turno.setEstado(estado),
          ),
        );

    return _TarjetaInferior(
      aviso: issue,
      child: Row(
        children: [
          pildora(
            EstadoCapacidad.disponible,
            l10n.capacityAvailable,
            status.disponible,
          ),
          const SizedBox(width: AppSpacing.xs),
          pildora(
            EstadoCapacidad.medioLleno,
            l10n.capacityHalf,
            status.medioLleno,
          ),
          const SizedBox(width: AppSpacing.xs),
          pildora(EstadoCapacidad.lleno, l10n.capacityFull, status.lleno),
          const SizedBox(width: AppSpacing.sm),
          // Terminar el turno pide confirmación: es un botón chico al lado de
          // los que se tocan manejando, y un toque de más sacaría al colectivo
          // del mapa de los pasajeros.
          SizedBox.square(
            dimension: TurnoScreen.altoControles,
            child: IconButton.filled(
              onPressed: _turno.busy ? null : () => _confirmarFin(l10n),
              tooltip: l10n.turnoEnd,
              style: IconButton.styleFrom(
                backgroundColor: scheme.errorContainer,
                foregroundColor: scheme.onErrorContainer,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppSpacing.md),
                ),
              ),
              icon: _turno.busy
                  ? const _Girando()
                  : const Icon(Icons.stop_rounded, size: 28),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmarFin(AppLocalizations l10n) async {
    final scheme = Theme.of(context).colorScheme;
    final terminar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.turnoEndConfirmTitle),
        content: Text(l10n.turnoEndConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: scheme.error,
              foregroundColor: scheme.onError,
            ),
            child: Text(l10n.turnoEnd),
          ),
        ],
      ),
    );
    if (terminar == true) await _turno.terminarTurno();
  }

  /// La línea a cubrir, como una píldora: tocarla abre la lista. Es lo que ve
  /// el pasajero al tocar el colectivo en el mapa: su trazado se ilumina.
  Widget _chipLinea(AppLocalizations l10n) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final recorrido = _turno.recorridoAsignado;
    final opciones = _turno.recorridosDisponibles;

    return Material(
      color: scheme.surfaceContainerHighest,
      shape: const StadiumBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: opciones.isEmpty ? null : () => _pickRecorrido(l10n),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: TurnoScreen.altoControles,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: Row(
              children: [
                Icon(
                  Icons.circle,
                  size: 12,
                  color: recorrido == null
                      ? scheme.outline
                      : Color(recorrido.colorValue),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    recorrido?.nombre ??
                        (opciones.isEmpty
                            ? l10n.turnoRouteEmpty
                            : l10n.turnoRouteNone),
                    style: theme.textTheme.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (opciones.isNotEmpty) const Icon(Icons.arrow_drop_down),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _pickRecorrido(AppLocalizations l10n) async {
    final opciones = _turno.recorridosDisponibles;
    final actual = _turno.recorridoAsignado;

    final elegido = await showModalBottomSheet<_RecorridoChoice>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Text(
                l10n.turnoRoutePick,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            ListTile(
              leading: const Icon(Icons.block),
              title: Text(l10n.turnoRouteNone),
              selected: actual == null,
              onTap: () => Navigator.pop(context, const _RecorridoChoice(null)),
            ),
            for (final r in opciones)
              ListTile(
                leading: CircleAvatar(
                  radius: 14,
                  backgroundColor: Color(r.colorValue),
                ),
                title: Text(r.nombre),
                selected: actual?.id == r.id,
                onTap: () => Navigator.pop(context, _RecorridoChoice(r)),
              ),
          ],
        ),
      ),
    );

    // `null` es cerrar la hoja sin elegir; "Sin recorrido" viene envuelto.
    if (elegido == null) return;
    await _turno.setRecorridoAsignado(elegido.recorrido);
  }

  String? _issueMessage(AppLocalizations l10n) => switch (_turno.issue) {
    TurnoIssue.none => null,
    TurnoIssue.trackingDisabled => l10n.turnoIssueTracking,
    TurnoIssue.cuentaInactiva => l10n.turnoIssueInactive,
    TurnoIssue.ubicacionNoDisponible => l10n.turnoIssueLocation,
  };
}

/// La tarjeta de abajo del chofer: flota sobre el mapa con poco margen, para
/// tapar lo menos posible. Un aviso (GPS, cuenta deshabilitada) va encima de
/// sus controles.
class _TarjetaInferior extends StatelessWidget {
  const _TarjetaInferior({required this.child, this.aviso});

  final Widget child;
  final String? aviso;

  @override
  Widget build(BuildContext context) {
    final aviso = this.aviso;
    return MapOverlayCard(
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (aviso != null) ...[
            InlineNotice(
              icon: Icons.warning_amber_outlined,
              message: aviso,
              tone: StatusTone.warning,
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
          child,
        ],
      ),
    );
  }
}

/// Una opción del semáforo de capacidad (informe §7.3.1-C): un solo toque,
/// como exige el informe, con el estado intermedio que hace útil el semáforo
/// para la garita.
///
/// La elegida va rellena con su color y en negrita; las demás, con un punto de
/// su color. El texto se achica si no cabe, en vez de partirse en dos líneas.
class _PildoraCapacidad extends StatelessWidget {
  const _PildoraCapacidad({
    required this.texto,
    required this.color,
    required this.elegida,
    required this.onTap,
  });

  final String texto;
  final Color color;
  final bool elegida;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final frente = elegida
        ? AppStatusColors.onColorFor(color)
        : scheme.onSurface;

    return Semantics(
      button: true,
      selected: elegida,
      child: Material(
        color: elegida ? color : scheme.surfaceContainerHighest,
        shape: const StadiumBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            height: TurnoScreen.altoControles,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (!elegida) ...[
                    Icon(Icons.circle, size: 10, color: color),
                    const SizedBox(width: AppSpacing.xs),
                  ],
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        texto,
                        maxLines: 1,
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: frente,
                          fontWeight: elegida ? FontWeight.w700 : null,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// "Volver a centrar": una píldora chica, flotando sobre el mapa como sus
/// demás controles.
class _BotonRecentrar extends StatelessWidget {
  const _BotonRecentrar({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ElevatedButton.icon(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        minimumSize: const Size(0, 40),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        visualDensity: VisualDensity.compact,
        textStyle: theme.textTheme.labelLarge,
        backgroundColor: theme.colorScheme.mapControl,
        foregroundColor: theme.colorScheme.onSurface,
        elevation: 4,
      ),
      icon: const Icon(Icons.navigation, size: 18),
      label: Text(label),
    );
  }
}

class _Girando extends StatelessWidget {
  const _Girando();

  @override
  Widget build(BuildContext context) => const SizedBox(
    width: 18,
    height: 18,
    child: CircularProgressIndicator(strokeWidth: 2),
  );
}

/// El mapa del chofer. Escucha por su cuenta lo que cambia a cada rato (el
/// GPS, una vez por segundo en turno, y la flota en vivo), para no reconstruir
/// los controles de encima con cada arreglo.
class _MapaTurno extends StatelessWidget {
  const _MapaTurno({
    required this.controller,
    required this.style,
    required this.follow,
    required this.insets,
    required this.zoomPara,
    required this.onUserGesture,
  });

  final AppMapController controller;
  final MapStyle style;
  final MapFollow follow;
  final EdgeInsets insets;

  /// El zoom de navegación para una velocidad en m/s.
  final double Function(double? metrosPorSegundo) zoomPara;
  final VoidCallback onUserGesture;

  static final _sinHora = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  Widget build(BuildContext context) {
    final location = LocationService.instance;
    final telemetria = FirebaseTelemetriaService.instance;

    return ListenableBuilder(
      listenable: Listenable.merge([location, telemetria.state]),
      builder: (context, _) {
        final auth = AuthService.instance;
        final turno = TurnoService.instance;
        final recorridos = RecorridosService.instance;
        final l10n = AppLocalizations.of(context)!;
        final status = AppStatusColors.of(context);
        final scheme = Theme.of(context).colorScheme;
        final position = location.position;
        final ahora = telemetria.serverNow();

        // El chofer es la flecha: su propio colectivo no se dibuja encima.
        final otros = colectivosVisibles(
          telemetria.state.value.colectivos,
          position ?? kQuilpueCenter,
        ).where((c) => c.uid != auth.uid);
        final elegida = recorridos.selected ?? turno.recorridoAsignado;

        return AppMap(
          controller: controller,
          initialCenter: position ?? kQuilpueCenter,
          initialZoom: position == null ? kInitialZoom : kStreetZoom,
          style: style,
          onUserGesture: onUserGesture,
          navigation: MapNavigation(
            fix: position == null
                ? null
                : MapUserFix(
                    point: position,
                    time: location.timestamp ?? _sinHora,
                    heading: location.heading,
                    speed: location.speed,
                    accuracy: location.accuracy,
                  ),
            follow: follow,
            zoom: turno.enTurno ? zoomPara(location.speed) : kStreetZoom,
            insets: insets,
          ),
          // Sólo su línea: las demás, o sus puntos de seña, son ruido para
          // quien maneja.
          lines: [
            if (elegida != null)
              ...recorridoLines(
                elegida,
                status,
                sentido: recorridos.selected != null
                    ? recorridos.selectedSentido
                    : null,
                badge: true,
                arrows: true,
              ),
          ],
          // Sin toque: manejando, una ficha que se abre es una distracción.
          // La etiqueta dice qué línea cubre cada uno.
          markers: [
            for (final c in otros)
              colectivoMarker(
                c,
                isMe: false,
                offline: c.seemsOffline(ahora),
                status: status,
                primary: scheme.primary,
                l10n: l10n,
                linea: lineaDeColectivo(c),
              ),
          ],
        );
      },
    );
  }
}

/// Lo que devuelve la hoja de recorridos. Envolverlo distingue "eligió Sin
/// recorrido" (`recorrido` nulo) de "cerró la hoja" (la hoja devuelve `null`).
class _RecorridoChoice {
  const _RecorridoChoice(this.recorrido);
  final Recorrido? recorrido;
}

/// Sin conexión, el aviso de que la posición se enviará al volver la señal.
/// Con conexión no se muestra nada: "En servicio" ya dice que se transmite.
class _AvisoSinSenal extends StatelessWidget {
  const _AvisoSinSenal();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return ValueListenableBuilder<bool>(
      valueListenable: TurnoService.instance.conectado,
      builder: (context, conectado, _) => conectado
          ? const SizedBox.shrink()
          : Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.sm,
                0,
                0,
                AppSpacing.sm,
              ),
              child: InlineNotice(
                icon: Icons.signal_cellular_connected_no_internet_0_bar,
                message: l10n.turnoOffline,
              ),
            ),
    );
  }
}
