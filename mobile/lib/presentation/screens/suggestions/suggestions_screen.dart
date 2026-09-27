import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../data/datasources/local/sms_service.dart';
import '../../../data/datasources/remote/api_client.dart';
import '../../widgets/suggestion_card.dart';

class SuggestionsScreen extends StatefulWidget {
  const SuggestionsScreen({super.key});

  @override
  State<SuggestionsScreen> createState() => _SuggestionsScreenState();
}

class _SuggestionsScreenState extends State<SuggestionsScreen> with SingleTickerProviderStateMixin {
  final ApiClient _api = ApiClient();
  final SmsReaderService _smsReader = SmsReaderService();
  late TabController _tabController;

  bool _isLoading = true;
  bool _isScanning = false;
  String? _error;

  List<dynamic> _suggestions = [];
  List<dynamic> _categories = [];
  List<dynamic> _accounts = [];

  DateTime? _lastReviewedDate;
  DateTime? _syncStartDate;
  bool _autoAdvanceWindow = true;

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
        _api.getUserProfile(),
      ]);

      final suggestionsRes = futures[0] as List<dynamic>;
      final categoriesRes = futures[1] as List<dynamic>;
      final accountsRes = futures[2] as List<dynamic>;
      final profileRes = futures[3] as Map<String, dynamic>;

      final prefs = (profileRes['preferences'] as Map<String, dynamic>?) ?? {};
      DateTime? revDate;
      DateTime? strtDate;

      if (prefs['lastReviewedDate'] != null) {
        revDate = DateTime.tryParse(prefs['lastReviewedDate'].toString());
      }
      if (prefs['syncStartDate'] != null) {
        strtDate = DateTime.tryParse(prefs['syncStartDate'].toString());
      }

      if (mounted) {
        setState(() {
          _suggestions = suggestionsRes;
          _categories = categoriesRes;
          _accounts = accountsRes;
          _lastReviewedDate = revDate;
          _syncStartDate = strtDate;
          _autoAdvanceWindow = prefs['autoAdvanceWindow'] ?? true;
          _isLoading = false;
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

  Future<void> _handleApprove(
    String id, {
    String? walletAccountId,
    String? walletCategoryId,
    String? walletCategoryName,
    String? transactionType,
    bool? isTransfer,
    String? transferToAccountId,
  }) async {
    try {
      final res = await _api.approveSuggestion(
        id,
        walletAccountId: walletAccountId,
        walletCategoryId: walletCategoryId,
        walletCategoryName: walletCategoryName,
        transactionType: transactionType,
        isTransfer: isTransfer,
        transferToAccountId: transferToAccountId,
      );

      // Check if sliding window auto-advanced
      if (res['slidingWindowUpdated'] == true && res['newCutoffDate'] != null) {
        final newCutoff = DateTime.tryParse(res['newCutoffDate'].toString());
        if (newCutoff != null) {
          setState(() {
            _lastReviewedDate = newCutoff;
          });
        }
      }

      // Remove from list
      setState(() {
        _suggestions.removeWhere((item) => item['id'] == id);
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(res['syncedToWallet'] == true
                ? 'Approved & Synced to BudgetBakers Wallet!'
                : 'Approved suggestion!'),
            duration: const Duration(seconds: 2),
            backgroundColor: Colors.green.shade700,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Approval failed: $e'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    }
  }

  Future<void> _handleReject(String id) async {
    try {
      final res = await _api.rejectSuggestion(id);

      // Check if sliding window auto-advanced
      if (res['slidingWindowUpdated'] == true && res['newCutoffDate'] != null) {
        final newCutoff = DateTime.tryParse(res['newCutoffDate'].toString());
        if (newCutoff != null) {
          setState(() {
            _lastReviewedDate = newCutoff;
          });
        }
      }

      // Remove from list
      setState(() {
        _suggestions.removeWhere((item) => item['id'] == id);
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Suggestion rejected'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Reject failed: $e'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    }
  }

  Future<void> _pickNewCutoffDate() async {
    final effectiveCutoff = _lastReviewedDate ?? _syncStartDate ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: effectiveCutoff,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );

    if (picked != null) {
      try {
        await _api.updatePreferences(lastReviewedDate: picked);
        setState(() {
          _lastReviewedDate = picked;
        });
        _loadData();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Cutoff updated to ${DateFormatter.formatDate(picked)}'),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to update cutoff: $e')),
          );
        }
      }
    }
  }

  Future<void> _scanSmsInbox() async {
    setState(() => _isScanning = true);
    final effectiveCutoff = _lastReviewedDate ?? _syncStartDate;
    try {
      final summary = await _smsReader.scanAndSyncInbox(
        sinceDate: effectiveCutoff,
        apiClient: _api,
      );
      await _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              summary['created']! > 0
                  ? 'Found ${summary['created']} new transactions (scanned ${summary['scanned']} SMS)!'
                  : 'Scanned ${summary['scanned']} SMS • No new transactions found.',
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
    final effectiveCutoff = _lastReviewedDate ?? _syncStartDate;

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
            icon: const Icon(Icons.settings),
            tooltip: 'Window & Wallet Settings',
            onPressed: () => context.push('/settings'),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Pending'),
            Tab(text: 'Approved'),
            Tab(text: 'Rejected'),
          ],
        ),
      ),
      body: Column(
        children: [
          // ----------------------------------------------------
          // Sliding Window Cutoff Header Banner
          // ----------------------------------------------------
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer.withOpacity(0.4),
              border: Border(
                bottom: BorderSide(color: theme.colorScheme.outlineVariant.withOpacity(0.5)),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.timelapse,
                  color: theme.colorScheme.primary,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        effectiveCutoff != null
                            ? 'Reviewed Up To: ${DateFormatter.formatDate(effectiveCutoff)}'
                            : 'No cutoff set (all SMS processed)',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.onPrimaryContainer,
                        ),
                      ),
                      Text(
                        _autoAdvanceWindow ? 'Window sliding automatically on review' : 'Sliding window paused',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onPrimaryContainer.withOpacity(0.7),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: _pickNewCutoffDate,
                  child: const Text('Adjust'),
                ),
              ],
            ),
          ),

          // ----------------------------------------------------
          // Content / Suggestions List
          // ----------------------------------------------------
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
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
                                        Icons.check_circle_outline,
                                        size: 64,
                                        color: theme.colorScheme.primary.withOpacity(0.5),
                                      ),
                                      const SizedBox(height: 16),
                                      Text(
                                        'All caught up!',
                                        style: theme.textTheme.titleMedium?.copyWith(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        effectiveCutoff != null
                                            ? 'No $_currentStatusFilter transactions after ${DateFormatter.formatDate(effectiveCutoff)}'
                                            : 'No $_currentStatusFilter transactions found.',
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
                              padding: const EdgeInsets.only(top: 8, bottom: 24),
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
