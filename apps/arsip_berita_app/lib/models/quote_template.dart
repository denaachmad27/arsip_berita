import 'dart:convert';

class QuoteTemplate {
  final int? id;
  final String name;
  final String description;
  final String promptTemplate;
  final String? previewImageUrl;
  final String styleCategory; // 'minimal', 'bold', 'elegant', 'modern', 'creative'
  final Map<String, dynamic>? customSettings;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  QuoteTemplate({
    this.id,
    required this.name,
    required this.description,
    required this.promptTemplate,
    this.previewImageUrl,
    required this.styleCategory,
    this.customSettings,
    this.isActive = true,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'description': description,
        'prompt_template': promptTemplate,
        'preview_image_url': previewImageUrl,
        'style_category': styleCategory,
        'custom_settings': customSettings != null ? jsonEncode(customSettings) : null,
        'is_active': isActive ? 1 : 0,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  factory QuoteTemplate.fromMap(Map<String, Object?> m) => QuoteTemplate(
        id: m['id'] as int?,
        name: m['name'] as String,
        description: m['description'] as String,
        promptTemplate: m['prompt_template'] as String,
        previewImageUrl: m['preview_image_url'] as String?,
        styleCategory: m['style_category'] as String,
        customSettings: m['custom_settings'] != null
            ? jsonDecode(m['custom_settings'] as String) as Map<String, dynamic>
            : null,
        isActive: (m['is_active'] as int?) == 1,
        createdAt: DateTime.tryParse((m['created_at'] as String?) ?? '') ?? DateTime.now(),
        updatedAt: DateTime.tryParse((m['updated_at'] as String?) ?? '') ?? DateTime.now(),
      );

  QuoteTemplate copyWith({
    int? id,
    String? name,
    String? description,
    String? promptTemplate,
    String? previewImageUrl,
    String? styleCategory,
    Map<String, dynamic>? customSettings,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return QuoteTemplate(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      promptTemplate: promptTemplate ?? this.promptTemplate,
      previewImageUrl: previewImageUrl ?? this.previewImageUrl,
      styleCategory: styleCategory ?? this.styleCategory,
      customSettings: customSettings ?? this.customSettings,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// Build final prompt with actual values
  String buildPrompt({
    required String quoteText,
    required String sourceQuote,
    String? subtitle,
    String? linkAdvertisement,
  }) {
    String prompt = promptTemplate;

    // Replace placeholders with actual values
    prompt = prompt.replaceAll('[QUOTE_TEXT]', quoteText);
    prompt = prompt.replaceAll('[SOURCE]', sourceQuote);
    prompt = prompt.replaceAll('[SUBTITLE]', subtitle ?? '');
    prompt = prompt.replaceAll('[LINK]', linkAdvertisement ?? '');

    return prompt;
  }
}
