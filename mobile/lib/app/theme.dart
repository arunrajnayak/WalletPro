import 'package:flutter/material.dart';

class AppTheme {
  static const _seedColor = Color(0xFF4F46E5); // Indigo
  static const _secondaryColor = Color(0xFF0EA5E9); // Sky / Teal

  static final _colorSchemeLight = ColorScheme.fromSeed(
    seedColor: _seedColor,
    secondary: _secondaryColor,
    brightness: Brightness.light,
    surface: const Color(0xFFFFFFFF),
    surfaceContainerHighest: const Color(0xFFF1F5F9), // Slate 100
  );

  static final _colorSchemeDark = ColorScheme.fromSeed(
    seedColor: _seedColor,
    secondary: _secondaryColor,
    brightness: Brightness.dark,
    surface: const Color(0xFF0F172A), // Slate 900
    surfaceContainerHighest: const Color(0xFF1E293B), // Slate 800
  );

  static ThemeData get lightTheme => ThemeData(
        useMaterial3: true,
        colorScheme: _colorSchemeLight,
        scaffoldBackgroundColor: const Color(0xFFF8FAFC), // Slate 50
        cardTheme: CardThemeData(
          elevation: 0,
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: Color(0xFFE2E8F0)), // Slate 200
          ),
        ),
        appBarTheme: const AppBarTheme(
          elevation: 0,
          scrolledUnderElevation: 1,
          backgroundColor: Color(0xFFF8FAFC),
          centerTitle: false,
          titleTextStyle: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Color(0xFF0F172A),
          ),
        ),
        navigationBarTheme: NavigationBarThemeData(
          height: 66,
          elevation: 0,
          backgroundColor: Colors.white,
          indicatorColor: const Color(0xFFE0E7FF), // Indigo 100
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          labelTextStyle: WidgetStateProperty.resolveWith((states) {
            final isSelected = states.contains(WidgetState.selected);
            return TextStyle(
              fontSize: 12,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              color: isSelected ? const Color(0xFF4338CA) : const Color(0xFF64748B),
            );
          }),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            minimumSize: const Size(0, 48),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, 48),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5),
          ),
        ),
      );

  static ThemeData get darkTheme => ThemeData(
        useMaterial3: true,
        colorScheme: _colorSchemeDark,
        scaffoldBackgroundColor: const Color(0xFF090D16),
        cardTheme: CardThemeData(
          elevation: 0,
          color: const Color(0xFF0F172A),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: Color(0xFF1E293B)),
          ),
        ),
        appBarTheme: const AppBarTheme(
          elevation: 0,
          scrolledUnderElevation: 1,
          backgroundColor: Color(0xFF090D16),
          centerTitle: false,
          titleTextStyle: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        navigationBarTheme: NavigationBarThemeData(
          height: 66,
          elevation: 0,
          backgroundColor: const Color(0xFF0F172A),
          indicatorColor: const Color(0xFF312E81), // Dark indigo
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          labelTextStyle: WidgetStateProperty.resolveWith((states) {
            final isSelected = states.contains(WidgetState.selected);
            return TextStyle(
              fontSize: 12,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              color: isSelected ? const Color(0xFF818CF8) : const Color(0xFF94A3B8),
            );
          }),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            minimumSize: const Size(0, 48),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, 48),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5),
          ),
        ),
      );
}
