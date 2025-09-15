import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
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
import 'package:rich_editor/rich_editor.dart';

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
  final _descEditorKey = GlobalKey<RichEditorState>();

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
    // Ensure rich editor shows existing description when editing
    if (!kIsWeb && (_desc.text.trim().isNotEmpty)) {
      void apply() async {
        try { await _descEditorKey.currentState?.setHtml(_desc.text.trim()); } catch (_) {}
      }
      WidgetsBinding.instance.addPostFrameCallback((_) { apply(); });
      // Retry a few times to wait for WebView to be fully ready
      Future.delayed(const Duration(milliseconds: 200), apply);
      Future.delayed(const Duration(milliseconds: 600), apply);
      Future.delayed(const Duration(milliseconds: 1200), apply);
    }
  }

  Future<void> _pickImage() async {
    setState(() { _error = null; });
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
        _pickedImageExt = (f.extension ?? '').isNotEmpty ? f.extension!.toLowerCase() : null;
        _removeImage = false; // since we pick a new one
      });
    } catch (e) {
      setState(() { _error = e.toString(); });
    }
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
        // Also push extracted content into the rich editor
        final cand = ((meta.description ?? '').trim().isNotEmpty)
            ? meta.description!.trim()
            : (meta.excerpt ?? '').trim();
        if (!kIsWeb && cand.isNotEmpty) {
          await _descEditorKey.currentState?.setHtml(cand);
        }
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
    // Capture rich content HTML from the editor or fallback
    String? descHtml;
    if (kIsWeb) {
      descHtml = _desc.text.trim().isEmpty ? null : _desc.text.trim();
    } else {
      try {
        descHtml = (await _descEditorKey.currentState?.getHtml())?.trim();
        if (descHtml != null && descHtml!.isEmpty) descHtml = null;
      } catch (_) {
        descHtml = _desc.text.trim().isEmpty ? null : _desc.text.trim();
      }
    }
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
      description: descHtml,
      excerpt: _excerpt.text.trim().isEmpty ? null : _excerpt.text.trim(),
      publishedAt: _date,
      imagePath: _isEditing ? widget.article!.imagePath : null,
    );
    // Handle image save/delete
    if (_pickedImageBytes != null && _pickedImageBytes!.isNotEmpty) {
      try {
        final ext = (_pickedImageExt ?? 'jpg').replaceAll('.', '');
        final savedPath = await saveImageForArticle(a.id, _pickedImageBytes!, ext: ext);
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
              // Excerpt field hidden per request; still kept in state for storage if needed
              // Use rich editor (mobile/desktop); fallback to textarea on Web
              Builder(builder: (context) {
                if (kIsWeb) {
                  return UiTextArea(controller: _desc, hint: 'Deskripsi', minLines: 5, maxLines: 12);
                }
                return _KeepAlive(
                  child: Container(
                    height: 320,
                    decoration: BoxDecoration(
                      border: Border.all(color: DS.border),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: RichEditor(
                        key: _descEditorKey,
                        editorOptions: RichEditorOptions(
                          barPosition: BarPosition.TOP,
                          placeholder: 'Tulis deskripsi/artikel di sini...',
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ]),
          ),
          const SizedBox(height: Spacing.lg),
          SectionCard(
            title: 'Gambar',
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
                    return Image.memory(_pickedImageBytes!, height: 160, fit: BoxFit.cover);
                  } else if ((_imagePath ?? '').isNotEmpty) {
                    final w = imageFromPath(_imagePath!, height: 160, fit: BoxFit.cover);
                    if (w != null) return w;
                  }
                  return Text('Belum ada gambar', style: TextStyle(color: DS.textDim));
                }),
              ),
              const SizedBox(height: Spacing.sm),
              Row(children: [
                UiButton(label: 'Pilih Gambar', icon: Icons.image, primary: false, onPressed: _pickImage),
                const SizedBox(width: Spacing.sm),
                UiButton(label: 'Hapus', icon: Icons.delete, primary: false, onPressed: (_pickedImageBytes != null) || ((_imagePath ?? '').isNotEmpty) ? () { setState(() { _pickedImageBytes = null; _pickedImageExt = null; _removeImage = true; }); } : null),
              ]),
              if (kIsWeb) Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('Catatan: Penyimpanan gambar belum didukung di Web.', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: DS.textDim)),
              ),
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

class _KeepAlive extends StatefulWidget {
  final Widget child;
  const _KeepAlive({required this.child});
  @override
  State<_KeepAlive> createState() => _KeepAliveState();
}

class _KeepAliveState extends State<_KeepAlive> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
