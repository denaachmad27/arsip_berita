import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'dart:io';
import '../../util/platform_io.dart';
import '../../data/local/db.dart';
import '../../widgets/page_container.dart';
import '../../ui/theme.dart';
import '../../ui/design.dart';
import '../../ui/theme_mode.dart';
import '../../widgets/ui_scaffold.dart';
import '../../widgets/ui_card.dart';
import '../../widgets/image_preview.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:url_launcher/url_launcher.dart';
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
    final isDark = ThemeController.instance.isDark;
    return Chip(
      avatar: Icon(icon, size: 16, color: isDark ? const Color(0xFF1F2937) : DS.text),
      label: Text(label, style: TextStyle(color: isDark ? const Color(0xFF1F2937) : DS.text)),
      backgroundColor: isDark ? const Color(0xFFD4A574) : DS.surface,
      side: BorderSide(color: isDark ? const Color(0xFFD4A574) : DS.border),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      visualDensity: const VisualDensity(horizontal: -2, vertical: -3),
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

  Future<void> _openUrl(String urlString) async {
    final shouldOpen = await showDialog<bool>(
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
                    color: DS.accent.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.open_in_new,
                    size: 36,
                    color: DS.accent,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Buka Link?',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: DS.text,
                      ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Apakah Anda ingin membuka link ini di browser?',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: DS.textDim,
                      ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: DS.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: DS.border),
                  ),
                  child: Text(
                    urlString,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: DS.accent,
                          fontFamily: 'monospace',
                        ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
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
                          backgroundColor: DS.accent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: const Text('Buka'),
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

    if (shouldOpen == true && mounted) {
      try {
        final uri = Uri.parse(urlString);
        final canLaunch = await canLaunchUrl(uri);

        if (!canLaunch) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Tidak dapat membuka URL. Browser tidak tersedia.'),
                backgroundColor: Colors.red,
              ),
            );
          }
          return;
        }

        final launched = await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );

        if (!launched && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Gagal membuka URL di browser.'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error: ${e.toString()}'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 4),
            ),
          );
        }
      }
    }
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
                  widget.article.tags = latest.tags;
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

                    // Get ImageProvider for preview
                    final ImageProvider imageProvider;
                    if (a.imagePath!.startsWith('http')) {
                      imageProvider = NetworkImage(a.imagePath!);
                    } else {
                      imageProvider = FileImage(File(a.imagePath!));
                    }

                    return GestureDetector(
                      onTap: () {
                        ImagePreview.show(
                          context,
                          imageProvider: imageProvider,
                          heroTag: 'cover-${a.id}',
                        );
                      },
                      child: Hero(
                        tag: 'cover-${a.id}',
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: w,
                        ),
                      ),
                    );
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

                  // Add general tags first
                  final generalTags = a.tags ?? const <String>[];
                  for (final t in generalTags) {
                    chips.add(_compactTagChip(Icons.local_offer, t));
                  }

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
              const SizedBox(height: Spacing.sm),
              GestureDetector(
                onTap: () => _openUrl(a.url),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        a.url,
                        style: TextStyle(
                          color: DS.accent,
                          decoration: TextDecoration.underline,
                          decorationColor: DS.accent.withValues(alpha: 0.5),
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      Icons.open_in_new,
                      size: 16,
                      color: DS.accent,
                    ),
                  ],
                ),
              ),
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
                  Builder(
                    builder: (context) {
                      final isDark = ThemeController.instance.isDark;
                      return Chip(
                        label: Text(
                          a.kind == 'opini' ? 'Opini' : 'Artikel',
                          style: TextStyle(color: isDark ? const Color(0xFF1F2937) : DS.text)
                        ),
                        backgroundColor: isDark ? const Color(0xFFD4A574) : DS.surface,
                        side: BorderSide(color: isDark ? const Color(0xFFD4A574) : DS.border),
                      );
                    }
                  ),
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
                    customStylesBuilder: (element) {
                      if (element.localName == 'p') {
                        return {'margin-bottom': '0px', 'margin-top': '0px'};
                      }
                      return null;
                    },
                    customWidgetBuilder: (element) {
                      if (element.localName == 'img') {
                        final src = element.attributes['src'];
                        if (src == null) return null;
                        final widthStr = element.attributes['width'];
                        double? width;
                        if (widthStr != null) {
                          width = double.tryParse(widthStr);
                        }
                        try {
                          final ImageProvider imageProvider;
                          final Widget imageWidget;

                          if (src.startsWith('data:')) {
                            final bytes = UriData.parse(src).contentAsBytes();
                            imageProvider = MemoryImage(bytes);
                            imageWidget = Image.memory(
                              bytes,
                              width: width,
                              fit: BoxFit.contain,
                              errorBuilder: (context, error, stackTrace) {
                                return const Icon(Icons.broken_image);
                              },
                            );
                          } else {
                            imageProvider = NetworkImage(src);
                            imageWidget = Image.network(
                              src,
                              width: width,
                              fit: BoxFit.contain,
                              errorBuilder: (context, error, stackTrace) {
                                return const Icon(Icons.broken_image);
                              },
                            );
                          }

                          return Align(
                            alignment: Alignment.centerLeft,
                            child: GestureDetector(
                              onTap: () {
                                ImagePreview.show(
                                  context,
                                  imageProvider: imageProvider,
                                  heroTag: 'content-img-${src.hashCode}',
                                );
                              },
                              child: Hero(
                                tag: 'content-img-${src.hashCode}',
                                child: imageWidget,
                              ),
                            ),
                          );
                        } catch (e) {
                          debugPrint('Error loading image: $e');
                          return const Icon(Icons.broken_image);
                        }
                      }
                      return null;
                    },
                  )
                else
                  SelectionArea(
                    child: HtmlWidget(
                      _renderDesc!,
                      textStyle: TextStyle(color: DS.text),
                      customStylesBuilder: (element) {
                        if (element.localName == 'p') {
                          return {'margin-bottom': '0px', 'margin-top': '0px'};
                        }
                        return null;
                      },
                      customWidgetBuilder: (element) {
                        if (element.localName == 'img') {
                          final src = element.attributes['src'];
                          if (src == null) return null;
                          final widthStr = element.attributes['width'];
                          double? width;
                          if (widthStr != null) {
                            width = double.tryParse(widthStr);
                          }
                          try {
                            final ImageProvider imageProvider;
                            final Widget imageWidget;

                            if (src.startsWith('data:')) {
                              final bytes = UriData.parse(src).contentAsBytes();
                              imageProvider = MemoryImage(bytes);
                              imageWidget = Image.memory(
                                bytes,
                                width: width,
                                fit: BoxFit.contain,
                                errorBuilder: (context, error, stackTrace) {
                                  return const Icon(Icons.broken_image);
                                },
                              );
                            } else {
                              imageProvider = NetworkImage(src);
                              imageWidget = Image.network(
                                src,
                                width: width,
                                fit: BoxFit.contain,
                                errorBuilder: (context, error, stackTrace) {
                                  return const Icon(Icons.broken_image);
                                },
                              );
                            }

                            return Align(
                              alignment: Alignment.centerLeft,
                              child: GestureDetector(
                                onTap: () {
                                  ImagePreview.show(
                                    context,
                                    imageProvider: imageProvider,
                                    heroTag: 'content-img-${src.hashCode}',
                                  );
                                },
                                child: Hero(
                                  tag: 'content-img-${src.hashCode}',
                                  child: imageWidget,
                                ),
                              ),
                            );
                          } catch (e) {
                            debugPrint('Error loading image: $e');
                            return const Icon(Icons.broken_image);
                          }
                        }
                        return null;
                      },
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
