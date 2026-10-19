import 'package:flutter/material.dart';

class BudlarkTheme {
  static const canvas = Color(0xFFF7F4EF);
  static const lightSurface = Color(0xFFFFFFFF);
  static const lightText = Color(0xFF242424);
  static const lightMutedText = Color(0xFF5C5C5C);
  static const lightPrimary = Color(0xFF2F6F4E);
  static const darkCanvas = Color(0xFF1E2A22);
  static const darkSurface = Color(0xFF252B27);
  static const darkText = Color(0xFFF2F4F0);
  static const darkMutedText = Color(0xFFBEC8C0);
  static const darkPrimary = Color(0xFF84C69A);

  static ThemeData light() => ThemeData(
    colorScheme:
        ColorScheme.fromSeed(
          seedColor: lightPrimary,
          brightness: Brightness.light,
        ).copyWith(
          primary: lightPrimary,
          onPrimary: lightSurface,
          surface: lightSurface,
          onSurface: lightText,
          onSurfaceVariant: lightMutedText,
        ),
    scaffoldBackgroundColor: canvas,
    fontFamily: 'Segoe UI',
    useMaterial3: true,
  );

  static ThemeData dark() => ThemeData(
    colorScheme:
        ColorScheme.fromSeed(
          seedColor: darkPrimary,
          brightness: Brightness.dark,
        ).copyWith(
          primary: darkPrimary,
          onPrimary: darkCanvas,
          surface: darkSurface,
          onSurface: darkText,
          onSurfaceVariant: darkMutedText,
        ),
    scaffoldBackgroundColor: darkCanvas,
    fontFamily: 'Segoe UI',
    useMaterial3: true,
  );
}
