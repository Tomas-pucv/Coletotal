import 'dart:async';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import 'package:taxi1/config/map_config.dart';
import 'package:taxi1/l10n/app_localizations.dart';
import 'package:taxi1/models/place_result.dart';
import 'package:taxi1/models/recorrido.dart';
import 'package:taxi1/navigation/app_destination.dart';
import 'package:taxi1/services/auth_service.dart';
import 'package:taxi1/services/firestore_writes.dart';
import 'package:taxi1/services/garita_service.dart';
import 'package:taxi1/services/geocoding_service.dart';
import 'package:taxi1/services/preferences_service.dart';
import 'package:taxi1/services/recorridos_service.dart';
import 'package:taxi1/services/routing.dart';
import 'package:taxi1/services/street_index.dart';
import 'package:taxi1/theme/app_colors.dart';
import 'package:taxi1/theme/app_spacing.dart';
import 'package:taxi1/theme/breakpoints.dart';
import 'package:taxi1/utils/distance_format.dart';
import 'package:taxi1/utils/polyline.dart';
import 'package:taxi1/utils/tile_coords.dart';
import 'package:taxi1/widgets/app_map.dart';
import 'package:taxi1/widgets/line_suggestions_sheet.dart' show sentidoLabel;
import 'package:taxi1/widgets/setting_tile.dart';
import 'package:taxi1/widgets/state_views.dart';

/// Las líneas de la garita, activas o no.
class RecorridosAdminScreen extends StatefulWidget {
  const RecorridosAdminScreen({super.key});

  @override
  State<RecorridosAdminScreen> createState() => _RecorridosAdminScreenState();
}

class _RecorridosAdminScreenState extends State<RecorridosAdminScreen> {
  final _garita = GaritaService.instance;
  final _recorridosService = RecorridosService.instance;
  final _auth = AuthService.instance;

  @override
  void initState() {
    super.initState();
    _recorridosService.addListener(_onChanged);
  }

  @override
  void dispose() {
    _recorridosService.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _edit(Recorrido? recorrido) async {
    final l10n = AppLocalizations.of(context)!;
    final resultado = await Navigator.of(context).push<_EditorResult>(
      MaterialPageRoute(
        builder: (_) => RecorridoEditorScreen(
          recorrido: recorrido,
          garitaId: _auth.garitaId ?? '',
        ),
      ),
    );
    if (resultado == null) return;
    _toast(
      resultado.outcome == WriteOutcome.queuedOffline
          ? l10n.savedOffline
          : (resultado.borrado ? l10n.routeDeleted : l10n.routeSaved),
    );
  }

  Future<void> _setActivo(Recorrido recorrido, bool activo) async {
    final l10n = AppLocalizations.of(context)!;
    try {
      final outcome = await _garita.setRecorridoActivo(recorrido, activo);
      if (outcome == WriteOutcome.queuedOffline) _toast(l10n.savedOffline);
    } catch (_) {
      _toast(l10n.errAuthUnknown);
    }
  }

  String _resumen(Recorrido r, AppLocalizations l10n) {
    String largo(Trayecto t) => formatDistance(polylineLength(t.trazado), l10n);
    final vuelta = r.vuelta;
    final infoVariante = [
      if (r.codigoVariante.isNotEmpty) '[${r.codigoVariante}]',
      if (r.nombreVariante.isNotEmpty) r.nombreVariante,
    ].join(' ');

    final cantCalles = r.callesIda.length + r.callesVuelta.length;
    final callesTxt = cantCalles > 0 ? ' · $cantCalles calles' : '';

    if (!r.ida.dibujable) {
      return infoVariante.isNotEmpty
          ? '$infoVariante$callesTxt · ${l10n.routeSummaryEmpty}'
          : l10n.routeSummaryEmpty;
    }
    if (vuelta == null || !vuelta.dibujable) {
      final idaTxt = l10n.routeSummaryIdaOnly(largo(r.ida));
      return infoVariante.isNotEmpty
          ? '$infoVariante$callesTxt · $idaTxt'
          : '$idaTxt$callesTxt';
    }
    final ambosTxt = l10n.routeSummaryBoth(largo(r.ida), largo(vuelta));
    return infoVariante.isNotEmpty
        ? '$infoVariante$callesTxt · $ambosTxt'
        : '$ambosTxt$callesTxt';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final recorridos = _recorridosService.porGarita(_auth.garitaId ?? '')
      ..sort((a, b) => a.nombre.compareTo(b.nombre));

    return Scaffold(
      appBar: AppBar(title: Text(AppDestination.recorridos.label(l10n))),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(null),
        icon: const Icon(Icons.add_road_outlined),
        label: Text(l10n.routeAdd),
      ),
      body: !_auth.isAdmin
          ? StatusMessageView(
              icon: Icons.lock_outline,
              title: AppDestination.recorridos.label(l10n),
              message: l10n.adminOnly,
            )
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: Breakpoints.maxContentWidth,
                ),
                child: recorridos.isEmpty
                    ? StatusMessageView(
                        icon: Icons.timeline_outlined,
                        title: l10n.routesEmpty,
                        message: l10n.routeTraceHint,
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.lg,
                          AppSpacing.lg,
                          AppSpacing.lg,
                          96,
                        ),
                        itemCount: recorridos.length,
                        separatorBuilder: (_, _) =>
                            const SizedBox(height: AppSpacing.sm),
                        itemBuilder: (context, index) {
                          final recorrido = recorridos[index];
                          return Card(
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: Color(recorrido.colorValue),
                                child: const Icon(
                                  Icons.timeline,
                                  color: Colors.white,
                                  size: 20,
                                ),
                              ),
                              title: Text(recorrido.nombre),
                              subtitle: Text(
                                recorrido.activo
                                    ? _resumen(recorrido, l10n)
                                    : '${l10n.routeInactive} · '
                                          '${_resumen(recorrido, l10n)}',
                              ),
                              // Encenderla o apagarla es lo más frecuente: no
                              // obliga a entrar al editor.
                              trailing: Switch(
                                value: recorrido.activo,
                                onChanged: (v) => _setActivo(recorrido, v),
                              ),
                              onTap: () => _edit(recorrido),
                            ),
                          );
                        },
                      ),
              ),
            ),
    );
  }
}

