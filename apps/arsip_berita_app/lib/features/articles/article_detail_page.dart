import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'dart:io';
import '../../util/platform_io.dart';
import '../../data/local/db.dart';
import '../../widgets/page_container.dart';
import '../../ui/theme.dart';
import '../../ui/design.dart';
import '../../widgets/ui_scaffold.dart';
import '../../widgets/ui_card.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'article_form_page.dart';

class ArticleDetailPage extends StatefulWidget {
  final ArticleModel article;
  const ArticleDetailPage({super.key, required this.article});
  @override
  State<ArticleDetailPage> createState() => _ArticleDetailPageState();
}

class _ArticleDetailPageState extends State<ArticleDetailPage> {
  final _db = LocalDatabase();
  Future<(List<String>, List<String>, List<String>, List<String>)>? _tagsFuture;
  String?
      _renderDesc; // processed HTML for rendering (e.g., local images -> data URIs)
  static const String _highlightStyle = 'background-color: #a5d6a7;';

  @override
  void initState() {
    super.initState();
    // Kick off tag loading immediately; _loadTags will init DB as needed
    _tagsFuture = _loadTags();
    _prepareDesc();
  }

  Future<void> _prepareDesc() async {
    final raw = widget.article.description;
    if (raw == null || raw.trim().isEmpty) {
      setState(() {
        _renderDesc = null;
      });
      return;
    }
    String html = raw;
    try {
      // Replace local file image src with data URIs so HtmlWidget can render them
      final regex = RegExp(r'''<img[^>]*src=["']([^"']+)["'][^>]*>''',
          caseSensitive: false);
      final matches = regex
          .allMatches(html)
          .toList()
          .reversed; // iterate from end to keep indices valid
      for (final m in matches) {
        final src = m.group(1);
        if (src == null) continue;
        final lowered = src.toLowerCase();
        final isNetwork = lowered.startsWith('http://') ||
            lowered.startsWith('https://') ||
            lowered.startsWith('data:');
        if (isNetwork) continue;
        // Handle file URI or plain path
        String path = src;
        if (lowered.startsWith('file://')) {
          path = src.replaceFirst(RegExp(r'^file://'), '');
        }
        try {
          final f = File(path);
          if (await f.exists()) {
            final bytes = await f.readAsBytes();
            final b64 = base64Encode(bytes);
            final mime = _guessImageMime(path);
            final dataUri = 'data:$mime;base64,$b64';
            html = html.replaceRange(
                m.start, m.end, m.group(0)!.replaceFirst(src, dataUri));
          } else {
            // Drop images pointing to non-readable locations (e.g., content://)
            html = html.replaceRange(m.start, m.end, '');
          }
        } catch (_) {}
      }
    } catch (_) {}
    html = _normalizeHighlightStyles(html);
    widget.article.description = html;
    if (mounted)
      setState(() {
        _renderDesc = html;
      });
  }

  Future<(List<String>, List<String>, List<String>, List<String>)>
      _loadTags() async {
    await _db.init();
    final authors = await _db.authorsForArticle(widget.article.id);
    final people = await _db.peopleForArticle(widget.article.id);
    final orgs = await _db.orgsForArticle(widget.article.id);
    final locs = await _db.locationsForArticle(widget.article.id);
    return (authors, people, orgs, locs);
  }

  Widget _compactTagChip(IconData icon, String label) {
    return Chip(
      avatar: Icon(icon, size: 16),
      label: Text(label),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      visualDensity: const VisualDensity(horizontal: -2, vertical: -3),
      labelStyle: Theme.of(context).textTheme.bodySmall,
    );
  }

