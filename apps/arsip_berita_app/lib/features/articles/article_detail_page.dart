import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import '../../util/platform_io.dart';
import '../../data/local/db.dart';
import '../../widgets/page_container.dart';
import '../../ui/theme.dart';
import '../../ui/design.dart';
import '../../widgets/ui_scaffold.dart';
import '../../widgets/ui_card.dart';
import '../../widgets/image_preview.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:url_launcher/url_launcher.dart';
import 'article_form_page.dart';
import 'quote_confirmation_page.dart';
import '../settings/ai_settings_page.dart';

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
  ArticleModel? _fullArticle; // Article with full content loaded from DB
  bool _loadingFullArticle = true;
  String? _cachedOpenAIKey; // Cached OpenAI API key
  String? _cachedGeminiKey; // Cached Gemini API key
  String _selectedAIModel = 'openai'; // Selected AI model
  static const String _openaiApiKeyKey = 'openai_api_key';
  static const String _geminiApiKeyKey = 'gemini_api_key';
  static const String _aiModelKey = 'ai_model_preference';

  @override
  void initState() {
    super.initState();
    // Load full article data (including description) from database
    _loadFullArticle();
    // Kick off tag loading immediately; _loadTags will init DB as needed
    _tagsFuture = _loadTags();
    // Load cached API key
    _loadApiKey();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _loadApiKey() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final openaiKey = prefs.getString(_openaiApiKeyKey);
      final geminiKey = prefs.getString(_geminiApiKeyKey);
      final aiModel = prefs.getString(_aiModelKey) ?? 'openai';
      if (mounted) {
        setState(() {
          _cachedOpenAIKey = openaiKey;
          _cachedGeminiKey = geminiKey;
          _selectedAIModel = aiModel;
        });
      }
    } catch (e) {
      debugPrint('Error loading API key: $e');
    }
  }

  Future<void> _saveApiKey(String apiKey) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Save to the appropriate key based on selected model
      if (_selectedAIModel == 'openai') {
        await prefs.setString(_openaiApiKeyKey, apiKey);
        setState(() {
          _cachedOpenAIKey = apiKey;
        });
      } else {
        await prefs.setString(_geminiApiKeyKey, apiKey);
        setState(() {
          _cachedGeminiKey = apiKey;
        });
      }
    } catch (e) {
      debugPrint('Error saving API key: $e');
    }
  }

  Future<void> _loadFullArticle() async {
    await _db.init();
    final fullArticle = await _db.getArticleById(widget.article.id);
    if (mounted) {
      setState(() {
        _fullArticle = fullArticle ?? widget.article;
        _loadingFullArticle = false;
      });
      await _prepareDesc();
    }
  }

  Future<void> _prepareDesc() async {
    // Use full article if loaded, otherwise use widget.article
    final article = _fullArticle ?? widget.article;
    final raw = article.description;
    if (raw == null || raw.trim().isEmpty) {
      if (mounted) {
        setState(() {
          _renderDesc = null;
        });
      }
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
    // Don't normalize highlight styles - preserve original colors
    article.description = html;
    if (mounted) {
      setState(() {
        _renderDesc = html;
      });
    }
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


  Future<void> _duplicateArticle() async {
    final shouldDuplicate = await showDialog<bool>(
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
                    Icons.content_copy,
                    size: 36,
                    color: DS.accent,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Duplikat Artikel?',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: DS.text,
                      ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Artikel ini akan diduplikat dengan judul "[Salinan] ${widget.article.title}". Anda dapat mengeditnya setelah duplikat dibuat.',
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
                          backgroundColor: DS.accent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: const Text('Duplikat'),
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

    if (shouldDuplicate == true && mounted) {
      try {
        await _db.init();

        // Load full article data including all relations
        final original = await _db.getArticleById(widget.article.id);
        if (original == null) {
          throw Exception('Artikel tidak ditemukan');
        }

        // Get all relations
        final authors = await _db.authorsForArticle(original.id);
        final people = await _db.peopleForArticle(original.id);
        final orgs = await _db.orgsForArticle(original.id);
        final locs = await _db.locationsForArticle(original.id);

        // Create new article with new ID
        final newId = 'local-${DateTime.now().millisecondsSinceEpoch}';
        final duplicated = ArticleModel(
          id: newId,
          title: '[Salinan] ${original.title}',
          url: original.url,
          canonicalUrl: null, // Clear canonical URL to avoid duplicates
          mediaId: original.mediaId,
          kind: original.kind,
          publishedAt: original.publishedAt,
          description: original.description,
          descriptionDelta: original.descriptionDelta,
          excerpt: original.excerpt,
          imagePath: original.imagePath,
          tags: original.tags,
        );

        // Save duplicated article
        await _db.upsertArticle(duplicated);

        // Duplicate all relations
        final authorIds = <int>[];
        for (final name in authors) {
          authorIds.add(await _db.upsertAuthorByName(name));
        }
        await _db.setArticleAuthors(newId, authorIds);

        final peopleIds = <int>[];
        for (final name in people) {
          peopleIds.add(await _db.upsertPersonByName(name));
        }
        await _db.setArticlePeople(newId, peopleIds);

        final orgIds = <int>[];
        for (final name in orgs) {
          orgIds.add(await _db.upsertOrganizationByName(name));
        }
        await _db.setArticleOrganizations(newId, orgIds);

        final locIds = <int>[];
        for (final name in locs) {
          locIds.add(await _db.upsertLocationByName(name));
        }
        await _db.setArticleLocations(newId, locIds);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Artikel berhasil diduplikat'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 2),
            ),
          );

          // Navigate back to list
          Navigator.of(context).pop(true);
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Gagal menduplikat artikel: ${e.toString()}'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 4),
            ),
          );
        }
      }
    }
  }

  Future<void> _deleteArticle() async {
    final shouldDelete = await showDialog<bool>(
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
                    color: const Color(0xFFEF4444).withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.delete_outline,
                    size: 36,
                    color: Color(0xFFEF4444),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Hapus Artikel?',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: DS.text,
                      ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Artikel "${widget.article.title}" akan dihapus secara permanen. Tindakan ini tidak dapat dibatalkan.',
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
                        child: const Text('Hapus'),
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

    if (shouldDelete == true && mounted) {
      try {
        await _db.init();

        // Delete the article and all its relations
        await _db.deleteArticle(widget.article.id);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Artikel berhasil dihapus'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 2),
            ),
          );

          // Navigate back to list
          Navigator.of(context).pop(true);
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Gagal menghapus artikel: ${e.toString()}'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 4),
            ),
          );
        }
      }
    }
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

  Future<void> _createQuoteFromClipboard() async {
    try {
      // Get text from clipboard
      final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
      final text = clipboardData?.text ?? '';

      if (text.trim().isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Clipboard kosong. Silakan select & copy text dari artikel terlebih dahulu.'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 3),
          ),
        );
        return;
      }

      // Call create quote post with clipboard text
      await _createQuotePost(text);
    } catch (e) {
      debugPrint('Error reading clipboard: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error membaca clipboard: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _createQuotePost(String selectedText) async {
    if (selectedText.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tidak ada teks yang dipilih'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Get the appropriate API key based on selected model
    String? apiKey;
    if (_selectedAIModel == 'openai') {
      apiKey = _cachedOpenAIKey;
    } else if (_selectedAIModel == 'gemini') {
      apiKey = _cachedGeminiKey;
    }

    // Check if API key is cached, if not show dialog
    if (apiKey == null || apiKey.trim().isEmpty) {
      apiKey = await _showApiKeyDialog();
      if (apiKey == null || apiKey.trim().isEmpty) {
        return;
      }
      // Save API key for future use
      await _saveApiKey(apiKey);
    }

    // Navigate to confirmation page instead of directly generating
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => QuoteConfirmationPage(
          initialText: selectedText,
          apiKey: apiKey!, // Safe to use ! here after null check
          aiModel: _selectedAIModel,
        ),
      ),
    );
  }

  Future<String?> _showApiKeyDialog() async {
    final controller = TextEditingController();
    return showDialog<String>(
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
                    Icons.key,
                    size: 36,
                    color: DS.accent,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'OpenAI API Key',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: DS.text,
                      ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Masukkan OpenAI API key Anda untuk generate quote image.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: DS.textDim,
                      ),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: controller,
                  obscureText: true,
                  decoration: InputDecoration(
                    hintText: 'sk-...',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                ),
                const SizedBox(height: 28),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.of(context).pop(null),
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
                        onPressed: () {
                          Navigator.of(context).pop(controller.text);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: DS.accent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: const Text('Generate'),
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
            tooltip: 'AI Settings',
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AISettingsPage()),
              );
              // Reload settings after returning from settings page
              await _loadApiKey();
            },
            icon: const Icon(Icons.settings),
          ),
          IconButton(
            tooltip: 'Create Quote Post (dari clipboard)',
            onPressed: _createQuoteFromClipboard,
            icon: const Icon(Icons.format_quote),
          ),
          IconButton(
            tooltip: 'Duplikat',
            onPressed: () => _duplicateArticle(),
            icon: const Icon(Icons.content_copy),
          ),
          IconButton(
            tooltip: 'Hapus',
            onPressed: () => _deleteArticle(),
            icon: const Icon(Icons.delete),
          ),
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
                // Update widget.article with latest data
                widget.article.title = latest.title;
                widget.article.url = latest.url;
                widget.article.canonicalUrl = latest.canonicalUrl;
                widget.article.mediaId = latest.mediaId;
                widget.article.kind = latest.kind;
                widget.article.publishedAt = latest.publishedAt;
                widget.article.descriptionDelta = latest.descriptionDelta;
                widget.article.description = latest.description;
                widget.article.excerpt = latest.excerpt;
                widget.article.imagePath = latest.imagePath;
                widget.article.tags = latest.tags;

                // Update _fullArticle to trigger content refresh
                _fullArticle = latest;

                setState(() {
                  _tagsFuture = _loadTags();
                });

                // Await prepareDesc to ensure HTML content is updated before rebuild
                await _prepareDesc();
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

                    // Get ImageProvider for preview with error handling
                    late ImageProvider imageProvider;
                    try {
                      if (a.imagePath!.startsWith('http')) {
                        imageProvider = NetworkImage(a.imagePath!);
                      } else {
                        final file = File(a.imagePath!);
                        if (!file.existsSync()) {
                          return const SizedBox.shrink();
                        }
                        imageProvider = FileImage(file);
                      }
                    } catch (e) {
                      // If we can't create the ImageProvider, return empty space
                      return const SizedBox.shrink();
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
                  Chip(label: Text(a.kind == 'opini' ? 'Opini' : 'Artikel')),
                ],
              ]),

              // canonical URL removed to avoid duplication with main URL
              // Show loading indicator while full article is being loaded
              if (_loadingFullArticle) ...[
                const SizedBox(height: Spacing.md),
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24.0),
                    child: Column(
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 12),
                        Text('Memuat konten artikel...', style: TextStyle(color: Colors.grey)),
                      ],
                    ),
                  ),
                ),
              ]
              // Show excerpt only when there is no rich description to avoid duplication
              else if ((a.excerpt != null && a.excerpt!.trim().isNotEmpty) &&
                  (_renderDesc == null || _renderDesc!.trim().isEmpty)) ...[
                const SizedBox(height: Spacing.md),
                // Render excerpt as plain text (usually short summary)
                Text(a.excerpt!, style: TextStyle(color: DS.text)),
              ]
              else if (_renderDesc != null && _renderDesc!.trim().isNotEmpty) ...[
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
