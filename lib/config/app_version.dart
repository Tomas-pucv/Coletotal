import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Versión instalada de la app, leída del propio paquete.
///
/// Antes la versión vivía escrita a mano en cuatro lugares que ya no
/// coincidían entre sí: `pubspec.yaml` decía `0.4.3+4`, el actualizador `4` y
/// `'0.4.3.1'`, Preferencias `'0.4.3.1'` y la auditoría de turnos `'0.4.3+3'`.
/// El actualizador OTA compara contra este número, así que un descuido al
/// publicar hacía que el aviso de actualización no apareciera nunca o
/// apareciera siempre.
///
/// Ahora la única fuente es `version:` en `pubspec.yaml`: Flutter la copia al
/// `versionName`/`versionCode` del APK y [load] la lee de ahí.
abstract final class AppVersion {
  static String _name = '0.0.0';
  static int _code = 0;

  /// Nombre de versión (`0.4.3` en `version: 0.4.3+4`).
  static String get name => _name;

  /// Número de compilación (`4` en `version: 0.4.3+4`). Es lo que se compara
  /// contra `config/app_version.versionCode` para ofrecer la actualización.
  static int get code => _code;

  /// Texto para mostrar: `0.4.3 (4)`.
  static String get label => '$_name ($_code)';

  /// Se llama una vez desde `main()`, antes de `runApp`.
  static Future<void> load() async {
    try {
      final info = await PackageInfo.fromPlatform();
      _name = info.version;
      _code = int.tryParse(info.buildNumber) ?? 0;
    } catch (e) {
      // Sin la versión la app funciona igual; lo único que se pierde es el
      // aviso de actualización, que con código 0 se ofrece siempre.
      debugPrint('AppVersion: no se pudo leer la versión instalada: $e');
    }
  }

  @visibleForTesting
  static void debugSet({required String name, required int code}) {
    _name = name;
    _code = code;
  }
}
