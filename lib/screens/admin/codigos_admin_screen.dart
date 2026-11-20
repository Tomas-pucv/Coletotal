import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:taxi1/l10n/app_localizations.dart';
import 'package:taxi1/models/app_user.dart';
import 'package:taxi1/models/garita.dart';
import 'package:taxi1/services/auth_service.dart';
import 'package:taxi1/services/firestore_writes.dart';
import 'package:taxi1/services/garita_service.dart';
import 'package:taxi1/theme/app_spacing.dart';
import 'package:taxi1/theme/breakpoints.dart';
import 'package:taxi1/widgets/state_views.dart';

/// Gestión de códigos de acceso de la garita para inscribir nuevos conductores
/// y administradores.
class CodigosAdminScreen extends StatefulWidget {
  const CodigosAdminScreen({super.key});

  @override
  State<CodigosAdminScreen> createState() => _CodigosAdminScreenState();
}

class _CodigosAdminScreenState extends State<CodigosAdminScreen> {
  final _garita = GaritaService.instance;
  final _auth = AuthService.instance;

  @override
  void initState() {
    super.initState();
    _garita.addListener(_onChanged);
  }

  @override
  void dispose() {
    _garita.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _toggleActivo(CodigoAcceso codigo, bool activo) async {
    final l10n = AppLocalizations.of(context)!;
    try {
      final outcome = await _garita.setCodigoAccesoActivo(codigo, activo);
      _toast(
        outcome == WriteOutcome.queuedOffline
            ? l10n.savedOffline
            : l10n.driverSaved,
      );
    } catch (_) {
      _toast(l10n.errAuthUnknown);
    }
  }

  Future<void> _eliminar(CodigoAcceso codigo) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar código de garita'),
        content: Text(
          'Se eliminará el código «${codigo.codigo}». Los usuarios que ya se '
          'registraron seguirán con su cuenta activa, pero nadie más podrá '
          'inscribirse con este código.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
    if (confirmar != true) return;
    try {
      await _garita.deleteCodigoAcceso(codigo.codigo);
      _toast('Código eliminado.');
    } catch (_) {
      _toast(l10n.errAuthUnknown);
    }
  }

  Future<void> _crearCodigo() async {
    final gid = _auth.garitaId;
    if (gid == null || gid.isEmpty) return;
    final l10n = AppLocalizations.of(context)!;
    final creado = await showDialog<CodigoAcceso>(
      context: context,
      builder: (_) => _NuevoCodigoDialog(garitaId: gid),
    );
    if (creado == null || !mounted) return;
    try {
      final outcome = await _garita.upsertCodigoAcceso(creado);
      _toast(
        outcome == WriteOutcome.queuedOffline
            ? l10n.savedOffline
            : 'Código ${creado.codigo} guardado.',
      );
    } catch (_) {
      _toast(l10n.errAuthUnknown);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final codigos = _garita.codigos;

    return Scaffold(
      appBar: AppBar(title: const Text('Códigos de garita')),
      floatingActionButton: _auth.isAdmin
          ? FloatingActionButton.extended(
              onPressed: _crearCodigo,
              icon: const Icon(Icons.add_moderator_outlined),
              label: const Text('Nuevo código'),
            )
          : null,
      body: !_auth.isAdmin
          ? StatusMessageView(
              icon: Icons.lock_outline,
              title: 'Códigos de garita',
              message: l10n.adminOnly,
            )
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: Breakpoints.maxContentWidth,
                ),
                child: codigos.isEmpty
                    ? const StatusMessageView(
                        icon: Icons.vpn_key_outlined,
                        title: 'Sin códigos de acceso',
                        message:
                            'Crea un código de conductor o de administrador '
                            'para inscribir usuarios en tu garita.',
                      )
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.lg,
                          AppSpacing.lg,
                          AppSpacing.lg,
                          96,
                        ),
                        children: [
                          const InlineNotice(
                            icon: Icons.info_outline,
                            message:
                                'Comparte el código de Conductor sólo con los '
                                'conductores de tu línea. Si un código se '
                                'filtra, apágalo aquí y crea uno nuevo.',
                            tone: StatusTone.neutral,
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          for (final c in codigos) ...[
                            _CodigoTile(
                              codigo: c,
                              onToggle: (v) => _toggleActivo(c, v),
                              onCopy: () {
                                Clipboard.setData(
                                  ClipboardData(text: c.codigo),
                                );
                                _toast('Código ${c.codigo} copiado.');
                              },
                              onDelete: () => _eliminar(c),
                            ),
                            const SizedBox(height: AppSpacing.sm),
                          ],
                        ],
                      ),
              ),
            ),
    );
  }
}

