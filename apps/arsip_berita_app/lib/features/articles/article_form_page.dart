import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb;
import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import '../../util/platform_io.dart';
import '../../data/local/db.dart';
import '../../services/metadata_extractor.dart';
import '../../ui/theme.dart';
import '../../widgets/page_container.dart';
import '../../widgets/section_card.dart';
import '../../widgets/tag_editor.dart';
import '../../ui/design.dart';
import '../../widgets/ui_input.dart';
import '../../widgets/ui_button.dart';
import '../../widgets/ui_textarea.dart';
import '../../widgets/ui_scaffold.dart';
import 'package:super_editor/super_editor.dart';
import 'package:super_editor_markdown/super_editor_markdown.dart';
import 'package:html2md/html2md.dart' as html2md;
import 'package:markdown/markdown.dart' as md;

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
  final _desc = TextEditingController();
  final _excerpt = TextEditingController();
  final _mediaName = TextEditingController();
  String _mediaType = 'online';
  String _kind = 'artikel';
  final _authorInput = TextEditingController();
  final _peopleInput = TextEditingController();
  final _orgsInput = TextEditingController();
  final _locationInput = TextEditingController();
  final List<String> _authorTags = [];
  final List<String> _peopleTags = [];
  final List<String> _orgTags = [];
  final List<String> _locationTags = [];
  DateTime? _date;
  bool _loading = false;
  String? _canonical;
  String? _error;
  // image state
  Uint8List? _pickedImageBytes;
  String? _pickedImageExt;
  String? _imagePath; // existing image path (when editing)
  bool _removeImage = false;
  MutableDocument _descDocument = _emptyDocument();
  MutableDocumentComposer _descComposer = MutableDocumentComposer();
  late Editor _descEditor = createDefaultDocumentEditor(
      document: _descDocument, composer: _descComposer);
  final FocusNode _descEditorFocusNode = FocusNode();
  final ScrollController _descScrollController = ScrollController();
  final GlobalKey _descLayoutKey = GlobalKey();
  CommonEditorOperations? _commonEditorOps;
  double _editorViewportHeight = 360;
  static const double _defaultImageWidth = 320;
  static const double _minImageWidth = 120;
  static const double _maxImageWidth = 800;
  final Map<String, double> _imageWidths = {};
  String? _selectedImageNodeId;
  double? _activeImageWidth;
  late final VoidCallback _selectionListener;
  bool _prefillInProgress = false;

  bool get _isEditing => widget.article != null;

  static MutableDocument _emptyDocument() => MutableDocument(nodes: [
        ParagraphNode(id: Editor.createNodeId(), text: AttributedText()),
      ]);

  DocumentLayout _resolveDocumentLayout() {
    final layoutState = _descLayoutKey.currentState;
    if (layoutState == null) {
      throw StateError('Editor layout is not available yet');
    }
    if (layoutState is! DocumentLayout) {
      throw StateError('Editor layout key is not bound to a DocumentLayout');
    }
    return layoutState as DocumentLayout;
  }

  CommonEditorOperations get _editorOps =>
      _commonEditorOps ??= CommonEditorOperations(
        document: _descDocument,
        editor: _descEditor,
        composer: _descComposer,
        documentLayoutResolver: _resolveDocumentLayout,
      );

  void _invalidateEditorOps() {
    _commonEditorOps = null;
  }

  void _replaceDocument(MutableDocument document) {
    _descComposer.selectionNotifier.removeListener(_selectionListener);
    _descComposer.dispose();
    _descDocument = document;
    _descComposer = MutableDocumentComposer();
    _descComposer.selectionNotifier.addListener(_selectionListener);
    _imageWidths.clear();
    _selectedImageNodeId = null;
    _activeImageWidth = null;
    _populateImageWidthCache();
    _descEditor = createDefaultDocumentEditor(
        document: _descDocument, composer: _descComposer);
    _invalidateEditorOps();
  }

  void _resetEditorDocument() {
    _replaceDocument(_emptyDocument());
    _desc.text = '';
  }

  Future<void> _loadHtmlIntoEditor(String html) async {
    final trimmed = html.trim();
    if (!mounted) {
      return;
    }
    if (trimmed.isEmpty) {
      setState(_resetEditorDocument);
      return;
    }
    try {
      final imageWidths = _extractImageWidths(trimmed);
      final markdown = html2md.convert(trimmed);
      final doc = deserializeMarkdownToDocument(markdown,
          syntax: MarkdownSyntax.superEditor);
      _replaceDocument(doc);
      if (imageWidths.isNotEmpty) {
        for (var i = 0; i < _descDocument.nodeCount; i++) {
          final node = _descDocument.getNodeAt(i);
          if (node is ImageNode) {
            final width = imageWidths[node.imageUrl];
            if (width != null) {
              _applyWidthToImageNode(node.id, width);
            }
          }
        }
      }
      setState(() {});
      _desc.text = trimmed;
    } catch (err) {
      debugPrint('Gagal memuat HTML ke editor: ' + err.toString());
      setState(_resetEditorDocument);
      _desc.text = trimmed;
    }
  }

  String? _editorHtml() {
    if (_descDocument.nodeCount == 0) {
      return null;
    }
    if (_descDocument.nodeCount == 1) {
      final node = _descDocument.getNodeAt(0);
      if (node is ParagraphNode && node.text.toPlainText().trim().isEmpty) {
        return null;
      }
    }
    final markdown = serializeDocumentToMarkdown(_descDocument,
        syntax: MarkdownSyntax.superEditor);
    if (markdown.trim().isEmpty) {
      return null;
    }
    var html = md.markdownToHtml(
      markdown,
      extensionSet: md.ExtensionSet.gitHubWeb,
    );
    html = _injectImageWidthsIntoHtml(html);
    return html;
  }

  void _populateImageWidthCache() {
    for (final node in _descDocument) {
      if (node is ImageNode) {
        final width = node.getMetadataValue('width');
        if (width is num) {
          _imageWidths[node.id] = width.toDouble();
        }
      }
    }
  }

  double? _imageWidthFor(String nodeId) {
    final cached = _imageWidths[nodeId];
    if (cached != null) {
      return cached;
    }
    final node = _descDocument.getNodeById(nodeId);
    if (node is ImageNode) {
      final width = node.getMetadataValue('width');
      if (width is num) {
        final value = width.toDouble();
        _imageWidths[node.id] = value;
        return value;
      }
    }
    return null;
  }

  Map<String, double> _extractImageWidths(String html) {
    final result = <String, double>{};
    final imgTagRegex = RegExp(r'<img[^>]*>', caseSensitive: false);
    final srcRegex = RegExp('src=[\'"]([^\'"]+)[\'"]', caseSensitive: false);
    final widthRegex =
        RegExp('width=[\'"]([0-9]+(?:\\.[0-9]+)?)[\'"]', caseSensitive: false);
    for (final match in imgTagRegex.allMatches(html)) {
      final tag = match.group(0)!;
      final srcMatch = srcRegex.firstMatch(tag);
      if (srcMatch == null) {
        continue;
      }
      final widthMatch = widthRegex.firstMatch(tag);
      if (widthMatch == null) {
        continue;
      }
      final value = double.tryParse(widthMatch.group(1)!);
      if (value != null) {
        result[srcMatch.group(1)!] = value;
      }
    }
    return result;
  }

  String _ensureImageWidthAttribute(
      String html, String imageUrl, double width) {
    final widthText = width.toStringAsFixed(0);
    final doubleQuoteKey = 'src="' + imageUrl + '"';
    final singleQuoteKey = "src='" + imageUrl + "'";
    var matchIndex = html.indexOf(doubleQuoteKey);
    if (matchIndex == -1) {
      matchIndex = html.indexOf(singleQuoteKey);
    }
    if (matchIndex == -1) {
      return html;
    }
    final tagStart = html.lastIndexOf('<img', matchIndex);
    if (tagStart == -1) {
      return html;
    }
    final tagEnd = html.indexOf('>', matchIndex);
    if (tagEnd == -1) {
      return html;
    }
    final existingTag = html.substring(tagStart, tagEnd + 1);
    final widthRegex =
        RegExp('width=[\'"]([0-9]+(?:\\.[0-9]+)?)[\'"]', caseSensitive: false);
    String newTag;
    if (widthRegex.hasMatch(existingTag)) {
      newTag =
          existingTag.replaceFirst(widthRegex, 'width="' + widthText + '"');
    } else {
      final trimmedTag = existingTag.trimRight();
      final closesSelf = trimmedTag.endsWith('/>');
      final insertionIndex = closesSelf
          ? existingTag.lastIndexOf('/>')
          : existingTag.lastIndexOf('>');
      if (insertionIndex == -1) {
        return html;
      }
      newTag = existingTag.substring(0, insertionIndex) +
          ' width="' +
          widthText +
          '"' +
          existingTag.substring(insertionIndex);
    }
    return html.replaceFirst(existingTag, newTag);
  }

  String _injectImageWidthsIntoHtml(String html) {
    if (_imageWidths.isEmpty) {
      return html;
    }
    var updatedHtml = html;
    for (final entry in _imageWidths.entries) {
      final node = _descDocument.getNodeById(entry.key);
      if (node is ImageNode) {
        updatedHtml =
            _ensureImageWidthAttribute(updatedHtml, node.imageUrl, entry.value);
      }
    }
    return updatedHtml;
  }

  void _applyWidthToImageNode(String nodeId, double width) {
    final node = _descDocument.getNodeById(nodeId);
    if (node is! ImageNode) {
      return;
    }
    final clampedWidth = width.clamp(_minImageWidth, _maxImageWidth).toDouble();
    _imageWidths[nodeId] = clampedWidth;
    final currentWidth = node.getMetadataValue('width');
    if (currentWidth is num && currentWidth.toDouble() == clampedWidth) {
      return;
    }
    final updatedNode =
        node.copyWithAddedMetadata({'width': clampedWidth}) as ImageNode;
    _descEditor.execute([
      ReplaceNodeRequest(existingNodeId: nodeId, newNode: updatedNode),
    ]);
  }

  void _updateActiveImageWidth(double width) {
    final nodeId = _selectedImageNodeId;
    if (nodeId == null) {
      return;
    }
    final clampedWidth = width.clamp(_minImageWidth, _maxImageWidth).toDouble();
    _applyWidthToImageNode(nodeId, clampedWidth);
    setState(() {
      _activeImageWidth = clampedWidth;
    });
  }

  void _clearImageSelection() {
    if (_selectedImageNodeId == null && _activeImageWidth == null) {
      return;
    }
    setState(() {
      _selectedImageNodeId = null;
      _activeImageWidth = null;
    });
  }

  void _handleSelectionChange() {
    if (!mounted) {
      return;
    }
    final selection = _descComposer.selection;
    if (selection == null) {
      if (_selectedImageNodeId != null) {
        _clearImageSelection();
      }
      return;
    }
    final nodeId = selection.extent.nodeId;
    final node = _descDocument.getNodeById(nodeId);
    if (node is ImageNode) {
      final width = _imageWidthFor(node.id) ?? _defaultImageWidth;
      if (_imageWidths[node.id] != width) {
        _applyWidthToImageNode(node.id, width);
      }
      if (_selectedImageNodeId != node.id || _activeImageWidth != width) {
        setState(() {
          _selectedImageNodeId = node.id;
          _activeImageWidth = width;
        });
      }
      return;
    }
    if (_selectedImageNodeId != null) {
      _clearImageSelection();
    }
  }

  Widget _buildImageResizeControls() {
    if (_selectedImageNodeId == null || _activeImageWidth == null) {
      return const SizedBox.shrink(key: ValueKey('image-resize-hidden'));
    }
    return Builder(builder: (context) {
      final width =
          _activeImageWidth!.clamp(_minImageWidth, _maxImageWidth).toDouble();
      final labelStyle =
          Theme.of(context).textTheme.bodySmall?.copyWith(color: DS.textDim);
      return Column(
        key: const ValueKey('image-resize-visible'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Divider(height: 1, thickness: 1, color: DS.border),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              children: [
                Text('Lebar gambar', style: labelStyle),
                const Spacer(),
                Text('${width.toInt()} px',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: DS.text)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Slider(
              min: _minImageWidth,
              max: _maxImageWidth,
              value: width,
              onChanged: _updateActiveImageWidth,
            ),
          ),
        ],
      );
    });
  }

  void _toggleInlineAttribution(Attribution attribution) {
    final selection = _descComposer.selection;
    if (selection == null || selection.isCollapsed) {
      _editorOps.toggleComposerAttributions({attribution});
    } else {
      _editorOps.toggleAttributionsOnSelection({attribution});
    }
    setState(() {});
  }

  void _toggleHeading(Attribution blockType) {
    final selection = _descComposer.selection;
    if (selection == null || selection.base.nodeId != selection.extent.nodeId) {
      return;
    }
    final node = _descDocument.getNodeById(selection.extent.nodeId);
    if (node is! ParagraphNode) {
      return;
    }
    final current = node.metadata[NodeMetadata.blockType] as Attribution?;
    final nextType = current == blockType ? paragraphAttribution : blockType;
    _descEditor.execute([
      ChangeParagraphBlockTypeRequest(nodeId: node.id, blockType: nextType),
    ]);
    setState(() {});
  }

  void _toggleUnorderedList() {
    final selection = _descComposer.selection;
    if (selection == null || selection.base.nodeId != selection.extent.nodeId) {
      return;
    }
    final node = _descDocument.getNodeById(selection.extent.nodeId);
    if (node is ListItemNode) {
      _editorOps.convertToParagraph();
    } else if (node is TextNode) {
      _editorOps.convertToListItem(ListItemType.unordered, node.text);
    }
    setState(() {});
  }

  void _resizeEditorViewport(bool increase) {
    setState(() {
      const minHeight = 320.0;
      const maxHeight = 960.0;
      final delta = increase ? 120.0 : -120.0;
      _editorViewportHeight =
          (_editorViewportHeight + delta).clamp(minHeight, maxHeight);
    });
  }

  Future<void> _insertImageIntoEditor() async {
    if (kIsWeb) {
      return;
    }
    final selection = _descComposer.selection;
    if (selection == null) {
      return;
    }
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['png', 'jpg', 'jpeg', 'gif', 'webp'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) {
      return;
    }
    final picked = result.files.first;
    final bytes = picked.bytes ??
        (picked.path != null ? await File(picked.path!).readAsBytes() : null);
    if (bytes == null) {
      return;
    }
    final ext = (picked.extension ?? '').toLowerCase();
    final mime = _mimeFromExtension(ext);
    final dataUri = 'data:' + mime + ';base64,' + base64Encode(bytes);
    final inserted = _editorOps.insertImage(dataUri);
    if (!inserted) {
      return;
    }
    final selectionAfterInsert = _descComposer.selection;
    if (selectionAfterInsert != null) {
      final nodeBefore =
          _descDocument.getNodeBeforeById(selectionAfterInsert.extent.nodeId);
      if (nodeBefore is ImageNode && nodeBefore.imageUrl == dataUri) {
        final imageNodeWithWidth = nodeBefore.copyWithAddedMetadata({
          'width': _defaultImageWidth,
        }) as ImageNode;
        _descEditor.execute([
          ReplaceNodeRequest(
              existingNodeId: nodeBefore.id, newNode: imageNodeWithWidth),
        ]);
        _imageWidths[nodeBefore.id] = _defaultImageWidth;
        _activeImageWidth = _defaultImageWidth;
        _selectedImageNodeId = nodeBefore.id;
      }
    }
    setState(() {});
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

  Widget _buildEditorToolbar() {
    if (kIsWeb) {
      return const SizedBox.shrink();
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: DS.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                _ToolbarIconButton(
                  icon: Icons.format_bold,
                  tooltip: 'Tebal',
                  onPressed: () => _toggleInlineAttribution(boldAttribution),
                ),
                _ToolbarIconButton(
                  icon: Icons.format_italic,
                  tooltip: 'Miring',
                  onPressed: () => _toggleInlineAttribution(italicsAttribution),
                ),
                _ToolbarIconButton(
                  icon: Icons.format_underline,
                  tooltip: 'Garis bawah',
                  onPressed: () =>
                      _toggleInlineAttribution(underlineAttribution),
                ),
                _ToolbarIconButton(
                  icon: Icons.format_list_bulleted,
                  tooltip: 'Bullet',
                  onPressed: _toggleUnorderedList,
                ),
                _ToolbarIconButton(
                  icon: Icons.title,
                  tooltip: 'Heading',
                  onPressed: () => _toggleHeading(header2Attribution),
                ),
                _ToolbarIconButton(
                  icon: Icons.image,
                  tooltip: 'Sisipkan gambar',
                  onPressed: _insertImageIntoEditor,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _ToolbarIconButton(
            icon: Icons.unfold_less,
            tooltip: 'Kecilkan tinggi editor',
            onPressed: () => _resizeEditorViewport(false),
          ),
          const SizedBox(width: 4),
          _ToolbarIconButton(
            icon: Icons.unfold_more,
            tooltip: 'Perbesar tinggi editor',
            onPressed: () => _resizeEditorViewport(true),
          ),
        ],
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _selectionListener = _handleSelectionChange;
    _descComposer.selectionNotifier.addListener(_selectionListener);
    _populateImageWidthCache();
    if (_isEditing) {
      _prefillInProgress = true;
      _loadArticleForEditing();
    }
  }

  @override
  void dispose() {
    _url.dispose();
    _title.dispose();
    _desc.dispose();
    _excerpt.dispose();
    _mediaName.dispose();
    _authorInput.dispose();
    _peopleInput.dispose();
    _orgsInput.dispose();
    _locationInput.dispose();
    _descComposer.selectionNotifier.removeListener(_selectionListener);
    _descComposer.dispose();
    _descEditorFocusNode.dispose();
    _descScrollController.dispose();
    super.dispose();
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
        // Use a raw triple-quoted regex so quotes don't need escaping
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
          String path = src;
          if (lowered.startsWith('file://')) {
            path = src.replaceFirst(RegExp(r'^file://'), '');
          }
          try {
            final f = File(path);
            if (await f.exists()) {
              final bytes = await f.readAsBytes();
              final b64 = base64Encode(bytes);
              String mime;
              final p = path.toLowerCase();
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
              // Remove images pointing to non-readable locations to avoid broken icons in editor
              html = html.replaceRange(m.start, m.end, '');
            }
          } catch (_) {}
        }
      } catch (_) {}
      return html;
    }

    _title.text = a.title;
    _url.text = a.url;
    _canonical = a.canonicalUrl;
    _desc.text = a.description ?? '';
    _excerpt.text = a.excerpt ?? '';
    _date = a.publishedAt;
    _kind = a.kind ?? 'artikel';
    _imagePath = a.imagePath;
    await widget.db.init();
    if (a.mediaId != null) {
      final m = await widget.db.getMediaById(a.mediaId!);
      if (m != null) {
        _mediaName.text = m.name;
        _mediaType = m.type;
      }
    }
    final authors = await widget.db.authorsForArticle(a.id);
    final people = await widget.db.peopleForArticle(a.id);
    final orgs = await widget.db.orgsForArticle(a.id);
    final locs = await widget.db.locationsForArticle(a.id);
    setState(() {
      _authorTags.addAll(authors);
      _peopleTags.addAll(people);
      _orgTags.addAll(orgs);
      _locationTags.addAll(locs);
    });

    final descText = a.description?.trim() ?? '';
    if (descText.isNotEmpty) {
      if (kIsWeb) {
        _desc.text = descText;
      } else {
        final processed = await convertLocalImagesToDataUri(descText);
        await _loadHtmlIntoEditor(processed);
      }
    } else if (!kIsWeb) {
      _resetEditorDocument();
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
      final f = res.files.single;
      setState(() {
        _pickedImageBytes = f.bytes;
        _pickedImageExt =
            (f.extension ?? '').isNotEmpty ? f.extension!.toLowerCase() : null;
        _removeImage = false; // since we pick a new one
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
        if ((_title.text).isEmpty && (meta.title ?? '').isNotEmpty)
          _title.text = meta.title!;
        if ((_excerpt.text).isEmpty && (meta.excerpt ?? '').isNotEmpty)
          _excerpt.text = meta.excerpt!;
        if ((_desc.text).isEmpty && (meta.description ?? '').isNotEmpty)
          _desc.text = meta.description!;
        // Also push extracted content into the rich editor
        final cand = ((meta.description ?? '').trim().isNotEmpty)
            ? meta.description!.trim()
            : (meta.excerpt ?? '').trim();
        if (!kIsWeb && cand.isNotEmpty) {
          await _loadHtmlIntoEditor(cand);
        } else if (kIsWeb && cand.isNotEmpty) {
          _desc.text = cand;
        }
      }
      // local dedupe by canonical URL
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
      if (mounted)
        setState(() {
          _loading = false;
        });
    }
  }

  Future<void> _save() async {
    await widget.db.init();
    // Capture rich content HTML from the editor or fallback
    String? descHtml;
    if (kIsWeb) {
      descHtml = _desc.text.trim().isEmpty ? null : _desc.text.trim();
    } else {
      try {
        descHtml = _editorHtml()?.trim();
      } catch (_) {
        descHtml = null;
      }
      if (descHtml == null || descHtml.isEmpty) {
        descHtml = _desc.text.trim().isEmpty ? null : _desc.text.trim();
      }
    }
    if (!kIsWeb && descHtml != null && descHtml.isNotEmpty) {
      descHtml = _injectImageWidthsIntoHtml(descHtml);
    }
    int? mediaId;
    if (_mediaName.text.trim().isNotEmpty) {
      mediaId = await widget.db.upsertMedia(_mediaName.text.trim(), _mediaType);
    }
    final a = ArticleModel(
      id: _isEditing
          ? widget.article!.id
          : 'local-${DateTime.now().millisecondsSinceEpoch}',
      title: _title.text.trim(),
      url: _url.text.trim(),
      canonicalUrl: _canonical?.trim().isEmpty == true ? null : _canonical,
      mediaId: mediaId,
      kind: _kind,
      description: descHtml,
      excerpt: _excerpt.text.trim().isEmpty ? null : _excerpt.text.trim(),
      publishedAt: _date,
      imagePath: _isEditing ? widget.article!.imagePath : null,
    );
    // Handle image save/delete
    if (_pickedImageBytes != null && _pickedImageBytes!.isNotEmpty) {
      try {
        final ext = (_pickedImageExt ?? 'jpg').replaceAll('.', '');
        final savedPath =
            await saveImageForArticle(a.id, _pickedImageBytes!, ext: ext);
        if (savedPath.isEmpty && kIsWeb) {
          _error = 'Penyimpanan gambar belum didukung di Web.';
        }
        if (savedPath.isNotEmpty) {
          a.imagePath = savedPath;
          _imagePath = savedPath;
        }
      } catch (e) {
        _error = 'Gagal menyimpan gambar: $e';
      }
    } else if (_removeImage) {
      // remove existing image and delete file when applicable
      final old = _imagePath ?? widget.article?.imagePath;
      if (old != null && old.isNotEmpty) {
        await deleteIfExists(old);
      }
      a.imagePath = null;
      _imagePath = null;
    }
    await widget.db.upsertArticle(a);
    // Upsert tags and link
    final authorIds = <int>[];
    for (final name
        in _authorTags.map((e) => e.trim()).where((e) => e.isNotEmpty)) {
      authorIds.add(await widget.db.upsertAuthorByName(name));
    }
    await widget.db.setArticleAuthors(a.id, authorIds);

    final peopleIds = <int>[];
    for (final name
        in _peopleTags.map((e) => e.trim()).where((e) => e.isNotEmpty)) {
      peopleIds.add(await widget.db.upsertPersonByName(name));
    }
    await widget.db.setArticlePeople(a.id, peopleIds);

    final orgIds = <int>[];
    for (final name
        in _orgTags.map((e) => e.trim()).where((e) => e.isNotEmpty)) {
      orgIds.add(await widget.db.upsertOrganizationByName(name));
    }
    await widget.db.setArticleOrganizations(a.id, orgIds);

    final locIds = <int>[];
    for (final name
        in _locationTags.map((e) => e.trim()).where((e) => e.isNotEmpty)) {
      locIds.add(await widget.db.upsertLocationByName(name));
    }
    await widget.db.setArticleLocations(a.id, locIds);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
                    onPressed: _loading ? null : _save),
              ],
              child: PageContainer(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SectionCard(
                        title: 'Sumber',
                        child: Column(children: [
                          UiInput(
                              controller: _url,
                              hint: 'Link artikel',
                              prefix: Icons.link,
                              suffix: InkWell(
                                  onTap: _loading ? null : _extract,
                                  borderRadius: BorderRadius.circular(8),
                                  child: const Padding(
                                      padding: EdgeInsets.all(8),
                                      child: Icon(Icons.auto_fix_high)))),
                          const SizedBox(height: Spacing.md),
                          UiInput(controller: _title, hint: 'Judul'),
                          const SizedBox(height: Spacing.sm),
                          _KindChips(
                              value: _kind,
                              onChanged: (v) =>
                                  setState(() => _kind = v ?? 'artikel')),
                        ]),
                      ),
                      const SizedBox(height: Spacing.lg),
                      _buildMediaSection(context),
                      const SizedBox(height: Spacing.lg),
                      SectionCard(
                        title: 'Konten',
                        child: Column(children: [
                          // Excerpt field hidden per request; still kept in state for storage if needed
                          // Use rich editor (mobile/desktop); fallback to textarea on Web
                          Builder(builder: (context) {
                            if (kIsWeb) {
                              return UiTextArea(
                                  controller: _desc,
                                  hint: 'Deskripsi',
                                  minLines: 5,
                                  maxLines: 12);
                            }
                            return _KeepAlive(
                              child: Container(
                                height: _editorViewportHeight,
                                decoration: BoxDecoration(
                                  color: DS.surface,
                                  border: Border.all(color: DS.border),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: CustomScrollView(
                                  controller: _descScrollController,
                                  slivers: [
                                    SliverToBoxAdapter(
                                      child: _buildEditorToolbar(),
                                    ),
                                    SliverToBoxAdapter(
                                      child: Divider(
                                          height: 1,
                                          thickness: 1,
                                          color: DS.border),
                                    ),
                                    SuperEditor(
                                      editor: _descEditor,
                                      focusNode: _descEditorFocusNode,
                                      documentLayoutKey: _descLayoutKey,
                                      plugins: const {_DataUriImagePlugin()},
                                      stylesheet: defaultStylesheet.copyWith(
                                        documentPadding:
                                            const EdgeInsets.symmetric(
                                                vertical: 8, horizontal: 8),
                                      ),
                                      selectionStyle: SelectionStyles(
                                        selectionColor: DS.accentLite,
                                      ),
                                    ),
                                    SliverToBoxAdapter(
                                      child: AnimatedSwitcher(
                                        duration:
                                            const Duration(milliseconds: 180),
                                        child: _buildImageResizeControls(),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }),
                        ]),
                      ),
                      const SizedBox(height: Spacing.lg),
                      _buildImageSection(context),
                      const SizedBox(height: Spacing.lg),
                      SectionCard(
                        title: 'Tag',
                        child: Column(children: [
                          TagEditor(
                            label: 'Lokasi',
                            controller: _locationInput,
                            tags: _locationTags,
                            onAdded: (v) {
                              setState(() => _locationTags.add(v));
                            },
                            onRemoved: (v) {
                              setState(() => _locationTags.remove(v));
                            },
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
                            onAdded: (v) {
                              setState(() => _authorTags.add(v));
                            },
                            onRemoved: (v) {
                              setState(() => _authorTags.remove(v));
                            },
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
                            onAdded: (v) {
                              setState(() => _peopleTags.add(v));
                            },
                            onRemoved: (v) {
                              setState(() => _peopleTags.remove(v));
                            },
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
                            onAdded: (v) {
                              setState(() => _orgTags.add(v));
                            },
                            onRemoved: (v) {
                              setState(() => _orgTags.remove(v));
                            },
                            suggestionFetcher: (text) async {
                              await widget.db.init();
                              return widget.db.suggestOrganizations(text);
                            },
                          ),
                        ]),
                      ),
                      const SizedBox(height: Spacing.lg),
                      if (_canonical != null)
                        Text('Canonical URL: $_canonical',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: DS.textDim)),
                      if (_error != null)
                        Padding(
                            padding: const EdgeInsets.only(top: Spacing.sm),
                            child: Text(_error!,
                                style: const TextStyle(color: Colors.red))),
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
    );
  }

  Widget _buildMediaSection(BuildContext context) {
    return SectionCard(
      title: 'Media & Tanggal',
      child: LayoutBuilder(builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 640;
        final mediaNameField = _buildLabeledField(
          context,
          'Nama Media',
          UiInput(
            controller: _mediaName,
            hint: 'Nama media',
            prefix: Icons.apartment,
          ),
        );
        final dateField = _buildLabeledField(
          context,
          'Tanggal Terbit',
          _buildDateField(context),
        );
        final mediaTypeField = _buildLabeledField(
          context,
          'Jenis Media',
          _buildMediaTypeField(context),
        );
        if (isWide) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: mediaNameField),
                  const SizedBox(width: Spacing.md),
                  Expanded(child: dateField),
                ],
              ),
              const SizedBox(height: Spacing.md),
              mediaTypeField,
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            mediaNameField,
            const SizedBox(height: Spacing.md),
            dateField,
            const SizedBox(height: Spacing.md),
            mediaTypeField,
          ],
        );
      }),
    );
  }

  Widget _buildImageSection(BuildContext context) {
    return SectionCard(
      title: 'Gambar',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: DS.surface,
              border: Border.all(color: DS.border),
              borderRadius: BorderRadius.circular(8),
            ),
            padding: const EdgeInsets.all(12),
            child: Builder(builder: (context) {
              if (_pickedImageBytes != null && _pickedImageBytes!.isNotEmpty) {
                return Image.memory(_pickedImageBytes!,
                    height: 160, fit: BoxFit.cover);
              } else if ((_imagePath ?? '').isNotEmpty) {
                final w =
                    imageFromPath(_imagePath!, height: 160, fit: BoxFit.cover);
                if (w != null) return w;
              }
              return Text('Belum ada gambar',
                  style: TextStyle(color: DS.textDim));
            }),
          ),
          const SizedBox(height: Spacing.sm),
          Row(children: [
            UiButton(
                label: 'Pilih Gambar',
                icon: Icons.image,
                primary: false,
                onPressed: _pickImage),
            const SizedBox(width: Spacing.sm),
            UiButton(
                label: 'Hapus',
                icon: Icons.delete,
                primary: false,
                onPressed: (_pickedImageBytes != null) ||
                        ((_imagePath ?? '').isNotEmpty)
                    ? () {
                        setState(() {
                          _pickedImageBytes = null;
                          _pickedImageExt = null;
                          _removeImage = true;
                        });
                      }
                    : null),
          ]),
          if (kIsWeb)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('Catatan: Penyimpanan gambar belum didukung di Web.',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: DS.textDim)),
            ),
        ],
      ),
    );
  }

  Widget _buildMediaTypeField(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: DS.surface,
        borderRadius: DS.br,
        border: Border.all(color: DS.border),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: _MediaTypeChips(
        value: _mediaType,
        onChanged: (v) => setState(() => _mediaType = v ?? 'online'),
      ),
    );
  }

  Widget _buildDateField(BuildContext context) {
    final label =
        _date == null ? 'Pilih tanggal terbit' : _formatDisplayDate(_date!);
    final textStyle = Theme.of(context).textTheme.bodyMedium;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _pickPublishedDate(context),
      child: Container(
        decoration: BoxDecoration(
          color: DS.surface,
          borderRadius: DS.br,
          border: Border.all(color: DS.border),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: Row(
          children: [
            Icon(Icons.event, color: DS.textDim),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: textStyle?.copyWith(
                  color: _date == null ? DS.textDim : DS.text,
                ),
              ),
            ),
            Icon(Icons.keyboard_arrow_down, color: DS.textDim),
          ],
        ),
      ),
    );
  }

  Widget _buildLabeledField(
    BuildContext context,
    String label,
    Widget child,
  ) {
    final style =
        Theme.of(context).textTheme.bodySmall?.copyWith(color: DS.textDim);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: style),
        const SizedBox(height: 6),
        child,
      ],
    );
  }

  String _formatDisplayDate(DateTime date) {
    String twoDigits(int value) => value.toString().padLeft(2, '0');
    return '${date.year}-${twoDigits(date.month)}-${twoDigits(date.day)}';
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
      child: Row(children: [
        for (final t in types) ...[
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: InkWell(
              onTap: () => onChanged(t.$1),
              borderRadius: BorderRadius.circular(20),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: (value == t.$1
                      ? ((t.$1 == 'online' || t.$1 == 'tv')
                          ? DS.accentLite
                          : DS.accent2Lite)
                      : DS.surface),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: DS.border),
                ),
                child: Text(t.$2,
                    style: TextStyle(
                        color: value == t.$1
                            ? ((t.$1 == 'online' || t.$1 == 'tv')
                                ? DS.accent
                                : DS.accent2)
                            : DS.text)),
              ),
            ),
          ),
        ]
      ]),
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
    return Row(children: [
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
              child: Text(k.$2,
                  style: TextStyle(color: value == k.$1 ? DS.accent : DS.text)),
            ),
          ),
        ),
      ]
    ]);
  }
}

