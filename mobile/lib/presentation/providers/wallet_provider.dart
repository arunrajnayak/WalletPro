import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/utils/account_sorter.dart';
import '../../core/utils/stats_parser.dart';

class WalletAccountsNotifier extends StateNotifier<List<dynamic>> {
  WalletAccountsNotifier() : super([]);

  /// Sets accounts list, merging with existing accounts so that balances,
  /// colors, and mappings are preserved if the incoming list has partial data.
  void setAccounts(List<dynamic> accounts) {
    if (state.isEmpty) {
      final list = List<dynamic>.from(accounts);
      AccountSorter.sortAccounts(list);
      state = list;
      return;
    }

    // Build a map of existing accounts by id and walletAccountId
    final existingMap = <String, Map<String, dynamic>>{};
    for (final item in state) {
      if (item is Map) {
        final id = (item['id'] ?? item['walletAccountId'])?.toString();
        if (id != null) {
          existingMap[id] = Map<String, dynamic>.from(item);
        }
        final wId = item['walletAccountId']?.toString();
        if (wId != null) {
          existingMap[wId] = Map<String, dynamic>.from(item);
        }
        final name = (item['name'] ?? '').toString().trim().toLowerCase();
        if (name.isNotEmpty) {
          existingMap['name_$name'] = Map<String, dynamic>.from(item);
        }
      }
    }

    final mergedList = <dynamic>[];
    for (final item in accounts) {
      if (item is Map) {
        final mapItem = Map<String, dynamic>.from(item);
        final id = (mapItem['id'] ?? mapItem['walletAccountId'])?.toString();
        final name = (mapItem['name'] ?? '').toString().trim().toLowerCase();
        final existing = (id != null ? existingMap[id] : null) ??
            (name.isNotEmpty ? existingMap['name_$name'] : null);

        if (existing != null) {
          // If incoming balance is missing or null, preserve existing balance!
          if (mapItem['balance'] == null && existing['balance'] != null) {
            mapItem['balance'] = existing['balance'];
          }
          // If incoming color is missing or null/empty, preserve existing color!
          if ((mapItem['color'] == null || mapItem['color'].toString().trim().isEmpty) &&
              existing['color'] != null) {
            mapItem['color'] = existing['color'];
          }
          // Preserve last4Digits if missing in incoming
          if (mapItem['last4Digits'] == null && existing['last4Digits'] != null) {
            mapItem['last4Digits'] = existing['last4Digits'];
          }
        }
        mergedList.add(mapItem);
      } else {
        mergedList.add(item);
      }
    }

    AccountSorter.sortAccounts(mergedList);
    state = mergedList;
  }

  /// Optimistically adjust balance for an account (e.g. after transaction approval)
  void adjustAccountBalance(String accountId, double amountDelta) {
    state = [
      for (final a in state)
        if (a is Map && (a['id']?.toString() == accountId || a['walletAccountId']?.toString() == accountId))
          Map<String, dynamic>.from(a)
            ..['balance'] = parseDouble(a['balance']) + amountDelta
        else
          a
    ];
  }

  /// Optimistically updates the last4Digits mapping for an account
  void updateMapping(String id, String? last4Digits) {
    state = [
      for (final a in state)
        if (a['id'] == id || a['walletAccountId'] == id)
          Map<String, dynamic>.from(a as Map<String, dynamic>)..['last4Digits'] = last4Digits
        else
          a
    ];
  }

  /// Optimistically reorders the accounts list
  void reorder(List<String> orderIds) {
    final list = List<dynamic>.from(state);
    AccountSorter.sortAccounts(list, customOrder: orderIds);
    state = list;
  }
}

final walletAccountsProvider =
    StateNotifierProvider<WalletAccountsNotifier, List<dynamic>>((ref) {
  return WalletAccountsNotifier();
});

/// Trigger to tell the Dashboard screen to re-fetch live data when coming back from other tabs
final dashboardRefreshTriggerProvider = StateProvider<int>((ref) => 0);

class WalletCategoriesNotifier extends StateNotifier<List<dynamic>> {
  WalletCategoriesNotifier() : super([]);

  void setCategories(List<dynamic> categories) {
    state = List<dynamic>.from(categories);
  }
}

final walletCategoriesProvider =
    StateNotifierProvider<WalletCategoriesNotifier, List<dynamic>>((ref) {
  return WalletCategoriesNotifier();
});
