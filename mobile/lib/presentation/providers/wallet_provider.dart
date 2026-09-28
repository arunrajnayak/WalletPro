import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/utils/account_sorter.dart';

class WalletAccountsNotifier extends StateNotifier<List<dynamic>> {
  WalletAccountsNotifier() : super([]);

  /// Sets accounts list, sorting them according to account order
  void setAccounts(List<dynamic> accounts) {
    final list = List<dynamic>.from(accounts);
    AccountSorter.sortAccounts(list);
    state = list;
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
