import 'package:flutter/material.dart';
import '../ui/design.dart';

class UiListItem extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final Color? accentColor;
  final Widget? leading;
  const UiListItem({super.key, required this.title, required this.subtitle, this.onTap, this.accentColor, this.leading});
  @override
  Widget build(BuildContext context) {
    final Color ac = accentColor ?? DS.accent;
    return InkWell(
      onTap: onTap,
      borderRadius: DS.br,
      child: Container(
        decoration: BoxDecoration(color: DS.surface, borderRadius: DS.br, border: Border.all(color: DS.border)),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(children: [
          Container(width: 3, height: 36, decoration: BoxDecoration(color: ac, borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 12),
          if (leading != null) ...[
            ClipRRect(borderRadius: BorderRadius.circular(8), child: SizedBox(width: 56, height: 56, child: FittedBox(fit: BoxFit.cover, child: leading))),
            const SizedBox(width: 12),
          ],
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: DS.text)),
            const SizedBox(height: 4),
            Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: DS.textDim)),
          ])),
          Icon(Icons.chevron_right, color: DS.textDim),
        ]),
      ),
    );
  }
}
