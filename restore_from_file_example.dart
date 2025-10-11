import 'dart:io';
import 'package:path/path.dart' as p;
import 'apps/arsip_berita_app/lib/data/local/db.dart';
import 'apps/arsip_berita_app/lib/data/local/db_recovery_service.dart';

/// Contoh script untuk restore database dari file atau direktori
///
/// Cara menjalankan:
/// 1. Restore dari file:
///    dart restore_from_file_example.dart --file /path/to/backup.db
///
/// 2. Restore dari direktori:
///    dart restore_from_file_example.dart --dir /path/to/directory
///
/// 3. Scan direktori untuk mencari database:
///    dart restore_from_file_example.dart --scan /path/to/directory
///
/// 4. Validasi file database saja:
///    dart restore_from_file_example.dart --validate /path/to/backup.db

Future<void> main(List<String> args) async {
  print('═══════════════════════════════════════');
  print('🔄 DATABASE RESTORE UTILITY');
  print('═══════════════════════════════════════\n');

  if (args.isEmpty) {
    _printUsage();
    exit(0);
  }

  try {
    final db = LocalDatabase();
    final recoveryService = DbRecoveryService(db);

    final command = args[0];

    switch (command) {
      case '--file':
        if (args.length < 2) {
          print('❌ ERROR: Path file harus disertakan\n');
          _printUsage();
          exit(1);
        }
        await _restoreFromFile(recoveryService, args[1]);
        break;

      case '--dir':
        if (args.length < 2) {
          print('❌ ERROR: Path direktori harus disertakan\n');
          _printUsage();
          exit(1);
        }
        await _restoreFromDirectory(recoveryService, args[1]);
        break;

      case '--scan':
        if (args.length < 2) {
          print('❌ ERROR: Path direktori harus disertakan\n');
          _printUsage();
          exit(1);
        }
        await _scanDirectory(recoveryService, args[1]);
        break;

      case '--validate':
        if (args.length < 2) {
          print('❌ ERROR: Path file harus disertakan\n');
          _printUsage();
          exit(1);
        }
        await _validateFile(recoveryService, args[1]);
        break;

      default:
        print('❌ ERROR: Perintah tidak dikenali: $command\n');
        _printUsage();
        exit(1);
    }

  } catch (e, stackTrace) {
    print('\n❌ ERROR: $e');
    print('\nStackTrace: $stackTrace\n');
    exit(1);
  }
}

void _printUsage() {
  print('Cara menggunakan:');
  print('');
  print('1. Restore dari file backup:');
  print('   dart restore_from_file_example.dart --file /path/to/backup.db');
  print('');
  print('2. Restore dari direktori (mencari arsip_berita.db):');
  print('   dart restore_from_file_example.dart --dir /path/to/directory');
  print('');
  print('3. Scan direktori untuk mencari semua file database:');
  print('   dart restore_from_file_example.dart --scan /path/to/directory');
  print('');
  print('4. Validasi file database:');
  print('   dart restore_from_file_example.dart --validate /path/to/backup.db');
  print('');
}

Future<void> _restoreFromFile(DbRecoveryService service, String filePath) async {
  print('📂 Restore dari file: $filePath\n');

  // Validasi dulu
  print('🔍 Memvalidasi file...');
  final validation = await service.validateDatabaseFile(filePath);

  if (!validation.isValid) {
    print('❌ File tidak valid: ${validation.error}\n');
    exit(1);
  }

  print('✅ File valid!');
  print('   📊 Jumlah artikel: ${validation.articleCount}\n');

  // Tampilkan info current database
  final info = await service.getDatabaseInfo();
  print('📍 Database Current:');
  print('   Path: ${info.current.path}');
  print('   Artikel: ${info.current.articleCount}\n');

  if (info.current.articleCount > 0) {
    print('⚠️  WARNING: Database current akan DITIMPA!');
    print('   Backup otomatis akan dibuat.\n');
  }

  // Konfirmasi
  print('Lanjutkan restore? (yes/no)');
  final confirm = stdin.readLineSync()?.toLowerCase();

  if (confirm != 'yes' && confirm != 'y') {
    print('❌ Restore dibatalkan.\n');
    exit(0);
  }

  print('\n🔄 Memulai restore...');
  await service.restoreFromFile(filePath);

  print('✅ Restore berhasil!\n');

  // Verifikasi
  final newInfo = await service.getDatabaseInfo();
  print('═══════════════════════════════════════');
  print('✅ RESTORE SELESAI!');
  print('═══════════════════════════════════════');
  print('📊 Jumlah artikel sekarang: ${newInfo.current.articleCount}');
  print('📍 Path: ${newInfo.current.path}\n');
}

