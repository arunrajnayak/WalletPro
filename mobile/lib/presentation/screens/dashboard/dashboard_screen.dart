import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../core/utils/account_sorter.dart';
import '../../../core/utils/stats_parser.dart';
import '../../../data/datasources/local/notification_service.dart';
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

  bool _isLoading = true;
  String _selectedAccountFilter = 'All'; // 'All' | 'Banks' | 'Credit' | 'Investments'

  Map<String, dynamic>? _quickViewData;
  Map<String, dynamic>? _walletProfile;

  @override
  void initState() {
    super.initState();
    _loadDashboard();
  }

  Future<void> _loadDashboard({bool forceRefresh = false}) async {
    if (_quickViewData == null) {
      setState(() => _isLoading = true);
    }
    try {
      final futures = await Future.wait([
        _api.getSuggestionStats(),
        _api.getUserProfile(forceRefresh: forceRefresh),
        _api.getWalletCategories(forceRefresh: forceRefresh),
        _api.getQuickView(forceRefresh: forceRefresh).catchError((_) => <String, dynamic>{}),
        _api.getWalletProfile(forceRefresh: forceRefresh).catchError((_) => <String, dynamic>{}),
      ]);

      final stats = futures[0] as Map<String, dynamic>;
      final categories = futures[2] as List<dynamic>;
      final quickView = futures[3] as Map<String, dynamic>;
      final walletProfile = futures[4] as Map<String, dynamic>;

      final int pending = parseStatCount(stats['pending']);
      ref.read(pendingCountProvider.notifier).state = pending;
      NotificationService.updatePendingCount(pending);

      // Prefer quickView accounts because they contain live balances and colors from BudgetBakers
      var accounts = (quickView['accounts'] as List<dynamic>?) ?? [];
      if (accounts.isEmpty) {
        // Fallback to local accounts only if quickView accounts are missing
        try {
          accounts = await _api.getWalletAccounts(forceRefresh: forceRefresh);
        } catch (_) {}
      }

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

  bool _isCreditAccount(Map<String, dynamic> acc) {
    final type = (acc['accountType'] ?? '').toString().toLowerCase();
    final name = (acc['name'] ?? '').toString().toLowerCase();
    return type.contains('credit') ||
        name.contains('credit') ||
        name.contains('card') ||
        name.contains('platinum') ||
        name.contains('rewards');
  }

  bool _isInvestmentAccount(Map<String, dynamic> acc) {
    final type = (acc['accountType'] ?? '').toString().toLowerCase();
    final name = (acc['name'] ?? '').toString().toLowerCase();
    return type.contains('invest') ||
        name.contains('mutual') ||
        name.contains('fund') ||
        name.contains('zerodha') ||
        name.contains('stock') ||
        name.contains('share') ||
        name.contains('nps') ||
        name.contains('upstox') ||
        name.contains('epf');
  }

  bool _isBankOrCashAccount(Map<String, dynamic> acc) {
    return !_isCreditAccount(acc) && !_isInvestmentAccount(acc);
  }

  void _showAccountDetailSheet(Map<String, dynamic> account) {
    final accountId = (account['walletAccountId'] ?? account['id']).toString();
    final accountName = account['name'] ?? 'Account';
    final balance = parseDouble(account['balance']);
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
                            if (isMapped) ...[
                              const SizedBox(height: 3),
                              Text(
                                'Mapped: •••• $last4',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.green.shade400,
                                ),
                              ),
                            ] else if (!isNone) ...[
                              const SizedBox(height: 3),
                              Text(
                                'Not Mapped',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade400,
                                ),
                              ),
                            ],
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
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_isInvestmentAccount(account)) ...[
                            TextButton.icon(
                              icon: const Icon(Icons.edit_rounded, size: 14, color: Color(0xFF818CF8)),
                              label: const Text(
                                'Update Value',
                                style: TextStyle(fontSize: 12, color: Color(0xFF818CF8), fontWeight: FontWeight.bold),
                              ),
                              onPressed: () {
                                Navigator.pop(ctx);
                                _showUpdateInvestmentValueSheet(account);
                              },
                            ),
                            const SizedBox(width: 4),
                          ],
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

  void _showUpdateInvestmentValueSheet(Map<String, dynamic> account) {
    final accountName = account['name'] ?? 'Investment Account';
    final color = _getAccountColor(account['color'], 0);
    final icon = _getAccountIcon(accountName, account['accountType']);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0F172A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => _UpdateInvestmentValueSheet(
        account: account,
        accountName: accountName,
        color: color,
        icon: icon,
        quickViewAccounts: (_quickViewData?['accounts'] as List<dynamic>?) ?? [],
        onUpdated: () => _loadDashboard(forceRefresh: true),
      ),
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
    ref.listen(dashboardRefreshTriggerProvider, (previous, next) {
      if (next > 0) {
        _loadDashboard(forceRefresh: true);
      }
    });

    final accounts = ref.watch(walletAccountsProvider);
    final updateState = ref.watch(appUpdateProvider);

    final netWorth = parseDouble(_quickViewData?['summary']?['netWorth']);
    final totalAssets = parseDouble(_quickViewData?['summary']?['totalAssets']);
    final totalLiabilities = parseDouble(_quickViewData?['summary']?['totalLiabilities']);

    final isSyncing = _walletProfile?['syncState'] == 'syncing';
    final isConnected = _walletProfile?['connected'] == true;

    // Filter accounts based on selected segment
    final filteredAccounts = accounts.where((acc) {
      if (acc is! Map<String, dynamic>) return true;
      if (_selectedAccountFilter == 'All') return true;
      if (_selectedAccountFilter == 'Credit') return _isCreditAccount(acc);
      if (_selectedAccountFilter == 'Investments') return _isInvestmentAccount(acc);
      if (_selectedAccountFilter == 'Banks') return _isBankOrCashAccount(acc);
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
    final absAssets = totalAssets.abs();
    final absLiab = totalLiabilities.abs();
    final totalPool = absAssets + absLiab;
    final assetRatio = totalPool > 0
        ? (absAssets / totalPool).clamp(0.05, 0.95)
        : 1.0;
    final assetPct = (assetRatio * 100).toInt();
    final liabPct = 100 - assetPct;

    return Container(
      padding: const EdgeInsets.all(22),
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
            blurRadius: 20,
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
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: netWorth >= 0 ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'TOTAL NET WORTH',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                      color: Color(0xFF94A3B8),
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3.5),
                decoration: BoxDecoration(
                  color: netWorth >= 0
                      ? const Color(0xFF064E3B).withValues(alpha: 0.5)
                      : const Color(0xFF7F1D1D).withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: netWorth >= 0
                        ? const Color(0xFF059669).withValues(alpha: 0.6)
                        : const Color(0xFFDC2626).withValues(alpha: 0.6),
                    width: 0.8,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      netWorth >= 0 ? Icons.trending_up_rounded : Icons.trending_down_rounded,
                      size: 13,
                      color: netWorth >= 0 ? const Color(0xFF4ADE80) : const Color(0xFFF87171),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      netWorth >= 0 ? 'Healthy' : 'Deficit',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: netWorth >= 0 ? const Color(0xFF4ADE80) : const Color(0xFFF87171),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              CurrencyFormatter.formatINR(netWorth),
              style: TextStyle(
                fontSize: 36,
                fontWeight: FontWeight.w900,
                letterSpacing: -1.0,
                color: netWorth >= 0 ? Colors.white : const Color(0xFFF87171),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Visual Ratio Split Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '$assetPct% Assets',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF34D399),
                ),
              ),
              Text(
                '$liabPct% Liabilities',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFFF87171),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),

          // Visual Ratio Split Bar
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              height: 7,
              child: Row(
                children: [
                  Expanded(
                    flex: assetPct > 0 ? assetPct : 1,
                    child: Container(color: const Color(0xFF10B981)),
                  ),
                  const SizedBox(width: 2),
                  Expanded(
                    flex: liabPct > 0 ? liabPct : 1,
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
                    color: const Color(0xFF10B981).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.25)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.arrow_upward_rounded, size: 13, color: Colors.green.shade400),
                          const SizedBox(width: 4),
                          const Text(
                            'Total Assets',
                            style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8), fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          CurrencyFormatter.formatINR(totalAssets),
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF4ADE80),
                          ),
                        ),
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
                    color: const Color(0xFFEF4444).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.25)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.arrow_downward_rounded, size: 13, color: Colors.red.shade400),
                          const SizedBox(width: 4),
                          const Text(
                            'Total Liabilities',
                            style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8), fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          CurrencyFormatter.formatINR(totalLiabilities),
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFFF87171),
                          ),
                        ),
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

  int _countForFilter(String filter, List<dynamic> list) {
    if (filter == 'All') return list.length;
    if (filter == 'Banks') return list.where((a) => a is Map<String, dynamic> && _isBankOrCashAccount(a)).length;
    if (filter == 'Credit') return list.where((a) => a is Map<String, dynamic> && _isCreditAccount(a)).length;
    if (filter == 'Investments') return list.where((a) => a is Map<String, dynamic> && _isInvestmentAccount(a)).length;
    return 0;
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

        // Filter Pills with item counts
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          child: Row(
            children: ['All', 'Banks', 'Credit', 'Investments'].map((filter) {
              final isSel = _selectedAccountFilter == filter;
              final count = _countForFilter(filter, allAccounts);
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilterChip(
                  label: Text('$filter ($count)'),
                  selected: isSel,
                  onSelected: (val) {
                    setState(() => _selectedAccountFilter = filter);
                  },
                  backgroundColor: const Color(0xFF0F172A),
                  selectedColor: const Color(0xFF312E81),
                  labelStyle: TextStyle(
                    fontSize: 12,
                    fontWeight: isSel ? FontWeight.bold : FontWeight.w600,
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
              mainAxisExtent: 126,
            ),
            itemBuilder: (context, index) {
              final acc = filteredAccounts[index];
              final name = (acc['name'] ?? 'Account').toString();
              final balance = parseDouble(acc['balance']);
              final color = _getAccountColor(acc['color'], index);
              final icon = _getAccountIcon(name, acc['accountType']);
              final last4 = (acc['last4Digits'] ?? '').toString().trim();
              final hasLast4 = last4.isNotEmpty && last4.toUpperCase() != 'NONE';

              return InkWell(
                onTap: () => _showAccountDetailSheet(acc),
                borderRadius: BorderRadius.circular(18),
                child: Container(
                  padding: const EdgeInsets.all(13),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: const Color(0xFF1E293B),
                      width: 1.2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.25),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.16),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: color.withValues(alpha: 0.35), width: 1),
                            ),
                            child: Icon(icon, size: 17, color: color),
                          ),
                          if (hasLast4)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1E293B),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: const Color(0xFF334155), width: 0.8),
                              ),
                              child: Text(
                                '••$last4',
                                style: const TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF94A3B8),
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        name,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          letterSpacing: -0.2,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          CurrencyFormatter.formatINR(balance),
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.3,
                            color: balance < 0 ? const Color(0xFFF87171) : const Color(0xFF4ADE80),
                          ),
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

