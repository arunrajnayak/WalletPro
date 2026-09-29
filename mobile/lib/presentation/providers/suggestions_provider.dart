import 'package:flutter_riverpod/flutter_riverpod.dart';

class PendingSuggestionsNotifier extends StateNotifier<List<dynamic>> {
  PendingSuggestionsNotifier() : super([]);

  static DateTime _parseDate(dynamic item) {
    if (item is Map) {
      final rawDate = item['transactionDate'] ?? item['createdAt'] ?? item['actionedAt'];
      if (rawDate != null) {
        final parsed = DateTime.tryParse(rawDate.toString());
        if (parsed != null) return parsed;
      }
    }
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  static List<dynamic> sortByDateTime(List<dynamic> items) {
    final list = List<dynamic>.from(items);
    list.sort((a, b) {
      final dateA = _parseDate(a);
      final dateB = _parseDate(b);
      return dateB.compareTo(dateA); // Newest / most recent first
    });
    return list;
  }

  /// Sets the pending suggestions list
  void setSuggestions(List<dynamic> suggestions) {
    state = sortByDateTime(suggestions);
  }

  /// Optimistically removes a suggestion by ID (used on approve / reject)
  void removeSuggestion(String id) {
    state = state.where((item) => item['id'] != id).toList();
  }

  /// Optimistically inserts a suggestion (used on undo or when new SMS detected)
  void insertSuggestion(dynamic item, {int index = 0}) {
    final list = List<dynamic>.from(state);
    list.add(item);
    state = sortByDateTime(list);
  }

  /// Optimistically updates a suggestion by ID
  void updateSuggestion(String id, Map<String, dynamic> updates) {
    final updated = [
      for (final item in state)
        if (item['id'] == id)
          {...(item as Map<String, dynamic>), ...updates}
        else
          item
    ];
    state = sortByDateTime(updated);
  }
}

final pendingSuggestionsProvider =
    StateNotifierProvider<PendingSuggestionsNotifier, List<dynamic>>((ref) {
  return PendingSuggestionsNotifier();
});
