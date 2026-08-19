import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// Run gaya teks (bold/italic) pada teks ketikan Samsung Notes.
/// `start`/`end` adalah offset unit UTF-16 ke dalam [SamsungNotesDocument.text].
class SamsungTextRun {
  final int start;
  final int end;
  final bool bold;
  final bool italic;

  const SamsungTextRun({
    required this.start,
    required this.end,
    required this.bold,
    required this.italic,
  });
}

class SamsungNoteImage {
  final String name;
  final String mimeType;
  final Uint8List data;

  const SamsungNoteImage({
    required this.name,
    required this.mimeType,
    required this.data,
  });
}

/// Hasil parsing file Samsung Notes (.sdocx).
/// Hanya teks ketikan (keyboard) yang diekstrak; tulisan tangan (stroke)
/// pada file `.page` tidak didukung dan diabaikan.
class SamsungNotesDocument {
  final String text;
  final List<SamsungTextRun> runs;
  final DateTime? createdAt;
  final DateTime? modifiedAt;
  final List<SamsungNoteImage> images;

  const SamsungNotesDocument({
    required this.text,
    required this.runs,
    this.createdAt,
    this.modifiedAt,
    required this.images,
  });
}

class SamsungNotesParseException implements Exception {
  final String message;
  const SamsungNotesParseException(this.message);

  @override
  String toString() => message;
}

/// Parser untuk file Samsung Notes (.sdocx).
///
/// Format `.sdocx` adalah arsip ZIP yang berisi:
/// - `note.note`   : metadata & teks ketikan (UTF-16LE) + gaya (TLV)
/// - `end_tag.bin` : timestamp pembuatan/modifikasi (i64 LE)
/// - `media/`      : gambar ter-embed (jpg/png/webp)
/// - `*.page`      : data stroke tulisan tangan (biner, tidak didukung)
///
/// Struktur file direverse-engineer dari pustaka komunitas
/// (mis. https://github.com/twangodev/sdocx).
class SamsungNotesParser {
  /// Parse byte file `.sdocx`.
  ///
  /// Melempar [SamsungNotesParseException] jika file bukan arsip ZIP yang
  /// valid, atau jika tidak ada teks ketikan maupun gambar yang ditemukan.
  SamsungNotesDocument parse(Uint8List bytes) {
    if (bytes.length < 4 || bytes[0] != 0x50 || bytes[1] != 0x4B) {
      throw const SamsungNotesParseException(
        'File bukan arsip Samsung Notes (.sdocx) yang valid.',
      );
    }

    Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (_) {
      throw const SamsungNotesParseException(
        'File tidak dapat dibuka sebagai arsip .sdocx.',
      );
    }

    ArchiveFile? noteFile;
    ArchiveFile? endTagFile;
    final mediaFiles = <ArchiveFile>[];

    for (final file in archive) {
      if (!file.isFile) continue;
      final name = file.name;
      final lower = name.toLowerCase();
      if (name == 'note.note') {
        noteFile = file;
      } else if (name == 'end_tag.bin') {
        endTagFile = file;
      } else if (name.startsWith('media/') &&
          (lower.endsWith('.jpg') ||
              lower.endsWith('.jpeg') ||
              lower.endsWith('.png') ||
              lower.endsWith('.webp'))) {
        mediaFiles.add(file);
      }
    }

    // Urutkan media sesuai urutan file asli di dalam catatan
    // (prefiks angka sebelum '@' pada nama file).
    mediaFiles.sort(
      (a, b) => _mediaSortKey(a.name).compareTo(_mediaSortKey(b.name)),
    );

    var text = '';
    var runs = const <SamsungTextRun>[];
    if (noteFile != null) {
      final data = _asBytes(noteFile);
      final decoded = _decodeNoteText(data);
      if (decoded != null) {
        text = decoded.text;
        runs = decoded.runs;
      }
    }

    final images = <SamsungNoteImage>[
      for (final file in mediaFiles)
        SamsungNoteImage(
          name: file.name,
          mimeType: _mimeForName(file.name),
          data: _asBytes(file),
        ),
    ];

    if (text.trim().isEmpty && images.isEmpty) {
      throw const SamsungNotesParseException(
        'Tidak ditemukan teks ketikan maupun gambar di dalam file ini. '
        'Catatan yang hanya berisi tulisan tangan belum didukung.',
      );
    }

    DateTime? createdAt;
    DateTime? modifiedAt;
    if (endTagFile != null) {
      final data = _asBytes(endTagFile);
      if (data.length >= 0x58) {
        createdAt = _dateFromMs(_leInt64(data, 0x48));
        modifiedAt = _dateFromMs(_leInt64(data, 0x50));
      }
    }

    return SamsungNotesDocument(
      text: text,
      runs: runs,
      createdAt: createdAt,
      modifiedAt: modifiedAt,
      images: images,
    );
  }

