import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../core/utils/account_sorter.dart';
import '../../../data/datasources/local/notification_service.dart';
import '../../../data/datasources/local/sms_service.dart';
import '../../../data/datasources/local/update_service.dart';
import '../../../data/datasources/remote/api_client.dart';
import '../../providers/app_update_provider.dart';
import '../../providers/pending_count_provider.dart';
import '../../providers/wallet_provider.dart';
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
  String _selectedAccountFilter = 'All'; // 'All' | 'Banks' | 'Credit' | 'Investments'

  Map<String, dynamic>? _quickViewData;
  Map<String, dynamic>? _walletProfile;

  @override
  void initState() {
    super.initState();
    _loadDashboard();
    _autoScanOnStartup();
  }

  Future<void> _autoScanOnStartup() async {
    try {
      final hasPerm = await _smsReader.hasPermission();
      if (hasPerm) {
        await _smsReader.scanAndSyncInbox(apiClient: _api);
        if (mounted) {
          _loadDashboard(forceRefresh: true);
        }
      }
    } catch (_) {}
  }

  Future<void> _loadDashboard({bool forceRefresh = false}) async {
    setState(() => _isLoading = true);
    try {
      final futures = await Future.wait([
        _api.getSuggestionStats(),
        _api.getUserProfile(forceRefresh: forceRefresh),
        _api.getWalletCategories(forceRefresh: forceRefresh),
        _api.getWalletAccounts(forceRefresh: forceRefresh),
        _api.getQuickView(forceRefresh: forceRefresh).catchError((_) => <String, dynamic>{}),
        _api.getWalletProfile(forceRefresh: forceRefresh).catchError((_) => <String, dynamic>{}),
      ]);

      final stats = futures[0] as Map<String, dynamic>;
      final categories = futures[2] as List<dynamic>;
      final localAccounts = futures[3] as List<dynamic>;
      final quickView = futures[4] as Map<String, dynamic>;
      final walletProfile = futures[5] as Map<String, dynamic>;

      final int pending = (stats['pending'] as num?)?.toInt() ?? 0;
      ref.read(pendingCountProvider.notifier).state = pending;
      NotificationService.updatePendingCount(pending);

      // Prefer quickView accounts because they contain live balances and colors from BudgetBakers
      final qvAccounts = (quickView['accounts'] as List<dynamic>?) ?? [];
      final accounts = qvAccounts.isNotEmpty ? qvAccounts : localAccounts;

      AccountSorter.sortAccounts(accounts);
      ref.read(walletAccountsProvider.notifier).setAccounts(accounts);
      ref.read(walletCategoriesProvider.notifier).setCategories(categories);

      if (mounted) {
        setState(() {
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

  Color _getAccountColor(dynamic colorValue, int index) {
    if (colorValue != null && colorValue is String && colorValue.isNotEmpty) {
      try {
        String hex = colorValue.replaceAll('#', '').trim();
        if (hex.length == 6) hex = 'FF$hex';
        if (hex.length == 8) return Color(int.parse('0x$hex'));
      } catch (_) {}
    }
    const palette = [
      Color(0xFF3B82F6), // Blue
      Color(0xFF10B981), // Emerald
      Color(0xFF8B5CF6), // Purple
      Color(0xFFF59E0B), // Amber
      Color(0xFFEC4899), // Pink
      Color(0xFF06B6D4), // Cyan
      Color(0xFF6366F1), // Indigo
      Color(0xFF14B8A6), // Teal
    ];
    return palette[index % palette.length];
  }

  IconData _getAccountIcon(String name, String? accountType) {
    final lower = name.toLowerCase();
    final typeLower = (accountType ?? '').toLowerCase();

    if (typeLower.contains('credit') ||
        lower.contains('credit') ||
        lower.contains('card') ||
        lower.contains('platinum') ||
        lower.contains('rewards')) {
      return Icons.credit_card;
    }
    if (lower.contains('mutual') ||
        lower.contains('fund') ||
        lower.contains('zerodha') ||
        lower.contains('upstox') ||
        lower.contains('stock') ||
        lower.contains('share')) {
      return Icons.trending_up_rounded;
    }
    if (typeLower.contains('cash') || lower.contains('cash') || lower.contains('wallet')) {
      return Icons.payments_outlined;
    }
    return Icons.account_balance_outlined;
  }

  void _showAccountDetailSheet(Map<String, dynamic> account) {
    final accountId = (account['walletAccountId'] ?? account['id']).toString();
    final accountName = account['name'] ?? 'Account';
    final balance = (account['balance'] as num?)?.toDouble() ?? 0.0;
    final last4 = account['last4Digits']?.toString();
    final isNone = last4 == 'NONE';
    final isMapped = last4 != null && !isNone && last4.trim().isNotEmpty;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0F172A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.65,
          minChildSize: 0.4,
          maxChildSize: 0.9,
          expand: false,
          builder: (context, scrollController) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    margin: const EdgeInsets.only(top: 12, bottom: 8),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade600,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              accountName,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 3),
                            Text(
                              isMapped
                                  ? 'Mapped: •••• $last4'
                                  : (isNone ? 'Don\'t Map' : 'Not Mapped'),
                              style: TextStyle(
                                fontSize: 12,
                                color: isMapped ? Colors.green.shade400 : Colors.grey.shade400,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        CurrencyFormatter.formatINR(balance),
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: balance < 0 ? const Color(0xFFF87171) : const Color(0xFF4ADE80),
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(color: Colors.white12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Recent Transactions',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.white70,
                        ),
                      ),
                      TextButton.icon(
                        icon: const Icon(Icons.edit, size: 14),
                        label: const Text('Edit Mapping', style: TextStyle(fontSize: 12)),
                        onPressed: () {
                          Navigator.pop(ctx);
                          context.push('/settings');
                        },
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: FutureBuilder<List<dynamic>>(
                    future: _api.getWalletRecords(limit: 25, accountId: accountId),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (snapshot.hasError) {
                        return Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              'Failed to load records: ${snapshot.error}',
                              style: const TextStyle(color: Colors.redAccent),
                            ),
                          ),
                        );
                      }
                      final records = snapshot.data ?? [];
                      if (records.isEmpty) {
                        return const Center(
                          child: Padding(
                            padding: EdgeInsets.all(24),
                            child: Text(
                              'No recent records found in Wallet',
                              style: TextStyle(color: Colors.white54),
                            ),
                          ),
                        );
                      }
                      return ListView.separated(
                        controller: scrollController,
                        itemCount: records.length,
                        separatorBuilder: (_, __) => const Divider(color: Colors.white10, height: 1),
                        itemBuilder: (context, idx) {
                          final rec = records[idx];
                          final rawAmount = rec['amount'];
                          double amt = 0.0;
                          if (rawAmount is Map && rawAmount['value'] != null) {
                            amt = (rawAmount['value'] as num).toDouble();
                          } else if (rawAmount is num) {
                            amt = rawAmount.toDouble();
                          }
                          final isExp = amt < 0;
                          final party = rec['counterParty'] ?? rec['note'] ?? 'Record';
                          final catName = rec['category']?['name'] ?? 'Uncategorized';
                          DateTime? dt;
                          if (rec['recordDate'] != null) {
                            dt = DateTime.tryParse(rec['recordDate'].toString());
                          }

                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: isExp
                                  ? Colors.red.shade900.withValues(alpha: 0.4)
                                  : Colors.green.shade900.withValues(alpha: 0.4),
                              child: Icon(
                                isExp ? Icons.arrow_upward : Icons.arrow_downward,
                                color: isExp ? Colors.red.shade300 : Colors.green.shade300,
                                size: 18,
                              ),
                            ),
                            title: Text(
                              party,
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                            ),
                            subtitle: Text(
                              '${dt != null ? DateFormatter.formatFull(dt) : ''} • $catName',
                              style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
                            ),
                            trailing: Text(
                              '${isExp ? '-' : '+'}₹${amt.abs().toStringAsFixed(2)}',
                              style: TextStyle(
                                color: isExp ? Colors.red.shade400 : Colors.green.shade400,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showReorderAccountsModal() {
    final currentAccounts = ref.read(walletAccountsProvider);
    final reorderList = List<dynamic>.from(currentAccounts);
    final previousList = List<dynamic>.from(currentAccounts);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0F172A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              height: MediaQuery.of(context).size.height * 0.8,
              padding: const EdgeInsets.only(top: 12),
              child: Column(
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade600,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Reorder Accounts',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Drag handle on right to reorder',
                              style: TextStyle(fontSize: 12, color: Colors.grey),
                            ),
                          ],
                        ),
                        TextButton(
                          onPressed: () async {
                            Navigator.pop(ctx);
                            final orderIds = reorderList
                                .map((a) => (a['walletAccountId'] ?? a['id']).toString())
                                .toList();
                            ref.read(walletAccountsProvider.notifier).reorder(orderIds);
                            try {
                              await _api.saveAccountOrder(orderIds);
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Account order saved!'), backgroundColor: Colors.green),
                                );
                              }
                            } catch (e) {
                              ref.read(walletAccountsProvider.notifier).setAccounts(previousList);
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Failed to save order: $e'), backgroundColor: Colors.red),
                                );
                              }
                            }
                          },
                          child: const Text('Done', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        ),
                      ],
                    ),
                  ),
                  const Divider(color: Colors.white12),
                  Expanded(
                    child: ReorderableListView.builder(
                      itemCount: reorderList.length,
                      onReorder: (oldIndex, newIndex) {
                        setModalState(() {
                          if (newIndex > oldIndex) newIndex--;
                          final item = reorderList.removeAt(oldIndex);
                          reorderList.insert(newIndex, item);
                        });
                      },
                      itemBuilder: (context, index) {
                        final acc = reorderList[index];
                        final name = acc['name'] ?? 'Account';
                        final last4 = acc['last4Digits']?.toString();
                        final isMapped = last4 != null && last4 != 'NONE' && last4.trim().isNotEmpty;

                        return ListTile(
                          key: ValueKey('reorder_${acc['walletAccountId'] ?? acc['id']}_$index'),
                          leading: CircleAvatar(
                            radius: 16,
                            backgroundColor: _getAccountColor(acc['color'], index).withValues(alpha: 0.2),
                            child: Icon(_getAccountIcon(name, acc['accountType']), size: 16, color: _getAccountColor(acc['color'], index)),
                          ),
                          title: Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                          subtitle: Text(
                            isMapped ? '•••• $last4' : (acc['accountType'] ?? 'General'),
                            style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
                          ),
                          trailing: const Icon(Icons.drag_handle_rounded, color: Colors.white54),
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final accounts = ref.watch(walletAccountsProvider);
    final updateState = ref.watch(appUpdateProvider);

    final netWorth = (_quickViewData?['summary']?['netWorth'] as num?)?.toDouble() ?? 0.0;
    final totalAssets = (_quickViewData?['summary']?['totalAssets'] as num?)?.toDouble() ?? 0.0;
    final totalLiabilities = (_quickViewData?['summary']?['totalLiabilities'] as num?)?.toDouble() ?? 0.0;

    final isSyncing = _walletProfile?['syncState'] == 'syncing';
    final isConnected = _walletProfile?['connected'] == true;

    // Filter accounts based on selected segment
    final filteredAccounts = accounts.where((acc) {
      if (_selectedAccountFilter == 'All') return true;
      final type = (acc['accountType'] ?? '').toString().toLowerCase();
      final name = (acc['name'] ?? '').toString().toLowerCase();
      if (_selectedAccountFilter == 'Credit') {
        return type.contains('credit') || name.contains('credit') || name.contains('card');
      }
      if (_selectedAccountFilter == 'Investments') {
        return type.contains('invest') || name.contains('fund') || name.contains('zerodha') || name.contains('stock') || name.contains('nps') || name.contains('epf');
      }
      if (_selectedAccountFilter == 'Banks') {
        final isCredit = type.contains('credit') || name.contains('credit') || name.contains('card');
        final isInv = type.contains('invest') || name.contains('fund') || name.contains('zerodha') || name.contains('stock');
        return !isCredit && !isInv;
      }
      return true;
    }).toList();

    return Scaffold(
      backgroundColor: const Color(0xFF090D16),
      appBar: AppBar(
        backgroundColor: const Color(0xFF090D16),
        elevation: 0,
        title: Row(
          children: [
            const Text(
              'WalletPro',
              style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: -0.5),
            ),
            const Spacer(),
            // Sync status pill
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: isSyncing
                    ? const Color(0xFF7C2D12).withValues(alpha: 0.3)
                    : (isConnected ? const Color(0xFF064E3B).withValues(alpha: 0.4) : const Color(0xFF1E293B)),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isSyncing
                      ? Colors.orange.shade700
                      : (isConnected ? Colors.green.shade600 : Colors.grey.shade600),
                  width: 0.9,
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
                          ? Colors.orangeAccent
                          : (isConnected ? const Color(0xFF4ADE80) : Colors.grey.shade400),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    isSyncing ? 'Syncing...' : (isConnected ? 'Wallet Live' : 'Offline'),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: isSyncing
                          ? Colors.orangeAccent
                          : (isConnected ? const Color(0xFF4ADE80) : Colors.grey.shade300),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, size: 20),
            tooltip: 'Refresh Dashboard',
            onPressed: () => _loadDashboard(forceRefresh: true),
          ),
        ],
      ),
      body: _isLoading
          ? const DashboardSkeleton()
          : RefreshIndicator(
              onRefresh: () => _loadDashboard(forceRefresh: true),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                children: [
                  // 0. Update Alert Banner (when new version is detected)
                  if (updateState.updateInfo?.isUpdateAvailable == true && !updateState.isBannerDismissed) ...[
                    _buildUpdateBanner(updateState.updateInfo!),
                    const SizedBox(height: 14),
                  ],

                  // 1. Consolidated Net Worth Hero Glance Card
                  _buildNetWorthHeroCard(netWorth, totalAssets, totalLiabilities),

                  const SizedBox(height: 20),

                  // 2. Consolidated Accounts & Balances Grid (from QuickView)
                  _buildAccountsSection(accounts, filteredAccounts),
                ],
              ),
            ),
    );
  }

  Widget _buildUpdateBanner(UpdateInfo info) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF3B82F6),
          width: 1.2,
        ),
      ),
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: const BoxDecoration(
              color: Color(0xFF1E3A8A),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.system_update_rounded,
              size: 20,
              color: Color(0xFF93C5FD),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'Update v${info.version} Available',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade600,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'NEW',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                const Text(
                  'A new version with the latest improvements is available for installation.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white70,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    FilledButton(
                      onPressed: () => context.push('/settings'),
                      style: FilledButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        backgroundColor: const Color(0xFF2563EB),
                      ),
                      child: const Text('Update Now', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: () => ref.read(appUpdateProvider.notifier).dismissBanner(),
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        foregroundColor: Colors.white60,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      ),
                      child: const Text('Later', style: TextStyle(fontSize: 12)),
                    ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(
              Icons.close_rounded,
              size: 18,
              color: Colors.white60,
            ),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: () => ref.read(appUpdateProvider.notifier).dismissBanner(),
            tooltip: 'Dismiss',
          ),
        ],
      ),
    );
  }

  Widget _buildNetWorthHeroCard(double netWorth, double totalAssets, double totalLiabilities) {
    final assetRatio = (totalAssets + totalLiabilities.abs()) > 0
        ? (totalAssets / (totalAssets + totalLiabilities.abs())).clamp(0.05, 0.95)
        : 1.0;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFF334155), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'TOTAL NET WORTH',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                  color: Color(0xFF94A3B8),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: netWorth >= 0
                      ? const Color(0xFF064E3B).withValues(alpha: 0.5)
                      : const Color(0xFF7F1D1D).withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      netWorth >= 0 ? Icons.trending_up : Icons.trending_down,
                      size: 13,
                      color: netWorth >= 0 ? const Color(0xFF4ADE80) : const Color(0xFFF87171),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      netWorth >= 0 ? 'Healthy' : 'Deficit',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.bold,
                        color: netWorth >= 0 ? const Color(0xFF4ADE80) : const Color(0xFFF87171),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              CurrencyFormatter.formatINR(netWorth),
              style: TextStyle(
                fontSize: 34,
                fontWeight: FontWeight.w900,
                letterSpacing: -1.0,
                color: netWorth >= 0 ? Colors.white : const Color(0xFFF87171),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Visual Ratio Split Bar
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              height: 7,
              child: Row(
                children: [
                  Expanded(
                    flex: (assetRatio * 100).toInt(),
                    child: Container(color: const Color(0xFF10B981)),
                  ),
                  const SizedBox(width: 2),
                  Expanded(
                    flex: ((1 - assetRatio) * 100).toInt(),
                    child: Container(color: const Color(0xFFEF4444)),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Assets & Liabilities Row
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF090D16).withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFF1E293B)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.arrow_upward_rounded, size: 13, color: Colors.green.shade400),
                          const SizedBox(width: 4),
                          const Text('Total Assets', style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8), fontWeight: FontWeight.w600)),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        CurrencyFormatter.formatINR(totalAssets),
                        style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold, color: Color(0xFF4ADE80)),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF090D16).withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFF1E293B)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.arrow_downward_rounded, size: 13, color: Colors.red.shade400),
                          const SizedBox(width: 4),
                          const Text('Total Liabilities', style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8), fontWeight: FontWeight.w600)),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        CurrencyFormatter.formatINR(totalLiabilities),
                        style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold, color: Color(0xFFF87171)),
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

  Widget _buildAccountsSection(List<dynamic> allAccounts, List<dynamic> filteredAccounts) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                const Text(
                  'Accounts & Balances',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${allAccounts.length}',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF94A3B8)),
                  ),
                ),
              ],
            ),
            TextButton.icon(
              icon: const Icon(Icons.swap_vert_rounded, size: 16),
              label: const Text('Reorder', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              onPressed: allAccounts.isNotEmpty ? _showReorderAccountsModal : null,
            ),
          ],
        ),
        const SizedBox(height: 8),

        // Filter Pills
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          child: Row(
            children: ['All', 'Banks', 'Credit', 'Investments'].map((filter) {
              final isSel = _selectedAccountFilter == filter;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilterChip(
                  label: Text(filter),
                  selected: isSel,
                  onSelected: (val) {
                    setState(() => _selectedAccountFilter = filter);
                  },
                  backgroundColor: const Color(0xFF0F172A),
                  selectedColor: const Color(0xFF312E81),
                  labelStyle: TextStyle(
                    fontSize: 12,
                    fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                    color: isSel ? Colors.white : const Color(0xFF94A3B8),
                  ),
                  side: BorderSide(
                    color: isSel ? const Color(0xFF6366F1) : const Color(0xFF1E293B),
                    width: isSel ? 1.4 : 1.0,
                  ),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 12),

        // Grid of Account Cards
        if (filteredAccounts.isEmpty)
          Container(
            padding: const EdgeInsets.all(28),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF1E293B)),
            ),
            child: const Text('No accounts match this filter', style: TextStyle(color: Colors.white54)),
          )
        else
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: filteredAccounts.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              mainAxisExtent: 116,
            ),
            itemBuilder: (context, index) {
              final acc = filteredAccounts[index];
              final name = acc['name'] ?? 'Account';
              final balance = (acc['balance'] as num?)?.toDouble() ?? 0.0;
              final color = _getAccountColor(acc['color'], index);
              final icon = _getAccountIcon(name, acc['accountType']);

              return InkWell(
                onTap: () => _showAccountDetailSheet(acc),
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFF1E293B)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.2),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      CircleAvatar(
                        radius: 14,
                        backgroundColor: color.withValues(alpha: 0.2),
                        child: Icon(icon, size: 14, color: color),
                      ),
                      Text(
                        name,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        CurrencyFormatter.formatINR(balance),
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w800,
                          color: balance < 0 ? const Color(0xFFF87171) : const Color(0xFF4ADE80),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
      ],
    );
  }

}
