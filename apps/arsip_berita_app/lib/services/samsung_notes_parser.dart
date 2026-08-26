import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_quill/quill_delta.dart';

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
  /// Jumlah minimum karakter ASCII pada bagian tengah rentang campuran
  /// (CJK + Latin) agar rentang tersebut dianggap isi catatan, bukan
  /// metadata pendek seperti "笔记 2024-01-15 10:30".
  static const int _minAsciiForMixed = 20;

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
      final normalized = file.name.replaceAll('\\', '/');
      final lower = normalized.toLowerCase();
      if (lower == 'note.note' || lower.endsWith('/note.note')) {
        noteFile = file;
      } else if (lower == 'end_tag.bin' || lower.endsWith('/end_tag.bin')) {
        endTagFile = file;
      } else if (_isImageFile(normalized, file)) {
        mediaFiles.add(file);
      }
    }

    // Urutkan media sesuai urutan file asli di dalam catatan
    mediaFiles.sort(
      (a, b) => _mediaSortKey(a.name.replaceAll('\\', '/'))
          .compareTo(_mediaSortKey(b.name.replaceAll('\\', '/'))),
    );

    final images = <SamsungNoteImage>[
      for (final file in mediaFiles)
        () {
          final data = _asBytes(file);
          return SamsungNoteImage(
            name: file.name.replaceAll('\\', '/'),
            mimeType: _mimeForName(file.name, data),
            data: data,
          );
        }(),
    ];

    var text = '';
    var runs = const <SamsungTextRun>[];
    if (noteFile != null) {
      final data = _asBytes(noteFile);
      final decoded = _decodeNoteText(data, imageCount: images.length);
      if (decoded != null) {
        text = decoded.text;
        runs = decoded.runs;
      }
    }

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

  _NoteText? _decodeNoteText(List<int> data, {int imageCount = 0}) {
    final ranges = _textRanges(data);
    if (ranges.isEmpty) return null;

    final normalizedRanges = ranges.map((r) {
      final cleanText = r.text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
      return _Range(cleanText, r.textEnd, r.stripStart);
    }).toList();

    final totalText = normalizedRanges.map((r) => r.text).join('\n');
    final hasUfffc =
        totalText.contains('\uFFFC') || totalText.contains('\uFFFD');

    final textSegments = <String>[];
    final separators = <String>[];

    for (var i = 0; i < normalizedRanges.length; i++) {
      textSegments.add(normalizedRanges[i].text);
      if (i < normalizedRanges.length - 1) {
        if (!hasUfffc && imageCount > 0 && i < imageCount) {
          separators.add('\n\n\uFFFC\n\n');
        } else {
          separators.add('\n\n');
        }
      }
    }

    final sb = StringBuffer();
    for (var i = 0; i < textSegments.length; i++) {
      sb.write(textSegments[i]);
      if (i < separators.length) {
        sb.write(separators[i]);
      }
    }
    final text = sb.toString();

    // Gaya teks (bold/italic) biasanya diletakkan setelah rentang terakhir
    // di `note.note`.
    final styles = data.sublist(ranges.last.textEnd);
    final rawRuns = _parseStyleRuns(styles, text.length);

    // Hitung penyesuaian offset rentang
    var baseOffset = 0;
    for (var i = 0; i < normalizedRanges.length - 1; i++) {
      baseOffset += normalizedRanges[i].text.length + separators[i].length;
    }
    baseOffset += normalizedRanges.last.stripStart;

    final runs = <SamsungTextRun>[];
    for (final run in rawRuns) {
      final start = run.start - baseOffset;
      final end = run.end - baseOffset;
      if (end <= 0) continue;
      runs.add(SamsungTextRun(
        start: start.clamp(0, text.length),
        end: end.clamp(0, text.length),
        bold: run.bold,
        italic: run.italic,
      ));
    }
    return _NoteText(text: text, runs: runs);
  }

  /// Kumpulkan rentang teks UTF-16LE yang merupakan isi catatan.
  ///
  /// `note.note` dapat menyimpan metadata (judul, timestamp, label, dsb.)
  /// sebagai rentang UTF-16LE tersendiri — sering kali berisi teks
  /// Mandarin/CJK. Untuk mencegah metadata itu muncul di artikel hasil
  /// import:
  ///
  /// - rentang murni ASCII dianggap bagian dari catatan;
  /// - rentang campuran (CJK menempel pada isi) dibuang tepinya, lalu
  ///   dipertahankan hanya jika bagian tengahnya cukup panjang;
  /// - rentang yang tersisa dijadikan fallback untuk catatan CJK-only.
  List<_Range> _textRanges(List<int> data) {
    final candidates = <_Range>[];
    _Range? fallback;
    var offset = 0;
    while (offset + 2 <= data.length) {
      if (!_isPrintableUnitAt(data, offset)) {
        offset += 2;
        continue;
      }
      var end = offset;
      while (end + 2 <= data.length && _isPrintableUnitAt(data, end)) {
        end += 2;
      }

      final units = <int>[];
      for (var i = offset; i < end; i += 2) {
        units.add(data[i] | (data[i + 1] << 8));
      }
      final rawText = String.fromCharCodes(units);
      final trimmed = rawText.trim();
      final score = _scoreText(trimmed);

      if (score.total < 3) {
        offset = end;
        continue;
      }

      if (score.ratioOk) {
        if (!_containsNonAscii(trimmed)) {
          candidates.add(_Range(
            trimmed,
            end,
            _leadingWhitespaceCount(rawText),
          ));
        } else {
          final startStrip = _leadingStripCount(trimmed);
          final endStrip = _trailingStripCount(trimmed);
          if (startStrip + endStrip < trimmed.length) {
            final stripped = trimmed.substring(
              startStrip,
              trimmed.length - endStrip,
            );
            if (_scoreText(stripped).ascii >= _minAsciiForMixed) {
              candidates.add(_Range(
                stripped,
                end,
                startStrip + _leadingWhitespaceCount(rawText),
              ));
            }
          }
        }
      } else {
        // Rentang non-ASCII atau terlalu sedikit ASCII-nya — simpan
        // sebagai fallback (dipakai jika tidak ada kandidat ASCII).
        final startStrip = _leadingStripCount(trimmed);
        final endStrip = _trailingStripCount(trimmed);
        final middle = startStrip + endStrip < trimmed.length
            ? trimmed.substring(startStrip, trimmed.length - endStrip)
            : trimmed;
        final middleScore = _scoreText(middle);
        if (fallback == null || middleScore.total > _scoreText(fallback.text).total) {
          fallback = _Range(
            middle,
            end,
            startStrip + _leadingWhitespaceCount(rawText),
          );
        }
      }
      offset = end;
    }

    if (candidates.isNotEmpty) return candidates;
    if (fallback != null) return [fallback];
    return const [];
  }

  bool _isPrintableUnitAt(List<int> data, int offset) {
    final unit = data[offset] | (data[offset + 1] << 8);
    return unit == 0x09 ||
        unit == 0x0A ||
        unit == 0x0D ||
        (unit >= 0x20 && unit <= 0xD7FF) ||
        (unit >= 0xD800 && unit <= 0xDFFF) ||
        (unit >= 0xE000 && unit <= 0xFFFD);
  }

  /// `true` jika `text` mengandung karakter non-ASCII selain whitespace.
  bool _containsNonAscii(String text) {
    for (final code in text.codeUnits) {
      if (_isWhitespaceUnit(code)) continue;
      if (_isAsciiAlnum(code) || _isAsciiPunctuation(code)) continue;
      return true;
    }
    return false;
  }

  /// Jumlah unit UTF-16 di awal teks yang dibuang: whitespace atau
  /// karakter non-ASCII (CJK/emoji). Berhenti di karakter ASCII pertama.
  int _leadingStripCount(String text) {
    var i = 0;
    while (i < text.length) {
      final code = text.codeUnitAt(i);
      if (_isWhitespaceUnit(code)) {
        i++;
        continue;
      }
      if (_isAsciiAlnum(code) || _isAsciiPunctuation(code)) break;
      i++;
    }
    return i;
  }

  /// Jumlah unit UTF-16 di akhir teks yang dibuang (simetris dari
  /// [_leadingStripCount]).
  int _trailingStripCount(String text) {
    var i = text.length;
    while (i > 0) {
      final code = text.codeUnitAt(i - 1);
      if (_isWhitespaceUnit(code)) {
        i--;
        continue;
      }
      if (_isAsciiAlnum(code) || _isAsciiPunctuation(code)) break;
      i--;
    }
    return text.length - i;
  }

  int _leadingWhitespaceCount(String text) {
    var i = 0;
    while (i < text.length && _isWhitespaceUnit(text.codeUnitAt(i))) {
      i++;
    }
    return i;
  }

  _TextScore _scoreText(String text) {
    var total = 0;
    var ascii = 0;
    for (final code in text.codeUnits) {
      if (_isWhitespaceUnit(code)) continue;
      total++;
      if (_isAsciiAlnum(code) || _isAsciiPunctuation(code)) ascii++;
    }
    return _TextScore(total, ascii);
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

  static const _imageExtensions = {
    '.jpg',
    '.jpeg',
    '.png',
    '.webp',
    '.gif',
    '.bmp',
    '.svg',
    '.heic',
    '.heif',
    '.jfif',
    '.pjpeg',
    '.pjp',
    '.tif',
    '.tiff',
    '.ico',
  };

  static const _nonImageExtensions = {
    '.note',
    '.bin',
    '.page',
    '.xml',
    '.json',
    '.txt',
    '.dat',
    '.sqlite',
    '.db',
  };

  bool _isImageFile(String normalizedName, ArchiveFile file) {
    final lower = normalizedName.toLowerCase();
    for (final ext in _nonImageExtensions) {
      if (lower.endsWith(ext)) return false;
    }
    for (final ext in _imageExtensions) {
      if (lower.endsWith(ext)) return true;
    }
    if (lower.startsWith('media/') ||
        lower.startsWith('images/') ||
        lower.startsWith('attachments/') ||
        lower.startsWith('resources/') ||
        lower.startsWith('secmedia/') ||
        lower.startsWith('attached/')) {
      return true;
    }
    return false;
  }

  int _mediaSortKey(String name) {
    final fileName = name.split('/').last;
    final match = RegExp(r'\d+').firstMatch(fileName);
    if (match != null) {
      return int.tryParse(match.group(0)!) ?? (1 << 30);
    }
    return 1 << 30;
  }

  String _mimeForName(String name, [List<int>? bytes]) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.gif')) return 'image/gif';
    if (lower.endsWith('.bmp')) return 'image/bmp';
    if (lower.endsWith('.svg')) return 'image/svg+xml';
    if (lower.endsWith('.heic')) return 'image/heic';
    if (lower.endsWith('.heif')) return 'image/heif';
    if (lower.endsWith('.tif') || lower.endsWith('.tiff')) return 'image/tiff';
    if (lower.endsWith('.ico')) return 'image/x-icon';
    if (lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.jfif') ||
        lower.endsWith('.pjpeg') ||
        lower.endsWith('.pjp')) {
      return 'image/jpeg';
    }
    if (bytes != null && bytes.length >= 4) {
      if (bytes[0] == 0x89 &&
          bytes[1] == 0x50 &&
          bytes[2] == 0x4E &&
          bytes[3] == 0x47) {
        return 'image/png';
      }
      if (bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) {
        return 'image/jpeg';
      }
      if (bytes[0] == 0x47 &&
          bytes[1] == 0x49 &&
          bytes[2] == 0x46 &&
          bytes[3] == 0x38) {
        return 'image/gif';
      }
      if (bytes[0] == 0x42 && bytes[1] == 0x4D) {
        return 'image/bmp';
      }
      if (bytes.length >= 12 &&
          bytes[0] == 0x52 &&
          bytes[1] == 0x49 &&
          bytes[2] == 0x46 &&
          bytes[3] == 0x46 &&
          bytes[8] == 0x57 &&
          bytes[9] == 0x45 &&
          bytes[10] == 0x42 &&
          bytes[11] == 0x50) {
        return 'image/webp';
      }
    }
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

class _Range {
  final String text;
  final int textEnd;
  final int stripStart;
  const _Range(this.text, this.textEnd, this.stripStart);
}

class _TextScore {
  final int total;
  final int ascii;
  const _TextScore(this.total, this.ascii);

  bool get ratioOk => total >= 3 && ascii * 4 >= total * 3;
}

/// Bangun HTML (paragraf `<p>`) dari dokumen Samsung Notes untuk di-load
/// ke editor Quill. Gaya bold/italic dikonversi ke `<strong>`/`<em>`,
/// gambar menjadi data URI base64 dengan lebar default 320.
String buildSamsungNotesHtml(SamsungNotesDocument doc) {
  final buffer = StringBuffer();
  final text = doc.text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  var imageIndex = 0;

  void insertImageHtml(SamsungNoteImage image) {
    buffer.write(
      '<p><img src="data:${image.mimeType};base64,${base64Encode(image.data)}" width="320"></p>',
    );
  }

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
    var i = 0;
    var paragraphStart = 0;
    var paragraphNumber = 0;

    bool isFullyBold(int start, int end) {
      var hasText = false;
      for (var index = start; index < end; index++) {
        final code = text.codeUnitAt(index);
        if (code == 0x09 ||
            code == 0x0A ||
            code == 0x0B ||
            code == 0x0C ||
            code == 0x0D ||
            code == 0x20 ||
            code == 0xA0) {
          continue;
        }
        hasText = true;
        if (bold[index] == 0) return false;
      }
      return hasText;
    }

    void flushParagraph() {
      if (paragraph == null) {
        // Baris kosong di note -> pertahankan sebagai paragraf kosong / jeda baris
        buffer.write('<p><br></p>');
        paragraphNumber++;
        return;
      }
      final content = paragraph.toString();
      if (content.isNotEmpty) {
        final heading = paragraphNumber == 0 && isFullyBold(paragraphStart, i)
            ? 'h1'
            : paragraphNumber == 1 && isFullyBold(paragraphStart, i)
                ? 'h2'
                : 'p';
        buffer.write('<$heading>$content</$heading>');
      } else {
        buffer.write('<p><br></p>');
      }
      paragraph = null;
      paragraphNumber++;
    }

    while (i < text.length) {
      if (text.codeUnitAt(i) == 0xFFFC || text.codeUnitAt(i) == 0xFFFD) {
        if (paragraph != null && paragraph.toString().isNotEmpty) {
          flushParagraph();
        }
        if (imageIndex < doc.images.length) {
          insertImageHtml(doc.images[imageIndex]);
          imageIndex++;
        }
        i++;
        paragraphStart = i;
        continue;
      }

      var j = i;
      while (j < text.length &&
          bold[j] == bold[i] &&
          italic[j] == italic[i] &&
          text[j] != '\n' &&
          text.codeUnitAt(j) != 0xFFFC &&
          text.codeUnitAt(j) != 0xFFFD) {
        j++;
      }
      // Jangan membelah pasangan surrogate (emoji dll): jika `j` jatuh di
      // low surrogate, perluas chunk agar pasangan lengkap ikut.
      if (j < text.length && j > i && _isLowSurrogate(text.codeUnitAt(j))) {
        j++;
      }
      final chunk = text.substring(i, j);
      if (chunk.isNotEmpty) {
        final escaped = const HtmlEscape(HtmlEscapeMode.element).convert(chunk);
        var styled = escaped;
        if (italic[i] == 1) styled = '<em>$styled</em>';
        if (bold[i] == 1) styled = '<strong>$styled</strong>';
        paragraph ??= StringBuffer();
        paragraph!.write(styled);
      }
      i = j;
      if (i < text.length && text[i] == '\n') {
        flushParagraph();
        i++;
        paragraphStart = i;
      }
    }
    if (paragraph != null && paragraph.toString().isNotEmpty) {
      flushParagraph();
    }
  }

  // Jika masih ada gambar yang belum terpasang dari posisi inline \uFFFC
  while (imageIndex < doc.images.length) {
    insertImageHtml(doc.images[imageIndex]);
    imageIndex++;
  }

  return buffer.toString();
}