  // ---------------------------------------------------------------------
  // Dekode teks ketikan dari note.note
  // ---------------------------------------------------------------------

  _NoteText? _decodeNoteText(List<int> data) {
    final result = _firstUtf16Text(data);
    if (result == null) return null;
    final styles = data.sublist(result.textEnd);
    return _NoteText(
      text: result.text,
      runs: _parseStyleRuns(styles, result.text.length),
    );
  }

  /// Cari rentang teks UTF-16LE terpanjang yang terlihat seperti teks catatan.
  _Utf16Result? _firstUtf16Text(List<int> data) {
    var offset = 0;
    while (offset + 6 <= data.length) {
      var end = offset;
      final units = <int>[];
      while (end + 2 <= data.length) {
        final unit = data[end] | (data[end + 1] << 8);
        final printable = unit == 0x0A || (unit >= 0x20 && unit <= 0xD7FF);
        if (!printable) break;
        units.add(unit);
        end += 2;
      }
      final text = String.fromCharCodes(units);
      final trimmed = text.trim();
      if (_nonWhitespaceCount(trimmed) >= 3 && _looksLikeNoteText(trimmed)) {
        return _Utf16Result(text, end);
      }
      offset += 2;
    }
    return null;
  }

  bool _looksLikeNoteText(String text) {
    var total = 0;
    var common = 0;
    for (final code in text.codeUnits) {
      if (_isWhitespaceUnit(code)) continue;
      total++;
      if (_isAsciiAlnum(code) || _isAsciiPunctuation(code)) common++;
    }
    return total >= 3 && common * 4 >= total * 3;
  }

  int _nonWhitespaceCount(String text) {
    var count = 0;
    for (final code in text.codeUnits) {
      if (!_isWhitespaceUnit(code)) count++;
    }
    return count;
  }

  /// Parse gaya bold (tag 0x05) & italic (tag 0x06) dari data TLV di
  /// belakang teks pada `note.note`.
  List<SamsungTextRun> _parseStyleRuns(List<int> data, int textLen) {
    final runs = <SamsungTextRun>[];
    void collect(int tag, {required bool bold, required bool italic}) {
      const markerBase = 0x18;
      for (var offset = 0; offset + 22 <= data.length; offset++) {
        if (data[offset] != markerBase ||
            data[offset + 1] != 0x00 ||
            data[offset + 2] != tag ||
            data[offset + 3] != 0x00) {
          continue;
        }
        final start = _leUint32(data, offset + 6);
        final end = _leUint32(data, offset + 10);
        final enabled = _leUint32(data, offset + 18) != 0;
        if (enabled && start < end && end <= textLen) {
          runs.add(SamsungTextRun(
            start: start,
            end: end,
            bold: bold,
            italic: italic,
          ));
        }
      }
    }

    collect(0x05, bold: true, italic: false);
    collect(0x06, bold: false, italic: true);
    return runs;
  }

  // ---------------------------------------------------------------------
  // Helper biner
  // ---------------------------------------------------------------------

  Uint8List _asBytes(ArchiveFile file) {
    final content = file.content;
    if (content is Uint8List) return content;
    return Uint8List.fromList(content as List<int>);
  }

  int _leUint32(List<int> data, int offset) {
    return data[offset] |
        (data[offset + 1] << 8) |
        (data[offset + 2] << 16) |
        (data[offset + 3] << 24);
  }

