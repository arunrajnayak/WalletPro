import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/datasources/local/local_cache.dart';

class ThemeModeNotifier extends StateNotifier<ThemeMode> {
  static const String _storageKey = 'app_theme_mode';

  ThemeModeNotifier() : super(_initialMode());

  static ThemeMode _initialMode() {
    final saved = LocalCache.getString(_storageKey);
    if (saved == 'dark') return ThemeMode.dark;
    if (saved == 'light') return ThemeMode.light;
    return ThemeMode.system;
  }

  void setThemeMode(ThemeMode mode) {
    state = mode;
    final value = mode == ThemeMode.dark
        ? 'dark'
        : (mode == ThemeMode.light ? 'light' : 'system');
    LocalCache.setString(_storageKey, value);
  }
}

final themeModeProvider = StateNotifierProvider<ThemeModeNotifier, ThemeMode>((ref) {
  return ThemeModeNotifier();
});
