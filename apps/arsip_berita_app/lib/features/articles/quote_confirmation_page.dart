import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../../ui/design.dart';
import '../../services/openai_quote_generator.dart';
import '../../services/gemini_quote_generator.dart';
import '../../services/quote_template_service.dart';
import '../../models/quote_settings.dart';
import '../../models/quote_template.dart';
import '../../data/local/db.dart';
import '../settings/quote_settings_page.dart';
import 'quote_image_page.dart';

class QuoteConfirmationPage extends StatefulWidget {
  final String initialText;
  final String apiKey;
  final String aiModel; // 'openai' or 'gemini'

  const QuoteConfirmationPage({
    super.key,
    required this.initialText,
    required this.apiKey,
    required this.aiModel,
  });

  @override
  State<QuoteConfirmationPage> createState() => _QuoteConfirmationPageState();
}

class _QuoteConfirmationPageState extends State<QuoteConfirmationPage> {
  late TextEditingController _textController;
  late TextEditingController _promptController;

  // Template settings controllers
  late TextEditingController _sourceController;
  late TextEditingController _subtitleController;
  late TextEditingController _linkController;

  bool _isGenerating = false;
  bool _showTemplateEditor = false;
  QuoteSettings? _quoteSettings;

  // Template selection
  List<QuoteTemplate> _templates = [];
  QuoteTemplate? _selectedTemplate;
  bool _templatesLoaded = false;
  final _db = LocalDatabase();
  late QuoteTemplateService _templateService;

  @override
  void initState() {
    super.initState();
    _templateService = QuoteTemplateService(db: _db);
    _textController = TextEditingController(text: widget.initialText);
    _promptController = TextEditingController();

    // Initialize template settings controllers
    _sourceController = TextEditingController();
    _subtitleController = TextEditingController();
    _linkController = TextEditingController();

    // Add listener to regenerate prompt when quote text changes
    _textController.addListener(() {
      // Only regenerate if settings are loaded
      if (_quoteSettings != null) {
        _regeneratePromptFromControllers();
      }
    });

    // Add listeners to template controllers
    _sourceController.addListener(() {
      if (_quoteSettings != null) {
        _regeneratePromptFromControllers();
      }
    });
    _subtitleController.addListener(() {
      if (_quoteSettings != null) {
        _regeneratePromptFromControllers();
      }
    });
    _linkController.addListener(() {
      if (_quoteSettings != null) {
        _regeneratePromptFromControllers();
      }
    });

    _loadSettingsAndInitPrompt();
    _loadTemplates();
  }

  Future<void> _loadTemplates() async {
    try {
      await _db.init();
      final templates = await _templateService.getActiveTemplates();
      setState(() {
        _templates = templates;
        _templatesLoaded = true;
        // Select first template by default
        if (_templates.isNotEmpty) {
          _selectedTemplate = _templates.first;
        }
      });

      // Generate prompt with default template if available
      if (_selectedTemplate != null && _quoteSettings != null) {
        _regeneratePromptWithTemplate();
      }
    } catch (e) {
      print('Error loading templates: $e');
      setState(() {
        _templatesLoaded = true;
      });
    }
  }

  void _onTemplateSelected(QuoteTemplate template) {
    setState(() {
      _selectedTemplate = template;
    });
    // Regenerate prompt with selected template
    _regeneratePromptWithTemplate();
  }

  void _regeneratePromptWithTemplate() {
    if (_selectedTemplate == null || _quoteSettings == null) return;

    final quoteText = _textController.text.trim();
    if (quoteText.isEmpty) return;

    // Build prompt using selected template
    final prompt = _selectedTemplate!.buildPrompt(
      quoteText: quoteText,
      sourceQuote: _sourceController.text.trim(),
      subtitle: _subtitleController.text.trim(),
      linkAdvertisement: _linkController.text.trim(),
    );

    setState(() {
      _promptController.text = prompt;
    });
  }

