class ArticleInput {
  final String title;
  final String url;
  final DateTime? publishedAt;
  final String? description;
  final String? excerpt;
  final String? canonicalUrl;
  final String? mediaName;
  final String? mediaType; // online/print/tv/radio/social
  final List<String> authors;
  final List<String> people;
  final List<String> organizations;

  ArticleInput({
    required this.title,
    required this.url,
    this.publishedAt,
    this.description,
    this.excerpt,
    this.canonicalUrl,
    this.mediaName,
    this.mediaType,
    this.authors = const [],
    this.people = const [],
    this.organizations = const [],
  });
}

