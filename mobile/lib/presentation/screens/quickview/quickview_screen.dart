import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../core/utils/account_sorter.dart';
import '../../../data/datasources/remote/api_client.dart';
import '../../providers/wallet_provider.dart';
import '../../widgets/skeleton_loader.dart';

class QuickViewScreen extends ConsumerStatefulWidget {
  const QuickViewScreen({super.key});

  @override
  ConsumerState<QuickViewScreen> createState() => _QuickViewScreenState();
}

class _QuickViewScreenState extends ConsumerState<QuickViewScreen> {
  final ApiClient _api = ApiClient();

  bool _isLoading = true;
  bool _isRefreshing = false;
  String? _errorMessage;

  List<dynamic> _recentRecords = [];
  Map<String, dynamic> _summary = {
    'totalAssets': 0.0,
    'totalLiabilities': 0.0,
    'netWorth': 0.0,
    'accountsCount': 0,
  };

  @override
  void initState() {
    super.initState();
    final existingAccounts = ref.read(walletAccountsProvider);
    if (existingAccounts.isNotEmpty) {
      _isLoading = false;
    }
    _loadQuickViewData(showRefreshing: existingAccounts.isNotEmpty);
  }

  Future<void> _loadQuickViewData({bool showRefreshing = false}) async {
    if (showRefreshing) {
      setState(() => _isRefreshing = true);
    } else {
      setState(() => _isLoading = true);
    }

    try {
      final data = await _api.getQuickView();
      if (mounted) {
        final accounts = (data['accounts'] as List<dynamic>?) ?? [];
        AccountSorter.sortAccounts(accounts);
        ref.read(walletAccountsProvider.notifier).setAccounts(accounts);

        setState(() {
          _recentRecords = (data['recentRecords'] as List<dynamic>?) ?? [];
          _summary = (data['summary'] as Map<String, dynamic>?) ?? _summary;
          _errorMessage = null;
          _isLoading = false;
          _isRefreshing = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to load accounts: $e';
          _isLoading = false;
          _isRefreshing = false;
        });
      }
    }
  }

  Color _parseAccountColor(dynamic colorValue, String name, int index) {
    if (colorValue != null && colorValue is String && colorValue.isNotEmpty) {
      try {
        String hex = colorValue.replaceAll('#', '').trim();
        if (hex.length == 6) hex = 'FF$hex';
        if (hex.length == 8) return Color(int.parse('0x$hex'));
      } catch (_) {}
    }

    // Fallback palette matching the screenshot
    final fallbackPalette = [
      const Color(0xFFFF1744), // Pinkish red (HDFC sb)
      const Color(0xFF00BCD4), // Cyan (SBI sb)
      const Color(0xFF009688), // Teal (Cash)
      const Color(0xFF00ACC1), // Deep cyan (Mutual funds)
      const Color(0xFF1E88E5), // Blue (Zerodha)
      const Color(0xFF9C27B0), // Purple (NPS)
      const Color(0xFF673AB7), // Deep purple (Upstox)
      const Color(0xFFFF9800), // Orange (EPF)
      const Color(0xFF455A64), // Slate (Amazon Pay)
      const Color(0xFF37474F), // Dark slate (Flipkart GC)
      const Color(0xFF5E35B1), // Purple (SBI cashback)
      const Color(0xFF7B1FA2), // Violet (Tata Neu)
      const Color(0xFFE91E63), // Pink red (HSBC Live+)
      const Color(0xFF880E4F), // Dark pink (Axis Flipkart)
      const Color(0xFFFB8C00), // Orange (Swiggy HDFC)
      const Color(0xFF4A148C), // Deep violet (Jupiter Edge)
      const Color(0xFF263238), // Charcoal (Cred indusind)
      const Color(0xFF1A237E), // Dark Navy (Amazon ICICI)
      const Color(0xFF0288D1), // Light blue (Ola SBI)
      const Color(0xFF00695C), // Dark teal (IDFC wealth)
      const Color(0xFF1565C0), // Blue (Axis Rewards)
      const Color(0xFF6A1B9A), // Purple (PhonePe)
      const Color(0xFFE65100), // Deep orange (Fastag)
      const Color(0xFFC2185B), // Pink (Axis forex)
      const Color(0xFF0D47A1), // Navy (LIC)
      const Color(0xFF212121), // Dark grey (ICICI platinum)
    ];

    return fallbackPalette[index % fallbackPalette.length];
  }