  Future<void> _loadSettingsAndInitPrompt() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final settingsJson = prefs.getString('quote_settings');

      QuoteSettings settings;
      if (settingsJson != null) {
        settings = QuoteSettings.fromJson(jsonDecode(settingsJson));
      } else {
        settings = QuoteSettings(); // Use default settings
      }

      setState(() {
        _quoteSettings = settings;

        // Initialize template controllers with settings values
        _sourceController.text = settings.sourceQuote;
        _subtitleController.text = settings.subtitle;
        _linkController.text = settings.linkAdvertisement;
      });

      // Generate prompt based on AI model - always use template
      final prompt = widget.aiModel == 'openai'
          ? settings.buildDallEPrompt(widget.initialText)
          : settings.buildImagenPrompt(widget.initialText);

      setState(() {
        _promptController.text = prompt;
      });
    } catch (e) {
      // If loading fails, use default settings
      setState(() {
        _quoteSettings = QuoteSettings();

        // Initialize with default values
        _sourceController.text = _quoteSettings!.sourceQuote;
        _subtitleController.text = _quoteSettings!.subtitle;
        _linkController.text = _quoteSettings!.linkAdvertisement;

        final prompt = widget.aiModel == 'openai'
            ? _quoteSettings!.buildDallEPrompt(widget.initialText)
            : _quoteSettings!.buildImagenPrompt(widget.initialText);
        _promptController.text = prompt;
      });
    }
  }


  @override
  void dispose() {
    _textController.dispose();
    _promptController.dispose();
    _sourceController.dispose();
    _subtitleController.dispose();
    _linkController.dispose();
    super.dispose();
  }

  /// Regenerate prompt based on current quote text and settings from controllers
  void _regeneratePromptFromControllers() {
    if (_quoteSettings == null) return;

    final quoteText = _textController.text.trim();
    if (quoteText.isEmpty) return;

    // Create temporary settings with current controller values
    final tempSettings = QuoteSettings(
      sourceQuote: _sourceController.text.trim(),
      subtitle: _subtitleController.text.trim(),
      linkAdvertisement: _linkController.text.trim(),
      fontType: _quoteSettings!.fontType,
      fontSize: _quoteSettings!.fontSize,
    );

    // Update the stored settings object
    setState(() {
      _quoteSettings = tempSettings;
    });

    // Use template-based prompt if template is selected, otherwise use settings
    if (_selectedTemplate != null) {
      _regeneratePromptWithTemplate();
    } else {
      // Fallback to old method if no template selected
      _promptController.text = widget.aiModel == 'openai'
          ? tempSettings.buildDallEPrompt(quoteText)
          : tempSettings.buildImagenPrompt(quoteText);
    }
  }

  /// Regenerate prompt based on stored settings (for compatibility)
  void _regeneratePrompt() {
    _regeneratePromptFromControllers();
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
      // Replace [QUOTE_TEXT] placeholder with actual quote text
      final finalPrompt = prompt.replaceAll('[QUOTE_TEXT]', text);

      String? imageUrl;

      if (widget.aiModel == 'openai') {
        final generator = OpenAIQuoteGenerator(apiKey: widget.apiKey);
        imageUrl = await generator.generateQuoteImageWithPrompt(finalPrompt);
      } else if (widget.aiModel == 'gemini') {
        final generator = GeminiQuoteGenerator(apiKey: widget.apiKey);
        imageUrl = await generator.generateQuoteImageWithPrompt(finalPrompt);
      } else {
        throw Exception('Model AI tidak dikenali: ${widget.aiModel}');
      }

      if (!mounted) return;

      if (imageUrl == null || imageUrl.isEmpty) {
        throw Exception('Failed to generate image URL');
      }

      // Navigate to quote image page
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => QuoteImagePage(
            imageUrl: imageUrl!, // Safe to use ! here after null check
            quoteText: text,
          ),
        ),
      );
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
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const QuoteSettingsPage(),
                ),
              );
              // Reload settings after returning from settings page
              _loadSettingsAndInitPrompt();
            },
            tooltip: 'Quote Settings',
          ),
        ],
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

                const SizedBox(height: 12),

                // AI Model Info Badge with Warning
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: DS.surface,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: DS.border),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.auto_awesome,
                              size: 16,
                              color: DS.accent,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        'Model: ',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: DS.textDim,
                                        ),
                                      ),
                                      Text(
                                        widget.aiModel == 'openai'
                                            ? 'OpenAI DALL-E 3'
                                            : 'Gemini 2.5 Flash',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: DS.accent,
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (widget.aiModel == 'gemini')
                                    Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Row(
                                        children: [
                                          Icon(Icons.info_outline, size: 12, color: DS.accent),
                                          const SizedBox(width: 4),
                                          Expanded(
                                            child: Text(
                                              'Native image generation dengan konteks tinggi',
                                              style: TextStyle(
                                                fontSize: 9,
                                                color: DS.accent,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (_quoteSettings != null)
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: DS.surface,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: DS.border),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.brush,
                                size: 16,
                                color: DS.accent,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  '${_quoteSettings!.fontType}, ${_quoteSettings!.fontSize}pt',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: DS.text,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
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
                    Expanded(
                      child: Text(
                        widget.aiModel == 'openai'
                            ? 'Prompt DALL-E'
                            : 'Prompt Gemini',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: DS.text,
                        ),
                      ),
                    ),
                    if (_quoteSettings != null)
                      TextButton.icon(
                        onPressed: _regeneratePrompt,
                        icon: Icon(Icons.refresh, size: 16, color: DS.accent),
                        label: Text(
                          'Refresh Prompt',
                          style: TextStyle(
                            fontSize: 12,
                            color: DS.accent,
                          ),
                        ),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                  ],
                ),

                const SizedBox(height: 8),

                // Template Settings Editor
                if (_quoteSettings != null)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: DS.accent.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: DS.accent.withValues(alpha: 0.2)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.tune, size: 16, color: DS.accent),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Template Settings',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: DS.accent,
                                ),
                              ),
                            ),
                            InkWell(
                              onTap: () {
                                setState(() {
                                  _showTemplateEditor = !_showTemplateEditor;
                                });
                              },
                              child: Icon(
                                _showTemplateEditor
                                    ? Icons.keyboard_arrow_up
                                    : Icons.keyboard_arrow_down,
                                size: 20,
                                color: DS.accent,
                              ),
                            ),
                          ],
                        ),

                        if (_showTemplateEditor) ...[
                          const SizedBox(height: 12),
                          Divider(color: DS.border, height: 1),
                          const SizedBox(height: 12),

                          // Source Quote Field
                          Text(
                            'Sumber Quote',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: DS.text,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Container(
                            decoration: BoxDecoration(
                              color: DS.surface,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: DS.border),
                            ),
                            child: TextField(
                              controller: _sourceController,
                              style: TextStyle(fontSize: 12, color: DS.text),
                              decoration: InputDecoration(
                                hintText: 'Contoh: Gandhi, Mandela, dll',
                                hintStyle: TextStyle(color: DS.textDim, fontSize: 11),
                                border: InputBorder.none,
                                contentPadding: const EdgeInsets.all(10),
                                isDense: true,
                              ),
                            ),
                          ),

                          const SizedBox(height: 12),

                          // Subtitle Field
                          Text(
                            'Subtitle (Opsional)',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: DS.text,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Container(
                            decoration: BoxDecoration(
                              color: DS.surface,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: DS.border),
                            ),
                            child: TextField(
                              controller: _subtitleController,
                              style: TextStyle(fontSize: 12, color: DS.text),
                              decoration: InputDecoration(
                                hintText: 'Contoh: Humas Andri Rusmana',
                                hintStyle: TextStyle(color: DS.textDim, fontSize: 11),
                                border: InputBorder.none,
                                contentPadding: const EdgeInsets.all(10),
                                isDense: true,
                              ),
                            ),
                          ),

                          const SizedBox(height: 12),

                          // Link Advertisement Field
                          Text(
                            'Link Advertisement (Opsional)',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: DS.text,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Container(
                            decoration: BoxDecoration(
                              color: DS.surface,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: DS.border),
                            ),
                            child: TextField(
                              controller: _linkController,
                              style: TextStyle(fontSize: 12, color: DS.text),
                              decoration: InputDecoration(
                                hintText: 'Contoh: @kyaranusa',
                                hintStyle: TextStyle(color: DS.textDim, fontSize: 11),
                                border: InputBorder.none,
                                contentPadding: const EdgeInsets.all(10),
                                isDense: true,
                              ),
                            ),
                          ),

                          const SizedBox(height: 12),

                          // Template Selector
                          Text(
                            'Pilih Gaya Template',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: DS.text,
                            ),
                          ),
                          const SizedBox(height: 8),

                          if (_templatesLoaded && _templates.isNotEmpty)
                            SizedBox(
                              height: 180,
                              child: ListView.builder(
                                scrollDirection: Axis.horizontal,
                                itemCount: _templates.length,
                                itemBuilder: (context, index) {
                                  final template = _templates[index];
                                  final isSelected = _selectedTemplate?.id == template.id;

                                  return GestureDetector(
                                    onTap: () => _onTemplateSelected(template),
                                    child: Container(
                                      width: 140,
                                      margin: const EdgeInsets.only(right: 12),
                                      decoration: BoxDecoration(
                                        color: DS.surface,
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: isSelected
                                              ? DS.accent
                                              : DS.border,
                                          width: isSelected ? 3 : 1,
                                        ),
                                        boxShadow: isSelected
                                            ? [
                                                BoxShadow(
                                                  color: DS.accent.withValues(alpha: 0.3),
                                                  blurRadius: 8,
                                                  offset: const Offset(0, 2),
                                                )
                                              ]
                                            : null,
                                      ),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          // Preview Image
                                          Container(
                                            height: 100,
                                            width: double.infinity,
                                            decoration: BoxDecoration(
                                              color: _getTemplatePreviewColor(template.styleCategory),
                                              borderRadius: const BorderRadius.vertical(
                                                top: Radius.circular(12),
                                              ),
                                            ),
                                            child: Stack(
                                              children: [
                                                // Preview content representation
                                                Center(
                                                  child: _buildTemplatePreview(template),
                                                ),
                                                // Selected indicator overlay
                                                if (isSelected)
                                                  Positioned(
                                                    top: 6,
                                                    right: 6,
                                                    child: Container(
                                                      padding: const EdgeInsets.all(4),
                                                      decoration: BoxDecoration(
                                                        color: DS.accent,
                                                        shape: BoxShape.circle,
                                                        boxShadow: [
                                                          BoxShadow(
                                                            color: Colors.black.withValues(alpha: 0.2),
                                                            blurRadius: 4,
                                                          )
                                                        ],
                                                      ),
                                                      child: const Icon(
                                                        Icons.check,
                                                        size: 14,
                                                        color: Colors.white,
                                                      ),
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          ),
                                          // Template info
                                          Padding(
                                            padding: const EdgeInsets.all(8),
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                // Template name
                                                Text(
                                                  template.name,
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w600,
                                                    color: isSelected ? DS.accent : DS.text,
                                                  ),
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                                const SizedBox(height: 4),
                                                // Category badge
                                                Container(
                                                  padding: const EdgeInsets.symmetric(
                                                    horizontal: 6,
                                                    vertical: 2,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: isSelected
                                                        ? DS.accent
                                                        : DS.textDim.withValues(alpha: 0.1),
                                                    borderRadius: BorderRadius.circular(4),
                                                  ),
                                                  child: Text(
                                                    _getCategoryLabel(template.styleCategory),
                                                    style: TextStyle(
                                                      fontSize: 9,
                                                      color: isSelected
                                                          ? Colors.white
                                                          : DS.textDim,
                                                      fontWeight: FontWeight.w600,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                            )
                          else if (_templatesLoaded)
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: DS.surface,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: DS.border),
                              ),
                              child: Text(
                                'Tidak ada template tersedia',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: DS.textDim,
                                ),
                              ),
                            )
                          else
                            Container(
                              padding: const EdgeInsets.all(12),
                              child: Center(
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: DS.accent,
                                ),
                              ),
                            ),

                          if (_selectedTemplate != null) ...[
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: DS.accent.withValues(alpha: 0.05),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.info_outline, size: 12, color: DS.accent),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      _selectedTemplate!.description,
                                      style: TextStyle(
                                        fontSize: 9,
                                        color: DS.text,
                                        fontStyle: FontStyle.italic,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],

                          const SizedBox(height: 12),

                          // Font Info (read-only)
                          Row(
                            children: [
                              Icon(Icons.text_fields, size: 14, color: DS.textDim),
                              const SizedBox(width: 6),
                              Text(
                                'Font: ${_quoteSettings!.fontType}, ${_quoteSettings!.fontSize}pt',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: DS.textDim,
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 10),

                          // Info text
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: DS.surface,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.auto_awesome, size: 12, color: DS.accent),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    'Prompt auto-update saat field berubah',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: DS.textDim,
                                      fontStyle: FontStyle.italic,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ] else ...[
                          const SizedBox(height: 8),
                          // Compact preview when collapsed
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: [
                              if (_sourceController.text.isNotEmpty)
                                _buildSettingChip('Sumber: ${_sourceController.text}'),
                              if (_subtitleController.text.isNotEmpty)
                                _buildSettingChip('Subtitle: ${_subtitleController.text}'),
                              if (_linkController.text.isNotEmpty)
                                _buildSettingChip('Link: ${_linkController.text}'),
                              _buildSettingChip('${_quoteSettings!.fontType}, ${_quoteSettings!.fontSize}pt'),
                            ],
                          ),
                        ],
                      ],
                    ),
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
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: widget.aiModel == 'gemini'
                        ? Colors.orange.withValues(alpha: 0.1)
                        : DS.accent.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: widget.aiModel == 'gemini'
                          ? Colors.orange.withValues(alpha: 0.4)
                          : DS.accent.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            widget.aiModel == 'gemini'
                                ? Icons.warning_rounded
                                : Icons.lightbulb_outline,
                            size: 16,
                            color: widget.aiModel == 'gemini'
                                ? Colors.orange
                                : DS.accent,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              widget.aiModel == 'gemini'
                                  ? 'Info Gemini'
                                  : 'Tips DALL-E',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: widget.aiModel == 'gemini'
                                    ? Colors.orange
                                    : DS.accent,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (widget.aiModel == 'gemini') ...[
                        Row(
                          children: [
                            const Icon(Icons.auto_awesome, size: 14, color: Colors.blue),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'Gemini 2.5 Flash Image',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.blue,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Gemini 2.5 Flash dapat menghasilkan gambar berkualitas tinggi dengan text rendering yang akurat.',
                          style: TextStyle(
                            fontSize: 10,
                            color: DS.text,
                            height: 1.4,
                          ),
                        ),
                      ] else ...[
                        Text(
                          'DALL-E dapat menampilkan text di gambar dengan baik. Semua template parameters akan digunakan dengan detailed instructions.',
                          style: TextStyle(
                            fontSize: 10,
                            color: DS.textDim,
                            height: 1.4,
                          ),
                        ),
                      ],
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

  Widget _buildSettingChip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: DS.surface,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: DS.border),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10,
          color: DS.text,
        ),
      ),
    );
  }

  String _getCategoryLabel(String category) {
    switch (category) {
      case 'minimal':
        return 'Minimal';
      case 'bold':
        return 'Bold';
      case 'elegant':
        return 'Elegan';
      case 'modern':
        return 'Modern';
      case 'creative':
        return 'Kreatif';
      default:
        return category;
    }
  }

  Color _getTemplatePreviewColor(String category) {
    switch (category) {
      case 'minimal':
        return Colors.grey.shade50;
      case 'bold':
        return Colors.purple.shade100;
      case 'elegant':
        return const Color(0xFFFAF9F6); // Cream
      case 'modern':
        return Colors.blue.shade50;
      case 'creative':
        return Colors.orange.shade50;
      default:
        return Colors.grey.shade100;
    }
  }

  Widget _buildTemplatePreview(QuoteTemplate template) {
    // Build a visual representation/mockup of the template style
    switch (template.styleCategory) {
      case 'minimal':
        return Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                height: 3,
                width: 50,
                color: Colors.grey.shade800,
              ),
              const SizedBox(height: 6),
              Container(
                height: 2,
                width: 40,
                color: Colors.grey.shade600,
              ),
              const SizedBox(height: 4),
              Container(
                height: 1,
                width: 30,
                color: Colors.grey.shade400,
              ),
            ],
          ),
        );

      case 'bold':
        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.purple.shade400,
                Colors.blue.shade400,
              ],
            ),
          ),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  height: 4,
                  width: 60,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(2),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.2),
                        blurRadius: 2,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  height: 2,
                  width: 40,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(1),
                  ),
                ),
              ],
            ),
          ),
        );

      case 'elegant':
        return Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                height: 1,
                width: 40,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.brown.shade300,
                      Colors.brown.shade600,
                      Colors.brown.shade300,
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Container(
                height: 3,
                width: 50,
                color: Colors.brown.shade800,
              ),
              const SizedBox(height: 6),
              Container(
                height: 2,
                width: 35,
                color: Colors.brown.shade600,
              ),
              const SizedBox(height: 8),
              Container(
                height: 1,
                width: 40,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.brown.shade300,
                      Colors.brown.shade600,
                      Colors.brown.shade300,
                    ],
                  ),
                ),
              ),
            ],
          ),
        );

      case 'modern':
        return Stack(
          children: [
            Positioned(
              top: 10,
              left: 10,
              child: Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: Colors.blue.shade300,
                  shape: BoxShape.circle,
                ),
              ),
            ),
            Positioned(
              bottom: 15,
              right: 15,
              child: Container(
                width: 25,
                height: 25,
                decoration: BoxDecoration(
                  color: Colors.orange.shade300,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    height: 3,
                    width: 50,
                    color: Colors.grey.shade800,
                  ),
                  const SizedBox(height: 5),
                  Container(
                    height: 2,
                    width: 35,
                    color: Colors.grey.shade600,
                  ),
                ],
              ),
            ),
          ],
        );

      case 'creative':
        return CustomPaint(
          size: const Size(100, 100),
          painter: _CreativePreviewPainter(),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  height: 3,
                  width: 45,
                  decoration: BoxDecoration(
                    color: Colors.orange.shade800,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  height: 2,
                  width: 35,
                  decoration: BoxDecoration(
                    color: Colors.orange.shade600,
                    borderRadius: BorderRadius.circular(1),
                  ),
                ),
              ],
            ),
          ),
        );

      default:
        return const Icon(
          Icons.image,
          size: 40,
          color: Colors.grey,
        );
    }
  }
}

// Custom painter for creative template preview
class _CreativePreviewPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.fill
      ..strokeWidth = 2;

    // Draw some artistic brush strokes
    paint.color = Colors.orange.shade200.withValues(alpha: 0.3);
    canvas.drawCircle(Offset(size.width * 0.2, size.height * 0.3), 15, paint);

    paint.color = Colors.pink.shade200.withValues(alpha: 0.3);
    canvas.drawCircle(Offset(size.width * 0.8, size.height * 0.7), 12, paint);

    paint.color = Colors.yellow.shade200.withValues(alpha: 0.2);
    canvas.drawCircle(Offset(size.width * 0.6, size.height * 0.2), 10, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
