import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../../ui/design.dart';
import '../../models/quote_settings.dart';

class QuoteSettingsPage extends StatefulWidget {
  const QuoteSettingsPage({super.key});

  @override
  State<QuoteSettingsPage> createState() => _QuoteSettingsPageState();
}

class _QuoteSettingsPageState extends State<QuoteSettingsPage> {
  late TextEditingController _sourceController;
  late TextEditingController _subtitleController;
  late TextEditingController _linkController;

  String _fontType = 'Roboto';
  int _fontSize = 24;

  bool _isLoading = true;
  bool _isSaving = false;

  // Font options
  static const List<String> fontOptions = [
    'Roboto',
    'Open Sans',
    'Lato',
    'Montserrat',
    'Poppins',
    'Playfair Display',
    'Merriweather',
    'Arial',
    'Times New Roman',
    'Georgia',
  ];

  @override
  void initState() {
    super.initState();
    _sourceController = TextEditingController();
    _subtitleController = TextEditingController();
    _linkController = TextEditingController();
    _loadSettings();
  }

  @override
  void dispose() {
    _sourceController.dispose();
    _subtitleController.dispose();
    _linkController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final settingsJson = prefs.getString('quote_settings');

      if (settingsJson != null) {
        final settings = QuoteSettings.fromJson(jsonDecode(settingsJson));
        setState(() {
          _fontType = settings.fontType;
          _fontSize = settings.fontSize;

          // Update controllers
          _sourceController.text = settings.sourceQuote;
          _subtitleController.text = settings.subtitle;
          _linkController.text = settings.linkAdvertisement;
        });
      } else {
        // Set default values
        setState(() {
          _sourceController.text = 'Tokoh inspiratif';
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal memuat settings: $e'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _saveSettings() async {
    setState(() {
      _isSaving = true;
    });

    try {
      final settings = QuoteSettings(
        sourceQuote: _sourceController.text.trim(),
        subtitle: _subtitleController.text.trim(),
        linkAdvertisement: _linkController.text.trim(),
        fontType: _fontType,
        fontSize: _fontSize,
      );

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('quote_settings', jsonEncode(settings.toJson()));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Settings berhasil disimpan'),
            backgroundColor: DS.accent,
            action: SnackBarAction(
              label: 'OK',
              textColor: Colors.white,
              onPressed: () {},
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal menyimpan settings: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() {
        _isSaving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: DS.bg,
        appBar: AppBar(
          title: const Text('Quote Settings'),
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
        title: const Text('Quote Settings'),
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
              icon: const Icon(Icons.save),
              onPressed: _saveSettings,
              tooltip: 'Simpan Settings',
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
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: DS.accent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: DS.accent.withValues(alpha: 0.3)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, color: DS.accent, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Pengaturan template untuk generate gambar quote. Settings ini akan digunakan secara default.',
                      style: TextStyle(
                        fontSize: 12,
                        color: DS.text,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // 1. Source Quote
            _buildSectionTitle('1. Sumber Quote'),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: DS.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: DS.border),
              ),
              child: TextField(
                controller: _sourceController,
                style: TextStyle(fontSize: 14, color: DS.text),
                decoration: InputDecoration(
                  hintText: 'Contoh: Gandhi, Mandela, Albert Einstein, dll',
                  hintStyle: TextStyle(color: DS.textDim, fontSize: 13),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.all(12),
                ),
                onChanged: (value) {
                  setState(() {}); // Update preview
                },
              ),
            ),

            const SizedBox(height: 20),

            // 2. Subtitle
            _buildSectionTitle('2. Subtitle (Opsional)'),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: DS.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: DS.border),
              ),
              child: TextField(
                controller: _subtitleController,
                style: TextStyle(fontSize: 14, color: DS.text),
                decoration: InputDecoration(
                  hintText: 'Contoh: Humas Andri Rusmana',
                  hintStyle: TextStyle(color: DS.textDim, fontSize: 13),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.all(12),
                ),
                onChanged: (value) {
                  setState(() {}); // Update preview
                },
              ),
            ),

            const SizedBox(height: 20),

            // 3. Link Advertisement
            _buildSectionTitle('3. Link Advertisement (Opsional)'),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: DS.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: DS.border),
              ),
              child: TextField(
                controller: _linkController,
                style: TextStyle(fontSize: 14, color: DS.text),
                decoration: InputDecoration(
                  hintText: 'Contoh: @kyaranusa',
                  hintStyle: TextStyle(color: DS.textDim, fontSize: 13),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.all(12),
                ),
                onChanged: (value) {
                  setState(() {}); // Update preview
                },
              ),
            ),

