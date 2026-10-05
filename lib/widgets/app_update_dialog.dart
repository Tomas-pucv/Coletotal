import 'package:flutter/material.dart';

import 'package:taxi1/config/app_version.dart';
import 'package:taxi1/l10n/app_localizations.dart';
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
      barrierDismissible: !info.isMandatoryFor(AppVersion.code),
      builder: (_) => AppUpdateDialog(info: info),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final mandatory = info.isMandatoryFor(AppVersion.code);

    return PopScope(
      canPop: !mandatory,
      child: AlertDialog(
        icon: Icon(
          Icons.system_update_rounded,
          size: 40,
          color: scheme.primary,
        ),
        title: Text(
          l10n.updateTitle,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
        ),
        content: SingleChildScrollView(
          child: Column(
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
                  l10n.updateVersions(info.versionName, AppVersion.label),
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: scheme.onPrimaryContainer,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                l10n.updateChangelogTitle,
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
                  info.changelog.isEmpty
                      ? l10n.updateDefaultChangelog
                      : info.changelog,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
              if (mandatory) ...[
                const SizedBox(height: AppSpacing.md),
                Text(
                  l10n.updateMandatory,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.error,
                    fontWeight: FontWeight.w500,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
        actions: [
          if (!mandatory)
            TextButton(
              onPressed: () {
                AppUpdateService.instance.dismissForNow();
                Navigator.of(context).pop();
              },
              child: Text(l10n.updateLater),
            ),
          FilledButton.icon(
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              final ok = await AppUpdateService.instance.launchDownload(
                info.apkUrl,
              );
              if (!ok) {
                messenger.showSnackBar(
                  SnackBar(content: Text(l10n.updateOpenFailed)),
                );
              }
            },
            icon: const Icon(Icons.download_rounded),
            label: Text(l10n.updateNow),
          ),
        ],
      ),
    );
  }
}
