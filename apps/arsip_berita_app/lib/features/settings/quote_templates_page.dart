import 'package:flutter/material.dart';
import '../../data/local/db.dart';
import '../../models/quote_template.dart';
import '../../ui/design.dart';
import 'quote_template_form_page.dart';

class QuoteTemplatesPage extends StatefulWidget {
  final LocalDatabase db;

  const QuoteTemplatesPage({super.key, required this.db});

  @override
  State<QuoteTemplatesPage> createState() => _QuoteTemplatesPageState();
}

class _QuoteTemplatesPageState extends State<QuoteTemplatesPage> {
  List<QuoteTemplate> _templates = [];
  bool _isLoading = true;
  String _selectedCategory = 'all';

  final List<Map<String, String>> _categories = [
    {'id': 'all', 'name': 'Semua'},
    {'id': 'minimal', 'name': 'Minimalis'},
    {'id': 'bold', 'name': 'Bold'},
    {'id': 'elegant', 'name': 'Elegan'},
    {'id': 'modern', 'name': 'Modern'},
    {'id': 'creative', 'name': 'Kreatif'},
  ];

  @override
  void initState() {
    super.initState();
    _loadTemplates();
  }

  Future<void> _loadTemplates() async {
    setState(() {
      _isLoading = true;
    });

    try {
      List<QuoteTemplate> templates;
      if (_selectedCategory == 'all') {
        templates = await widget.db.getQuoteTemplates(activeOnly: false);
      } else {
        templates = await widget.db.getQuoteTemplatesByCategory(_selectedCategory);
        // Also include inactive templates for the selected category
        final allInCategory = await widget.db.getQuoteTemplates(activeOnly: false);
        templates = allInCategory
            .where((t) => t.styleCategory == _selectedCategory)
            .toList();
      }

      setState(() {
        _templates = templates;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal memuat templates: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _toggleTemplateStatus(QuoteTemplate template) async {
    try {
      final updated = template.copyWith(isActive: !template.isActive);
      await widget.db.updateQuoteTemplate(updated);
      await _loadTemplates();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              template.isActive
                  ? 'Template dinonaktifkan'
                  : 'Template diaktifkan',
            ),
            backgroundColor: DS.accent,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal mengubah status: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _deleteTemplate(QuoteTemplate template) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: DS.surface,
        title: Text('Hapus Template?', style: TextStyle(color: DS.text)),
        content: Text(
          'Template "${template.name}" akan dihapus. Tindakan ini tidak dapat dibatalkan.',
          style: TextStyle(color: DS.text),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Batal', style: TextStyle(color: DS.textDim)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Hapus', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true && template.id != null) {
      try {
        await widget.db.deleteQuoteTemplate(template.id!);
        await _loadTemplates();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Template berhasil dihapus'),
              backgroundColor: DS.accent,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Gagal menghapus template: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Future<void> _navigateToForm({QuoteTemplate? template}) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => QuoteTemplateFormPage(
          db: widget.db,
          template: template,
        ),
      ),
    );

    if (result == true) {
      await _loadTemplates();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DS.bg,
      appBar: AppBar(
        title: const Text('Kelola Template Quote'),
        backgroundColor: DS.surface,
        foregroundColor: DS.text,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _navigateToForm(),
            tooltip: 'Tambah Template Baru',
          ),
        ],
      ),
      body: Column(
        children: [
          // Category filter
          Container(
            height: 56,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: DS.surface,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _categories.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final category = _categories[index];
                final isSelected = _selectedCategory == category['id'];

                return FilterChip(
                  label: Text(category['name']!),
                  selected: isSelected,
                  onSelected: (selected) {
                    setState(() {
                      _selectedCategory = category['id']!;
                    });
                    _loadTemplates();
                  },
                  backgroundColor: DS.bg,
                  selectedColor: DS.accent,
                  labelStyle: TextStyle(
                    color: isSelected ? Colors.white : DS.text,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  ),
                  side: BorderSide(
                    color: isSelected ? DS.accent : DS.border,
                  ),
                );
              },
            ),
          ),

          // Templates list
          Expanded(
            child: _isLoading
                ? Center(
                    child: CircularProgressIndicator(color: DS.accent),
                  )
                : _templates.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.style_outlined,
                              size: 64,
                              color: DS.textDim,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Belum ada template',
                              style: TextStyle(
                                fontSize: 16,
                                color: DS.textDim,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Tap tombol + untuk menambah',
                              style: TextStyle(
                                fontSize: 14,
                                color: DS.textDim,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _templates.length,
                        itemBuilder: (context, index) {
                          final template = _templates[index];
                          return _buildTemplateCard(template);
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildTemplateCard(QuoteTemplate template) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: DS.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: DS.border),
      ),
      child: InkWell(
        onTap: () => _navigateToForm(template: template),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // Thumbnail or placeholder
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: DS.bg,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: DS.border),
                    ),
                    child: template.previewImageUrl != null
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.network(
                              template.previewImageUrl!,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Icon(
                                Icons.image_outlined,
                                color: DS.textDim,
                                size: 30,
                              ),
                            ),
                          )
                        : Icon(
                            Icons.style,
                            color: DS.textDim,
                            size: 30,
                          ),
                  ),

                  const SizedBox(width: 12),

                  // Template info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                template.name,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: DS.text,
                                ),
                              ),
                            ),
                            // Status badge
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: template.isActive
                                    ? DS.accent.withValues(alpha: 0.1)
                                    : DS.textDim.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                template.isActive ? 'Aktif' : 'Nonaktif',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: template.isActive
                                      ? DS.accent
                                      : DS.textDim,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          template.description,
                          style: TextStyle(
                            fontSize: 13,
                            color: DS.textDim,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: DS.accent.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            _getCategoryName(template.styleCategory),
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: DS.accent,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // Action buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton.icon(
                    onPressed: () => _toggleTemplateStatus(template),
                    icon: Icon(
                      template.isActive
                          ? Icons.visibility_off
                          : Icons.visibility,
                      size: 16,
                    ),
                    label: Text(
                      template.isActive ? 'Nonaktifkan' : 'Aktifkan',
                    ),
                    style: TextButton.styleFrom(
                      foregroundColor: DS.text,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => _navigateToForm(template: template),
                    icon: const Icon(Icons.edit, size: 16),
                    label: const Text('Edit'),
                    style: TextButton.styleFrom(
                      foregroundColor: DS.accent,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => _deleteTemplate(template),
                    icon: const Icon(Icons.delete, size: 16),
                    label: const Text('Hapus'),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.red,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _getCategoryName(String category) {
    final found = _categories.firstWhere(
      (c) => c['id'] == category,
      orElse: () => {'id': category, 'name': category},
    );
    return found['name']!;
  }
}
