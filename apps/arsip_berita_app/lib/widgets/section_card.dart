import 'package:flutter/material.dart';
import '../ui/theme.dart';

class SectionCard extends StatelessWidget {
  final String? title;
  final Widget child;
  final Widget? trailing;
  const SectionCard({super.key, this.title, required this.child, this.trailing});
  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.lg),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (title != null)
            Padding(
              padding: const EdgeInsets.only(bottom: Spacing.md),
              child: Row(
                children: [
                  Expanded(child: Text(title!, style: Theme.of(context).textTheme.titleMedium)),
                  if (trailing != null) trailing!,
                ],
              ),
            ),
          child,
        ]),
      ),
    );
  }
}