Future<void> _restoreFromDirectory(DbRecoveryService service, String dirPath) async {
  print('📂 Restore dari direktori: $dirPath\n');

  // Cek apakah ada file arsip_berita.db di direktori
  final dbPath = p.join(dirPath, 'arsip_berita.db');
  print('🔍 Mencari file: $dbPath\n');

  if (!await File(dbPath).exists()) {
    print('❌ File arsip_berita.db tidak ditemukan di direktori tersebut.\n');
    print('💡 Gunakan --scan untuk mencari semua file database di direktori.\n');
    exit(1);
  }

  // Validasi
  print('🔍 Memvalidasi file...');
  final validation = await service.validateDatabaseFile(dbPath);

  if (!validation.isValid) {
    print('❌ File tidak valid: ${validation.error}\n');
    exit(1);
  }

  print('✅ File valid!');
  print('   📊 Jumlah artikel: ${validation.articleCount}\n');

  // Tampilkan info current database
  final info = await service.getDatabaseInfo();
  print('📍 Database Current:');
  print('   Path: ${info.current.path}');
  print('   Artikel: ${info.current.articleCount}\n');

  if (info.current.articleCount > 0) {
    print('⚠️  WARNING: Database current akan DITIMPA!');
    print('   Backup otomatis akan dibuat.\n');
  }

  // Konfirmasi
  print('Lanjutkan restore? (yes/no)');
  final confirm = stdin.readLineSync()?.toLowerCase();

  if (confirm != 'yes' && confirm != 'y') {
    print('❌ Restore dibatalkan.\n');
    exit(0);
  }

  print('\n🔄 Memulai restore...');
  await service.restoreFromDirectory(dirPath);

  print('✅ Restore berhasil!\n');

  // Verifikasi
  final newInfo = await service.getDatabaseInfo();
  print('═══════════════════════════════════════');
  print('✅ RESTORE SELESAI!');
  print('═══════════════════════════════════════');
  print('📊 Jumlah artikel sekarang: ${newInfo.current.articleCount}');
  print('📍 Path: ${newInfo.current.path}\n');
}

Future<void> _scanDirectory(DbRecoveryService service, String dirPath) async {
  print('🔍 Scanning direktori: $dirPath\n');

  print('Mencari semua file database...\n');
  final databases = await service.scanDirectoryForDatabases(dirPath);

  if (databases.isEmpty) {
    print('❌ Tidak ada file database ditemukan.\n');
    exit(0);
  }

  print('═══════════════════════════════════════');
  print('📦 DITEMUKAN ${databases.length} FILE DATABASE');
  print('═══════════════════════════════════════\n');

  for (var i = 0; i < databases.length; i++) {
    final db = databases[i];
    print('${i + 1}. ${db.filename}');
    print('   Path: ${db.path}');
    print('   Size: ${db.sizeKB.toStringAsFixed(2)} KB');
    print('   Modified: ${db.modified}');

    if (db.isValid) {
      print('   Status: ✅ Valid');
      print('   Artikel: ${db.articleCount}');
    } else {
      print('   Status: ❌ Invalid');
      print('   Error: ${db.error}');
    }
    print('');
  }

  print('═══════════════════════════════════════\n');
  print('💡 Gunakan --file untuk restore dari salah satu file di atas.\n');
}

Future<void> _validateFile(DbRecoveryService service, String filePath) async {
  print('🔍 Validasi file: $filePath\n');

  if (!await File(filePath).exists()) {
    print('❌ File tidak ditemukan.\n');
    exit(1);
  }

  final validation = await service.validateDatabaseFile(filePath);

  print('═══════════════════════════════════════');
  if (validation.isValid) {
    print('✅ FILE DATABASE VALID');
    print('═══════════════════════════════════════');
    print('📊 Jumlah artikel: ${validation.articleCount}');

    // Info tambahan
    final file = File(filePath);
    final stat = await file.stat();
    print('📏 Ukuran: ${(stat.size / 1024).toStringAsFixed(2)} KB');
    print('📅 Modified: ${stat.modified}');
  } else {
    print('❌ FILE DATABASE TIDAK VALID');
    print('═══════════════════════════════════════');
    print('Error: ${validation.error}');
  }
  print('═══════════════════════════════════════\n');
}
