import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart' as dom;

String normalizeUrl(String input) {
  try {
    final u = Uri.parse(input);
    final qp = Map.of(u.queryParameters)..removeWhere((k, v) => const {
      'utm_source','utm_medium','utm_campaign','utm_term','utm_content','fbclid','gclid'
    }.contains(k));
    final nu = Uri(
      scheme: u.scheme,
      userInfo: u.userInfo,
      host: u.host,
      port: u.hasPort ? u.port : null,
      path: u.path,
      queryParameters: qp.isEmpty ? null : qp,
    );
    return nu.toString();
  } catch (_) {
    return input;
  }
}

class ExtractedMetadata {
  final String? canonicalUrl;
  final String? title;
  final String? description;
  final String? excerpt;
  final String? fullContent;
  final String? mediaName;
  final DateTime? publishedDate;
  final String? coverImageUrl;
  final Uint8List? coverImageBytes;
  ExtractedMetadata({
    this.canonicalUrl,
    this.title,
    this.description,
    this.excerpt,
    this.fullContent,
    this.mediaName,
    this.publishedDate,
    this.coverImageUrl,
    this.coverImageBytes,
  });
}

class MetadataExtractor {
  Future<ExtractedMetadata?> fetch(String url) async {
    var fixedUrl = url.trim();
    if (fixedUrl.startsWith('htps://')) {
      fixedUrl = fixedUrl.replaceFirst('htps://', 'https://');
    }

    // Add headers to mimic a real browser and avoid being blocked
    final headers = {
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
      'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8',
      'Accept-Language': 'id-ID,id;q=0.9,en-US;q=0.8,en;q=0.7',
      'Accept-Encoding': 'gzip, deflate, br',
      'Connection': 'keep-alive',
      'Upgrade-Insecure-Requests': '1',
      'Sec-Fetch-Dest': 'document',
      'Sec-Fetch-Mode': 'navigate',
      'Sec-Fetch-Site': 'none',
      'Cache-Control': 'max-age=0',
    };

    final res = await http.get(Uri.parse(fixedUrl), headers: headers);

    if (res.statusCode < 200 || res.statusCode >= 300) {
      debugPrint('❌ HTTP Error ${res.statusCode} for URL: $fixedUrl');
      return null;
    }

    // Handle encoding properly to avoid "Missing extension byte" error
    String htmlContent;
    try {
      // Detect encoding from headers or content
      final contentType = res.headers['content-type'] ?? '';

      if (contentType.toLowerCase().contains('charset=')) {
        // Extract charset from content-type header
        final charsetMatch = RegExp(r'charset=([^;]+)').firstMatch(contentType);
        if (charsetMatch != null) {
          final charset = charsetMatch.group(1)?.trim().toLowerCase();
          debugPrint('🔤 Detected charset: $charset');

          // Use appropriate decoder
          if (charset == 'utf-8' || charset == 'utf8') {
            htmlContent = utf8.decode(res.bodyBytes, allowMalformed: true);
          } else if (charset == 'iso-8859-1' || charset == 'latin1') {
            htmlContent = latin1.decode(res.bodyBytes);
          } else {
            // Fallback to UTF-8 with malformed chars allowed
            htmlContent = utf8.decode(res.bodyBytes, allowMalformed: true);
          }
        } else {
          htmlContent = utf8.decode(res.bodyBytes, allowMalformed: true);
        }
      } else {
        // No charset specified, try UTF-8 with malformed chars allowed
        htmlContent = utf8.decode(res.bodyBytes, allowMalformed: true);
      }
    } catch (e) {
      debugPrint('❌ Encoding error: $e');
      // Last resort: use Latin1 (accepts all bytes)
      htmlContent = latin1.decode(res.bodyBytes);
    }

    final doc = html_parser.parse(htmlContent);

    // Debug: check document structure
    debugPrint('📄 Document parsed - body exists: ${doc.body != null}');
    bool isPossiblyJSRendered = false;

    if (doc.body != null) {
      final totalElements = doc.body!.querySelectorAll('*').length;
      final pTags = doc.body!.querySelectorAll('p').length;
      final divTags = doc.body!.querySelectorAll('div').length;

      debugPrint('📊 Total elements in body: $totalElements');
      debugPrint('📊 Total <p> tags: $pTags');
      debugPrint('📊 Total <div> tags: $divTags');

      // Check if there are any text-containing elements
      final textElements = doc.body!.querySelectorAll('*').where((e) =>
        e.text.trim().length > 100
      ).length;
      debugPrint('📊 Elements with >100 chars text: $textElements');

      // Detect if page is likely JavaScript-rendered (very few elements)
      if (totalElements < 50 && pTags == 0 && divTags < 5) {
        isPossiblyJSRendered = true;
        debugPrint('⚠️ WARNING: Page appears to be JavaScript-rendered (SPA)');
      }
    }

    final result = await _extract(doc, res.request?.url.toString() ?? fixedUrl);

    // If extraction failed and page is JS-rendered, add special marker
    if (isPossiblyJSRendered && (result.fullContent == null || result.fullContent!.isEmpty)) {
      return ExtractedMetadata(
        canonicalUrl: result.canonicalUrl,
        title: result.title,
        description: result.description,
        excerpt: result.excerpt,
        fullContent: '__JS_RENDERED_PAGE__', // Special marker
        mediaName: result.mediaName,
        publishedDate: result.publishedDate,
        coverImageUrl: result.coverImageUrl,
        coverImageBytes: result.coverImageBytes,
      );
    }

    return result;
  }