class _UpdateInvestmentValueSheet extends StatefulWidget {
  final Map<String, dynamic> account;
  final String accountName;
  final Color color;
  final IconData icon;
  final List<dynamic> quickViewAccounts;
  final VoidCallback onUpdated;

  const _UpdateInvestmentValueSheet({
    required this.account,
    required this.accountName,
    required this.color,
    required this.icon,
    required this.quickViewAccounts,
    required this.onUpdated,
  });

  @override
  State<_UpdateInvestmentValueSheet> createState() => _UpdateInvestmentValueSheetState();
}

class _UpdateInvestmentValueSheetState extends State<_UpdateInvestmentValueSheet> {
  final ApiClient _api = ApiClient();
  late final TextEditingController _valueController;
  late final TextEditingController _noteController;

  double? _currentBalance;
  bool _isLoadingBalance = false;
  String? _balanceError;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _valueController = TextEditingController();
    _noteController = TextEditingController(text: 'Manual valuation update');
    _resolveInitialBalance();
  }

  @override
  void dispose() {
    _valueController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  void _resolveInitialBalance() {
    final rawBal = widget.account['balance'];
    double? bal = rawBal != null ? parseDouble(rawBal) : null;

    final accountId = (widget.account['walletAccountId'] ?? widget.account['id']).toString();
    final accountName = widget.accountName.toLowerCase().trim();

    // If balance is missing or zero, check if quickViewAccounts has a non-zero balance
    if (bal == null || bal == 0.0) {
      for (final qv in widget.quickViewAccounts) {
        final qvId = (qv['id'] ?? qv['walletAccountId']).toString();
        final qvName = (qv['name'] ?? '').toString().toLowerCase().trim();
        if (qvId == accountId || (accountName.isNotEmpty && qvName == accountName)) {
          final qvBal = parseDouble(qv['balance']);
          if (qvBal != 0.0) {
            bal = qvBal;
            break;
          }
        }
      }
    }

    if (bal != null && bal != 0.0) {
      _currentBalance = bal;
    } else {
      // Fetch live balance asynchronously to guarantee safety
      _fetchLiveBalance();
    }
  }

  Future<void> _fetchLiveBalance() async {
    setState(() {
      _isLoadingBalance = true;
      _balanceError = null;
    });

    try {
      final qv = await _api.getQuickView(forceRefresh: true);
      final accounts = (qv['accounts'] as List<dynamic>?) ?? [];
      final accountId = (widget.account['walletAccountId'] ?? widget.account['id']).toString();
      final accountName = widget.accountName.toLowerCase().trim();

      double? foundBal;
      for (final a in accounts) {
        final aId = (a['id'] ?? a['walletAccountId']).toString();
        final aName = (a['name'] ?? '').toString().toLowerCase().trim();
        if (aId == accountId || (accountName.isNotEmpty && aName == accountName)) {
          foundBal = parseDouble(a['balance']);
          break;
        }
      }

      if (mounted) {
        setState(() {
          _isLoadingBalance = false;
          _currentBalance = foundBal ?? 0.0;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingBalance = false;
          _balanceError = 'Could not fetch live balance from Wallet';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = _valueController.text;
    final cleanText = text.replaceAll(',', '').replaceAll(' ', '').trim();
    final newValue = double.tryParse(cleanText);

    double diff = 0.0;
    bool isIncome = false;
    bool isExpense = false;
    bool isZero = false;
    bool isValid = false;

    if (_currentBalance != null && newValue != null && newValue >= 0) {
      diff = double.parse((newValue - _currentBalance!).toStringAsFixed(2));
      isIncome = diff > 0.001;
      isExpense = diff < -0.001;
      isZero = diff.abs() <= 0.001;
      isValid = !isZero && !_isLoadingBalance;
    }

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Drag Handle
            Center(
              child: Container(
                margin: const EdgeInsets.only(bottom: 16),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade600,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Header
            Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: widget.color.withValues(alpha: 0.2),
                  child: Icon(widget.icon, size: 18, color: widget.color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Update ${widget.accountName} Value',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'Record portfolio gain or loss adjustment',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: Colors.white60, size: 20),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 18),

            // Current Value Card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B).withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF334155)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'CURRENT VALUE',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                          color: Color(0xFF94A3B8),
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Current ledger balance in Wallet',
                        style: TextStyle(fontSize: 11, color: Colors.white54),
                      ),
                    ],
                  ),
                  if (_isLoadingBalance)
                    const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF818CF8)),
                        ),
                        SizedBox(width: 8),
                        Text(
                          'Fetching live balance...',
                          style: TextStyle(fontSize: 12, color: Color(0xFF818CF8)),
                        ),
                      ],
                    )
                  else if (_balanceError != null)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _balanceError!,
                          style: const TextStyle(fontSize: 12, color: Colors.redAccent),
                        ),
                        const SizedBox(width: 4),
                        IconButton(
                          icon: const Icon(Icons.refresh_rounded, size: 16, color: Colors.white70),
                          onPressed: _fetchLiveBalance,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      ],
                    )
                  else
                    Text(
                      CurrencyFormatter.formatINR(_currentBalance ?? 0.0),
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // New Value Input Field
            const Text(
              'NEW VALUE',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: Color(0xFF94A3B8),
              ),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _valueController,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                prefixIcon: const Padding(
                  padding: EdgeInsets.only(left: 14, right: 6),
                  child: Text(
                    '₹',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF818CF8),
                    ),
                  ),
                ),
                prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
                hintText: 'Enter new total balance',
                hintStyle: const TextStyle(fontSize: 15, color: Colors.white38, fontWeight: FontWeight.normal),
                filled: true,
                fillColor: const Color(0xFF090D16),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: Color(0xFF334155), width: 1.2),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: Color(0xFF6366F1), width: 1.6),
                ),
                suffixIcon: text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded, size: 18, color: Colors.white54),
                        onPressed: () {
                          _valueController.clear();
                          setState(() {});
                        },
                      )
                    : null,
              ),
            ),
            const SizedBox(height: 14),

            // Live Difference / Preview Card
            if (newValue != null && isValid) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isIncome
                      ? const Color(0xFF064E3B).withValues(alpha: 0.35)
                      : const Color(0xFF7F1D1D).withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isIncome ? const Color(0xFF059669) : const Color(0xFFDC2626),
                    width: 1.2,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(
                              isIncome ? Icons.trending_up_rounded : Icons.trending_down_rounded,
                              size: 18,
                              color: isIncome ? const Color(0xFF4ADE80) : const Color(0xFFF87171),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '${isIncome ? '+' : '-'}${CurrencyFormatter.formatINR(diff.abs())}',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: isIncome ? const Color(0xFF4ADE80) : const Color(0xFFF87171),
                              ),
                            ),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: isIncome ? const Color(0xFF065F46) : const Color(0xFF991B1B),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            isIncome ? 'INCOME' : 'EXPENSE',
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      isIncome
                          ? 'Creates an Income transaction of +${CurrencyFormatter.formatINR(diff.abs())} under Investments > Investment value update so the ledger balance becomes ${CurrencyFormatter.formatINR(newValue)}.'
                          : 'Creates an Expense transaction of -${CurrencyFormatter.formatINR(diff.abs())} under Investments > Investment value update so the ledger balance becomes ${CurrencyFormatter.formatINR(newValue)}.',
                      style: const TextStyle(fontSize: 11.5, color: Colors.white70, height: 1.3),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
            ] else if (isZero) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B).withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white12),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline_rounded, size: 16, color: Colors.amberAccent),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'New value matches current balance (₹0.00 difference). No transaction needed.',
                        style: TextStyle(fontSize: 12, color: Colors.white70),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
            ],

            // Note Field
            const Text(
              'NOTE (OPTIONAL)',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: Color(0xFF94A3B8),
              ),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _noteController,
              style: const TextStyle(fontSize: 14, color: Colors.white),
              decoration: InputDecoration(
                hintText: 'e.g. Monthly valuation update',
                hintStyle: const TextStyle(fontSize: 13, color: Colors.white38),
                filled: true,
                fillColor: const Color(0xFF090D16),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFF334155), width: 1.0),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFF6366F1), width: 1.4),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Actions
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _isSubmitting ? null : () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      side: const BorderSide(color: Color(0xFF334155)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Cancel', style: TextStyle(color: Colors.white70, fontSize: 14)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    onPressed: (!isValid || _isSubmitting || _isLoadingBalance)
                        ? null
                        : () async {
                            setState(() => _isSubmitting = true);
                            try {
                              final accountId = (widget.account['walletAccountId'] ?? widget.account['id']).toString();
                              final res = await _api.updateInvestmentBalance(
                                accountId: accountId,
                                newValue: newValue!,
                                currentValue: _currentBalance,
                                note: _noteController.text.trim(),
                              );

                              if (context.mounted) {
                                Navigator.pop(context);
                              }

                              final txType = res['transactionType'] ?? (isIncome ? 'income' : 'expense');
                              final diffAmt = parseDouble(res['diff'], fallback: diff).abs();
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Updated ${widget.accountName}! Recorded ${isIncome ? '+' : '-'}${CurrencyFormatter.formatINR(diffAmt)} $txType.',
                                    ),
                                    backgroundColor: isIncome ? const Color(0xFF059669) : const Color(0xFF4338CA),
                                    duration: const Duration(seconds: 4),
                                  ),
                                );
                              }
                              widget.onUpdated();
                            } catch (e) {
                              if (mounted) {
                                setState(() => _isSubmitting = false);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Failed to update value: $e'),
                                    backgroundColor: Colors.red.shade700,
                                  ),
                                );
                              }
                            }
                          },
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF4F46E5),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _isSubmitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Text(
                            'Confirm & Update',
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                          ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
