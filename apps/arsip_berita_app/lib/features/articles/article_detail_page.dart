import 'package:flutter/material.dart';
import '../../data/local/db.dart';
import '../../widgets/page_container.dart';
import '../../widgets/section_card.dart';
import '../../ui/theme.dart';
import '../../ui/design.dart';
import '../../widgets/ui_scaffold.dart';
import '../../widgets/ui_card.dart';
import '../../ui/theme_mode.dart';

class ArticleDetailPage extends StatefulWidget {
  final ArticleModel article;
  const ArticleDetailPage({super.key, required this.article});
  @override
  State<ArticleDetailPage> createState() => _ArticleDetailPageState();
}

class _ArticleDetailPageState extends State<ArticleDetailPage> {
  final _db = LocalDatabase();
  Future<(List<String>, List<String>, List<String>)>? _tagsFuture;

  @override
  void initState() {
    super.initState();
    _db.init().then((_) {
      setState(() {
        _tagsFuture = _loadTags();
      });
    });
  }

  Future<(List<String>, List<String>, List<String>)> _loadTags() async {
    final authors = await _db.authorsForArticle(widget.article.id);
    final people = await _db.peopleForArticle(widget.article.id);
    final orgs = await _db.orgsForArticle(widget.article.id);
    return (authors, people, orgs);
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.article;
    return Scaffold(
      backgroundColor: DS.bg,
      body: UiScaffold(
        title: 'Detail Artikel',
        actions: [
          InkWell(onTap: () { ThemeController.instance.toggle(); }, borderRadius: BorderRadius.circular(10), child: Padding(padding: const EdgeInsets.all(8), child: Icon(Icons.dark_mode, color: DS.textDim))),
        ],
        child: PageContainer(child: ListView(children: [
          UiCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(a.title, style: Theme.of(context).textTheme.titleLarge?.copyWith(color: DS.text)),
              const SizedBox(height: Spacing.sm),
              Text(a.url, style: TextStyle(color: DS.textDim)),
              if (a.canonicalUrl != null) Padding(
                padding: const EdgeInsets.only(top: Spacing.xs),
                child: Text('Canonical: ${a.canonicalUrl}', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: DS.textDim)),
              ),
              if (a.excerpt != null) ...[
                const SizedBox(height: Spacing.md),
                Text(a.excerpt!, style: TextStyle(color: DS.text)),
              ],
              if (a.description != null) ...[
                const SizedBox(height: Spacing.md),
                Text(a.description!, style: TextStyle(color: DS.text)),
              ],
            ]),
          ),
          const SizedBox(height: Spacing.lg),
          FutureBuilder<(List<String>, List<String>, List<String>)>(
            future: _tagsFuture,
            builder: (context, snapshot) {
              final authors = snapshot.data?.$1 ?? const <String>[];
              final people = snapshot.data?.$2 ?? const <String>[];
              final orgs = snapshot.data?.$3 ?? const <String>[];
              return Column(children: [
                if (authors.isNotEmpty)
                  SectionCard(title: 'Penulis', child: Wrap(spacing: 8, runSpacing: 8, children: [for (final t in authors) Chip(label: Text(t))])),
                if (people.isNotEmpty) ...[
                  const SizedBox(height: Spacing.lg),
                  SectionCard(title: 'Tokoh', child: Wrap(spacing: 8, runSpacing: 8, children: [for (final t in people) Chip(label: Text(t))])),
                ],
                if (orgs.isNotEmpty) ...[
                  const SizedBox(height: Spacing.lg),
                  SectionCard(title: 'Organisasi', child: Wrap(spacing: 8, runSpacing: 8, children: [for (final t in orgs) Chip(label: Text(t))])),
                ],
              ]);
            },
          ),
          const SizedBox(height: Spacing.xxl),
        ])),
      ),
    );
  }
}
