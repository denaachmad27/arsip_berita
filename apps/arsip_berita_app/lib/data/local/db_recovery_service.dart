import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:archive/archive.dart';
import 'db.dart';

class DatabaseInfo {
  final String path;
  final bool exists;
  final double sizeKB;
  final DateTime? lastModified;
  final int articleCount;

  DatabaseInfo({
    required this.path,
    required this.exists,
    required this.sizeKB,
    required this.lastModified,
    required this.articleCount,
  });
}

class BackupFileInfo {
  final String path;
  final String filename;
  final DateTime modified;
  final double sizeKB;
  final int articleCount;

  BackupFileInfo({
    required this.path,
    required this.filename,
    required this.modified,
    required this.sizeKB,
    required this.articleCount,
  });
}

class DatabaseRecoveryInfo {
  final DatabaseInfo current;
  final DatabaseInfo? legacy;
  final List<BackupFileInfo> autoBackups;
  final bool hasRecoveryOptions;

  DatabaseRecoveryInfo({
    required this.current,
    required this.legacy,
    required this.autoBackups,
  }) : hasRecoveryOptions = ((legacy?.exists ?? false) && (legacy?.articleCount ?? 0) > 0) ||
          autoBackups.isNotEmpty;
}

class DbRecoveryService {
  final LocalDatabase db;

  DbRecoveryService(this.db);

  /// Mendapatkan informasi lengkap tentang database dan backup
  Future<DatabaseRecoveryInfo> getDatabaseInfo() async {
    await db.init();

    // Current database
    final currentPath = await db.databasePath();
    final currentInfo = await _getDatabaseInfo(currentPath);

    // Legacy database
    final legacyDir = await getDatabasesPath();
    final legacyPath = p.join(legacyDir, 'arsip_berita.db');
    final legacyInfo = await _getDatabaseInfo(legacyPath);

    // Auto-backups
    final backups = await _getAutoBackupFiles();

    return DatabaseRecoveryInfo(
      current: currentInfo,
      legacy: legacyInfo,
      autoBackups: backups,
    );
  }

  Future<DatabaseInfo> _getDatabaseInfo(String path) async {
    final file = File(path);
    final exists = await file.exists();

    if (!exists) {
      return DatabaseInfo(
        path: path,
        exists: false,
        sizeKB: 0,
        lastModified: null,
        articleCount: 0,
      );
    }

    final stat = await file.stat();
    final sizeKB = stat.size / 1024;
    int articleCount = 0;

    try {
      final tempDb = await openDatabase(path, readOnly: true);
      try {
        final result = await tempDb.rawQuery('SELECT COUNT(*) as c FROM articles');
        articleCount = (result.first['c'] as int?) ?? 0;
      } finally {
        await tempDb.close();
      }
    } catch (e) {
      print('Error reading database at $path: $e');
    }

    return DatabaseInfo(
      path: path,
      exists: true,
      sizeKB: sizeKB,
      lastModified: stat.modified,
      articleCount: articleCount,
    );
  }

  Future<List<BackupFileInfo>> _getAutoBackupFiles() async {
    final dir = await db.documentsDirectory();
    final files = await dir.list().toList();

    final backupFiles = <BackupFileInfo>[];

    for (final file in files) {
      if (file is File) {
        final filename = p.basename(file.path);
        // Include both auto backups and daily scheduled backups
        if (filename.startsWith('arsip_berita.db.backup_') ||
            filename.startsWith('arsip_berita.db.backup_daily_')) {
          try {
            final stat = await file.stat();
            final sizeKB = stat.size / 1024;

            int articleCount = 0;
            try {
              final tempDb = await openDatabase(file.path, readOnly: true);
              try {
                final result = await tempDb.rawQuery('SELECT COUNT(*) as c FROM articles');
                articleCount = (result.first['c'] as int?) ?? 0;
              } finally {
                await tempDb.close();
              }
            } catch (e) {
              print('Error reading backup at ${file.path}: $e');
            }

            backupFiles.add(BackupFileInfo(
              path: file.path,
              filename: filename,
              modified: stat.modified,
              sizeKB: sizeKB,
              articleCount: articleCount,
            ));
          } catch (e) {
            print('Error processing backup file ${file.path}: $e');
          }
        }
      }
    }

    // Sort by modified date (newest first)
    backupFiles.sort((a, b) => b.modified.compareTo(a.modified));

    return backupFiles;
  }

  /// Restore dari legacy database
  Future<void> restoreFromLegacy() async {
    final info = await getDatabaseInfo();

    if (info.legacy == null || !info.legacy!.exists) {
      throw Exception('Legacy database tidak ditemukan');
    }

    if (info.legacy!.articleCount == 0) {
      throw Exception('Legacy database kosong');
    }

    // Backup current database jika ada
    if (info.current.exists && info.current.articleCount > 0) {
      await _backupCurrentDatabase();
    }

    // Copy legacy ke current
    await File(info.legacy!.path).copy(info.current.path);

    // Re-init database
    await db.close();
    await db.init();
  }