  Future<ExtractedMetadata> _extract(dom.Document doc, String baseUrl) async {
    String? getMeta(String selector) => doc.querySelector(selector)?.attributes['content'];
    final title = getMeta('meta[property="og:title"]') ?? getMeta('meta[name="twitter:title"]') ?? doc.querySelector('title')?.text;
    final description = getMeta('meta[property="og:description"]') ?? getMeta('meta[name="description"]');
    final canonical = doc.querySelector('link[rel="canonical"]')?.attributes['href'];
    final canonAbs = canonical == null ? null : Uri.parse(baseUrl).resolve(canonical).toString();
    final paragraphs = doc.querySelectorAll('p').map((e) => e.text.trim()).where((t) => t.length > 40).toList();
    final excerpt = description ?? (paragraphs.take(3).join(' ').substring(0, paragraphs.isNotEmpty ? (paragraphs.join(' ').length.clamp(0, 500)) : 0));

    // Extract full article content
    final fullContent = _extractArticleContent(doc, baseUrl);

    // Extract media name
    final mediaName = _extractMediaName(doc, baseUrl);

    // Extract published date
    final publishedDate = _extractPublishedDate(doc);

    // Extract cover image
    final coverImageUrl = _extractCoverImageUrl(doc, baseUrl);
    Uint8List? coverImageBytes;
    if (coverImageUrl != null) {
      coverImageBytes = await _downloadImage(coverImageUrl);
    }

    return ExtractedMetadata(
      canonicalUrl: canonAbs != null ? normalizeUrl(canonAbs) : null,
      title: title,
      description: description,
      excerpt: excerpt.isEmpty ? null : excerpt,
      fullContent: fullContent,
      mediaName: mediaName,
      publishedDate: publishedDate,
      coverImageUrl: coverImageUrl,
      coverImageBytes: coverImageBytes,
    );
  }

