import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/local/db.dart';
import '../../services/samsung_notes_folder_service.dart';
import '../../services/samsung_notes_import.dart';
import '../../ui/design.dart';

/// Dialog sinkronisasi dengan folder export Samsung Notes.
///
/// Folder dipilih sekali lewat system folder picker (SAF), izin di-persist
/// oleh sistem sehingga tetap berlaku setelah reboot. Setelah itu daftar
/// file `.sdocx` tampil langsung di dalam aplikasi tanpa file manager.
///
/// Dialog menutup dengan nilai int = jumlah artikel yang berhasil diimport.
class SamsungNotesSyncDialog extends StatefulWidget {
  final LocalDatabase db;

  const SamsungNotesSyncDialog({super.key, required this.db});

  @override
  State<SamsungNotesSyncDialog> createState() =>
      _SamsungNotesSyncDialogState();
}

class _SamsungNotesSyncDialogState extends State<SamsungNotesSyncDialog> {
  final _service = SamsungNotesFolderService();

  String? _folderUri;
  List<SamsungNoteFileInfo> _files = [];
  Map<String, bool> _importedByFile = {};
  bool _loading = true;
  bool _busy = false;
  String? _error;
  int _importedCount = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final prefs = await SharedPreferences.getInstance();
    final uri = prefs.getString(SamsungNotesFolderService.prefsFolderKey);
    if (uri == null || uri.isEmpty) {
      if (mounted) {
        setState(() {
          _folderUri = null;
          _loading = false;
        });
      }
      return;
    }
    final hasAccess = await _service.hasPersistedPermission(uri);
    if (!hasAccess) {
      await prefs.remove(SamsungNotesFolderService.prefsFolderKey);
      if (mounted) {
        setState(() {
          _folderUri = null;
          _loading = false;
          _error =
              'Akses folder tidak berlaku lagi. Pilih ulang folder export Samsung Notes.';
        });
      }
      return;
    }
    await _refresh(uri);
  }

  Future<void> _refresh(String uri) async {
    try {
      final files = (await _service.listFiles(uri))
          .where((f) => f.isSdocx && f.name.isNotEmpty)
          .toList()
        ..sort((a, b) {
          final ta = a.lastModified?.millisecondsSinceEpoch ?? 0;
          final tb = b.lastModified?.millisecondsSinceEpoch ?? 0;
          return tb.compareTo(ta);
        });
      final statuses = <String, bool>{};
      for (final file in files) {
        statuses[file.name] =
            await widget.db.existsByCanonicalUrl('sdocx://${file.name}');
      }
      if (!mounted) return;
      setState(() {
        _folderUri = uri;
        _files = files;
        _importedByFile = statuses;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Gagal membaca folder: $e';
      });
    }
  }

  Future<void> _pickFolder() async {
    final uri = await _service.pickFolder();
    if (uri == null || uri.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(SamsungNotesFolderService.prefsFolderKey, uri);
    await _refresh(uri);
  }

  Future<void> _releaseFolder() async {
    final uri = _folderUri;
    if (uri == null) return;
    await _service.releasePersistedPermission(uri);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(SamsungNotesFolderService.prefsFolderKey);
    if (!mounted) return;
    setState(() {
      _folderUri = null;
      _files = [];
      _importedByFile = {};
    });
  }

  List<SamsungNoteFileInfo> get _newFiles =>
      _files.where((f) => !(_importedByFile[f.name] ?? true)).toList();

  Future<void> _importNew() async {
    final newFiles = _newFiles;
    if (newFiles.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final sources = <SdocxImportSource>[];
      for (final file in newFiles) {
        final bytes = await _service.readBytes(file.uri);
        if (bytes != null) {
          sources.add(SdocxImportSource(fileName: file.name, bytes: bytes));
        }
      }
      final result =
          await SamsungNotesImportService().importBatch(widget.db, sources);
      _importedCount = result.imported;
      if (!mounted) return;
      final uri = _folderUri;
      if (uri != null) await _refresh(uri);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Hasil Sinkronisasi'),
          content: Text(
            'Berhasil: ${result.imported}\n'
            'Dilewati (sudah ada): ${result.skipped}\n'
            'Gagal: ${result.failed}'
            '${result.details.isEmpty ? '' : '\n\n${result.details.take(5).join('\n')}${result.details.length > 5 ? '\n...' : ''}'}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Tutup'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Gagal mengimpor: $e';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  String get _folderName {
    final uri = _folderUri ?? '';
    final last = uri.split('/').last;
    try {
      return Uri.decodeComponent(last);
    } catch (_) {
      return last;
    }
  }

  String _formatDate(DateTime d) {
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    return '$dd/$mm/${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.phone_android, size: 20),
          const SizedBox(width: 8),
          const Expanded(child: Text('Sinkronisasi Samsung Notes')),
          IconButton(
            tooltip: 'Tutup',
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.pop(context, _importedCount),
          ),
        ],
      ),
      content: SizedBox(
        width: 480,
        height: 440,
        child: _buildContent(),
      ),
      actions: _buildActions(),
    );
  }

  Widget _buildContent() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_folderUri == null) {
      return SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_error != null) ...[
              Text(
                _error!,
                style: TextStyle(color: DS.danger),
              ),
              const SizedBox(height: 12),
            ],
            const Text(
              'Android tidak mengizinkan aplikasi lain membuka penyimpanan '
              'internal Samsung Notes. Karena itu, export catatanmu satu kali:',
            ),
            const SizedBox(height: 12),
            _step(1, 'Buka Samsung Notes, pilih catatan (bisa "Semua")'),
            _step(2,
                'Tekan ⋮ (More) → Save as file → format Samsung Notes (.sdocx)'),
            _step(3, 'Pilih satu folder tujuan, mis. Download'),
            _step(4,
                'Kembali ke sini dan pilih folder itu — setelah ini aplikasi akan mengingatnya dan menampilkan catatanmu langsung di sini'),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                _folderName,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            IconButton(
              tooltip: 'Ganti folder',
              icon: const Icon(Icons.folder_open, size: 20),
              onPressed: _busy ? null : _pickFolder,
            ),
            IconButton(
              tooltip: 'Lepas akses folder',
              icon: const Icon(Icons.link_off, size: 20),
              onPressed: _busy ? null : _releaseFolder,
            ),
            IconButton(
              tooltip: 'Muat ulang',
              icon: const Icon(Icons.refresh, size: 20),
              onPressed:
                  (_busy || _folderUri == null) ? null : () => _refresh(_folderUri!),
            ),
          ],
        ),
        if (_error != null) ...[
          Text(_error!, style: TextStyle(color: DS.danger)),
          const SizedBox(height: 8),
        ],
        Expanded(
          child: _files.isEmpty
              ? Center(
                  child: Text(
                    'Tidak ada file .sdocx di folder ini.',
                    style: TextStyle(color: DS.textDim),
                  ),
                )
              : ListView.builder(
                  itemCount: _files.length,
                  itemBuilder: (context, index) {
                    final file = _files[index];
                    final imported = _importedByFile[file.name] ?? true;
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        imported ? Icons.check_circle : Icons.note_add_outlined,
                        color: imported ? DS.textDim : DS.accent2,
                        size: 20,
                      ),
                      title: Text(
                        file.name,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          color: imported ? DS.textDim : DS.text,
                        ),
                      ),
                      subtitle: file.lastModified != null
                          ? Text(
                              _formatDate(file.lastModified!),
                              style: const TextStyle(fontSize: 12),
                            )
                          : null,
                      trailing: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: imported ? DS.surface2 : DS.accent2Lite,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          imported ? 'Terimport' : 'Baru',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: imported ? DS.textDim : DS.accent2,
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _step(int number, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: DS.accentLite,
              shape: BoxShape.circle,
            ),
            child: Text(
              '$number',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: DS.accent,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }

  List<Widget> _buildActions() {
    final actions = <Widget>[];
    if (_folderUri == null) {
      actions.add(TextButton(
        onPressed: () => Navigator.pop(context, _importedCount),
        child: const Text('Tutup'),
      ));
      actions.add(FilledButton.icon(
        onPressed: _busy ? null : _pickFolder,
        icon: const Icon(Icons.folder_open, size: 18),
        label: const Text('Pilih Folder'),
      ));
      return actions;
    }

    final newCount = _newFiles.length;
    actions.add(TextButton(
      onPressed: () => Navigator.pop(context, _importedCount),
      child: const Text('Tutup'),
    ));
    actions.add(FilledButton.icon(
      onPressed: (_busy || newCount == 0) ? null : _importNew,
      icon: _busy
          ? const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.download_done, size: 18),
      label: Text(
        newCount == 0 ? 'Tidak Ada File Baru' : 'Import $newCount File Baru',
      ),
    ));
    return actions;
  }
}