class _CodigoTile extends StatelessWidget {
  const _CodigoTile({
    required this.codigo,
    required this.onToggle,
    required this.onCopy,
    required this.onDelete,
  });

  final CodigoAcceso codigo;
  final ValueChanged<bool> onToggle;
  final VoidCallback onCopy;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final esAdmin = codigo.rol == UserRole.administrador;
    final rolTexto = esAdmin ? 'Administrador' : 'Conductor';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: codigo.activo
                  ? (esAdmin
                        ? scheme.tertiaryContainer
                        : scheme.secondaryContainer)
                  : scheme.surfaceContainerHighest,
              foregroundColor: codigo.activo
                  ? (esAdmin
                        ? scheme.onTertiaryContainer
                        : scheme.onSecondaryContainer)
                  : scheme.onSurfaceVariant,
              child: Icon(
                esAdmin ? Icons.admin_panel_settings_outlined : Icons.local_taxi,
                size: 20,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SelectableText(
                    codigo.codigo,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    codigo.activo
                        ? 'Rol: $rolTexto · Activo'
                        : 'Rol: $rolTexto · Desactivado',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.copy_outlined, size: 20),
              tooltip: 'Copiar código',
              onPressed: onCopy,
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 20),
              tooltip: 'Eliminar código',
              onPressed: onDelete,
            ),
            Switch(value: codigo.activo, onChanged: onToggle),
          ],
        ),
      ),
    );
  }
}

class _NuevoCodigoDialog extends StatefulWidget {
  const _NuevoCodigoDialog({required this.garitaId});

  final String garitaId;

  @override
  State<_NuevoCodigoDialog> createState() => _NuevoCodigoDialogState();
}

class _NuevoCodigoDialogState extends State<_NuevoCodigoDialog> {
  final _formKey = GlobalKey<FormState>();
  final _controller = TextEditingController();
  UserRole _rol = UserRole.colectivero;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _generarAleatorio() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rnd = Random.secure();
    final sufijo = List.generate(
      6,
      (_) => chars[rnd.nextInt(chars.length)],
    ).join();
    final prefijo = _rol == UserRole.administrador ? 'ADMIN' : 'COND';
    setState(() {
      _controller.text = '$prefijo$sufijo';
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return AlertDialog(
      title: const Text('Nuevo código de garita'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SegmentedButton<UserRole>(
              selected: {_rol},
              onSelectionChanged: (s) => setState(() => _rol = s.first),
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(
                  value: UserRole.colectivero,
                  icon: Icon(Icons.local_taxi, size: 18),
                  label: Text('Conductor'),
                ),
                ButtonSegment(
                  value: UserRole.administrador,
                  icon: Icon(Icons.apartment, size: 18),
                  label: Text('Administrador'),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              controller: _controller,
              textCapitalization: TextCapitalization.characters,
              autocorrect: false,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9_-]')),
                LengthLimitingTextInputFormatter(32),
              ],
              decoration: InputDecoration(
                labelText: 'Código',
                hintText: 'Ej: CONDUCTORSERRANOS',
                suffixIcon: IconButton(
                  icon: const Icon(Icons.casino_outlined),
                  tooltip: 'Generar código aleatorio',
                  onPressed: _generarAleatorio,
                ),
              ),
              validator: (v) {
                final limpio = (v ?? '').trim().toUpperCase();
                if (limpio.length < 4) {
                  return 'Mínimo 4 caracteres.';
                }
                if (limpio.contains('CHOFER') ||
                    limpio.contains('COLECTIVERO')) {
                  return 'Usa CONDUCTOR en lugar de CHOFER o COLECTIVERO.';
                }
                return null;
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: () {
            if (!(_formKey.currentState?.validate() ?? false)) return;
            Navigator.of(context).pop(
              CodigoAcceso(
                codigo: _controller.text.trim().toUpperCase(),
                garitaId: widget.garitaId,
                rol: _rol,
                activo: true,
              ),
            );
          },
          child: Text(l10n.save),
        ),
      ],
    );
  }
}
