import 'package:flutter/material.dart';

/// Same palette as the web panel: green as the brand, soft tones for states.
abstract final class AppColors {
  static const brand = Color(0xFF188365);
  static const ink = Color(0xFF1C2421);
  static const muted = Color(0xFF5F6B66);
  static const surface = Color(0xFFF7F8F6);
  static const amber = Color(0xFFD98A00);
  static const danger = Color(0xFFC2410C);
}

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(seedColor: AppColors.brand, primary: AppColors.brand, surface: Colors.white);

  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    scaffoldBackgroundColor: AppColors.surface,
    appBarTheme: const AppBarTheme(backgroundColor: AppColors.surface, foregroundColor: AppColors.ink, elevation: 0, centerTitle: false),
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Color(0xFFE7E5E4))),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
    ),
  );
}
