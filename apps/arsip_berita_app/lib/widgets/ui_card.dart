import 'package:flutter/material.dart';
import '../ui/design.dart';

class UiCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  const UiCard({super.key, required this.child, this.padding = const EdgeInsets.all(16)});
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(color: DS.surface, borderRadius: DS.br, border: Border.all(color: DS.border)),
      child: Padding(padding: padding, child: child),
    );
  }
}

