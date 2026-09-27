import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Robust local key-value and JSON caching layer backed by SharedPreferences
class LocalCache {
  static SharedPreferences? _prefs;

  /// Ensure SharedPreferences is initialized
  static Future<SharedPreferences> get _instance async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }

  /// Initialize during app startup
  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  /// Save raw string
  static Future<bool> setString(String key, String value) async {
    try {
      final p = await _instance;
      return await p.setString(key, value);
    } catch (_) {
      return false;
    }
  }

  /// Get raw string
  static String? getString(String key) {
    return _prefs?.getString(key);
  }

  /// Get raw string with async fallback
  static Future<String?> getStringAsync(String key) async {
    try {
      final p = await _instance;
      return p.getString(key);
    } catch (_) {
      return null;
    }
  }

  /// Save JSON-serializable object (Map, List, num, etc.)
  static Future<bool> setJson(String key, dynamic value) async {
    try {
      final jsonStr = jsonEncode(value);
      final p = await _instance;
      return await p.setString(key, jsonStr);
    } catch (_) {
      return false;
    }
  }

  /// Retrieve JSON-deserialized object
  static dynamic getJson(String key) {
    try {
      final str = _prefs?.getString(key);
      if (str == null || str.isEmpty) return null;
      return jsonDecode(str);
    } catch (_) {
      return null;
    }
  }

  /// Retrieve JSON-deserialized object with async fallback
  static Future<dynamic> getJsonAsync(String key) async {
    try {
      final p = await _instance;
      final str = p.getString(key);
      if (str == null || str.isEmpty) return null;
      return jsonDecode(str);
    } catch (_) {
      return null;
    }
  }

  /// Remove specific key
  static Future<bool> remove(String key) async {
    try {
      final p = await _instance;
      return await p.remove(key);
    } catch (_) {
      return false;
    }
  }

  /// Clear all cached data
  static Future<bool> clear() async {
    try {
      final p = await _instance;
      return await p.clear();
    } catch (_) {
      return false;
    }
  }
}
