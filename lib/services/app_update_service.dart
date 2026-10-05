import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:taxi1/config/app_version.dart';

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

  /// Novedades de la versión. Vacío si el documento no las trae: el diálogo
  /// pone entonces un texto genérico, traducido.
  final String changelog;

  /// Marcada a mano como obligatoria en `config/app_version`.
  final bool mandatory;

  factory AppUpdateInfo.fromMap(Map<String, dynamic> data) {
    final versionCode = (data['versionCode'] as num?)?.toInt() ?? 1;
    return AppUpdateInfo(
      versionCode: versionCode,
      versionName: (data['versionName'] as String?) ?? '$versionCode',
      minRequiredVersionCode:
          (data['minRequiredVersionCode'] as num?)?.toInt() ?? 1,
      apkUrl: (data['apkUrl'] as String?)?.trim() ?? '',
      changelog: (data['changelog'] as String?)?.trim() ?? '',
      mandatory: (data['esObligatoria'] as bool?) ?? false,
    );
  }

  /// Si esta versión es más nueva que la instalada ([installedCode]).
  bool isNewerThan(int installedCode) => versionCode > installedCode;

  /// Si la versión instalada ya no puede seguir operando sin actualizar.
  ///
  /// `minRequiredVersionCode` se leía de Firestore y no se usaba: una versión
  /// con un error grave no había forma de retirarla. Y una actualización
  /// obligatoria **sin enlace** no se considera obligatoria: el diálogo no se
  /// podría cerrar ni completar y dejaría la app inutilizable.
  bool isMandatoryFor(int installedCode) =>
      apkUrl.isNotEmpty && (mandatory || installedCode < minRequiredVersionCode);
}

/// Servicio que comprueba la versión remota contra Firestore y avisa
/// de nuevas actualizaciones para descarga directa sin fricción (OTA).
///
/// La versión instalada sale de [AppVersion] (el `version:` del pubspec), ya
/// no de constantes escritas a mano en este archivo.
class AppUpdateService extends ChangeNotifier {
  AppUpdateService._();
  static final AppUpdateService instance = AppUpdateService._();

  FirebaseFirestore get _db => FirebaseFirestore.instance;

  AppUpdateInfo? _availableUpdate;
  bool _checking = false;
  bool _dismissedThisSession = false;

  AppUpdateInfo? get availableUpdate => _availableUpdate;
  bool get checking => _checking;

  bool get hasUpdate =>
      _availableUpdate?.isNewerThan(AppVersion.code) ?? false;

  bool get isMandatory =>
      hasUpdate && _availableUpdate!.isMandatoryFor(AppVersion.code);

  /// Una actualización obligatoria se vuelve a mostrar aunque se haya
  /// postergado.
  bool get shouldShowDialog =>
      hasUpdate && (!_dismissedThisSession || isMandatory);

  void dismissForNow() {
    _dismissedThisSession = true;
    notifyListeners();
  }

  /// Consulta el documento `config/app_version` en Firestore.
  Future<void> checkForUpdates() async {
    if (_checking) return;
    _checking = true;
    notifyListeners();

    try {
      final doc = await _db.collection('config').doc('app_version').get();
      final data = doc.data();
      if (doc.exists && data != null) {
        final info = AppUpdateInfo.fromMap(data);
        _availableUpdate = info.isNewerThan(AppVersion.code) ? info : null;
      }
    } catch (e) {
      debugPrint('AppUpdateService: error al consultar actualización: $e');
    } finally {
      _checking = false;
      notifyListeners();
    }
  }

  /// Abre la URL directa del APK en el navegador.
  ///
  /// Sólo `https`: la URL viene de Firestore y abrir cualquier esquema que
  /// llegara ahí sería confiar demasiado en un documento remoto.
  Future<bool> launchDownload(String apkUrl) async {
    final uri = Uri.tryParse(apkUrl.trim());
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) return false;
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('AppUpdateService: error al abrir descarga: $e');
      return false;
    }
  }
}
