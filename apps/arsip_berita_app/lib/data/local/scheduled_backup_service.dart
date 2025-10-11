import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'db.dart';

class ScheduledBackupService {
  static const String _lastBackupKey = 'last_backup_timestamp';
  static const String _backupEnabledKey = 'backup_enabled';

  final LocalDatabase db;
  Timer? _checkTimer;
  DateTime? _lastBackupDate;

  ScheduledBackupService(this.db);

  /// Initialize dan mulai monitoring untuk scheduled backup
  Future<void> initialize() async {
    await _loadLastBackupDate();

    // Check immediately on startup
    await _checkAndRunBackup();

    // Setup periodic check setiap 1 menit
    _checkTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      _checkAndRunBackup();
    });

    debugPrint('📅 Scheduled Backup Service initialized');
  }

  /// Load last backup date dari shared preferences
  Future<void> _loadLastBackupDate() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final timestamp = prefs.getInt(_lastBackupKey);
      if (timestamp != null) {
        _lastBackupDate = DateTime.fromMillisecondsSinceEpoch(timestamp);
        debugPrint('📅 Last backup: $_lastBackupDate');
      }
    } catch (e) {
      debugPrint('⚠️  Failed to load last backup date: $e');
    }
  }

  /// Save last backup date ke shared preferences
  Future<void> _saveLastBackupDate(DateTime date) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_lastBackupKey, date.millisecondsSinceEpoch);
      _lastBackupDate = date;
      debugPrint('✅ Saved last backup date: $date');
    } catch (e) {
      debugPrint('⚠️  Failed to save last backup date: $e');
    }
  }

  /// Check apakah perlu backup dan jalankan jika perlu
  Future<void> _checkAndRunBackup() async {
    try {
      final now = DateTime.now();

      // Check apakah sudah lewat jam 00:00 sejak backup terakhir
      if (!_shouldBackupToday(now)) {
        return;
      }

      // Check apakah sekarang sudah jam 00:00 - 00:59
      if (now.hour != 0) {
        return;
      }

      debugPrint('🔄 Running scheduled backup at ${now.toIso8601String()}');
      await _performBackup();
      await _saveLastBackupDate(now);

    } catch (e) {
      debugPrint('⚠️  Scheduled backup check failed: $e');
    }
  }

  /// Check apakah perlu backup hari ini
  bool _shouldBackupToday(DateTime now) {
    if (_lastBackupDate == null) {
      return true; // Belum pernah backup
    }

    // Check apakah last backup berbeda hari dengan sekarang
    final lastBackup = _lastBackupDate!;
    return now.year != lastBackup.year ||
           now.month != lastBackup.month ||
           now.day != lastBackup.day;
  }

  /// Perform actual backup
  Future<void> _performBackup() async {
    try {
      await db.init();

      final path = await db.databasePath();
      final file = File(path);

      if (!await file.exists()) {
        debugPrint('⚠️  Database file not found, skipping backup');
        return;
      }

      // Check apakah database ada isinya
      final articleCount = await db.totalArticles();
      if (articleCount == 0) {
        debugPrint('⚠️  Database empty, skipping backup');
        return;
      }

      // Create backup dengan format: arsip_berita.db.backup_daily_YYYYMMDD
      final now = DateTime.now();
      final dateStr = '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
      final backupPath = '$path.backup_daily_$dateStr';

      await file.copy(backupPath);

      final stat = await File(backupPath).stat();
      final sizeKB = (stat.size / 1024).toStringAsFixed(2);

      debugPrint('✅ Scheduled backup created:');
      debugPrint('   Path: $backupPath');
      debugPrint('   Size: $sizeKB KB');
      debugPrint('   Articles: $articleCount');

      // Cleanup old daily backups (keep only 7 days)
      await _cleanupOldDailyBackups();

    } catch (e) {
      debugPrint('❌ Backup failed: $e');
      rethrow;
    }
  }

  /// Hapus backup daily yang lebih dari 7 hari
  Future<void> _cleanupOldDailyBackups() async {
    try {
      final dir = await db.documentsDirectory();
      final files = await dir.list().toList();

      // Filter hanya file backup daily
      final dailyBackups = files
          .whereType<File>()
          .where((f) => p.basename(f.path).startsWith('arsip_berita.db.backup_daily_'))
          .toList();

      // Sort by modified date (newest first)
      dailyBackups.sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));

      // Hapus yang lebih dari 7
      if (dailyBackups.length > 7) {
        for (var i = 7; i < dailyBackups.length; i++) {
          await dailyBackups[i].delete();
          debugPrint('🗑️  Deleted old daily backup: ${p.basename(dailyBackups[i].path)}');
        }
      }
    } catch (e) {
      debugPrint('⚠️  Cleanup old daily backups failed: $e');
    }
  }

  /// Manual trigger backup (untuk testing atau force backup)
  Future<void> triggerManualBackup() async {
    debugPrint('🔄 Manual backup triggered');
    await _performBackup();
    await _saveLastBackupDate(DateTime.now());
  }

  /// Get info kapan backup terakhir
  DateTime? get lastBackupDate => _lastBackupDate;

  /// Get info apakah backup akan jalan hari ini
  bool get willBackupToday {
    final now = DateTime.now();
    return _shouldBackupToday(now);
  }

  /// Get info jam berapa backup akan jalan (selalu 00:00)
  String get nextBackupTime {
    if (!willBackupToday) {
      return 'Sudah backup hari ini';
    }
    return '00:00 (tengah malam)';
  }

  /// Dispose timer
  void dispose() {
    _checkTimer?.cancel();
    _checkTimer = null;
    debugPrint('📅 Scheduled Backup Service disposed');
  }
}
