import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class WebSearchService {
  static const String _serpApiKeyKey = 'serpapi_api_key';

  Future<String> searchNews(String query, {int maxResults = 5}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final apiKey = prefs.getString(_serpApiKeyKey);

      if (apiKey == null || apiKey.isEmpty) {
        return _getFallbackSearch(query);
      }

      final url = Uri.parse('https://serpapi.com/search.json').replace(queryParameters: {
        'engine': 'google_news',
        'q': query,
        'api_key': apiKey,
        'num': maxResults.toString(),
        'gl': 'id', // Indonesia location
        'hl': 'id', // Indonesia language
      });

      final response = await http.get(
        url,
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return _formatSearchResults(data, query);
      } else {
        return _getFallbackSearch(query);
      }
    } catch (e) {
      print('Web search error: $e');
      return _getFallbackSearch(query);
    }
  }

  String _formatSearchResults(Map<String, dynamic> data, String originalQuery) {
    final results = data['news_results'] as List? ?? [];

    if (results.isEmpty) {
      return '''
🔍 **Hasil Pencarian Berita: "$originalQuery"**

Tidak ditemukan berita terkait yang spesifik. Silakan coba dengan kata kunci lain atau gunakan sumber berita terpercaya berikut:

**Sumber Berita Indonesia Terpercaya:**
- Kompas.com
- Detik.com
- Tempo.co
- CNN Indonesia
- Republika.co.id
- Liputan6.com
- Viva.co.id
''';
    }

    final formattedResults = results.map((result) {
      final title = result['title'] ?? 'Tanpa judul';
      final link = result['link'] ?? '';
      final snippet = result['snippet'] ?? '';
      final source = result['source'] ?? 'Sumber tidak diketahui';
      final date = result['date'] ?? '';

      return '''
**$title**
📰 Sumber: $source
📅 Tanggal: $date
🔗 Link: $link

$snippet

---''';
    }).join('\n');

    return '''
🔍 **Hasil Pencarian Berita: "$originalQuery"**

$formattedResults

**Catatan:** Ini adalah hasil pencarian real-time dari internet. Untuk informasi terlengkap, kunjungi link sumber berita.
''';
  }

  String _getFallbackSearch(String query) {
    return '''
🔍 **Pencarian Berita: "$query"**

❌ **Web search tidak tersedia** - API key belum dikonfigurasi.

**Solusi:**
1. Buka **Settings → AI Settings**
2. Tambahkan **SerpApi Key** untuk web search
3. Dapatkan API key di: https://serpapi.com/

**Sementara ini, gunakan sumber berita manual:**
📱 **Aplikasi Berita Indonesia:**
- Kompas
- Detik
- Tempo
- CNN Indonesia
- Liputan6

🌐 **Website Berita:**
- kompas.com
- detik.com
- tempo.co
- cnnindonesia.com
- liputan6.com
''';
  }

  Future<bool> hasApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    final apiKey = prefs.getString(_serpApiKeyKey);
    return apiKey != null && apiKey.isNotEmpty;
  }

  Future<void> saveApiKey(String apiKey) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_serpApiKeyKey, apiKey);
  }

  Future<String?> getApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_serpApiKeyKey);
  }
}