  IconData _getAccountIcon(String name, String? accountType) {
    final lower = name.toLowerCase();
    final typeLower = (accountType ?? '').toLowerCase();

    if (typeLower.contains('credit') ||
        lower.contains('credit') ||
        lower.contains('card') ||
        lower.contains('cashback') ||
        lower.contains('platinum') ||
        lower.contains('rewards') ||
        lower.contains('neu') ||
        lower.contains('live+') ||
        lower.contains('edge') ||
        lower.contains('flipkart') && !lower.contains('gc')) {
      return Icons.credit_card;
    }
    if (lower.contains('mutual') ||
        lower.contains('fund') ||
        lower.contains('zerodha') ||
        lower.contains('upstox') ||
        lower.contains('groww') ||
        lower.contains('stock') ||
        lower.contains('shares')) {
      return Icons.insights;
    }
    if (lower.contains('nps') || lower.contains('epf') || lower.contains('ppf') || lower.contains('pension')) {
      return Icons.pie_chart_outline;
    }
    if (lower.contains('cash')) {
      return Icons.payments_outlined;
    }
    if (lower.contains('pay') ||
        lower.contains('wallet') ||
        lower.contains('phonepe') ||
        lower.contains('paytm') ||
        lower.contains('gc') ||
        lower.contains('gift')) {
      return Icons.account_balance_wallet_outlined;
    }
    if (lower.contains('fastag') || lower.contains('car')) {
      return Icons.directions_car_outlined;
    }
    if (lower.contains('lic') || lower.contains('insurance')) {
      return Icons.shield_outlined;
    }
    if (lower.contains('sb') || lower.contains('savings')) {
      return Icons.savings_outlined;
    }
    return Icons.account_balance_outlined;
  }