  /// Restore dari auto-backup file
  Future<void> restoreFromBackup(String backupPath) async {
    final backupFile = File(backupPath);
    if (!await backupFile.exists()) {
      throw Exception('File backup tidak ditemukan');
    }

    final info = await getDatabaseInfo();

    // Backup current database jika ada
    if (info.current.exists && info.current.articleCount > 0) {
      await _backupCurrentDatabase();
    }

    // Copy backup ke current
    await backupFile.copy(info.current.path);

    // Re-init database
    await db.close();
    await db.init();
  }

  Future<void> _backupCurrentDatabase() async {
    final currentPath = await db.databasePath();
    final file = File(currentPath);
    if (!await file.exists()) return;

    final now = DateTime.now();
    final timestamp = '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';
    final backupPath = '$currentPath.backup_before_restore_$timestamp';

    await file.copy(backupPath);
    print('✅ Backed up current database to: $backupPath');
  }

  /// Restore dari file upload (bisa berupa .db atau .zip)
  /// [sourcePath] adalah path file database/zip yang ingin di-restore
  /// [validateBeforeRestore] jika true, akan validasi database terlebih dahulu
  Future<void> restoreFromFile(String sourcePath, {bool validateBeforeRestore = true}) async {
    final sourceFile = File(sourcePath);
    if (!await sourceFile.exists()) {
      throw Exception('File tidak ditemukan: $sourcePath');
    }

    // Check apakah file adalah ZIP
    final extension = p.extension(sourcePath).toLowerCase();

    if (extension == '.zip') {
      await _restoreFromZip(sourcePath, validateBeforeRestore: validateBeforeRestore);
    } else if (extension == '.db') {
      await _restoreFromDatabaseFile(sourcePath, validateBeforeRestore: validateBeforeRestore);
    } else {
      throw Exception('Format file tidak didukung. Gunakan file .db atau .zip');
    }
  }

  /// Restore dari file .db
  Future<void> _restoreFromDatabaseFile(String sourcePath, {bool validateBeforeRestore = true}) async {
    final sourceFile = File(sourcePath);
    if (!await sourceFile.exists()) {
      throw Exception('File database tidak ditemukan: $sourcePath');
    }

    // Validasi file database
    if (validateBeforeRestore) {
      final validation = await validateDatabaseFile(sourcePath);
      if (!validation.isValid) {
        throw Exception('File database tidak valid: ${validation.error}');
      }
      if (validation.articleCount == 0) {
        throw Exception('Database kosong (tidak ada artikel)');
      }
    }

    final info = await getDatabaseInfo();

    // Backup current database jika ada
    if (info.current.exists && info.current.articleCount > 0) {
      await _backupCurrentDatabase();
    }

    // Close database sebelum overwrite
    await db.close();

    // Copy file source ke current database path
    await sourceFile.copy(info.current.path);

    // Re-init database
    await db.init();
  }

  /// Restore dari file .zip (berisi database dan images)
  Future<void> _restoreFromZip(String zipPath, {bool validateBeforeRestore = true}) async {
    final zipFile = File(zipPath);
    if (!await zipFile.exists()) {
      throw Exception('File ZIP tidak ditemukan: $zipPath');
    }

    // Extract ZIP ke temporary directory
    final bytes = await zipFile.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);

    // Cari file .db di dalam ZIP
    ArchiveFile? dbFile;
    final imageFiles = <ArchiveFile>[];

    for (final file in archive) {
      final filename = file.name;

      // Cari file database
      if (filename.endsWith('.db') && !filename.contains('/')) {
        dbFile = file;
      }

      // Cari folder images (hanya file, skip direktori)
      if (filename.startsWith('images/') && filename.length > 7) {
        if (file.isFile) {
          imageFiles.add(file);
        }
        // Skip direktori
      }
    }

    if (dbFile == null) {
      throw Exception('File database (.db) tidak ditemukan di dalam ZIP');
    }

    // Extract database ke temporary file untuk validasi
    final tempDir = await Directory.systemTemp.createTemp('arsip_restore_');
    final tempDbPath = p.join(tempDir.path, 'temp.db');
    final tempDbFile = File(tempDbPath);
    await tempDbFile.writeAsBytes(dbFile.content as List<int>);