  String? _extractArticleContent(dom.Document doc, String baseUrl) {
    // Try common article content selectors (in order of priority)
    final contentSelectors = [
      // Structured data
      '[itemprop="articleBody"]',
      // CNN Indonesia specific
      '.detail-text',
      '#detikdetailtext',
      'div.detail_text',
      // CNBC Indonesia specific
      'div.detail',
      'div.detail_text',
      // Detik specific
      'div[class*="detikdetailtext"]',
      'div[id*="detikdetailtext"]',
      // Kompas specific
      'div.read__content',
      // Tempo specific
      'div.detail-in',
      // Tribun specific (various patterns)
      'div.side-article',
      'div.txt-article',
      'article.side-article',
      '.side-article .txt-article',
      'div[class*="side-article"]',
      'div[class*="article-content"]',
      // Tribun alternative patterns
      'div#article',
      'div.article',
      'div[id*="article"]',
      // Look for containers with many p tags
      'body > div',
      'main > div',
      // Generic selectors
      'article[class*="detail"]',
      'div[class*="detail_text"]',
      'div[class*="detail-text"]',
      'article[class*="content"]',
      'article[class*="article"]',
      'div[class*="article-content"]',
      'div[class*="article_content"]',
      'div[class*="entry-content"]',
      'div[class*="post-content"]',
      'div[class*="story-content"]',
      'div[class*="article-body"]',
      'div[class*="post-body"]',
      'div[class*="content-detail"]',
      'div[id*="article-content"]',
      'div[id*="story-content"]',
      '.article-content',
      '.entry-content',
      '.post-content',
      'article',
      'main article',
    ];

    dom.Element? articleElement;
    int maxScore = 0;
    String? selectedSelector;

    // Score-based selection: find element with best content indicators
    for (final selector in contentSelectors) {
      final element = doc.querySelector(selector);
      if (element == null) continue;

      final score = _scoreContentElement(element);
      debugPrint('📊 Selector "$selector" - Score: $score, Paragraphs: ${element.querySelectorAll('p').length}');

      if (score > maxScore) {
        maxScore = score;
        articleElement = element;
        selectedSelector = selector;
      }
    }

    // Fallback: find the largest container with quality paragraphs
    if (articleElement == null || maxScore < 10) {
      debugPrint('⚠️ Using fallback content container search (maxScore: $maxScore)');
      articleElement = _findBestContentContainer(doc);
    }

    // Ultimate fallback: direct paragraph extraction
    if (articleElement == null) {
      debugPrint('⚠️ No container found, trying direct paragraph extraction');
      final directContent = _extractParagraphsDirect(doc, baseUrl);
      if (directContent != null && directContent.isNotEmpty) {
        debugPrint('✅ Direct extraction successful: ${directContent.length} chars');
        return directContent;
      }
      debugPrint('❌ No article element found');
      return null;
    }

    debugPrint('✅ Selected element with selector: $selectedSelector (score: $maxScore)');

    // Extract and clean content
    final buffer = StringBuffer();
    _processElement(articleElement, buffer, baseUrl);

    final content = buffer.toString().trim();
    debugPrint('📝 Extracted content length: ${content.length} chars');
    debugPrint('📝 First 500 chars of HTML:');
    debugPrint(content.substring(0, content.length.clamp(0, 500)));

    return content.isEmpty ? null : content;
  }

  String? _extractParagraphsDirect(dom.Document doc, String baseUrl) {
    // Get ALL paragraphs from the entire document
    final allParagraphs = doc.querySelectorAll('p');

    if (allParagraphs.isEmpty) {
      debugPrint('❌ No paragraphs found in document');
      return null;
    }

    final buffer = StringBuffer();
    int extractedCount = 0;

    // Filter and extract meaningful paragraphs
    for (final p in allParagraphs) {
      final text = p.text.trim();

      // Skip if too short
      if (text.length < 40) continue;

      // Skip if looks like navigation, ads, or metadata
      if (_isLikelyMetadata(text)) continue;

      // Check parent classes/ids for unwanted content
      final parent = p.parent;
      if (parent != null) {
        final parentClass = (parent.attributes['class'] ?? '').toLowerCase();
        final parentId = (parent.attributes['id'] ?? '').toLowerCase();
        final combined = '$parentClass $parentId';

        // Skip if parent is clearly not article content
        if (combined.contains('nav') ||
            combined.contains('menu') ||
            combined.contains('footer') ||
            combined.contains('header') ||
            combined.contains('sidebar') ||
            combined.contains('widget') ||
            combined.contains('advertisement') ||
            combined.contains('promo') ||
            combined.contains('comment')) {
          continue;
        }
      }

      // This looks like article content - extract with styling
      buffer.write('<p>');
      _processInlineElements(p, buffer, baseUrl);
      buffer.write('</p>');
      extractedCount++;
    }

    final result = buffer.toString().trim();

    if (extractedCount >= 3) {
      debugPrint('✅ Direct extraction: $extractedCount paragraphs extracted');
      return result;
    }

    debugPrint('⚠️ Only $extractedCount paragraphs found, might be too few');
    return extractedCount > 0 ? result : null;
  }

