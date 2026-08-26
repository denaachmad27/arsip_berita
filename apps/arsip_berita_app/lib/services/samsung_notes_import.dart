import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_quill_delta_from_html/flutter_quill_delta_from_html.dart';

import '../data/local/db.dart';
import '../util/platform_io.dart';
import 'samsung_notes_parser.dart';

/// Satu file `.sdocx` yang akan diimport.
class SdocxImportSource {
  final String fileName;
  final Uint8List bytes;

  const SdocxImportSource({required this.fileName, required this.bytes});
}

/// Hasil import batch.
class SdocxImportResult {
  final int imported;
  final int skipped;
  final int failed;

  /// Detail error per file yang gagal (maksimal sesuai isi list).
  final List<String> details;

  const SdocxImportResult({
    required this.imported,
    required this.skipped,
    required this.failed,
    this.details = const [],
  });

  bool get hasErrors => failed > 0;
}

/// Import banyak file Samsung Notes (.sdocx) langsung ke database,
/// tanpa melalui form editor.
///
/// Dedupe memakai `canonical_url = sdocx://<namaFile>` sehingga file yang
/// pernah diimport tidak akan tersimpan dua kali.
class SamsungNotesImportService {
  static const mediaName = 'Samsung Notes';

  Future<SdocxImportResult> importBatch(
    LocalDatabase db,
    List<SdocxImportSource> sources,
  ) async {
    await db.init();

    var imported = 0;
    var skipped = 0;
    var failed = 0;
    final details = <String>[];
    int? mediaId;

    for (final source in sources) {
      final canonical = 'sdocx://${source.fileName}';
      try {
        if (await db.existsByCanonicalUrl(canonical)) {
          skipped++;
          continue;
        }

        final doc = SamsungNotesParser().parse(source.bytes);
        final html = buildSamsungNotesHtml(doc);
        if (html.trim().isEmpty) {
          failed++;
          details.add('${source.fileName}: tidak ada konten yang bisa diimpor');
          continue;
        }

        mediaId ??= await db.upsertMedia(mediaName, 'online');

        final delta = buildSamsungNotesDelta(doc);
        final articleId =
            'local-${DateTime.now().millisecondsSinceEpoch}-$imported';

        String? imagePath;
        if (doc.images.isNotEmpty) {
          try {
            final firstImg = doc.images.first;
            final ext = extFromMime(firstImg.mimeType);
            final saved = await saveImageForArticle(
              articleId,
              firstImg.data,
              ext: ext,
            );
            if (saved.isNotEmpty) {
              imagePath = saved;
            }
          } catch (_) {}
        }

        await db.upsertArticle(ArticleModel(
          id: articleId,
          title: _titleFrom(doc.text, source.fileName),
          url: '',
          canonicalUrl: canonical,
          mediaId: mediaId,
          kind: 'artikel',
          publishedAt: doc.modifiedAt,
          description: html,
          descriptionDelta: jsonEncode(delta.toJson()),
          imagePath: imagePath,
        ));
        imported++;
      } catch (e) {
        failed++;
        details.add('${source.fileName}: $e');
      }
    }

    return SdocxImportResult(
      imported: imported,
      skipped: skipped,
      failed: failed,
      details: details,
    );
  }

  String _titleFrom(String text, String fileName) {
    final firstLine = text
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .firstOrNull;
    if (firstLine != null && firstLine.isNotEmpty) return firstLine;
    return fileName
        .replaceAll(RegExp(r'\.sdocx$', caseSensitive: false), '')
        .trim();
  }

  /// Sama seperti transformasi di `ArticleFormPage._loadHtmlIntoQuill`:
  /// beri jarak antar paragraf agar `HtmlToDelta` memisahkannya dengan benar.
  String _spacedHtml(String html) {
    return html
        .replaceAll('</p><p>', '</p><br><br><p>')
        .replaceAll('</h1><p>', '</h1><br><br><p>')
        .replaceAll('</h2><p>', '</h2><br><br><p>')
        .replaceAll('</h3><p>', '</h3><br><br><p>')
        .replaceAll('</h4><p>', '</h4><br><br><p>')
        .replaceAll('</ul><p>', '</ul><br><br><p>')
        .replaceAll('</ol><p>', '</ol><br><br><p>')
        .replaceAll('</blockquote><p>', '</blockquote><br><br><p>');
  }
}