/// Qué pasó en el editor, para el aviso de la lista.
class _EditorResult {
  const _EditorResult(this.outcome, {this.borrado = false});

  final WriteOutcome outcome;
  final bool borrado;
}

/// Editor de una línea: su nombre, su color y el recorrido de ida y de vuelta.
///
/// El recorrido se marca en el mapa punto por punto (mantener presionado) y la
/// app lo ajusta a las calles con el mismo enrutador del teléfono que usa el
/// pasajero, en auto: respeta los sentidos de tránsito y no se mete por
/// pasajes ni huellas. Basta con marcar los puntos donde la línea dobla; lo de
/// entremedio lo resuelve el enrutador.
class RecorridoEditorScreen extends StatefulWidget {
  const RecorridoEditorScreen({
    super.key,
    required this.recorrido,
    required this.garitaId,
  });

  final Recorrido? recorrido;
  final String garitaId;

  /// La vuelta, para empezar a dibujarla: los mismos puntos de la ida, al
  /// revés. Después se corrigen donde la vuelta va por otras calles.
  static List<LatLng> vueltaDesdeIda(List<LatLng> ida) =>
      ida.reversed.toList(growable: true);

  /// Tope de puntos por sentido; el mismo que aceptan las reglas.
  static const int maxPuntos = 200;

  @override
  State<RecorridoEditorScreen> createState() => _RecorridoEditorScreenState();
}

class _RecorridoEditorScreenState extends State<RecorridoEditorScreen> {
  final _formKey = GlobalKey<FormState>();
  final _mapController = AppMapController();
  late final TextEditingController _nombre;
  late final TextEditingController _linea;
  late final TextEditingController _codigoVariante;
  late final TextEditingController _nombreVariante;
  final TextEditingController _calleInputController = TextEditingController();
  bool _nombreAutogenerado = false;

  late int _color;
  late bool _activo;
  Sentido _sentido = Sentido.ida;

  /// Por sentido: las calles oficiales de la cartola (D.S. 212).
  final Map<Sentido, List<String>> _calles = {};

  /// Por sentido: los puntos marcados y el trazado por calle calculado con
  /// ellos. [_ajustado] dice si el trazado corresponde a los puntos actuales.
  final Map<Sentido, List<LatLng>> _puntos = {};
  final Map<Sentido, List<LatLng>> _trazados = {};
  final Map<Sentido, bool> _ajustado = {};
  final Map<Sentido, bool> _fallo = {};