  int _scoreContentElement(dom.Element element) {
    int score = 0;

    // Count meaningful paragraphs (longer than 40 chars, lowered from 50)
    final paragraphs = element.querySelectorAll('p');
    final meaningfulParagraphs = paragraphs.where((p) => p.text.trim().length > 40).length;
    score += meaningfulParagraphs * 5;

    // Bonus for article-related class/id names
    final className = (element.attributes['class'] ?? '').toLowerCase();
    final id = (element.attributes['id'] ?? '').toLowerCase();
    final combined = '$className $id';

    if (combined.contains('article') || combined.contains('story') || combined.contains('content')) {
      score += 10;
    }
    if (combined.contains('detail')) score += 10;
    if (combined.contains('main')) score += 5;

    // Higher bonus for specific article body indicators
    if (combined.contains('articlebody') || combined.contains('article-body') ||
        combined.contains('detail_text') || combined.contains('detail-text')) {
      score += 20;
    }

    // Tribun specific indicators
    if (combined.contains('side-article') || combined.contains('txt-article')) {
      score += 25;
    }

    // Penalty for ads, sidebar (but not side-article), navigation
    if (combined.contains('ad-') || combined.contains('advertisement') ||
        combined.contains('comment') || combined.contains('related') ||
        combined.contains('recommend') || combined.contains('widget') ||
        combined.contains('footer') || combined.contains('header') ||
        (combined.contains('sidebar') && !combined.contains('side-article'))) {
      score -= 20;
    }

    return score;
  }

  dom.Element? _findBestContentContainer(dom.Document doc) {
    // Find element with most meaningful paragraph content
    dom.Element? best;
    int maxScore = 0;
    int maxParagraphCount = 0;

    // First pass: look for containers with many paragraphs
    for (final element in doc.querySelectorAll('div, section, article, main, span')) {
      final paragraphs = element.querySelectorAll('p');
      // More lenient: 30 chars minimum
      final meaningfulParagraphs = paragraphs.where((p) => p.text.trim().length > 30).toList();

      if (meaningfulParagraphs.isEmpty) continue;

      final score = _scoreContentElement(element);
      final paragraphCount = meaningfulParagraphs.length;

      debugPrint('🔍 Fallback checking: ${element.localName}.${element.attributes['class'] ?? ''} - Score: $score, Paragraphs: $paragraphCount');

      // Prioritize: high score OR many paragraphs
      if (score > maxScore || (score >= maxScore && paragraphCount > maxParagraphCount)) {
        maxScore = score;
        maxParagraphCount = paragraphCount;
        best = element;
      }
    }

    // Second pass: if still nothing, find ANY element with most paragraphs (very aggressive)
    if (best == null || maxParagraphCount < 3) {
      debugPrint('⚠️ Aggressive fallback: finding element with most paragraphs');

      for (final element in doc.querySelectorAll('*')) {
        // Direct children paragraphs only (avoid counting nested duplicates)
        final directParagraphs = element.children.where((child) =>
          child.localName == 'p' && child.text.trim().length > 30
        ).toList();

        if (directParagraphs.length > maxParagraphCount) {
          maxParagraphCount = directParagraphs.length;
          best = element;
          debugPrint('🎯 Found better container: ${element.localName}.${element.attributes['class'] ?? ''} with $maxParagraphCount paragraphs');
        }
      }
    }

    if (best != null) {
      debugPrint('✅ Fallback selected: ${best.localName}.${best.attributes['class'] ?? ''} (score: $maxScore, paragraphs: $maxParagraphCount)');
    }

    return best;
  }

