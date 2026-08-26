import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:arsip_berita_app/services/samsung_notes_parser.dart';
import 'package:flutter_quill_delta_from_html/flutter_quill_delta_from_html.dart';
import 'package:flutter_test/flutter_test.dart';

/// Bangun file `.sdocx` sintetis: ZIP berisi `note.note` (header biner +
/// teks UTF-16LE + gaya TLV), `end_tag.bin`, dan file di folder `media/`.
Uint8List buildSdocx({
  required String text,
  List<({int start, int end, bool bold, bool italic})> styleRuns = const [],
  Uint8List? endTag,
  List<(String, Uint8List)> media = const [],
  List<String> extraFiles = const [],
  List<int> notePrefix = const [],
  List<int> noteSuffix = const [],
}) {
  final data = <int>[
    // header biner non-printable
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
  ];
  data.addAll(notePrefix);
  for (final unit in text.codeUnits) {
    data.add(unit & 0xFF);
    data.add((unit >> 8) & 0xFF);
  }
  data.addAll(noteSuffix);
  for (final run in styleRuns) {
    final tag = run.bold ? 0x05 : 0x06;
    data.addAll([0x18, 0x00, tag, 0x00]); // marker
    data.addAll([0x00, 0x00]); // pad
    data.addAll(_leUint32(run.start)); // start
    data.addAll(_leUint32(run.end)); // end
    data.addAll([0x00, 0x00, 0x00, 0x00]); // pad
    data.addAll([0x01, 0x00, 0x00, 0x00]); // enabled
  }
  final noteBytes = Uint8List.fromList(data);

  final archive = Archive();
  archive.addFile(ArchiveFile('note.note', noteBytes.length, noteBytes));
  if (endTag != null) {
    archive.addFile(ArchiveFile('end_tag.bin', endTag.length, endTag));
  }
  for (final entry in media) {
    archive.addFile(ArchiveFile(entry.$1, entry.$2.length, entry.$2));
  }
  for (final name in extraFiles) {
    archive.addFile(ArchiveFile(name, 4, [0x01, 0x02, 0x03, 0x04]));
  }
  return Uint8List.fromList(ZipEncoder().encode(archive)!);
}

List<int> _leUint32(int value) => [
      value & 0xFF,
      (value >> 8) & 0xFF,
      (value >> 16) & 0xFF,
      (value >> 24) & 0xFF,
    ];

List<int> _utf16le(String text) {
  final bytes = <int>[];
  for (final unit in text.codeUnits) {
    bytes.add(unit & 0xFF);
    bytes.add((unit >> 8) & 0xFF);
  }
  return bytes;
}

Uint8List buildEndTag(DateTime created, DateTime modified) {
  final bytes = Uint8List(0x60);
  final bd = ByteData.sublistView(bytes);
  bd.setInt64(0x48, created.millisecondsSinceEpoch, Endian.little);
  bd.setInt64(0x50, modified.millisecondsSinceEpoch, Endian.little);
  return bytes;
}

const kText = 'Judul Berita\nIni adalah isi berita di Samsung Notes.';

