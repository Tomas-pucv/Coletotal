import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Lo que necesita el turno para seguir transmitiendo con la pantalla
/// bloqueada o en otra app.
///
/// Durante el turno el GPS ya corre en un servicio en primer plano (ver
/// `LocationService`), pero el teléfono puede frenarlo igual: desde Android 13
/// su notificación no se muestra sin permiso, y el ahorro de batería —en
/// Xiaomi, además, su propio ahorro por app— corta la red con la pantalla
/// bloqueada. Los pasajeros dejaban de ver el colectivo.
///
/// El lado nativo está en `MainActivity.kt` (canal `cl.coletotal/segundo_plano`).
abstract final class SegundoPlano {
  static const _canal = MethodChannel('cl.coletotal/segundo_plano');

  /// Si ya se pidieron los permisos: se piden una sola vez, al primer turno.
  static const _clavePedido = 'segundo_plano_pedido';

  /// Si ya se mostró el aviso de Xiaomi.
  static const _claveXiaomi = 'segundo_plano_aviso_xiaomi';

  static bool get _android =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Pide, la primera vez, el permiso de notificaciones y quedar fuera del
  /// ahorro de batería, con los diálogos del sistema. Vuelve cuando el usuario
  /// los cerró, así el turno arranca con la app otra vez al frente.
  ///
  /// Devuelve si hay que mostrar el aviso para teléfonos Xiaomi: una sola vez.
  static Future<bool> preparar() async {
    if (!_android) return false;
    try {
      final sp = await SharedPreferences.getInstance();
      final estado = await _canal.invokeMapMethod<String, Object?>('estado');
      if (estado == null) return false;
      if (sp.getBool(_clavePedido) != true) {
        await sp.setBool(_clavePedido, true);
        if (estado['notificaciones'] == false) {
          await _canal.invokeMethod<bool>('pedirNotificaciones');
        }
        if (estado['bateria'] == false) {
          await _canal.invokeMethod<bool>('pedirSinAhorroDeBateria');
        }
      }
      return estado['xiaomi'] == true && sp.getBool(_claveXiaomi) != true;
    } catch (e) {
      // Sin el canal (pruebas, otra plataforma): el turno arranca igual.
      debugPrint('SegundoPlano: no se pudo preparar: $e');
      return false;
    }
  }

  /// El aviso de Xiaomi ya se mostró: no se repite.
  static Future<void> marcarAvisoXiaomi() async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setBool(_claveXiaomi, true);
    } catch (_) {}
  }

  /// La ficha de la app en los ajustes del teléfono.
  static Future<void> abrirAjustes() async {
    if (!_android) return;
    try {
      await _canal.invokeMethod<void>('abrirAjustes');
    } catch (e) {
      debugPrint('SegundoPlano: no se pudieron abrir los ajustes: $e');
    }
  }
}
