import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';

import 'package:taxi1/l10n/app_localizations.dart';
import 'package:taxi1/models/bus_stop.dart';
import 'package:taxi1/models/recorrido.dart';
import 'package:taxi1/navigation/app_destination.dart';
import 'package:taxi1/services/auth_service.dart';
import 'package:taxi1/services/firestore_writes.dart';
import 'package:taxi1/services/garita_service.dart';
import 'package:taxi1/services/recorridos_service.dart';
import 'package:taxi1/services/stops_service.dart';
import 'package:taxi1/theme/app_spacing.dart';
import 'package:taxi1/theme/breakpoints.dart';
import 'package:taxi1/widgets/setting_tile.dart';
import 'package:taxi1/widgets/state_views.dart';

/// Lista de recorridos de la garita.
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
    final outcome = await Navigator.of(context).push<WriteOutcome>(
      MaterialPageRoute(
        builder: (_) => RecorridoEditorScreen(
          recorrido: recorrido,
          garitaId: _auth.garitaId ?? '',
        ),
      ),
    );
    if (outcome == null) return;
    _toast(
      outcome == WriteOutcome.queuedOffline
          ? l10n.savedOffline
          : l10n.routeSaved,
    );
  }

  Future<void> _confirmDelete(Recorrido recorrido) async {
    final l10n = AppLocalizations.of(context)!;
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
    if (!(confirmed ?? false)) return;
    try {
      final outcome = await _garita.deleteRecorrido(recorrido);
      _toast(
        outcome == WriteOutcome.queuedOffline
            ? l10n.savedOffline
            : l10n.routeDeleted,
      );
    } catch (_) {
      _toast(l10n.errAuthUnknown);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final recorridos = _recorridosService.porGarita(_auth.garitaId ?? '');

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
                                l10n.routeStopCount(
                                  '${recorrido.paraderoIds.length}',
                                ),
                              ),
                              trailing: IconButton(
                                icon: const Icon(Icons.delete_outline),
                                tooltip: l10n.delete,
                                onPressed: () => _confirmDelete(recorrido),
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

/// Editor de un recorrido.
///
/// Un recorrido es nombre + color + **lista ordenada de paraderos**. El trazado
/// no se dibuja punto a punto: se deriva de esa lista conectando los paraderos
/// por calle con el mismo enrutador que ya usa el pasajero. Así el trazado no
/// puede quedar desincronizado de los paraderos, y editar el recorrido es
/// arrastrar filas en vez de dibujar decenas de vértices a dedo.
class RecorridoEditorScreen extends StatefulWidget {
  const RecorridoEditorScreen({
    super.key,
    required this.recorrido,
    required this.garitaId,
  });

  final Recorrido? recorrido;
  final String garitaId;

  @override
  State<RecorridoEditorScreen> createState() => _RecorridoEditorScreenState();
}

class _RecorridoEditorScreenState extends State<RecorridoEditorScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nombre;

  late List<String> _paraderoIds;
  late int _color;
  late bool _activo;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final r = widget.recorrido;
    _nombre = TextEditingController(text: r?.nombre ?? '');
    _paraderoIds = List.of(r?.paraderoIds ?? const []);
    _color = r?.colorValue ?? kRecorridoColors.first;
    _activo = r?.activo ?? true;
  }

  @override
  void dispose() {
    _nombre.dispose();
    super.dispose();
  }

  Future<void> _addStop() async {
    final l10n = AppLocalizations.of(context)!;
    final disponibles = StopsService.instance.stops
        .where((s) => !_paraderoIds.contains(s.id))
        .toList(growable: false);

    if (disponibles.isEmpty) return;

    final selected = await showModalBottomSheet<BusStop>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Text(
                l10n.routeAddStop,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            for (final stop in disponibles)
              ListTile(
                leading: const Icon(Icons.pin_drop_outlined),
                title: Text(stop.name),
                subtitle: Text(
                  stop.address,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () => Navigator.pop(context, stop),
              ),
          ],
        ),
      ),
    );

    if (selected != null) {
      setState(() => _paraderoIds = [..._paraderoIds, selected.id]);
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final l10n = AppLocalizations.of(context)!;
    if (_paraderoIds.length < 2) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(l10n.routeNeedsStops)));
      return;
    }

    setState(() => _saving = true);
    final original = widget.recorrido;
    // Si los paraderos no cambiaron, el trazado guardado sigue siendo válido
    // y se conserva tal cual. Antes se guardaba siempre sin geometría: cambiar
    // el nombre o el color de una línea reemplazaba su trazado afinado por uno
    // recalculado, o lo borraba si OSRM no respondía.
    final mismaGeometria =
        original != null && listEquals(original.paraderoIds, _paraderoIds);
    try {
      final (_, outcome) = await GaritaService.instance.upsertRecorrido(
        Recorrido(
          id: original?.id ?? '',
          garitaId: widget.garitaId,
          nombre: _nombre.text.trim(),
          colorValue: _color,
          paraderoIds: _paraderoIds,
          geometria: mismaGeometria ? original.geometria : null,
          activo: _activo,
        ),
      );
      if (mounted) Navigator.of(context).pop(outcome);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(l10n.errAuthUnknown)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final stops = StopsService.instance;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.recorrido == null ? l10n.routeAdd : l10n.routeEdit,
        ),
        actions: [
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addStop,
        icon: const Icon(Icons.add_location_alt_outlined),
        label: Text(l10n.routeAddStop),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: Breakpoints.maxContentWidth,
          ),
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextFormField(
                        controller: _nombre,
                        textCapitalization: TextCapitalization.words,
                        maxLength: 80,
                        decoration: InputDecoration(
                          labelText: l10n.routeName,
                          prefixIcon: const Icon(Icons.timeline_outlined),
                        ),
                        validator: (v) =>
                            (v ?? '').trim().isEmpty ? l10n.authRequired : null,
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      Text(l10n.routeColor, style: theme.textTheme.bodyLarge),
                      const SizedBox(height: AppSpacing.sm),
                      _ColorPicker(
                        value: _color,
                        onChanged: (c) => setState(() => _color = c),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      SettingSwitchTile(
                        title: l10n.routeActive,
                        value: _activo,
                        onChanged: (v) => setState(() => _activo = v),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        l10n.routeStops,
                        style: theme.textTheme.titleSmall,
                      ),
                      Text(
                        l10n.routeStopsHelp,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: _paraderoIds.isEmpty
                      ? StatusMessageView(
                          icon: Icons.add_location_alt_outlined,
                          title: l10n.routeNeedsStops,
                          message: l10n.routeTraceHint,
                        )
                      : ReorderableListView.builder(
                          padding: const EdgeInsets.fromLTRB(
                            AppSpacing.lg,
                            0,
                            AppSpacing.lg,
                            96,
                          ),
                          itemCount: _paraderoIds.length,
                          // `onReorderItem` y no `onReorder`: el índice ya
                          // viene ajustado a la lista sin el elemento movido,
                          // así que se acabó el clásico `if (newIndex >
                          // oldIndex) newIndex -= 1`.
                          onReorderItem: (oldIndex, newIndex) {
                            setState(() {
                              final id = _paraderoIds.removeAt(oldIndex);
                              _paraderoIds.insert(newIndex, id);
                            });
                          },
                          itemBuilder: (context, index) {
                            final id = _paraderoIds[index];
                            final stop = stops.byId(id);
                            return Card(
                              key: ValueKey(id),
                              margin: const EdgeInsets.only(
                                bottom: AppSpacing.sm,
                              ),
                              child: ListTile(
                                leading: CircleAvatar(
                                  radius: 14,
                                  backgroundColor: Color(_color),
                                  child: Text(
                                    '${index + 1}',
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                                // Un paradero dado de baja no desaparece del
                                // recorrido: se muestra su id para que el
                                // administrador vea que hay algo que arreglar.
                                title: Text(stop?.name ?? id),
                                subtitle: stop == null
                                    ? null
                                    : Text(
                                        stop.address,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.close),
                                      onPressed: () => setState(
                                        () => _paraderoIds.removeAt(index),
                                      ),
                                    ),
                                    ReorderableDragStartListener(
                                      index: index,
                                      child: const Icon(Icons.drag_handle),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ColorPicker extends StatelessWidget {
  const _ColorPicker({required this.value, required this.onChanged});

  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Wrap(
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.sm,
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
