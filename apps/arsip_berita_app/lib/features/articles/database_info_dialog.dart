import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import '../../data/local/db.dart';
import '../../data/local/db_recovery_service.dart';
import '../../ui/design.dart';

class DatabaseInfoDialog extends StatefulWidget {
  final LocalDatabase db;

  const DatabaseInfoDialog({super.key, required this.db});

  @override
  State<DatabaseInfoDialog> createState() => _DatabaseInfoDialogState();
}

class _DatabaseInfoDialogState extends State<DatabaseInfoDialog> {
  late DbRecoveryService _recovery;
  DatabaseRecoveryInfo? _info;
  bool _loading = true;
  String? _error;
  DateTime? _lastScheduledBackup;

  @override
  void initState() {
    super.initState();
    _recovery = DbRecoveryService(widget.db);
    _loadInfo();
  }

  Future<void> _loadInfo() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final info = await _recovery.getDatabaseInfo();

      // Load last scheduled backup info
      final prefs = await SharedPreferences.getInstance();
      final timestamp = prefs.getInt('last_backup_timestamp');
      final lastBackup = timestamp != null
          ? DateTime.fromMillisecondsSinceEpoch(timestamp)
          : null;

      if (mounted) {
        setState(() {
          _info = info;
          _lastScheduledBackup = lastBackup;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _restoreFromLegacy() async {
    final confirmed = await _showConfirmDialog(
      'Restore dari Legacy Database?',
      'Database current akan di-backup otomatis sebelum di-restore. Proses ini tidak bisa dibatalkan.',
    );

    if (confirmed != true) return;

    try {
      await _recovery.restoreFromLegacy();
      if (mounted) {
        Navigator.of(context).pop(true); // Return true to indicate refresh needed
        _showSuccessSnackbar('Database berhasil di-restore dari legacy');
      }
    } catch (e) {
      if (mounted) {
        _showErrorDialog('Restore Gagal', e.toString());
      }
    }
  }

  Future<void> _restoreFromBackup(String backupPath, String filename) async {
    final confirmed = await _showConfirmDialog(
      'Restore dari Backup?',
      'Database current akan di-backup otomatis sebelum di-restore. Proses ini tidak bisa dibatalkan.\n\nBackup: $filename',
    );

    if (confirmed != true) return;

    try {
      await _recovery.restoreFromBackup(backupPath);
      if (mounted) {
        Navigator.of(context).pop(true); // Return true to indicate refresh needed
        _showSuccessSnackbar('Database berhasil di-restore dari backup');
      }
    } catch (e) {
      if (mounted) {
        _showErrorDialog('Restore Gagal', e.toString());
      }
    }
  }

  Future<void> _deleteBackup(BackupFileInfo backup) async {
    final confirmed = await _showConfirmDialog(
      'Hapus Backup?',
      'Apakah Anda yakin ingin menghapus backup ini?\n\n${backup.filename}\n\nProses ini tidak bisa dibatalkan.',
    );

    if (confirmed != true) return;

    try {
      await _recovery.deleteBackup(backup.path);
      await _loadInfo();
      if (mounted) {
        _showSuccessSnackbar('Backup berhasil dihapus');
      }
    } catch (e) {
      if (mounted) {
        _showErrorDialog('Hapus Gagal', e.toString());
      }
    }
  }

  Future<void> _restoreFromFile() async {
    try {
      // Pilih file menggunakan file picker
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['db', 'zip'],
        dialogTitle: 'Pilih File Database atau ZIP Backup',
      );

      if (result == null || result.files.isEmpty) {
        return; // User membatalkan
      }

      final filePath = result.files.single.path;
      if (filePath == null) {
        if (mounted) {
          _showErrorDialog('Error', 'Path file tidak valid');
        }
        return;
      }

      // Validasi file terlebih dahulu
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const AlertDialog(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Memvalidasi file...'),
              ],
            ),
          ),
        );
      }

      // Check extension untuk handling yang berbeda
      final extension = filePath.toLowerCase().split('.').last;
      final isZip = extension == 'zip';

      DatabaseValidation validation;

      if (isZip) {
        // Untuk file ZIP, langsung lakukan restore tanpa validasi detail
        // karena validasi akan dilakukan di dalam _restoreFromZip
        validation = DatabaseValidation(isValid: true, articleCount: -1); // -1 indicates unknown count for ZIP
      } else {
        // Untuk file .db, lakukan validasi normal
        validation = await _recovery.validateDatabaseFile(filePath);
      }

