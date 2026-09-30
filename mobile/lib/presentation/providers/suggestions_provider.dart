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

  static String _itemSignature(dynamic item) {
    if (item is! Map) return item.toString();
    final id = item['id']?.toString() ?? '';
    final sourceId = item['sourceId']?.toString() ?? '';
    final ref = item['referenceNumber']?.toString().trim() ?? '';
    final rawText = (item['rawText'] ?? '').toString().replaceAll(RegExp(r'\s+'), ' ').trim().toLowerCase();
    final amount = (item['amount'] as num?)?.toDouble().toStringAsFixed(2) ?? item['amount']?.toString() ?? '';
    final date = _parseDate(item);
    final dateKey = '${date.year}-${date.month}-${date.day}';

    // If sourceId is available, it represents the unique SMS or notification id
    if (sourceId.isNotEmpty) {
      return 'src:$sourceId';
    }
    // If referenceNumber is available, amount + ref is uniquely identifying
    if (ref.isNotEmpty) {
      return 'ref:$amount:$ref';
    }
    // If rawText is available, amount + normalized text represents the identical transaction
    if (rawText.isNotEmpty) {
      return 'txt:$amount:$rawText';
    }
    // Fallback to amount + dateKey + accountLast4 + id
    final last4 = (item['accountLast4'] ?? '').toString().trim();
    return 'fallback:$amount:$dateKey:$last4:$id';
  }

  /// Deduplicates items by unique id and transaction signature
  static List<dynamic> deduplicate(List<dynamic> items) {
    final seenIds = <String>{};
    final seenSignatures = <String>{};
    final deduped = <dynamic>[];

    for (final item in items) {
      if (item is! Map) continue;
      final id = item['id']?.toString();
      if (id != null && id.isNotEmpty) {
        if (seenIds.contains(id)) continue;
        seenIds.add(id);
      }

      final sig = _itemSignature(item);
      if (seenSignatures.contains(sig)) continue;
      seenSignatures.add(sig);

      deduped.add(item);
    }
    return deduped;
  }

  static List<dynamic> sortByDateTime(List<dynamic> items) {
    final list = deduplicate(items);
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

  /// When account mappings change, re-match all pending suggestions in memory
  void refreshAccountMappings(List<dynamic> accounts) {
    if (state.isEmpty) return;
    final updated = state.map((item) {
      if (item is! Map) return item;
      final map = Map<String, dynamic>.from(item);
      final rawLast4 = (map['accountLast4'] ?? '').toString().trim();
      if (rawLast4.isEmpty || rawLast4.toUpperCase() == 'NONE') return map;

      // Find matching account by last 4 digits
      dynamic matchedAccount;
      for (final acc in accounts) {
        if (acc is! Map) continue;
        final last4Digits = (acc['last4Digits'] ?? '').toString().trim();
        if (last4Digits.isEmpty || last4Digits.toUpperCase() == 'NONE') continue;
        final digitsList = last4Digits.split(RegExp(r'[,;\s]+')).map((s) => s.trim()).toList();
        if (digitsList.contains(rawLast4) || last4Digits == rawLast4) {
          matchedAccount = acc;
          break;
        }
      }

      if (matchedAccount != null) {
        map['walletAccountId'] = matchedAccount['walletAccountId'] ?? matchedAccount['id'];
        map['walletAccountName'] = matchedAccount['name'];
      }
      return map;
    }).toList();
    state = sortByDateTime(updated);
  }
}

final pendingSuggestionsProvider =
    StateNotifierProvider<PendingSuggestionsNotifier, List<dynamic>>((ref) {
  return PendingSuggestionsNotifier();
});
