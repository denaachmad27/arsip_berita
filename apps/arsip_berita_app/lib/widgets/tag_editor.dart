import 'package:flutter/material.dart';
import '../ui/theme.dart';
import '../ui/design.dart';
import 'ui_input.dart';
import 'ui_button.dart';
import 'ui_chip.dart';

class TagEditor extends StatefulWidget {
  final String label;
  final TextEditingController controller;
  final List<String> tags;
  final void Function(String value) onAdded;
  final void Function(String value) onRemoved;
  final Future<List<String>> Function(String prefix)? suggestionFetcher;
  final String? errorText;
  const TagEditor({super.key, required this.label, required this.controller, required this.tags, required this.onAdded, required this.onRemoved, this.suggestionFetcher, this.errorText});
  @override
  State<TagEditor> createState() => _TagEditorState();
}

class _TagEditorState extends State<TagEditor> {
  List<String> _suggestions = const [];
  bool _loading = false;
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
  }
  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    super.dispose();
  }
  void _onChanged() async {
    final fetcher = widget.suggestionFetcher;
    final text = widget.controller.text.trim();
    if (fetcher == null || text.isEmpty) {
      if (_suggestions.isNotEmpty) setState(() => _suggestions = const []);
      return;
    }
    setState(() => _loading = true);
    final list = await fetcher(text);
    if (mounted) setState(() { _suggestions = list.where((s) => !widget.tags.contains(s)).toList(); _loading = false; });
  }
  @override
  Widget build(BuildContext context) {
    final hasError = widget.errorText != null && widget.errorText!.isNotEmpty;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: UiInput(controller: widget.controller, hint: widget.label, errorText: hasError && widget.tags.isEmpty ? widget.errorText : null)),
        const SizedBox(width: Spacing.sm),
        UiButton(label: 'Tambah', icon: Icons.add, onPressed: () { final v = widget.controller.text.trim(); if (v.isNotEmpty && !widget.tags.contains(v)) { widget.onAdded(v); widget.controller.clear(); } }, color: DS.accent2),
      ]),
      const SizedBox(height: Spacing.sm),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final t in widget.tags)
          Row(mainAxisSize: MainAxisSize.min, children: [
            UiChip(label: t, selected: true, activeColor: DS.accent2, onTap: null),
            const SizedBox(width: 4),
            InkWell(onTap: () => widget.onRemoved(t), borderRadius: BorderRadius.circular(10), child: Padding(padding: const EdgeInsets.all(4), child: Icon(Icons.close, size: 16, color: DS.textDim))),
          ]),
      ]),
      if (_loading && _suggestions.isEmpty) const Padding(padding: EdgeInsets.only(top: Spacing.xs), child: LinearProgressIndicator(minHeight: 2)),
      if (_suggestions.isNotEmpty) ...[
        const SizedBox(height: Spacing.xs),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final s in _suggestions)
            UiChip(label: s, selected: true, activeColor: DS.accent2, onTap: () { widget.onAdded(s); widget.controller.clear(); setState(() => _suggestions = const []); }),
        ]),
      ],
    ]);
  }
}
