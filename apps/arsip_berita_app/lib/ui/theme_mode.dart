import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'design.dart';

class ThemeController extends ChangeNotifier {
  bool isDark = false;
  static final ThemeController instance = ThemeController._();
  ThemeController._() {
    init();
  }

  Color? _baseAccent;
  Color? _baseAccent2;

  Future<void> init() async {
    isDark = false;
    _apply();
    notifyListeners();
  }

  void setDark(bool v) {
    // Do nothing
  }

  void toggle() {
    // Do nothing
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