void main() {
  group('SamsungNotesParser', () {
    test('parses typed text, styles, timestamps and images', () {
      final img0 = Uint8List.fromList(
          [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 1, 2, 3]);
      final img1 = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 9, 8, 7]);
      final created = DateTime(2024, 3, 10, 8, 30);
      final modified = DateTime(2025, 6, 1, 12, 0);

      final bytes = buildSdocx(
        text: kText,
        styleRuns: [
          (start: 6, end: 12, bold: true, italic: false), // "Berita"
          (start: 24, end: 27, bold: false, italic: true), // "isi"
        ],
        endTag: buildEndTag(created, modified),
        media: [
          ('media/image0.png', img0),
          ('media/image1.jpg', img1),
        ],
      );

      final doc = SamsungNotesParser().parse(bytes);

      expect(doc.text, kText);
      expect(doc.runs, hasLength(2));

      final boldRun = doc.runs.singleWhere((r) => r.bold);
      expect(boldRun.start, 6);
      expect(boldRun.end, 12);

      final italicRun = doc.runs.singleWhere((r) => r.italic);
      expect(italicRun.start, 24);
      expect(italicRun.end, 27);

      expect(doc.createdAt, created);
      expect(doc.modifiedAt, modified);

      expect(doc.images, hasLength(2));
      expect(doc.images[0].name, 'media/image0.png');
      expect(doc.images[0].mimeType, 'image/png');
      expect(doc.images[0].data, img0);
      expect(doc.images[1].mimeType, 'image/jpeg');
      expect(doc.images[1].data, img1);
    });

    test('rejects non-zip bytes', () {
      final parser = SamsungNotesParser();
      expect(
        () => parser.parse(Uint8List.fromList([1, 2, 3, 4, 5, 6, 7])),
        throwsA(isA<SamsungNotesParseException>()),
      );
    });

    test('extracts images even when note has no typed text (handwriting only)',
        () {
      final img0 = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 1, 2, 3]);
      final bytes = buildSdocx(
        text: '',
        media: [('media/image0.png', img0)],
        extraFiles: ['abc8fd18-01b9.page'],
      );

      final doc = SamsungNotesParser().parse(bytes);

      expect(doc.text, '');
      expect(doc.images, hasLength(1));
      expect(doc.images.single.data, img0);
    });

    test('throws when there is no text and no images', () {
      final bytes = buildSdocx(
        text: '',
        extraFiles: ['abc8fd18-01b9.page'],
      );

      expect(
        () => SamsungNotesParser().parse(bytes),
        throwsA(isA<SamsungNotesParseException>()),
      );
    });

    test('ignores separate CJK metadata ranges around the body', () {
      final prefix = _utf16le('三星笔记');
      final suffix = _utf16le('笔记 2024-01-15 10:30');
      const body = 'Judul Berita\nIni adalah isi berita Samsung Notes.';
      final bytes = buildSdocx(
        text: body,
        notePrefix: [...prefix, 0x00, 0x00], // null-terminated separate range
        noteSuffix: [0x00, 0x00, ...suffix],
      );

      final doc = SamsungNotesParser().parse(bytes);
      expect(doc.text, body);
    });

    test('strips CJK characters attached to the start and end of the body',
        () {
      const body = 'Judul Berita\nIni adalah isi berita Samsung Notes.';
      final bytes = buildSdocx(
        text: body,
        notePrefix: _utf16le('三星笔记'),
        noteSuffix: _utf16le('正文结尾'),
      );

      final doc = SamsungNotesParser().parse(bytes);
      expect(doc.text, body);
    });

    test('falls back to CJK text when the note contains only CJK characters',
        () {
      const text = '三星笔记内容示例';
      final bytes = buildSdocx(text: text);

      final doc = SamsungNotesParser().parse(bytes);
      expect(doc.text, text);
    });

    test('supports Windows backslash paths, uppercase folders, and various image formats', () {
      final imgJfif = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 1, 2]);
      final imgWebp = Uint8List.fromList([
        0x52, 0x49, 0x46, 0x46, 0, 0, 0, 0, 0x57, 0x45, 0x42, 0x50, 1, 2
      ]);
      final bytes = buildSdocx(
        text: 'Catatan Gambar',
        media: [
          (r'Media\1@photo.jfif', imgJfif),
          ('attachments/image2.webp', imgWebp),
        ],
      );

      final doc = SamsungNotesParser().parse(bytes);
      expect(doc.images, hasLength(2));
      expect(doc.images[0].name, 'Media/1@photo.jfif');
      expect(doc.images[0].mimeType, 'image/jpeg');
      expect(doc.images[1].name, 'attachments/image2.webp');
      expect(doc.images[1].mimeType, 'image/webp');
      expect(extFromMime(doc.images[0].mimeType), 'jpg');
      expect(extFromMime(doc.images[1].mimeType), 'webp');
    });
  });

  group('buildSamsungNotesHtml', () {
    test('renders paragraphs with bold/italic styles', () {
      final img0 = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 1, 2, 3]);
      final doc = SamsungNotesParser().parse(buildSdocx(
        text: kText,
        styleRuns: [
          (start: 6, end: 12, bold: true, italic: false),
          (start: 24, end: 27, bold: false, italic: true),
        ],
        media: [('media/image0.png', img0)],
      ));

      final html = buildSamsungNotesHtml(doc);

      expect(html, contains('<p>Judul <strong>Berita</strong></p>'));
      expect(
        html,
        contains('<p>Ini adalah <em>isi</em> berita di Samsung Notes.</p>'),
      );
      expect(
        html,
        contains('data:image/png;base64,${base64Encode(img0)}'),
      );
      expect(html, contains('width="320"'));
    });

    test('HtmlToDelta converts embedded images to quill delta image blocks', () {
      final img0 = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 1, 2, 3]);
      final doc = SamsungNotesParser().parse(buildSdocx(
        text: 'Judul Catatan\nIsi catatan dengan foto.',
        media: [('media/image0.png', img0)],
      ));
      final html = buildSamsungNotesHtml(doc);
      final delta = HtmlToDelta().convert(html);
      final json = delta.toJson();
      final hasImage = json.any((op) => op is Map && op['insert'] is Map && op['insert']['image'] != null);
      expect(hasImage, isTrue);
    });

    test('preserves bold title and subtitle as headings', () {
      const text =
          'JUDUL UTAMA\nSUB JUDUL\nIsi berita dengan icon ⭐ tetap ada.';
      final doc = SamsungNotesParser().parse(buildSdocx(
        text: text,
        styleRuns: [
          (start: 0, end: 11, bold: true, italic: false),
          (start: 12, end: 21, bold: true, italic: false),
        ],
      ));

      final html = buildSamsungNotesHtml(doc);

      expect(html, contains('<h1><strong>JUDUL UTAMA</strong></h1>'));
      expect(html, contains('<h2><strong>SUB JUDUL</strong></h2>'));
      expect(html, contains('icon ⭐ tetap ada.'));
    });

    test('keeps additional image formats used by notes icons', () {
      final svg = Uint8List.fromList('<svg></svg>'.codeUnits);
      final doc = SamsungNotesParser().parse(buildSdocx(
        text: 'Catatan dengan ikon',
        media: [('media/icon.svg', svg)],
      ));

      expect(doc.images.single.mimeType, 'image/svg+xml');
      expect(
          buildSamsungNotesHtml(doc), contains('data:image/svg+xml;base64,'));
    });

    test('escapes html special characters in text', () {
      final doc = SamsungNotesParser().parse(buildSdocx(
        text: 'Teks <b>mentah</b> & "kutip"',
      ));

      final html = buildSamsungNotesHtml(doc);

      expect(html,
          contains('<p>Teks &lt;b&gt;mentah&lt;/b&gt; &amp; "kutip"</p>'));
    });

    test('keeps text after tabs, carriage returns and emoji', () {
      const text = 'Awal\tteks\r\nBagian kedua 😀 tetap utuh sampai akhir.';
      final doc = SamsungNotesParser().parse(buildSdocx(text: text));

      expect(doc.text, 'Awal\tteks\nBagian kedua 😀 tetap utuh sampai akhir.');
      expect(buildSamsungNotesHtml(doc), contains('tetap utuh sampai akhir.'));
    });

    test('joins separated title and body text ranges in source order', () {
      final doc = SamsungNotesParser().parse(buildSdocx(
        text: 'JUDUL UTAMA\u0000SUB JUDUL\u0000Isi lengkap sampai akhir.',
      ));

      expect(doc.text, 'JUDUL UTAMA\n\nSUB JUDUL\n\nIsi lengkap sampai akhir.');
      final html = buildSamsungNotesHtml(doc);
      expect(html, contains('JUDUL UTAMA'));
      expect(html, contains('SUB JUDUL'));
      expect(html, contains('Isi lengkap sampai akhir.'));
    });

    test('positions inline image using 0xFFFC object replacement character in Delta and HTML', () {
      final img = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 1, 2, 3]);
      final doc = SamsungNotesParser().parse(buildSdocx(
        text: 'Judul Catatan\n\nPenulis Catatan\n\n\uFFFC\n\nIsi paragraf setelah gambar.',
        media: [('media/image0.png', img)],
      ));

      final delta = buildSamsungNotesDelta(doc);
      final jsonList = delta.toJson();

      // Verify that the image embed is located between Penulis and Isi
      final imgIndex = jsonList.indexWhere((op) =>
          op is Map &&
          op['insert'] is Map &&
          (op['insert'] as Map).containsKey('image'));
      expect(imgIndex, greaterThan(0));

      final html = buildSamsungNotesHtml(doc);
      expect(html.indexOf('Penulis Catatan'), lessThan(html.indexOf('<img')));
      expect(html.indexOf('<img'), lessThan(html.indexOf('Isi paragraf setelah gambar.')));
    });

    test('preserves empty lines (double line breaks) in Delta and HTML', () {
      const text = 'Baris 1\n\nBaris 2\n\n\nBaris 3';
      final doc = SamsungNotesParser().parse(buildSdocx(text: text));

      final delta = buildSamsungNotesDelta(doc);
      final deltaJson = jsonEncode(delta.toJson());
      expect(deltaJson, contains(r'\n\n'));

      final html = buildSamsungNotesHtml(doc);
      expect(html, contains('<p><br></p>'));
    });

    test('returns empty string for empty document', () {
      const doc = SamsungNotesDocument(text: '', runs: [], images: []);
      expect(buildSamsungNotesHtml(doc), '');
    });
  });
}