bool _isLowSurrogate(int codeUnit) {
  return codeUnit >= 0xDC00 && codeUnit <= 0xDFFF;
}

String extFromMime(String mimeType) {
  final lower = mimeType.toLowerCase();
  if (lower.contains('png')) return 'png';
  if (lower.contains('webp')) return 'webp';
  if (lower.contains('gif')) return 'gif';
  if (lower.contains('bmp')) return 'bmp';
  if (lower.contains('svg')) return 'svg';
  if (lower.contains('heic')) return 'heic';
  if (lower.contains('heif')) return 'heif';
  return 'jpg';
}

/// Bangun Delta Flutter Quill dari dokumen Samsung Notes.
/// Menghasilkan format rich text dan image embed yang siap digunakan oleh
/// QuillController maupun disimpan ke database.
Delta buildSamsungNotesDelta(SamsungNotesDocument doc) {
  final delta = Delta();
  final text = doc.text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  var imageIndex = 0;

  void insertImageDelta(SamsungNoteImage image) {
    final dataUri =
        'data:${image.mimeType};base64,${base64Encode(image.data)}';
    delta.insert({'image': dataUri});
    delta.insert('\n');
  }

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

    var i = 0;
    var paragraphStart = 0;
    var paragraphNumber = 0;
    var paragraphHasContent = false;

    bool isFullyBold(int start, int end) {
      var hasText = false;
      for (var index = start; index < end; index++) {
        final code = text.codeUnitAt(index);
        if (code == 0x09 ||
            code == 0x0A ||
            code == 0x0B ||
            code == 0x0C ||
            code == 0x0D ||
            code == 0x20 ||
            code == 0xA0) {
          continue;
        }
        hasText = true;
        if (bold[index] == 0) return false;
      }
      return hasText;
    }

    while (i < text.length) {
      if (text.codeUnitAt(i) == 0xFFFC || text.codeUnitAt(i) == 0xFFFD) {
        if (paragraphHasContent) {
          delta.insert('\n');
          paragraphHasContent = false;
        }
        if (imageIndex < doc.images.length) {
          insertImageDelta(doc.images[imageIndex]);
          imageIndex++;
        }
        i++;
        paragraphStart = i;
        continue;
      }

      var j = i;
      while (j < text.length &&
          bold[j] == bold[i] &&
          italic[j] == italic[i] &&
          text[j] != '\n' &&
          text.codeUnitAt(j) != 0xFFFC &&
          text.codeUnitAt(j) != 0xFFFD) {
        j++;
      }
      if (j < text.length && j > i && _isLowSurrogate(text.codeUnitAt(j))) {
        j++;
      }
      final chunk = text.substring(i, j);
      if (chunk.isNotEmpty) {
        final attrs = <String, dynamic>{};
        if (bold[i] == 1) attrs['bold'] = true;
        if (italic[i] == 1) attrs['italic'] = true;
        delta.insert(chunk, attrs.isEmpty ? null : attrs);
        paragraphHasContent = true;
      }
      i = j;
      if (i < text.length && text[i] == '\n') {
        if (paragraphHasContent) {
          final isHeading1 =
              paragraphNumber == 0 && isFullyBold(paragraphStart, i);
          final isHeading2 =
              paragraphNumber == 1 && isFullyBold(paragraphStart, i);
          if (isHeading1) {
            delta.insert('\n', {'header': 1});
          } else if (isHeading2) {
            delta.insert('\n', {'header': 2});
          } else {
            delta.insert('\n');
          }
        } else {
          // Baris kosong -> insert baris kosong di Delta
          delta.insert('\n');
        }
        i++;
        paragraphStart = i;
        paragraphNumber++;
        paragraphHasContent = false;
      }
    }

    if (paragraphHasContent) {
      final isHeading1 =
          paragraphNumber == 0 && isFullyBold(paragraphStart, i);
      final isHeading2 =
          paragraphNumber == 1 && isFullyBold(paragraphStart, i);
      if (isHeading1) {
        delta.insert('\n', {'header': 1});
      } else if (isHeading2) {
        delta.insert('\n', {'header': 2});
      } else {
        delta.insert('\n');
      }
    }
  }

  // Jika masih ada gambar yang belum terpasang dari posisi inline \uFFFC
  while (imageIndex < doc.images.length) {
    insertImageDelta(doc.images[imageIndex]);
    imageIndex++;
  }

  if (delta.isEmpty) {
    delta.insert('\n');
  }

  return delta;
}


