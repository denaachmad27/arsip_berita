import 'dart:convert';

class ExportService {
  static String toCsv(List<Map<String, dynamic>> rows) {
    if (rows.isEmpty) return '';
    final headers = rows.first.keys.toList();
    final sb = StringBuffer()
      ..writeln(headers.join(','));
    for (final r in rows) {
      sb.writeln(headers.map((h) => _csvEscape(r[h])).join(','));
    }
    return sb.toString();
  }

  static String toJsonPretty(List<Map<String, dynamic>> rows) => const JsonEncoder.withIndent('  ').convert(rows);

  static String _csvEscape(dynamic v) {
    final s = (v ?? '').toString();
    if (s.contains(',') || s.contains('"') || s.contains('\n')) {
      return '"' + s.replaceAll('"', '""') + '"';
    }
    return s;
  }
}

