import 'package:dio/dio.dart';
import '../../../core/constants/api_constants.dart';

class _CacheItem {
  final dynamic data;
  final DateTime expiresAt;

  _CacheItem(this.data, this.expiresAt);
  bool get isExpired => DateTime.now().isAfter(expiresAt);
}

class ApiClient {
  final Dio _dio;
  static final Map<String, _CacheItem> _cache = {};

  ApiClient({String? baseUrl, String? apiKey})
      : _dio = Dio(
          BaseOptions(
            baseUrl: baseUrl ?? ApiConstants.backendBaseUrl,
            connectTimeout: const Duration(seconds: 15),
            receiveTimeout: const Duration(seconds: 15),
            headers: {
              'Content-Type': 'application/json',
              if (apiKey != null && apiKey.isNotEmpty) 'x-api-key': apiKey,
            },
          ),
        ) {
    _dio.interceptors.add(
      LogInterceptor(
        requestBody: false,
        responseBody: false,
        error: true,
      ),
    );
  }

  /// In-memory cache helper
  T? _getFromCache<T>(String key) {
    final item = _cache[key];
    if (item == null) return null;
    if (item.isExpired) {
      _cache.remove(key);
      return null;
    }
    return item.data as T;
  }

  void _saveToCache(String key, dynamic data, {Duration ttl = const Duration(seconds: 60)}) {
    _cache[key] = _CacheItem(data, DateTime.now().add(ttl));
  }

  /// Explicitly clear cached API responses (e.g. on pull-to-refresh)
  void clearCache() {
    _cache.clear();
  }

  // ----------------------------------------------------
  // User Profile & Preferences (Sliding Window Settings)
  // ----------------------------------------------------

  /// Fetch user profile and preferences (syncStartDate, lastReviewedDate, etc.)
  Future<Map<String, dynamic>> getUserProfile({bool forceRefresh = false}) async {
    const key = 'user_profile';
    if (!forceRefresh) {
      final cached = _getFromCache<Map<String, dynamic>>(key);
      if (cached != null) return cached;
    }

    final res = await _dio.get('/api/auth/profile');
    final data = res.data as Map<String, dynamic>;
    _saveToCache(key, data, ttl: const Duration(seconds: 45));
    return data;
  }

  /// Update user preferences including sliding window cutoff date
  Future<Map<String, dynamic>> updatePreferences({
    DateTime? syncStartDate,
    DateTime? lastReviewedDate,
    bool? autoAdvanceWindow,
  }) async {
    _cache.remove('user_profile');
    final res = await _dio.patch(
      '/api/auth/preferences',
      data: {
        if (syncStartDate != null) 'syncStartDate': syncStartDate.toIso8601String(),
        if (lastReviewedDate != null) 'lastReviewedDate': lastReviewedDate.toIso8601String(),
        if (autoAdvanceWindow != null) 'autoAdvanceWindow': autoAdvanceWindow,
      },
    );
    return res.data as Map<String, dynamic>;
  }

  // ----------------------------------------------------
  // Suggestions Endpoints
  // ----------------------------------------------------

  /// Fetch suggestions queue
  Future<List<dynamic>> getSuggestions({String? status, String? source, int limit = 50}) async {
    final res = await _dio.get(
      '/api/suggestions',
      queryParameters: {
        if (status != null) 'status': status,
        if (source != null) 'source': source,
        'limit': limit,
      },
    );
    return res.data as List<dynamic>;
  }

  /// Fetch suggestion statistics
  Future<Map<String, dynamic>> getSuggestionStats() async {
    final res = await _dio.get('/api/suggestions/stats');
    return res.data as Map<String, dynamic>;
  }

  /// Submit new suggestion (parsed or raw text)
  Future<Map<String, dynamic>> createSuggestion(Map<String, dynamic> data) async {
    _cache.remove('user_profile');
    final res = await _dio.post('/api/suggestions', data: data);
    return res.data as Map<String, dynamic>;
  }

