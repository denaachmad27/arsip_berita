import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

class RSSNewsService {
  // RSS feeds dari media Indonesia (100% gratis)
  static const Map<String, String> _rssSources = {
    'Detik News': 'https://news.detik.com/rss',
    'Kompas': 'https://www.kompas.com/rss/all',
    'Tempo': 'https://rss.tempo.co/',
    'CNN Indonesia': 'https://www.cnnindonesia.com/rss',
    'Liputan6': 'https://www.liputan6.com/rss',
    'Republika': 'https://www.republika.co.id/rss',
    'Viva': 'https://www.viva.co.id/rss',
    'Suara': 'https://www.suara.com/rss',
    'Okezone': 'https://rss.okezone.com/',
    'Sindonews': 'https://www.sindonews.com/rss',
  };

  Future<String> searchNews(String query, {int maxResults = 5}) async {
    try {
      final List<Map<String, dynamic>> allArticles = [];

      // Fetch dari multiple RSS sources
      for (final entry in _rssSources.entries) {
        try {
          final articles = await _fetchRSSFeed(entry.key, entry.value, query);
          allArticles.addAll(articles);

          // Limit untuk performa
          if (allArticles.length >= maxResults * 2) break;
        } catch (e) {
          print('Error fetching ${entry.key}: $e');
          continue; // Skip source yang error
        }
      }

      // Sort by relevance (simple keyword matching)
      final relevantArticles = _sortArticlesByRelevance(allArticles, query)
          .take(maxResults)
          .toList();

      return _formatNewsResults(relevantArticles, query);
    } catch (e) {
      print('RSS search error: $e');
      return _getFallbackResponse(query);
    }
  }

