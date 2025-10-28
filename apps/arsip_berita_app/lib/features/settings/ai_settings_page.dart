import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../ui/design.dart';
import '../../data/local/db.dart';
import 'quote_settings_page.dart';
import 'quote_templates_page.dart';

class AISettingsPage extends StatefulWidget {
  const AISettingsPage({super.key});

  @override
  State<AISettingsPage> createState() => _AISettingsPageState();
}

class _AISettingsPageState extends State<AISettingsPage> {
  static const String _aiModelKey = 'ai_model_preference';
  static const String _openaiApiKeyKey = 'openai_api_key';
  static const String _geminiApiKeyKey = 'gemini_api_key';

  String _selectedModel = 'openai'; // 'openai' or 'gemini'
  final TextEditingController _openaiKeyController = TextEditingController();
  final TextEditingController _geminiKeyController = TextEditingController();
  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _openaiKeyController.dispose();
    _geminiKeyController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final model = prefs.getString(_aiModelKey) ?? 'openai';
      final openaiKey = prefs.getString(_openaiApiKeyKey) ?? '';
      final geminiKey = prefs.getString(_geminiApiKeyKey) ?? '';

      if (mounted) {
        setState(() {
          _selectedModel = model;
          _openaiKeyController.text = openaiKey;
          _geminiKeyController.text = geminiKey;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading settings: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _saveSettings() async {
    setState(() {
      _isSaving = true;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_aiModelKey, _selectedModel);
      await prefs.setString(_openaiApiKeyKey, _openaiKeyController.text.trim());
      await prefs.setString(_geminiApiKeyKey, _geminiKeyController.text.trim());

      if (mounted) {
        setState(() {
          _isSaving = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Settings berhasil disimpan'),
            backgroundColor: DS.accent,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving settings: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: DS.bg,
        appBar: AppBar(
          title: const Text('AI Settings'),
          backgroundColor: DS.surface,
          foregroundColor: DS.text,
          elevation: 0,
        ),
        body: Center(
          child: CircularProgressIndicator(color: DS.accent),
        ),
      );
    }

    return Scaffold(
      backgroundColor: DS.bg,
      appBar: AppBar(
        title: const Text('AI Settings'),
        backgroundColor: DS.surface,
        foregroundColor: DS.text,
        elevation: 0,
        actions: [
          if (_isSaving)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: DS.accent,
                  ),
                ),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.check),
              onPressed: _saveSettings,
              tooltip: 'Simpan',
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Info card
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
                      'Pilih AI model untuk generate gambar quote',
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

            const SizedBox(height: 24),

            // Model Selection
            Text(
              'AI Model',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: DS.text,
              ),
            ),

            const SizedBox(height: 12),

            // OpenAI Option
            InkWell(
              onTap: () {
                setState(() {
                  _selectedModel = 'openai';
                });
              },
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: DS.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _selectedModel == 'openai'
                        ? DS.accent
                        : DS.border,
                    width: _selectedModel == 'openai' ? 2 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _selectedModel == 'openai'
                              ? DS.accent
                              : DS.textDim,
                          width: 2,
                        ),
                      ),
                      child: _selectedModel == 'openai'
                          ? Center(
                              child: Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: DS.accent,
                                ),
                              ),
                            )
                          : null,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'OpenAI DALL-E 3',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: DS.text,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Generate gambar berkualitas tinggi dengan DALL-E 3',
                            style: TextStyle(
                              fontSize: 11,
                              color: DS.textDim,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 12),

            // Gemini Option
            InkWell(
              onTap: () {
                setState(() {
                  _selectedModel = 'gemini';
                });
              },
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: DS.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _selectedModel == 'gemini'
                        ? DS.accent
                        : DS.border,
                    width: _selectedModel == 'gemini' ? 2 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _selectedModel == 'gemini'
                              ? DS.accent
                              : DS.textDim,
                          width: 2,
                        ),
                      ),
                      child: _selectedModel == 'gemini'
                          ? Center(
                              child: Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: DS.accent,
                                ),
                              ),
                            )
                          : null,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Google Gemini Imagen',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: DS.text,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Generate gambar dengan Google Gemini',
                            style: TextStyle(
                              fontSize: 11,
                              color: DS.textDim,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 32),

            // API Keys Section
            Text(
              'API Keys',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: DS.text,
              ),
            ),

            const SizedBox(height: 12),

            // OpenAI API Key
            Text(
              'OpenAI API Key',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: DS.text,
              ),
            ),

            const SizedBox(height: 8),

            Container(
              decoration: BoxDecoration(
                color: DS.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: DS.border),
              ),
              child: TextField(
                controller: _openaiKeyController,
                obscureText: true,
                style: TextStyle(
                  fontSize: 13,
                  color: DS.text,
                  fontFamily: 'monospace',
                ),
                decoration: InputDecoration(
                  hintText: 'sk-...',
                  hintStyle: TextStyle(color: DS.textDim, fontSize: 12),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.all(12),
                  suffixIcon: _openaiKeyController.text.isNotEmpty
                      ? IconButton(
                          icon: Icon(Icons.clear, size: 18, color: DS.textDim),
                          onPressed: () {
                            setState(() {
                              _openaiKeyController.clear();
                            });
                          },
                        )
                      : null,
                ),
                onChanged: (value) {
                  setState(() {});
                },
              ),
            ),

            const SizedBox(height: 20),

            // Gemini API Key
            Text(
              'Google Gemini API Key',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: DS.text,
              ),
            ),

            const SizedBox(height: 8),

            Container(
              decoration: BoxDecoration(
                color: DS.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: DS.border),
              ),
              child: TextField(
                controller: _geminiKeyController,
                obscureText: true,
                style: TextStyle(
                  fontSize: 13,
                  color: DS.text,
                  fontFamily: 'monospace',
                ),
                decoration: InputDecoration(
                  hintText: 'AIza...',
                  hintStyle: TextStyle(color: DS.textDim, fontSize: 12),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.all(12),
                  suffixIcon: _geminiKeyController.text.isNotEmpty
                      ? IconButton(
                          icon: Icon(Icons.clear, size: 18, color: DS.textDim),
                          onPressed: () {
                            setState(() {
                              _geminiKeyController.clear();
                            });
                          },
                        )
                      : null,
                ),
                onChanged: (value) {
                  setState(() {});
                },
              ),
            ),

            const SizedBox(height: 16),

            // API Key info
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
                    Icons.security,
                    size: 14,
                    color: DS.accent,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'API key disimpan secara lokal di device Anda dan tidak dikirim ke server manapun',
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

            const SizedBox(height: 32),

            // Divider
            Divider(color: DS.border, height: 1),

            const SizedBox(height: 24),

            // Quote Template Settings Section
            Text(
              'Quote Template',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: DS.text,
              ),
            ),

            const SizedBox(height: 12),

            // Quote Settings Card
            InkWell(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const QuoteSettingsPage(),
                  ),
                );
              },
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: DS.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: DS.border),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: DS.accent.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.format_quote,
                        color: DS.accent,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Pengaturan Template Quote',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: DS.text,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Atur sumber quote, subtitle, link, font & ukuran',
                            style: TextStyle(
                              fontSize: 11,
                              color: DS.textDim,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.chevron_right,
                      color: DS.textDim,
                      size: 20,
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 12),

            // Template Management Card
            InkWell(
              onTap: () async {
                final db = LocalDatabase();
                await db.init();
                if (mounted) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => QuoteTemplatesPage(db: db),
                    ),
                  );
                }
              },
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: DS.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: DS.border),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: DS.accent.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.style,
                        color: DS.accent,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Kelola Template Quote',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: DS.text,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Tambah, edit, hapus gaya template quote gambar',
                            style: TextStyle(
                              fontSize: 11,
                              color: DS.textDim,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.chevron_right,
                      color: DS.textDim,
                      size: 20,
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 32),

            // Save button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isSaving ? null : _saveSettings,
                style: ElevatedButton.styleFrom(
                  backgroundColor: DS.accent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  disabledBackgroundColor: DS.accent.withValues(alpha: 0.5),
                ),
                child: _isSaving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Simpan Settings'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
