import 'package:arsip_berita_app/services/samsung_notes_folder_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SamsungNoteFileInfo', () {
    test('parses map from platform channel', () {
      final info = SamsungNoteFileInfo.fromMap({
        'uri': 'content://tree/document/abc',
        'name': 'Catatan1.sdocx',
        'size': 2048,
        'lastModified': 1700000000000,
      });

      expect(info.uri, 'content://tree/document/abc');
      expect(info.name, 'Catatan1.sdocx');
      expect(info.size, 2048);
      expect(
        info.lastModified,
        DateTime.fromMillisecondsSinceEpoch(1700000000000),
      );
      expect(info.isSdocx, isTrue);
    });

    test('isSdocx is case-insensitive and rejects other extensions', () {
      expect(
        const SamsungNoteFileInfo(uri: 'u', name: 'A.SDOCX', size: 0).isSdocx,
        isTrue,
      );
      expect(
        const SamsungNoteFileInfo(uri: 'u', name: 'b.txt', size: 0).isSdocx,
        isFalse,
      );
      expect(
        const SamsungNoteFileInfo(uri: 'u', name: 'c.pdf', size: 0).isSdocx,
        isFalse,
      );
    });

    test('handles missing lastModified', () {
      final info = SamsungNoteFileInfo.fromMap({
        'uri': 'u',
        'name': 'n.sdocx',
        'size': 1,
      });
      expect(info.lastModified, isNull);
    });

    test('handles zero lastModified as null', () {
      final info = SamsungNoteFileInfo.fromMap({
        'uri': 'u',
        'name': 'n.sdocx',
        'size': 1,
        'lastModified': 0,
      });
      expect(info.lastModified, isNull);
    });
  });
}
