class AccountSorter {
  /// Default ordering matching BudgetBakers app layout
  static const List<String> defaultAccountOrder = [
    'HDFC sb',
    'SBI sb',
    'Cash',
    'Mutual funds',
    'Zerodha',
    'NPS',
    'Upstox',
    'EPF',
    'Amazon Pay',
    'Flipkart GC',
    'SBI cashback',
    'Tata Neu',
    'HSBC Live+',
    'Axis Flipkart',
    'Swiggy HDFC',
    'Jupiter Edge',
    'Cred indusind',
    'Amazon ICICI',
    'Ola SBI',
    'IDFC wealth',
    'Axis Rewards',
    'PhonePe',
    'Fastag',
    'Axis forex',
    'LIC',
    'ICICI platinum',
  ];

  /// Sorts a mutable list of account maps in-place according to the default order
  static void sortAccounts(List<dynamic> accounts, {List<String>? customOrder}) {
    final order = (customOrder != null && customOrder.isNotEmpty) ? customOrder : defaultAccountOrder;

    accounts.sort((a, b) {
      final nameA = (a['name'] ?? '').toString().trim().toLowerCase();
      final nameB = (b['name'] ?? '').toString().trim().toLowerCase();
      final idA = (a['walletAccountId'] ?? a['id'] ?? '').toString();
      final idB = (b['walletAccountId'] ?? b['id'] ?? '').toString();

      // Check by ID first if present in customOrder
      final idIdxA = order.indexOf(idA);
      final idIdxB = order.indexOf(idB);
      if (idIdxA != -1 && idIdxB != -1) return idIdxA - idIdxB;
      if (idIdxA != -1) return -1;
      if (idIdxB != -1) return 1;

      // Check by normalized Name
      final idxA = order.indexWhere((n) => n.trim().toLowerCase() == nameA);
      final idxB = order.indexWhere((n) => n.trim().toLowerCase() == nameB);
      if (idxA != -1 && idxB != -1) return idxA - idxB;
      if (idxA != -1) return -1;
      if (idxB != -1) return 1;

      return nameA.compareTo(nameB);
    });
  }

  /// Returns a new sorted list
  static List<dynamic> sorted(List<dynamic> accounts, {List<String>? customOrder}) {
    final list = List<dynamic>.from(accounts);
    sortAccounts(list, customOrder: customOrder);
    return list;
  }
}
