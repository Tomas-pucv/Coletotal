import 'package:flutter/material.dart';

import 'package:taxi1/services/app_update_service.dart';
import 'package:taxi1/theme/app_spacing.dart';

/// Diálogo emergente que solicita actualizar la aplicación cuando
/// se publica una nueva versión para los choferes e inspectores.
class AppUpdateDialog extends StatelessWidget {
  const AppUpdateDialog({super.key, required this.info});

  final AppUpdateInfo info;

  static Future<void> showIfAvailable(
    BuildContext context,
    AppUpdateInfo info,
  ) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: !info.mandatory,
      builder: (_) => AppUpdateDialog(info: info),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return PopScope(
      canPop: !info.mandatory,
      child: AlertDialog(
        icon: Icon(
          Icons.system_update_rounded,
          size: 40,
          color: scheme.primary,
        ),
        title: Text(
          '¡Nueva versión disponible!',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.xs,
              ),
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
              ),
              child: Text(
                'Versión ${info.versionName} (Instalada: ${AppUpdateService.currentVersionName})',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: scheme.onPrimaryContainer,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Novedades y mejoras:',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                border: Border.all(
                  color: scheme.outlineVariant.withValues(alpha: 0.5),
                ),
              ),
              child: Text(
                info.changelog,
                style: theme.textTheme.bodyMedium,
              ),
            ),
            if (info.mandatory) ...[
              const SizedBox(height: AppSpacing.md),
              Text(
                'Esta actualización es obligatoria para continuar operando en la garita.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.error,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
        actions: [
          if (!info.mandatory)
            TextButton(
              onPressed: () {
                AppUpdateService.instance.dismissForNow();
                Navigator.of(context).pop();
              },
              child: const Text('Recordar más tarde'),
            ),
          FilledButton.icon(
            onPressed: () async {
              final ok = await AppUpdateService.instance.launchDownload(
                info.apkUrl,
              );
              if (!ok && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'No se pudo abrir el enlace de descarga del APK.',
                    ),
                  ),
                );
              }
            },
            icon: const Icon(Icons.download_rounded),
            label: const Text('Actualizar ahora'),
          ),
        ],
      ),
    );
  }
}
