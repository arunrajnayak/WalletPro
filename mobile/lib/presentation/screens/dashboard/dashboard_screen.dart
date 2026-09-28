import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../core/utils/account_sorter.dart';
import '../../../data/datasources/local/sms_service.dart';
import '../../../data/datasources/remote/api_client.dart';
import '../../providers/pending_count_provider.dart';
import '../../widgets/suggestion_card.dart';
import '../../widgets/skeleton_loader.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  final ApiClient _api = ApiClient();
  final SmsReaderService _smsReader = SmsReaderService();

  bool _isLoading = true;
  bool _isScanning = false;
  int _pendingCount = 0;
  int _approvedCount = 0;

  Map<String, dynamic>? _quickViewData;
  Map<String, dynamic>? _walletProfile;
  List<dynamic> _recentSuggestions = [];
  List<dynamic> _categories = [];
  List<dynamic> _accounts = [];

  @override
  void initState() {
    super.initState();
    _loadDashboard();
  }

  Future<void> _loadDashboard({bool forceRefresh = false}) async {
    setState(() => _isLoading = true);
    try {
      final futures = await Future.wait([
        _api.getSuggestionStats(),
        _api.getUserProfile(forceRefresh: forceRefresh),
        _api.getSuggestions(status: 'pending', limit: 5),
        _api.getWalletCategories(forceRefresh: forceRefresh),
        _api.getWalletAccounts(forceRefresh: forceRefresh),
        _api.getQuickView(forceRefresh: forceRefresh).catchError((_) => <String, dynamic>{}),
        _api.getWalletProfile(forceRefresh: forceRefresh).catchError((_) => <String, dynamic>{}),
      ]);

      final stats = futures[0] as Map<String, dynamic>;
      final recents = futures[2] as List<dynamic>;
      final categories = futures[3] as List<dynamic>;
      final accounts = futures[4] as List<dynamic>;
      final quickView = futures[5] as Map<String, dynamic>;
      final walletProfile = futures[6] as Map<String, dynamic>;

      final int pending = (stats['pending'] as num?)?.toInt() ?? 0;
      ref.read(pendingCountProvider.notifier).state = pending;

      if (mounted) {
        setState(() {
          _pendingCount = pending;
          _approvedCount = stats['approved'] ?? 0;
          AccountSorter.sortAccounts(accounts);
          _recentSuggestions = recents;
          _categories = categories;
          _accounts = accounts;
          _quickViewData = quickView;
          _walletProfile = walletProfile;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// Optimistic UI Approve: Removes card instantly and calls API in background.
  /// Rolls back on failure.
  Future<void> _handleApprove(
    String id, {
    String? walletAccountId,
    String? walletCategoryId,
    String? walletCategoryName,
    String? transactionType,
    bool? isTransfer,
    String? transferToAccountId,
  }) async {
    final index = _recentSuggestions.indexWhere((item) => item['id'] == id);
    if (index == -1) return;
    final removedItem = _recentSuggestions[index];

    final updatedPending = (_pendingCount - 1).clamp(0, 9999);
    ref.read(pendingCountProvider.notifier).state = updatedPending;

    setState(() {
      _recentSuggestions.removeAt(index);
      _pendingCount = updatedPending;
      _approvedCount += 1;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isTransfer == true || transactionType == 'transfer'
                ? 'Transfer approved & synced ✓'
                : 'Approved & synced to Wallet ✓',
          ),
          duration: const Duration(seconds: 2),
          backgroundColor: Colors.green.shade700,
        ),
      );
    }

    try {
      await _api.approveSuggestion(
        id,
        walletAccountId: walletAccountId,
        walletCategoryId: walletCategoryId,
        walletCategoryName: walletCategoryName,
        transactionType: transactionType,
        isTransfer: isTransfer,
        transferToAccountId: transferToAccountId,
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          if (index <= _recentSuggestions.length) {
            _recentSuggestions.insert(index, removedItem);
          } else {
            _recentSuggestions.add(removedItem);
          }
          _pendingCount = (_pendingCount + 1).clamp(0, 9999);
          _approvedCount = (_approvedCount - 1).clamp(0, 9999);
        });
        ref.read(pendingCountProvider.notifier).state = _pendingCount;

        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Approval failed: $e'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    }
  }

  /// Optimistic UI Reject: Removes card instantly and calls API in background.
  /// Rolls back on failure.
  Future<void> _handleReject(String id) async {
    final index = _recentSuggestions.indexWhere((item) => item['id'] == id);
    if (index == -1) return;
    final removedItem = _recentSuggestions[index];

    final updatedPending = (_pendingCount - 1).clamp(0, 9999);
    ref.read(pendingCountProvider.notifier).state = updatedPending;

    setState(() {
      _recentSuggestions.removeAt(index);
      _pendingCount = updatedPending;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Suggestion rejected'),
          duration: Duration(seconds: 2),
        ),
      );
    }

    try {
      await _api.rejectSuggestion(id);
    } catch (e) {
      if (mounted) {
        setState(() {
          if (index <= _recentSuggestions.length) {
            _recentSuggestions.insert(index, removedItem);
          } else {
            _recentSuggestions.add(removedItem);
          }
          _pendingCount = (_pendingCount + 1).clamp(0, 9999);
        });
        ref.read(pendingCountProvider.notifier).state = _pendingCount;

        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Reject failed: $e'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    }
  }

  Future<void> _scanSmsInbox() async {
    setState(() => _isScanning = true);
    try {
      final summary = await _smsReader.scanAndSyncInbox(
        apiClient: _api,
      );
      await _loadDashboard(forceRefresh: true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              summary['created']! > 0
                  ? 'Found ${summary['created']} new transactions (scanned ${summary['scanned']} SMS)!'
                  : 'Scanned ${summary['scanned']} SMS from Sep 1, 2026 • No new transactions.',
            ),
            duration: const Duration(seconds: 3),
            backgroundColor: Colors.green.shade700,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('SMS Scan failed: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isScanning = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final netWorth = (_quickViewData?['summary']?['netWorth'] as num?)?.toDouble() ?? 0.0;
    final totalAssets = (_quickViewData?['summary']?['totalAssets'] as num?)?.toDouble() ?? 0.0;
    final totalLiabilities = (_quickViewData?['summary']?['totalLiabilities'] as num?)?.toDouble() ?? 0.0;

    final isSyncing = _walletProfile?['syncState'] == 'syncing';
    final isConnected = _walletProfile?['connected'] == true;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Text('WalletPro'),
            const Spacer(),
            // Sync status pill
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                color: isSyncing
                    ? Colors.orange.shade50
                    : (isConnected ? Colors.green.shade50 : Colors.grey.shade100),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isSyncing
                      ? Colors.orange.shade300
                      : (isConnected ? Colors.green.shade300 : Colors.grey.shade300),
                  width: 0.8,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isSyncing
                          ? Colors.orange.shade700
                          : (isConnected ? Colors.green.shade700 : Colors.grey.shade600),
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    isSyncing ? 'Syncing...' : (isConnected ? 'Wallet Live' : 'Disconnected'),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: isSyncing
                          ? Colors.orange.shade900
                          : (isConnected ? Colors.green.shade900 : Colors.grey.shade700),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      body: _isLoading
          ? const DashboardSkeleton()
          : RefreshIndicator(
              onRefresh: () => _loadDashboard(forceRefresh: true),
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                children: [
                  // 1. Hero Net Worth Glance Card
                  _buildNetWorthHeroCard(netWorth, totalAssets, totalLiabilities, theme, isDark),

                  const SizedBox(height: 16),

                  // 2. Quick Action Grid
                  _buildQuickActionGrid(theme, isDark),

                  const SizedBox(height: 16),

                  // 3. SMS Detection & Scan Banner
                  _buildSmsScanCard(theme, isDark),

                  const SizedBox(height: 16),

                  // 4. Pending Review Queue Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Text(
                            'Pending Review',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          if (_pendingCount > 0) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.orange.shade100,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                '$_pendingCount',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.orange.shade900,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (_recentSuggestions.isNotEmpty)
                        TextButton(
                          onPressed: () => context.push('/suggestions'),
                          child: const Text('View All'),
                        ),
                    ],
                  ),

                  const SizedBox(height: 8),

                  // 5. Recent Suggestion Cards
                  if (_recentSuggestions.isEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 16),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: theme.colorScheme.outlineVariant.withOpacity(0.5)),
                      ),
                      child: Column(
                        children: [
                          Icon(Icons.check_circle_outline_rounded, size: 48, color: Colors.green.shade600),
                          const SizedBox(height: 12),
                          const Text(
                            'All Caught Up!',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'No pending SMS transactions waiting for approval.',
                            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    )
                  else
                    ..._recentSuggestions.map(
                      (item) => Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: SuggestionCard(
                          key: Key(item['id']),
                          margin: const EdgeInsets.symmetric(horizontal: 0, vertical: 6),
                          suggestion: item,
                          categories: _categories,
                          accounts: _accounts,
                          onApprove: _handleApprove,
                          onReject: _handleReject,
                        ),
                      ),
                    ),
                  const SizedBox(height: 100),
                ],
              ),
            ),
    );
  }

  Widget _buildNetWorthHeroCard(
    double netWorth,
    double assets,
    double liabilities,
    ThemeData theme,
    bool isDark,
  ) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: theme.colorScheme.outlineVariant.withOpacity(0.5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.25 : 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'TOTAL NET WORTH',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.8,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              InkWell(
                onTap: () => context.push('/quickview'),
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  child: Row(
                    children: [
                      Text(
                        'View All Accounts',
                        style: TextStyle(fontSize: 12, color: theme.colorScheme.primary, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(width: 2),
                      Icon(Icons.chevron_right_rounded, size: 16, color: theme.colorScheme.primary),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            CurrencyFormatter.formatINR(netWorth),
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF064E3B).withOpacity(0.3) : const Color(0xFFF0FDF4),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.green.withOpacity(0.2)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Assets', style: TextStyle(fontSize: 11, color: Colors.green.shade700, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text(
                        CurrencyFormatter.formatINR(assets, compact: true),
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.green.shade800),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF7F1D1D).withOpacity(0.3) : const Color(0xFFFEF2F2),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.red.withOpacity(0.2)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Liabilities', style: TextStyle(fontSize: 11, color: Colors.red.shade700, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text(
                        CurrencyFormatter.formatINR(liabilities, compact: true),
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.red.shade800),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActionGrid(ThemeData theme, bool isDark) {
    return Row(
      children: [
        _buildActionTile(
          icon: Icons.sms_outlined,
          label: _isScanning ? 'Scanning...' : 'Scan SMS',
          color: const Color(0xFF3B82F6),
          onTap: _isScanning ? null : _scanSmsInbox,
          theme: theme,
        ),
        const SizedBox(width: 10),
        _buildActionTile(
          icon: Icons.grid_view_rounded,
          label: 'QuickView',
          color: const Color(0xFF8B5CF6),
          onTap: () => context.push('/quickview'),
          theme: theme,
        ),
        const SizedBox(width: 10),
        _buildActionTile(
          icon: Icons.checklist_rtl_rounded,
          label: 'Review ($_pendingCount)',
          color: const Color(0xFFF59E0B),
          onTap: () => context.push('/suggestions'),
          theme: theme,
        ),
      ],
    );
  }

  Widget _buildActionTile({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback? onTap,
    required ThemeData theme,
  }) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: theme.colorScheme.outlineVariant.withOpacity(0.5)),
          ),
          child: Column(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: color.withOpacity(0.12),
                child: Icon(icon, color: color, size: 18),
              ),
              const SizedBox(height: 6),
              Text(
                label,
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSmsScanCard(ThemeData theme, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: theme.colorScheme.outlineVariant.withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.sms_rounded, size: 18, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  const Text('SMS Sync & Detection', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'From 1 Sep 2026',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Scans incoming bank and credit card SMS notifications to automatically create transaction suggestions.',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: FilledButton.icon(
              icon: _isScanning
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.sync_rounded, size: 18),
              label: Text(_isScanning ? 'Scanning Inbox...' : 'Scan New SMS Inbox'),
              onPressed: _isScanning ? null : _scanSmsInbox,
            ),
          ),
        ],
      ),
    );
  }
}
