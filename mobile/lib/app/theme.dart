import 'package:flutter/material.dart';

class AppTheme {
  static final _colorSchemeLight = ColorScheme.fromSeed(
    seedColor: Colors.indigo,
    secondary: Colors.teal,
    brightness: Brightness.light,
  );

  static final _colorSchemeDark = ColorScheme.fromSeed(
    seedColor: Colors.indigo,
    secondary: Colors.teal,
    brightness: Brightness.dark,
  );

  static ThemeData get lightTheme => ThemeData(
        useMaterial3: true,
        colorScheme: _colorSchemeLight,
        cardTheme: CardThemeData(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      );

  static ThemeData get darkTheme => ThemeData(
        useMaterial3: true,
        colorScheme: _colorSchemeDark,
        cardTheme: CardThemeData(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      );
}
