import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../ui/design.dart';

class QuoteImagePage extends StatefulWidget {
  final String imageUrl;
  final String quoteText;

  const QuoteImagePage({
    super.key,
    required this.imageUrl,
    required this.quoteText,
  });

  @override
  State<QuoteImagePage> createState() => _QuoteImagePageState();
}

class _QuoteImagePageState extends State<QuoteImagePage> {
  bool _downloading = false;
  String? _savedPath;

  /// Check if the imageUrl is a data URI (base64)
  bool get _isDataUri => widget.imageUrl.startsWith('data:');

  /// Decode base64 data URI to bytes
  Uint8List? _decodeDataUri() {
    if (!_isDataUri) return null;

    try {
      // Extract base64 string from data URI
      // Format: data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAA...
      final base64String = widget.imageUrl.split(',')[1];
      return base64Decode(base64String);
    } catch (e) {
      // Error decoding data URI
      return null;
    }
  }

  /// Build image widget based on URL type (data URI or HTTP URL)
  Widget _buildImage() {
    if (_isDataUri) {
      // Handle data URI (base64 encoded image from Gemini)
      final imageBytes = _decodeDataUri();
      if (imageBytes == null) {
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 48, color: DS.textDim),
              const SizedBox(height: 16),
              Text(
                'Failed to decode image data',
                style: TextStyle(color: DS.textDim),
              ),
            ],
          ),
        );
      }

      return Image.memory(
        imageBytes,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, size: 48, color: DS.textDim),
                const SizedBox(height: 16),
                Text(
                  'Failed to load image',
                  style: TextStyle(color: DS.textDim),
                ),
              ],
            ),
          );
        },
      );
    } else {
      // Handle HTTP/HTTPS URL (from OpenAI DALL-E)
      return Image.network(
        widget.imageUrl,
        fit: BoxFit.contain,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(
                  value: loadingProgress.expectedTotalBytes != null
                      ? loadingProgress.cumulativeBytesLoaded /
                          loadingProgress.expectedTotalBytes!
                      : null,
                  color: DS.accent,
                ),
                const SizedBox(height: 16),
                Text(
                  'Loading image...',
                  style: TextStyle(color: DS.textDim),
                ),
              ],
            ),
          );
        },
        errorBuilder: (context, error, stackTrace) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, size: 48, color: DS.textDim),
                const SizedBox(height: 16),
                Text(
                  'Failed to load image',
                  style: TextStyle(color: DS.textDim),
                ),
              ],
            ),
          );
        },
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Quote Post'),
        backgroundColor: DS.surface,
        foregroundColor: DS.text,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.download),
            onPressed: _downloading ? null : _downloadImage,
            tooltip: 'Download Image',
          ),
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: _downloading ? null : _shareImage,
            tooltip: 'Share',
          ),
        ],
      ),
      body: Container(
        color: DS.bg,
        child: Column(
          children: [
            // Quote text preview
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              margin: const EdgeInsets.all(16),
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
                      Icon(Icons.format_quote, color: DS.accent, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'Selected Quote',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: DS.accent,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.quoteText,
                    style: TextStyle(
                      fontSize: 13,
                      color: DS.textDim,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),

            // Generated image
            Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: DS.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: DS.border),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: InteractiveViewer(
                    minScale: 0.5,
                    maxScale: 4.0,
                    child: Center(
                      child: _buildImage(),
                    ),
                  ),
                ),
              ),
            ),

            // Action buttons
            if (_downloading)
              Container(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: DS.accent,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Processing...',
                      style: TextStyle(color: DS.textDim),
                    ),
                  ],
                ),
              )
            else if (_savedPath != null)
              Container(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.check_circle, color: DS.accent, size: 20),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'Saved to: $_savedPath',
                        style: TextStyle(
                          color: DS.accent,
                          fontSize: 12,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              )
            else
              const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Future<void> _downloadImage() async {
    setState(() {
      _downloading = true;
      _savedPath = null;
    });

    try {
      Uint8List imageBytes;

      if (_isDataUri) {
        // Decode data URI directly
        final decoded = _decodeDataUri();
        if (decoded == null) {
          throw Exception('Failed to decode image data');
        }
        imageBytes = decoded;
      } else {
        // Download image from URL
        final response = await http.get(Uri.parse(widget.imageUrl));
        if (response.statusCode != 200) {
          throw Exception('Failed to download image');
        }
        imageBytes = response.bodyBytes;
      }

      // Get downloads directory
      final Directory? directory = await getDownloadsDirectory();
      if (directory == null) {
        throw Exception('Could not access downloads directory');
      }

      // Create unique filename
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = 'quote_post_$timestamp.png';
      final filePath = '${directory.path}/$fileName';

      // Save image
      final file = File(filePath);
      await file.writeAsBytes(imageBytes);

      if (mounted) {
        setState(() {
          _savedPath = filePath;
          _downloading = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Image downloaded successfully'),
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
        setState(() {
          _downloading = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to download: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _shareImage() async {
    setState(() {
      _downloading = true;
    });

    try {
      Uint8List imageBytes;

      if (_isDataUri) {
        // Decode data URI directly
        final decoded = _decodeDataUri();
        if (decoded == null) {
          throw Exception('Failed to decode image data');
        }
        imageBytes = decoded;
      } else {
        // Download image from URL
        final response = await http.get(Uri.parse(widget.imageUrl));
        if (response.statusCode != 200) {
          throw Exception('Failed to download image');
        }
        imageBytes = response.bodyBytes;
      }

      // Get temporary directory
      final directory = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = 'quote_post_$timestamp.png';
      final filePath = '${directory.path}/$fileName';

      // Save image temporarily
      final file = File(filePath);
      await file.writeAsBytes(imageBytes);

      // Share the image
      await Share.shareXFiles(
        [XFile(filePath)],
        text: 'Quote: ${widget.quoteText}',
        subject: 'Quote Post',
      );

      if (mounted) {
        setState(() {
          _downloading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _downloading = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to share: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}