  int _leInt64(List<int> data, int offset) {
    var value = 0;
    for (var i = 7; i >= 0; i--) {
      value = (value << 8) | data[offset + i];
    }
    return value;
  }

  DateTime? _dateFromMs(int ms) {
    if (ms <= 0) return null;
    return DateTime.fromMillisecondsSinceEpoch(ms);
  }

  int _mediaSortKey(String name) {
    final base = name.split('/').last.split('@').first;
    return int.tryParse(base) ?? (1 << 30);
  }

  String _mimeForName(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }

  bool _isWhitespaceUnit(int code) {
    return code == 0x09 ||
        code == 0x0A ||
        code == 0x0B ||
        code == 0x0C ||
        code == 0x0D ||
        code == 0x20 ||
        code == 0xA0;
  }

  bool _isAsciiAlnum(int code) {
    return (code >= 0x30 && code <= 0x39) ||
        (code >= 0x41 && code <= 0x5A) ||
        (code >= 0x61 && code <= 0x7A);
  }

  bool _isAsciiPunctuation(int code) {
    return (code >= 0x21 && code <= 0x2F) ||
        (code >= 0x3A && code <= 0x40) ||
        (code >= 0x5B && code <= 0x60) ||
        (code >= 0x7B && code <= 0x7E);
  }
}

class _NoteText {
  final String text;
  final List<SamsungTextRun> runs;
  const _NoteText({required this.text, required this.runs});
}

class _Utf16Result {
  final String text;
  final int textEnd;
  const _Utf16Result(this.text, this.textEnd);
}

/// Bangun HTML (paragraf `<p>`) dari dokumen Samsung Notes untuk di-load
/// ke editor Quill. Gaya bold/italic dikonversi ke `<strong>`/`<em>`,
/// gambar menjadi data URI base64 dengan lebar default 320.
String buildSamsungNotesHtml(SamsungNotesDocument doc) {
  final buffer = StringBuffer();
  final text = doc.text;

  if (text.trim().isNotEmpty) {
    final bold = Uint8List(text.length);
    final italic = Uint8List(text.length);
    for (final run in doc.runs) {
      final start = run.start.clamp(0, text.length);
      final end = run.end.clamp(start, text.length);
      for (var i = start; i < end; i++) {
        if (run.bold) bold[i] = 1;
        if (run.italic) italic[i] = 1;
      }
    }

    StringBuffer? paragraph;

    void flushParagraph() {
      if (paragraph == null) return;
      final content = paragraph.toString().trim();
      if (content.isNotEmpty) {
        buffer.write('<p>$content</p>');
      }
      paragraph = null;
    }

    var i = 0;
    while (i < text.length) {
      var j = i;
      while (j < text.length &&
          bold[j] == bold[i] &&
          italic[j] == italic[i] &&
          text[j] != '\n') {
        j++;
      }
      // Jangan membelah pasangan surrogate (emoji dll): jika `j` jatuh di
      // low surrogate, perluas chunk agar pasangan lengkap ikut.
      if (j < text.length && j > i && _isLowSurrogate(text.codeUnitAt(j))) {
        j++;
      }
      final chunk = text.substring(i, j);
      if (chunk.isNotEmpty) {
        final escaped =
            const HtmlEscape().convert(chunk).replaceAll('&#47;', '/');
        var styled = escaped;
        if (italic[i] == 1) styled = '<em>$styled</em>';
        if (bold[i] == 1) styled = '<strong>$styled</strong>';
        paragraph ??= StringBuffer();
        paragraph!.write(styled);
      }
      i = j;
      if (i < text.length) {
        if (text[i] == '\n') {
          flushParagraph();
          i++;
        }
      }
    }
    flushParagraph();
  }

  for (final image in doc.images) {
    buffer
      ..write('<p><img src="data:${image.mimeType};base64,')
      ..write(base64Encode(image.data))
      ..write('" width="320"></p>');
  }

  return buffer.toString();
}

bool _isLowSurrogate(int codeUnit) {
  return codeUnit >= 0xDC00 && codeUnit <= 0xDFFF;
}