  /// Approve a suggestion and sync to BudgetBakers Wallet
  Future<Map<String, dynamic>> approveSuggestion(
    String id, {
    String? walletAccountId,
    String? walletCategoryId,
    String? walletCategoryName,
    String? note,
    String? transactionType,
    bool? isTransfer,
    String? transferToAccountId,
  }) async {
    clearCache();
    final res = await _dio.patch(
      '/api/suggestions/$id/approve',
      data: {
        if (walletAccountId != null) 'walletAccountId': walletAccountId,
        if (walletCategoryId != null) 'walletCategoryId': walletCategoryId,
        if (walletCategoryName != null) 'walletCategoryName': walletCategoryName,
        if (note != null) 'note': note,
        if (transactionType != null) 'transactionType': transactionType,
        if (isTransfer != null) 'isTransfer': isTransfer,
        if (transferToAccountId != null) 'transferToAccountId': transferToAccountId,
      },
    );
    return res.data as Map<String, dynamic>;
  }

  /// Reject a suggestion
  Future<Map<String, dynamic>> rejectSuggestion(String id) async {
    clearCache();
    final res = await _dio.patch('/api/suggestions/$id/reject');
    return res.data as Map<String, dynamic>;
  }

  /// Batch action (approve or reject)
  Future<Map<String, dynamic>> batchSuggestions({
    required String action,
    required List<String> ids,
    String? walletAccountId,
    String? walletCategoryId,
  }) async {
    clearCache();
    final res = await _dio.post(
      '/api/suggestions/batch',
      data: {
        'action': action,
        'ids': ids,
        if (walletAccountId != null) 'walletAccountId': walletAccountId,
        if (walletCategoryId != null) 'walletCategoryId': walletCategoryId,
      },
    );
    return res.data as Map<String, dynamic>;
  }

  // ----------------------------------------------------
  // Wallet Integration Endpoints
  // ----------------------------------------------------

  /// Connect Wallet with API Token
  Future<Map<String, dynamic>> connectWallet(String token) async {
    clearCache();
    final res = await _dio.post(
      '/api/wallet/connect',
      data: {'token': token},
    );
    return res.data as Map<String, dynamic>;
  }

  /// Fetch Wallet connection status, sync state, and rate limits
  Future<Map<String, dynamic>> getWalletProfile({bool forceRefresh = false}) async {
    const key = 'wallet_profile';
    if (!forceRefresh) {
      final cached = _getFromCache<Map<String, dynamic>>(key);
      if (cached != null) return cached;
    }

    final res = await _dio.get('/api/wallet/profile');
    final data = res.data as Map<String, dynamic>;
    _saveToCache(key, data, ttl: const Duration(seconds: 30));
    return data;
  }

  /// Fetch accounts mapped to user (filters out archived accounts by default)
  Future<List<dynamic>> getWalletAccounts({bool includeArchived = false, bool forceRefresh = false}) async {
    final key = 'wallet_accounts_${includeArchived ? 'all' : 'active'}';
    if (!forceRefresh) {
      final cached = _getFromCache<List<dynamic>>(key);
      if (cached != null) return cached;
    }

    final res = await _dio.get(
      '/api/wallet/accounts',
      queryParameters: {
        if (includeArchived) 'includeArchived': 'true',
      },
    );
    final data = res.data as List<dynamic>;
    _saveToCache(key, data, ttl: const Duration(seconds: 60));
    return data;
  }

  /// Fetch cached categories from Wallet
  Future<List<dynamic>> getWalletCategories({bool forceRefresh = false}) async {
    const key = 'wallet_categories';
    if (!forceRefresh) {
      final cached = _getFromCache<List<dynamic>>(key);
      if (cached != null) return cached;
    }

    final res = await _dio.get('/api/wallet/categories');
    final data = res.data as List<dynamic>;
    _saveToCache(key, data, ttl: const Duration(minutes: 5));
    return data;
  }

  /// Trigger full sync from BudgetBakers Wallet
  Future<Map<String, dynamic>> syncWallet() async {
    clearCache();
    final res = await _dio.post('/api/wallet/sync');
    return res.data as Map<String, dynamic>;
  }

  /// Map bank account last 4 digits to Wallet account
  Future<Map<String, dynamic>> mapAccountLast4(String id, String last4Digits) async {
    clearCache();
    final res = await _dio.patch(
      '/api/wallet/accounts/$id/map-last4',
      data: {'last4Digits': last4Digits},
    );
    return res.data as Map<String, dynamic>;
  }

