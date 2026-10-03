import 'package:flutter/material.dart';

abstract final class AppTheme {
  static ThemeData get light {
    const seedColor = Color(0xFF176B45);
    const ink = Color(0xFF14221B);
    const muted = Color(0xFF68776F);
    const canvas = Color(0xFFF4F7F4);

    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: seedColor,
        brightness: Brightness.light,
      ),
      scaffoldBackgroundColor: canvas,
      visualDensity: VisualDensity.standard,
      fontFamily: 'Segoe UI',
      textTheme: const TextTheme(
        headlineLarge: TextStyle(color: ink, fontWeight: FontWeight.w700, letterSpacing: -0.6),
        headlineMedium: TextStyle(color: ink, fontWeight: FontWeight.w700, letterSpacing: -0.4),
        headlineSmall: TextStyle(color: ink, fontWeight: FontWeight.w700),
        titleLarge: TextStyle(color: ink, fontWeight: FontWeight.w700),
        titleMedium: TextStyle(color: ink, fontWeight: FontWeight.w600),
        bodyLarge: TextStyle(color: ink),
        bodyMedium: TextStyle(color: muted),
        bodySmall: TextStyle(color: muted),
      ),
      appBarTheme: const AppBarTheme(
        centerTitle: false,
        backgroundColor: canvas,
        foregroundColor: ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        toolbarHeight: 72,
      ),
      cardTheme: const CardThemeData(
        margin: EdgeInsets.zero,
        elevation: 1,
        shadowColor: Color(0x140F2D1F),
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(14)),
        ),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(10)), borderSide: BorderSide(color: Color(0xFFD9E2DC))),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(10)), borderSide: BorderSide(color: Color(0xFFD9E2DC))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(10)), borderSide: BorderSide(color: seedColor, width: 1.4)),
        filled: true,
        fillColor: Colors.white,
        contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        prefixIconColor: seedColor,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 52),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(9))),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 52),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(9))),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        contentTextStyle: TextStyle(fontSize: 15),
      ),
    );
  }
}
