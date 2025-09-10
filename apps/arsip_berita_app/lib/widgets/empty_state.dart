import 'package:flutter/material.dart';
import '../ui/theme.dart';

class EmptyState extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget? action;
  const EmptyState({super.key, required this.title, required this.subtitle, this.action});
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.xl),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.library_books_outlined, size: 64, color: Colors.grey),
            const SizedBox(height: Spacing.md),
            Text(title, style: Theme.of(context).textTheme.titleLarge, textAlign: TextAlign.center),
            const SizedBox(height: Spacing.sm),
            Text(subtitle, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey[700]), textAlign: TextAlign.center),
            if (action != null) ...[
              const SizedBox(height: Spacing.lg),
              action!,
            ]
          ]),
        ),
      ),
    );
  }
}