  /// Fetch live quickview data (accounts with balances & colors, summary, budgets, recent records)
  Future<Map<String, dynamic>> getQuickView({bool forceRefresh = false}) async {
    const key = 'wallet_quickview';
    if (!forceRefresh) {
      final cached = _getFromCache<Map<String, dynamic>>(key);
      if (cached != null) return cached;
    }

    final res = await _dio.get('/api/wallet/quickview');
    final data = res.data as Map<String, dynamic>;
    _saveToCache(key, data, ttl: const Duration(seconds: 30));
    return data;
  }

  /// Fetch records directly from Wallet with filtering and search
  Future<List<dynamic>> getWalletRecords({
    int limit = 20,
    String? accountId,
    String? recordType,
    String? counterParty,
  }) async {
    final res = await _dio.get(
      '/api/wallet/records',
      queryParameters: {
        'limit': limit,
        if (accountId != null) 'accountId': accountId,
        if (recordType != null) 'recordType': recordType,
        if (counterParty != null) 'counterParty': counterParty,
      },
    );
    return res.data as List<dynamic>;
  }

  /// Save custom account display order
  Future<Map<String, dynamic>> saveAccountOrder(List<String> accountOrder) async {
    clearCache();
    final res = await _dio.patch(
      '/api/wallet/accounts/reorder',
      data: {'accountOrder': accountOrder},
    );
    return res.data as Map<String, dynamic>;
  }

  // ----------------------------------------------------
  // Insights Endpoints
  // ----------------------------------------------------

  /// Monthly breakdown powered by Wallet records aggregation
  Future<Map<String, dynamic>> getInsightsMonthly({int? year, int? month, bool forceRefresh = false}) async {
    final key = 'insights_monthly_${year ?? 'curr'}_${month ?? 'curr'}';
    if (!forceRefresh) {
      final cached = _getFromCache<Map<String, dynamic>>(key);
      if (cached != null) return cached;
    }

    final res = await _dio.get(
      '/api/insights/monthly',
      queryParameters: {
        if (year != null) 'year': year,
        if (month != null) 'month': month,
      },
    );
    final data = res.data as Map<String, dynamic>;
    _saveToCache(key, data, ttl: const Duration(seconds: 45));
    return data;
  }

  /// Budget progress from Wallet
  Future<Map<String, dynamic>> getInsightsBudgets({bool forceRefresh = false}) async {
    const key = 'insights_budgets';
    if (!forceRefresh) {
      final cached = _getFromCache<Map<String, dynamic>>(key);
      if (cached != null) return cached;
    }

    final res = await _dio.get('/api/insights/budgets');
    final data = res.data as Map<String, dynamic>;
    _saveToCache(key, data, ttl: const Duration(seconds: 45));
    return data;
  }

  /// Discretionary vs Essential ("Must" vs "Want" vs "Need") spending
  Future<Map<String, dynamic>> getInsightsCardinality({bool forceRefresh = false}) async {
    const key = 'insights_cardinality';
    if (!forceRefresh) {
      final cached = _getFromCache<Map<String, dynamic>>(key);
      if (cached != null) return cached;
    }

    final res = await _dio.get('/api/insights/cardinality');
    final data = res.data as Map<String, dynamic>;
    _saveToCache(key, data, ttl: const Duration(seconds: 60));
    return data;
  }

  /// Top spending merchants / payees
  Future<Map<String, dynamic>> getInsightsMerchants({bool forceRefresh = false}) async {
    const key = 'insights_merchants';
    if (!forceRefresh) {
      final cached = _getFromCache<Map<String, dynamic>>(key);
      if (cached != null) return cached;
    }

    final res = await _dio.get('/api/insights/merchants');
    final data = res.data as Map<String, dynamic>;
    _saveToCache(key, data, ttl: const Duration(seconds: 60));
    return data;
  }

  /// Multi-month trends
  Future<Map<String, dynamic>> getInsightsTrends({bool forceRefresh = false}) async {
    const key = 'insights_trends';
    if (!forceRefresh) {
      final cached = _getFromCache<Map<String, dynamic>>(key);
      if (cached != null) return cached;
    }

    final res = await _dio.get('/api/insights/trends');
    final data = res.data as Map<String, dynamic>;
    _saveToCache(key, data, ttl: const Duration(minutes: 2));
    return data;
  }
}
