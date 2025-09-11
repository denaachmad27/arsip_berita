import 'package:flutter/material.dart';
import '../../util/platform_io.dart';
import '../../data/local/db.dart';
import '../../data/export_service.dart';
import '../../ui/theme.dart';
import '../../widgets/page_container.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/section_card.dart';
import '../../ui/design.dart';
import '../../widgets/ui_scaffold.dart';
import '../../widgets/ui_button.dart';
import '../../widgets/ui_input.dart';
import '../../widgets/ui_chip.dart';
import '../../widgets/ui_list_item.dart';
import '../../ui/theme_mode.dart';
import 'article_form_page.dart';
import 'article_detail_page.dart';

class ArticlesListPage extends StatefulWidget {
  const ArticlesListPage({super.key});
  @override
  State<ArticlesListPage> createState() => _ArticlesListPageState();
}

class _ArticlesListPageState extends State<ArticlesListPage> {
  final _db = LocalDatabase();
  final _q = TextEditingController();
  List<ArticleWithMedium> _results = [];
  String? _mediaType; // null = semua
  DateTime? _startDate;
  DateTime? _endDate;
  int _statTotal = 0; int _statMonth = 0; int _statMedia = 0;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _db.init();
    await _search();
  }

  Future<void> _search() async {
    await _db.init();
    final list = await _db.searchArticles(
      q: _q.text,
      mediaType: (_mediaType == null || _mediaType == 'all') ? null : _mediaType,
      startDate: _startDate,
      endDate: _endDate,
    );
    setState(() { _results = list; });
    _recomputeStats();
  }

  void _recomputeStats() {
    final now = DateTime.now();
    final startMonth = DateTime(now.year, now.month, 1);
    final nextMonth = DateTime(now.year, now.month + 1, 1);
    final total = _results.length;
    final month = _results.where((e) {
      final d = e.article.publishedAt;
      if (d == null) return false;
      return !d.isBefore(startMonth) && d.isBefore(nextMonth);
    }).length;
    final media = _results.map((e) => e.medium?.id).where((id) => id != null).toSet().length;
    setState(() { _statTotal = total; _statMonth = month; _statMedia = media; });
  }

  Widget _StatCard({required String label, required String value, required IconData icon, Color? accent}) {
    return Container(
      decoration: BoxDecoration(color: DS.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: DS.border)),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 44, height: 44,
          decoration: BoxDecoration(color: (accent == null ? DS.accentLite : DS.accent2Lite), borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, color: accent ?? DS.accent),
        ),
        const SizedBox(height: 8),
        Text(label, style: Theme.of(context).textTheme.bodyMedium, textAlign: TextAlign.center),
        const SizedBox(height: 4),
        Text(value, style: Theme.of(context).textTheme.titleLarge, textAlign: TextAlign.center),
      ]),
    );
  }

  Future<void> _exportJson() async {
    await _db.init();
    final rows = <Map<String, dynamic>>[];
    for (final e in _results) {
      final authors = await _db.authorsForArticle(e.article.id);
      final people = await _db.peopleForArticle(e.article.id);
      final orgs = await _db.orgsForArticle(e.article.id);
      final locs = await _db.locationsForArticle(e.article.id);
      rows.add({
        'id': e.article.id, 'title': e.article.title, 'url': e.article.url, 'canonical_url': e.article.canonicalUrl,
        'published_at': e.article.publishedAt?.toIso8601String(), 'description': e.article.description, 'excerpt': e.article.excerpt,
        'media': e.medium?.name, 'media_type': e.medium?.type,
        'kind': e.article.kind,
        'authors': authors, 'people': people, 'organizations': orgs, 'locations': locs,
      });
    }
    final json = ExportService.toJsonPretty(rows);
    _showExport(json);
  }

  Future<void> _exportCsv() async {
    await _db.init();
    final rows = <Map<String, dynamic>>[];
    for (final e in _results) {
      final authors = await _db.authorsForArticle(e.article.id);
      final people = await _db.peopleForArticle(e.article.id);
      final orgs = await _db.orgsForArticle(e.article.id);
      final locs = await _db.locationsForArticle(e.article.id);
      rows.add({
        'id': e.article.id, 'title': e.article.title, 'url': e.article.url, 'canonical_url': e.article.canonicalUrl,
        'published_at': e.article.publishedAt?.toIso8601String(), 'description': e.article.description, 'excerpt': e.article.excerpt,
        'media': e.medium?.name, 'media_type': e.medium?.type,
        'kind': e.article.kind,
        'authors': authors.join('; '), 'people': people.join('; '), 'organizations': orgs.join('; '), 'locations': locs.join('; '),
      });
    }
    final csv = ExportService.toCsv(rows);
    _showExport(csv);
  }

  void _showExport(String s) {
    showDialog(context: context, builder: (_) => AlertDialog(
      title: const Text('Export Preview'),
      content: SizedBox(width: 600, child: SingleChildScrollView(child: Text(s))),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DS.bg,
      body: UiScaffold(
        title: 'Arsip Berita',
        actions: [
          UiButton(label: 'Tambah', icon: Icons.add, onPressed: () async {
            await Navigator.push(context, MaterialPageRoute(builder: (_) => ArticleFormPage(db: _db)));
            _search();
          }),
        ],
        child: PageContainer(child: Column(children: [
          // Search input moved under date filter; export icons hidden for now
          const SizedBox(height: Spacing.md),
          Row(children: [
            Expanded(child: _StatCard(label: 'Total Artikel', value: _statTotal.toString(), icon: Icons.newspaper, accent: DS.accent)),
            const SizedBox(width: Spacing.sm),
            Expanded(child: _StatCard(label: 'Bulan Ini', value: _statMonth.toString(), icon: Icons.calendar_today, accent: DS.accent2)),
            const SizedBox(width: Spacing.sm),
            Expanded(child: _StatCard(label: 'Media', value: _statMedia.toString(), icon: Icons.apartment, accent: DS.accent2)),
          ]),
          const SizedBox(height: Spacing.md),
          LayoutBuilder(builder: (context, constraints) {
            final w = constraints.maxWidth;
            final isNarrow = w < 520;
            if (isNarrow) {
              return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                _MediaChips(value: _mediaType, onChanged: (v) { setState(() => _mediaType = v); _search(); }),
                const SizedBox(height: Spacing.sm),
                _DateRangeInput(
                  label: _startDate == null && _endDate == null ? 'Rentang Tanggal' : '${_startDate!.toIso8601String().substring(0,10)} - ${_endDate!.toIso8601String().substring(0,10)}',
                  hasValue: _startDate != null || _endDate != null,
                  onPick: () async {
                    final now = DateTime.now();
                    final range = await showDateRangePicker(
                      context: context,
                      firstDate: DateTime(1990),
                      lastDate: DateTime(now.year + 1),
                      initialDateRange: _startDate == null && _endDate == null
                        ? null
                        : DateTimeRange(start: _startDate ?? now.subtract(const Duration(days: 7)), end: _endDate ?? now),
                    );
                    if (range != null) {
                      setState(() { _startDate = range.start; _endDate = range.end; });
                      _search();
                    }
                  },
                  onClear: () { setState(() { _startDate = null; _endDate = null; }); _search(); },
                ),
                const SizedBox(height: Spacing.sm),
                UiInput(
                  controller: _q,
                  hint: 'Cari judul…',
                  prefix: Icons.search,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  onChanged: (_) => _search(),
                  onSubmitted: (_) => _search(),
                ),
                // Reload icon removed; pull-to-refresh is used instead
              ]);
            }
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Expanded(child: _MediaChips(value: _mediaType, onChanged: (v) { setState(() => _mediaType = v); _search(); })),
                const SizedBox(width: Spacing.sm),
                Expanded(child: _DateRangeInput(
                  label: _startDate == null && _endDate == null ? 'Rentang Tanggal' : '${_startDate!.toIso8601String().substring(0,10)} - ${_endDate!.toIso8601String().substring(0,10)}',
                  hasValue: _startDate != null || _endDate != null,
                  onPick: () async {
                    final now = DateTime.now();
                    final range = await showDateRangePicker(
                      context: context,
                      firstDate: DateTime(1990),
                      lastDate: DateTime(now.year + 1),
                      initialDateRange: _startDate == null && _endDate == null
                        ? null
                        : DateTimeRange(start: _startDate ?? now.subtract(const Duration(days: 7)), end: _endDate ?? now),
                    );
                    if (range != null) {
                      setState(() { _startDate = range.start; _endDate = range.end; });
                      _search();
                    }
                  },
                  onClear: () { setState(() { _startDate = null; _endDate = null; }); _search(); },
                )),
              ]),
              const SizedBox(height: Spacing.sm),
              UiInput(
                controller: _q,
                hint: 'Cari judul…',
                prefix: Icons.search,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                onChanged: (_) => _search(),
                onSubmitted: (_) => _search(),
              ),
            ]);
          }),
          const SizedBox(height: Spacing.lg),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async { await _search(); },
              child: _results.isEmpty
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        EmptyState(
                          title: 'Belum ada artikel',
                          subtitle: 'Tambah artikel pertama Anda atau lakukan pencarian.',
                          action: UiButton(label: 'Tambah Artikel', icon: Icons.add, onPressed: () async {
                            await Navigator.push(context, MaterialPageRoute(builder: (_) => ArticleFormPage(db: _db)));
                            _search();
                          }),
                        ),
                      ],
                    )
                  : ListView.separated(
                      itemCount: _results.length,
                      separatorBuilder: (_, __) => const SizedBox(height: Spacing.sm),
                      itemBuilder: (ctx, i) {
                        final a = _results[i].article; final m = _results[i].medium;
                        final type = m?.type;
                        final ac = (type == 'online' || type == 'tv') ? DS.accent : DS.accent2;
                        Widget? thumb = (a.imagePath ?? '').isNotEmpty
                            ? imageFromPath(a.imagePath!, width: 56, height: 56, fit: BoxFit.cover)
                            : null;
                        return FutureBuilder<List<String>>(
                          future: _db.authorsForArticle(a.id),
                          builder: (context, snapshot) {
                            final authors = snapshot.data ?? const <String>[];
                            final subtitle = authors.isEmpty ? '-' : authors.join(', ');
                            return UiListItem(
                              title: a.title,
                              subtitle: subtitle,
                              accentColor: ac,
                              leading: thumb,
                              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ArticleDetailPage(article: a))),
                            );
                          },
                        );
                      },
                    ),
            ),
          ),
        ])),
      ),
    );
  }
}

