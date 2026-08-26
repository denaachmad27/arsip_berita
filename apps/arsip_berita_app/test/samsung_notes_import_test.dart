import 'dart:io';
import 'dart:typed_data';

import 'package:arsip_berita_app/data/local/db.dart';
import 'package:arsip_berita_app/services/samsung_notes_import.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:flutter/services.dart';

import 'samsung_notes_parser_test.dart';

class _TestDb extends LocalDatabase {
  final String path;
  _TestDb(this.path);

  @override
  Future<String> databasePath() async => path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late _TestDb db;
  late Directory tempDir;
  const channel = MethodChannel('plugins.flutter.io/path_provider');

  setUp(() {
    databaseFactory = databaseFactoryFfi;
    tempDir = Directory.systemTemp.createTempSync('arsip_test_');
    db = _TestDb(p.join(tempDir.path, 'test.db'));

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'getApplicationDocumentsDirectory':
        case 'getApplicationSupportDirectory':
        case 'getTemporaryDirectory':
          return tempDir.path;
      }
      return null;
    });
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await db.close();
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  SdocxImportSource source(String name, String text) =>
      SdocxImportSource(fileName: name, bytes: buildSdocx(text: text));

  test('imports multiple files and persists articles', () async {
    final res = await SamsungNotesImportService().importBatch(db, [
      source('note1.sdocx', 'Berita Pertama\nIsi berita satu.'),
      source('note2.sdocx', 'Berita Kedua\nIsi berita dua.'),
    ]);

    expect(res.imported, 2);
    expect(res.skipped, 0);
    expect(res.failed, 0);

    final all = await db.searchArticles();
    expect(all, hasLength(2));

    expect(await db.existsByCanonicalUrl('sdocx://note1.sdocx'), isTrue);
    expect(await db.existsByCanonicalUrl('sdocx://note2.sdocx'), isTrue);

    final id1 = await db.findArticleIdByCanonicalUrl('sdocx://note1.sdocx');
    final a1 = await db.getArticleById(id1!);
    expect(a1, isNotNull);
    expect(a1!.title, 'Berita Pertama');
    expect(a1.description, contains('<p>Berita Pertama</p>'));
    expect(a1.descriptionDelta, isNotNull);
    expect(a1.mediaId, isNotNull);

    final media = await db.getMediaById(a1.mediaId!);
    expect(media?.name, 'Samsung Notes');
  });

  test('skips already imported files (dedupe by filename)', () async {
    final svc = SamsungNotesImportService();
    await svc.importBatch(db, [source('note1.sdocx', 'Judul\nIsi.')]);

    final res =
        await svc.importBatch(db, [source('note1.sdocx', 'Judul\nIsi.')]);

    expect(res.imported, 0);
    expect(res.skipped, 1);
    expect(res.failed, 0);

    final all = await db.searchArticles();
    expect(all, hasLength(1));
  });

  test('counts corrupt files as failed and imports the rest', () async {
    final res = await SamsungNotesImportService().importBatch(db, [
      SdocxImportSource(
          fileName: 'rusak.sdocx', bytes: Uint8List.fromList([1, 2, 3])),
      source('note1.sdocx', 'Judul\nIsi.'),
    ]);

    expect(res.imported, 1);
    expect(res.failed, 1);
    expect(res.skipped, 0);
    expect(res.details, hasLength(1));
    expect(res.details.single, contains('rusak.sdocx'));
  });

  test('fails on handwriting-only notes (no typed text, no images)', () async {
    final bytes = buildSdocx(
      text: '',
      extraFiles: ['abc8fd18-01b9.page'],
    );

    final res = await SamsungNotesImportService().importBatch(db, [
      SdocxImportSource(fileName: 'tulisan_tangan.sdocx', bytes: bytes),
    ]);

    expect(res.imported, 0);
    expect(res.failed, 1);
    expect(res.details.single, contains('tulisan_tangan.sdocx'));
  });

  test('imports image-only note with filename as title and saves cover imagePath', () async {
    final img = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 1, 2, 3]);
    final bytes = buildSdocx(
      text: '',
      media: [('media/image0.png', img)],
    );

    final res = await SamsungNotesImportService().importBatch(db, [
      SdocxImportSource(fileName: 'foto_bukti.sdocx', bytes: bytes),
    ]);

    expect(res.imported, 1);
    expect(res.failed, 0);

    final id =
        await db.findArticleIdByCanonicalUrl('sdocx://foto_bukti.sdocx');
    final article = await db.getArticleById(id!);
    expect(article!.title, 'foto_bukti');
    expect(article.description, contains('data:image/png;base64,'));
    expect(article.imagePath, isNotNull);
    expect(article.imagePath, endsWith('.png'));
    expect(File(article.imagePath!).existsSync(), isTrue);
  });
}
