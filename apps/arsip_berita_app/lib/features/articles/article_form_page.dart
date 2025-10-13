import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb, listEquals;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill_delta_from_html/flutter_quill_delta_from_html.dart';

import '../../data/local/db.dart';
import '../../services/metadata_extractor.dart';
import '../../ui/design.dart';
import '../../ui/theme.dart';
import '../../util/platform_io.dart';
import '../../widgets/page_container.dart';
import '../../widgets/section_card.dart';
import '../../widgets/tag_editor.dart';
import '../../widgets/ui_button.dart';
import '../../widgets/ui_input.dart';
import '../../widgets/ui_scaffold.dart';
import '../../widgets/ui_toast.dart';

class _ResizableImage extends StatefulWidget {
  final String imageUrl;
  final double width;

  const _ResizableImage({
    super.key,
    required this.imageUrl,
    required this.width,
  });

  @override
  State<_ResizableImage> createState() => _ResizableImageState();
}

class _ResizableImageState extends State<_ResizableImage> {
  Uint8List? _cachedBytes;
  String? _cachedUrl;

  Uint8List? _getImageBytes() {
    if (widget.imageUrl.startsWith('data:image')) {
      if (_cachedUrl == widget.imageUrl && _cachedBytes != null) {
        return _cachedBytes;
      }
      try {
        final base64String = widget.imageUrl.split(',')[1];
        final bytes = base64Decode(base64String);
        _cachedBytes = bytes;
        _cachedUrl = widget.imageUrl;
        return bytes;
      } catch (e) {
        return null;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _getImageBytes();

    if (bytes != null) {
      return Align(
        alignment: Alignment.centerLeft,
        child: SizedBox(
          width: widget.width,
          child: Image.memory(
            bytes,
            fit: BoxFit.contain,
            gaplessPlayback: true,
            errorBuilder: (context, error, stackTrace) {
              return const Icon(Icons.broken_image);
            },
          ),
        ),
      );
    }

    if (widget.imageUrl.startsWith('http')) {
      return Align(
        alignment: Alignment.centerLeft,
        child: SizedBox(
          width: widget.width,
          child: Image.network(
            widget.imageUrl,
            fit: BoxFit.contain,
            gaplessPlayback: true,
            errorBuilder: (context, error, stackTrace) {
              return const Icon(Icons.broken_image);
            },
          ),
        ),
      );
    }

    return const Icon(Icons.broken_image);
  }
}

class ImageEmbedBuilder extends EmbedBuilder {
  final ValueNotifier<Map<String, double>> imageWidthsNotifier;
  final double defaultWidth;

  ImageEmbedBuilder({
    required this.imageWidthsNotifier,
    this.defaultWidth = 320,
  });

  @override
  String get key => 'image';

  @override
  Widget build(
    BuildContext context,
    EmbedContext embedContext,
  ) {
    final embedValue = embedContext.node.value;
    String imageUrl;

    // Extract image URL from various possible formats
    final data = embedValue.data;
    if (data is String) {
      imageUrl = data;
    } else if (data is Map && data.containsKey('source')) {
      imageUrl = data['source'] as String;
    } else if (data is Map && data.containsKey('image')) {
      imageUrl = data['image'] as String;
    } else {
      return const Icon(Icons.broken_image);
    }

    return ValueListenableBuilder<Map<String, double>>(
      valueListenable: imageWidthsNotifier,
      builder: (context, imageWidths, child) {
        final width = imageWidths[imageUrl] ?? defaultWidth;

        return _ResizableImage(
          key: ValueKey('img-${imageUrl.hashCode}-$width'),
          imageUrl: imageUrl,
          width: width,
        );
      },
    );
  }
}

class ArticleFormPage extends StatefulWidget {
  final LocalDatabase db;
  final ArticleModel? article; // when set, edit mode
  const ArticleFormPage({super.key, required this.db, this.article});

  @override
  State<ArticleFormPage> createState() => _ArticleFormPageState();
}

class _ArticleFormPageState extends State<ArticleFormPage> {
  final _url = TextEditingController();
  final _title = TextEditingController();
  final _excerpt = TextEditingController();
  final _mediaName = TextEditingController();
  String _mediaType = 'online';
  String _kind = 'artikel';
  final _authorInput = TextEditingController();
  final _peopleInput = TextEditingController();
  final _orgsInput = TextEditingController();
  final _locationInput = TextEditingController();
  final _tagsInput = TextEditingController();
  final List<String> _authorTags = [];
  final List<String> _peopleTags = [];
  final List<String> _orgTags = [];
  final List<String> _locationTags = [];
  final List<String> _tags = [];
  DateTime? _date;
  bool _loading = false;
  String? _canonical;
  String? _error;
  String? _titleError;
  String? _mediaNameError;

  Uint8List? _pickedImageBytes;
  String? _pickedImageExt;
  String? _imagePath;
  bool _removeImage = false;

  late QuillController _quillController;
  final FocusNode _quillFocusNode = FocusNode();
  final ScrollController _quillScrollController = ScrollController();

  double _editorViewportHeight = 420;
  static const double _defaultImageWidth = 320;
  static const double _minImageWidth = 120;
  static const double _maxImageWidth = 800;
  final _imageWidthsNotifier = ValueNotifier<Map<String, double>>({});
  List<String> _documentImages = [];
  String? _selectedImageSrc;
  double? _activeImageWidth;

  bool _prefillInProgress = false;
  bool _hasUnsavedChanges = false;

  Map<String, double> get _imageWidths => _imageWidthsNotifier.value;

  void _updateImageWidth(String src, double width) {
    final updated = Map<String, double>.from(_imageWidths);
    updated[src] = width;
    _imageWidthsNotifier.value = updated;
  }

  void _updateImageWidths(Map<String, double> widths) {
    _imageWidthsNotifier.value = Map<String, double>.from(widths);
  }

  bool get _isEditing => widget.article != null;

  @override
  void initState() {
    super.initState();
    _quillController = QuillController.basic();
    _quillController.addListener(_handleQuillChange);

    // Track changes for unsaved changes warning
    _url.addListener(_markAsChanged);
    _title.addListener(_markAsChanged);
    _title.addListener(_clearTitleError);
    _excerpt.addListener(_markAsChanged);
    _mediaName.addListener(_markAsChanged);
    _mediaName.addListener(_clearMediaNameError);
    _authorInput.addListener(_markAsChanged);
    _peopleInput.addListener(_markAsChanged);
    _orgsInput.addListener(_markAsChanged);
    _locationInput.addListener(_markAsChanged);
    _tagsInput.addListener(_markAsChanged);

    if (_isEditing) {
      _prefillInProgress = true;
      _loadArticleForEditing();
    }
  }

  void _markAsChanged() {
    if (!_hasUnsavedChanges) {
      setState(() {
        _hasUnsavedChanges = true;
      });
    }
  }

  void _clearTitleError() {
    if (_titleError != null && _title.text.trim().isNotEmpty) {
      setState(() {
        _titleError = null;
      });
    }
  }

  void _clearMediaNameError() {
    if (_mediaNameError != null && _mediaName.text.trim().isNotEmpty) {
      setState(() {
        _mediaNameError = null;
      });
    }
  }

  @override
  void dispose() {
    _url.dispose();
    _title.dispose();
    _excerpt.dispose();
    _mediaName.dispose();
    _authorInput.dispose();
    _peopleInput.dispose();
    _orgsInput.dispose();
    _locationInput.dispose();
    _tagsInput.dispose();
    _quillController.removeListener(_handleQuillChange);
    _quillController.dispose();
    _quillFocusNode.dispose();
    _quillScrollController.dispose();
    _imageWidthsNotifier.dispose();
    super.dispose();
  }

  void _resetQuillDocument() {
    _applyDocument(Document());
  }

  Future<void> _loadHtmlIntoQuill(String rawHtml) async {
    final trimmed = rawHtml.trim();
    if (!mounted) return;
    if (trimmed.isEmpty) {
      setState(_resetQuillDocument);
      return;
    }

    final sanitized = trimmed.contains('<')
        ? trimmed
        : '<p>${htmlEscape.convert(trimmed)}</p>';
    try {
      // Use HtmlToDelta converter to properly parse HTML with formatting
      final converter = HtmlToDelta();
      final delta = converter.convert(sanitized);

      // Debug: check if delta has proper structure
      debugPrint('Loaded delta: ${delta.toJson()}');

      final document = Document.fromDelta(delta);
      final widths = _extractImageWidths(trimmed);
      setState(() {
        _applyDocument(document, widths: widths);
      });
    } catch (err) {
      debugPrint('Gagal memuat HTML ke editor: $err');
      setState(_resetQuillDocument);
    }
  }

  void _applyDocument(Document document, {Map<String, double>? widths}) {
    final images = _collectDocumentImages(document);

    final newWidths = Map<String, double>.from(widths ?? const {});
    for (final src in images) {
      newWidths.putIfAbsent(src, () => _defaultImageWidth);
    }

    _quillController.removeListener(_handleQuillChange);
    _quillController.dispose();
    _quillController = QuillController(
      document: document,
      selection: const TextSelection.collapsed(offset: 0),
    );
    _quillController.addListener(_handleQuillChange);

    _documentImages = images;
    _updateImageWidths(newWidths);

    _selectedImageSrc = images.isNotEmpty ? images.first : null;
    _activeImageWidth =
        _selectedImageSrc != null ? _imageWidths[_selectedImageSrc!] : null;
  }
  List<String> _collectDocumentImages([Document? document]) {
    final doc = document ?? _quillController.document;
    final result = <String>[];
    for (final node in doc.root.children) {
      if (node is Line) {
        result.addAll(_imagesFromLine(node));
      } else if (node is Block) {
        for (final child in node.children) {
          if (child is Line) {
            result.addAll(_imagesFromLine(child));
          }
        }
      }
    }
    return result;
  }

  Iterable<String> _imagesFromLine(Line line) sync* {
    for (final leaf in line.children) {
      if (leaf is Embed) {
        final value = leaf.value;
        // Check for both BlockEmbed and custom embed types
        if (value.type == 'image') {
          final data = value.data;
          if (data is String) {
            yield data;
          } else if (data is Map && data.containsKey('source')) {
            yield data['source'] as String;
          } else if (data is Map && data.containsKey('image')) {
            yield data['image'] as String;
          }
        }
      }
    }
  }

  void _handleQuillChange() {
    if (!mounted) return;

    // Mark as changed for unsaved warning (but don't trigger setState)
    if (!_hasUnsavedChanges) {
      _hasUnsavedChanges = true;
    }

    final images = _collectDocumentImages();

    // Only update if images actually changed (not just text edits)
    if (!listEquals(images, _documentImages)) {
      final updatedWidths = Map<String, double>.from(_imageWidths);

      for (final src in images) {
        updatedWidths.putIfAbsent(src, () => _defaultImageWidth);
      }
      final toRemove =
          updatedWidths.keys.where((src) => !images.contains(src)).toList();
      for (final src in toRemove) {
        updatedWidths.remove(src);
      }

      String? selectionImage;
      final selection = _quillController.selection;
      if (selection.isCollapsed) {
        try {
          final embed = getEmbedNode(_quillController, selection.start).value.value;
          if (embed is BlockEmbed && embed.type == BlockEmbed.imageType) {
            selectionImage = embed.data as String;
          }
        } catch (_) {
          // ignore when cursor is not on an embed
        }
      }

      var selected = selectionImage ?? _selectedImageSrc;
      if (selected != null && !images.contains(selected)) {
        selected = images.isNotEmpty ? images.first : null;
      }
      final active = selected != null ? updatedWidths[selected] : null;

      setState(() {
        _documentImages = images;
        _updateImageWidths(updatedWidths);
        _selectedImageSrc = selected;
        _activeImageWidth = active;
      });
    }
  }

  bool _documentIsEffectivelyEmpty(Document document) {
    return document.toPlainText().trim().isEmpty;
  }

  String _documentToHtml(Document document) {
    final buffer = StringBuffer();
    for (final node in document.root.children) {
      if (node is Block) {
        buffer.write(_blockToHtml(node));
      } else if (node is Line) {
        buffer.write(_lineToHtml(node));
      }
    }
    return buffer.toString();
  }

  String _blockToHtml(Block block) {
    final attrs = block.style.attributes;
    if (attrs.containsKey(Attribute.list.key)) {
      final type = attrs[Attribute.list.key]?.value?.toString();
      final tag = type == 'ordered' ? 'ol' : 'ul';
      final buffer = StringBuffer('<$tag>');
      for (final child in block.children) {
        if (child is! Line) continue;
        final content = _lineInlineHtml(child);
        buffer.write('<li>${content.isEmpty ? '<br>' : content}</li>');
      }
      buffer.write('</$tag>');
      return buffer.toString();
    }
    if (attrs.containsKey(Attribute.blockQuote.key)) {
      final content = block.children
          .whereType<Line>()
          .map(_lineInlineHtml)
          .join('<br/>');
      final body = content.isEmpty ? '&nbsp;' : content;
      return '<blockquote>$body</blockquote>';
    }
    if (attrs.containsKey(Attribute.codeBlock.key)) {
      final code = block.children.whereType<Line>().map((line) {
        final plain = line.toPlainText().replaceAll('\n', '');
        return htmlEscape.convert(plain);
      }).join('\n');
      return '<pre><code>$code</code></pre>';
    }
    final buffer = StringBuffer();
    for (final child in block.children) {
      if (child is Line) {
        buffer.write(_lineToHtml(child));
      }
    }
    return buffer.toString();
  }

  String _lineToHtml(Line line) {
    final inline = _lineInlineHtml(line);
    final attributes = <String, String>{};

    final parent = line.parent;
    if (parent is Block) {
      final blockAttrs = parent.style.attributes;
      final align = blockAttrs[Attribute.align.key]?.value;
      if (align != null) {
        attributes['text-align'] = align.toString();
      }
      final indent = blockAttrs[Attribute.indent.key]?.value;
      if (indent != null) {
        final value = int.tryParse(indent.toString()) ?? 0;
        if (value > 0) {
          attributes['margin-left'] = '${value * 24}px';
        }
      }
    }

    final lineAttrs = line.style.attributes;
    final align = lineAttrs[Attribute.align.key]?.value;
    if (align != null) {
      attributes['text-align'] = align.toString();
    }
    final indentAttr = lineAttrs[Attribute.indent.key]?.value;
    if (indentAttr != null) {
      final value = int.tryParse(indentAttr.toString()) ?? 0;
      if (value > 0) {
        attributes['margin-left'] = '${value * 24}px';
      }
    }

    final styleAttr = attributes.isEmpty
        ? ''
        : ' style="${attributes.entries.map((entry) => '${entry.key}: ${entry.value}').join('; ')}"';

    if (lineAttrs.containsKey(Attribute.header.key)) {
      final levelValue = lineAttrs[Attribute.header.key]?.value;
      var level = 1;
      if (levelValue is num) {
        level = levelValue.toInt().clamp(1, 6);
      }
      final body = inline.isEmpty ? '&nbsp;' : inline;
      return '<h$level$styleAttr>$body</h$level>';
    }

    final body = inline.isEmpty ? '&nbsp;' : inline;
    return '<p$styleAttr>$body</p>';
  }

  String _lineInlineHtml(Line line) {
    final buffer = StringBuffer();
    for (final leaf in line.children) {
      if (leaf is QuillText) {
        buffer.write(_textLeafToHtml(leaf));
      } else if (leaf is Embed) {
        buffer.write(_embedToHtml(leaf));
      }
    }
    return buffer.toString();
  }

  String _textLeafToHtml(QuillText leaf) {
    final raw = leaf.value as String? ?? '';
    if (raw.isEmpty) {
      return '';
    }
    String text = htmlEscape.convert(raw);
    final style = leaf.style.attributes;

    final linkAttr = style[Attribute.link.key];
    if (linkAttr != null && linkAttr.value != null) {
      final href = _escapeAttribute(linkAttr.value.toString());
      text = '<a href="$href">$text</a>';
    }
    if (style.containsKey(Attribute.inlineCode.key)) {
      text = '<code>$text</code>';
    }
    if (style.containsKey(Attribute.bold.key)) {
      text = '<strong>$text</strong>';
    }
    if (style.containsKey(Attribute.italic.key)) {
      text = '<em>$text</em>';
    }
    if (style.containsKey(Attribute.underline.key)) {
      text = '<u>$text</u>';
    }
    if (style.containsKey(Attribute.strikeThrough.key)) {
      text = '<s>$text</s>';
    }

    final highlightStyles = <String, String>{};
    final colorAttr = style[Attribute.color.key]?.value;
    if (colorAttr != null) {
      highlightStyles['color'] = colorAttr.toString();
    }
    final backgroundAttr = style[Attribute.background.key]?.value;
    if (backgroundAttr != null) {
      final value = backgroundAttr.toString();
      const highlightCandidates = {
        '#fff59d',
        '#fff9c4',
        '#a5d6a7',
      };
      if (highlightCandidates.contains(value.toLowerCase())) {
        text =
            '<mark data-highlight="true" style="background-color: #a5d6a7;">$text</mark>';
      } else {
        highlightStyles['background-color'] = value;
      }
    }

    // Handle font size
    final sizeAttr = style[Attribute.size.key]?.value;
    if (sizeAttr != null) {
      final sizeValue = sizeAttr.toString();
      // Map Quill size values to CSS font sizes
      if (sizeValue == 'small') {
        highlightStyles['font-size'] = '0.75em';
      } else if (sizeValue == 'large') {
        highlightStyles['font-size'] = '1.5em';
      } else if (sizeValue == 'huge') {
        highlightStyles['font-size'] = '2em';
      }
    }

    if (highlightStyles.isNotEmpty) {
      final styleString =
          highlightStyles.entries.map((e) => '${e.key}: ${e.value}').join('; ');
      text = '<span style="$styleString">$text</span>';
    }
    return text;
  }

  String _embedToHtml(Embed leaf) {
    final value = leaf.value;
    if (value.type == 'image') {
      String src;
      final data = value.data;
      if (data is String) {
        src = data;
      } else if (data is Map && data.containsKey('source')) {
        src = data['source'] as String;
      } else if (data is Map && data.containsKey('image')) {
        src = data['image'] as String;
      } else {
        return '';
      }

      final width = _imageWidths[src];
      final widthAttr =
          width != null ? ' width="${width.toStringAsFixed(0)}"' : '';
      return '<img src="${_escapeAttribute(src)}"$widthAttr />';
    }
    return '';
  }

  String _escapeAttribute(String value) {
    return value
        .replaceAll('&', '&amp;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&#39;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;');
  }

  Map<String, double> _extractImageWidths(String html) {
    final result = <String, double>{};
    final imgTagRegex = RegExp(r'<img[^>]*>', caseSensitive: false);
    final srcRegex =
        RegExp("src=['\"]([^'\"]+)['\"]", caseSensitive: false);
    final widthRegex = RegExp(
        "width=['\"]([0-9]+(?:\\.[0-9]+)?)['\"]",
        caseSensitive: false);
    for (final match in imgTagRegex.allMatches(html)) {
      final tag = match.group(0);
      if (tag == null) continue;
      final srcMatch = srcRegex.firstMatch(tag);
      final widthMatch = widthRegex.firstMatch(tag);
      if (srcMatch == null || widthMatch == null) continue;
      final src = srcMatch.group(1);
      final widthText = widthMatch.group(1);
      if (src == null || widthText == null) continue;
      final width = double.tryParse(widthText);
      if (width != null) {
        result[src] = width;
      }
    }
    return result;
  }

  Future<void> _insertImageIntoEditor() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      type: FileType.custom,
      allowedExtensions: const ['png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;

    final picked = result.files.first;
    final bytes = picked.bytes ??
        (picked.path != null ? await File(picked.path!).readAsBytes() : null);
    if (bytes == null || !mounted) return;

    final ext = (picked.extension ?? '').toLowerCase();
    final mime = _mimeFromExtension(ext);
    final dataUri = 'data:$mime;base64,${base64Encode(bytes)}';
    if (!mounted) return;
    final selection = _quillController.selection;
    final index = selection.baseOffset < 0 ? 0 : selection.baseOffset;
    _quillController.replaceText(
      index,
      0,
      BlockEmbed.image(dataUri),
      TextSelection.collapsed(offset: index + 1),
    );

    // Force update image list
    if (!mounted) return;
    final images = _collectDocumentImages();
    setState(() {
      _documentImages = images;
      _updateImageWidth(dataUri, _defaultImageWidth);
      _selectedImageSrc = dataUri;
      _activeImageWidth = _defaultImageWidth;
    });
  }

  String _mimeFromExtension(String ext) {
    switch (ext) {
      case 'png':
        return 'image/png';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      case 'bmp':
        return 'image/bmp';
      case 'svg':
        return 'image/svg+xml';
      default:
        return 'image/*';
    }
  }

  void _resizeEditorViewport(bool increase) {
    const minHeight = 320.0;
    const maxHeight = 900.0;
    final delta = increase ? 120.0 : -120.0;
    setState(() {
      _editorViewportHeight =
          (_editorViewportHeight + delta).clamp(minHeight, maxHeight);
    });
  }

  Widget _buildEditorHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Editor Konten',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          Tooltip(
            message: 'Perkecil tinggi editor',
            child: IconButton(
              icon: const Icon(Icons.unfold_less),
              onPressed: () => _resizeEditorViewport(false),
            ),
          ),
          Tooltip(
            message: 'Perbesar tinggi editor',
            child: IconButton(
              icon: const Icon(Icons.unfold_more),
              onPressed: () => _resizeEditorViewport(true),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImageWidthPanel(BuildContext context) {
    if (_documentImages.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: Text(
          'Belum ada gambar di konten. Gunakan tombol gambar pada toolbar untuk menambahkan.',
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: DS.textDim),
        ),
      );
    }
    final selected = _selectedImageSrc ?? _documentImages.first;
    final widthValue =
        (_activeImageWidth ?? _imageWidths[selected] ?? _defaultImageWidth)
            .clamp(_minImageWidth, _maxImageWidth);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: DropdownButton<String>(
                  value: selected,
                  isExpanded: true,
                  items: _documentImages
                      .asMap()
                      .entries
                      .map((entry) => DropdownMenuItem<String>(
                            value: entry.value,
                            child: Text(
                              'Gambar ${entry.key + 1}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ))
                      .toList(),
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() {
                      _selectedImageSrc = value;
                      _activeImageWidth =
                          _imageWidths[value] ?? _defaultImageWidth;
                    });
                  },
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '${widthValue.toStringAsFixed(0)} px',
                style: Theme.of(context)
                    .textTheme
                    .labelMedium
                    ?.copyWith(color: DS.textDim),
              ),
            ],
          ),
          Slider(
            value: widthValue,
            min: _minImageWidth,
            max: _maxImageWidth,
            onChanged: (value) {
              final target = _selectedImageSrc ?? selected;
              setState(() {
                _selectedImageSrc = target;
                _updateImageWidth(target, value);
                _activeImageWidth = value;
              });
            },
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () {
                final target = _selectedImageSrc ?? selected;
                setState(() {
                  _updateImageWidth(target, _defaultImageWidth);
                  _selectedImageSrc = target;
                  _activeImageWidth = _defaultImageWidth;
                });
              },
              child: const Text('Reset ke 320px'),
            ),
          ),
          Text(
            'Perubahan lebar akan terlihat pada detail artikel setelah disimpan.',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: DS.textDim),
          ),
        ],
      ),
    );
  }

  Future<void> _loadArticleForEditing() async {
    await _prefillFromArticle(widget.article!);
    if (mounted) {
      setState(() {
        _prefillInProgress = false;
      });
    }
  }

  Future<void> _prefillFromArticle(ArticleModel a) async {
    Future<String> convertLocalImagesToDataUri(String raw) async {
      String html = raw;
      try {
        final regex = RegExp(r'''<img[^>]*src=["']([^"']+|[^']+)["'][^>]*>''',
            caseSensitive: false);
        final matches = regex.allMatches(html).toList().reversed;
        for (final m in matches) {
          final src = m.group(1);
          if (src == null) continue;
          final lowered = src.toLowerCase();
          final isNetwork = lowered.startsWith('http://') ||
              lowered.startsWith('https://') ||
              lowered.startsWith('data:');
          if (isNetwork) continue;
          String pathStr = src;
          if (lowered.startsWith('file://')) {
            pathStr = src.replaceFirst(RegExp(r'^file://'), '');
          }
          try {
            final file = File(pathStr);
            if (await file.exists()) {
              final bytes = await file.readAsBytes();
              final b64 = base64Encode(bytes);
              String mime;
              final p = pathStr.toLowerCase();
              if (p.endsWith('.png')) {
                mime = 'image/png';
              } else if (p.endsWith('.jpg') || p.endsWith('.jpeg')) {
                mime = 'image/jpeg';
              } else if (p.endsWith('.gif')) {
                mime = 'image/gif';
              } else if (p.endsWith('.webp')) {
                mime = 'image/webp';
              } else if (p.endsWith('.bmp')) {
                mime = 'image/bmp';
              } else if (p.endsWith('.svg')) {
                mime = 'image/svg+xml';
              } else {
                mime = 'image/*';
              }
              final dataUri = 'data:$mime;base64,$b64';
              html = html.replaceRange(
                  m.start, m.end, m.group(0)!.replaceFirst(src, dataUri));
            } else {
              html = html.replaceRange(m.start, m.end, '');
            }
          } catch (_) {}
        }
      } catch (_) {}
      return html;
    }

    await widget.db.init();
    final article = await widget.db.getArticleById(a.id) ?? a;

    _title.text = article.title;
    _url.text = article.url;
    _canonical = article.canonicalUrl;
    _excerpt.text = article.excerpt ?? '';
    _date = article.publishedAt;
    _kind = article.kind ?? 'artikel';
    _imagePath = article.imagePath;

    if (article.mediaId != null) {
      final m = await widget.db.getMediaById(article.mediaId!);
      if (m != null) {
        _mediaName.text = m.name;
        _mediaType = m.type;
      }
    }
    final authors = await widget.db.authorsForArticle(article.id);
    final people = await widget.db.peopleForArticle(article.id);
    final orgs = await widget.db.orgsForArticle(article.id);
    final locs = await widget.db.locationsForArticle(article.id);
    setState(() {
      _authorTags
        ..clear()
        ..addAll(authors);
      _peopleTags
        ..clear()
        ..addAll(people);
      _orgTags
        ..clear()
        ..addAll(orgs);
      _locationTags
        ..clear()
        ..addAll(locs);
      _tags
        ..clear()
        ..addAll(article.tags ?? []);
    });

    // Priority 1: Load from Delta JSON (preserves newlines perfectly)
    final deltaJson = article.descriptionDelta?.trim();
    if (deltaJson != null && deltaJson.isNotEmpty) {
      try {
        final deltaData = jsonDecode(deltaJson) as List<dynamic>;
        final document = Document.fromJson(deltaData);

        // Extract image widths from the stored HTML
        final descText = article.description?.trim() ?? '';
        final widths = _extractImageWidths(descText);

        setState(() {
          _applyDocument(document, widths: widths);
        });
        debugPrint('✅ Loaded from Delta JSON successfully');
        return;
      } catch (e) {
        debugPrint('❌ Failed to load from Delta JSON: $e, falling back to HTML');
      }
    }

    // Priority 2: Fallback to HTML (for old articles without Delta)
    final descText = article.description?.trim() ?? '';
    if (descText.isNotEmpty) {
      final processed = await convertLocalImagesToDataUri(descText);
      await _loadHtmlIntoQuill(processed);
    } else {
      _resetQuillDocument();
    }
  }

  Future<void> _pickImage() async {
    setState(() {
      _error = null;
    });
    try {
      final res = await FilePicker.platform.pickFiles(
        allowMultiple: false,
        type: FileType.image,
        withData: true,
      );
      if (res == null || res.files.isEmpty) return;
      final file = res.files.single;
      setState(() {
        _pickedImageBytes = file.bytes;
        _pickedImageExt =
            (file.extension ?? '').isNotEmpty ? file.extension!.toLowerCase() : null;
        _removeImage = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
      });
    }
  }

  Future<void> _extract() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await widget.db.init();
      final svc = MetadataExtractor();
      final meta = await svc.fetch(_url.text.trim());
      if (meta != null) {
        _canonical = meta.canonicalUrl;
        if ((_title.text).isEmpty && (meta.title ?? '').isNotEmpty) {
          _title.text = meta.title!;
        }
        if ((_excerpt.text).isEmpty && (meta.excerpt ?? '').isNotEmpty) {
          _excerpt.text = meta.excerpt!;
        }
        final cand = ((meta.description ?? '').trim().isNotEmpty)
            ? meta.description!.trim()
            : (meta.excerpt ?? '').trim();
        if (cand.isNotEmpty) {
          await _loadHtmlIntoQuill(cand);
        }
      }
      if (_canonical != null) {
        final existingId =
            await widget.db.findArticleIdByCanonicalUrl(_canonical!);
        if (existingId != null &&
            (!_isEditing || existingId != widget.article!.id)) {
          _error = 'Artikel dengan canonical_url sudah ada: $_canonical';
        }
      }
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _save() async {
    try {
      setState(() {
        _loading = true;
        _error = null;
        _titleError = null;
        _mediaNameError = null;
      });

      // Validasi mandatory fields
      bool hasError = false;

      if (_title.text.trim().isEmpty) {
        setState(() {
          _titleError = 'Judul artikel wajib diisi';
        });
        hasError = true;
      }

      if (_mediaName.text.trim().isEmpty) {
        setState(() {
          _mediaNameError = 'Nama media wajib diisi';
        });
        hasError = true;
      }

      if (hasError) {
        setState(() {
          _loading = false;
        });
        throw 'Mohon lengkapi semua field yang wajib diisi';
      }

      await widget.db.init();
      String? descHtml;
      String? descDelta;
      final document = _quillController.document;
      if (!_documentIsEffectivelyEmpty(document)) {
        final html = _documentToHtml(document).trim();
        if (html.isNotEmpty) {
          descHtml = html;
          debugPrint('=== SAVING HTML ===');
          debugPrint(html);
        }
        // Save Delta JSON for accurate restore
        final delta = document.toDelta();
        descDelta = jsonEncode(delta.toJson());
        debugPrint('=== SAVING DELTA ===');
        debugPrint(descDelta);
      }

      int? mediaId;
      if (_mediaName.text.trim().isNotEmpty) {
        mediaId = await widget.db.upsertMedia(_mediaName.text.trim(), _mediaType);
      }
      final article = ArticleModel(
        id: _isEditing
            ? widget.article!.id
            : 'local-${DateTime.now().millisecondsSinceEpoch}',
        title: _title.text.trim(),
        url: _url.text.trim(),
        canonicalUrl: _canonical?.trim().isEmpty == true ? null : _canonical,
        mediaId: mediaId,
        kind: _kind,
        description: descHtml,
        descriptionDelta: descDelta,
        excerpt: _excerpt.text.trim().isEmpty ? null : _excerpt.text.trim(),
        publishedAt: _date,
        imagePath: _isEditing ? widget.article!.imagePath : null,
        tags: _tags.isEmpty ? null : _tags,
      );

      if (_pickedImageBytes != null && _pickedImageBytes!.isNotEmpty) {
        try {
          final ext = (_pickedImageExt ?? 'jpg').replaceAll('.', '');
          final savedPath =
              await saveImageForArticle(article.id, _pickedImageBytes!, ext: ext);
          if (savedPath.isEmpty && kIsWeb) {
            throw Exception('Penyimpanan gambar belum didukung di Web.');
          }
          if (savedPath.isNotEmpty) {
            article.imagePath = savedPath;
            _imagePath = savedPath;
          }
        } catch (e) {
          throw Exception('Gagal menyimpan gambar: $e');
        }
      } else if (_removeImage) {
        final old = _imagePath ?? widget.article?.imagePath;
        if (old != null && old.isNotEmpty) {
          await deleteIfExists(old);
        }
        article.imagePath = null;
        _imagePath = null;
      }

      await widget.db.upsertArticle(article);

      final authorIds = <int>[];
      for (final name in _authorTags.map((e) => e.trim()).where((e) => e.isNotEmpty)) {
        authorIds.add(await widget.db.upsertAuthorByName(name));
      }
      await widget.db.setArticleAuthors(article.id, authorIds);

      final peopleIds = <int>[];
      for (final name in _peopleTags.map((e) => e.trim()).where((e) => e.isNotEmpty)) {
        peopleIds.add(await widget.db.upsertPersonByName(name));
      }
      await widget.db.setArticlePeople(article.id, peopleIds);

      final orgIds = <int>[];
      for (final name in _orgTags.map((e) => e.trim()).where((e) => e.isNotEmpty)) {
        orgIds.add(await widget.db.upsertOrganizationByName(name));
      }
      await widget.db.setArticleOrganizations(article.id, orgIds);

      final locIds = <int>[];
      for (final name in _locationTags.map((e) => e.trim()).where((e) => e.isNotEmpty)) {
        locIds.add(await widget.db.upsertLocationByName(name));
      }
      await widget.db.setArticleLocations(article.id, locIds);

      // Mark as saved
      _hasUnsavedChanges = false;

      if (mounted) {
        UiToast.show(
          context,
          message: _isEditing
              ? 'Artikel berhasil diperbarui'
              : 'Artikel berhasil ditambahkan',
          type: ToastType.success,
        );

        // Delay to let toast show
        await Future.delayed(const Duration(milliseconds: 300));
        if (mounted) {
          Navigator.pop(context);
        }
      }
    } catch (e) {
      setState(() {
        _loading = false;
        _error = e.toString();
      });

      if (mounted) {
        // Remove "Exception: " prefix from error message
        String errorMessage = e.toString();
        if (errorMessage.startsWith('Exception: ')) {
          errorMessage = errorMessage.substring('Exception: '.length);
        }

        UiToast.show(
          context,
          message: errorMessage,
          type: ToastType.error,
          duration: const Duration(seconds: 4),
        );
      }
    }
  }

  Future<bool> _onWillPop() async {
    if (!_hasUnsavedChanges) {
      return true;
    }

    final shouldPop = await showDialog<bool>(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 76,
                  height: 76,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.warning_amber_outlined,
                    size: 36,
                    color: Color(0xFFF59E0B),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Buang Perubahan?',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: DS.text,
                      ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Anda memiliki perubahan yang belum disimpan. Apakah Anda yakin ingin keluar?',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: DS.textDim,
                      ),
                ),
                const SizedBox(height: 28),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                            side: BorderSide(color: DS.border),
                          ),
                        ),
                        child: const Text('Batal'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => Navigator.of(context).pop(true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFEF4444),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: const Text('Buang'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );

    return shouldPop ?? false;
  }

  Future<void> _pickPublishedDate(BuildContext context) async {
    FocusScope.of(context).unfocus();
    final now = DateTime.now();
    final initialDate = _date ?? now;
    final earliest = DateTime(1990);
    final adjustedInitial =
        initialDate.isBefore(earliest) ? earliest : initialDate;
    final picked = await showDatePicker(
      context: context,
      firstDate: earliest,
      lastDate: DateTime(now.year + 1, 12, 31),
      initialDate: adjustedInitial,
    );
    if (picked != null) {
      setState(() {
        _date = picked;
      });
    }
  }
  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_hasUnsavedChanges,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final shouldPop = await _onWillPop();
        if (shouldPop && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        backgroundColor: DS.bg,
        body: Stack(
        children: [
          AbsorbPointer(
            absorbing: _prefillInProgress,
            child: UiScaffold(
              title: _isEditing ? 'Edit Artikel' : 'Tambah Artikel',
              actions: [
                UiButton(
                  label: 'Simpan',
                  icon: Icons.save,
                  onPressed: _loading ? null : _save,
                ),
              ],
              child: PageContainer(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildSourceSection(),
                      const SizedBox(height: Spacing.lg),
                      _buildMediaSection(context),
                      const SizedBox(height: Spacing.lg),
                      _buildContentSection(context),
                      const SizedBox(height: Spacing.lg),
                      _buildImageSection(context),
                      const SizedBox(height: Spacing.lg),
                      _buildTagSection(context),
                      const SizedBox(height: Spacing.lg),
                      if (_canonical != null)
                        Text(
                          'Canonical URL: $_canonical',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: DS.textDim),
                        ),
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.only(top: Spacing.sm),
                          child: Text(
                            _error!,
                            style: const TextStyle(color: Colors.red),
                          ),
                        ),
                      const SizedBox(height: Spacing.xxl),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (_prefillInProgress)
            Positioned.fill(
              child: Container(
                color: Colors.black.withValues(alpha: 0.6),
                child: const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: Spacing.md),
                      Text(
                        'Memuat konten artikel...',
                        style: TextStyle(color: Colors.white, fontSize: 16),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
      ),
    );
  }

  Widget _buildSourceSection() {
    return SectionCard(
      title: 'Sumber',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          UiInput(
            controller: _url,
            hint: 'Link artikel',
            prefix: Icons.link,
            suffix: InkWell(
              onTap: _loading ? null : _extract,
              borderRadius: BorderRadius.circular(8),
              child: const Padding(
                padding: EdgeInsets.all(8),
                child: Icon(Icons.auto_fix_high),
              ),
            ),
          ),
          const SizedBox(height: Spacing.md),
          UiInput(controller: _title, hint: 'Judul', errorText: _titleError),
          const SizedBox(height: Spacing.sm),
          _KindChips(
            value: _kind,
            onChanged: (v) => setState(() => _kind = v ?? 'artikel'),
          ),
        ],
      ),
    );
  }

  Widget _buildMediaSection(BuildContext context) {
    return SectionCard(
      title: 'Media & Tanggal',
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 640;
          final children = [
            _buildLabeledField(
              context,
              'Nama Media',
              UiInput(
                controller: _mediaName,
                hint: 'Nama media',
                prefix: Icons.apartment,
                errorText: _mediaNameError,
              ),
            ),
            const SizedBox(height: Spacing.md),
            _buildLabeledField(
              context,
              'Jenis Media',
              _MediaTypeChips(
                value: _mediaType,
                onChanged: (value) => setState(() => _mediaType = value ?? 'online'),
              ),
            ),
            const SizedBox(height: Spacing.md),
            _buildLabeledField(
              context,
              'Tanggal Publikasi',
              InkWell(
                onTap: () => _pickPublishedDate(context),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  decoration: BoxDecoration(
                    color: DS.surface,
                    borderRadius: DS.br,
                    border: Border.all(color: DS.border),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_today, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _date == null
                              ? 'Pilih tanggal'
                              : '${_date!.day.toString().padLeft(2, '0')}/${_date!.month.toString().padLeft(2, '0')}/${_date!.year}',
                        ),
                      ),
                      if (_date != null)
                        InkWell(
                          onTap: () => setState(() => _date = null),
                          borderRadius: BorderRadius.circular(10),
                          child: const Padding(
                            padding: EdgeInsets.all(4),
                            child: Icon(Icons.close, size: 18),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ];

          if (isWide) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: Column(children: children.sublist(0, 2))),
                const SizedBox(width: Spacing.lg),
                Expanded(child: Column(children: children.sublist(2))),
              ],
            );
          }

          return Column(children: children);
        },
      ),
    );
  }

  Widget _buildContentSection(BuildContext context) {
    return SectionCard(
      title: 'Konten',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            decoration: BoxDecoration(
              color: DS.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: DS.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildEditorHeader(context),
                Divider(height: 1, thickness: 1, color: DS.border),
                _buildCompactToolbar(context),
                Divider(height: 1, thickness: 1, color: DS.border),
                _buildImageWidthPanel(context),
                Divider(height: 1, thickness: 1, color: DS.border),
                SizedBox(
                  height: _editorViewportHeight,
                  child: Stack(
                    children: [
                      QuillEditor(
                        controller: _quillController,
                        focusNode: _quillFocusNode,
                        scrollController: _quillScrollController,
                        config: QuillEditorConfig(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                          placeholder: 'Tulis konten artikel di sini...',
                          embedBuilders: [
                            ImageEmbedBuilder(
                              imageWidthsNotifier: _imageWidthsNotifier,
                              defaultWidth: _defaultImageWidth,
                            ),
                          ],
                        ),
                      ),
                      _CustomSelectionToolbar(
                        controller: _quillController,
                        scrollController: _quillScrollController,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactToolbar(BuildContext context) {
    return _CompactQuillToolbar(
      controller: _quillController,
      onInsertImage: _insertImageIntoEditor,
    );
  }

  Widget _buildImageSection(BuildContext context) {
    return SectionCard(
      title: 'Gambar Sampul',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              UiButton(
                label: 'Pilih Gambar',
                icon: Icons.image,
                onPressed: _pickImage,
              ),
              const SizedBox(width: Spacing.sm),
              if ((_pickedImageBytes != null && _pickedImageBytes!.isNotEmpty) ||
                  ((_imagePath ?? '').isNotEmpty))
                UiButton(
                  label: 'Hapus',
                  icon: Icons.delete,
                  primary: false,
                  onPressed: () {
                    setState(() {
                      _pickedImageBytes = null;
                      _pickedImageExt = null;
                      _removeImage = true;
                    });
                  },
                ),
            ],
          ),
          const SizedBox(height: Spacing.md),
          if (_pickedImageBytes != null && _pickedImageBytes!.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.memory(
                _pickedImageBytes!,
                height: 200,
                fit: BoxFit.cover,
              ),
            )
          else if ((_imagePath ?? '').isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: imageFromPath(
                _imagePath!,
                height: 200,
                width: double.infinity,
                fit: BoxFit.cover,
              ),
            )
          else
            Text(
              'Belum ada gambar sampul',
              style:
                  Theme.of(context).textTheme.bodySmall?.copyWith(color: DS.textDim),
            ),
        ],
      ),
    );
  }

  Widget _buildTagSection(BuildContext context) {
    return SectionCard(
      title: 'Tag',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TagEditor(
            label: 'Tags',
            controller: _tagsInput,
            tags: _tags,
            onAdded: (v) => setState(() => _tags.add(v)),
            onRemoved: (v) => setState(() => _tags.remove(v)),
          ),
          const SizedBox(height: Spacing.md),
          TagEditor(
            label: 'Lokasi',
            controller: _locationInput,
            tags: _locationTags,
            onAdded: (v) => setState(() => _locationTags.add(v)),
            onRemoved: (v) => setState(() => _locationTags.remove(v)),
            suggestionFetcher: (text) async {
              await widget.db.init();
              return widget.db.suggestLocations(text);
            },
          ),
          const SizedBox(height: Spacing.md),
          TagEditor(
            label: 'Penulis',
            controller: _authorInput,
            tags: _authorTags,
            onAdded: (v) => setState(() => _authorTags.add(v)),
            onRemoved: (v) => setState(() => _authorTags.remove(v)),
            suggestionFetcher: (text) async {
              await widget.db.init();
              return widget.db.suggestAuthors(text);
            },
          ),
          const SizedBox(height: Spacing.md),
          TagEditor(
            label: 'Tokoh',
            controller: _peopleInput,
            tags: _peopleTags,
            onAdded: (v) => setState(() => _peopleTags.add(v)),
            onRemoved: (v) => setState(() => _peopleTags.remove(v)),
            suggestionFetcher: (text) async {
              await widget.db.init();
              return widget.db.suggestPeople(text);
            },
          ),
          const SizedBox(height: Spacing.md),
          TagEditor(
            label: 'Organisasi',
            controller: _orgsInput,
            tags: _orgTags,
            onAdded: (v) => setState(() => _orgTags.add(v)),
            onRemoved: (v) => setState(() => _orgTags.remove(v)),
            suggestionFetcher: (text) async {
              await widget.db.init();
              return widget.db.suggestOrganizations(text);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildLabeledField(BuildContext context, String label, Widget child) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: Spacing.xs),
        child,
      ],
    );
  }
}

class _MediaTypeChips extends StatelessWidget {
  final String value;
  final ValueChanged<String?> onChanged;
  const _MediaTypeChips({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    const types = [
      ('online', 'Online'),
      ('print', 'Cetak'),
      ('tv', 'TV'),
      ('radio', 'Radio'),
      ('social', 'Sosial'),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final t in types) ...[
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: InkWell(
                onTap: () => onChanged(t.$1),
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: value == t.$1
                        ? ((t.$1 == 'online' || t.$1 == 'tv')
                            ? DS.accentLite
                            : DS.accent2Lite)
                        : DS.surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: DS.border),
                  ),
                  child: Text(
                    t.$2,
                    style: TextStyle(
                      color: value == t.$1
                          ? ((t.$1 == 'online' || t.$1 == 'tv') ? DS.accent : DS.accent2)
                          : DS.text,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _KindChips extends StatelessWidget {
  final String value;
  final ValueChanged<String?> onChanged;
  const _KindChips({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    const kinds = [
      ('artikel', 'Artikel'),
      ('opini', 'Opini'),
    ];
    return Row(
      children: [
        for (final k in kinds) ...[
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: InkWell(
              onTap: () => onChanged(k.$1),
              borderRadius: BorderRadius.circular(20),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: value == k.$1 ? DS.accentLite : DS.surface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: DS.border),
                ),
                child: Text(
                  k.$2,
                  style: TextStyle(color: value == k.$1 ? DS.accent : DS.text),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _CompactQuillToolbar extends StatefulWidget {
  final QuillController controller;
  final VoidCallback onInsertImage;

  const _CompactQuillToolbar({
    required this.controller,
    required this.onInsertImage,
  });

  @override
  State<_CompactQuillToolbar> createState() => _CompactQuillToolbarState();
}

class _CompactQuillToolbarState extends State<_CompactQuillToolbar> {
  bool _showAll = false;

  Widget _buildToolbarButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
    bool? isActive,
    Color? activeColor,
  }) {
    return Tooltip(
      message: tooltip,
      child: IconButton(
        icon: Icon(icon, size: 20),
        onPressed: onPressed,
        color: isActive == true ? (activeColor ?? DS.accent) : DS.text,
        iconSize: 20,
        padding: const EdgeInsets.all(4),
        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      ),
    );
  }

  Widget _buildAttributeButton({
    required Attribute attribute,
    required IconData icon,
    required String tooltip,
  }) {
    final isActive = widget.controller.getSelectionStyle().containsKey(attribute.key);
    return _buildToolbarButton(
      icon: icon,
      tooltip: tooltip,
      isActive: isActive,
      onPressed: () {
        widget.controller.formatSelection(
          isActive ? Attribute.clone(attribute, null) : attribute,
        );
        setState(() {}); // Rebuild to update button state
      },
    );
  }

  void _applyTextColor(String color) {
    widget.controller.formatSelection(ColorAttribute(color));
    setState(() {});
  }

  void _applyBackgroundColor(String color) {
    widget.controller.formatSelection(BackgroundAttribute(color));
    setState(() {});
  }

  void _applyFontSize(String size) {
    widget.controller.formatSelection(SizeAttribute(size));
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final row1Buttons = [
      _buildAttributeButton(
        attribute: Attribute.bold,
        icon: Icons.format_bold,
        tooltip: 'Bold',
      ),
      _buildAttributeButton(
        attribute: Attribute.italic,
        icon: Icons.format_italic,
        tooltip: 'Italic',
      ),
      _buildAttributeButton(
        attribute: Attribute.underline,
        icon: Icons.format_underlined,
        tooltip: 'Underline',
      ),
      _buildAttributeButton(
        attribute: Attribute.strikeThrough,
        icon: Icons.strikethrough_s,
        tooltip: 'Strikethrough',
      ),
      _buildToolbarButton(
        icon: Icons.image_outlined,
        tooltip: 'Sisipkan gambar',
        onPressed: widget.onInsertImage,
      ),
      PopupMenuButton<String>(
        tooltip: 'Warna Teks',
        icon: const Icon(Icons.format_color_text, size: 20),
        iconSize: 20,
        padding: const EdgeInsets.all(4),
        onSelected: _applyTextColor,
        itemBuilder: (context) => [
          const PopupMenuItem(value: '#000000', child: Row(children: [Icon(Icons.circle, color: Color(0xFF000000), size: 16), SizedBox(width: 8), Text('Hitam')])),
          const PopupMenuItem(value: '#ff0000', child: Row(children: [Icon(Icons.circle, color: Color(0xFFFF0000), size: 16), SizedBox(width: 8), Text('Merah')])),
          const PopupMenuItem(value: '#0000ff', child: Row(children: [Icon(Icons.circle, color: Color(0xFF0000FF), size: 16), SizedBox(width: 8), Text('Biru')])),
          const PopupMenuItem(value: '#008000', child: Row(children: [Icon(Icons.circle, color: Color(0xFF008000), size: 16), SizedBox(width: 8), Text('Hijau')])),
          const PopupMenuItem(value: '#ff8c00', child: Row(children: [Icon(Icons.circle, color: Color(0xFFFF8C00), size: 16), SizedBox(width: 8), Text('Orange')])),
          const PopupMenuItem(value: '#800080', child: Row(children: [Icon(Icons.circle, color: Color(0xFF800080), size: 16), SizedBox(width: 8), Text('Ungu')])),
        ],
      ),
      PopupMenuButton<String>(
        tooltip: 'Highlight / Latar Belakang',
        icon: const Icon(Icons.format_color_fill, size: 20),
        iconSize: 20,
        padding: const EdgeInsets.all(4),
        onSelected: _applyBackgroundColor,
        itemBuilder: (context) => [
          const PopupMenuItem(value: '#fff59d', child: Row(children: [Icon(Icons.circle, color: Color(0xFFFFF59D), size: 16), SizedBox(width: 8), Text('Kuning')])),
          const PopupMenuItem(value: '#a5d6a7', child: Row(children: [Icon(Icons.circle, color: Color(0xFFA5D6A7), size: 16), SizedBox(width: 8), Text('Hijau Muda')])),
          const PopupMenuItem(value: '#ffccbc', child: Row(children: [Icon(Icons.circle, color: Color(0xFFFFCCBC), size: 16), SizedBox(width: 8), Text('Orange Muda')])),
          const PopupMenuItem(value: '#b3e5fc', child: Row(children: [Icon(Icons.circle, color: Color(0xFFB3E5FC), size: 16), SizedBox(width: 8), Text('Biru Muda')])),
          const PopupMenuItem(value: '#f8bbd0', child: Row(children: [Icon(Icons.circle, color: Color(0xFFF8BBD0), size: 16), SizedBox(width: 8), Text('Pink Muda')])),
        ],
      ),
      PopupMenuButton<String>(
        tooltip: 'Ukuran Font',
        icon: const Icon(Icons.format_size, size: 20),
        iconSize: 20,
        padding: const EdgeInsets.all(4),
        onSelected: _applyFontSize,
        itemBuilder: (context) => [
          const PopupMenuItem(value: 'small', child: Text('Kecil', style: TextStyle(fontSize: 12))),
          const PopupMenuItem(value: 'large', child: Text('Sedang', style: TextStyle(fontSize: 16))),
          const PopupMenuItem(value: 'huge', child: Text('Besar', style: TextStyle(fontSize: 20))),
        ],
      ),
    ];

    final row2Buttons = [
      _buildToolbarButton(
        icon: Icons.undo,
        tooltip: 'Undo',
        onPressed: () {
          widget.controller.undo();
          setState(() {}); // Rebuild to update button states
        },
      ),
      _buildToolbarButton(
        icon: Icons.redo,
        tooltip: 'Redo',
        onPressed: () {
          widget.controller.redo();
          setState(() {}); // Rebuild to update button states
        },
      ),
      _buildAttributeButton(
        attribute: Attribute.ul,
        icon: Icons.format_list_bulleted,
        tooltip: 'Bullet List',
      ),
      _buildAttributeButton(
        attribute: Attribute.ol,
        icon: Icons.format_list_numbered,
        tooltip: 'Numbered List',
      ),
      _buildToolbarButton(
        icon: _showAll ? Icons.expand_less : Icons.expand_more,
        tooltip: _showAll ? 'Sembunyikan' : 'Tampilkan semua',
        onPressed: () => setState(() => _showAll = !_showAll),
      ),
    ];

    final additionalButtons = _showAll
        ? [
            _buildAttributeButton(
              attribute: Attribute.h1,
              icon: Icons.looks_one,
              tooltip: 'Heading 1',
            ),
            _buildAttributeButton(
              attribute: Attribute.h2,
              icon: Icons.looks_two,
              tooltip: 'Heading 2',
            ),
            _buildAttributeButton(
              attribute: Attribute.h3,
              icon: Icons.looks_3,
              tooltip: 'Heading 3',
            ),
            _buildAttributeButton(
              attribute: Attribute.inlineCode,
              icon: Icons.code,
              tooltip: 'Inline Code',
            ),
            _buildAttributeButton(
              attribute: Attribute.blockQuote,
              icon: Icons.format_quote,
              tooltip: 'Block Quote',
            ),
            _buildAttributeButton(
              attribute: Attribute.codeBlock,
              icon: Icons.code_rounded,
              tooltip: 'Code Block',
            ),
            _buildAttributeButton(
              attribute: Attribute.leftAlignment,
              icon: Icons.format_align_left,
              tooltip: 'Align Left',
            ),
            _buildAttributeButton(
              attribute: Attribute.centerAlignment,
              icon: Icons.format_align_center,
              tooltip: 'Align Center',
            ),
            _buildAttributeButton(
              attribute: Attribute.rightAlignment,
              icon: Icons.format_align_right,
              tooltip: 'Align Right',
            ),
            _buildAttributeButton(
              attribute: Attribute.justifyAlignment,
              icon: Icons.format_align_justify,
              tooltip: 'Justify',
            ),
          ]
        : <Widget>[];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: row1Buttons,
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: row2Buttons,
          ),
          if (_showAll && additionalButtons.isNotEmpty) ...[
            const SizedBox(height: 4),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: additionalButtons,
            ),
          ],
        ],
      ),
    );
  }
}


class _CustomSelectionToolbar extends StatefulWidget {
  final QuillController controller;
  final ScrollController scrollController;

  const _CustomSelectionToolbar({
    required this.controller,
    required this.scrollController,
  });

  @override
  State<_CustomSelectionToolbar> createState() => _CustomSelectionToolbarState();
}

class _CustomSelectionToolbarState extends State<_CustomSelectionToolbar> {
  bool _isToolbarVisible = true;
  Offset _toolbarPosition = Offset.zero;
  bool _isDragging = false;

  @override
  void initState() {
    super.initState();
    widget.scrollController.addListener(_updateToolbarPosition);
    widget.controller.addListener(_updateToolbarPosition);
  }

  @override
  void dispose() {
    widget.scrollController.removeListener(_updateToolbarPosition);
    widget.controller.removeListener(_updateToolbarPosition);
    super.dispose();
  }

  void _updateToolbarPosition() {
    if (!mounted) return;

    final selection = widget.controller.selection;
    if (selection.isCollapsed) {
      if (!_isToolbarVisible) {
        setState(() {
          _isToolbarVisible = true;
          _toolbarPosition = Offset.zero;
        });
      }
      return;
    }

    // Cek apakah toolbar masih visible dalam viewport
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      try {
        // Get render box untuk menghitung posisi selection
        final renderBox = context.findRenderObject() as RenderBox?;
        if (renderBox != null && renderBox.hasSize) {
          final scrollOffset = widget.scrollController.offset;

          // Estimasi posisi selection berdasarkan scroll offset
          // Jika scroll lebih dari 100px, anggap toolbar keluar dari view
          final isOutOfView = scrollOffset > 100;

          if (isOutOfView != !_isToolbarVisible) {
            setState(() {
              _isToolbarVisible = !isOutOfView;
              if (!isOutOfView) {
                _toolbarPosition = Offset.zero;
              }
            });
          }
        }
      } catch (e) {
        // Ignore error saat context belum ready
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final selection = widget.controller.selection;
    final hasSelection = !selection.isCollapsed;

    if (!hasSelection) {
      return const SizedBox.shrink();
    }

    // Gunakan Stack dengan positioning absolut untuk drag bebas
    return Positioned.fill(
      child: Stack(
        children: [
          Positioned(
            left: _toolbarPosition.dx,
            top: _isToolbarVisible
                ? null
                : 8 + _toolbarPosition.dy,
            bottom: _isToolbarVisible
                ? 60 + _toolbarPosition.dy
                : null,
            child: _buildToolbarContent(context),
          ),
        ],
      ),
    );
  }

  Widget _buildToolbarContent(BuildContext context) {
    return Draggable<int>(
      feedback: Material(
        elevation: 8,
        borderRadius: BorderRadius.circular(8),
        color: Colors.white,
        child: Opacity(
          opacity: 0.9,
          child: _buildToolbarUI(context),
        ),
      ),
      childWhenDragging: Opacity(
        opacity: 0.3,
        child: _buildToolbarUI(context),
      ),
      onDragStarted: () {
        setState(() {
          _isDragging = true;
        });
      },
      onDragEnd: (details) {
        setState(() {
          _isDragging = false;
          // Update posisi toolbar ke posisi akhir drag
          final renderBox = context.findRenderObject() as RenderBox?;
          if (renderBox != null) {
            final localPosition = renderBox.globalToLocal(details.offset);
            _toolbarPosition = localPosition;
          }
        });
      },
      child: _buildToolbarUI(context),
    );
  }

  Widget _buildToolbarUI(BuildContext context) {
    return Material(
      elevation: _isDragging ? 8 : 4,
      borderRadius: BorderRadius.circular(8),
      color: Colors.white,
      child: IntrinsicWidth(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(top: 6, bottom: 2),
              decoration: BoxDecoration(
                color: Colors.grey.shade400,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildButton(context, label: 'B', attribute: Attribute.bold),
                  const SizedBox(width: 8),
                  _buildButton(context, label: 'I', attribute: Attribute.italic),
                  const SizedBox(width: 8),
                  _buildButton(context, label: 'U', attribute: Attribute.underline),
                  const SizedBox(width: 8),
                  _buildButton(context, label: 'S', attribute: Attribute.strikeThrough),
                  Container(
                    width: 1,
                    height: 24,
                    margin: const EdgeInsets.symmetric(horizontal: 8),
                    color: Colors.grey.shade300,
                  ),
                  _buildIconButton(context, Icons.undo, 'Undo', _handleUndo),
                  const SizedBox(width: 8),
                  _buildIconButton(context, Icons.redo, 'Redo', _handleRedo),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildButton(BuildContext context, {required String label, required Attribute attribute}) {
    final style = widget.controller.getSelectionStyle();
    final isActive = style.containsKey(attribute.key);

    // Tentukan style visual berdasarkan tipe attribute
    TextStyle textStyle;
    if (attribute == Attribute.bold) {
      textStyle = TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w900,
        color: isActive ? Colors.blue.shade700 : Colors.black87,
      );
    } else if (attribute == Attribute.italic) {
      textStyle = TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        fontStyle: FontStyle.italic,
        color: isActive ? Colors.blue.shade700 : Colors.black87,
      );
    } else if (attribute == Attribute.underline) {
      textStyle = TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        decoration: TextDecoration.underline,
        color: isActive ? Colors.blue.shade700 : Colors.black87,
      );
    } else if (attribute == Attribute.strikeThrough) {
      textStyle = TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        decoration: TextDecoration.lineThrough,
        color: isActive ? Colors.blue.shade700 : Colors.black87,
      );
    } else {
      textStyle = TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: isActive ? Colors.blue.shade700 : Colors.black87,
      );
    }

    return InkWell(
      onTap: () => widget.controller.formatSelection(isActive ? Attribute.clone(attribute, null) : attribute),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? Colors.blue.shade100 : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(label, style: textStyle),
      ),
    );
  }

  Widget _buildIconButton(BuildContext context, IconData icon, String tooltip, VoidCallback onTap) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(icon, size: 20, color: Colors.black87),
        ),
      ),
    );
  }

  void _handleUndo() {
    widget.controller.undo();
  }

  void _handleRedo() {
    widget.controller.redo();
  }
}
