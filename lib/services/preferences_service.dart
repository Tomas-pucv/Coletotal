import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PreferencesService extends ChangeNotifier {
  PreferencesService._();
  static final PreferencesService instance = PreferencesService._();

  // Claves de persistencia local
  static const _keyMapType = 'map_type';
  static const _keyTheme = 'theme_mode';
  static const _keyLocationTracking = 'location_tracking';
  static const _keyFontSize = 'font_size';
  static const _keyDensity = 'compact_mode';
  static const _keyAnimations = 'animations_enabled';

  // Estilo de mapa ('normal' | 'satellite')
  String _mapType = 'normal';

  // Tema y apariencia ('system' | 'light' | 'dark')
  String _theme = 'system';
  double _fontSizeMultiplier = 1.0;
  bool _compactMode = false;
  bool _animationsEnabled = true;

  // Privacidad de ubicación
  bool _locationTracking = true;

  bool _initialized = false;

  String get mapType => _mapType;

  /// Valor textual del tema seleccionado.
  String get themeName => _theme;

  /// Modo de tema resuelto para [MaterialApp.themeMode].
  ThemeMode get themeMode => switch (_theme) {
    'dark' => ThemeMode.dark,
    'light' => ThemeMode.light,
    _ => ThemeMode.system,
  };
  double get fontSizeMultiplier => _fontSizeMultiplier;
  bool get compactMode => _compactMode;
  bool get animationsEnabled => _animationsEnabled;
  bool get locationTracking => _locationTracking;
  bool get isInitialized => _initialized;

  Future<void> load() async {
    if (_initialized) return;
    try {
      final prefs = await SharedPreferences.getInstance();

      _mapType = prefs.getString(_keyMapType) ?? 'normal';
      _theme = prefs.getString(_keyTheme) ?? 'system';
      _locationTracking = prefs.getBool(_keyLocationTracking) ?? true;
      _fontSizeMultiplier = (prefs.getDouble(_keyFontSize) ?? 1.0).clamp(
        0.8,
        1.6,
      );
      _compactMode = prefs.getBool(_keyDensity) ?? false;
      _animationsEnabled = prefs.getBool(_keyAnimations) ?? true;

      // Limpieza de claves deprecadas de versiones previas.
      await prefs.remove('user_role');
      await prefs.remove('driver_id');
      await prefs.remove('seen_welcome');
    } catch (e) {
      debugPrint('PreferencesService: error al cargar preferencias: $e');
    }

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
}
