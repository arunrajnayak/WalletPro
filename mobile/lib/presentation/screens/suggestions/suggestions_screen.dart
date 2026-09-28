import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/utils/account_sorter.dart';
import '../../../data/datasources/local/sms_service.dart';
import '../../../data/datasources/remote/api_client.dart';
import '../../providers/pending_count_provider.dart';
import '../../widgets/skeleton_loader.dart';
import '../../widgets/suggestion_card.dart';

class SuggestionsScreen extends ConsumerStatefulWidget {
  const SuggestionsScreen({super.key});

  @override
  ConsumerState<SuggestionsScreen> createState() => _SuggestionsScreenState();
}

class _SuggestionsScreenState extends ConsumerState<SuggestionsScreen> with SingleTickerProviderStateMixin {
  final ApiClient _api = ApiClient();
  final SmsReaderService _smsReader = SmsReaderService();
  late TabController _tabController;

  bool _isLoading = true;
  bool _isScanning = false;
  String? _error;

  List<dynamic> _suggestions = [];
  List<dynamic> _categories = [];
  List<dynamic> _accounts = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        _loadData();
      }
    });
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  String get _currentStatusFilter {
    switch (_tabController.index) {
      case 1:
        return 'approved';
      case 2:
        return 'rejected';
      default:
        return 'pending';
    }
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final futures = await Future.wait([
        _api.getSuggestions(status: _currentStatusFilter),
        _api.getWalletCategories(),
        _api.getWalletAccounts(),
        _api.getSuggestionStats().catchError((_) => <String, dynamic>{}),
      ]);

      final suggestionsRes = futures[0] as List<dynamic>;
      final categoriesRes = futures[1] as List<dynamic>;
      final accountsRes = futures[2] as List<dynamic>;
      AccountSorter.sortAccounts(accountsRes);
      final statsRes = futures[3] as Map<String, dynamic>;

      if (mounted) {
        setState(() {
          _suggestions = suggestionsRes;
          _categories = categoriesRes;
          _accounts = accountsRes;
          _isLoading = false;
        });

        final int pendingCount = (statsRes['pending'] as num?)?.toInt() ??
            (_currentStatusFilter == 'pending' ? suggestionsRes.length : ref.read(pendingCountProvider));
        ref.read(pendingCountProvider.notifier).state = pendingCount;
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to load suggestions: $e';
          _isLoading = false;
        });
      }
    }
  }

  /// Optimistic UI Approve: Removes card instantly and calls API in background.
  /// If API fails, rolls back card to its previous position.
  Future<void> _handleApprove(
    String id, {
    String? walletAccountId,
    String? walletCategoryId,
    String? walletCategoryName,
    String? transactionType,
    bool? isTransfer,
    String? transferToAccountId,
  }) async {
    final index = _suggestions.indexWhere((item) => item['id'] == id);
    if (index == -1) return;

    final removedItem = _suggestions[index];

    // 1. Optimistic removal
    setState(() {
      _suggestions.removeAt(index);
    });

    if (_currentStatusFilter == 'pending') {
      final newCount = (_suggestions.length).clamp(0, 9999);
      ref.read(pendingCountProvider.notifier).state = newCount;
    }

    if (mounted) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Text(
                isTransfer == true || transactionType == 'transfer'
                    ? 'Transfer approved & synced ✓'
                    : 'Transaction approved & synced ✓',
              ),
            ],
          ),
          duration: const Duration(seconds: 2),
          backgroundColor: Colors.green.shade700,
        ),
      );
    }

    // 2. Background API call
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
      // 3. Rollback on failure
      if (mounted) {
        setState(() {
          if (index <= _suggestions.length) {
            _suggestions.insert(index, removedItem);
          } else {
            _suggestions.add(removedItem);
          }
        });

        if (_currentStatusFilter == 'pending') {
          ref.read(pendingCountProvider.notifier).state = _suggestions.length;
        }

        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text('Approval failed: $e')),
              ],
            ),
            duration: const Duration(seconds: 4),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    }
  }

  /// Optimistic UI Reject: Removes card instantly and calls API in background.
  /// If API fails, rolls back card to its previous position.
  Future<void> _handleReject(String id) async {
    final index = _suggestions.indexWhere((item) => item['id'] == id);
    if (index == -1) return;

    final removedItem = _suggestions[index];

    // 1. Optimistic removal
    setState(() {
      _suggestions.removeAt(index);
    });

    if (_currentStatusFilter == 'pending') {
      final newCount = (_suggestions.length).clamp(0, 9999);
      ref.read(pendingCountProvider.notifier).state = newCount;
    }

    if (mounted) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Suggestion rejected'),
          duration: Duration(seconds: 2),
        ),
      );
    }

    // 2. Background API call
    try {
      await _api.rejectSuggestion(id);
    } catch (e) {
      // 3. Rollback on failure
      if (mounted) {
        setState(() {
          if (index <= _suggestions.length) {
            _suggestions.insert(index, removedItem);
          } else {
            _suggestions.add(removedItem);
          }
        });

        if (_currentStatusFilter == 'pending') {
          ref.read(pendingCountProvider.notifier).state = _suggestions.length;
        }

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
      await _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              summary['created']! > 0
                  ? 'Found ${summary['created']} new transactions (scanned ${summary['scanned']} SMS)!'
                  : 'Scanned ${summary['scanned']} SMS from Sep 1, 2026 • No new transactions.',
            ),
            backgroundColor: Colors.green.shade700,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('SMS Scan failed: $e'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isScanning = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pendingCount = ref.watch(pendingCountProvider);
    final isApprovedOrRejected = _currentStatusFilter != 'pending';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Review Queue'),
        actions: [
          _isScanning
              ? const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                )
              : IconButton(
                  icon: const Icon(Icons.sms_outlined),
                  tooltip: 'Scan SMS Inbox',
                  onPressed: _scanSmsInbox,
                ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
            onPressed: () => context.push('/settings'),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('Pending'),
                  if (pendingCount > 0) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '$pendingCount',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const Tab(text: 'Approved'),
            const Tab(text: 'Rejected'),
          ],
        ),
      ),
      body: Column(
        children: [
          // Informational bar for approved / rejected tabs capping at 100
          if (isApprovedOrRejected && _suggestions.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.4),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 14, color: theme.colorScheme.outline),
                  const SizedBox(width: 6),
                  Text(
                    'Showing latest ${_suggestions.length} records sorted by date',
                    style: TextStyle(fontSize: 11.5, color: theme.colorScheme.outline),
                  ),
                ],
              ),
            ),

          // Content / Suggestions List
          Expanded(
            child: _isLoading
                ? const SuggestionListSkeleton()
                : _error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
                              const SizedBox(height: 12),
                              Text(_error!, textAlign: TextAlign.center),
                              const SizedBox(height: 16),
                              ElevatedButton(
                                onPressed: _loadData,
                                child: const Text('Retry'),
                              ),
                            ],
                          ),
                        ),
                      )
                    : _suggestions.isEmpty
                        ? RefreshIndicator(
                            onRefresh: _loadData,
                            child: ListView(
                              children: [
                                SizedBox(height: MediaQuery.of(context).size.height * 0.2),
                                Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        _currentStatusFilter == 'pending'
                                            ? Icons.check_circle_outline
                                            : (_currentStatusFilter == 'approved'
                                                ? Icons.task_alt
                                                : Icons.block_outlined),
                                        size: 64,
                                        color: theme.colorScheme.primary.withOpacity(0.5),
                                      ),
                                      const SizedBox(height: 16),
                                      Text(
                                        _currentStatusFilter == 'pending'
                                            ? 'All caught up!'
                                            : (_currentStatusFilter == 'approved'
                                                ? 'No approved transactions yet'
                                                : 'No rejected transactions'),
                                        style: theme.textTheme.titleMedium?.copyWith(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        _currentStatusFilter == 'pending'
                                            ? 'No pending SMS transactions since Sep 1, 2026.'
                                            : 'Transactions will appear here once reviewed.',
                                        style: theme.textTheme.bodySmall?.copyWith(
                                          color: theme.colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                      const SizedBox(height: 20),
                                      OutlinedButton.icon(
                                        icon: const Icon(Icons.refresh),
                                        label: const Text('Refresh'),
                                        onPressed: _loadData,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: _loadData,
                            child: ListView.builder(
                              padding: const EdgeInsets.only(top: 8, bottom: 100),
                              itemCount: _suggestions.length,
                              itemBuilder: (context, index) {
                                final item = _suggestions[index];
                                return SuggestionCard(
                                  key: Key(item['id']),
                                  suggestion: item,
                                  categories: _categories,
                                  accounts: _accounts,
                                  onApprove: _handleApprove,
                                  onReject: _handleReject,
                                );
                              },
                            ),
                          ),
          ),
        ],
      ),
    );
  }
}
