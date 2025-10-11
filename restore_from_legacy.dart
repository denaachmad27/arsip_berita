import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

/// Script untuk restore database dari legacy location
/// PERINGATAN: Script ini akan menimpa database current!
Future<void> main(List<String> args) async {
  print('═══════════════════════════════════════');
  print('🔧 RESTORE DATABASE DARI LEGACY');
  print('═══════════════════════════════════════\n');

  try {
    // Lokasi database
    final appDir = await getApplicationDocumentsDirectory();
    final currentDbPath = p.join(appDir.path, 'arsip_berita.db');
    final legacyDir = await getDatabasesPath();
    final legacyDbPath = p.join(legacyDir, 'arsip_berita.db');

    // Validasi
    if (!await File(legacyDbPath).exists()) {
      print('❌ ERROR: Legacy database tidak ditemukan!');
      print('   Path: $legacyDbPath\n');
      exit(1);
    }

    // Tampilkan info
    print('📍 Legacy Database: $legacyDbPath');
    final legacyDb = await openDatabase(legacyDbPath, readOnly: true);
    final legacyResult = await legacyDb.rawQuery('SELECT COUNT(*) as c FROM articles');
    final legacyCount = legacyResult.first['c'] as int?;
    print('   📊 Jumlah artikel: $legacyCount');

    if ((legacyCount ?? 0) == 0) {
      print('\n⚠️  WARNING: Legacy database kosong!');
      print('   Tidak ada data untuk di-restore.\n');
      await legacyDb.close();
      exit(1);
    }

    // Tampilkan artikel terbaru
    final articles = await legacyDb.rawQuery(
      'SELECT title, updated_at FROM articles ORDER BY updated_at DESC LIMIT 5'
    );
    print('\n   📰 5 Artikel Terbaru:');
    for (var i = 0; i < articles.length; i++) {
      print('   ${i + 1}. ${articles[i]['title']}');
      print('      ${articles[i]['updated_at']}');
    }
    await legacyDb.close();

    print('\n📍 Database Current: $currentDbPath');
    if (await File(currentDbPath).exists()) {
      final currentDb = await openDatabase(currentDbPath, readOnly: true);
      final currentResult = await currentDb.rawQuery('SELECT COUNT(*) as c FROM articles');
      final currentCount = currentResult.first['c'] as int?;
      print('   📊 Jumlah artikel: $currentCount');
      await currentDb.close();

      if ((currentCount ?? 0) > 0) {
        print('\n⚠️  WARNING: Database current sudah ada data!');
        print('   Data ini akan DITIMPA jika Anda lanjutkan.\n');
      }
    } else {
      print('   ℹ️  Database current tidak ada (akan dibuat baru)\n');
    }

    // Konfirmasi
    print('═══════════════════════════════════════');
    print('⚠️  PERINGATAN PENTING!');
    print('═══════════════════════════════════════');
    print('Script ini akan:');
    print('1. Backup database current (jika ada)');
    print('2. Copy legacy database ke lokasi current');
    print('3. Database current AKAN DITIMPA!\n');

    if (args.isEmpty || args.first != '--confirm') {
      print('❌ Restore dibatalkan.');
      print('\nUntuk menjalankan restore, gunakan:');
      print('   dart restore_from_legacy.dart --confirm\n');
      exit(0);
    }

    print('✅ Konfirmasi diterima. Memulai restore...\n');

    // Backup current database jika ada
    if (await File(currentDbPath).exists()) {
      final backupPath = '$currentDbPath.backup.${DateTime.now().millisecondsSinceEpoch}';
      await File(currentDbPath).copy(backupPath);
      print('✅ Backup current database ke:');
      print('   $backupPath\n');
    }

    // Copy legacy ke current
    await File(legacyDbPath).copy(currentDbPath);
    print('✅ Database berhasil di-restore!\n');

    // Verifikasi
    final restoredDb = await openDatabase(currentDbPath, readOnly: true);
    final restoredResult = await restoredDb.rawQuery('SELECT COUNT(*) as c FROM articles');
    final restoredCount = restoredResult.first['c'] as int?;
    await restoredDb.close();

    print('═══════════════════════════════════════');
    print('✅ RESTORE SELESAI!');
    print('═══════════════════════════════════════');
    print('📊 Jumlah artikel di database current: $restoredCount');
    print('\nSilakan jalankan aplikasi dan cek datanya.\n');

  } catch (e, stackTrace) {
    print('❌ ERROR: $e');
    print('StackTrace: $stackTrace\n');
    exit(1);
  }
}