            const SizedBox(height: 20),

            // 4. Font Type
            _buildSectionTitle('4. Font Type Utama'),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: DS.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: DS.border),
              ),
              child: DropdownButtonFormField<String>(
                initialValue: fontOptions.contains(_fontType) ? _fontType : fontOptions[0],
                decoration: InputDecoration(
                  hintText: 'Pilih font',
                  hintStyle: TextStyle(color: DS.textDim, fontSize: 13),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
                dropdownColor: DS.surface,
                style: TextStyle(fontSize: 14, color: DS.text),
                items: fontOptions.map((font) {
                  return DropdownMenuItem(
                    value: font,
                    child: Text(font),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    _fontType = value!;
                  });
                },
              ),
            ),

            const SizedBox(height: 20),

            // 5. Font Size
            _buildSectionTitle('5. Font Size Utama'),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: DS.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: DS.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Ukuran: $_fontSize pt',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: DS.text,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: DS.accent.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          _getFontSizeLabel(),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: DS.accent,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SliderTheme(
                    data: SliderThemeData(
                      activeTrackColor: DS.accent,
                      inactiveTrackColor: DS.border,
                      thumbColor: DS.accent,
                      overlayColor: DS.accent.withValues(alpha: 0.2),
                      trackHeight: 4,
                    ),
                    child: Slider(
                      value: _fontSize.toDouble(),
                      min: 16,
                      max: 48,
                      divisions: 32,
                      label: '$_fontSize pt',
                      onChanged: (value) {
                        setState(() {
                          _fontSize = value.round();
                        });
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '16',
                          style: TextStyle(fontSize: 11, color: DS.textDim),
                        ),
                        Text(
                          '48',
                          style: TextStyle(fontSize: 11, color: DS.textDim),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),

            // Preview section
            _buildSectionTitle('Preview Template'),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: DS.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: DS.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.preview, color: DS.accent, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        'Template Summary',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: DS.accent,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _buildPreviewItem('Sumber', _sourceController.text.isEmpty ? '(Belum diisi)' : _sourceController.text),
                  if (_subtitleController.text.isNotEmpty)
                    _buildPreviewItem('Subtitle', _subtitleController.text),
                  if (_linkController.text.isNotEmpty)
                    _buildPreviewItem('Link', _linkController.text),
                  _buildPreviewItem('Font', '$_fontType, $_fontSize pt'),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Save button (larger)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isSaving ? null : _saveSettings,
                style: ElevatedButton.styleFrom(
                  backgroundColor: DS.accent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  disabledBackgroundColor: DS.accent.withValues(alpha: 0.5),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (_isSaving)
                      const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    else
                      const Icon(Icons.save, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      _isSaving ? 'Menyimpan...' : 'Simpan Settings',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: DS.text,
      ),
    );
  }

  Widget _buildPreviewItem(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              '$label:',
              style: TextStyle(
                fontSize: 12,
                color: DS.textDim,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: DS.text,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _getFontSizeLabel() {
    if (_fontSize <= 18) return 'Kecil';
    if (_fontSize <= 24) return 'Normal';
    if (_fontSize <= 32) return 'Besar';
    return 'Sangat Besar';
  }
}