  void _showReorderAccountsModal() {
    final currentAccounts = ref.read(walletAccountsProvider);
    final reorderList = List<dynamic>.from(currentAccounts);
    final previousList = List<dynamic>.from(currentAccounts);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E1E22),
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
                            // Frame 0 optimistic update in Riverpod shared provider
                            ref.read(walletAccountsProvider.notifier).reorder(orderIds);
                            try {
                              await _api.saveAccountOrder(orderIds);
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Account order saved!'), backgroundColor: Colors.green),
                                );
                              }
                            } catch (e) {
                              // Rollback on failure
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
                    child: Theme(
                      data: Theme.of(context).copyWith(
                        canvasColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                      ),
                      child: ReorderableListView.builder(
                        itemCount: reorderList.length,
                        onReorder: (oldIndex, newIndex) {
                          setModalState(() {
                            if (oldIndex < newIndex) {
                              newIndex -= 1;
                            }
                            final item = reorderList.removeAt(oldIndex);
                            reorderList.insert(newIndex, item);
                          });
                        },
                        itemBuilder: (context, index) {
                          final a = reorderList[index];
                          final name = a['name'] ?? 'Account';
                          final balance = (a['balance'] is num) ? (a['balance'] as num).toDouble() : 0.0;
                          final color = _parseAccountColor(a['color'], name, index);

                          return ListTile(
                            key: ValueKey(a['walletAccountId'] ?? a['id'] ?? index),
                            leading: CircleAvatar(
                              radius: 12,
                              backgroundColor: color,
                            ),
                            title: Text(
                              name,
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                            ),
                            subtitle: Text(
                              CurrencyFormatter.formatINR(balance),
                              style: TextStyle(
                                color: balance < 0 ? Colors.red.shade300 : Colors.green.shade300,
                                fontSize: 12,
                              ),
                            ),
                            trailing: const Icon(Icons.drag_handle, color: Colors.white54),
                          );
                        },
                      ),
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

  void _showAccountDetailsModal(Map<String, dynamic> account) {
    final name = account['name'] ?? 'Account';
    final balance = (account['balance'] is num) ? (account['balance'] as num).toDouble() : 0.0;
    final last4 = account['last4Digits'];
    final hasLast4 = last4 != null && last4 != 'NONE' && last4.toString().trim().isNotEmpty;
    final type = account['accountType'] ?? 'General';
    final isNegative = balance < 0;

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E22),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
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
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      name,
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                  ),
                  Text(
                    CurrencyFormatter.formatINR(balance),
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: isNegative ? Colors.red.shade400 : Colors.green.shade400,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Type: $type${hasLast4 ? ' • Card Last 4: $last4' : ''}',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade400),
              ),
              const Divider(color: Colors.white12, height: 28),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  backgroundColor: Colors.blue.shade900.withOpacity(0.5),
                  child: const Icon(Icons.list_alt, color: Colors.blueAccent),
                ),
                title: const Text('View Pending Reviews for this Account', style: TextStyle(color: Colors.white)),
                subtitle: const Text('Check unreviewed SMS suggestions', style: TextStyle(color: Colors.grey, fontSize: 12)),
                trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
                onTap: () {
                  Navigator.pop(ctx);
                  context.push('/suggestions');
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  backgroundColor: Colors.purple.shade900.withOpacity(0.5),
                  child: const Icon(Icons.history, color: Colors.purpleAccent),
                ),
                title: const Text('View Wallet Records', style: TextStyle(color: Colors.white)),
                subtitle: const Text('Recent transactions posted in BudgetBakers', style: TextStyle(color: Colors.grey, fontSize: 12)),
                trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
                onTap: () {
                  Navigator.pop(ctx);
                  _showRecordsModal(accountId: account['walletAccountId'] ?? account['id'], accountName: name);
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  backgroundColor: Colors.teal.shade900.withOpacity(0.5),
                  child: const Icon(Icons.edit, color: Colors.tealAccent),
                ),
                title: const Text('Edit Card Mapping (Last 4)', style: TextStyle(color: Colors.white)),
                subtitle: const Text('Map SMS bank identifier to this Wallet account', style: TextStyle(color: Colors.grey, fontSize: 12)),
                trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
                onTap: () {
                  Navigator.pop(ctx);
                  context.push('/settings');
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _showRecordsModal({String? accountId, String? accountName}) async {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E1E22),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.75,
          minChildSize: 0.4,
          maxChildSize: 0.95,
          expand: false,
          builder: (_, scrollController) {
            return FutureBuilder<List<dynamic>>(
              future: accountId != null
                  ? _api.getWalletRecords(limit: 30, accountId: accountId)
                  : Future.value(_recentRecords),
              builder: (context, snapshot) {
                return Column(
                  children: [
                    const SizedBox(height: 12),
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
                          Text(
                            accountName != null ? '$accountName Records' : 'Recent Wallet Records',
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, color: Colors.white70),
                            onPressed: () => Navigator.pop(ctx),
                          ),
                        ],
                      ),
                    ),
                    const Divider(color: Colors.white12),
                    Expanded(
                      child: snapshot.connectionState == ConnectionState.waiting
                          ? const Center(child: CircularProgressIndicator())
                          : snapshot.hasError
                              ? Center(
                                  child: Padding(
                                    padding: const EdgeInsets.all(24),
                                    child: Text('Error loading records: ${snapshot.error}', style: const TextStyle(color: Colors.redAccent)),
                                  ),
                                )
                              : (snapshot.data == null || snapshot.data!.isEmpty)
                                  ? const Center(
                                      child: Padding(
                                        padding: EdgeInsets.all(24),
                                        child: Text('No records found', style: TextStyle(color: Colors.white54)),
                                      ),
                                    )
                                  : ListView.separated(
                                      controller: scrollController,
                                      itemCount: snapshot.data!.length,
                                      separatorBuilder: (_, __) => const Divider(color: Colors.white10, height: 1),
                                      itemBuilder: (_, index) {
                                        final rec = snapshot.data![index];
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
                                            backgroundColor: isExp ? Colors.red.shade900.withOpacity(0.4) : Colors.green.shade900.withOpacity(0.4),
                                            child: Icon(
                                              isExp ? Icons.arrow_upward : Icons.arrow_downward,
                                              color: isExp ? Colors.red.shade300 : Colors.green.shade300,
                                              size: 18,
                                            ),
                                          ),
                                          title: Text(party, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
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
                                    ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  void _showAddAccountDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF222226),
        title: const Text('Add Account', style: TextStyle(color: Colors.white)),
        content: const Text(
          'To add a new bank account or credit card:\n\n1. Open BudgetBakers Wallet app\n2. Add the account under Accounts\n3. Return here and tap "Sync Wallet" to refresh your accounts in WalletPro!',
          style: TextStyle(color: Colors.white70, fontSize: 14, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Got it', style: TextStyle(color: Colors.blueAccent)),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: Colors.blueAccent),
            icon: const Icon(Icons.sync, size: 16),
            label: const Text('Sync Wallet Now'),
            onPressed: () async {
              Navigator.pop(ctx);
              await _syncWallet();
            },
          ),
        ],
      ),
    );
  }

  Future<void> _syncWallet() async {
    setState(() => _isRefreshing = true);
    try {
      await _api.syncWallet();
      await _loadQuickViewData(showRefreshing: true);
      final freshCategories = await _api.getWalletCategories(forceRefresh: true);
      ref.read(walletCategoriesProvider.notifier).setCategories(freshCategories);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Wallet accounts synchronized successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sync failed: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isRefreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Dark theme matching the user's screenshot
    const bgColor = Color(0xFF141416);
    const cardDarkColor = Color(0xFF1C1C1F);
    final accounts = ref.watch(walletAccountsProvider);

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.menu, color: Colors.white),
          onPressed: () {
            // Open quick navigation bottom sheet
            showModalBottomSheet(
              context: context,
              backgroundColor: const Color(0xFF1E1E22),
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              builder: (ctx) => SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ListTile(
                        leading: const Icon(Icons.home_outlined, color: Colors.white),
                        title: const Text('Home Dashboard', style: TextStyle(color: Colors.white)),
                        onTap: () {
                          Navigator.pop(ctx);
                          context.go('/');
                        },
                      ),
                      ListTile(
                        leading: const Icon(Icons.list_alt, color: Colors.white),
                        title: const Text('Review Transactions', style: TextStyle(color: Colors.white)),
                        onTap: () {
                          Navigator.pop(ctx);
                          context.push('/suggestions');
                        },
                      ),
                      ListTile(
                        leading: const Icon(Icons.settings_outlined, color: Colors.white),
                        title: const Text('Settings', style: TextStyle(color: Colors.white)),
                        onTap: () {
                          Navigator.pop(ctx);
                          context.push('/settings');
                        },
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
        title: const Text(
          'Home',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        actions: [
          // Notification Bell with red dot
          Stack(
            alignment: Alignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.notifications_none, color: Colors.white, size: 26),
                onPressed: () {
                  context.push('/suggestions');
                },
              ),
              Positioned(
                top: 14,
                right: 14,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: Colors.redAccent,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ],
          ),
          IconButton(
            icon: _isRefreshing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                  )
                : const Icon(Icons.refresh, color: Colors.white),
            onPressed: _isRefreshing ? null : () => _loadQuickViewData(showRefreshing: true),
          ),
        ],
      ),
      body: _isLoading
          ? const QuickViewSkeleton()
          : _errorMessage != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.cloud_off, size: 56, color: Colors.redAccent),
                        const SizedBox(height: 16),
                        Text(_errorMessage!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: () => _loadQuickViewData(),
                          icon: const Icon(Icons.refresh),
                          label: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              : _buildAccountsTab(cardDarkColor, accounts),
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFF64B5F6), // Light blue matching screenshot
        foregroundColor: Colors.white,
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: const Icon(Icons.add, size: 28),
        onPressed: () {
          // Quick actions menu
          showModalBottomSheet(
            context: context,
            backgroundColor: const Color(0xFF1E1E22),
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            builder: (ctx) => SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ListTile(
                      leading: const Icon(Icons.rate_review, color: Colors.blueAccent),
                      title: const Text('Review SMS Transactions', style: TextStyle(color: Colors.white)),
                      subtitle: const Text('Approve or reject pending suggestions', style: TextStyle(color: Colors.grey, fontSize: 12)),
                      onTap: () {
                        Navigator.pop(ctx);
                        context.push('/suggestions');
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.sync, color: Colors.greenAccent),
                      title: const Text('Sync Wallet Accounts', style: TextStyle(color: Colors.white)),
                      subtitle: const Text('Fetch latest accounts and balances from BudgetBakers', style: TextStyle(color: Colors.grey, fontSize: 12)),
                      onTap: () {
                        Navigator.pop(ctx);
                        _syncWallet();
                      },
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildAccountsTab(Color cardDarkColor, List<dynamic> accounts) {
    return RefreshIndicator(
      onRefresh: () => _loadQuickViewData(showRefreshing: true),
      color: Colors.white,
      backgroundColor: cardDarkColor,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 100),
        children: [
          // Section Title: My Accounts in Wallet + Reorder & '>' Buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'My Accounts in Wallet',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  letterSpacing: -0.2,
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.swap_vert, color: Colors.white70, size: 20),
                    tooltip: 'Reorder accounts',
                    onPressed: _showReorderAccountsModal,
                  ),
                  InkWell(
                    onTap: _showReorderAccountsModal,
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.08),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.chevron_right, color: Colors.white70, size: 20),
                    ),
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 12),

          // 3-Column Accounts Grid
          _buildAccountsGrid(accounts),

          const SizedBox(height: 12),

          // Right aligned [ ≡ Records ] Button
          Align(
            alignment: Alignment.centerRight,
            child: InkWell(
              onTap: () => _showRecordsModal(),
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF222228),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white12),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.format_list_bulleted, color: Colors.lightBlueAccent, size: 16),
                    SizedBox(width: 6),
                    Text(
                      'Records',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Action Chips Row (Horizontal Scroll)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildActionChip(
                  icon: Icons.trending_up,
                  label: 'Balance',
                  onTap: () {
                    // Scroll to Balance Trend
                  },
                ),
                const SizedBox(width: 8),
                _buildActionChip(
                  icon: Icons.file_upload_outlined,
                  label: 'Exports',
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Exporting records to CSV... (Coming soon)')),
                    );
                  },
                ),
                const SizedBox(width: 8),
                _buildActionChip(
                  icon: Icons.business_center_outlined,
                  label: 'Investments',
                  onTap: () {
                    // Filter investment accounts
                    final investAccounts = accounts.where((a) {
                      final name = (a['name'] ?? '').toString().toLowerCase();
                      return name.contains('mutual') ||
                          name.contains('zerodha') ||
                          name.contains('nps') ||
                          name.contains('upstox') ||
                          name.contains('epf');
                    }).toList();

                    showDialog(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        backgroundColor: const Color(0xFF222226),
                        title: const Text('Investment Accounts', style: TextStyle(color: Colors.white)),
                        content: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: investAccounts.map((a) {
                            final b = (a['balance'] is num) ? (a['balance'] as num).toDouble() : 0.0;
                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(a['name'] ?? '', style: const TextStyle(color: Colors.white)),
                              trailing: Text(CurrencyFormatter.formatINR(b), style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold)),
                            );
                          }).toList(),
                        ),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
                        ],
                      ),
                    );
                  },
                ),
                const SizedBox(width: 8),
                _buildActionChip(
                  icon: Icons.sync,
                  label: 'Sync Wallet',
                  onTap: _syncWallet,
                ),
              ],
            ),
          ),

          const SizedBox(height: 22),

          // Section: Balance Trend with 3-dot menu
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Balance Trend',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  letterSpacing: -0.2,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.more_vert, color: Colors.white70),
                onPressed: () {
                  showModalBottomSheet(
                    context: context,
                    backgroundColor: const Color(0xFF1E1E22),
                    builder: (ctx) => Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ListTile(
                          leading: const Icon(Icons.refresh, color: Colors.white),
                          title: const Text('Refresh Balance Trend', style: TextStyle(color: Colors.white)),
                          onTap: () {
                            Navigator.pop(ctx);
                            _loadQuickViewData(showRefreshing: true);
                          },
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),

          const SizedBox(height: 8),

          // Balance Trend Summary Card
          _buildBalanceTrendCard(accounts),

          const SizedBox(height: 60), // Spacing for FAB
        ],
      ),
    );
  }

  Widget _buildAccountsGrid(List<dynamic> accounts) {
    final itemCount = accounts.length + 1; // +1 for "Add account +"

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 1.15,
      ),
      itemCount: itemCount,
      itemBuilder: (context, index) {
        if (index == accounts.length) {
          // "Add account +" Tile
          return InkWell(
            onTap: _showAddAccountDialog,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF1C1C20),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white12),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    'Add\naccount',
                    style: TextStyle(
                      color: Color(0xFF90CAF9),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      height: 1.2,
                    ),
                  ),
                  Icon(Icons.add, color: Color(0xFF90CAF9), size: 20),
                ],
              ),
            ),
          );
        }

        final acc = accounts[index];
        final name = acc['name'] ?? 'Account';
        final rawBal = acc['balance'];
        final double balance = (rawBal is num) ? rawBal.toDouble() : (double.tryParse(rawBal?.toString() ?? '0') ?? 0.0);
        final color = _parseAccountColor(acc['color'], name, index);
        final icon = _getAccountIcon(name, acc['accountType']);

        return InkWell(
          onTap: () => _showAccountDetailsModal(acc),
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(10),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Top: Icon + Name
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Icon(icon, color: Colors.white, size: 14),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),

                // Bottom: Balance
                Text(
                  CurrencyFormatter.formatINR(balance),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: -0.2,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildActionChip({required IconData icon, required String label, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF222228),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: Colors.tealAccent),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(fontSize: 13, color: Colors.white, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBalanceTrendCard(List<dynamic> accounts) {
    final assets = (_summary['totalAssets'] is num) ? (_summary['totalAssets'] as num).toDouble() : 0.0;
    final liabilities = (_summary['totalLiabilities'] is num) ? (_summary['totalLiabilities'] as num).toDouble() : 0.0;
    final netWorth = (_summary['netWorth'] is num) ? (_summary['netWorth'] as num).toDouble() : 0.0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E22),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Total Net Worth', style: TextStyle(color: Colors.white70, fontSize: 13)),
                  const SizedBox(height: 4),
                  Text(
                    CurrencyFormatter.formatINR(netWorth),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.green.shade900.withOpacity(0.4),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.arrow_upward, size: 14, color: Colors.green.shade400),
                    const SizedBox(width: 2),
                    Text(
                      '${accounts.length} Accounts',
                      style: TextStyle(color: Colors.green.shade400, fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const Divider(color: Colors.white12, height: 24),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(width: 8, height: 8, decoration: const BoxDecoration(color: Colors.greenAccent, shape: BoxShape.circle)),
                        const SizedBox(width: 6),
                        const Text('Assets', style: TextStyle(color: Colors.white60, fontSize: 12)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      CurrencyFormatter.formatINR(assets),
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(width: 8, height: 8, decoration: const BoxDecoration(color: Colors.redAccent, shape: BoxShape.circle)),
                        const SizedBox(width: 6),
                        const Text('Liabilities', style: TextStyle(color: Colors.white60, fontSize: 12)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '-${CurrencyFormatter.formatINR(liabilities)}',
                      style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
