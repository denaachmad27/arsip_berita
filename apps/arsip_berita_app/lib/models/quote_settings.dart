class QuoteSettings {
  final String sourceQuote;
  final String subtitle;
  final String linkAdvertisement;
  final String fontType;
  final int fontSize;

  // Predefined source quote options
  static const List<String> sourceQuoteOptions = [
    'Mandela',
    'Gandhi',
    'Tokoh politik lain',
    'Tokoh inspiratif',
    'Ulama',
    'Filsuf',
    'Penulis terkenal',
    'Lainnya (custom)',
  ];

  QuoteSettings({
    this.sourceQuote = 'Tokoh inspiratif',
    this.subtitle = '',
    this.linkAdvertisement = '',
    this.fontType = 'Roboto',
    this.fontSize = 24,
  });

  QuoteSettings copyWith({
    String? sourceQuote,
    String? subtitle,
    String? linkAdvertisement,
    String? fontType,
    int? fontSize,
  }) {
    return QuoteSettings(
      sourceQuote: sourceQuote ?? this.sourceQuote,
      subtitle: subtitle ?? this.subtitle,
      linkAdvertisement: linkAdvertisement ?? this.linkAdvertisement,
      fontType: fontType ?? this.fontType,
      fontSize: fontSize ?? this.fontSize,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'sourceQuote': sourceQuote,
      'subtitle': subtitle,
      'linkAdvertisement': linkAdvertisement,
      'fontType': fontType,
      'fontSize': fontSize,
    };
  }

  factory QuoteSettings.fromJson(Map<String, dynamic> json) {
    return QuoteSettings(
      sourceQuote: json['sourceQuote'] as String? ?? 'Tokoh inspiratif',
      subtitle: json['subtitle'] as String? ?? '',
      linkAdvertisement: json['linkAdvertisement'] as String? ?? '',
      fontType: json['fontType'] as String? ?? 'Roboto',
      fontSize: json['fontSize'] as int? ?? 24,
    );
  }

  /// Build prompt template for OpenAI DALL-E with current settings
  String buildDallEPrompt(String quoteText) {
    final sourceText = sourceQuote.isNotEmpty ? sourceQuote : 'Tokoh inspiratif';

    // Build simple, visual-focused description
    String content = 'Quote card design:\n\n';
    content += 'Main quote text: "$quoteText"\n';
    content += 'Attribution: "- $sourceText"\n';

    if (subtitle.isNotEmpty) {
      content += 'Subtitle: "$subtitle"\n';
    }

    if (linkAdvertisement.isNotEmpty) {
      content += 'Watermark: "$linkAdvertisement"\n';
    }

    return '''Create a clean, elegant quote card for social media posting.

TEXT TO DISPLAY:
$content

VISUAL STYLE:
- Minimalist and modern design
- Square format (1:1 ratio)
- Main quote centered and prominent
- Attribution below quote in smaller text${subtitle.isNotEmpty ? '\n- Subtitle in small text below attribution' : ''}${linkAdvertisement.isNotEmpty ? '\n- Small watermark in bottom right corner' : ''}
- Soft gradient background with muted colors
- Elegant typography (${fontType.toLowerCase()} style)
- Clean white space around text
- Professional and readable layout

IMPORTANT:
- Display text exactly as written, no typos
- No technical elements or code visible
- Focus on typography and composition
- Keep design simple and elegant''';
  }

  /// Build prompt template for Google Imagen with current settings
  /// Based on Imagen documentation: Use natural language with clear text specification
  ///
  /// NOTE: This is a fallback prompt. For best results, use GeminiPromptOptimizer
  /// to generate optimized prompt using Gemini 2.0 Flash
  String buildImagenPrompt(String quoteText) {
    final sourceText = sourceQuote.isNotEmpty ? sourceQuote : '';

    // Use simple, clear language to describe what text should appear
    // Imagen documentation example: "A {style} logo for a {area} company. Include the text {name}."

    String prompt = 'A minimalist quote card with soft gradient background. ';

    // Main quote text
    prompt += 'Include the text "$quoteText" ';

    // Attribution
    if (sourceText.isNotEmpty) {
      prompt += 'with attribution "- $sourceText" below it';
    }

    // Additional elements
    if (subtitle.isNotEmpty && linkAdvertisement.isNotEmpty) {
      prompt += ', subtitle text "$subtitle" and credit "$linkAdvertisement" at bottom';
    } else if (subtitle.isNotEmpty) {
      prompt += ' and subtitle text "$subtitle" below';
    } else if (linkAdvertisement.isNotEmpty) {
      prompt += ' and credit text "$linkAdvertisement" at bottom corner';
    }

    prompt += '. Use elegant typography, centered layout, pastel colors, modern style';

    return prompt;
  }

  /// Get parameters for Gemini Prompt Optimizer
  Map<String, String?> getImagenParameters(String quoteText) {
    return {
      'quoteText': quoteText,
      'sourceQuote': sourceQuote.isNotEmpty ? sourceQuote : null,
      'subtitle': subtitle.isNotEmpty ? subtitle : null,
      'linkAdvertisement': linkAdvertisement.isNotEmpty ? linkAdvertisement : null,
    };
  }
}