  void _processElement(dom.Element element, StringBuffer buffer, String baseUrl) {
    // Skip unwanted elements
    final skipTags = {'script', 'style', 'nav', 'header', 'footer', 'aside', 'form', 'button', 'iframe', 'noscript'};
    final skipClasses = [
      'ad', 'advertisement', 'social', 'share', 'comment', 'related', 'sidebar', 'menu',
      'widget', 'promo', 'subscribe', 'newsletter', 'recommended', 'trending',
      'banner', 'sponsor', 'popup'
    ];

    if (skipTags.contains(element.localName?.toLowerCase())) {
      return;
    }

    // Skip elements with unwanted classes or IDs
    final className = (element.attributes['class'] ?? '').toLowerCase();
    final id = (element.attributes['id'] ?? '').toLowerCase();
    final combined = '$className $id';

    if (skipClasses.any((skip) => combined.contains(skip))) {
      return;
    }

    for (final node in element.nodes) {
      if (node is dom.Element) {
        final tagName = node.localName?.toLowerCase();

        // Process block elements
        if (tagName == 'p') {
          final text = node.text.trim();
          // Accept paragraphs with minimum 20 chars (lowered from 30)
          if (text.isNotEmpty && text.length > 20) {
            // Skip if looks like metadata or caption
            if (!_isLikelyMetadata(text)) {
              buffer.write('<p>');
              _processInlineElements(node, buffer, baseUrl);
              buffer.write('</p>');
            }
          }
        } else if (tagName == 'h1' || tagName == 'h2' || tagName == 'h3' || tagName == 'h4') {
          final text = node.text.trim();
          if (text.isNotEmpty && text.length > 5) {
            buffer.write('<$tagName>');
            _processInlineElements(node, buffer, baseUrl);
            buffer.write('</$tagName>');
          }
        } else if (tagName == 'ul' || tagName == 'ol') {
          final items = node.querySelectorAll('li');
          final validItems = items.where((li) => li.text.trim().length > 10).toList();

          if (validItems.isNotEmpty) {
            buffer.write('<$tagName>');
            for (final li in validItems) {
              final text = li.text.trim();
              if (text.isNotEmpty) {
                buffer.write('<li>');
                _processInlineElements(li, buffer, baseUrl);
                buffer.write('</li>');
              }
            }
            buffer.write('</$tagName>');
          }
        } else if (tagName == 'blockquote') {
          final text = node.text.trim();
          if (text.isNotEmpty && text.length > 20) {
            buffer.write('<blockquote>');
            _processInlineElements(node, buffer, baseUrl);
            buffer.write('</blockquote>');
          }
        } else if (tagName == 'img') {
          // Extract images (with ad filtering)
          if (!_isLikelyAdImage(node)) {
            final src = node.attributes['src'] ?? node.attributes['data-src'];
            if (src != null && src.trim().isNotEmpty) {
              try {
                final absoluteUrl = Uri.parse(baseUrl).resolve(src.trim()).toString();
                final alt = node.attributes['alt'] ?? '';
                buffer.write('<img src="${_escapeHtml(absoluteUrl)}"');
                if (alt.isNotEmpty) {
                  buffer.write(' alt="${_escapeHtml(alt)}"');
                }
                buffer.write(' />');
              } catch (e) {
                debugPrint('⚠️ Failed to process image: $src');
              }
            }
          }
        } else {
          // Recursively process child elements
          _processElement(node, buffer, baseUrl);
        }
      }
    }
  }