      if (mounted) {
        Navigator.of(context).pop(); // Tutup loading dialog
      }

      if (!isZip) {
        // Hanya check validation untuk file .db
        if (!validation.isValid) {
          if (mounted) {
            _showErrorDialog(
              'File Tidak Valid',
              'File yang dipilih bukan database yang valid.\n\n${validation.error}',
            );
          }
          return;
        }

        if (validation.articleCount == 0) {
          if (mounted) {
            _showErrorDialog(
              'Database Kosong',
              'File database tidak memiliki artikel.\n\nPilih file database lain yang berisi data.',
            );
          }
          return;
        }
      }

      // Tampilkan info dan konfirmasi
      final confirmed = await _showRestoreConfirmDialog(
        filePath: filePath,
        articleCount: isZip ? -1 : validation.articleCount, // -1 for unknown (ZIP)
      );

      if (confirmed != true) return;

      // Proses restore
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const AlertDialog(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Restoring database...'),
              ],
            ),
          ),
        );
      }

      await _recovery.restoreFromFile(filePath);

      if (mounted) {
        Navigator.of(context).pop(); // Tutup loading dialog
        Navigator.of(context).pop(true); // Tutup database info dialog, return true
        _showSuccessSnackbar('Database berhasil di-restore!');
      }
    } catch (e) {
      if (mounted) {
        // Tutup loading dialog jika masih ada
        Navigator.of(context).popUntil((route) => route is! DialogRoute || route.isFirst);
        _showErrorDialog('Restore Gagal', e.toString());
      }
    }
  }

  Future<bool?> _showRestoreConfirmDialog({
    required String filePath,
    required int articleCount,
  }) {
    final isZip = filePath.toLowerCase().endsWith('.zip');

    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Restore Database?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Anda akan melakukan restore dengan detail berikut:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            _buildConfirmInfoRow('Tipe File', isZip ? 'ZIP Backup (database + images)' : 'Database saja'),
            if (articleCount >= 0)
              _buildConfirmInfoRow('Jumlah Artikel', '$articleCount artikel')
            else
              _buildConfirmInfoRow('Jumlah Artikel', 'Akan divalidasi saat restore'),
            _buildConfirmInfoRow('File', filePath.split('/').last),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.warning_amber, size: 18, color: Colors.orange),
                      SizedBox(width: 8),
                      Text(
                        'Perhatian',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.orange,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 8),
                  Text(
                    '• Database current akan di-backup otomatis\n'
                    '• Data current akan diganti dengan data dari file\n'
                    '• Proses ini tidak bisa dibatalkan',
                    style: TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: DS.accent,
              foregroundColor: Colors.white,
            ),
            child: const Text('Ya, Restore'),
          ),
        ],
      ),
    );
  }

  Widget _buildConfirmInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: Colors.black54,
              ),
            ),
          ),
          const Text(': ', style: TextStyle(fontSize: 13)),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Future<bool?> _showConfirmDialog(String title, String message) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: DS.accent,
              foregroundColor: Colors.white,
            ),
            child: const Text('Ya, Lanjutkan'),
          ),
        ],
      ),
    );
  }

  void _showErrorDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.error_outline, color: Theme.of(context).colorScheme.error),
            const SizedBox(width: 8),
            Text(title),
          ],
        ),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Tutup'),
          ),
        ],
      ),
    );
  }

  void _showSuccessSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 700),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: DS.accent.withValues(alpha: 0.1),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: DS.accent.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.storage, color: DS.accent, size: 24),
                  ),
                  const SizedBox(width: 16),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Informasi Database',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Cek status dan restore data',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.black54,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),

            // Content
            Expanded(
              child: _loading
                  ? const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 16),
                          Text('Memuat informasi database...'),
                        ],
                      ),
                    )
                  : _error != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.error_outline,
                                    size: 64, color: Theme.of(context).colorScheme.error),
                                const SizedBox(height: 16),
                                Text(
                                  'Error',
                                  style: Theme.of(context).textTheme.titleLarge,
                                ),
                                const SizedBox(height: 8),
                                Text(_error!),
                                const SizedBox(height: 16),
                                ElevatedButton(
                                  onPressed: _loadInfo,
                                  child: const Text('Coba Lagi'),
                                ),
                              ],
                            ),
                          ),
                        )
                      : _buildContent(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    if (_info == null) return const SizedBox.shrink();

    // Debug print
    print('Database Info: legacy=${_info!.legacy?.exists}, backups=${_info!.autoBackups.length}');

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        _buildScheduledBackupInfoSection(),
        const SizedBox(height: 24),
        _buildCurrentDatabaseSection(),
        const SizedBox(height: 24),
        // Selalu tampilkan legacy section untuk debugging
        if (_info!.legacy != null) ...[
          _buildLegacyDatabaseSection(),
          const SizedBox(height: 24),
        ],
        _buildAutoBackupsSection(),
        const SizedBox(height: 24),
        _buildRestoreFromFileSection(),
        const SizedBox(height: 16),
        if (_info!.hasRecoveryOptions)
          _buildRecoveryTips()
        else
          _buildNoRecoveryOptions(),
      ],
    );
  }

  Widget _buildScheduledBackupInfoSection() {
    final dateFormat = DateFormat('dd MMM yyyy, HH:mm');
    final now = DateTime.now();
    final isToday = _lastScheduledBackup != null &&
        _lastScheduledBackup!.year == now.year &&
        _lastScheduledBackup!.month == now.month &&
        _lastScheduledBackup!.day == now.day;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.schedule, color: Colors.blue.shade700, size: 20),
              const SizedBox(width: 8),
              const Text(
                'Backup Otomatis Terjadwal',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildInfoRow('Jadwal', 'Setiap hari jam 00:00 (tengah malam)'),
          _buildInfoRow(
            'Backup Terakhir',
            _lastScheduledBackup == null
                ? 'Belum pernah backup'
                : dateFormat.format(_lastScheduledBackup!),
          ),
          _buildInfoRow(
            'Status',
            isToday ? '✅ Sudah backup hari ini' : '⏰ Menunggu jam 00:00',
          ),
          _buildInfoRow('Retensi', 'Maksimal 7 hari terakhir'),
          const SizedBox(height: 12),
          const Text(
            '💡 Backup otomatis akan menyimpan seluruh artikel setiap hari jam 00:00. File backup akan disimpan maksimal 7 hari.',
            style: TextStyle(
              fontSize: 12,
              color: Colors.black54,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCurrentDatabaseSection() {
    final current = _info!.current;
    return _buildDatabaseCard(
      title: 'Database Current',
      icon: Icons.storage,
      iconColor: DS.accent,
      info: current,
      actions: [],
    );
  }

  Widget _buildLegacyDatabaseSection() {
    final legacy = _info!.legacy!;

    // Debug print
    print('Legacy DB Info: exists=${legacy.exists}, count=${legacy.articleCount}, path=${legacy.path}');

    return _buildDatabaseCard(
      title: 'Legacy Database',
      icon: Icons.history,
      iconColor: DS.accent2,
      info: legacy,
      actions: legacy.exists && legacy.articleCount > 0
          ? [
              ElevatedButton.icon(
                onPressed: _restoreFromLegacy,
                icon: const Icon(Icons.restore),
                label: const Text('Restore dari Legacy'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: DS.accent2,
                  foregroundColor: Colors.white,
                ),
              ),
            ]
          : legacy.exists
              ? [
                  const Text(
                    'Legacy database ditemukan tapi kosong',
                    style: TextStyle(color: Colors.orange, fontSize: 12),
                  ),
                ]
              : [],
    );
  }

  Widget _buildAutoBackupsSection() {
    final backups = _info!.autoBackups;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: DS.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: DS.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.backup, color: DS.accent, size: 20),
              const SizedBox(width: 8),
              const Text(
                'Auto-Backup Files',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (backups.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: Text(
                  'Belum ada backup otomatis.\nBackup akan dibuat otomatis saat save artikel.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.black54),
                ),
              ),
            )
          else
            ...backups.map((backup) => _buildBackupItem(backup)).toList(),
        ],
      ),
    );
  }

  Widget _buildDatabaseCard({
    required String title,
    required IconData icon,
    required Color iconColor,
    required DatabaseInfo info,
    required List<Widget> actions,
  }) {
    final dateFormat = DateFormat('dd MMM yyyy, HH:mm');

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: DS.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: DS.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: iconColor, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              // Status badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: info.exists
                      ? (info.articleCount > 0 ? Colors.green.shade100 : Colors.orange.shade100)
                      : Colors.red.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  info.exists
                      ? (info.articleCount > 0 ? '✓ ${info.articleCount} artikel' : '⚠ Kosong')
                      : '✗ Tidak ada',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: info.exists
                        ? (info.articleCount > 0 ? Colors.green.shade800 : Colors.orange.shade800)
                        : Colors.red.shade800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (!info.exists)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                '❌ Database tidak ditemukan di: ${info.path}',
                style: const TextStyle(color: Colors.red, fontSize: 12),
              ),
            )
          else ...[
            _buildInfoRow('Artikel', '${info.articleCount} artikel'),
            _buildInfoRow('Ukuran', '${info.sizeKB.toStringAsFixed(2)} KB'),
            if (info.lastModified != null)
              _buildInfoRow('Modified', dateFormat.format(info.lastModified!)),
            _buildInfoRow('Path', info.path, mono: true),
          ],
          if (actions.isNotEmpty) ...[
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: actions,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBackupItem(BackupFileInfo backup) {
    final dateFormat = DateFormat('dd MMM yyyy, HH:mm');

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: DS.border.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  backup.filename,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, size: 20),
                onSelected: (value) {
                  if (value == 'restore') {
                    _restoreFromBackup(backup.path, backup.filename);
                  } else if (value == 'delete') {
                    _deleteBackup(backup);
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'restore',
                    child: Row(
                      children: [
                        Icon(Icons.restore, size: 18),
                        SizedBox(width: 8),
                        Text('Restore'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete, size: 18, color: Colors.red),
                        SizedBox(width: 8),
                        Text('Hapus', style: TextStyle(color: Colors.red)),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '📊 ${backup.articleCount} artikel • ${backup.sizeKB.toStringAsFixed(1)} KB',
            style: const TextStyle(fontSize: 12, color: Colors.black54),
          ),
          const SizedBox(height: 4),
          Text(
            '📅 ${dateFormat.format(backup.modified)}',
            style: const TextStyle(fontSize: 12, color: Colors.black54),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, {bool mono = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: Colors.black54,
              ),
            ),
          ),
          const Text(': ', style: TextStyle(fontSize: 13)),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontFamily: mono ? 'monospace' : null,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecoveryTips() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.green.shade200),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline, color: Colors.green, size: 20),
              SizedBox(width: 8),
              Text(
                'Opsi Recovery Tersedia',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.green,
                ),
              ),
            ],
          ),
          SizedBox(height: 8),
          Text(
            'Ada backup yang bisa di-restore. Pilih backup yang memiliki jumlah artikel terbanyak atau waktu modified yang sesuai.',
            style: TextStyle(fontSize: 13, color: Colors.black87),
          ),
        ],
      ),
    );
  }

  Widget _buildNoRecoveryOptions() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning_amber_outlined, color: Colors.orange, size: 20),
              SizedBox(width: 8),
              Text(
                'Tidak Ada Opsi Recovery',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.orange,
                ),
              ),
            ],
          ),
          SizedBox(height: 8),
          Text(
            'Tidak ada backup yang tersedia untuk di-restore. Pastikan untuk selalu backup data ke Google Drive secara berkala.',
            style: TextStyle(fontSize: 13, color: Colors.black87),
          ),
        ],
      ),
    );
  }

  Widget _buildRestoreFromFileSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: DS.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: DS.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.upload_file, color: DS.accent, size: 20),
              const SizedBox(width: 8),
              const Text(
                'Restore dari File Lokal',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'Upload file database (.db) atau ZIP backup dari perangkat Anda untuk melakukan restore. '
            'File akan divalidasi terlebih dahulu sebelum proses restore.\n\n'
            'Format yang didukung:\n'
            '• .db - Database saja (tanpa images)\n'
            '• .zip - Database + images (struktur: arsip_berita.db dan folder images/)',
            style: TextStyle(fontSize: 13, color: Colors.black87),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _restoreFromFile,
              icon: const Icon(Icons.upload_file),
              label: const Text('Pilih File Database/ZIP'),
              style: ElevatedButton.styleFrom(
                backgroundColor: DS.accent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.blue.shade200),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, size: 16, color: Colors.blue),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Database current akan di-backup otomatis sebelum restore. '
                    'Anda dapat restore kembali dari backup jika diperlukan.',
                    style: TextStyle(fontSize: 11, color: Colors.black87),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
