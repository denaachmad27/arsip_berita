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
  final String? errorText;
  const UiInput({super.key, required this.controller, required this.hint, this.prefix, this.suffix, this.onSubmitted, this.onChanged, this.contentPadding, this.errorText});
  @override
  Widget build(BuildContext context) {
    final hasError = errorText != null && errorText!.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          decoration: BoxDecoration(
            color: DS.surface,
            borderRadius: DS.br,
            border: Border.all(color: hasError ? const Color(0xFFEF4444) : DS.border),
          ),
          padding: contentPadding ?? const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(children: [
            if (prefix != null) ...[
              Icon(prefix, color: hasError ? const Color(0xFFEF4444) : DS.textDim), const SizedBox(width: 8),
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
        ),
        if (hasError) ...[
          const SizedBox(height: 6),
          Row(
            children: [
              const Icon(Icons.error_outline, size: 14, color: Color(0xFFEF4444)),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  errorText!,
                  style: const TextStyle(fontSize: 12, color: Color(0xFFEF4444)),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