  Future<List<Map<String, dynamic>>> _fetchRSSFeed(
    String sourceName,
    String rssUrl,
    String query
  ) async {
    try {
      final response = await http.get(
        Uri.parse(rssUrl),
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}');
      }

      final document = XmlDocument.parse(response.body);
      final articles = <Map<String, dynamic>>[];

      final items = document.findAllElements('item');
      final lowerQuery = query.toLowerCase();

      for (final item in items.take(10)) { // Limit per source
        try {
          final title = item.getElement('title')?.innerText ?? '';
          final description = item.getElement('description')?.innerText ?? '';
          final link = item.getElement('link')?.innerText ?? '';
          final pubDate = item.getElement('pubDate')?.innerText ?? '';

          // Simple relevance check
          if (_isRelevantToQuery(title, description, lowerQuery)) {
            articles.add({
              'title': _cleanText(title),
              'description': _cleanText(description),
              'link': link,
              'source': sourceName,
              'pubDate': _parseDate(pubDate),
              'relevanceScore': _calculateRelevanceScore(title, description, lowerQuery),
            });
          }
        } catch (e) {
          continue; // Skip invalid items
        }
      }

      return articles;
    } catch (e) {
      throw Exception('Failed to parse RSS: $e');
    }
  }

  bool _isRelevantToQuery(String title, String description, String query) {
    final titleLower = title.toLowerCase();
    final descLower = description.toLowerCase();
    final queryLower = query.toLowerCase();

    // Keywords untuk setiap kategori
    final Map<String, List<String>> categoryKeywords = {
      'politik': ['politik', 'pemerintah', 'presiden', 'menteri', 'dpr', 'kpu', 'pilkada', 'partai', 'koalisi', 'kebijakan', 'negara', 'dewan', 'legislatif', 'parlemen'],
      'ekonomi': ['ekonomi', 'bisnis', 'investasi', 'saham', 'uang', 'inflasi', 'bank', 'bjb', 'bri', 'mandiri', 'bca', 'harga', 'pasar', 'dagang', 'trade', 'ekonomi'],
      'olahraga': ['bola', 'sepakbola', 'persib', 'persija', 'timnas', 'liga', 'pertandingan', 'gol', 'olahraga', 'sport', 'athlete', 'championship', 'olahraga'],
      'teknologi': ['teknologi', 'gadget', 'smartphone', 'laptop', 'aplikasi', 'startup', 'digital', 'internet', 'ai', 'artificial intelligence', 'tech'],
      'kesehatan': ['kesehatan', 'obat', 'rumah sakit', 'dokter', 'penyakit', 'virus', 'covid', 'vaksin', 'medical', 'kesehatan', 'medicine'],
      'pendidikan': ['pendidikan', 'sekolah', 'universitas', 'siswa', 'mahasiswa', 'guru', 'kuliah', 'belajar', 'education', 'akademik'],
      'hukum': ['hukum', 'pengadilan', 'kasus', 'hakim', 'jaksa', 'kepolisian', 'polisi', 'kriminal', 'korupsi', 'legal', 'undang-undang'],
      'internasional': ['internasional', 'luar negeri', 'asing', 'dunia', 'global', 'asean', 'pbb', 'un', 'foreign', 'international'],
    };

    // Detect kategori dari query
    String detectedCategory = 'general';
    for (final category in categoryKeywords.keys) {
      if (queryLower.contains(category)) {
        detectedCategory = category;
        break;
      }
    }

    // Jika general, gunakan logic biasa
    if (detectedCategory == 'general') {
      final queryWords = queryLower.split(' ').where((w) => w.length > 2).toList();
      if (queryWords.isEmpty) return true;
      return queryWords.any((word) => titleLower.contains(word) || descLower.contains(word));
    }

    // Jika kategori spesifik, filter lebih ketat
    final categoryKeywordsList = categoryKeywords[detectedCategory] ?? [];

    // Check relevance: harus mengandung keywords kategori OR query keywords
    final hasCategoryKeyword = categoryKeywordsList.any((keyword) =>
        titleLower.contains(keyword) || descLower.contains(keyword));

    final hasQueryKeyword = queryLower.split(' ').any((word) => word.length > 2 &&
        (titleLower.contains(word) || descLower.contains(word)));

    return hasCategoryKeyword || hasQueryKeyword;
  }

  int _calculateRelevanceScore(String title, String description, String query) {
    final titleLower = title.toLowerCase();
    final descLower = description.toLowerCase();
    final queryLower = query.toLowerCase();
    int score = 0;

    final queryWords = queryLower.split(' ');

    // Category keywords mapping
    final Map<String, List<String>> categoryKeywords = {
      'politik': ['politik', 'pemerintah', 'presiden', 'menteri', 'dpr', 'kpu', 'pilkada', 'partai', 'koalisi', 'kebijakan', 'negara', 'dewan', 'legislatif', 'parlemen'],
      'ekonomi': ['ekonomi', 'bisnis', 'investasi', 'saham', 'uang', 'inflasi', 'bank', 'bjb', 'bri', 'mandiri', 'bca', 'harga', 'pasar', 'dagang', 'trade', 'ekonomi'],
      'olahraga': ['bola', 'sepakbola', 'persib', 'persija', 'timnas', 'liga', 'pertandingan', 'gol', 'olahraga', 'sport', 'athlete', 'championship', 'olahraga'],
      'teknologi': ['teknologi', 'gadget', 'smartphone', 'laptop', 'aplikasi', 'startup', 'digital', 'internet', 'ai', 'artificial intelligence', 'tech'],
      'kesehatan': ['kesehatan', 'obat', 'rumah sakit', 'dokter', 'penyakit', 'virus', 'covid', 'vaksin', 'medical', 'kesehatan', 'medicine'],
      'pendidikan': ['pendidikan', 'sekolah', 'universitas', 'siswa', 'mahasiswa', 'guru', 'kuliah', 'belajar', 'education', 'akademik'],
      'hukum': ['hukum', 'pengadilan', 'kasus', 'hakim', 'jaksa', 'kepolisian', 'polisi', 'kriminal', 'korupsi', 'legal', 'undang-undang'],
      'internasional': ['internasional', 'luar negeri', 'asing', 'dunia', 'global', 'asean', 'pbb', 'un', 'foreign', 'international'],
    };

    // Detect category from query
    String detectedCategory = 'general';
    for (final category in categoryKeywords.keys) {
      if (queryLower.contains(category)) {
        detectedCategory = category;
        break;
      }
    }

    // Score for direct query matches
    for (final word in queryWords) {
      if (word.length > 2) {
        if (titleLower.contains(word)) score += 5; // High weight for query words in title
        if (descLower.contains(word)) score += 2; // Medium weight for query words in description
      }
    }

    // Bonus score for category relevance
    if (detectedCategory != 'general') {
      final categoryKeywordsList = categoryKeywords[detectedCategory] ?? [];
      for (final keyword in categoryKeywordsList) {
        if (titleLower.contains(keyword)) score += 3; // Bonus for category keyword in title
        if (descLower.contains(keyword)) score += 1; // Small bonus for category keyword in description
      }
    }

    // Penalty for containing other category keywords
    for (final category in categoryKeywords.keys) {
      if (category != detectedCategory && categoryKeywords[category] != null) {
        for (final keyword in categoryKeywords[category]!) {
          if (titleLower.contains(keyword)) score -= 1; // Small penalty
        }
      }
    }

    return score;
  }

  List<Map<String, dynamic>> _sortArticlesByRelevance(
    List<Map<String, dynamic>> articles,
    String query
  ) {
    // Sort by relevance score, then by date (newest first)
    articles.sort((a, b) {
      final scoreA = a['relevanceScore'] as int;
      final scoreB = b['relevanceScore'] as int;

      if (scoreA != scoreB) {
        return scoreB.compareTo(scoreA); // Higher score first
      }

      // If same score, sort by date (newest first)
      return (b['pubDate'] as String).compareTo(a['pubDate'] as String);
    });

    return articles;
  }

  String _cleanText(String text) {
    // Remove HTML tags and clean text
    return text
        .replaceAll(RegExp(r'<[^>]*>'), '') // Remove HTML tags
        .replaceAll(RegExp(r'&[^;]+;'), ' ') // Remove HTML entities
        .replaceAll(RegExp(r'\s+'), ' ') // Normalize whitespace
        .trim();
  }

  String _parseDate(String pubDate) {
    try {
      // Try to parse RFC date format
      final date = DateTime.tryParse(pubDate) ?? DateTime.now();
      return '${date.day}-${date.month}-${date.year}';
    } catch (e) {
      return DateTime.now().toString().substring(0, 10);
    }
  }

  String _formatNewsResults(List<Map<String, dynamic>> articles, String query) {
    if (articles.isEmpty) {
      return '''
🔍 **Hasil Pencarian Berita: "$query"**

❌ Tidak ditemukan berita terkait yang spesifik.

**Sumber Berita yang Tersedia:**
📰 Detik News: detik.com
📰 Kompas: kompas.com
📰 Tempo: tempo.co
📰 CNN Indonesia: cnnindonesia.com
📰 Liputan6: liputan6.com
📰 Republika: republika.co.id
📰 Viva: viva.co.id

💡 **Tips:** Coba dengan kata kunci yang lebih spesifik atau kunjungi langsung website media di atas.
''';
    }

    final formattedResults = articles.asMap().entries.map((entry) {
      final index = entry.key + 1;
      final article = entry.value;
      final title = article['title'] as String;
      final description = article['description'] as String;
      final source = article['source'] as String;
      final pubDate = article['pubDate'] as String;
      final link = article['link'] as String;

      return '''
**$index. $title**
📰 Sumber: $source
📅 Tanggal: $pubDate

${description.length > 250 ? '${description.substring(0, 250)}...' : description}

🔗 **Link Berita:** $link

---
''';
    }).join('\n');

    return '''
🔍 **Hasil Pencarian Berita: "$query"**
*Dari ${articles.length} sumber RSS Indonesia*

$formattedResults

💡 **Akses Langsung Link Berita:**
Gunakan link di atas untuk membaca artikel lengkap dari sumber media Indonesia.
Copy URL dan paste di browser untuk membaca.
''';
  }

  String _getFallbackResponse(String query) {
    return '''
🔍 **Pencarian Berita: "$query"**

❌ **RSS feeds sedang tidak tersedia** - Kemungkinan masalah koneksi atau server.

**Akses Langsung ke Sumber Berita:**
📱 **Website Resmi:**
• Detik News: https://news.detik.com
• Kompas: https://www.kompas.com
• Tempo: https://www.tempo.co
• CNN Indonesia: https://www.cnnindonesia.com
• Liputan6: https://www.liputan6.com
• Republika: https://www.republika.co.id
• Viva: https://www.viva.co.id

🌐 **Cara Manual Google:**
Cari: "$query site:detik.com"
Contoh: "politik hari ini site:kompas.com"

**Template Arsip Berita:**
Gunakan Ask AI dengan perintah:
- "Buat template berita politik"
- "Format kutipan media"
- "Contoh arsip berita harian"
''';
  }

  Future<bool> hasConnection() async {
    try {
      final response = await http.get(
        Uri.parse('https://news.detik.com/rss'),
        headers: {'User-Agent': 'Mozilla/5.0'},
      ).timeout(const Duration(seconds: 5));

      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }
}