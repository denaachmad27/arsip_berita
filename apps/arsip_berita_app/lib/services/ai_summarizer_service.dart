import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

class AISummarizerService {
  static const String _aiModelKey = 'ai_model_preference';
  static const String _openaiApiKeyKey = 'openai_api_key';
  static const String _geminiApiKeyKey = 'gemini_api_key';

  Future<String> summarizeText(String content, {String language = 'id', String? customPrompt}) async {
    final prefs = await SharedPreferences.getInstance();
    final selectedModel = prefs.getString(_aiModelKey) ?? 'openai';

    // Debug: Print custom prompt to console
    if (customPrompt != null && customPrompt.isNotEmpty) {
      print('🤖 Custom Prompt: $customPrompt');
    } else {
      print('🤖 No custom prompt provided');
    }

    if (selectedModel == 'openai') {
      return await _summarizeWithOpenAI(content, language: language, customPrompt: customPrompt);
    } else {
      return await _summarizeWithGemini(content, language: language, customPrompt: customPrompt);
    }
  }

  Future<String> _summarizeWithOpenAI(String content, {String language = 'id', String? customPrompt}) async {
    final prefs = await SharedPreferences.getInstance();
    final apiKey = prefs.getString(_openaiApiKeyKey);

    if (apiKey == null || apiKey.isEmpty) {
      throw Exception('OpenAI API key tidak ditemukan. Silakan atur di Settings terlebih dahulu.');
    }

    const endpoint = 'https://api.openai.com/v1/chat/completions';

    final prompt = customPrompt != null && customPrompt.isNotEmpty
        ? language == 'id'
            ? '''Berdasarkan konten berikut, $customPrompt

Konten:
$content

Buatlah jawaban yang jelas dan ringkas dalam bahasa Indonesia.'''
            : '''Based on the following content, $customPrompt

Content:
$content

Provide a clear and concise answer.'''
        : language == 'id'
            ? '''Buatlah ringkasan yang jelas dan ringkas dari konten berikut.
Fokus pada poin-poin utama dan informasi penting.
Ringkasan harus dalam bahasa Indonesia dengan struktur yang mudah dibaca:

Konten:
$content'''
            : '''Create a clear and concise summary of the following content.
Focus on the main points and important information.
The summary should be well-structured and easy to read:

Content:
$content''';

    // Debug: Print final prompt sent to OpenAI
    print('🤖 Final Prompt sent to OpenAI:\n$prompt');

    try {
      final response = await http.post(
        Uri.parse(endpoint),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $apiKey',
        },
        body: jsonEncode({
          'model': 'gpt-3.5-turbo',
          'messages': [
            {
              'role': 'user',
              'content': prompt
            }
          ],
          'max_tokens': 1000,
          'temperature': 0.3,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final summary = data['choices'][0]['message']['content'] as String;
        return summary.trim();
      } else {
        final errorData = jsonDecode(response.body);
        throw Exception('OpenAI API Error: ${errorData['error']['message']}');
      }
    } catch (e) {
      throw Exception('Gagal melakukan ringkasan dengan OpenAI: $e');
    }
  }

  Future<String> _summarizeWithGemini(String content, {String language = 'id', String? customPrompt}) async {
    final prefs = await SharedPreferences.getInstance();
    final apiKey = prefs.getString(_geminiApiKeyKey);

    if (apiKey == null || apiKey.isEmpty) {
      throw Exception('Gemini API key tidak ditemukan. Silakan atur di Settings terlebih dahulu.');
    }

    const endpoint = 'https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash-latest:generateContent';

    final prompt = customPrompt != null && customPrompt.isNotEmpty
        ? language == 'id'
            ? '''Berdasarkan konten berikut, $customPrompt

Konten:
$content

Buatlah jawaban yang jelas dan ringkas dalam bahasa Indonesia.'''
            : '''Based on the following content, $customPrompt

Content:
$content

Provide a clear and concise answer.'''
        : language == 'id'
            ? '''Buatlah ringkasan yang jelas dan ringkas dari konten berikut.
Fokus pada poin-poin utama dan informasi penting.
Ringkasan harus dalam bahasa Indonesia dengan struktur yang mudah dibaca:

Konten:
$content'''
            : '''Create a clear and concise summary of the following content.
Focus on the main points and important information.
The summary should be well-structured and easy to read:

Content:
$content''';

    // Debug: Print final prompt sent to Gemini
    print('🤖 Final Prompt sent to Gemini:\n$prompt');

    try {
      final response = await http.post(
        Uri.parse('$endpoint?key=$apiKey'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'contents': [
            {
              'parts': [
                {
                  'text': prompt
                }
              ]
            }
          ],
          'generationConfig': {
            'temperature': 0.3,
            'maxOutputTokens': 1000,
          },
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final summary = data['candidates'][0]['content']['parts'][0]['text'] as String;
        return summary.trim();
      } else {
        final errorData = jsonDecode(response.body);
        throw Exception('Gemini API Error: ${errorData['error']['message']}');
      }
    } catch (e) {
      throw Exception('Gagal melakukan ringkasan dengan Gemini: $e');
    }
  }

  Future<String> extractTextFromPdf(File pdfFile) async {
    try {
      // Check file size to ensure it's not too large
      final fileSize = await pdfFile.length();
      if (fileSize > 10 * 1024 * 1024) { // 10MB limit
        throw Exception('Ukuran file PDF terlalu besar. Maksimal 10MB.');
      }

      // Check if file exists and is readable
      if (!await pdfFile.exists()) {
        throw Exception('File PDF tidak ditemukan.');
      }

      // Read PDF bytes
      final bytes = await pdfFile.readAsBytes();

      // Load PDF document using Syncfusion
      final PdfDocument document = PdfDocument(inputBytes: bytes);
      String fullText = '';

      // Extract text from each page
      for (int i = 0; i < document.pages.count; i++) {
        final String pageText = PdfTextExtractor(document).extractText(startPageIndex: i, endPageIndex: i);

        if (pageText.trim().isNotEmpty) {
          if (fullText.isNotEmpty) {
            fullText += '\n\n';
          }
          fullText += pageText.trim();
        }
      }

      // Dispose the document
      document.dispose();

      if (fullText.trim().isEmpty) {
        throw Exception('''📄 **PDF Text Tidak Dapat Diekstrak**

PDF yang Anda upload tidak mengandung teks yang dapat diekstrak. Kemungkin:

📌 **PDF adalah gambar scan (image-based)**
• Hasil scan dari dokumen fisik
• Tidak mengandung teks yang bisa dipilih

📌 **PDF dilindungi atau di-password**

**💡 Solusi Cepat:**

**Method 1 - Copy-Paste Manual:**
1. Buka PDF di Adobe Reader/Chrome
2. Pilih text (Ctrl+A)
3. Copy (Ctrl+C) dan paste di "Input Teks Manual"

**Method 2 - Konversi Online:**
• Upload PDF ke Google Drive
• Klik kanan → Buka dengan Google Docs
• Teks akan otomatis ter-extract

**Method 3 - OCR Tools:**
• Adobe Acrobat Pro (berbayar tapi akurat)
• Online-OCR.net (gratis, upload ke 15MB)
• Microsoft OneNote (drag & drop PDF)

Setelah berhasil extract, paste teksnya ke dialog ini untuk dianalisis AI! 🚀''');
      }

      // Limit text length for API processing
      if (fullText.length > 50000) {
        fullText = '${fullText.substring(0, 50000)}\n\n[NOTE: Text truncated for processing]';
      }

      return fullText;

    } catch (e) {
      // If automated extraction fails, provide comprehensive guidance
      throw Exception('''📄 **PDF Extraction Error**

Terjadi kesalahan saat mengekstrak teks dari PDF: ${e.toString()}

**🔧 Solusi Alternatif:**

**Option 1 - Copy-Paste Manual (Recommended):**
1. Buka PDF di Adobe Reader/Chrome/Firefox
2. Select text (Ctrl+A atau drag select)
3. Copy (Ctrl+C) dan paste di "Input Teks Manual"

**Option 2 - Google Drive (Free & Easy):**
1. Upload PDF ke Google Drive
2. Klik kanan → Open with Google Docs
3. Teks akan otomatis ter-extract dengan baik

**Option 3 - Online OCR Tools:**
• Online-OCR.net (gratis, max 15MB)
• SmallPDF OCR (berbayar, akurat)
• Microsoft OneNote (drag & drop PDF)

**💡 Tips:**
- Untuk PDF scan, gunakan resolusi tinggi (300dpi+)
- Pastikan PDF tidak di-password protect
- Test dengan PDF text-based terlebih dahulu

Copy-paste manual tetap menjadi opsi paling reliable! ✨''');
    }
  }

  String extractTextFromTxt(File txtFile) {
    try {
      return txtFile.readAsStringSync(encoding: utf8);
    } catch (e) {
      throw Exception('Gagal membaca file txt: $e');
    }
  }
}