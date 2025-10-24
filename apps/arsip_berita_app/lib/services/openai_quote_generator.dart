import 'dart:convert';
import 'package:http/http.dart' as http;

class OpenAIQuoteGenerator {
  final String apiKey;

  OpenAIQuoteGenerator({required this.apiKey});

  /// Generate a quote image using DALL-E 3
  /// Returns the URL of the generated image
  Future<String?> generateQuoteImage(String quoteText) async {
    // Build the prompt for generating a visually appealing quote image
    final prompt = _buildQuotePrompt(quoteText);
    return generateQuoteImageWithPrompt(prompt);
  }

  /// Generate a quote image using DALL-E 3 with custom prompt
  /// Returns the URL of the generated image
  Future<String?> generateQuoteImageWithPrompt(String prompt) async {
    const endpoint = 'https://api.openai.com/v1/images/generations';

    try {
      final response = await http.post(
        Uri.parse(endpoint),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $apiKey',
        },
        body: jsonEncode({
          'model': 'dall-e-3',
          'prompt': prompt,
          'n': 1,
          'size': '1024x1024',
          'quality': 'standard',
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final imageUrl = data['data'][0]['url'] as String?;
        return imageUrl;
      } else {
        final errorData = jsonDecode(response.body);
        throw Exception('OpenAI API Error: ${errorData['error']['message']}');
      }
    } catch (e) {
      throw Exception('Failed to generate quote image: $e');
    }
  }

  /// Build a detailed prompt for DALL-E to create a quote image
  String _buildQuotePrompt(String quoteText) {
    // Truncate quote if too long for display
    final displayQuote = quoteText.length > 200
        ? '${quoteText.substring(0, 197)}...'
        : quoteText;

    return '''
Buatkan gambar quote estetik untuk posting di media sosial. Teks utama pada gambar: "$displayQuote" 
Kriteria visual:
- Jangan typo atau kesalahan ejaan pada teks quote.
- Jangan ubah teks quote, baik ditambahkan atau diterjemahkan, apa adanya saja.
- Teks harus jelas dan mudah dibaca, tidak menjadi bagian dari latar belakang.
- Gaya visual minimalis dan modern 
- Komposisi seimbang, fokus pada teks 
- Warna lembut, selaras dengan suasana quote 
- Sertakan ruang kosong yang cukup di sekitar teks (clean layout) 
- Rasio gambar persegi (1:1)
''';
  }
}
