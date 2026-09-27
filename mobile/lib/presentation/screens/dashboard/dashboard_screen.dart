import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../data/datasources/local/sms_service.dart';
import '../../../data/datasources/remote/api_client.dart';
import '../../widgets/suggestion_card.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final ApiClient _api = ApiClient();
  final SmsReaderService _smsReader = SmsReaderService();

  bool _isLoading = true;
  bool _isScanning = false;
  int _pendingCount = 0;
  int _approvedCount = 0;
  DateTime? _lastReviewedDate;
  DateTime? _syncStartDate;
  bool _autoAdvance = true;
  List<dynamic> _recentSuggestions = [];
  List<dynamic> _categories = [];
  List<dynamic> _accounts = [];

  @override
  void initState() {
    super.initState();
    _loadDashboard();
  }

  Future<void> _loadDashboard() async {
    setState(() => _isLoading = true);
    try {
      final futures = await Future.wait([
        _api.getSuggestionStats(),
        _api.getUserProfile(),
        _api.getSuggestions(status: 'pending', limit: 5),
        _api.getWalletCategories(),
        _api.getWalletAccounts(),
      ]);

      final stats = futures[0] as Map<String, dynamic>;
      final profile = futures[1] as Map<String, dynamic>;
      final recents = futures[2] as List<dynamic>;
      final categories = futures[3] as List<dynamic>;
      final accounts = futures[4] as List<dynamic>;

      final prefs = (profile['preferences'] as Map<String, dynamic>?) ?? {};
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
          _pendingCount = stats['pending'] ?? 0;
          _approvedCount = stats['approved'] ?? 0;
          _lastReviewedDate = revDate;
          _syncStartDate = strtDate;
          _autoAdvance = prefs['autoAdvanceWindow'] ?? true;
          _recentSuggestions = recents;
          _categories = categories;
          _accounts = accounts;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _handleApprove(
    String id, {
    String? walletAccountId,
    String? walletCategoryId,
    String? walletCategoryName,
  }) async {
    try {
      final res = await _api.approveSuggestion(
        id,
        walletAccountId: walletAccountId,
        walletCategoryId: walletCategoryId,
        walletCategoryName: walletCategoryName,
      );

      if (res['slidingWindowUpdated'] == true && res['newCutoffDate'] != null) {
        final newCutoff = DateTime.tryParse(res['newCutoffDate'].toString());
        if (newCutoff != null) {
          setState(() => _lastReviewedDate = newCutoff);
        }
      }

      setState(() {
        _recentSuggestions.removeWhere((item) => item['id'] == id);
        _pendingCount = (_pendingCount - 1).clamp(0, 9999);
        _approvedCount += 1;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Approved & Synced to Wallet!'),
            duration: Duration(seconds: 2),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Approval failed: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _handleReject(String id) async {
    try {
      final res = await _api.rejectSuggestion(id);

      if (res['slidingWindowUpdated'] == true && res['newCutoffDate'] != null) {
        final newCutoff = DateTime.tryParse(res['newCutoffDate'].toString());
        if (newCutoff != null) {
          setState(() => _lastReviewedDate = newCutoff);
        }
      }

      setState(() {
        _recentSuggestions.removeWhere((item) => item['id'] == id);
        _pendingCount = (_pendingCount - 1).clamp(0, 9999);
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Suggestion rejected'), duration: Duration(seconds: 2)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Reject failed: $e'), backgroundColor: Colors.red),
        );
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
      await _loadDashboard();
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
          SnackBar(content: Text('SMS Scan failed: $e'), backgroundColor: Colors.red.shade700),
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
        title: const Text('WalletPro'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _loadDashboard,
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Settings',
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadDashboard,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                children: [
                  // ----------------------------------------------------
                  // Sliding Window Status Card
                  // ----------------------------------------------------
                  Card(
                    elevation: 0,
                    color: theme.colorScheme.primaryContainer.withOpacity(0.3),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(color: theme.colorScheme.primary.withOpacity(0.2)),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.history_toggle_off, color: theme.colorScheme.primary),
                              const SizedBox(width: 8),
                              Text(
                                'Sliding Window Cutoff',
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                              const Spacer(),
                              TextButton(
                                onPressed: () => context.push('/settings'),
                                child: const Text('Settings'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            effectiveCutoff != null
                                ? 'Transactions reviewed up to ${DateFormatter.formatDate(effectiveCutoff)}'
                                : 'No cutoff set (all SMS processed)',
                            style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _autoAdvance
                                ? 'Old SMS prior to this date are automatically skipped.'
                                : 'Auto-advance is paused.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              style: FilledButton.styleFrom(
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              icon: _isScanning
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                    )
                                  : const Icon(Icons.sms_outlined, size: 18),
                              label: Text(_isScanning ? 'Scanning SMS Inbox...' : 'Scan SMS Inbox (From Cutoff)'),
                              onPressed: _isScanning ? null : _scanSmsInbox,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // ----------------------------------------------------
                  // Summary Stats Row
                  // ----------------------------------------------------
                  Row(
                    children: [
                      Expanded(
                        child: Card(
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                            side: BorderSide(color: theme.colorScheme.outlineVariant),
                          ),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: () => context.push('/suggestions'),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '$_pendingCount',
                                    style: theme.textTheme.headlineMedium?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: _pendingCount > 0 ? Colors.orange.shade800 : Colors.green.shade800,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text('Pending Review', style: theme.textTheme.bodySmall),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Card(
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                            side: BorderSide(color: theme.colorScheme.outlineVariant),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '$_approvedCount',
                                  style: theme.textTheme.headlineMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: theme.colorScheme.primary,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text('Synced to Wallet', style: theme.textTheme.bodySmall),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // ----------------------------------------------------
                  // Pending Queue Header
                  // ----------------------------------------------------
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Pending Review',
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      if (_recentSuggestions.isNotEmpty)
                        TextButton(
                          onPressed: () => context.push('/suggestions'),
                          child: const Text('View All'),
                        ),
                    ],
                  ),

                  const SizedBox(height: 8),

                  if (_recentSuggestions.isEmpty)
                    Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(color: theme.colorScheme.outlineVariant),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 16),
                        child: Column(
                          children: [
                            Icon(Icons.done_all, size: 48, color: Colors.green.shade600),
                            const SizedBox(height: 12),
                            const Text(
                              'All Transactions Reviewed!',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Incoming SMS will appear here automatically.',
                              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    ..._recentSuggestions.map(
                      (item) => SuggestionCard(
                        key: Key(item['id']),
                        suggestion: item,
                        categories: _categories,
                        accounts: _accounts,
                        onApprove: _handleApprove,
                        onReject: _handleReject,
                      ),
                    ),
                ],
              ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: 0,
        type: BottomNavigationBarType.fixed,
        items: [
          const BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
          BottomNavigationBarItem(
            icon: Badge(
              isLabelVisible: _pendingCount > 0,
              label: Text('$_pendingCount'),
              child: const Icon(Icons.list_alt),
            ),
            label: 'Review',
          ),
          const BottomNavigationBarItem(icon: Icon(Icons.pie_chart_outline), label: 'Portfolio'),
          const BottomNavigationBarItem(icon: Icon(Icons.insights_outlined), label: 'Insights'),
          const BottomNavigationBarItem(icon: Icon(Icons.settings_outlined), label: 'Settings'),
        ],
        onTap: (index) {
          switch (index) {
            case 1:
              context.push('/suggestions');
              break;
            case 2:
              context.push('/portfolio');
              break;
            case 3:
              context.push('/insights');
              break;
            case 4:
              context.push('/settings');
              break;
          }
        },
      ),
    );
  }
}
