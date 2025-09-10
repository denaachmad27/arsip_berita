import 'package:flutter/material.dart';
import '../ui/design.dart';

class UiInput extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final IconData? prefix;
  final Widget? suffix;
  final void Function(String value)? onSubmitted;
  final void Function(String value)? onChanged;
  final EdgeInsetsGeometry? contentPadding;
  const UiInput({super.key, required this.controller, required this.hint, this.prefix, this.suffix, this.onSubmitted, this.onChanged, this.contentPadding});
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: DS.surface,
        borderRadius: DS.br,
        border: Border.all(color: DS.border),
      ),
      padding: contentPadding ?? const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(children: [
        if (prefix != null) ...[
          Icon(prefix, color: DS.textDim), const SizedBox(width: 8),
        ],
        Expanded(
          child: TextField(
            controller: controller,
            decoration: InputDecoration.collapsed(hintText: hint, hintStyle: TextStyle(color: DS.textDim)),
            onSubmitted: onSubmitted,
            onChanged: onChanged,
          ),
        ),
        if (suffix != null) suffix!,
      ]),
    );
  }
}
