import 'dart:async';
import 'package:flutter/material.dart';
import '../../util/platform_io.dart';
import '../../data/backup/drive_backup_service.dart';
import '../../data/local/db.dart';
import '../../data/local/scheduled_backup_service.dart';
import '../../data/export_service.dart';
import '../../ui/theme.dart';
import '../../widgets/page_container.dart';
import '../../widgets/empty_state.dart';
import '../../ui/design.dart';
import '../../widgets/ui_scaffold.dart';
import '../../widgets/ui_button.dart';
import '../../widgets/ui_input.dart';
import '../../widgets/ui_chip.dart';
import '../../widgets/ui_list_item.dart';
import 'article_form_page.dart';
import 'article_detail_page.dart';
import 'database_info_dialog.dart';
import '../settings/ai_settings_page.dart';

class ArticlesListPage extends StatefulWidget {
  const ArticlesListPage({super.key});
  @override
  State<ArticlesListPage> createState() => _ArticlesListPageState();
}

enum _DriveAction { backup, restore, databaseInfo }

class _ArticlesListPageState extends State<ArticlesListPage> {
  final _db = LocalDatabase();
  final DriveBackupService _driveBackup = DriveBackupService();
  late ScheduledBackupService _scheduledBackup;
  final _q = TextEditingController();
  final _scrollController = ScrollController();
  bool _driveBusy = false;
  List<ArticleWithMedium> _results = [];
  String? _mediaType; // null = semua
  DateTime? _startDate;
  DateTime? _endDate;
  int _statTotal = 0;
  int _statMonth = 0;

  // Pagination
  static const int _pageSize = 50;
  int _currentPage = 0;
  bool _isLoadingMore = false;
  bool _hasMore = true;

  // View toggle
  bool _isGridView = false;

  @override
  void initState() {
    super.initState();
    _scheduledBackup = ScheduledBackupService(_db);
    _q.addListener(_updateClearButton);
    _init();
  }

  void _updateClearButton() {
    // Hanya rebuild untuk update tombol clear, tidak trigger search
    setState(() {});
  }

  Future<void> _init() async {
    await _db.init();
    await _scheduledBackup.initialize();
    await _search();
  }

  Future<void> _search() async {
    await _db.init();
    setState(() {
      _currentPage = 0;
      _hasMore = true;
      _results = [];
    });

    final list = await _db.searchArticles(
      q: _q.text,
      mediaType:
          (_mediaType == null || _mediaType == 'all') ? null : _mediaType,
      startDate: _startDate,
      endDate: _endDate,
      limit: _pageSize,
      offset: 0,
    );

    setState(() {
      _results = list;
      _hasMore = list.length == _pageSize;
    });
    await _recomputeStats();
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || !_hasMore) return;

    setState(() {
      _isLoadingMore = true;
    });

    await _db.init();
    final nextPage = _currentPage + 1;
    final list = await _db.searchArticles(
      q: _q.text,
      mediaType:
          (_mediaType == null || _mediaType == 'all') ? null : _mediaType,
      startDate: _startDate,
      endDate: _endDate,
      limit: _pageSize,
      offset: nextPage * _pageSize,
    );

