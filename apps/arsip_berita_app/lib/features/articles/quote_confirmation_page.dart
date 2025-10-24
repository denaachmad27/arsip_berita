import 'package:flutter/material.dart';
import '../../ui/design.dart';
import '../../services/openai_quote_generator.dart';
import 'quote_image_page.dart';

class QuoteConfirmationPage extends StatefulWidget {
  final String initialText;
  final String apiKey;

  const QuoteConfirmationPage({
    super.key,
    required this.initialText,
    required this.apiKey,
  });

  @override
  State<QuoteConfirmationPage> createState() => _QuoteConfirmationPageState();
}

class _QuoteConfirmationPageState extends State<QuoteConfirmationPage> {
  late TextEditingController _textController;
  late TextEditingController _promptController;
  bool _isGenerating = false;

  // Default prompt template
  static const String defaultPrompt = '''Buatkan gambar quote estetik untuk posting di media sosial. Teks utama pada gambar: "[QUOTE_TEXT]"
Kriteria visual:
- Jangan typo atau kesalahan ejaan pada teks quote.
- Jangan ubah teks quote, baik ditambahkan atau diterjemahkan, apa adanya saja.
- Teks harus jelas dan mudah dibaca, tidak menjadi bagian dari latar belakang.
- Gaya visual minimalis dan modern
- Komposisi seimbang, fokus pada teks
- Warna lembut, selaras dengan suasana quote
- Sertakan ruang kosong yang cukup di sekitar teks (clean layout)
- Rasio gambar persegi (1:1)''';

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(text: widget.initialText);
    _promptController = TextEditingController(text: defaultPrompt);
  }

  @override
  void dispose() {
    _textController.dispose();
    _promptController.dispose();
    super.dispose();
  }

  Future<void> _generateQuote() async {
    final text = _textController.text.trim();
    final prompt = _promptController.text.trim();

    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Teks quote tidak boleh kosong'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (prompt.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Prompt tidak boleh kosong'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      _isGenerating = true;
    });

    try {
      final generator = OpenAIQuoteGenerator(apiKey: widget.apiKey);

      // Replace [QUOTE_TEXT] placeholder with actual quote text
      final finalPrompt = prompt.replaceAll('[QUOTE_TEXT]', text);

      final imageUrl = await generator.generateQuoteImageWithPrompt(finalPrompt);

      if (!mounted) return;

      if (imageUrl != null) {
        // Navigate to quote image page
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => QuoteImagePage(
              imageUrl: imageUrl,
              quoteText: text,
            ),
          ),
        );
      } else {
        throw Exception('Failed to generate image URL');
      }
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isGenerating = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Gagal generate quote: ${e.toString()}'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DS.bg,
      appBar: AppBar(
        title: const Text('Konfirmasi Quote'),
        backgroundColor: DS.surface,
        foregroundColor: DS.text,
        elevation: 0,
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Info card - compact
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: DS.accent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: DS.accent.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, color: DS.accent, size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Modifikasi teks quote dan prompt sebelum generate',
                          style: TextStyle(
                            fontSize: 12,
                            color: DS.text,
                            height: 1.3,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // Label - compact
                Text(
                  'Teks Quote',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: DS.text,
                  ),
                ),

                const SizedBox(height: 8),

                // Text field - compact
                Container(
                  decoration: BoxDecoration(
                    color: DS.surface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: DS.border),
                  ),
                  child: TextField(
                    controller: _textController,
                    maxLines: 4,
                    style: TextStyle(
                      fontSize: 13,
                      color: DS.text,
                      height: 1.4,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Masukkan teks quote...',
                      hintStyle: TextStyle(color: DS.textDim, fontSize: 12),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.all(12),
                    ),
                  ),
                ),

                const SizedBox(height: 6),

                // Character count - compact
                Text(
                  '${_textController.text.length} karakter',
                  style: TextStyle(
                    fontSize: 11,
                    color: DS.textDim,
                  ),
                ),

                const SizedBox(height: 16),

                // Divider
                Divider(color: DS.border, height: 1),

                const SizedBox(height: 16),

                // Prompt section label - compact
                Row(
                  children: [
                    Text(
                      'Prompt DALL-E',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: DS.text,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Tooltip(
                      message: 'Gunakan [QUOTE_TEXT] sebagai placeholder',
                      child: Icon(
                        Icons.help_outline,
                        size: 16,
                        color: DS.textDim,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 8),

                // Prompt text field - expanded for long prompts
                Container(
                  decoration: BoxDecoration(
                    color: DS.surface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: DS.border),
                  ),
                  child: TextField(
                    controller: _promptController,
                    maxLines: 12,
                    minLines: 12,
                    style: TextStyle(
                      fontSize: 12,
                      color: DS.text,
                      height: 1.4,
                      fontFamily: 'monospace',
                    ),
                    decoration: InputDecoration(
                      hintText: 'Masukkan prompt untuk generate gambar...',
                      hintStyle: TextStyle(color: DS.textDim, fontSize: 11),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.all(12),
                    ),
                  ),
                ),

                const SizedBox(height: 6),

                // Prompt info - compact
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: DS.accent.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: DS.accent.withValues(alpha: 0.2)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.lightbulb_outline,
                        size: 14,
                        color: DS.accent,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Gunakan [QUOTE_TEXT] untuk placeholder teks quote',
                          style: TextStyle(
                            fontSize: 10,
                            color: DS.textDim,
                            height: 1.3,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // Action buttons
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: _isGenerating ? null : () => Navigator.pop(context),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(color: DS.border),
                          ),
                        ),
                        child: const Text('Batal'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _isGenerating ? null : _generateQuote,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: DS.accent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          disabledBackgroundColor: DS.accent.withValues(alpha: 0.5),
                        ),
                        child: const Text('Lanjutkan'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Loading overlay
          if (_isGenerating)
            Container(
              color: Colors.black54,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: DS.surface,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: DS.accent),
                      const SizedBox(height: 16),
                      Text(
                        'Generating quote image...',
                        style: TextStyle(color: DS.text, fontSize: 16),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'This may take a few seconds',
                        style: TextStyle(color: DS.textDim, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
