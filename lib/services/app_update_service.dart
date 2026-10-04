import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

class AppUpdateInfo {
  const AppUpdateInfo({
    required this.versionCode,
    required this.versionName,
    required this.minRequiredVersionCode,
    required this.apkUrl,
    required this.changelog,
    required this.mandatory,
  });

  final int versionCode;
  final String versionName;
  final int minRequiredVersionCode;
  final String apkUrl;
  final String changelog;
  final bool mandatory;

  factory AppUpdateInfo.fromMap(Map<String, dynamic> data) => AppUpdateInfo(
    versionCode: (data['versionCode'] as num?)?.toInt() ?? 1,
    versionName: (data['versionName'] as String?) ?? '0.4.3',
    minRequiredVersionCode:
        (data['minRequiredVersionCode'] as num?)?.toInt() ?? 1,
    apkUrl: (data['apkUrl'] as String?) ?? '',
    changelog:
        (data['changelog'] as String?) ??
        'Nueva versión con mejoras operacionales.',
    mandatory: (data['esObligatoria'] as bool?) ?? false,
  );
}

/// Servicio que comprueba la versión remota contra Firestore y avisa
/// de nuevas actualizaciones para descarga directa sin fricción (OTA).
class AppUpdateService extends ChangeNotifier {
  AppUpdateService._();
  static final AppUpdateService instance = AppUpdateService._();

  /// Versión actual instalada en el dispositivo (alineada con pubspec.yaml 0.4.3+4).
  static const int currentVersionCode = 4;
  static const String currentVersionName = '0.4.3.1';

  FirebaseFirestore get _db => FirebaseFirestore.instance;

  AppUpdateInfo? _availableUpdate;
  bool _checking = false;
  bool _dismissedThisSession = false;

  AppUpdateInfo? get availableUpdate => _availableUpdate;
  bool get hasUpdate =>
      _availableUpdate != null &&
      _availableUpdate!.versionCode > currentVersionCode;
  bool get shouldShowDialog => hasUpdate && !_dismissedThisSession;

  void dismissForNow() {
    _dismissedThisSession = true;
    notifyListeners();
  }

  /// Consulta el documento `config/app_version` en Firestore.
  Future<void> checkForUpdates() async {
    if (_checking) return;
    _checking = true;

    try {
      final doc = await _db.collection('config').doc('app_version').get();
      if (!doc.exists || doc.data() == null) {
        _checking = false;
        return;
      }

      final info = AppUpdateInfo.fromMap(doc.data()!);
      if (info.versionCode > currentVersionCode) {
        _availableUpdate = info;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('AppUpdateService: error al consultar actualización: $e');
    } finally {
      _checking = false;
    }
  }

  /// Inicia la descarga del nuevo APK abriendo la URL directa de Firebase / GitHub.
  Future<bool> launchDownload(String apkUrl) async {
    if (apkUrl.trim().isEmpty) return false;
    final uri = Uri.parse(apkUrl);
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('AppUpdateService: error al abrir descarga: $e');
      return false;
    }
  }
}
