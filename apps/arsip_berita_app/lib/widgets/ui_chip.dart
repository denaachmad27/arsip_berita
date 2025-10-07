import 'package:flutter/material.dart';
import '../ui/design.dart';
import '../ui/theme_mode.dart';

class UiChip extends StatelessWidget {
  final String label; final bool selected; final VoidCallback? onTap; final Color? activeColor;
  const UiChip({super.key, required this.label, this.selected = false, this.onTap, this.activeColor});
  @override
  Widget build(BuildContext context) {
    final isDark = ThemeController.instance.isDark;
    final Color ac = activeColor ?? DS.accent;

    // For dark mode: golden yellow background with dark text
    final bg = selected
        ? (isDark
            ? const Color(0xFFD4A574)  // Golden yellow for dark mode
            : (activeColor == null ? DS.accentLite : DS.accent2Lite))
        : DS.surface;

    final fg = selected
        ? (isDark
            ? const Color(0xFF1F2937)  // Dark text for dark mode chip
            : ac)
        : DS.text;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected && isDark ? const Color(0xFFD4A574) : DS.border)
        ),
        child: Text(label, style: TextStyle(color: fg, fontWeight: FontWeight.w600)),
      ),
    );
  }
}
