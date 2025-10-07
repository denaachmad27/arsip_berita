import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'design.dart';

enum ThemePreference {
  light,
  dark,
  system,
}

class ThemeController extends ChangeNotifier {
  bool isDark = false;
  ThemePreference preference = ThemePreference.system;
  static final ThemeController instance = ThemeController._();

  ThemeController._() {
    init();
  }

  Color? _baseAccent;
  Color? _baseAccent2;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final savedPref = prefs.getString('theme_preference') ?? 'system';

    switch (savedPref) {
      case 'light':
        preference = ThemePreference.light;
        isDark = false;
        break;
      case 'dark':
        preference = ThemePreference.dark;
        isDark = true;
        break;
      case 'system':
      default:
        preference = ThemePreference.system;
        isDark = _getSystemBrightness();
        break;
    }

    _apply();
    notifyListeners();
  }

  bool _getSystemBrightness() {
    // This will be updated when we get the actual brightness from the widget
    return false;
  }

  Future<void> setThemePreference(ThemePreference pref, {Brightness? systemBrightness}) async {
    preference = pref;

    switch (pref) {
      case ThemePreference.light:
        isDark = false;
        break;
      case ThemePreference.dark:
        isDark = true;
        break;
      case ThemePreference.system:
        isDark = systemBrightness == Brightness.dark;
        break;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('theme_preference', pref.name);

    _apply();
    notifyListeners();
  }

  void updateSystemBrightness(Brightness brightness) {
    if (preference == ThemePreference.system) {
      final newIsDark = brightness == Brightness.dark;
      if (newIsDark != isDark) {
        isDark = newIsDark;
        _apply();
        notifyListeners();
      }
    }
  }

  void setDark(bool v) {
    setThemePreference(v ? ThemePreference.dark : ThemePreference.light);
  }

  void toggle() {
    setDark(!isDark);
  }

  void _apply() {
    _baseAccent ??= DS.accent;
    _baseAccent2 ??= DS.accent2;

    if (!isDark) {
      // Light scheme
      DS.bg = const Color(0xFFF4F6F8);
      DS.surface = const Color(0xFFFCFCFD);
      DS.surface2 = const Color(0xFFF6F7F9);
      DS.border = const Color(0xFFE5E7EB);
      DS.text = const Color(0xFF0F172A);
      DS.textDim = const Color(0xFF475569);
      // accents keep from loader; ensure lite variants
      DS.accent = _baseAccent!;
      DS.accent2 = _baseAccent2!;
      DS.accentLite = DS.accent.withOpacity(0.2);
      DS.accent2Lite = DS.accent2.withOpacity(0.2);
    } else {
      // Dark scheme, serious
      DS.bg = const Color(0xFF0B1220);
      DS.surface = const Color(0xFF101827);
      DS.surface2 = const Color(0xFF0F172A);
      DS.border = const Color(0xFF1F2A3C);
      DS.text = const Color(0xFFE5E7EB);
      DS.textDim = const Color(0xFF9CA3AF);
      // Accents slightly brighter on dark
      DS.accent = _ensureContrast(_baseAccent!, lightOnDark: true);
      DS.accent2 = _ensureContrast(_baseAccent2!, lightOnDark: true);
      DS.accentLite = DS.accent.withOpacity(0.2);
      DS.accent2Lite = DS.accent2.withOpacity(0.2);
    }
  }

  Color _ensureContrast(Color c, {required bool lightOnDark}) {
    if (!lightOnDark) return c;
    // boost saturation/lightness a bit for dark backgrounds
    final hsl = HSLColor.fromColor(c);
    final boosted = hsl.withLightness((hsl.lightness + 0.08).clamp(0.0, 1.0));
    return boosted.toColor();
  }
}
