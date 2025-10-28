import '../data/local/db.dart';
import '../models/quote_template.dart';

class QuoteTemplateService {
  final LocalDatabase db;

  QuoteTemplateService({required this.db});

  /// Get all active templates
  Future<List<QuoteTemplate>> getActiveTemplates() async {
    return await db.getQuoteTemplates(activeOnly: true);
  }

  /// Get all templates (including inactive)
  Future<List<QuoteTemplate>> getAllTemplates() async {
    return await db.getQuoteTemplates(activeOnly: false);
  }

  /// Get template by ID
  Future<QuoteTemplate?> getTemplateById(int id) async {
    return await db.getQuoteTemplateById(id);
  }

  /// Get templates by style category
  Future<List<QuoteTemplate>> getTemplatesByCategory(String category) async {
    return await db.getQuoteTemplatesByCategory(category);
  }

  /// Get templates grouped by category
  Future<Map<String, List<QuoteTemplate>>> getTemplatesGroupedByCategory() async {
    final templates = await getActiveTemplates();
    final grouped = <String, List<QuoteTemplate>>{};

    for (final template in templates) {
      if (!grouped.containsKey(template.styleCategory)) {
        grouped[template.styleCategory] = [];
      }
      grouped[template.styleCategory]!.add(template);
    }

    return grouped;
  }

  /// Save new template
  Future<int> saveTemplate(QuoteTemplate template) async {
    return await db.insertQuoteTemplate(template);
  }

  /// Update existing template
  Future<void> updateTemplate(QuoteTemplate template) async {
    await db.updateQuoteTemplate(template);
  }

  /// Delete template
  Future<void> deleteTemplate(int id) async {
    await db.deleteQuoteTemplate(id);
  }

  /// Build prompt from template with actual values
  Future<String?> buildPromptFromTemplate({
    required int templateId,
    required String quoteText,
    required String sourceQuote,
    String? subtitle,
    String? linkAdvertisement,
  }) async {
    final template = await getTemplateById(templateId);
    if (template == null) return null;

    return template.buildPrompt(
      quoteText: quoteText,
      sourceQuote: sourceQuote,
      subtitle: subtitle,
      linkAdvertisement: linkAdvertisement,
    );
  }

  /// Get available style categories
  List<String> getStyleCategories() {
    return ['minimal', 'bold', 'elegant', 'modern', 'creative'];
  }

  /// Get category display name
  String getCategoryDisplayName(String category) {
    switch (category) {
      case 'minimal':
        return 'Minimalis';
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

  /// Initialize default templates (should be called once)
  Future<void> initializeDefaults() async {
    await db.initDefaultQuoteTemplates();
  }
}
