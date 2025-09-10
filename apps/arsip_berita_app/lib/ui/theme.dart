import 'package:flutter/material.dart';
import 'palette.dart';
import 'design.dart';

class AppTheme {
  static ThemeData build() {
    final base = ThemeData(useMaterial3: true, colorSchemeSeed: DS.accent);
    return base.copyWith(
      visualDensity: VisualDensity.standard,
      scaffoldBackgroundColor: DS.bg,
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.all(DS.radius)),
        filled: true,
        fillColor: DS.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      ),
      cardTheme: CardThemeData(
        margin: EdgeInsets.zero,
        elevation: 0,
        color: DS.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(DS.radius)),
      ),
      listTileTheme: const ListTileThemeData(contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 6)),
      iconTheme: IconThemeData(color: DS.textDim),
      textTheme: base.textTheme.apply(
        displayColor: DS.text,
        bodyColor: DS.textDim,
      ).copyWith(
        titleLarge: base.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.3),
        titleMedium: base.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        bodyLarge: base.textTheme.bodyLarge?.copyWith(height: 1.4),
        bodyMedium: base.textTheme.bodyMedium?.copyWith(height: 1.4),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(DS.radius)),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          elevation: 0,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: DS.accent,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(DS.radius)),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          elevation: 0,
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        labelStyle: base.textTheme.bodyMedium,
        side: BorderSide(color: DS.border),
      ),
    );
  }
}

class Spacing {
  static const double xs = 6;
  static const double sm = 10;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;
}
