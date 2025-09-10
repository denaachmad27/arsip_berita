import 'package:flutter/material.dart';
import '../ui/design.dart';

class UiButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool primary;
  final Color? color; // when provided, used as solid background
  const UiButton({super.key, required this.label, this.icon, this.onPressed, this.primary = true, this.color});
  @override
  Widget build(BuildContext context) {
    final bg = color ?? (primary ? DS.accent : DS.surface);
    final fg = (color != null || primary) ? Colors.white : DS.text;
    final border = (color != null || primary) ? Colors.transparent : DS.border;
    return InkWell(
      onTap: onPressed,
      borderRadius: DS.br,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(color: bg, borderRadius: DS.br, border: Border.all(color: border)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[
            Icon(icon, size: 18, color: fg), const SizedBox(width: 8),
          ],
          Text(label, style: TextStyle(color: fg, fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }
}
