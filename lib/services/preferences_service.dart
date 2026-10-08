import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PreferencesService extends ChangeNotifier {
  PreferencesService._internal();
  static final PreferencesService instance = PreferencesService._internal();

  // Storage keys
  static const _keyMapType = 'map_type';
  static const _keyTheme = 'theme_mode';
  static const _keyLocationTracking = 'location_tracking';
  static const _keyHistoryEnabled = 'history_enabled';
  static const _keyFontSize = 'font_size';
  static const _keyDensity = 'compact_mode';
  static const _keyAnimations = 'animations_enabled';

  // Mapa
  String _mapType = 'normal';

  // Tema y apariencia. 'system' | 'light' | 'dark'
  String _theme = 'system';
  double _fontSizeMultiplier = 1.0;
  bool _compactMode = false;
  bool _animationsEnabled = true;

  // Notificaciones y privacidad
  bool _locationTracking = true;
  bool _historyEnabled = true;

  // El rol del usuario ya no vive acá.
  //
  // Era `user_role` en SharedPreferences, elegible desde un selector en esta
  // misma pantalla, más un `driver_id` generado en el teléfono. Con eso
  // cualquiera se declaraba chofer y se ponía a transmitir GPS a la garita con
  // un identificador inventado, que además impedía escribir cualquier regla de
  // seguridad. El rol es identidad, no preferencia: vive en `AuthService`.

  bool _initialized = false;

  // Getters - Mapa
  String get mapType => _mapType;

  // Getters - Tema y apariencia
  /// Valor crudo del tema, para enlazar los radios de Preferencias.
  String get themeName => _theme;

  /// Antes esta propiedad solo podía devolver light u oscuro, con lo que
  /// [ThemeMode.system] era inalcanzable y la app ignoraba el tema del sistema.
  ThemeMode get themeMode => switch (_theme) {
    'dark' => ThemeMode.dark,
    'light' => ThemeMode.light,
    _ => ThemeMode.system,
  };
  double get fontSizeMultiplier => _fontSizeMultiplier;
  bool get compactMode => _compactMode;
  bool get animationsEnabled => _animationsEnabled;

  // Getters - Notificaciones y privacidad
  bool get locationTracking => _locationTracking;
  bool get historyEnabled => _historyEnabled;

  bool get isInitialized => _initialized;

  Future<void> load() async {
    if (_initialized) return;
    final prefs = await SharedPreferences.getInstance();

    _mapType = prefs.getString(_keyMapType) ?? 'normal';
    _theme = prefs.getString(_keyTheme) ?? 'system';
    _locationTracking = prefs.getBool(_keyLocationTracking) ?? true;
    _historyEnabled = prefs.getBool(_keyHistoryEnabled) ?? true;
    _fontSizeMultiplier = prefs.getDouble(_keyFontSize) ?? 1.0;
    _compactMode = prefs.getBool(_keyDensity) ?? false;
    _animationsEnabled = prefs.getBool(_keyAnimations) ?? true;

    // Restos de estados que ya no existen: el rol local (cuando "chofer" era
    // una preferencia) y la bandera de la pantalla de bienvenida. Se borran
    // una vez para que un teléfono actualizado no arrastre un identificador de
    // vehículo que ya no significa nada.
    await prefs.remove('user_role');
    await prefs.remove('driver_id');
    await prefs.remove('seen_welcome');

    _initialized = true;
    notifyListeners();
  }

  // Setters - Mapa
  Future<void> setMapType(String value) async {
    if (value == _mapType) return;
    _mapType = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyMapType, value);
    notifyListeners();
  }

  // Setters - Tema y apariencia
  Future<void> setTheme(String value) async {
    if (value == _theme) return;
    _theme = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyTheme, value);
    notifyListeners();
  }

  Future<void> setFontSizeMultiplier(double value) async {
    if (value == _fontSizeMultiplier) return;
    _fontSizeMultiplier = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyFontSize, value);
    notifyListeners();
  }

  Future<void> setCompactMode(bool value) async {
    if (value == _compactMode) return;
    _compactMode = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyDensity, value);
    notifyListeners();
  }

  Future<void> setAnimationsEnabled(bool value) async {
    if (value == _animationsEnabled) return;
    _animationsEnabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyAnimations, value);
    notifyListeners();
  }

  // Setters - Privacidad
  //
  // `notificationsEnabled` se eliminó: era un interruptor que se persistía y no
  // tenía ningún módulo de notificaciones detrás. Volverá cuando exista el de
  // telemetría/ETA, que es lo único que justificaría notificar algo.
  Future<void> setLocationTracking(bool value) async {
    if (value == _locationTracking) return;
    _locationTracking = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyLocationTracking, value);
    notifyListeners();
  }

  Future<void> setHistoryEnabled(bool value) async {
    if (value == _historyEnabled) return;
    _historyEnabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyHistoryEnabled, value);
    notifyListeners();
  }
}
