import 'package:flutter/material.dart';

class BatiProTheme {
  static const ink = Color(0xFF172B3B);
  static const inkSoft = Color(0xFF233F52);
  static const gold = Color(0xFFE5A43A);
  static const canvas = Color(0xFFF4F6F8);
  static const muted = Color(0xFF718096);
  static const line = Color(0xFFE7ECF0);
  static const green = Color(0xFF18866A);
  static const red = Color(0xFFD85B55);
  static const blue = Color(0xFF477DB5);

  static ThemeData get light {
    final scheme = ColorScheme.fromSeed(
      seedColor: ink,
      brightness: Brightness.light,
      primary: ink,
      secondary: gold,
      surface: Colors.white,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: canvas,
      fontFamily: 'Arial',
      appBarTheme: const AppBarTheme(
        backgroundColor: canvas,
        foregroundColor: ink,
        elevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: line),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFF7F9FA),
        hintStyle: const TextStyle(color: muted, fontSize: 13),
        prefixIconColor: muted,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: ink, width: 1.4),
        ),
      ),
    );
  }
}
