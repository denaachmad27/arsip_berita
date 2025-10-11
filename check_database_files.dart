import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

/// Script untuk mengecek dan mencari file database yang mungkin bisa di-restore
Future<void> main() async {
  print('=== Mencari File Database ===\n');

  try {
    // 1. Cek lokasi database current
    final appDir = await getApplicationDocumentsDirectory();
    final currentDbPath = p.join(appDir.path, 'arsip_berita.db');

    print('📍 Lokasi Database Current:');
    print('   $currentDbPath');
    if (await File(currentDbPath).exists()) {
      final stat = await File(currentDbPath).stat();
      final size = (stat.size / 1024).toStringAsFixed(2);
      print('   ✅ File ada (${size} KB)');
      print('   📅 Modified: ${stat.modified}');

      // Cek jumlah artikel di database current
      try {
        final db = await openDatabase(currentDbPath, readOnly: true);
        final result = await db.rawQuery('SELECT COUNT(*) as c FROM articles');
        final count = result.first['c'] as int?;
        print('   📊 Jumlah artikel: $count');
        await db.close();
      } catch (e) {
        print('   ⚠️  Tidak bisa membaca: $e');
      }
    } else {
      print('   ❌ File tidak ada');
    }

    // 2. Cek lokasi legacy database
    print('\n📍 Lokasi Database Legacy:');
    final legacyDir = await getDatabasesPath();
    final legacyDbPath = p.join(legacyDir, 'arsip_berita.db');

    print('   $legacyDbPath');
    if (await File(legacyDbPath).exists()) {
      final stat = await File(legacyDbPath).stat();
      final size = (stat.size / 1024).toStringAsFixed(2);
      print('   ✅ File ada (${size} KB)');
      print('   📅 Modified: ${stat.modified}');

      // Cek jumlah artikel di database legacy
      try {
        final db = await openDatabase(legacyDbPath, readOnly: true);
        final result = await db.rawQuery('SELECT COUNT(*) as c FROM articles');
        final count = result.first['c'] as int?;
        print('   📊 Jumlah artikel: $count');

        // Tampilkan 5 artikel terbaru
        final articles = await db.rawQuery(
          'SELECT id, title, updated_at FROM articles ORDER BY updated_at DESC LIMIT 5'
        );
        if (articles.isNotEmpty) {
          print('\n   📰 5 Artikel Terbaru:');
          for (var i = 0; i < articles.length; i++) {
            print('   ${i + 1}. ${articles[i]['title']}');
            print('      Updated: ${articles[i]['updated_at']}');
          }
        }

        await db.close();
      } catch (e) {
        print('   ⚠️  Tidak bisa membaca: $e');
      }
    } else {
      print('   ❌ File tidak ada');
    }

    // 3. Cek apakah ada file backup lainnya
    print('\n📍 Mencari File Backup Lainnya:');
    final appDirFiles = await Directory(appDir.path).list().toList();
    final dbBackups = appDirFiles.where((f) =>
      f.path.toLowerCase().contains('arsip_berita') &&
      (f.path.endsWith('.db') || f.path.endsWith('.db-journal') ||
       f.path.endsWith('.bak') || f.path.endsWith('.backup'))
    ).toList();

    if (dbBackups.isEmpty) {
      print('   ❌ Tidak ada backup ditemukan');
    } else {
      for (final file in dbBackups) {
        if (file is File) {
          final stat = await file.stat();
          final size = (stat.size / 1024).toStringAsFixed(2);
          print('   ✅ ${p.basename(file.path)} (${size} KB)');
          print('      ${file.path}');
          print('      Modified: ${stat.modified}');
        }
      }
    }

    // 4. Rekomendasi
    print('\n═══════════════════════════════════════');
    print('📋 REKOMENDASI:');
    print('═══════════════════════════════════════\n');

    final currentExists = await File(currentDbPath).exists();
    final legacyExists = await File(legacyDbPath).exists();

    if (legacyExists && !currentExists) {
      print('✅ Database legacy ditemukan!');
      print('   Jalankan: dart restore_from_legacy.dart');
      print('   untuk restore data dari legacy database.\n');
    } else if (legacyExists && currentExists) {
      print('⚠️  PERINGATAN: Kedua database ditemukan!');
      print('   Bandingkan jumlah artikel di atas.');
      print('   Jika legacy punya lebih banyak data,');
      print('   jalankan: dart restore_from_legacy.dart\n');
    } else if (!legacyExists && !currentExists) {
      print('❌ Tidak ada database yang ditemukan.');
      print('   Data kemungkinan tidak bisa dikembalikan.\n');
    } else {
      print('✅ Database current sudah ada.');
      print('   Pastikan bug sudah diperbaiki agar');
      print('   data tidak hilang lagi.\n');
    }

  } catch (e, stackTrace) {
    print('❌ Error: $e');
    print('StackTrace: $stackTrace');
  }
}