class _KeepAlive extends StatefulWidget {
  final Widget child;
  const _KeepAlive({required this.child});
  @override
  State<_KeepAlive> createState() => _KeepAliveState();
}

class _KeepAliveState extends State<_KeepAlive>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

class _ToolbarIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  const _ToolbarIconButton(
      {required this.icon, required this.tooltip, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(6),
          child: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: DS.surface2,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: DS.border),
            ),
            child: Icon(icon, size: 18, color: DS.text),
          ),
        ),
      ),
    );
  }
}

class _DataUriImagePlugin extends SuperEditorPlugin {
  const _DataUriImagePlugin();

  @override
  List<ComponentBuilder> get componentBuilders => const [
        _DataUriImageComponentBuilder(),
      ];
}

class _DataUriImageComponentBuilder extends ImageComponentBuilder {
  const _DataUriImageComponentBuilder();

  @override
  SingleColumnLayoutComponentViewModel? createViewModel(
      Document document, DocumentNode node) {
    final viewModel = super.createViewModel(document, node);
    if (viewModel is ImageComponentViewModel && node is ImageNode) {
      final widthMeta = node.getMetadataValue('width');
      if (widthMeta is num) {
        final width = widthMeta.toDouble();
        viewModel.maxWidth = width;
      }
    }
    return viewModel;
  }