  void _processInlineElements(dom.Element element, StringBuffer buffer, String baseUrl) {
    for (final node in element.nodes) {
      if (node is dom.Text) {
        // Plain text node
        final text = node.text;
        if (text.isNotEmpty) {
          buffer.write(_escapeHtml(text));
        }
      } else if (node is dom.Element) {
        final tagName = node.localName?.toLowerCase();

        // Process inline styling elements
        if (tagName == 'strong' || tagName == 'b') {
          buffer.write('<strong>');
          _processInlineElements(node, buffer, baseUrl);
          buffer.write('</strong>');
        } else if (tagName == 'em' || tagName == 'i') {
          buffer.write('<em>');
          _processInlineElements(node, buffer, baseUrl);
          buffer.write('</em>');
        } else if (tagName == 'u') {
          buffer.write('<u>');
          _processInlineElements(node, buffer, baseUrl);
          buffer.write('</u>');
        } else if (tagName == 's' || tagName == 'strike' || tagName == 'del') {
          buffer.write('<s>');
          _processInlineElements(node, buffer, baseUrl);
          buffer.write('</s>');
        } else if (tagName == 'a') {
          final href = node.attributes['href'];
          if (href != null && href.isNotEmpty) {
            // Resolve relative URLs to absolute
            final absoluteUrl = Uri.parse(baseUrl).resolve(href).toString();
            buffer.write('<a href="${_escapeHtml(absoluteUrl)}">');
            _processInlineElements(node, buffer, baseUrl);
            buffer.write('</a>');
          } else {
            // Link without href, just process content
            _processInlineElements(node, buffer, baseUrl);
          }
        } else if (tagName == 'code') {
          buffer.write('<code>');
          _processInlineElements(node, buffer, baseUrl);
          buffer.write('</code>');
        } else if (tagName == 'mark') {
          // Convert <mark> to background color for better compatibility
          buffer.write('<span style="background-color: #fff59d;">');
          _processInlineElements(node, buffer, baseUrl);
          buffer.write('</span>');
        } else if (tagName == 'br') {
          // Preserve line breaks within paragraphs
          buffer.write('<br/>');
        } else if (tagName == 'span') {
          // Just process content of span, ignore styling for now
          _processInlineElements(node, buffer, baseUrl);
        } else {
          // For other inline elements, just process their content
          _processInlineElements(node, buffer, baseUrl);
        }
      }
    }
  }

  bool _isLikelyMetadata(String text) {
    final lower = text.toLowerCase();
    // Skip common metadata patterns
    return lower.startsWith('share') ||
           lower.startsWith('follow') ||
           lower.startsWith('subscribe') ||
           lower.contains('©') ||
           lower.contains('copyright') ||
           (lower.split(' ').length < 5); // Too short to be article content
  }

  String _escapeHtml(String text) {
    return text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&#39;');
  }

  String? _extractMediaName(dom.Document doc, String baseUrl) {
    // Try to get media name from various meta tags
    String? getMeta(String selector) => doc.querySelector(selector)?.attributes['content'];

    // Priority 1: og:site_name (most reliable)
    var mediaName = getMeta('meta[property="og:site_name"]');
    if (mediaName != null && mediaName.trim().isNotEmpty) {
      debugPrint('📰 Media name from og:site_name: $mediaName');
      return mediaName.trim();
    }

    // Priority 2: twitter:site (without @ symbol)
    mediaName = getMeta('meta[name="twitter:site"]');
    if (mediaName != null && mediaName.trim().isNotEmpty) {
      // Remove @ symbol if present
      mediaName = mediaName.trim().replaceFirst(RegExp(r'^@'), '');
      debugPrint('📰 Media name from twitter:site: $mediaName');
      return mediaName;
    }

    // Priority 3: application-name
    mediaName = getMeta('meta[name="application-name"]');
    if (mediaName != null && mediaName.trim().isNotEmpty) {
      debugPrint('📰 Media name from application-name: $mediaName');
      return mediaName.trim();
    }

    // Priority 4: Extract from domain name as fallback
    try {
      final uri = Uri.parse(baseUrl);
      var domain = uri.host;

      // Remove 'www.' prefix
      domain = domain.replaceFirst(RegExp(r'^www\.'), '');

      // Remove TLDs (.com, .co.id, etc.)
      domain = domain.replaceFirst(RegExp(r'\.(com|co\.id|id|net|org|tv)$'), '');

      // Capitalize first letter
      if (domain.isNotEmpty) {
        domain = domain[0].toUpperCase() + domain.substring(1);
        debugPrint('📰 Media name from domain: $domain');
        return domain;
      }
    } catch (e) {
      debugPrint('❌ Failed to extract media name from domain: $e');
    }

    return null;
  }

