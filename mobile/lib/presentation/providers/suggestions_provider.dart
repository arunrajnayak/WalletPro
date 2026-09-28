import 'package:flutter_riverpod/flutter_riverpod.dart';

class PendingSuggestionsNotifier extends StateNotifier<List<dynamic>> {
  PendingSuggestionsNotifier() : super([]);

  /// Sets the pending suggestions list
  void setSuggestions(List<dynamic> suggestions) {
    state = List<dynamic>.from(suggestions);
  }

  /// Optimistically removes a suggestion by ID (used on approve / reject)
  void removeSuggestion(String id) {
    state = state.where((item) => item['id'] != id).toList();
  }

  /// Optimistically inserts a suggestion (used on undo or when new SMS detected)
  void insertSuggestion(dynamic item, {int index = 0}) {
    final list = List<dynamic>.from(state);
    if (index >= 0 && index <= list.length) {
      list.insert(index, item);
    } else {
      list.insert(0, item);
    }
    state = list;
  }

  /// Optimistically updates a suggestion by ID
  void updateSuggestion(String id, Map<String, dynamic> updates) {
    state = [
      for (final item in state)
        if (item['id'] == id)
          {...(item as Map<String, dynamic>), ...updates}
        else
          item
    ];
  }
}

final pendingSuggestionsProvider =
    StateNotifierProvider<PendingSuggestionsNotifier, List<dynamic>>((ref) {
  return PendingSuggestionsNotifier();
});
