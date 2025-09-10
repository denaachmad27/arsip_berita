import 'package:flutter/material.dart';
import '../ui/theme.dart';

class PageContainer extends StatelessWidget {
  final Widget child;
  const PageContainer({super.key, required this.child});
  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: const EdgeInsets.all(Spacing.lg),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 980),
          child: child,
        ),
      ),
    );
  }
}

