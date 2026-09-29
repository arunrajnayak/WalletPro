import 'package:dio/dio.dart';
import '../../../core/constants/api_constants.dart';
import '../local/local_cache.dart';

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

  /// In-memory & persistent cache helper with stale-while-revalidate fallback
  T? _getFromCache<T>(String key, {bool allowStale = false}) {
    final item = _cache[key];
    if (item != null) {
      if (!item.isExpired || allowStale) {
        return item.data as T;
      }
    }

    // Fall back to persistent LocalCache
    final local = LocalCache.getJson(key);
    if (local != null) {
      _cache[key] = _CacheItem(local, DateTime.now().add(const Duration(minutes: 5)));
      return local as T;
    }
    return null;
  }

  void _saveToCache(String key, dynamic data, {Duration ttl = const Duration(seconds: 60)}) {
    _cache[key] = _CacheItem(data, DateTime.now().add(ttl));
    LocalCache.setJson(key, data);
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

    try {
      final res = await _dio.get('/api/auth/profile');
      final data = res.data as Map<String, dynamic>;
      _saveToCache(key, data, ttl: const Duration(minutes: 2));
      return data;
    } catch (_) {
      final stale = _getFromCache<Map<String, dynamic>>(key, allowStale: true);
      if (stale != null) return stale;
      rethrow;
    }
  }

  /// Update user preferences (e.g. account order, theme, etc.)
  Future<Map<String, dynamic>> updatePreferences(Map<String, dynamic> preferences) async {
    _cache.remove('user_profile');
    LocalCache.remove('user_profile');
    final res = await _dio.patch(
      '/api/auth/preferences',
      data: preferences,
    );
    return res.data as Map<String, dynamic>;
  }

  // ----------------------------------------------------
  // Suggestions Endpoints
  // ----------------------------------------------------

  /// Fetch suggestions queue with offline caching fallback
  Future<List<dynamic>> getSuggestions({String? status, String? source, int? limit}) async {
    final key = 'suggestions_${status ?? 'all'}_${source ?? 'all'}';
    try {
      final res = await _dio.get(
        '/api/suggestions',
        queryParameters: {
          if (status != null) 'status': status,
          if (source != null) 'source': source,
          if (limit != null) 'limit': limit,
        },
      );
      final data = res.data as List<dynamic>;
      _saveToCache(key, data, ttl: const Duration(seconds: 30));
      return data;
    } catch (_) {
      final stale = _getFromCache<List<dynamic>>(key, allowStale: true);
      if (stale != null) return stale;
      rethrow;
    }
  }

  /// Fetch suggestion statistics
  Future<Map<String, dynamic>> getSuggestionStats() async {
    final res = await _dio.get('/api/suggestions/stats');
    return res.data as Map<String, dynamic>;
  }

  /// Submit new suggestion (parsed or raw text)
  Future<Map<String, dynamic>> createSuggestion(Map<String, dynamic> data) async {
    clearCache();
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

  /// Reset a suggestion back to pending (Undo)
  Future<Map<String, dynamic>> resetSuggestion(String id) async {
    clearCache();
    final res = await _dio.patch('/api/suggestions/$id/reset');
    return res.data as Map<String, dynamic>;
  }

  /// Batch action (approve or reject)
  Future<Map<String, dynamic>> batchSuggestions({
    required String action,
    required List<String> ids,
  }) async {
    clearCache();
    final res = await _dio.post(
      '/api/suggestions/batch',
      data: {
        'action': action,
        'suggestionIds': ids,
      },
    );
    return res.data as Map<String, dynamic>;
  }

  /// Check deduplication for SMS transaction
  Future<Map<String, dynamic>> checkDuplicate({
    required double amount,
    required String transactionDate,
    String? counterParty,
    String? last4,
    String? referenceNumber,
  }) async {
    final res = await _dio.post(
      '/api/suggestions/check-duplicate',
      data: {
        'amount': amount,
        'transactionDate': transactionDate,
        if (counterParty != null) 'counterParty': counterParty,
        if (last4 != null) 'accountLast4': last4,
        if (referenceNumber != null) 'referenceNumber': referenceNumber,
      },
    );
    return res.data as Map<String, dynamic>;
  }

  // ----------------------------------------------------
  // Wallet Direct Endpoints
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

    try {
      final res = await _dio.get('/api/wallet/profile');
      final data = res.data as Map<String, dynamic>;
      _saveToCache(key, data, ttl: const Duration(seconds: 30));
      return data;
    } catch (_) {
      final stale = _getFromCache<Map<String, dynamic>>(key, allowStale: true);
      if (stale != null) return stale;
      rethrow;
    }
  }

  /// Fetch accounts mapped to user (filters out archived accounts by default)
  Future<List<dynamic>> getWalletAccounts({bool includeArchived = false, bool forceRefresh = false}) async {
    final key = 'wallet_accounts_${includeArchived ? 'all' : 'active'}';
    if (!forceRefresh) {
      final cached = _getFromCache<List<dynamic>>(key);
      if (cached != null) return cached;
    }

    try {
      final res = await _dio.get(
        '/api/wallet/accounts',
        queryParameters: {
          if (includeArchived) 'includeArchived': 'true',
        },
      );
      final data = res.data as List<dynamic>;
      _saveToCache(key, data, ttl: const Duration(minutes: 2));
      return data;
    } catch (_) {
      final stale = _getFromCache<List<dynamic>>(key, allowStale: true);
      if (stale != null) return stale;
      rethrow;
    }
  }

  /// Fetch cached categories from Wallet
  Future<List<dynamic>> getWalletCategories({bool forceRefresh = false}) async {
    const key = 'wallet_categories';
    if (!forceRefresh) {
      final cached = _getFromCache<List<dynamic>>(key);
      if (cached != null) return cached;
    }

    try {
      final res = await _dio.get('/api/wallet/categories');
      final data = res.data as List<dynamic>;
      _saveToCache(key, data, ttl: const Duration(minutes: 10));
      return data;
    } catch (_) {
      final stale = _getFromCache<List<dynamic>>(key, allowStale: true);
      if (stale != null) return stale;
      rethrow;
    }
  }

  /// Trigger full sync from BudgetBakers Wallet
  Future<Map<String, dynamic>> syncWallet() async {
    clearCache();
    final res = await _dio.post('/api/wallet/sync');
    return res.data as Map<String, dynamic>;
  }

  /// Map bank account last 4 digits to Wallet account (pass 'NONE' to mark as Don't Map)
  Future<Map<String, dynamic>> mapAccountLast4(String id, String? last4Digits) async {
    clearCache();
    final res = await _dio.patch(
      '/api/wallet/accounts/$id/map-last4',
      data: {'last4Digits': last4Digits},
    );
    return res.data as Map<String, dynamic>;
  }

  /// Fetch live quickview data (accounts with balances & colors, summary, recent records)
  Future<Map<String, dynamic>> getQuickView({bool forceRefresh = false}) async {
    const key = 'wallet_quickview';
    if (!forceRefresh) {
      final cached = _getFromCache<Map<String, dynamic>>(key);
      if (cached != null) return cached;
    }

    try {
      final res = await _dio.get('/api/wallet/quickview');
      final data = res.data as Map<String, dynamic>;
      _saveToCache(key, data, ttl: const Duration(seconds: 45));
      return data;
    } catch (_) {
      final stale = _getFromCache<Map<String, dynamic>>(key, allowStale: true);
      if (stale != null) return stale;
      rethrow;
    }
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

  /// Fetch latest release information from backend proxy cache
  Future<Map<String, dynamic>> getLatestRelease() async {
    final res = await _dio.get('/api/app/latest-release');
    return res.data as Map<String, dynamic>;
  }

  /// Fetch 3-5 last used categories for a specific account
  Future<List<Map<String, dynamic>>> getRecentCategoriesForAccount(
    String accountId, {
    int limit = 5,
    bool forceRefresh = false,
  }) async {
    final key = 'recent_categories_$accountId';
    if (!forceRefresh) {
      final cached = _getFromCache<List<dynamic>>(key);
      if (cached != null) {
        return cached.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
    }

    try {
      final res = await _dio.get(
        '/api/suggestions/recent-categories',
        queryParameters: {'accountId': accountId, 'limit': limit},
      );
      final rawList = res.data as List<dynamic>;
      final list = rawList.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      _saveToCache(key, list, ttl: const Duration(minutes: 5));
      return list;
    } catch (_) {
      final stale = _getFromCache<List<dynamic>>(key, allowStale: true);
      if (stale != null) {
        return stale.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
      return [];
    }
  }

  /// Optimistically record that a category was used for an account in local cache
  void recordCategoryUsedForAccount(String accountId, String categoryId, String categoryName) {
    final key = 'recent_categories_$accountId';
    final existing = _getFromCache<List<dynamic>>(key, allowStale: true) ?? [];
    final list = existing.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    list.removeWhere((item) => item['id'] == categoryId);
    list.insert(0, {'id': categoryId, 'name': categoryName});
    if (list.length > 5) {
      list.removeRange(5, list.length);
    }
    _saveToCache(key, list, ttl: const Duration(minutes: 10));
  }
}