class _DateRangeInput extends StatelessWidget {
  final String label;
  final bool hasValue;
  final VoidCallback onPick;
  final VoidCallback onClear;
  const _DateRangeInput({required this.label, required this.hasValue, required this.onPick, required this.onClear});
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPick,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          color: DS.surface,
          borderRadius: DS.br,
          border: Border.all(color: DS.border),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: Row(children: [
          const Icon(Icons.event),
          const SizedBox(width: 8),
          Expanded(child: Text(label)),
          if (hasValue) ...[
            const SizedBox(width: 8),
            InkWell(
              onTap: () { onClear(); },
              borderRadius: BorderRadius.circular(10),
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(Icons.close, size: 18),
              ),
            ),
          ],
        ]),
      ),
    );
  }
}

class _MediaChips extends StatelessWidget {
  final String? value;
  final ValueChanged<String?> onChanged;
  const _MediaChips({required this.value, required this.onChanged});
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
        UiChip(label: 'Semua', selected: value == null, onTap: () => onChanged(null), activeColor: DS.accent),
        const SizedBox(width: 8),
        for (final t in types) ...[
          UiChip(
            label: t.$2,
            selected: value == t.$1,
            onTap: () => onChanged(t.$1),
            activeColor: (t.$1 == 'online' || t.$1 == 'tv') ? DS.accent : DS.accent2,
          ),
          const SizedBox(width: 8),
        ]
      ]),
    );
  }
}
