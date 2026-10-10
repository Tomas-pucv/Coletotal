import 'package:flutter/material.dart';

import 'package:taxi1/l10n/app_localizations.dart';
import 'package:taxi1/models/recorrido.dart';
import 'package:taxi1/models/variante.dart';
import 'package:taxi1/navigation/app_destination.dart';
import 'package:taxi1/services/auth_service.dart';
import 'package:taxi1/services/firestore_writes.dart';
import 'package:taxi1/services/garita_service.dart';
import 'package:taxi1/services/recorridos_service.dart';
import 'package:taxi1/theme/app_spacing.dart';
import 'package:taxi1/theme/breakpoints.dart';
import 'package:taxi1/widgets/setting_tile.dart';
import 'package:taxi1/widgets/state_views.dart';

/// Lista de recorridos y cartolas de la garita.
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
                          final variante = varianteById(recorrido.varianteId);
                          final varText = variante?.nombre ??
                              (recorrido.varianteNombre.isNotEmpty
                                  ? recorrido.varianteNombre
                                  : 'Variante general');
                          final totalCalles =
                              recorrido.callesIda.length + recorrido.callesVuelta.length;

                          return Card(
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: Color(recorrido.colorValue),
                                child: const Icon(
                                  Icons.alt_route,
                                  color: Colors.white,
                                  size: 20,
                                ),
                              ),
                              title: Text(recorrido.nombre),
                              subtitle: Text(
                                totalCalles > 0
                                    ? '$varText • ${recorrido.callesIda.length} ida / ${recorrido.callesVuelta.length} vuelta'
                                    : '$varText • Sin cartolas registradas',
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

/// Calles e hitos comunes en la red vial de Quilpué para sugerencias rápidas.
const List<String> _kCallesSugeridasQuilpue = [
  'Garita Serrano',
  'Av. Los Carrera',
  'Freire',
  'Av. Valparaíso',
  'Baden Powell',
  'Marga Marga',
  'Estación Quilpué',
  'Hospital de Quilpué',
  'Plaza Vieja',
  'Belloto 2000',
  'Las Rosas',
  'El Mirador',
  'Cumming',
  'San Martín',
  'Covadonga',
  'Blanco Encalada',
  'Thompson',
  'Diego Portales',
  'Paredes',
  'Vespucio',
  'Tierras Rojas',
];

/// Editor de un recorrido modelado a través de sus **Cartolas Oficiales**
/// (secuencia de calles de Ida y Vuelta) y su variante asignada.
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

class _RecorridoEditorScreenState extends State<RecorridoEditorScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nombre;
  late final TabController _tabController;

  late String _varianteId;
  late List<String> _callesIda;
  late List<String> _callesVuelta;
  late int _color;
  late bool _activo;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final r = widget.recorrido;
    _nombre = TextEditingController(text: r?.nombre ?? '');
    _varianteId = r?.varianteId ?? (kVariantesSerrano.isNotEmpty ? kVariantesSerrano.first.id : '');
    _callesIda = List.of(r?.callesIda ?? const []);
    _callesVuelta = List.of(r?.callesVuelta ?? const []);
    _color = r?.colorValue ?? kRecorridoColors.first;
    _activo = r?.activo ?? true;
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _nombre.dispose();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _agregarCalle(bool esIda) async {
    final streetCtrl = TextEditingController();
    final agregada = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(esIda ? 'Agregar calle a Cartola de Ida' : 'Agregar calle a Cartola de Vuelta'),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: streetCtrl,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Nombre de la calle o hito',
                  hintText: 'Ej. Freire, Baden Powell...',
                  prefixIcon: Icon(Icons.edit_road),
                ),
                onSubmitted: (val) {
                  if (val.trim().isNotEmpty) {
                    Navigator.pop(context, val.trim());
                  }
                },
              ),
              const SizedBox(height: AppSpacing.md),
              const Text(
                'Sugerencias frecuentes en Quilpué:',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: AppSpacing.xs),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final sugerida in _kCallesSugeridasQuilpue.take(8))
                    ActionChip(
                      label: Text(sugerida, style: const TextStyle(fontSize: 11)),
                      onPressed: () => Navigator.pop(context, sugerida),
                    ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              final text = streetCtrl.text.trim();
              if (text.isNotEmpty) Navigator.pop(context, text);
            },
            child: const Text('Agregar'),
          ),
        ],
      ),
    );

    if (agregada != null && agregada.trim().isNotEmpty) {
      setState(() {
        if (esIda) {
          _callesIda.add(agregada.trim());
        } else {
          _callesVuelta.add(agregada.trim());
        }
      });
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!(_formKey.currentState?.validate() ?? false)) {
      _tabController.animateTo(0);
      return;
    }

    final l10n = AppLocalizations.of(context)!;
    if (_callesIda.isEmpty && _callesVuelta.isEmpty) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Debes registrar al menos una calle en la cartola de ida o vuelta'),
          ),
        );
      _tabController.animateTo(1);
      return;
    }

    setState(() => _saving = true);
    final original = widget.recorrido;
    final varianteObj = varianteById(_varianteId);

    try {
      final (_, outcome) = await GaritaService.instance.upsertRecorrido(
        Recorrido(
          id: original?.id ?? '',
          garitaId: widget.garitaId,
          nombre: _nombre.text.trim(),
          colorValue: _color,
          varianteId: _varianteId,
          varianteNombre: varianteObj?.nombre ?? '',
          callesIda: _callesIda,
          callesVuelta: _callesVuelta,
          paraderoIds: original?.paraderoIds ?? const [],
          geometria: original?.geometria,
          geometriaVuelta: original?.geometriaVuelta,
          trazado: original?.trazado ?? const [],
          trazadoVuelta: original?.trazadoVuelta ?? const [],
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
    final tabIndex = _tabController.index;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.recorrido == null ? l10n.routeAdd : l10n.routeEdit),
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
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            const Tab(
              icon: Icon(Icons.tune),
              text: 'General',
            ),
            Tab(
              icon: const Icon(Icons.arrow_forward),
              text: 'Ida (${_callesIda.length})',
            ),
            Tab(
              icon: const Icon(Icons.arrow_back),
              text: 'Vuelta (${_callesVuelta.length})',
            ),
          ],
        ),
      ),
      floatingActionButton: tabIndex == 0
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _agregarCalle(tabIndex == 1),
              icon: const Icon(Icons.add_road),
              label: Text(tabIndex == 1 ? 'Agregar a Ida' : 'Agregar a Vuelta'),
            ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: Breakpoints.maxContentWidth,
          ),
          child: TabBarView(
            controller: _tabController,
            children: [
              // Tab 1: Datos Generales
              Form(
                key: _formKey,
                child: ListView(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  children: [
                    TextFormField(
                      controller: _nombre,
                      textCapitalization: TextCapitalization.words,
                      maxLength: 80,
                      decoration: InputDecoration(
                        labelText: l10n.routeName,
                        hintText: 'Ej. Línea 101 - Variante Belloto 2000',
                        prefixIcon: const Icon(Icons.alt_route),
                      ),
                      validator: (v) =>
                          (v ?? '').trim().isEmpty ? l10n.authRequired : null,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    DropdownButtonFormField<String>(
                      initialValue: _varianteId.isNotEmpty ? _varianteId : null,
                      decoration: const InputDecoration(
                        labelText: 'Variante Operacional',
                        prefixIcon: Icon(Icons.hub_outlined),
                      ),
                      items: [
                        for (final v in kVariantesSerrano)
                          DropdownMenuItem(
                            value: v.id,
                            child: Text(v.nombre),
                          ),
                      ],
                      onChanged: (val) {
                        if (val != null) setState(() => _varianteId = val);
                      },
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
                    const SizedBox(height: AppSpacing.lg),
                    Card(
                      color: theme.colorScheme.surfaceContainerHighest,
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        child: Row(
                          children: [
                            Icon(
                              Icons.info_outline,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: AppSpacing.md),
                            Expanded(
                              child: Text(
                                'Las cartolas oficiales determinan el orden de calles de ida y vuelta que los choferes y pasajeros verán.',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Tab 2: Cartola de Ida
              _CartolaListTab(
                calles: _callesIda,
                esIda: true,
                colorValue: _color,
                onReorder: (oldIndex, newIndex) {
                  setState(() {
                    final item = _callesIda.removeAt(oldIndex);
                    _callesIda.insert(newIndex, item);
                  });
                },
                onDelete: (index) {
                  setState(() => _callesIda.removeAt(index));
                },
                onAdd: () => _agregarCalle(true),
              ),

              // Tab 3: Cartola de Vuelta
              _CartolaListTab(
                calles: _callesVuelta,
                esIda: false,
                colorValue: _color,
                onReorder: (oldIndex, newIndex) {
                  setState(() {
                    final item = _callesVuelta.removeAt(oldIndex);
                    _callesVuelta.insert(newIndex, item);
                  });
                },
                onDelete: (index) {
                  setState(() => _callesVuelta.removeAt(index));
                },
                onAdd: () => _agregarCalle(false),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CartolaListTab extends StatelessWidget {
  const _CartolaListTab({
    required this.calles,
    required this.esIda,
    required this.colorValue,
    required this.onReorder,
    required this.onDelete,
    required this.onAdd,
  });

  final List<String> calles;
  final bool esIda;
  final int colorValue;
  final void Function(int oldIndex, int newIndex) onReorder;
  final ValueChanged<int> onDelete;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (calles.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                esIda ? Icons.arrow_forward : Icons.arrow_back,
                size: 48,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                esIda ? 'Sin calles en Cartola de Ida' : 'Sin calles en Cartola de Vuelta',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Agrega las calles o hitos principales que componen el trayecto oficial.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              FilledButton.icon(
                onPressed: onAdd,
                icon: const Icon(Icons.add_road),
                label: const Text('Agregar primera calle'),
              ),
            ],
          ),
        ),
      );
    }

    return ReorderableListView.builder(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        96,
      ),
      itemCount: calles.length,
      onReorderItem: onReorder,
      itemBuilder: (context, index) {
        final calle = calles[index];
        return Card(
          key: ValueKey('cartola_${esIda ? "ida" : "vuelta"}_${index}_$calle'),
          margin: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: ListTile(
            leading: CircleAvatar(
              radius: 14,
              backgroundColor: Color(colorValue),
              child: Text(
                '${index + 1}',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            title: Text(calle, style: theme.textTheme.titleSmall),
            subtitle: Text(
              index == 0
                  ? 'Origen / Inicio de cartola'
                  : index == calles.length - 1
                      ? 'Destino / Fin de cartola'
                      : 'Tramo intermedio',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: 'Quitar de la cartola',
                  onPressed: () => onDelete(index),
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
