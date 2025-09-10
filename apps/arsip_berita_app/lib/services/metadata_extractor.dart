import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart' as dom;

String normalizeUrl(String input) {
  try {
    final u = Uri.parse(input);
    final qp = Map.of(u.queryParameters)..removeWhere((k, v) => const {
      'utm_source','utm_medium','utm_campaign','utm_term','utm_content','fbclid','gclid'
    }.contains(k));
    final nu = Uri(
      scheme: u.scheme,
      userInfo: u.userInfo,
      host: u.host,
      port: u.hasPort ? u.port : null,
      path: u.path,
      queryParameters: qp.isEmpty ? null : qp,
    );
    return nu.toString();
  } catch (_) {
    return input;
  }
}

class ExtractedMetadata {
  final String? canonicalUrl;
  final String? title;
  final String? description;
  final String? excerpt;
  ExtractedMetadata({this.canonicalUrl, this.title, this.description, this.excerpt});
}

class MetadataExtractor {
  Future<ExtractedMetadata?> fetch(String url) async {
    var fixedUrl = url.trim();
    if (fixedUrl.startsWith('htps://')) {
      fixedUrl = fixedUrl.replaceFirst('htps://', 'https://');
    }
    final res = await http.get(Uri.parse(fixedUrl));
    if (res.statusCode < 200 || res.statusCode >= 300) return null;
    final doc = html_parser.parse(res.body);
    return _extract(doc, res.request?.url.toString() ?? fixedUrl);
  }

  ExtractedMetadata _extract(dom.Document doc, String baseUrl) {
    String? _meta(String selector) => doc.querySelector(selector)?.attributes['content'];
    final title = _meta('meta[property="og:title"]') ?? _meta('meta[name="twitter:title"]') ?? doc.querySelector('title')?.text;
    final description = _meta('meta[property="og:description"]') ?? _meta('meta[name="description"]');
    final canonical = doc.querySelector('link[rel="canonical"]')?.attributes['href'];
    final canonAbs = canonical == null ? null : Uri.parse(baseUrl).resolve(canonical).toString();
    final paragraphs = doc.querySelectorAll('p').map((e) => e.text.trim()).where((t) => t.length > 40).toList();
    final excerpt = description ?? (paragraphs.take(3).join(' ').substring(0, paragraphs.isNotEmpty ? (paragraphs.join(' ').length.clamp(0, 500)) : 0));
    return ExtractedMetadata(
      canonicalUrl: canonAbs != null ? normalizeUrl(canonAbs) : null,
      title: title,
      description: description,
      excerpt: excerpt.isEmpty ? null : excerpt,
    );
  }
}

