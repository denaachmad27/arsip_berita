import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:arsip_berita_app/services/samsung_notes_parser.dart';
import 'package:flutter_test/flutter_test.dart';

/// Bangun file `.sdocx` sintetis: ZIP berisi `note.note` (header biner +
/// teks UTF-16LE + gaya TLV), `end_tag.bin`, dan file di folder `media/`.
Uint8List buildSdocx({
  required String text,
  List<({int start, int end, bool bold, bool italic})> styleRuns = const [],
  Uint8List? endTag,
  List<(String, Uint8List)> media = const [],
  List<String> extraFiles = const [],
}) {
  final data = <int>[
    // header biner non-printable
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
  ];
  for (final unit in text.codeUnits) {
    data.add(unit & 0xFF);
    data.add((unit >> 8) & 0xFF);
  }
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

    test('escapes html special characters in text', () {
      final doc = SamsungNotesParser().parse(buildSdocx(
        text: 'Teks <b>mentah</b> & "kutip"',
      ));

      final html = buildSamsungNotesHtml(doc);

      expect(
          html,
          contains(
              '<p>Teks &lt;b&gt;mentah&lt;/b&gt; &amp; &quot;kutip&quot;</p>'));
    });

    test('returns empty string for empty document', () {
      const doc = SamsungNotesDocument(text: '', runs: [], images: []);
      expect(buildSamsungNotesHtml(doc), '');
    });
  });
}
