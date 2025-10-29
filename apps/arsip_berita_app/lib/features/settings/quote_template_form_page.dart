import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import '../../data/local/db.dart';
import '../../models/quote_template.dart';
import '../../ui/design.dart';

class QuoteTemplateFormPage extends StatefulWidget {
  final LocalDatabase db;
  final QuoteTemplate? template;

  const QuoteTemplateFormPage({
    super.key,
    required this.db,
    this.template,
  });

  @override
  State<QuoteTemplateFormPage> createState() => _QuoteTemplateFormPageState();
}

class _QuoteTemplateFormPageState extends State<QuoteTemplateFormPage> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _descriptionController;
  late TextEditingController _promptController;
  late TextEditingController _imageUrlController;

  String _selectedCategory = 'minimal';
  bool _isSaving = false;
  File? _selectedImage;
  final ImagePicker _imagePicker = ImagePicker();

  final List<Map<String, String>> _categories = [
    {'id': 'minimal', 'name': 'Minimalis'},
    {'id': 'bold', 'name': 'Bold'},
    {'id': 'elegant', 'name': 'Elegan'},
    {'id': 'modern', 'name': 'Modern'},
    {'id': 'creative', 'name': 'Kreatif'},
  ];

  @override
  void initState() {
    super.initState();
    final template = widget.template;

    _nameController = TextEditingController(text: template?.name ?? '');
    _descriptionController = TextEditingController(text: template?.description ?? '');
    _promptController = TextEditingController(
      text: template?.promptTemplate ??
'''TEXT CONTENT:
- Main Quote: "[QUOTE_TEXT]"
- Attribution: "- [SOURCE]"
- Subtitle: "[SUBTITLE]"
- Watermark: "[LINK]"''',
    );
    _imageUrlController = TextEditingController(text: template?.previewImageUrl ?? '');

    if (template != null) {
      _selectedCategory = template.styleCategory;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _promptController.dispose();
    _imageUrlController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 85,
      );

      if (image != null) {
        setState(() {
          _selectedImage = File(image.path);
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal memilih gambar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<String?> _saveImageToAppDirectory() async {
    if (_selectedImage == null) return null;

    try {
      final dir = await widget.db.documentsDirectory();
      final templatesDir = Directory(p.join(dir.path, 'quote_templates'));

      // Create directory if it doesn't exist
      if (!await templatesDir.exists()) {
        await templatesDir.create(recursive: true);
      }

      // Generate unique filename
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final extension = p.extension(_selectedImage!.path);
      final fileName = 'template_$timestamp$extension';
      final targetPath = p.join(templatesDir.path, fileName);

      // Copy file
      await _selectedImage!.copy(targetPath);
      return targetPath;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal menyimpan gambar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return null;
    }
  }

  Future<void> _saveTemplate() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSaving = true;
    });

    try {
      // Save image if selected
      String? imagePath;
      if (_selectedImage != null) {
        imagePath = await _saveImageToAppDirectory();
      } else if (_imageUrlController.text.isNotEmpty) {
        imagePath = _imageUrlController.text;
      } else if (widget.template != null) {
        imagePath = widget.template!.previewImageUrl;
      }

      final template = QuoteTemplate(
        id: widget.template?.id,
        name: _nameController.text.trim(),
        description: _descriptionController.text.trim(),
        promptTemplate: _promptController.text.trim(),
        previewImageUrl: imagePath,
        styleCategory: _selectedCategory,
        isActive: widget.template?.isActive ?? true,
      );

      if (widget.template == null) {
        // Create new template
        await widget.db.insertQuoteTemplate(template);
      } else {
        // Update existing template
        await widget.db.updateQuoteTemplate(template);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.template == null
                  ? 'Template berhasil ditambahkan'
                  : 'Template berhasil diperbarui',
            ),
            backgroundColor: DS.accent,
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal menyimpan template: $e'),
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
    final isEdit = widget.template != null;

    return Scaffold(
      backgroundColor: DS.bg,
      appBar: AppBar(
        title: Text(isEdit ? 'Edit Template' : 'Tambah Template'),
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
              onPressed: _saveTemplate,
              tooltip: 'Simpan',
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
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
                        'Gunakan placeholder: [QUOTE_TEXT], [SOURCE], [SUBTITLE], [LINK] pada prompt template.',
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

              // 1. Nama Template
              _buildSectionTitle('1. Nama Template', required: true),
              const SizedBox(height: 8),
              TextFormField(
                controller: _nameController,
                style: TextStyle(fontSize: 14, color: DS.text),
                decoration: InputDecoration(
                  hintText: 'Contoh: Orange Brush Strokes',
                  hintStyle: TextStyle(color: DS.textDim, fontSize: 13),
                  filled: true,
                  fillColor: DS.surface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: DS.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: DS.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: DS.accent, width: 2),
                  ),
                  contentPadding: const EdgeInsets.all(12),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Nama template wajib diisi';
                  }
                  return null;
                },
              ),

              const SizedBox(height: 20),

              // 2. Deskripsi
              _buildSectionTitle('2. Deskripsi', required: true),
              const SizedBox(height: 8),
              TextFormField(
                controller: _descriptionController,
                style: TextStyle(fontSize: 14, color: DS.text),
                maxLines: 2,
                decoration: InputDecoration(
                  hintText: 'Contoh: Desain dengan coretan kuas oranye...',
                  hintStyle: TextStyle(color: DS.textDim, fontSize: 13),
                  filled: true,
                  fillColor: DS.surface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: DS.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: DS.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: DS.accent, width: 2),
                  ),
                  contentPadding: const EdgeInsets.all(12),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Deskripsi wajib diisi';
                  }
                  return null;
                },
              ),

              const SizedBox(height: 20),

              // 3. Kategori
              _buildSectionTitle('3. Kategori', required: true),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: _selectedCategory,
                style: TextStyle(fontSize: 14, color: DS.text),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: DS.surface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: DS.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: DS.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: DS.accent, width: 2),
                  ),
                  contentPadding: const EdgeInsets.all(12),
                ),
                dropdownColor: DS.surface,
                items: _categories.map((cat) {
                  return DropdownMenuItem(
                    value: cat['id'],
                    child: Text(cat['name']!),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    _selectedCategory = value!;
                  });
                },
              ),

              const SizedBox(height: 20),

              // 4. Thumbnail
              _buildSectionTitle('4. Gambar Thumbnail (Opsional)'),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: DS.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: DS.border),
                ),
                child: Column(
                  children: [
                    // Preview
                    if (_selectedImage != null)
                      Container(
                        width: double.infinity,
                        height: 200,
                        decoration: BoxDecoration(
                          color: DS.bg,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: DS.border),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.file(
                            _selectedImage!,
                            fit: BoxFit.cover,
                          ),
                        ),
                      )
                    else if (_imageUrlController.text.isNotEmpty)
                      Container(
                        width: double.infinity,
                        height: 200,
                        decoration: BoxDecoration(
                          color: DS.bg,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: DS.border),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(
                            _imageUrlController.text,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Center(
                              child: Icon(
                                Icons.broken_image,
                                color: DS.textDim,
                                size: 48,
                              ),
                            ),
                          ),
                        ),
                      )
                    else if (widget.template?.previewImageUrl != null)
                      Container(
                        width: double.infinity,
                        height: 200,
                        decoration: BoxDecoration(
                          color: DS.bg,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: DS.border),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.file(
                            File(widget.template!.previewImageUrl!),
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Center(
                              child: Icon(
                                Icons.broken_image,
                                color: DS.textDim,
                                size: 48,
                              ),
                            ),
                          ),
                        ),
                      )
                    else
                      Container(
                        width: double.infinity,
                        height: 200,
                        decoration: BoxDecoration(
                          color: DS.bg,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: DS.border, style: BorderStyle.solid),
                        ),
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.image_outlined,
                                color: DS.textDim,
                                size: 48,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Belum ada gambar',
                                style: TextStyle(
                                  color: DS.textDim,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                    const SizedBox(height: 12),

                    // Buttons
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _pickImage,
                            icon: const Icon(Icons.photo_library, size: 18),
                            label: const Text('Pilih Gambar'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: DS.accent,
                              side: BorderSide(color: DS.accent),
                            ),
                          ),
                        ),
                        if (_selectedImage != null) ...[
                          const SizedBox(width: 8),
                          IconButton(
                            onPressed: () {
                              setState(() {
                                _selectedImage = null;
                              });
                            },
                            icon: const Icon(Icons.close),
                            color: Colors.red,
                            tooltip: 'Hapus gambar',
                          ),
                        ],
                      ],
                    ),

                    const SizedBox(height: 12),

                    // Or use URL
                    TextFormField(
                      controller: _imageUrlController,
                      style: TextStyle(fontSize: 13, color: DS.text),
                      decoration: InputDecoration(
                        hintText: 'Atau masukkan URL gambar',
                        hintStyle: TextStyle(color: DS.textDim, fontSize: 12),
                        filled: true,
                        fillColor: DS.bg,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: BorderSide(color: DS.border),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: BorderSide(color: DS.border),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 10,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // 5. Prompt Template
              _buildSectionTitle('5. Prompt Template', required: true),
              const SizedBox(height: 8),
              TextFormField(
                controller: _promptController,
                style: TextStyle(
                  fontSize: 13,
                  color: DS.text,
                  fontFamily: 'monospace',
                ),
                maxLines: 15,
                decoration: InputDecoration(
                  hintText: 'Tambahkan prompt style/design untuk menghasilkan gambar quote...',
                  hintStyle: TextStyle(color: DS.textDim, fontSize: 12),
                  filled: true,
                  fillColor: DS.surface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: DS.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: DS.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: DS.accent, width: 2),
                  ),
                  contentPadding: const EdgeInsets.all(12),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Prompt template wajib diisi';
                  }
                  return null;
                },
              ),

              const SizedBox(height: 32),

              // Save button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isSaving ? null : _saveTemplate,
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
                        const Icon(Icons.check, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        _isSaving
                            ? 'Menyimpan...'
                            : (isEdit ? 'Update Template' : 'Simpan Template'),
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
      ),
    );
  }

  Widget _buildSectionTitle(String title, {bool required = false}) {
    return Row(
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: DS.text,
          ),
        ),
        if (required) ...[
          const SizedBox(width: 4),
          const Text(
            '*',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Colors.red,
            ),
          ),
        ],
      ],
    );
  }
}
