import 'dart:convert';
import 'package:http/http.dart' as http;

/// Service untuk mengoptimalkan prompt menggunakan Gemini 2.0 Flash
/// Gemini akan membantu membuat prompt yang optimal untuk Imagen
class GeminiPromptOptimizer {
  final String apiKey;

  GeminiPromptOptimizer({required this.apiKey});

  /// Generate optimal Imagen prompt using Gemini 2.0 Flash
  /// Returns optimized prompt string
  Future<String> optimizeForImagen({
    required String quoteText,
    String? sourceQuote,
    String? subtitle,
    String? linkAdvertisement,
  }) async {
    const model = 'gemini-2.0-flash-exp';
    const endpoint = 'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent';

    // Build context for Gemini
    String context = 'Quote Text: "$quoteText"';
    if (sourceQuote != null && sourceQuote.isNotEmpty) {
      context += '\nSource: $sourceQuote';
    }
    if (subtitle != null && subtitle.isNotEmpty) {
      context += '\nSubtitle: $subtitle';
    }
    if (linkAdvertisement != null && linkAdvertisement.isNotEmpty) {
      context += '\nCredit/Link: $linkAdvertisement';
    }

    const systemInstruction = '''You are an expert prompt engineer for Google Imagen API.

Your task: Create a perfect prompt for Imagen to generate a quote card image.

CRITICAL RULES for Imagen prompts:
1. Use simple, natural language - NO technical terms
2. Clearly specify text with "Include the text..." format
3. Avoid CSS, pixels, hex codes, measurements, or code-like syntax
4. Keep it concise but descriptive
5. Focus on visual description, not instructions

Good example: "A minimalist quote card. Include the text "Be yourself" with attribution "- Oscar Wilde" below. Use elegant typography, soft gradient background, centered layout, pastel colors"

Bad example: "padding:40px; font-size:24px; color:#333; background:linear-gradient()"

Your output should be ONLY the optimized prompt text, nothing else.''';

    final userPrompt = '''Create an optimal Imagen prompt for this quote card:

$context

Requirements:
- Include ALL text elements (quote, source, subtitle if present, link if present)
- Use natural language description
- No technical/CSS terms
- Describe visual style (gradient background, elegant typography, minimal, modern)
- Make it clear which text goes where (main quote centered, attribution below, etc)

Generate the Imagen prompt now:''';

    try {
      final requestBody = {
        'contents': [
          {
            'parts': [
              {'text': userPrompt}
            ]
          }
        ],
        'systemInstruction': {
          'parts': [
            {'text': systemInstruction}
          ]
        },
        'generationConfig': {
          'temperature': 0.7,
          'topK': 40,
          'topP': 0.95,
          'maxOutputTokens': 500,
        }
      };

      final response = await http.post(
        Uri.parse('$endpoint?key=$apiKey'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode(requestBody),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final candidates = data['candidates'] as List?;

        if (candidates == null || candidates.isEmpty) {
          throw Exception('No candidates in Gemini response');
        }

        final content = candidates[0]['content'];
        final parts = content['parts'] as List?;

        if (parts == null || parts.isEmpty) {
          throw Exception('No parts in Gemini response');
        }

        final optimizedPrompt = parts[0]['text'] as String?;

        if (optimizedPrompt == null || optimizedPrompt.trim().isEmpty) {
          throw Exception('Empty prompt from Gemini');
        }

        return optimizedPrompt.trim();
      } else {
        final errorData = jsonDecode(response.body);
        final errorMessage = errorData['error']?['message'] ?? 'Unknown error';
        throw Exception('Gemini API Error (${response.statusCode}): $errorMessage');
      }
    } catch (e) {
      throw Exception('Failed to optimize prompt with Gemini: $e');
    }
  }
}
