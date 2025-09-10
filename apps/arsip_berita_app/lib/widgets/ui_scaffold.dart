import 'package:flutter/material.dart';
import '../ui/design.dart';

class UiScaffold extends StatelessWidget {
  final String title;
  final List<Widget> actions;
  final Widget child;
  const UiScaffold({super.key, required this.title, required this.actions, required this.child});
  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(color: DS.bg, border: Border(bottom: BorderSide(color: DS.border))),
          child: Row(children: [
            Text(title, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20, color: DS.text)),
            const Spacer(),
            ...actions,
          ]),
        ),
        Expanded(child: child),
      ]),
    );
  }
}
