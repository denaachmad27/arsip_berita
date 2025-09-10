import 'dart:ui';
import 'package:flutter/material.dart';
import '../ui/palette.dart';

class BackgroundBlobs extends StatelessWidget {
  const BackgroundBlobs({super.key});
  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.bgStart, AppColors.bgEnd],
          ),
        ),
      ),
      // blobs
      Positioned(
        top: -80,
        left: -60,
        child: _Blob(color: AppColors.heroGradient[0], size: 220),
      ),
      Positioned(
        top: 100,
        right: -40,
        child: _Blob(color: AppColors.heroGradient[1], size: 180),
      ),
      Positioned(
        bottom: -60,
        left: 40,
        child: _Blob(color: AppColors.heroGradient[2], size: 220),
      ),
      // subtle global blur
      Positioned.fill(
        child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20), child: Container(color: Colors.transparent)),
      ),
    ]);
  }
}

class _Blob extends StatelessWidget {
  final Color color; final double size;
  const _Blob({required this.color, required this.size});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: size, height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
      ),
    );
  }
}