  String _normalizeHighlightStyles(String html) {
    final regex = RegExp(
        r'(<mark[^>]*data-highlight="true"[^>]*style=")([^"]*)(")',
        caseSensitive: false);
    final singleQuoteRegex = RegExp(
        r"(<mark[^>]*data-highlight='true'[^>]*style=')([^']*)(')",
        caseSensitive: false);
    html = html.replaceAllMapped(
        regex, (m) => '${m.group(1)}$_highlightStyle${m.group(3)}');
    html = html.replaceAllMapped(
        singleQuoteRegex, (m) => '${m.group(1)}$_highlightStyle${m.group(3)}');
    html = html.replaceAll(
        RegExp(r'background-color:\s*#fff59d;?', caseSensitive: false),
        _highlightStyle);
    html = html.replaceAll(
        RegExp(r'background-color:\s*#fff9c4;?', caseSensitive: false),
        _highlightStyle);
    return html;
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.article;
    return Scaffold(
      backgroundColor: DS.bg,
      body: UiScaffold(
        title: 'Detail Artikel',
        actions: [
          IconButton(
            tooltip: 'Edit',
            onPressed: () async {
              await Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => ArticleFormPage(db: _db, article: a)));
              // reload article and tags after editing
              final latest = await _db.getArticleById(a.id);
              if (latest != null && mounted) {
                setState(() {
                  widget.article.title = latest.title;
                  widget.article.url = latest.url;
                  widget.article.canonicalUrl = latest.canonicalUrl;
                  widget.article.mediaId = latest.mediaId;
                  widget.article.kind = latest.kind;
                  widget.article.publishedAt = latest.publishedAt;
                  widget.article.description = latest.description;
                  widget.article.excerpt = latest.excerpt;
                  widget.article.imagePath = latest.imagePath;
                  _tagsFuture = _loadTags();
                  _prepareDesc();
                });
              }
            },
            icon: const Icon(Icons.edit),
          ),
        ],
        child: PageContainer(
            child: ListView(children: [
          UiCard(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if ((a.imagePath ?? '').isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: Spacing.sm),
                  child: Builder(builder: (context) {
                    final w = imageFromPath(a.imagePath!,
                        width: double.infinity, height: 180, fit: BoxFit.cover);
                    if (w == null) return const SizedBox.shrink();
                    return ClipRRect(
                        borderRadius: BorderRadius.circular(8), child: w);
                  }),
                ),
              Text(a.title,
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(color: DS.text)),
              const SizedBox(height: Spacing.sm),
              // Tags directly below title and above URL
              FutureBuilder<
                  (List<String>, List<String>, List<String>, List<String>)>(
                future: _tagsFuture,
                builder: (context, snapshot) {
                  final authors = snapshot.data?.$1 ?? const <String>[];
                  final people = snapshot.data?.$2 ?? const <String>[];
                  final orgs = snapshot.data?.$3 ?? const <String>[];
                  final locs = snapshot.data?.$4 ?? const <String>[];
                  final chips = <Widget>[];
                  for (final t in authors) {
                    chips.add(_compactTagChip(Icons.person, t));
                  }
                  for (final t in people) {
                    chips.add(_compactTagChip(Icons.account_circle, t));
                  }
                  for (final t in orgs) {
                    chips.add(_compactTagChip(Icons.apartment, t));
                  }
                  for (final t in locs) {
                    chips.add(_compactTagChip(Icons.place, t));
                  }
                  if (chips.isEmpty) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Wrap(spacing: 6, runSpacing: 4, children: chips),
                  );
                },
              ),
              Text(a.url, style: TextStyle(color: DS.textDim)),
              const SizedBox(height: Spacing.sm),
              Row(children: [
                if (a.publishedAt != null) ...[
                  const Icon(Icons.event, size: 18, color: Colors.grey),
                  const SizedBox(width: 6),
                  Text(_formatDate(a.publishedAt!),
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: DS.textDim)),
                ],
                if ((a.kind ?? '').isNotEmpty) ...[
                  const SizedBox(width: 12),
                  Chip(label: Text(a.kind == 'opini' ? 'Opini' : 'Artikel')),
                ],
              ]),

              // canonical URL removed to avoid duplication with main URL
              // Show excerpt only when there is no rich description to avoid duplication
              if ((a.excerpt != null && a.excerpt!.trim().isNotEmpty) &&
                  (_renderDesc == null || _renderDesc!.trim().isEmpty)) ...[
                const SizedBox(height: Spacing.md),
                // Render excerpt as plain text (usually short summary)
                Text(a.excerpt!, style: TextStyle(color: DS.text)),
              ],
              if (_renderDesc != null && _renderDesc!.trim().isNotEmpty) ...[
                const SizedBox(height: Spacing.md),
                if (kIsWeb)
                  HtmlWidget(
                    _renderDesc!,
                    textStyle: TextStyle(color: DS.text),
                  )
                else
                  SelectionArea(
                    child: HtmlWidget(
                      _renderDesc!,
                      textStyle: TextStyle(color: DS.text),
                    ),
                  ),
              ],
            ]),
          ),
          const SizedBox(height: Spacing.lg),
          const SizedBox(height: Spacing.xxl),
        ])),
      ),
    );
  }
}

String _formatDate(DateTime d) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(d.day)}/${two(d.month)}/${d.year}';
}

String _guessImageMime(String path) {
  final p = path.toLowerCase();
  if (p.endsWith('.png')) return 'image/png';
  if (p.endsWith('.jpg') || p.endsWith('.jpeg')) return 'image/jpeg';
  if (p.endsWith('.gif')) return 'image/gif';
  if (p.endsWith('.webp')) return 'image/webp';
  if (p.endsWith('.bmp')) return 'image/bmp';
  if (p.endsWith('.svg')) return 'image/svg+xml';
  return 'image/*';
}
