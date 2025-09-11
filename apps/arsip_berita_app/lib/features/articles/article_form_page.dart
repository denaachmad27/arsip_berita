import 'package:flutter/material.dart';
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

  bool get _isEditing => widget.article != null;

  @override
  void initState() {
    super.initState();
    if (_isEditing) {
      _prefillFromArticle(widget.article!);
    }
  }

  Future<void> _prefillFromArticle(ArticleModel a) async {
    _title.text = a.title;
    _url.text = a.url;
    _canonical = a.canonicalUrl;
    _desc.text = a.description ?? '';
    _excerpt.text = a.excerpt ?? '';
    _date = a.publishedAt;
    _kind = a.kind ?? 'artikel';
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
  }

  Future<void> _extract() async {
    setState(() { _loading = true; _error = null; });
    try {
      await widget.db.init();
      final svc = MetadataExtractor();
      final meta = await svc.fetch(_url.text.trim());
      if (meta != null) {
        _canonical = meta.canonicalUrl;
        if ((_title.text).isEmpty && (meta.title ?? '').isNotEmpty) _title.text = meta.title!;
        if ((_excerpt.text).isEmpty && (meta.excerpt ?? '').isNotEmpty) _excerpt.text = meta.excerpt!;
        if ((_desc.text).isEmpty && (meta.description ?? '').isNotEmpty) _desc.text = meta.description!;
      }
      // local dedupe by canonical URL
      if (_canonical != null) {
        final existingId = await widget.db.findArticleIdByCanonicalUrl(_canonical!);
        if (existingId != null && (!_isEditing || existingId != widget.article!.id)) {
          _error = 'Artikel dengan canonical_url sudah ada: $_canonical';
        }
      }
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) setState(() { _loading = false; });
    }
  }

  Future<void> _save() async {
    await widget.db.init();
    int? mediaId;
    if (_mediaName.text.trim().isNotEmpty) {
      mediaId = await widget.db.upsertMedia(_mediaName.text.trim(), _mediaType);
    }
    final a = ArticleModel(
      id: _isEditing ? widget.article!.id : 'local-${DateTime.now().millisecondsSinceEpoch}',
      title: _title.text.trim(),
      url: _url.text.trim(),
      canonicalUrl: _canonical?.trim().isEmpty == true ? null : _canonical,
      mediaId: mediaId,
      kind: _kind,
      description: _desc.text.trim().isEmpty ? null : _desc.text.trim(),
      excerpt: _excerpt.text.trim().isEmpty ? null : _excerpt.text.trim(),
      publishedAt: _date,
    );
    await widget.db.upsertArticle(a);
    // Upsert tags and link
    final authorIds = <int>[];
    for (final name in _authorTags.map((e) => e.trim()).where((e) => e.isNotEmpty)) {
      authorIds.add(await widget.db.upsertAuthorByName(name));
    }
    await widget.db.setArticleAuthors(a.id, authorIds);

    final peopleIds = <int>[];
    for (final name in _peopleTags.map((e) => e.trim()).where((e) => e.isNotEmpty)) {
      peopleIds.add(await widget.db.upsertPersonByName(name));
    }
    await widget.db.setArticlePeople(a.id, peopleIds);

    final orgIds = <int>[];
    for (final name in _orgTags.map((e) => e.trim()).where((e) => e.isNotEmpty)) {
      orgIds.add(await widget.db.upsertOrganizationByName(name));
    }
    await widget.db.setArticleOrganizations(a.id, orgIds);

    final locIds = <int>[];
    for (final name in _locationTags.map((e) => e.trim()).where((e) => e.isNotEmpty)) {
      locIds.add(await widget.db.upsertLocationByName(name));
    }
    await widget.db.setArticleLocations(a.id, locIds);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DS.bg,
      body: UiScaffold(
        title: _isEditing ? 'Edit Artikel' : 'Tambah Artikel',
        actions: [
          UiButton(label: 'Simpan', icon: Icons.save, onPressed: _loading ? null : _save),
        ],
        child: PageContainer(child: ListView(children: [
          SectionCard(
            title: 'Sumber',
            child: Column(children: [
              UiInput(controller: _url, hint: 'Link artikel', prefix: Icons.link, suffix: InkWell(onTap: _loading ? null : _extract, borderRadius: BorderRadius.circular(8), child: const Padding(padding: EdgeInsets.all(8), child: Icon(Icons.auto_fix_high)))),
              const SizedBox(height: Spacing.md),
              UiInput(controller: _title, hint: 'Judul'),
              const SizedBox(height: Spacing.sm),
              _KindChips(value: _kind, onChanged: (v) => setState(() => _kind = v ?? 'artikel')),
            ]),
          ),
          const SizedBox(height: Spacing.lg),
          SectionCard(
            title: 'Media & Tanggal',
            child: Column(children: [
              Row(children: [
                Expanded(child: UiInput(controller: _mediaName, hint: 'Nama Media', prefix: Icons.apartment)),
                const SizedBox(width: Spacing.sm),
                Expanded(child: _MediaTypeChips(value: _mediaType, onChanged: (v) => setState(() => _mediaType = v ?? 'online'))),
              ]),
              const SizedBox(height: Spacing.md),
              Row(children: [
                Expanded(child: Text(_date == null ? 'Tanggal: -' : 'Tanggal: ${_date!.toIso8601String().substring(0,10)}')),
                const SizedBox(width: Spacing.sm),
                UiButton(label: 'Pilih Tanggal', icon: Icons.event, primary: false, onPressed: () async {
                  final now = DateTime.now();
                  final d = await showDatePicker(context: context, firstDate: DateTime(1990), lastDate: DateTime(now.year+1), initialDate: now);
                  if (d != null) setState(() => _date = d);
                }),
              ]),
            ]),
          ),
          const SizedBox(height: Spacing.lg),
          SectionCard(
            title: 'Konten',
            child: Column(children: [
              UiInput(controller: _excerpt, hint: 'Excerpt'),
              const SizedBox(height: Spacing.md),
              UiTextArea(controller: _desc, hint: 'Deskripsi', minLines: 5, maxLines: 12),
            ]),
          ),
          const SizedBox(height: Spacing.lg),
          SectionCard(
            title: 'Tag',
            child: Column(children: [
              TagEditor(
                label: 'Lokasi',
                controller: _locationInput,
                tags: _locationTags,
                onAdded: (v){ setState(() => _locationTags.add(v)); },
                onRemoved: (v){ setState(() => _locationTags.remove(v)); },
                suggestionFetcher: (text) async { await widget.db.init(); return widget.db.suggestLocations(text); },
              ),
              const SizedBox(height: Spacing.md),
              TagEditor(
                label: 'Penulis',
                controller: _authorInput,
                tags: _authorTags,
                onAdded: (v){ setState(() => _authorTags.add(v)); },
                onRemoved: (v){ setState(() => _authorTags.remove(v)); },
                suggestionFetcher: (text) async { await widget.db.init(); return widget.db.suggestAuthors(text); },
              ),
              const SizedBox(height: Spacing.md),
              TagEditor(
                label: 'Tokoh',
                controller: _peopleInput,
                tags: _peopleTags,
                onAdded: (v){ setState(() => _peopleTags.add(v)); },
                onRemoved: (v){ setState(() => _peopleTags.remove(v)); },
                suggestionFetcher: (text) async { await widget.db.init(); return widget.db.suggestPeople(text); },
              ),
              const SizedBox(height: Spacing.md),
              TagEditor(
                label: 'Organisasi',
                controller: _orgsInput,
                tags: _orgTags,
                onAdded: (v){ setState(() => _orgTags.add(v)); },
                onRemoved: (v){ setState(() => _orgTags.remove(v)); },
                suggestionFetcher: (text) async { await widget.db.init(); return widget.db.suggestOrganizations(text); },
              ),
            ]),
          ),
          const SizedBox(height: Spacing.lg),
          if (_canonical != null) Text('Canonical URL: $_canonical', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: DS.textDim)),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: Spacing.sm), child: Text(_error!, style: const TextStyle(color: Colors.red))),
          const SizedBox(height: Spacing.xxl),
        ])),
      ),
    );
  }
}

class _MediaTypeChips extends StatelessWidget {
  final String value; final ValueChanged<String?> onChanged;
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
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: (value == t.$1 ? ((t.$1 == 'online' || t.$1 == 'tv') ? DS.accentLite : DS.accent2Lite) : DS.surface),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: DS.border),
                ),
                child: Text(t.$2, style: TextStyle(color: value == t.$1 ? ((t.$1 == 'online' || t.$1 == 'tv') ? DS.accent : DS.accent2) : DS.text)),
              ),
            ),
          ),
        ]
      ]),
    );
  }
}

class _KindChips extends StatelessWidget {
  final String value; final ValueChanged<String?> onChanged;
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
              child: Text(k.$2, style: TextStyle(color: value == k.$1 ? DS.accent : DS.text)),
            ),
          ),
        ),
      ]
    ]);
  }
}
