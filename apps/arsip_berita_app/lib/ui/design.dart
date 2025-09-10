import 'package:flutter/material.dart';

class DS {
  // Futuristic, serious palette (can be updated by ThemeLoader)
  static Color bg = const Color(0xFFF4F6F8);
  static Color surface = const Color(0xFFFCFCFD);
  static Color surface2 = const Color(0xFFF6F7F9);
  static Color border = const Color(0xFFE5E7EB);
  static Color text = const Color(0xFF0F172A);
  static Color textDim = const Color(0xFF475569);
  static Color accent = const Color(0xFF1E3A8A); // deep indigo
  static Color accent2 = const Color(0xFF0EA5E9); // sky blue
  static Color accentLite = const Color(0x331E3A8A);
  static Color accent2Lite = const Color(0x330EA5E9);
  static Color danger = const Color(0xFFB91C1C);

  static const EdgeInsets contentPad = EdgeInsets.symmetric(horizontal: 18, vertical: 14);
  static const Radius radius = Radius.circular(12);
  static BorderRadius get br => BorderRadius.circular(12);
}