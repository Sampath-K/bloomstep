import 'package:flutter/material.dart';

class BloomstepTheme {
  static const seed = Color(0xFF3E8E5E);

  static ThemeData light() => ThemeData(
    colorScheme: ColorScheme.fromSeed(seedColor: seed),
    fontFamily: 'Segoe UI',
    useMaterial3: true,
  );

  static ThemeData dark() => ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.dark,
    ),
    fontFamily: 'Segoe UI',
    useMaterial3: true,
  );
}
