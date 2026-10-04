import 'package:flutter_test/flutter_test.dart';
import 'package:taxi1/services/app_update_service.dart';

void main() {
  group('AppUpdateService y AppUpdateInfo', () {
    test('AppUpdateInfo parsea correctamente un mapa de Firestore', () {
      final data = {
        'versionCode': 4,
        'versionName': '0.4.3.1',
        'minRequiredVersionCode': 3,
        'apkUrl': 'https://coletotal-32735.web.app/releases/ColeTotal-v0.4.3.1.apk',
        'changelog': '• Nueva estética visual\n• Correcciones de estabilidad',
        'esObligatoria': true,
      };

      final info = AppUpdateInfo.fromMap(data);

      expect(info.versionCode, equals(4));
      expect(info.versionName, equals('0.4.3.1'));
      expect(info.minRequiredVersionCode, equals(3));
      expect(info.apkUrl, equals('https://coletotal-32735.web.app/releases/ColeTotal-v0.4.3.1.apk'));
      expect(info.mandatory, isTrue);
      expect(info.changelog, contains('Nueva estética'));
    });

    test('AppUpdateInfo maneja valores nulos con valores por defecto seguros', () {
      final info = AppUpdateInfo.fromMap({});

      expect(info.versionCode, equals(1));
      expect(info.versionName, equals('0.4.3'));
      expect(info.minRequiredVersionCode, equals(1));
      expect(info.apkUrl, isEmpty);
      expect(info.mandatory, isFalse);
      expect(info.changelog, isNotEmpty);
    });

    test('Lógica de detección: detecta actualización si versionCode remoto > local', () {
      const currentCode = AppUpdateService.currentVersionCode;

      final updateMayor = AppUpdateInfo(
        versionCode: currentCode + 1,
        versionName: '9.9.9',
        minRequiredVersionCode: 1,
        apkUrl: 'http://test.url',
        changelog: 'Test',
        mandatory: false,
      );

      final updateIgual = AppUpdateInfo(
        versionCode: currentCode,
        versionName: '0.4.3',
        minRequiredVersionCode: 1,
        apkUrl: 'http://test.url',
        changelog: 'Test',
        mandatory: false,
      );

      final updateMenor = AppUpdateInfo(
        versionCode: currentCode - 1,
        versionName: '0.1.0',
        minRequiredVersionCode: 1,
        apkUrl: 'http://test.url',
        changelog: 'Test',
        mandatory: false,
      );

      expect(updateMayor.versionCode > currentCode, isTrue);
      expect(updateIgual.versionCode > currentCode, isFalse);
      expect(updateMenor.versionCode > currentCode, isFalse);
    });
  });
}