  DateTime? _extractPublishedDate(dom.Document doc) {
    String? getMeta(String selector) => doc.querySelector(selector)?.attributes['content'];

    // Try various meta tags for published date
    final dateSelectors = [
      'meta[property="article:published_time"]',
      'meta[name="article:published_time"]',
      'meta[property="datePublished"]',
      'meta[name="datePublished"]',
      'meta[property="publishdate"]',
      'meta[name="publishdate"]',
      'meta[property="publish-date"]',
      'meta[name="publish-date"]',
      'meta[name="date"]',
      'meta[property="og:published_time"]',
      'meta[name="publication_date"]',
      'meta[name="DC.date.issued"]',
      'time[itemprop="datePublished"]',
    ];

    for (final selector in dateSelectors) {
      String? dateStr;

      if (selector.startsWith('time[')) {
        // For <time> elements, try datetime attribute first
        final timeElement = doc.querySelector(selector);
        dateStr = timeElement?.attributes['datetime'] ?? timeElement?.text;
      } else {
        dateStr = getMeta(selector);
      }

      if (dateStr != null && dateStr.trim().isNotEmpty) {
        try {
          final date = DateTime.parse(dateStr.trim());
          debugPrint('📅 Published date from $selector: $date');
          return date;
        } catch (e) {
          debugPrint('⚠️ Failed to parse date from $selector: $dateStr');
          continue;
        }
      }
    }

    // Try schema.org JSON-LD
    try {
      final scripts = doc.querySelectorAll('script[type="application/ld+json"]');
      for (final script in scripts) {
        final jsonText = script.text;
        if (jsonText.isEmpty) continue;

        try {
          final dynamic jsonData = jsonDecode(jsonText);

          // Handle both single object and array of objects
          final List<dynamic> items = jsonData is List ? jsonData : [jsonData];

          for (final item in items) {
            if (item is! Map<String, dynamic>) continue;

            // Check for Article type
            final type = item['@type'];
            if (type == 'Article' || type == 'NewsArticle' || type == 'BlogPosting') {
              final datePublished = item['datePublished'];
              if (datePublished != null && datePublished is String) {
                try {
                  final date = DateTime.parse(datePublished.trim());
                  debugPrint('📅 Published date from JSON-LD: $date');
                  return date;
                } catch (e) {
                  debugPrint('⚠️ Failed to parse JSON-LD date: $datePublished');
                }
              }
            }
          }
        } catch (e) {
          debugPrint('⚠️ Failed to parse JSON-LD script: $e');
          continue;
        }
      }
    } catch (e) {
      debugPrint('❌ Error processing JSON-LD: $e');
    }

    debugPrint('❌ No published date found');
    return null;
  }

