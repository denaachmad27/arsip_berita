import 'dart:convert';
import 'package:http/http.dart' as http;

class GeminiQuoteGenerator {
  final String apiKey;

  GeminiQuoteGenerator({required this.apiKey});

  /// Generate a quote image using Gemini 2.5 Flash
  /// Returns a data URI (base64 encoded image) that can be used directly
  Future<String?> generateQuoteImageWithPrompt(String prompt) async {
    const geminiModel = 'gemini-2.5-flash-image';
    const endpoint = 'https://generativelanguage.googleapis.com/v1beta/models/$geminiModel:generateContent';

    try {
      final requestBody = {
        'contents': [
          {
            'parts': [
              {'text': prompt}
            ]
          }
        ],
        'generationConfig': {
          'responseModalities': ['Image'],
          'imageConfig': {
            'aspectRatio': '1:1', // Square format for quote images
          }
        }
      };

      final response = await http.post(
        Uri.parse(endpoint),
        headers: {
          'Content-Type': 'application/json',
          'x-goog-api-key': apiKey,
        },
        body: jsonEncode(requestBody),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        // Extract base64 image data from response
        final candidates = data['candidates'] as List?;
        if (candidates == null || candidates.isEmpty) {
          throw Exception('No candidates in response. Response: ${response.body}');
        }

        final content = candidates[0]['content'];
        final parts = content['parts'] as List?;
        if (parts == null || parts.isEmpty) {
          throw Exception('No parts in response. Response: ${response.body}');
        }

        // Get inline data from the first part
        final inlineData = parts[0]['inlineData'];
        if (inlineData == null) {
          throw Exception('No inline data in response. Response: ${response.body}');
        }

        final base64Data = inlineData['data'] as String?;
        if (base64Data == null || base64Data.isEmpty) {
          throw Exception('Base64 data is null or empty. Response: ${response.body}');
        }

        // Get mime type (default to image/png)
        final mimeType = inlineData['mimeType'] as String? ?? 'image/png';

        // Return as data URI
        return 'data:$mimeType;base64,$base64Data';
      } else {
        final errorData = jsonDecode(response.body);
        final errorMessage = errorData['error']?['message'] ?? 'Unknown error';
        throw Exception('Gemini API Error (${response.statusCode}): $errorMessage');
      }
    } catch (e) {
      throw Exception('Failed to generate quote image with Gemini 2.5 Flash: $e');
    }
  }
}