  Timer? _espera;
  final Map<Sentido, int> _pedidos = {};
  bool _ajustando = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final r = widget.recorrido;
    _linea = TextEditingController(text: r?.linea ?? '');
    _codigoVariante = TextEditingController(text: r?.codigoVariante ?? '');
    _nombreVariante = TextEditingController(text: r?.nombreVariante ?? '');
    _nombre = TextEditingController(text: r?.nombre ?? '');

    if (_nombre.text.isEmpty) {
      final sugerido = _nombreSugerido();
      if (sugerido.isNotEmpty) {
        _nombre.text = sugerido;
        _nombreAutogenerado = true;
      }
    }

    _linea.addListener(_onCartolaCamposCambiaron);
    _codigoVariante.addListener(_onCartolaCamposCambiaron);
    _nombreVariante.addListener(_onCartolaCamposCambiaron);

    _color = r?.colorValue ?? kRecorridoColors.first;
    _activo = r?.activo ?? true;
    for (final sentido in Sentido.values) {
      final t = r?.trayecto(sentido);
      _puntos[sentido] = List.of(t?.puntos ?? const <LatLng>[]);
      _trazados[sentido] = t?.trazado ?? const [];
      _ajustado[sentido] = true;
      _fallo[sentido] = false;
      _calles[sentido] = List.of(r?.calles(sentido) ?? const <String>[]);
    }
  }

  @override
  void dispose() {
    _espera?.cancel();
    _linea.removeListener(_onCartolaCamposCambiaron);
    _codigoVariante.removeListener(_onCartolaCamposCambiaron);
    _nombreVariante.removeListener(_onCartolaCamposCambiaron);
    _linea.dispose();
    _codigoVariante.dispose();
    _nombreVariante.dispose();
    _calleInputController.dispose();
    _nombre.dispose();
    super.dispose();
  }

  String _nombreSugerido() {
    final lin = _linea.text.trim();
    final cod = _codigoVariante.text.trim();
    final varNom = _nombreVariante.text.trim();
    final partes = <String>[];
    if (lin.isNotEmpty) partes.add(lin);
    if (cod.isNotEmpty) partes.add('[$cod]');
    if (varNom.isNotEmpty) partes.add(varNom);
    return partes.join(' ');
  }

  void _onCartolaCamposCambiaron() {
    final sugerido = _nombreSugerido();
    if (sugerido.isNotEmpty && (_nombre.text.isEmpty || _nombreAutogenerado)) {
      _nombreAutogenerado = true;
      _nombre.text = sugerido;
    }
  }

  List<LatLng> get _actuales => _puntos[_sentido]!;

  void _onMapReady() {
    // Una línea que ya existe se muestra entera; una nueva, desde Quilpué.
    final todo = [..._trazados[Sentido.ida]!, ..._trazados[Sentido.vuelta]!];
    if (todo.length < 2) return;
    final size = MediaQuery.sizeOf(context);
    final vista = encuadre(todo, ancho: size.width, alto: size.height * 0.45);
    unawaited(_mapController.moveTo(vista.centro, zoom: vista.zoom));
  }

  void _cambiarPuntos(void Function(List<LatLng> puntos) cambio) {
    setState(() {
      cambio(_actuales);
      _ajustado[_sentido] = false;
      _fallo[_sentido] = false;
      if (_actuales.length < 2) _trazados[_sentido] = const [];
    });
    _programarAjuste();
  }

  void _agregar(LatLng punto) {
    if (_actuales.length >= RecorridoEditorScreen.maxPuntos) return;
    _cambiarPuntos((p) => p.add(punto));
  }

  void _quitar(int indice) {
    final l10n = AppLocalizations.of(context)!;
    final sentido = _sentido;
    final punto = _actuales[indice];
    _cambiarPuntos((p) => p.removeAt(indice));
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(l10n.routePointRemoved),
          action: SnackBarAction(
            label: l10n.undo,
            onPressed: () {
              if (!mounted || _sentido != sentido) return;
              _cambiarPuntos((p) => p.insert(indice.clamp(0, p.length), punto));
            },
          ),
        ),
      );
  }

  void _vueltaDesdeIda() {
    setState(() {
      _sentido = Sentido.vuelta;
      _calles[Sentido.vuelta] = List.of(_calles[Sentido.ida]!.reversed);
    });
    _cambiarPuntos((p) {
      p
        ..clear()
        ..addAll(RecorridoEditorScreen.vueltaDesdeIda(_puntos[Sentido.ida]!));
    });
  }

  Future<LatLng?> _geocodificarCalle(String nombreCalle, {LatLng? cercaDe}) async {
    final query = nombreCalle.trim();
    if (query.isEmpty) return null;

    final pois = GeocodingService.searchLocal(query);
    if (pois.isNotEmpty) {
      return pois.first.location;
    }

    final centro = cercaDe ?? (_actuales.isNotEmpty ? _actuales.last : kQuilpueCenter);
    final resultados = await StreetIndex.search(query, near: centro, limit: 5);
    if (resultados.isNotEmpty) {
      return resultados.first.location;
    }

    final limpia = query
        .replaceAll(
          RegExp(
            r'^(AV\.|AVDA\.|AVENIDA|CALLE|PJE\.|PASAJE|CAMINO)\s+',
            caseSensitive: false,
          ),
          '',
        )
        .trim();
    if (limpia.isNotEmpty && limpia != query) {
      final resLimpia = await StreetIndex.search(limpia, near: centro, limit: 3);
      if (resLimpia.isNotEmpty) {
        return resLimpia.first.location;
      }
    }

    return null;
  }

  Future<void> _agregarCalle(String nombre, {LatLng? coordenada}) async {
    final calleLimpia = nombre.trim();
    if (calleLimpia.isEmpty) return;

    final sentido = _sentido;
    setState(() {
      _calles[sentido]!.add(calleLimpia);
    });

    LatLng? punto = coordenada;
    punto ??= await _geocodificarCalle(
      calleLimpia,
      cercaDe: _actuales.isNotEmpty ? _actuales.last : kQuilpueCenter,
    );

    if (punto != null) {
      _agregar(punto);
      unawaited(_mapController.moveTo(punto, zoom: 15));
    } else {
      if (mounted) {
        _toast(
          'Calle "$calleLimpia" agregada a la lista. Mantén presionado el mapa si deseas marcar su coordenada.',
        );
      }
    }
  }

  void _quitarCalle(int indice) {
    final sentido = _sentido;
    if (indice < 0 || indice >= _calles[sentido]!.length) return;
    setState(() {
      _calles[sentido]!.removeAt(indice);
      if (indice < _puntos[sentido]!.length) {
        _puntos[sentido]!.removeAt(indice);
        _ajustado[sentido] = false;
        _fallo[sentido] = false;
        if (_puntos[sentido]!.length < 2) {
          _trazados[sentido] = const [];
        }
      }
    });
    _programarAjuste();
  }

  Future<void> _procesarTextoCartola(String texto) async {
    final separadas = texto
        .split(RegExp(r'[;\n\r]+'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (separadas.isEmpty) return;

    final sentido = _sentido;
    final nuevosPuntos = <LatLng>[];

    for (final calle in separadas) {
      _calles[sentido]!.add(calle);
      final ref = nuevosPuntos.isNotEmpty
          ? nuevosPuntos.last
          : (_puntos[sentido]!.isNotEmpty ? _puntos[sentido]!.last : kQuilpueCenter);
      final coord = await _geocodificarCalle(calle, cercaDe: ref);
      if (coord != null) {
        nuevosPuntos.add(coord);
      }
    }

    if (nuevosPuntos.isNotEmpty) {
      _cambiarPuntos((p) => p.addAll(nuevosPuntos));
      final todo = _puntos[sentido]!;
      if (todo.length >= 2 && mounted) {
        final size = MediaQuery.sizeOf(context);
        final vista = encuadre(todo, ancho: size.width, alto: size.height * 0.45);
        unawaited(_mapController.moveTo(vista.centro, zoom: vista.zoom));
      } else {
        unawaited(_mapController.moveTo(nuevosPuntos.last, zoom: 15));
      }
    } else {
      setState(() {});
    }

    if (mounted) {
      _toast('${separadas.length} calles agregadas (${nuevosPuntos.length} trazadas en el mapa)');
    }
  }

  Future<void> _mostrarDialogoPegarCartola() async {
    final textCtrl = TextEditingController();
    final sentido = _sentido;
    final l10n = AppLocalizations.of(context)!;
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.content_paste_go),
        title: Text('Pegar Trazado Cartola (${sentidoLabel(sentido, l10n)})'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Pega la lista de calles de la cartola oficial MTT (separadas por ";" o saltos de línea):',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: textCtrl,
              maxLines: 6,
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                hintText: 'SERRANO; COVADONGA; SAN MARTIN; BAQUEDANO; ...',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          FilledButton.icon(
            icon: const Icon(Icons.map_outlined),
            onPressed: () => Navigator.pop(context, true),
            label: const Text('Procesar y Trazar'),
          ),
        ],
      ),
    );

    if (confirmado == true && textCtrl.text.trim().isNotEmpty) {
      await _procesarTextoCartola(textCtrl.text.trim());
    }
  }

  /// Ajusta a las calles un rato después del último cambio: marcar varios
  /// puntos seguidos no dispara una consulta por cada uno.
  void _programarAjuste() {
    _espera?.cancel();
    final sentido = _sentido;
    if (_puntos[sentido]!.length < 2) return;
    _espera = Timer(
      const Duration(milliseconds: 400),
      () => unawaited(_ajustar(sentido)),
    );
  }

  Future<void> _ajustar(Sentido sentido) async {
    final puntos = List<LatLng>.of(_puntos[sentido]!);
    if (puntos.length < 2) return;
    final pedido = (_pedidos[sentido] ?? 0) + 1;
    _pedidos[sentido] = pedido;
    setState(() => _ajustando = true);

    final ruta = await Routing.linePath(puntos);

    // Mientras tanto se movieron los puntos: esta respuesta ya no sirve.
    if (!mounted || _pedidos[sentido] != pedido) return;
    setState(() {
      _ajustando = false;
      if (ruta == null || ruta.points.length < 2) {
        _fallo[sentido] = true;
        _trazados[sentido] = const [];
      } else {
        _fallo[sentido] = false;
        _trazados[sentido] = ruta.points;
        _ajustado[sentido] = true;
      }
    });
  }

  Future<void> _verPuntos() async {
    final l10n = AppLocalizations.of(context)!;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheet) {
          final puntos = _actuales;
          return SafeArea(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.6,
              ),
              child: ReorderableListView.builder(
                shrinkWrap: true,
                header: Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Text(
                    '${sentidoLabel(_sentido, l10n)} · '
                    '${l10n.routePointsButton('${puntos.length}')}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                itemCount: puntos.length,
                onReorderItem: (desde, hasta) {
                  _cambiarPuntos((p) => p.insert(hasta, p.removeAt(desde)));
                  setSheet(() {});
                },
                itemBuilder: (context, i) => ListTile(
                  key: ValueKey(
                    '${puntos[i].latitude},${puntos[i].longitude},$i',
                  ),
                  leading: CircleAvatar(
                    radius: 14,
                    backgroundColor: Color(_color),
                    child: Text(
                      '${i + 1}',
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                  title: Text(l10n.routePointLabel('${i + 1}')),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.close),
                        tooltip: l10n.delete,
                        onPressed: () {
                          _cambiarPuntos((p) => p.removeAt(i));
                          setSheet(() {});
                        },
                      ),
                      ReorderableDragStartListener(
                        index: i,
                        child: const Icon(Icons.drag_handle),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// El trayecto de [sentido] listo para guardar, `null` si no tiene puntos,
  /// o una excepción con el mensaje para el usuario si no se pudo ajustar.
  Future<Trayecto?> _trayectoParaGuardar(Sentido sentido) async {
    final puntos = _puntos[sentido]!;
    if (puntos.length < 2) return null;
    if (_ajustado[sentido] != true) {
      _espera?.cancel();
      await _ajustar(sentido);
    }
    final trazado = _trazados[sentido]!;
    if (_ajustado[sentido] != true || trazado.length < 2) {
      throw const _NoSeAjusto();
    }
    return Trayecto(
      puntos: List.unmodifiable(puntos),
      geometria: encodePolyline(trazado),
      trazado: trazado,
    );
  }

  void _toast(String message) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));

  Future<void> _save() async {
    if (_saving) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final l10n = AppLocalizations.of(context)!;
    if (_puntos[Sentido.ida]!.length < 2) {
      setState(() => _sentido = Sentido.ida);
      _toast(l10n.routeNeedsIda);
      return;
    }

    setState(() => _saving = true);
    try {
      final ida = await _trayectoParaGuardar(Sentido.ida);
      final vuelta = await _trayectoParaGuardar(Sentido.vuelta);
      final linea = _linea.text.trim();
      final codigoVariante = _codigoVariante.text.trim();
      final nombreVariante = _nombreVariante.text.trim();
      final callesIda = List<String>.unmodifiable(_calles[Sentido.ida]!);
      final callesVuelta = List<String>.unmodifiable(_calles[Sentido.vuelta]!);

      String nombreFinal = _nombre.text.trim();
      if (nombreFinal.isEmpty) {
        nombreFinal = _nombreSugerido();
      }
      if (nombreFinal.isEmpty) {
        nombreFinal = 'Recorrido sin nombre';
      }

      final (_, outcome) = await GaritaService.instance.upsertRecorrido(
        Recorrido(
          id: widget.recorrido?.id ?? '',
          garitaId: widget.garitaId,
          nombre: nombreFinal,
          colorValue: _color,
          activo: _activo,
          ida: ida!,
          vuelta: vuelta,
          linea: linea,
          codigoVariante: codigoVariante,
          nombreVariante: nombreVariante,
          callesIda: callesIda,
          callesVuelta: callesVuelta,
        ),
      );
      if (mounted) Navigator.of(context).pop(_EditorResult(outcome));
    } on _NoSeAjusto {
      if (!mounted) return;
      setState(() => _saving = false);
      _toast(l10n.routeSnapFailed);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      _toast(l10n.errAuthUnknown);
    }
  }

  Future<void> _delete() async {
    final l10n = AppLocalizations.of(context)!;
    final recorrido = widget.recorrido;
    if (recorrido == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.delete_outline),
        title: Text(l10n.routeDeleteTitle),
        content: Text(l10n.routeDeleteMessage(recorrido.nombre)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
    if (!(confirmed ?? false) || !mounted) return;
    try {
      final outcome = await GaritaService.instance.deleteRecorrido(recorrido);
      if (mounted) {
        Navigator.of(context).pop(_EditorResult(outcome, borrado: true));
      }
    } catch (_) {
      if (mounted) _toast(l10n.errAuthUnknown);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final status = AppStatusColors.of(context);
    final color = Color(_color);
    final otro = _sentido == Sentido.ida ? Sentido.vuelta : Sentido.ida;
    final trazado = _trazados[_sentido]!;
    final puntos = _actuales;

    final resumen = _ajustando
        ? l10n.routeSnapping
        : l10n.routeTrayectoSummary(
            '${puntos.length}',
            formatDistance(polylineLength(trazado), l10n),
          );

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.recorrido == null ? l10n.routeAdd : l10n.routeEdit),
        actions: [
          if (widget.recorrido != null)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: l10n.delete,
              onPressed: _saving ? null : _delete,
            ),
          IconButton(
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check),
            tooltip: l10n.save,
            onPressed: _saving ? null : _save,
          ),
        ],
      ),
      body: Column(
        children: [
          // Los datos van arriba, en una franja con su propio scroll: con el
          // teclado abierto o la letra grande, el mapa se achica pero no
          // desborda.
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.46,
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.md,
                AppSpacing.lg,
                AppSpacing.sm,
              ),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 2,
                          child: TextFormField(
                            controller: _linea,
                            textCapitalization: TextCapitalization.words,
                            decoration: const InputDecoration(
                              labelText: 'Línea',
                              hintText: 'Ej: Línea 10',
                              prefixIcon: Icon(Icons.directions_bus_outlined),
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          flex: 1,
                          child: TextFormField(
                            controller: _codigoVariante,
                            textCapitalization: TextCapitalization.characters,
                            decoration: const InputDecoration(
                              labelText: 'Variante',
                              hintText: 'Ej: T, V-1',
                              prefixIcon: Icon(Icons.tag),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    TextFormField(
                      controller: _nombreVariante,
                      textCapitalization: TextCapitalization.words,
                      maxLength: 80,
                      decoration: const InputDecoration(
                        labelText: 'Nombre de la Variante / Trazado',
                        hintText: 'Ej: Belloto 2000 - Las Rosas, Troncos Viejos...',
                        prefixIcon: Icon(Icons.alt_route),
                      ),
                    ),
                    TextFormField(
                      controller: _nombre,
                      textCapitalization: TextCapitalization.sentences,
                      maxLength: 80,
                      decoration: InputDecoration(
                        labelText: l10n.routeName,
                        hintText: 'Ej: Línea 10 [T] Belloto 2000',
                        prefixIcon: const Icon(Icons.timeline_outlined),
                      ),
                      validator: (v) {
                        if ((v ?? '').trim().isEmpty &&
                            _linea.text.trim().isEmpty &&
                            _nombreVariante.text.trim().isEmpty) {
                          return l10n.authRequired;
                        }
                        return null;
                      },
                    ),
                    _ColorPicker(
                      value: _color,
                      onChanged: (c) => setState(() => _color = c),
                    ),
                    SettingSwitchTile(
                      title: l10n.routeActive,
                      subtitle: l10n.routeActiveDesc,
                      value: _activo,
                      onChanged: (v) => setState(() => _activo = v),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    SegmentedButton<Sentido>(
                      segments: [
                        for (final s in Sentido.values)
                          ButtonSegment(
                            value: s,
                            label: Text(
                              '${sentidoLabel(s, l10n)} (${_calles[s]?.length ?? 0})',
                            ),
                            icon: Icon(
                              s == Sentido.ida
                                  ? Icons.arrow_forward
                                  : Icons.arrow_back,
                            ),
                          ),
                      ],
                      selected: {_sentido},
                      onSelectionChanged: (sel) =>
                          setState(() => _sentido = sel.first),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    // Tarjeta de Calles de la Cartola Oficial MTT
                    Card(
                      margin: EdgeInsets.zero,
                      color: theme.colorScheme.surfaceContainerLow,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(
                          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.sm),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.route_outlined,
                                  size: 18,
                                  color: theme.colorScheme.primary,
                                ),
                                const SizedBox(width: AppSpacing.xs),
                                Text(
                                  'Calles ${sentidoLabel(_sentido, l10n)} (${_calles[_sentido]?.length ?? 0})',
                                  style: theme.textTheme.labelLarge?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const Spacer(),
                                IconButton.filledTonal(
                                  icon: const Icon(Icons.paste, size: 16),
                                  visualDensity: VisualDensity.compact,
                                  tooltip: 'Pegar Cartola Completa',
                                  onPressed: _mostrarDialogoPegarCartola,
                                ),
                              ],
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            Autocomplete<PlaceResult>(
                              displayStringForOption: (opt) => opt.name,
                              optionsBuilder: (textVal) async {
                                final q = textVal.text.trim();
                                if (q.length < 2) {
                                  return const Iterable<PlaceResult>.empty();
                                }
                                final pois = GeocodingService.searchLocal(q);
                                final calles = await StreetIndex.search(
                                  q,
                                  near: _actuales.isNotEmpty
                                      ? _actuales.last
                                      : kQuilpueCenter,
                                  limit: 6,
                                );
                                return [...pois, ...calles];
                              },
                              onSelected: (opt) {
                                _agregarCalle(opt.name, coordenada: opt.location);
                                _calleInputController.clear();
                              },
                              fieldViewBuilder: (ctx, controller, focusNode, onDone) {
                                return TextField(
                                  controller: controller,
                                  focusNode: focusNode,
                                  textCapitalization: TextCapitalization.characters,
                                  decoration: InputDecoration(
                                    hintText: 'Agregar calle o pegar trazado (;)',
                                    isDense: true,
                                    prefixIcon: const Icon(Icons.add_road, size: 18),
                                    suffixIcon: IconButton(
                                      icon: const Icon(Icons.add_circle, size: 20),
                                      onPressed: () {
                                        final txt = controller.text.trim();
                                        if (txt.contains(';')) {
                                          _procesarTextoCartola(txt);
                                          controller.clear();
                                        } else if (txt.isNotEmpty) {
                                          _agregarCalle(txt);
                                          controller.clear();
                                        }
                                      },
                                    ),
                                  ),
                                  onSubmitted: (txt) {
                                    if (txt.contains(';')) {
                                      _procesarTextoCartola(txt);
                                      controller.clear();
                                    } else if (txt.trim().isNotEmpty) {
                                      _agregarCalle(txt.trim());
                                      controller.clear();
                                    }
                                  },
                                );
                              },
                            ),
                            if ((_calles[_sentido] ?? const []).isNotEmpty) ...[
                              const SizedBox(height: AppSpacing.xs),
                              ConstrainedBox(
                                constraints: const BoxConstraints(maxHeight: 110),
                                child: SingleChildScrollView(
                                  child: Wrap(
                                    spacing: 4,
                                    runSpacing: 4,
                                    children: [
                                      for (var i = 0; i < _calles[_sentido]!.length; i++)
                                        Chip(
                                          visualDensity: VisualDensity.compact,
                                          avatar: CircleAvatar(
                                            radius: 10,
                                            backgroundColor: color,
                                            child: Text(
                                              '${i + 1}',
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 10,
                                              ),
                                            ),
                                          ),
                                          label: Text(
                                            _calles[_sentido]![i],
                                            style: const TextStyle(fontSize: 11),
                                          ),
                                          onDeleted: () => _quitarCalle(i),
                                          deleteIconColor: theme.colorScheme.error,
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Wrap(
                      spacing: AppSpacing.xs,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.undo),
                          tooltip: l10n.routeUndoPoint,
                          onPressed: puntos.isEmpty
                              ? null
                              : () => _cambiarPuntos((p) => p.removeLast()),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_sweep_outlined),
                          tooltip: l10n.routeClearPoints,
                          onPressed: puntos.isEmpty
                              ? null
                              : () {
                                  setState(() {
                                    _calles[_sentido]!.clear();
                                  });
                                  _cambiarPuntos((p) => p.clear());
                                },
                        ),
                        TextButton.icon(
                          icon: const Icon(Icons.format_list_numbered),
                          label: Text(
                            l10n.routePointsButton('${puntos.length}'),
                          ),
                          onPressed: puntos.isEmpty ? null : _verPuntos,
                        ),
                        if (_sentido == Sentido.vuelta &&
                            puntos.isEmpty &&
                            _puntos[Sentido.ida]!.length >= 2)
                          FilledButton.tonalIcon(
                            icon: const Icon(Icons.swap_horiz),
                            label: Text(l10n.routeVueltaFromIda),
                            onPressed: _vueltaDesdeIda,
                          ),
                      ],
                    ),
                    Text(
                      puntos.isEmpty ? l10n.routeAddPointHint : resumen,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (_fallo[_sentido] == true) ...[
                      const SizedBox(height: AppSpacing.sm),
                      InlineNotice(
                        icon: Icons.wrong_location_outlined,
                        message: l10n.routeSnapFailed,
                        tone: StatusTone.error,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: AppMap(
              controller: _mapController,
              initialCenter: kQuilpueCenter,
              style: MapStyle.fromPref(PreferencesService.instance.mapType),
              attributionAlignment: Alignment.topRight,
              onMapReady: _onMapReady,
              onLongPress: _agregar,
              lines: [
                // El otro sentido, tenue, como referencia.
                if (_trazados[otro]!.length >= 2)
                  MapLine(
                    points: _trazados[otro]!,
                    color: color.withValues(alpha: 0.35),
                    width: 4,
                  ),
                // El que se edita: el trazado por calle o, mientras se
                // calcula (o si falló), los puntos unidos con rectas.
                if (trazado.length >= 2)
                  MapLine(
                    points: trazado,
                    color: color.withValues(alpha: 0.9),
                    width: 6,
                    borderColor: status.routeLineCasing,
                    borderWidth: 1.5,
                  )
                else if (puntos.length >= 2)
                  MapLine(
                    points: puntos,
                    color: color.withValues(alpha: 0.6),
                    width: 3,
                    dotted: true,
                  ),
              ],
              markers: [
                for (var i = 0; i < puntos.length; i++)
                  MapMarker(
                    id: 'punto_$i',
                    point: puntos[i],
                    icon: MarkerIcon.circle(
                      diameter: i == 0 || i == puntos.length - 1 ? 26 : 16,
                      color: color,
                      borderColor: status.markerBorder,
                      borderWidth: 2,
                      glyph: i == 0
                          ? Icons.play_arrow
                          : (i == puntos.length - 1 ? Icons.flag : null),
                      glyphColor: Colors.white,
                      glyphSize: 16,
                      tapTarget: AppSpacing.minTapTarget,
                    ),
                    semanticLabel: l10n.routePointLabel('${i + 1}'),
                    onTap: () => _quitar(i),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// El trazado de un sentido no se pudo ajustar a las calles.
class _NoSeAjusto implements Exception {
  const _NoSeAjusto();
}

class _ColorPicker extends StatelessWidget {
  const _ColorPicker({required this.value, required this.onChanged});

  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.xs,
      children: [
        for (final color in kRecorridoColors)
          Semantics(
            button: true,
            selected: color == value,
            child: InkWell(
              onTap: () => onChanged(color),
              customBorder: const CircleBorder(),
              child: Container(
                width: AppSpacing.minTapTarget,
                height: AppSpacing.minTapTarget,
                decoration: BoxDecoration(
                  color: Color(color),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: color == value
                        ? scheme.onSurface
                        : Colors.transparent,
                    width: 3,
                  ),
                ),
                child: color == value
                    ? const Icon(Icons.check, color: Colors.white, size: 20)
                    : null,
              ),
            ),
          ),
      ],
    );
  }
}