  @override
  Widget? createComponent(
    SingleColumnDocumentComponentContext componentContext,
    SingleColumnLayoutComponentViewModel componentViewModel,
  ) {
    if (componentViewModel is! ImageComponentViewModel) {
      return super.createComponent(componentContext, componentViewModel);
    }

    final imageUrl = componentViewModel.imageUrl;
    if (!imageUrl.startsWith('data:')) {
      return super.createComponent(componentContext, componentViewModel);
    }

    final imageViewModel = componentViewModel as ImageComponentViewModel;
    final explicitWidth = imageViewModel.expectedSize?.width?.toDouble() ??
        imageViewModel.maxWidth;

    return ImageComponent(
      componentKey: componentContext.componentKey,
      imageUrl: imageUrl,
      expectedSize: componentViewModel.expectedSize,
      selection: componentViewModel.selection?.nodeSelection
          as UpstreamDownstreamNodeSelection?,
      selectionColor: componentViewModel.selectionColor,
      opacity: componentViewModel.opacity,
      imageBuilder: (context, _) {
        final bytes = _decodeDataUriBytes(imageUrl);
        if (bytes == null) {
          debugPrint('Failed to decode data URI image');
          return const SizedBox.shrink();
        }
        final imageWidget = Image.memory(
          bytes,
          fit: BoxFit.contain,
        );
        if (explicitWidth == null) {
          return imageWidget;
        }
        return Align(
          alignment: Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: explicitWidth!,
            ),
            child: imageWidget,
          ),
        );
      },
    );
  }

  Uint8List? _decodeDataUriBytes(String uri) {
    final trimmed = uri.trim();
    try {
      return UriData.parse(trimmed).contentAsBytes();
    } catch (_) {
      final normalized = trimmed.replaceAll(RegExp(r'\s+'), '');
      if (normalized != trimmed) {
        try {
          return UriData.parse(normalized).contentAsBytes();
        } catch (_) {}
      }
      final match = RegExp(r'^data:([^;]+);base64,(.*)$',
              caseSensitive: false, dotAll: true)
          .firstMatch(normalized);
      if (match != null) {
        final payload = match.group(2);
        if (payload != null) {
          try {
            return base64Decode(payload);
          } catch (_) {}
        }
      }
    }
    return null;
  }
}