  String? _extractCoverImageUrl(dom.Document doc, String baseUrl) {
    String? getMeta(String selector) => doc.querySelector(selector)?.attributes['content'];

    // Try various meta tags for cover image
    final imageSelectors = [
      'meta[property="og:image"]',
      'meta[property="og:image:url"]',
      'meta[name="twitter:image"]',
      'meta[name="twitter:image:src"]',
      'meta[property="article:image"]',
      'meta[name="thumbnail"]',
    ];

    for (final selector in imageSelectors) {
      final imageUrl = getMeta(selector);
      if (imageUrl != null && imageUrl.trim().isNotEmpty) {
        try {
          // Resolve relative URLs to absolute
          final absoluteUrl = Uri.parse(baseUrl).resolve(imageUrl.trim()).toString();
          debugPrint('🖼️ Cover image from $selector: $absoluteUrl');
          return absoluteUrl;
        } catch (e) {
          debugPrint('⚠️ Failed to resolve image URL: $imageUrl');
          continue;
        }
      }
    }

    // Try link tag
    final linkImage = doc.querySelector('link[rel="image_src"]')?.attributes['href'];
    if (linkImage != null && linkImage.trim().isNotEmpty) {
      try {
        final absoluteUrl = Uri.parse(baseUrl).resolve(linkImage.trim()).toString();
        debugPrint('🖼️ Cover image from link[rel="image_src"]: $absoluteUrl');
        return absoluteUrl;
      } catch (e) {
        debugPrint('⚠️ Failed to resolve link image URL: $linkImage');
      }
    }

    // Try schema.org JSON-LD
    try {
      final scripts = doc.querySelectorAll('script[type="application/ld+json"]');
      for (final script in scripts) {
        final jsonText = script.text;
        if (jsonText.isEmpty) continue;

        try {
          final dynamic jsonData = jsonDecode(jsonText);
          final List<dynamic> items = jsonData is List ? jsonData : [jsonData];

          for (final item in items) {
            if (item is! Map<String, dynamic>) continue;

            final type = item['@type'];
            if (type == 'Article' || type == 'NewsArticle' || type == 'BlogPosting') {
              final image = item['image'];
              String? imageUrl;

              if (image is String) {
                imageUrl = image;
              } else if (image is Map && image['url'] is String) {
                imageUrl = image['url'];
              } else if (image is List && image.isNotEmpty) {
                final first = image.first;
                if (first is String) {
                  imageUrl = first;
                } else if (first is Map && first['url'] is String) {
                  imageUrl = first['url'];
                }
              }

              if (imageUrl != null && imageUrl.trim().isNotEmpty) {
                try {
                  final absoluteUrl = Uri.parse(baseUrl).resolve(imageUrl.trim()).toString();
                  debugPrint('🖼️ Cover image from JSON-LD: $absoluteUrl');
                  return absoluteUrl;
                } catch (e) {
                  debugPrint('⚠️ Failed to resolve JSON-LD image URL: $imageUrl');
                }
              }
            }
          }
        } catch (e) {
          continue;
        }
      }
    } catch (e) {
      debugPrint('❌ Error processing JSON-LD for image: $e');
    }

    // Fallback: Find first large image in article content
    try {
      final articleSelectors = [
        '[itemprop="articleBody"] img',
        'article img',
        '.article-content img',
        '.entry-content img',
        '.post-content img',
        '.detail-text img',
        '.read__content img',
      ];

      for (final selector in articleSelectors) {
        final images = doc.querySelectorAll(selector);
        for (final img in images) {
          final src = img.attributes['src'] ?? img.attributes['data-src'];
          if (src == null || src.trim().isEmpty) continue;

          // Skip if image looks like an ad
          if (_isLikelyAdImage(img)) continue;

          try {
            final absoluteUrl = Uri.parse(baseUrl).resolve(src.trim()).toString();
            debugPrint('🖼️ Cover image from article content (fallback): $absoluteUrl');
            return absoluteUrl;
          } catch (e) {
            continue;
          }
        }
      }
    } catch (e) {
      debugPrint('❌ Error finding fallback image: $e');
    }

    debugPrint('❌ No cover image found');
    return null;
  }

  bool _isLikelyAdImage(dom.Element img) {
    final src = img.attributes['src'] ?? img.attributes['data-src'] ?? '';
    final className = (img.attributes['class'] ?? '').toLowerCase();
    final id = (img.attributes['id'] ?? '').toLowerCase();
    final alt = (img.attributes['alt'] ?? '').toLowerCase();
    final combined = '$className $id $alt $src'.toLowerCase();

    // Check for ad-related keywords
    final adKeywords = [
      'ad', 'advertisement', 'banner', 'promo', 'sponsored',
      'widget', 'sidebar', 'related', 'recommended'
    ];

    for (final keyword in adKeywords) {
      if (combined.contains(keyword)) {
        debugPrint('🚫 Skipping ad image: $src (contains: $keyword)');
        return true;
      }
    }

    // Check parent elements
    var parent = img.parent;
    for (var i = 0; i < 3 && parent != null; i++) {
      final parentClass = (parent.attributes['class'] ?? '').toLowerCase();
      final parentId = (parent.attributes['id'] ?? '').toLowerCase();
      final parentCombined = '$parentClass $parentId';

      for (final keyword in adKeywords) {
        if (parentCombined.contains(keyword)) {
          debugPrint('🚫 Skipping ad image: $src (parent contains: $keyword)');
          return true;
        }
      }
      parent = parent.parent;
    }

    return false;
  }

  Future<Uint8List?> _downloadImage(String imageUrl) async {
    try {
      debugPrint('⬇️ Downloading image: $imageUrl');
      final response = await http.get(
        Uri.parse(imageUrl),
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
          'Accept': 'image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8',
        },
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final bytes = response.bodyBytes;
        debugPrint('✅ Image downloaded: ${bytes.length} bytes');
        return bytes;
      } else {
        debugPrint('❌ Failed to download image: HTTP ${response.statusCode}');
        return null;
      }
    } catch (e) {
      debugPrint('❌ Error downloading image: $e');
      return null;
    }
  }
}