    try {
      // Validasi database
      if (validateBeforeRestore) {
        final validation = await validateDatabaseFile(tempDbPath);
        if (!validation.isValid) {
          throw Exception('File database tidak valid: ${validation.error}');
        }
        if (validation.articleCount == 0) {
          throw Exception('Database kosong (tidak ada artikel)');
        }
      }

      final info = await getDatabaseInfo();

      // Backup current database jika ada
      if (info.current.exists && info.current.articleCount > 0) {
        await _backupCurrentDatabase();
      }

      // Close database sebelum overwrite
      await db.close();

      // Copy database file
      await tempDbFile.copy(info.current.path);

      // Extract images
      if (imageFiles.isNotEmpty) {
        await _extractImages(imageFiles);
      }

      // Re-init database
      await db.init();

      print('✅ Restored database with ${imageFiles.length} images');
    } finally {
      // Cleanup temp directory
      try {
        await tempDir.delete(recursive: true);
      } catch (e) {
        print('⚠️  Failed to cleanup temp directory: $e');
      }
    }
  }

  /// Extract images dari ZIP ke direktori images aplikasi
  Future<void> _extractImages(List<ArchiveFile> imageFiles) async {
    final appDir = await db.documentsDirectory();
    final imagesDir = Directory(p.join(appDir.path, 'images'));

    // Buat direktori images jika belum ada
    if (!await imagesDir.exists()) {
      await imagesDir.create(recursive: true);
    }

    int extracted = 0;
    for (final file in imageFiles) {
      try {
        // Get filename (remove 'images/' prefix)
        final filename = file.name.substring(7); // Remove 'images/'
        final targetPath = p.join(imagesDir.path, filename);

        // Extract file
        final targetFile = File(targetPath);
        await targetFile.writeAsBytes(file.content as List<int>);
        extracted++;
      } catch (e) {
        print('⚠️  Failed to extract ${file.name}: $e');
      }
    }

    print('✅ Extracted $extracted images to ${imagesDir.path}');
  }

  /// Restore dari direktori (mencari file arsip_berita.db di direktori tersebut)
  /// [directoryPath] adalah path direktori yang berisi database
  Future<void> restoreFromDirectory(String directoryPath, {bool validateBeforeRestore = true}) async {
    final directory = Directory(directoryPath);
    if (!await directory.exists()) {
      throw Exception('Direktori tidak ditemukan: $directoryPath');
    }

    // Cari file arsip_berita.db di direktori
    final dbPath = p.join(directoryPath, 'arsip_berita.db');
    final dbFile = File(dbPath);

    if (!await dbFile.exists()) {
      throw Exception('File database tidak ditemukan di direktori: $dbPath');
    }

    // Gunakan restoreFromFile untuk melakukan restore
    await restoreFromFile(dbPath, validateBeforeRestore: validateBeforeRestore);
  }

  /// Validasi apakah file adalah database SQLite yang valid
  Future<DatabaseValidation> validateDatabaseFile(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) {
        return DatabaseValidation(
          isValid: false,
          error: 'File tidak ditemukan',
        );
      }

      // Check ukuran file minimal (database SQLite minimal ~100 bytes)
      final stat = await file.stat();
      if (stat.size < 100) {
        return DatabaseValidation(
          isValid: false,
          error: 'File terlalu kecil untuk menjadi database SQLite',
        );
      }

      // Coba buka database
      Database? testDb;
      try {
        testDb = await openDatabase(path, readOnly: true);

        // Cek apakah ada table articles
        final tables = await testDb.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name='articles'"
        );

        if (tables.isEmpty) {
          return DatabaseValidation(
            isValid: false,
            error: 'Database tidak memiliki table articles',
          );
        }

        // Hitung jumlah artikel
        final result = await testDb.rawQuery('SELECT COUNT(*) as c FROM articles');
        final articleCount = (result.first['c'] as int?) ?? 0;

        return DatabaseValidation(
          isValid: true,
          articleCount: articleCount,
        );

      } finally {
        await testDb?.close();
      }

    } catch (e) {
      return DatabaseValidation(
        isValid: false,
        error: 'Error membaca database: $e',
      );
    }
  }

  /// Scan direktori untuk menemukan semua file database yang mungkin
  Future<List<DatabaseFileInfo>> scanDirectoryForDatabases(String directoryPath) async {
    final directory = Directory(directoryPath);
    if (!await directory.exists()) {
      return [];
    }

    final results = <DatabaseFileInfo>[];
    final files = await directory.list(recursive: true).toList();

    for (final file in files) {
      if (file is File) {
        final filename = p.basename(file.path);
        // Cari file .db atau yang mengandung 'arsip_berita'
        if (filename.endsWith('.db') || filename.contains('arsip_berita')) {
          try {
            final validation = await validateDatabaseFile(file.path);
            final stat = await file.stat();

            results.add(DatabaseFileInfo(
              path: file.path,
              filename: filename,
              sizeKB: stat.size / 1024,
              modified: stat.modified,
              isValid: validation.isValid,
              articleCount: validation.articleCount,
              error: validation.error,
            ));
          } catch (e) {
            // Skip files yang error
            print('Error scanning ${file.path}: $e');
          }
        }
      }
    }

    // Sort by modified date (newest first)
    results.sort((a, b) => b.modified.compareTo(a.modified));

    return results;
  }

  /// Hapus file backup tertentu
  Future<void> deleteBackup(String backupPath) async {
    final file = File(backupPath);
    if (await file.exists()) {
      await file.delete();
    }
  }
}

/// Hasil validasi database
class DatabaseValidation {
  final bool isValid;
  final int articleCount;
  final String? error;

  DatabaseValidation({
    required this.isValid,
    this.articleCount = 0,
    this.error,
  });
}

/// Info file database yang ditemukan saat scan
class DatabaseFileInfo {
  final String path;
  final String filename;
  final double sizeKB;
  final DateTime modified;
  final bool isValid;
  final int articleCount;
  final String? error;

  DatabaseFileInfo({
    required this.path,
    required this.filename,
    required this.sizeKB,
    required this.modified,
    required this.isValid,
    required this.articleCount,
    this.error,
  });
}
