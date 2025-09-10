import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:palette_generator/palette_generator.dart';
import 'design.dart';

class ThemeLoader {
  static Future<void> loadFromAsset(String assetPath) async {
    try {
      // Ensure bindings to load assets
      final image = AssetImage(assetPath);
      await image.obtainKey(const ImageConfiguration());
      final palette = await PaletteGenerator.fromImageProvider(image, maximumColorCount: 12);
      // Pick dominant as primary, vibrant/muted as secondary
      final primary = palette.dominantColor?.color ?? DS.accent;
      final secondary = (palette.vibrantColor ?? palette.lightVibrantColor ?? palette.mutedColor)?.color ?? DS.accent2;
      DS.accent = primary;
      DS.accent2 = secondary;
      DS.accentLite = primary.withOpacity(0.2);
      DS.accent2Lite = secondary.withOpacity(0.2);
    } catch (_) {
      // ignore, keep defaults
    }
  }
}

