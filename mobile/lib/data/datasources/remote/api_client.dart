import 'package:dio/dio.dart';
import '../../../core/constants/api_constants.dart';

class ApiClient {
  final Dio _dio;

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
        requestBody: true,
        responseBody: true,
        error: true,
      ),
    );
  }

  // ----------------------------------------------------
  // User Profile & Preferences (Sliding Window Settings)
  // ----------------------------------------------------

  /// Fetch user profile and preferences (syncStartDate, lastReviewedDate, etc.)
  Future<Map<String, dynamic>> getUserProfile() async {
    final res = await _dio.get('/api/auth/profile');
    return res.data as Map<String, dynamic>;
  }

  /// Update user preferences including sliding window cutoff date
  Future<Map<String, dynamic>> updatePreferences({
    DateTime? syncStartDate,
    DateTime? lastReviewedDate,
    bool? autoAdvanceWindow,
  }) async {
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
    final res = await _dio.post(
      '/api/wallet/connect',
      data: {'token': token},
    );
    return res.data as Map<String, dynamic>;
  }

  /// Fetch accounts mapped to user (filters out archived accounts by default)
  Future<List<dynamic>> getWalletAccounts({bool includeArchived = false}) async {
    final res = await _dio.get(
      '/api/wallet/accounts',
      queryParameters: {
        if (includeArchived) 'includeArchived': 'true',
      },
    );
    return res.data as List<dynamic>;
  }

  /// Fetch cached categories from Wallet
  Future<List<dynamic>> getWalletCategories() async {
    final res = await _dio.get('/api/wallet/categories');
    return res.data as List<dynamic>;
  }

  /// Trigger full sync from BudgetBakers Wallet
  Future<Map<String, dynamic>> syncWallet() async {
    final res = await _dio.post('/api/wallet/sync');
    return res.data as Map<String, dynamic>;
  }

  /// Map bank account last 4 digits to Wallet account
  Future<Map<String, dynamic>> mapAccountLast4(String id, String last4Digits) async {
    final res = await _dio.patch(
      '/api/wallet/accounts/$id/map-last4',
      data: {'last4Digits': last4Digits},
    );
    return res.data as Map<String, dynamic>;
  }

  /// Fetch live quickview data (accounts with balances & colors, summary, budgets, recent records)
  Future<Map<String, dynamic>> getQuickView() async {
    final res = await _dio.get('/api/wallet/quickview');
    return res.data as Map<String, dynamic>;
  }

  /// Fetch records directly from Wallet
  Future<List<dynamic>> getWalletRecords({int limit = 20, String? accountId}) async {
    final res = await _dio.get(
      '/api/wallet/records',
      queryParameters: {
        'limit': limit,
        if (accountId != null) 'accountId': accountId,
      },
    );
    return res.data as List<dynamic>;
  }

  /// Save custom account display order
  Future<Map<String, dynamic>> saveAccountOrder(List<String> accountOrder) async {
    final res = await _dio.patch(
      '/api/wallet/accounts/reorder',
      data: {'accountOrder': accountOrder},
    );
    return res.data as Map<String, dynamic>;
  }

  // ----------------------------------------------------
  // Portfolio Endpoints
  // ----------------------------------------------------

  /// List all portfolio holdings
  Future<List<dynamic>> getPortfolio({String? type}) async {
    final res = await _dio.get(
      '/api/portfolio',
      queryParameters: {
        if (type != null) 'type': type,
      },
    );
    return res.data as List<dynamic>;
  }

  /// Portfolio summary (totals, gains, breakdown)
  Future<Map<String, dynamic>> getPortfolioSummary() async {
    final res = await _dio.get('/api/portfolio/summary');
    return res.data as Map<String, dynamic>;
  }

  /// Add holding manually
  Future<Map<String, dynamic>> addHolding(Map<String, dynamic> data) async {
    final res = await _dio.post('/api/portfolio/holdings', data: data);
    return res.data as Map<String, dynamic>;
  }

  /// Update holding
  Future<Map<String, dynamic>> updateHolding(String id, Map<String, dynamic> data) async {
    final res = await _dio.patch('/api/portfolio/holdings/$id', data: data);
    return res.data as Map<String, dynamic>;
  }

  /// Delete holding
  Future<void> deleteHolding(String id) async {
    await _dio.delete('/api/portfolio/holdings/$id');
  }

  /// Refresh portfolio NAVs and generate value suggestions
  Future<Map<String, dynamic>> refreshPortfolio() async {
    final res = await _dio.post('/api/portfolio/refresh');
    return res.data as Map<String, dynamic>;
  }

  // ----------------------------------------------------
  // Insights Endpoints
  // ----------------------------------------------------

  /// Monthly breakdown
  Future<Map<String, dynamic>> getInsightsMonthly() async {
    final res = await _dio.get('/api/insights/monthly');
    return res.data as Map<String, dynamic>;
  }

  /// Budget progress from Wallet
  Future<Map<String, dynamic>> getInsightsBudgets() async {
    final res = await _dio.get('/api/insights/budgets');
    return res.data as Map<String, dynamic>;
  }

  /// Multi-month trends
  Future<Map<String, dynamic>> getInsightsTrends() async {
    final res = await _dio.get('/api/insights/trends');
    return res.data as Map<String, dynamic>;
  }
}
