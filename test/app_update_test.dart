import 'package:flutter_test/flutter_test.dart';
import 'package:taxi1/services/app_update_service.dart';

void main() {
  AppUpdateInfo info({
    int versionCode = 5,
    int minRequired = 1,
    String apkUrl = 'https://example.com/coletotal.apk',
    bool mandatory = false,
  }) => AppUpdateInfo(
    versionCode: versionCode,
    versionName: '0.4.4',
    minRequiredVersionCode: minRequired,
    apkUrl: apkUrl,
    changelog: '',
    mandatory: mandatory,
  );

  group('AppUpdateInfo', () {
    test('parsea correctamente un mapa de Firestore', () {
      final parsed = AppUpdateInfo.fromMap({
        'versionCode': 4,
        'versionName': '0.4.3.1',
        'minRequiredVersionCode': 3,
        'apkUrl': 'https://coletotal-32735.web.app/releases/ColeTotal.apk',
        'changelog': '• Nueva estética visual\n• Correcciones de estabilidad',
        'esObligatoria': true,
      });

      expect(parsed.versionCode, 4);
      expect(parsed.versionName, '0.4.3.1');
      expect(parsed.minRequiredVersionCode, 3);
      expect(parsed.apkUrl, endsWith('ColeTotal.apk'));
      expect(parsed.mandatory, isTrue);
      expect(parsed.changelog, contains('Nueva estética'));
    });

    test('con el documento vacío usa valores por defecto seguros', () {
      final parsed = AppUpdateInfo.fromMap({});

      expect(parsed.versionCode, 1);
      expect(parsed.versionName, '1');
      expect(parsed.minRequiredVersionCode, 1);
      expect(parsed.apkUrl, isEmpty);
      expect(parsed.mandatory, isFalse);
      // El texto genérico lo pone el diálogo, traducido.
      expect(parsed.changelog, isEmpty);
    });

    test('sólo una versión mayor que la instalada es una actualización', () {
      expect(info(versionCode: 5).isNewerThan(4), isTrue);
      expect(info(versionCode: 4).isNewerThan(4), isFalse);
      expect(info(versionCode: 3).isNewerThan(4), isFalse);
    });

    test('minRequiredVersionCode vuelve obligatoria la actualización', () {
      // Antes este campo se leía y se ignoraba: no había forma de retirar una
      // versión con un error grave.
      final remota = info(minRequired: 5);
      expect(remota.isMandatoryFor(4), isTrue);
      expect(remota.isMandatoryFor(5), isFalse);
    });

    test('la marca esObligatoria también la vuelve obligatoria', () {
      expect(info(mandatory: true).isMandatoryFor(4), isTrue);
      expect(info().isMandatoryFor(4), isFalse);
    });

    test('una obligatoria sin enlace no bloquea la app', () {
      // Un diálogo que no se puede cerrar ni completar dejaría la app
      // inutilizable para siempre.
      expect(info(mandatory: true, apkUrl: '').isMandatoryFor(4), isFalse);
      expect(info(minRequired: 9, apkUrl: '').isMandatoryFor(4), isFalse);
    });
  });

  group('AppUpdateService.launchDownload', () {
    test('rechaza enlaces que no son https', () async {
      final service = AppUpdateService.instance;
      expect(await service.launchDownload(''), isFalse);
      expect(await service.launchDownload('http://example.com/a.apk'), isFalse);
      expect(await service.launchDownload('javascript:alert(1)'), isFalse);
    });
  });
}
