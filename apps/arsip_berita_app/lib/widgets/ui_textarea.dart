import 'package:flutter/material.dart';
import '../ui/design.dart';

class UiTextArea extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final int minLines;
  final int maxLines;
  const UiTextArea({super.key, required this.controller, required this.hint, this.minLines = 4, this.maxLines = 8});
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: DS.surface,
        borderRadius: DS.br,
        border: Border.all(color: DS.border),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: TextField(
        controller: controller,
        minLines: minLines,
        maxLines: maxLines,
        decoration: InputDecoration.collapsed(hintText: hint, hintStyle: TextStyle(color: DS.textDim)),
      ),
    );
  }
}