    setState(() {
      _currentPage = nextPage;
      _results.addAll(list);
      _hasMore = list.length == _pageSize;
      _isLoadingMore = false;
    });
  }

  Future<void> _recomputeStats() async {
    await _db.init();
    final total = await _db.totalArticles();
    final month = await _db.thisMonthArticles();
    setState(() {
      _statTotal = total;
      _statMonth = month;
    });
  }

  Widget _StatCard(
      {required String label,
      required String value,
      required IconData icon,
      Color? accent}) {
    final iconBg = accent == null ? DS.accentLite : DS.accent2Lite;
    final iconColor = accent ?? DS.accent;
    return Container(
      decoration: BoxDecoration(
        color: DS.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: DS.border),
      ),
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: iconColor, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ],
      ),
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
        'id': e.article.id,
        'title': e.article.title,
        'url': e.article.url,
        'canonical_url': e.article.canonicalUrl,
        'published_at': e.article.publishedAt?.toIso8601String(),
        'description': e.article.description,
        'excerpt': e.article.excerpt,
        'media': e.medium?.name,
        'media_type': e.medium?.type,
        'kind': e.article.kind,
        'authors': authors,
        'people': people,
        'organizations': orgs,
        'locations': locs,
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
        'id': e.article.id,
        'title': e.article.title,
        'url': e.article.url,
        'canonical_url': e.article.canonicalUrl,
        'published_at': e.article.publishedAt?.toIso8601String(),
        'description': e.article.description,
        'excerpt': e.article.excerpt,
        'media': e.medium?.name,
        'media_type': e.medium?.type,
        'kind': e.article.kind,
        'authors': authors.join('; '),
        'people': people.join('; '),
        'organizations': orgs.join('; '),
        'locations': locs.join('; '),
      });
    }
    final csv = ExportService.toCsv(rows);
    _showExport(csv);
  }

  Future<void> _backupToDrive() async {
    await _runWithProgress(
      message: 'Membuat backup ke Google Drive...',
      successMessage: 'Backup berhasil disimpan ke Google Drive.',
      notificationTitle: 'Backup Google Drive',
      action: () => _driveBackup.backup(_db),
    );
  }

  Future<void> _restoreFromDrive() async {
    await _runWithProgress(
      message: 'Mengambil backup dari Google Drive...',
      successMessage: 'Restore selesai.',
      notificationTitle: 'Restore Google Drive',
      action: () async {
        await _driveBackup.restore(_db);
        await _search();
      },
    );
  }

  Future<void> _showDatabaseInfo() async {
    final shouldRefresh = await showDialog<bool>(
      context: context,
      builder: (context) => DatabaseInfoDialog(db: _db),
    );

    // Jika user melakukan restore, reset semua filter dan refresh data
    if (shouldRefresh == true && mounted) {
      setState(() {
        _mediaType = null;
        _startDate = null;
        _endDate = null;
        _q.clear();
      });
      await _search();
    }
  }

  Future<void> _runWithProgress({
    required String message,
    String? successMessage,
    String? notificationTitle,
    required Future<void> Function() action,
  }) async {
    if (_driveBusy) return;
    var progressShown = false;
    if (mounted) {
      setState(() => _driveBusy = true);
      progressShown = true;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: DS.accent.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Padding(
                      padding: EdgeInsets.all(16),
                      child: CircularProgressIndicator(strokeWidth: 3),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: DS.text,
                        ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Proses ini mungkin memerlukan beberapa saat. Mohon tunggu...',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: DS.textDim,
                        ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    String? error;
    String? info;
    var cancelled = false;
    try {
      await action();
    } on DriveBackupCancelledException catch (e) {
      cancelled = true;
      info = e.message;
    } on DriveBackupException catch (e) {
      error = e.message;
    } catch (e, st) {
      error = 'Terjadi kesalahan: $e';
      debugPrint(st.toString());
    } finally {
      if (mounted) {
        final navigator = Navigator.of(context, rootNavigator: true);
        if (progressShown && navigator.canPop()) {
          navigator.pop();
        }
        setState(() => _driveBusy = false);
      } else {
        _driveBusy = false;
      }
    }
    if (!mounted) return;
    if (cancelled) {
      if (info != null && info.isNotEmpty) {
        await _showFeedbackDialog(
          title: 'Informasi',
          message: info,
          icon: Icons.info_outline,
          accentColor: DS.accent,
        );
      }
      return;
    }
    if (error != null) {
      await _showFeedbackDialog(
        title: 'Gagal',
        message: error,
        icon: Icons.error_outline,
        accentColor: Theme.of(context).colorScheme.error,
      );
    } else if (successMessage != null) {
      await _showFeedbackDialog(
        title: notificationTitle ?? 'Berhasil',
        message: successMessage,
        icon: Icons.cloud_done_outlined,
        accentColor: DS.accent,
      );
    }
  }

  Future<void> _showFeedbackDialog({
    required String title,
    required String message,
    required IconData icon,
    required Color accentColor,
  }) {
    if (!mounted) {
      return Future<void>.value();
    }
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (_) => Dialog(
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
                    color: accentColor.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: 36, color: accentColor),
                ),
                const SizedBox(height: 20),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: DS.text,
                      ),
                ),
                const SizedBox(height: 12),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: DS.textDim,
                      ),
                ),
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context, rootNavigator: true).pop(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accentColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text('Tutup'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showExport(String s) {
    showDialog(
        context: context,
        builder: (_) => AlertDialog(
              title: const Text('Export Preview'),
              content: SizedBox(
                  width: 600, child: SingleChildScrollView(child: Text(s))),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Close'))
              ],
            ));
  }

  @override
  void dispose() {
    _q.dispose();
    _scrollController.dispose();
    _scheduledBackup.dispose();
    unawaited(_driveBackup.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DS.bg,
      body: UiScaffold(
        title: 'Arsip Berita',
        actions: [
          PopupMenuButton<_DriveAction>(
            tooltip: 'Backup & Restore',
            icon: const Icon(Icons.cloud_outlined),
            onSelected: (value) {
              switch (value) {
                case _DriveAction.backup:
                  _backupToDrive();
                  break;
                case _DriveAction.restore:
                  _restoreFromDrive();
                  break;
                case _DriveAction.databaseInfo:
                  _showDatabaseInfo();
                  break;
              }
            },
            enabled: !_driveBusy,
            itemBuilder: (context) => [
              PopupMenuItem<_DriveAction>(
                value: _DriveAction.backup,
                child: const ListTile(
                  dense: true,
                  leading: Icon(Icons.cloud_upload_outlined),
                  title: Text('Backup ke Google Drive'),
                ),
              ),
              PopupMenuItem<_DriveAction>(
                value: _DriveAction.restore,
                child: const ListTile(
                  dense: true,
                  leading: Icon(Icons.cloud_download_outlined),
                  title: Text('Restore dari Google Drive'),
                ),
              ),
              const PopupMenuDivider(),
              PopupMenuItem<_DriveAction>(
                value: _DriveAction.databaseInfo,
                child: const ListTile(
                  dense: true,
                  leading: Icon(Icons.storage),
                  title: Text('Informasi Database'),
                ),
              ),
            ],
          ),
          const SizedBox(width: Spacing.sm),
          IconButton(
            tooltip: 'Pengaturan AI',
            icon: const Icon(Icons.auto_awesome_outlined),
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AISettingsPage()),
              );
            },
          ),
          const SizedBox(width: Spacing.sm),
          UiButton(
              label: 'Tambah',
              icon: Icons.add,
              onPressed: () async {
                await Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => ArticleFormPage(db: _db)));
                await _search();
              }),
        ],
        child: PageContainer(
            child: Column(children: [
          // Search input moved under date filter; export icons hidden for now
          const SizedBox(height: Spacing.md),
          Row(children: [
            Expanded(
                child: _StatCard(
                    label: 'Total',
                    value: _statTotal.toString(),
                    icon: Icons.newspaper,
                    accent: DS.accent)),
            const SizedBox(width: Spacing.sm),
            Expanded(
                child: _StatCard(
                    label: 'Bulan Ini',
                    value: _statMonth.toString(),
                    icon: Icons.calendar_today,
                    accent: DS.accent2)),
          ]),
          const SizedBox(height: Spacing.md),
          LayoutBuilder(builder: (context, constraints) {
            final w = constraints.maxWidth;
            final isNarrow = w < 600;
            if (isNarrow) {
              return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _MediaChips(
                        value: _mediaType,
                        onChanged: (v) {
                          setState(() => _mediaType = v);
                          _search();
                        }),
                      const SizedBox(height: Spacing.sm),
                    Row(
                      children: [
                        Expanded(
                          child: UiInput(
                            controller: _q,
                            hint: 'Cari artikel, tokoh, organisasi, lokasi...',
                            prefix: Icons.search,
                            suffix: _q.text.isNotEmpty
                                ? InkWell(
                                    onTap: () {
                                      setState(() {
                                        _q.clear();
                                      });
                                      _search();
                                    },
                                    borderRadius: BorderRadius.circular(10),
                                    child: const Padding(
                                      padding: EdgeInsets.all(4),
                                      child: Icon(Icons.close, size: 18),
                                    ),
                                  )
                                : null,
                            onSubmitted: (_) => _search(),
                          ),
                        ),
                        const SizedBox(width: Spacing.sm),
                        // Date Range Icon Button for narrow screen
                        InkWell(
                          onTap: () async {
                            final now = DateTime.now();
                            final range = await showDateRangePicker(
                              context: context,
                              firstDate: DateTime(1990),
                              lastDate: DateTime(now.year + 1),
                              initialDateRange:
                                  _startDate == null && _endDate == null
                                      ? null
                                      : DateTimeRange(
                                          start: _startDate ??
                                              now.subtract(const Duration(days: 7)),
                                          end: _endDate ?? now),
                            );
                            if (range != null) {
                              setState(() {
                                _startDate = range.start;
                                _endDate = range.end;
                              });
                              _search();
                            }
                          },
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: (_startDate != null || _endDate != null)
                                  ? DS.accent.withValues(alpha: 0.1)
                                  : DS.surface,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: DS.border),
                            ),
                            child: Column(
                              children: [
                                Icon(
                                  Icons.date_range,
                                  size: 20,
                                  color: (_startDate != null || _endDate != null)
                                      ? DS.accent
                                      : DS.textDim,
                                ),
                                if (_startDate != null || _endDate != null) ...[
                                  const SizedBox(height: 2),
                                  Container(
                                    width: 6,
                                    height: 6,
                                    decoration: BoxDecoration(
                                      color: DS.accent,
                                      borderRadius: BorderRadius.circular(3),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: Spacing.sm),
                        UiButton(
                          label: 'Cari',
                          icon: Icons.search,
                          onPressed: _search,
                        ),
                      ],
                    ),
                    // Reload icon removed; pull-to-refresh is used instead
                  ]);
            }
            return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(children: [
                    Expanded(
                        child: _MediaChips(
                            value: _mediaType,
                            onChanged: (v) {
                              setState(() => _mediaType = v);
                              _search();
                            })),
                    const SizedBox(width: Spacing.sm),
                    // Date Range Button for wide screen
                    Expanded(
                        child: InkWell(
                          onTap: () async {
                            final now = DateTime.now();
                            final range = await showDateRangePicker(
                              context: context,
                              firstDate: DateTime(1990),
                              lastDate: DateTime(now.year + 1),
                              initialDateRange:
                                  _startDate == null && _endDate == null
                                      ? null
                                      : DateTimeRange(
                                          start: _startDate ??
                                              now.subtract(const Duration(days: 7)),
                                          end: _endDate ?? now),
                            );
                            if (range != null) {
                              setState(() {
                                _startDate = range.start;
                                _endDate = range.end;
                              });
                              _search();
                            }
                          },
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                            decoration: BoxDecoration(
                              color: (_startDate != null || _endDate != null)
                                  ? DS.accent.withValues(alpha: 0.1)
                                  : DS.surface,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: DS.border),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.date_range,
                                  size: 20,
                                  color: (_startDate != null || _endDate != null)
                                      ? DS.accent
                                      : DS.textDim,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _startDate == null && _endDate == null
                                        ? 'Rentang Tanggal'
                                        : '${_startDate!.toIso8601String().substring(0, 10)} - ${_endDate!.toIso8601String().substring(0, 10)}',
                                    style: TextStyle(
                                      color: (_startDate != null || _endDate != null)
                                          ? DS.accent
                                          : DS.text,
                                      fontSize: 14,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (_startDate != null || _endDate != null) ...[
                                  const SizedBox(width: 8),
                                  InkWell(
                                    onTap: () {
                                      setState(() {
                                        _startDate = null;
                                        _endDate = null;
                                      });
                                      _search();
                                    },
                                    borderRadius: BorderRadius.circular(10),
                                    child: const Padding(
                                      padding: EdgeInsets.all(4),
                                      child: Icon(Icons.close, size: 18),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                    ),
                  ]),
                  const SizedBox(height: Spacing.sm),
                  Row(
                    children: [
                      Expanded(
                        child: UiInput(
                          controller: _q,
                          hint: 'Cari artikel, tokoh, organisasi, lokasi...',
                          prefix: Icons.search,
                          suffix: _q.text.isNotEmpty
                              ? InkWell(
                                  onTap: () {
                                    setState(() {
                                      _q.clear();
                                    });
                                    _search();
                                  },
                                  borderRadius: BorderRadius.circular(10),
                                  child: const Padding(
                                    padding: EdgeInsets.all(4),
                                    child: Icon(Icons.close, size: 18),
                                  ),
                                )
                              : null,
                          onSubmitted: (_) => _search(),
                        ),
                      ),
                      const SizedBox(width: Spacing.sm),
                      // Date Range Button
                      InkWell(
                        onTap: () async {
                          final now = DateTime.now();
                          final range = await showDateRangePicker(
                            context: context,
                            firstDate: DateTime(1990),
                            lastDate: DateTime(now.year + 1),
                            initialDateRange:
                                _startDate == null && _endDate == null
                                    ? null
                                    : DateTimeRange(
                                        start: _startDate ??
                                            now.subtract(const Duration(days: 7)),
                                        end: _endDate ?? now),
                          );
                          if (range != null) {
                            setState(() {
                              _startDate = range.start;
                              _endDate = range.end;
                            });
                            _search();
                          }
                        },
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: (_startDate != null || _endDate != null)
                                ? DS.accent.withValues(alpha: 0.1)
                                : DS.surface,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: DS.border),
                          ),
                          child: Column(
                            children: [
                              Icon(
                                Icons.date_range,
                                size: 20,
                                color: (_startDate != null || _endDate != null)
                                    ? DS.accent
                                    : DS.textDim,
                              ),
                              if (_startDate != null || _endDate != null) ...[
                                const SizedBox(height: 2),
                                Container(
                                  width: 6,
                                  height: 6,
                                  decoration: BoxDecoration(
                                    color: DS.accent,
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: Spacing.sm),
                      UiButton(
                        label: 'Cari',
                        icon: Icons.search,
                        onPressed: _search,
                      ),
                    ],
                  ),
                ]);
          }),
          const SizedBox(height: Spacing.md),

          // Toggle View Buttons
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            decoration: BoxDecoration(
              color: DS.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: DS.border),
            ),
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () {
                      setState(() {
                        _isGridView = false;
                      });
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: !_isGridView ? DS.accent.withValues(alpha: 0.1) : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.view_list,
                            size: 18,
                            color: !_isGridView ? DS.accent : DS.textDim,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Daftar',
                            style: TextStyle(
                              color: !_isGridView ? DS.accent : DS.textDim,
                              fontWeight: !_isGridView ? FontWeight.w600 : FontWeight.normal,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: InkWell(
                    onTap: () {
                      setState(() {
                        _isGridView = true;
                      });
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: _isGridView ? DS.accent.withValues(alpha: 0.1) : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.grid_view,
                            size: 18,
                            color: _isGridView ? DS.accent : DS.textDim,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Grid',
                            style: TextStyle(
                              color: _isGridView ? DS.accent : DS.textDim,
                              fontWeight: _isGridView ? FontWeight.w600 : FontWeight.normal,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: Spacing.md),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                await _search();
              },
              child: _results.isEmpty && !_isLoadingMore
                  ? ListView(
                      controller: _scrollController,
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        EmptyState(
                          title: 'Belum ada artikel',
                          subtitle:
                              'Tambah artikel pertama Anda atau lakukan pencarian.',
                          action: UiButton(
                              label: 'Tambah Artikel',
                              icon: Icons.add,
                              onPressed: () async {
                                await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                        builder: (_) =>
                                            ArticleFormPage(db: _db)));
                                await _search();
                              }),
                        ),
                      ],
                    )
                  : _isGridView
                      ? _buildGridView()
                      : _buildListView(),
            ),
          ),
        ])),
      ),
    );
  }

  // Method untuk membangun list view
  Widget _buildListView() {
    return ListView.separated(
      controller: _scrollController,
      itemCount: _results.length + (_hasMore || _isLoadingMore ? 1 : 0),
      separatorBuilder: (_, __) => const SizedBox(height: Spacing.sm),
      itemBuilder: (ctx, i) {
        // Load More button or loading indicator at the end
        if (i == _results.length) {
          if (_isLoadingMore) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        valueColor: AlwaysStoppedAnimation<Color>(DS.accent),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Memuat artikel...',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: DS.textDim),
                    ),
                  ],
                ),
              ),
            );
          }

          // Show Load More button if there's more data
          if (_hasMore) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: UiButton(
                  label: 'Muat Lebih Banyak',
                  icon: Icons.refresh,
                  onPressed: _loadMore,
                ),
              ),
            );
          }

          return const SizedBox.shrink();
        }

        final a = _results[i].article;
        final m = _results[i].medium;
        final type = m?.type;
        final ac = (type == 'online' || type == 'tv') ? DS.accent : DS.accent2;
        Widget? thumb = (a.imagePath ?? '').isNotEmpty
            ? imageFromPath(a.imagePath!, width: 56, height: 56, fit: BoxFit.cover)
            : null;
        return FutureBuilder<List<String>>(
          future: _db.authorsForArticle(a.id),
          builder: (context, snapshot) {
            final authors = snapshot.data ?? const <String>[];
            final displayTitle = a.title.isEmpty ? '(Tanpa judul)' : a.title;

            // Buat subtitle yang lebih informatif
            String subtitle;
            if (authors.isNotEmpty) {
              subtitle = authors.join(', ');
            } else if (m?.name.isNotEmpty == true) {
              subtitle = m!.name;
            } else {
              subtitle = 'Tidak ada penulis';
            }

            return UiListItem(
              title: displayTitle,
              subtitle: subtitle,
              accentColor: ac,
              leading: thumb,
              authors: authors.isNotEmpty ? authors : null,
              mediaName: m?.name,
              publishedAt: a.publishedAt,
              onTap: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ArticleDetailPage(article: a)
                  )
                );
                // Refresh data setelah kembali dari detail
                await _search();
              },
            );
          },
        );
      },
    );
  }

  // Method untuk membangun grid view
  Widget _buildGridView() {
    return CustomScrollView(
      controller: _scrollController,
      slivers: [
        // Grid items
        SliverPadding(
          padding: const EdgeInsets.all(4),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 0.65,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                return _buildArticleGridItem(_results[index]);
              },
              childCount: _results.length,
            ),
          ),
        ),

        // Load More section as full-width row
        if (_hasMore || _isLoadingMore)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              child: _isLoadingMore
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              valueColor: AlwaysStoppedAnimation<Color>(DS.accent),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Memuat artikel...',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: DS.textDim),
                          ),
                        ],
                      ),
                    )
                  : UiButton(
                      label: 'Muat Lebih Banyak',
                      icon: Icons.refresh,
                      onPressed: _loadMore,
                    ),
            ),
          ),
      ],
    );
  }

  // Method untuk membangun grid item
  Widget _buildArticleGridItem(ArticleWithMedium articleWithMedium) {
    final a = articleWithMedium.article;
    final m = articleWithMedium.medium;
    final type = m?.type;
    final ac = (type == 'online' || type == 'tv') ? DS.accent : DS.accent2;

    return FutureBuilder<List<String>>(
      future: _db.authorsForArticle(a.id),
      builder: (context, snapshot) {
        final authors = snapshot.data ?? const <String>[];
        final displayTitle = a.title.isEmpty ? '(Tanpa judul)' : a.title;

        Widget? thumbnail = (a.imagePath ?? '').isNotEmpty
            ? imageFromPath(a.imagePath!,
                width: double.infinity, height: 120, fit: BoxFit.cover)
            : null;

        return Card(
          elevation: 2,
          margin: const EdgeInsets.all(4),
          child: InkWell(
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ArticleDetailPage(article: a)
                )
              );
              await _search();
            },
            borderRadius: BorderRadius.circular(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Image section
                Expanded(
                  flex: 3,
                  child: thumbnail != null
                    ? ClipRRect(
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                        child: thumbnail,
                      )
                    : Container(
                        decoration: BoxDecoration(
                          color: DS.surface,
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                          border: Border.all(color: DS.border),
                        ),
                        child: Center(
                          child: Icon(
                            Icons.article_outlined,
                            size: 48,
                            color: DS.textDim,
                          ),
                        ),
                      ),
                ),
                // Content section
                Expanded(
                  flex: 2,
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Title
                        Text(
                          displayTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                            color: DS.text,
                          ),
                        ),
                        const SizedBox(height: 4),
                        // Date (instead of subtitle)
                        if (a.publishedAt != null)
                          Text(
                            _formatDate(a.publishedAt!),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: DS.textDim,
                            ),
                          )
                        else
                          Text(
                            _getMediaDisplay(type),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: DS.textDim,
                            ),
                          ),
                        const Spacer(),
                        // Chips section - 2 separate rows
                        if (authors.isNotEmpty || m?.name.isNotEmpty == true) ...[
                          // Baris 1: Author chips
                          if (authors.isNotEmpty)
                            Wrap(
                              spacing: 4,
                              runSpacing: 2,
                              children: authors
                                  .take(2)
                                  .map((author) => _buildAuthorChipGrid(author))
                                  .toList(),
                            ),
                          // Baris 2: Media chip
                          if (m?.name.isNotEmpty == true) ...[
                            const SizedBox(height: 2),
                            _buildMediaChipGrid(m!.name),
                          ],
                        ] else ...[
                          // Media type indicator as fallback
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: ac.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              _getMediaDisplay(type),
                              style: TextStyle(
                                fontSize: 10,
                                color: ac,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // Helper method untuk format tanggal
  String _formatDate(DateTime date) {
    // Format tanggal: dd MMM yyyy (contoh: 18 Nov 2025)
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun',
      'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des'
    ];
    return '${date.day.toString().padLeft(2, '0')} ${months[date.month - 1]} ${date.year}';
  }

  // Helper method untuk mendapatkan display media type
  String _getMediaDisplay(String? type) {
    switch (type) {
      case 'online':
        return 'Online';
      case 'print':
        return 'Cetak';
      case 'tv':
        return 'TV';
      case 'radio':
        return 'Radio';
      case 'social':
        return 'Sosial';
      default:
        return 'Media';
    }
  }

  // Helper method untuk author chip di grid
  Widget _buildAuthorChipGrid(String author) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.blue.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.person_outline,
            size: 12,
            color: Colors.blue[700],
          ),
          const SizedBox(width: 3),
          Text(
            author,
            style: TextStyle(
              color: Colors.blue[700],
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        ],
      ),
    );
  }

  // Helper method untuk media chip di grid
  Widget _buildMediaChipGrid(String mediaName) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.green.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.business,
            size: 12,
            color: Colors.green[700],
          ),
          const SizedBox(width: 3),
          Text(
            mediaName,
            style: TextStyle(
              color: Colors.green[700],
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        ],
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
        UiChip(
            label: 'Semua',
            selected: value == null,
            onTap: () => onChanged(null),
            activeColor: DS.accent),
        const SizedBox(width: 8),
        for (final t in types) ...[
          UiChip(
            label: t.$2,
            selected: value == t.$1,
            onTap: () => onChanged(t.$1),
            activeColor:
                (t.$1 == 'online' || t.$1 == 'tv') ? DS.accent : DS.accent2,
          ),
          const SizedBox(width: 8),
        ]
      ]),
    );
  }
}

