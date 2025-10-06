import 'package:flutter/material.dart';

class ImagePreview extends StatefulWidget {
  final ImageProvider imageProvider;
  final String? heroTag;

  const ImagePreview({
    super.key,
    required this.imageProvider,
    this.heroTag,
  });

  static Future<void> show(
    BuildContext context, {
    required ImageProvider imageProvider,
    String? heroTag,
  }) {
    return Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black87,
        pageBuilder: (context, animation, secondaryAnimation) {
          return ImagePreview(
            imageProvider: imageProvider,
            heroTag: heroTag,
          );
        },
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: animation,
            child: child,
          );
        },
      ),
    );
  }

  @override
  State<ImagePreview> createState() => _ImagePreviewState();
}

class _ImagePreviewState extends State<ImagePreview>
    with SingleTickerProviderStateMixin {
  late TransformationController _transformationController;
  late AnimationController _animationController;
  Animation<Matrix4>? _animation;

  @override
  void initState() {
    super.initState();
    _transformationController = TransformationController();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
  }

  @override
  void dispose() {
    _transformationController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  void _onInteractionEnd(ScaleEndDetails details) {
    // Check current scale from transformation matrix
    final scale = _transformationController.value.getMaxScaleOnAxis();
    if (scale < 1.0) {
      _resetAnimation();
    }
  }

  void _resetAnimation() {
    _animation = Matrix4Tween(
      begin: _transformationController.value,
      end: Matrix4.identity(),
    ).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeOut,
      ),
    );

    _animationController.forward(from: 0).then((_) {
      _animation?.removeListener(_onAnimationUpdate);
      _animation = null;
      _animationController.reset();
    });

    _animation!.addListener(_onAnimationUpdate);
  }

  void _onAnimationUpdate() {
    _transformationController.value = _animation!.value;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black87,
      body: Stack(
        children: [
          // Zoomable image - full screen
          GestureDetector(
            onTap: () {
              // Only close if not zoomed
              final scale = _transformationController.value.getMaxScaleOnAxis();
              if (scale <= 1.0) {
                Navigator.of(context).pop();
              }
            },
            child: InteractiveViewer(
              transformationController: _transformationController,
              minScale: 0.5,
              maxScale: 4.0,
              onInteractionEnd: _onInteractionEnd,
              boundaryMargin: const EdgeInsets.all(double.infinity),
              child: SizedBox.expand(
                child: widget.heroTag != null
                    ? Hero(
                        tag: widget.heroTag!,
                        child: Image(
                          image: widget.imageProvider,
                          fit: BoxFit.contain,
                        ),
                      )
                    : Image(
                        image: widget.imageProvider,
                        fit: BoxFit.contain,
                      ),
              ),
            ),
          ),

          // Close button
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            right: 8,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => Navigator.of(context).pop(),
                borderRadius: BorderRadius.circular(24),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.5),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.3),
                      width: 1,
                    ),
                  ),
                  child: const Icon(
                    Icons.close,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
              ),
            ),
          ),

          // Zoom hint
          Positioned(
            bottom: MediaQuery.of(context).padding.bottom + 24,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.2),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.pinch_outlined,
                      color: Colors.white.withValues(alpha: 0.9),
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Pinch to zoom',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.9),
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
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
}
