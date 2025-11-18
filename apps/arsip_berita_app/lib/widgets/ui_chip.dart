import 'package:flutter/material.dart';
import '../ui/design.dart';

class UiChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final Color? activeColor;
  const UiChip({super.key, required this.label, this.selected = false, this.onTap, this.activeColor});
  @override
  Widget build(BuildContext context) {
    final Color ac = activeColor ?? DS.accent;
    final bg = selected ? (activeColor == null ? DS.accentLite : DS.accent2Lite) : DS.surface;
    final fg = selected ? ac : DS.text;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20), border: Border.all(color: DS.border)),
        child: Text(label, style: TextStyle(color: fg, fontWeight: FontWeight.w600)),
      ),
    );
  }
}

class UiIconChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final Color? backgroundColor;
  final Color? textColor;
  final Color? iconColor;
  final double? fontSize;

  const UiIconChip({
    super.key,
    required this.label,
    required this.icon,
    this.onTap,
    this.backgroundColor,
    this.textColor,
    this.iconColor,
    this.fontSize,
  });

  @override
  Widget build(BuildContext context) {
    final bg = backgroundColor ?? DS.accent.withValues(alpha: 0.1);
    final fg = textColor ?? DS.accent;
    final ic = iconColor ?? DS.accent;
    final fs = fontSize ?? 12.0;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: bg, width: 0.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: ic,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: fg,
                fontSize: fs,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
