import 'package:flutter/material.dart';
import '../ui/design.dart';

class UiChip extends StatelessWidget {
  final String label; final bool selected; final VoidCallback? onTap; final Color? activeColor;
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
