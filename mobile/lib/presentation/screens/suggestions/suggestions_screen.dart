import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/utils/account_sorter.dart';
import '../../../core/utils/stats_parser.dart';
import '../../../data/datasources/local/notification_service.dart';
import '../../../data/datasources/local/sms_service.dart';
import '../../../data/datasources/remote/api_client.dart';
import '../../providers/pending_count_provider.dart';
import '../../providers/suggestions_provider.dart';
import '../../providers/wallet_provider.dart';
import '../../widgets/skeleton_loader.dart';
import '../../widgets/suggestion_card.dart';
import '../../widgets/swipeable_review_deck.dart';

class SuggestionsScreen extends ConsumerStatefulWidget {
  const SuggestionsScreen({super.key});

  @override
  ConsumerState<SuggestionsScreen> createState() => _SuggestionsScreenState();
}

class _SuggestionsScreenState extends ConsumerState<SuggestionsScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final ApiClient _api = ApiClient();
  final SmsReaderService _smsReader = SmsReaderService();
  late TabController _tabController;

  bool _isLoading = true;
  bool _isScanning = false;
  bool _isDeckMode = true;
  String? _error;

  List<dynamic> _historicalSuggestions = [];

  // Tracks last known pending count to detect new-card arrivals reactively
  int _lastKnownPendingLength = 0;
  bool _initialLoadDone = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        _loadData();
      }
    });
    SharedPreferences.getInstance().then((p) {
      if (mounted) {
        setState(() {
          _isDeckMode = p.getBool('pref_review_deck_mode') ?? true;
        });
      }
    });
    _loadData();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tabController.dispose();
    super.dispose();
  }

  /// Silently refresh when the app comes back to foreground
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      _api.clearSuggestionsCache();
      _loadData();
    }
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
    // Always bust suggestion cache so freshest data is fetched
    _api.clearSuggestionsCache();
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final futures = await Future.wait([
        _api.getSuggestions(
          status: _currentStatusFilter,
          limit: _currentStatusFilter == 'pending' ? null : 100,
        ),
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
        ref.read(walletAccountsProvider.notifier).setAccounts(accountsRes);
        ref.read(walletCategoriesProvider.notifier).setCategories(categoriesRes);
        if (_currentStatusFilter == 'pending') {
          ref.read(pendingSuggestionsProvider.notifier).setSuggestions(suggestionsRes);
        } else {
          _historicalSuggestions = PendingSuggestionsNotifier.sortByDateTime(suggestionsRes);
        }

        final int pendingCount = parseStatCount(
          statsRes['pending'],
          fallback: _currentStatusFilter == 'pending'
              ? suggestionsRes.length
              : ref.read(pendingCountProvider),
        );
        ref.read(pendingCountProvider.notifier).state = pendingCount;
        NotificationService.updatePendingCount(pendingCount);

        setState(() {
          _isLoading = false;
          _initialLoadDone = true;
          _lastKnownPendingLength = _currentStatusFilter == 'pending'
              ? suggestionsRes.length
              : _lastKnownPendingLength;
        });
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

  /// Optimistic UI Approve: Removes card instantly from shared provider and calls API in background.
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
    final pending = ref.read(pendingSuggestionsProvider);
    final index = pending.indexWhere((item) => item['id'] == id);
    final removedItem = index != -1 ? pending[index] : null;

    // 1. Optimistic removal from shared reactive store
    ref.read(pendingSuggestionsProvider.notifier).removeSuggestion(id);

    if (_currentStatusFilter == 'pending') {
      final newCount = (pending.length - 1).clamp(0, 9999);
      ref.read(pendingCountProvider.notifier).state = newCount;
      NotificationService.updatePendingCount(newCount);
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
      if (removedItem != null) {
        ref.read(pendingSuggestionsProvider.notifier).insertSuggestion(removedItem, index: index);
      }
      if (_currentStatusFilter == 'pending') {
        final revertedCount = ref.read(pendingSuggestionsProvider).length;
        ref.read(pendingCountProvider.notifier).state = revertedCount;
        NotificationService.updatePendingCount(revertedCount);
      }

      if (mounted) {
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

  /// Optimistic UI Reject: Removes card instantly from shared provider and calls API in background.
  /// If API fails, rolls back card to its previous position.
  Future<void> _handleReject(String id) async {
    final pending = ref.read(pendingSuggestionsProvider);
    final index = pending.indexWhere((item) => item['id'] == id);
    final removedItem = index != -1 ? pending[index] : null;

    // 1. Optimistic removal from shared reactive store
    ref.read(pendingSuggestionsProvider.notifier).removeSuggestion(id);

    if (_currentStatusFilter == 'pending') {
      final newCount = (pending.length - 1).clamp(0, 9999);
      ref.read(pendingCountProvider.notifier).state = newCount;
      NotificationService.updatePendingCount(newCount);
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
      if (removedItem != null) {
        ref.read(pendingSuggestionsProvider.notifier).insertSuggestion(removedItem, index: index);
      }
      if (_currentStatusFilter == 'pending') {
        final revertedCount = ref.read(pendingSuggestionsProvider).length;
        ref.read(pendingCountProvider.notifier).state = revertedCount;
        NotificationService.updatePendingCount(revertedCount);
      }

      if (mounted) {
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

  /// Undo last review decision: re-inserts the suggestion at the top and calls /reset in background.
  Future<void> _handleUndo(dynamic restoredItem) async {
    final id = restoredItem['id'].toString();

    // 1. Optimistic restoration into shared reactive store
    ref.read(pendingSuggestionsProvider.notifier).insertSuggestion(restoredItem, index: 0);

    if (_currentStatusFilter == 'pending') {
      final newCount = ref.read(pendingSuggestionsProvider).length;
      ref.read(pendingCountProvider.notifier).state = newCount;
      NotificationService.updatePendingCount(newCount);
    }

    if (mounted) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              Icon(Icons.replay_rounded, color: Colors.white, size: 18),
              SizedBox(width: 8),
              Text('Review decision undone ✓'),
            ],
          ),
          duration: Duration(seconds: 2),
          backgroundColor: Color(0xFFF59E0B),
        ),
      );
    }

    try {
      await _api.resetSuggestion(id);
    } catch (e) {
      // Rollback on failure
      ref.read(pendingSuggestionsProvider.notifier).removeSuggestion(id);
      if (_currentStatusFilter == 'pending') {
        final revertedCount = ref.read(pendingSuggestionsProvider).length;
        ref.read(pendingCountProvider.notifier).state = revertedCount;
        NotificationService.updatePendingCount(revertedCount);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Undo failed on server: $e'),
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

  /// Called during build whenever pendingSuggestions changes.
  /// Shows a snackbar if new cards were pushed in reactively (e.g. by background scan).
  void _onNewSuggestionsArrived(List<dynamic> suggestions) {
    if (!_initialLoadDone || _isLoading || _currentStatusFilter != 'pending') return;
    if (suggestions.length > _lastKnownPendingLength) {
      final added = suggestions.length - _lastKnownPendingLength;
      _lastKnownPendingLength = suggestions.length;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.fiber_new_rounded, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Text('$added new transaction${added > 1 ? 's' : ''} ready to review!'),
              ],
            ),
            backgroundColor: Colors.green.shade700,
            duration: const Duration(seconds: 3),
          ),
        );
      });
    } else {
      _lastKnownPendingLength = suggestions.length;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pendingCount = ref.watch(pendingCountProvider);
    final pendingSuggestions = ref.watch(pendingSuggestionsProvider);
    final accounts = ref.watch(walletAccountsProvider);
    final categories = ref.watch(walletCategoriesProvider);
    final isApprovedOrRejected = _currentStatusFilter != 'pending';
    final currentSuggestions = isApprovedOrRejected ? _historicalSuggestions : pendingSuggestions;

    // Reactively detect new suggestions pushed in from background scan
    _onNewSuggestionsArrived(pendingSuggestions);


    return Scaffold(
      appBar: AppBar(
        title: const Text('Review Queue'),
        actions: [
          if (_currentStatusFilter == 'pending')
            IconButton(
              icon: Icon(_isDeckMode ? Icons.view_agenda_outlined : Icons.view_carousel_rounded),
              tooltip: _isDeckMode ? 'Switch to List View' : 'Switch to Swipe Deck',
              onPressed: () {
                setState(() => _isDeckMode = !_isDeckMode);
                SharedPreferences.getInstance().then((p) => p.setBool('pref_review_deck_mode', _isDeckMode));
              },
            ),
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
          // Thin scanning indicator — shown while SMS scan is in progress
          if (_isScanning)
            LinearProgressIndicator(
              minHeight: 2,
              backgroundColor: Colors.transparent,
              color: theme.colorScheme.primary,
            ),

          // Informational bar for approved / rejected tabs capping at 100
          if (isApprovedOrRejected && currentSuggestions.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.4),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 14, color: theme.colorScheme.outline),
                  const SizedBox(width: 6),
                  Text(
                    'Showing latest ${currentSuggestions.length} records sorted by date',
                    style: TextStyle(fontSize: 11.5, color: theme.colorScheme.outline),
                  ),
                ],
              ),
            ),

          // Content / Suggestions List / Swipe Deck
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
                    : (_currentStatusFilter == 'pending' && _isDeckMode)
                        ? SwipeableReviewDeck(
                            suggestions: pendingSuggestions,
                            categories: categories,
                            accounts: accounts,
                            onApprove: _handleApprove,
                            onReject: _handleReject,
                            onUndo: _handleUndo,
                            onRefresh: _loadData,
                            onScanSms: _scanSmsInbox,
                          )
                        : currentSuggestions.isEmpty
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
                                            _currentStatusFilter == 'approved'
                                                ? Icons.task_alt
                                                : (_currentStatusFilter == 'rejected'
                                                    ? Icons.block_outlined
                                                    : Icons.check_circle_outline),
                                            size: 64,
                                            color: theme.colorScheme.primary.withOpacity(0.5),
                                          ),
                                          const SizedBox(height: 16),
                                          Text(
                                            _currentStatusFilter == 'approved'
                                                ? 'No approved transactions yet'
                                                : (_currentStatusFilter == 'rejected'
                                                    ? 'No rejected transactions'
                                                    : 'All caught up!'),
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
                                          if (_currentStatusFilter == 'pending') ...[
                                            const SizedBox(height: 12),
                                            OutlinedButton.icon(
                                              icon: const Icon(Icons.sms_outlined),
                                              label: const Text('Scan SMS Inbox'),
                                              onPressed: _isScanning ? null : _scanSmsInbox,
                                            ),
                                          ],
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
                                  itemCount: currentSuggestions.length,
                                  itemBuilder: (context, index) {
                                    final item = currentSuggestions[index];
                                    return SuggestionCard(
                                      key: Key(item['id']),
                                      suggestion: item,
                                      categories: categories,
                                      accounts: accounts,
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
