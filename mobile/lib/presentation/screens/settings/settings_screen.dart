import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../data/datasources/remote/api_client.dart';
import '../../../core/utils/date_formatter.dart';
import '../../providers/theme_provider.dart';
import '../../providers/wallet_provider.dart';
import '../../providers/app_update_provider.dart';
import '../../providers/suggestions_provider.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final ApiClient _api = ApiClient();
  bool _isLoading = true;
  bool _isSyncing = false;

  // Wallet State
  bool _walletConnected = false;
  Map<String, dynamic>? _walletProfile;

  String _accountSearchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings({bool forceRefresh = false}) async {
    final cachedAccounts = ref.read(walletAccountsProvider);
    final needAccounts = cachedAccounts.isEmpty || forceRefresh;

    setState(() => _isLoading = true);
    try {
      final futures = await Future.wait([
        _api.getUserProfile(forceRefresh: forceRefresh),
        needAccounts
            ? _api.getWalletAccounts(includeArchived: false, forceRefresh: forceRefresh)
            : Future.value(cachedAccounts),
        _api.getWalletProfile(forceRefresh: forceRefresh).catchError((_) => <String, dynamic>{}),
      ]);

      final profile = futures[0] as Map<String, dynamic>;
      final accounts = futures[1] as List<dynamic>;
      final walletProfile = futures[2] as Map<String, dynamic>;

      if (mounted) {
        if (needAccounts) {
          ref.read(walletAccountsProvider.notifier).setAccounts(accounts);
        }
        setState(() {
          _walletConnected = profile['walletApiToken'] != null;
          _walletProfile = walletProfile;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading settings: $e')),
        );
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
      Color(0xFF3B82F6),
      Color(0xFF10B981),
      Color(0xFF8B5CF6),
      Color(0xFFF59E0B),
      Color(0xFFEC4899),
      Color(0xFF06B6D4),
      Color(0xFF6366F1),
      Color(0xFF14B8A6),
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

  Future<void> _triggerWalletSync() async {
    setState(() => _isSyncing = true);
    try {
      final res = await _api.syncWallet();
      final freshAccounts = await _api.getWalletAccounts(includeArchived: false, forceRefresh: true);
      final freshCategories = await _api.getWalletCategories(forceRefresh: true);
      ref.read(walletAccountsProvider.notifier).setAccounts(freshAccounts);
      ref.read(walletCategoriesProvider.notifier).setCategories(freshCategories);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Synced ${res['accountsCount']} accounts & ${res['categoriesCount']} categories from Wallet',
            ),
            backgroundColor: Colors.green.shade700,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sync failed: $e'), backgroundColor: Colors.red.shade700),
        );
      }
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  Future<void> _showMapAccountDialog(Map<String, dynamic> account) async {
    final currentLast4 = account['last4Digits'];
    final isCurrentlyNone = currentLast4 == 'NONE';
    final controller = TextEditingController(
      text: (currentLast4 == null || isCurrentlyNone) ? '' : currentLast4.toString(),
    );

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Map "${account['name']}"'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter the last 4 digits of your card/bank account from transaction SMS alerts, or select "Don\'t Map" for cash or offline accounts:',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              keyboardType: TextInputType.text,
              maxLength: 10,
              decoration: InputDecoration(
                labelText: 'Last 4 Digits (e.g. 1234)',
                hintText: isCurrentlyNone ? 'Currently set to Don\'t Map' : null,
                filled: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            if (isCurrentlyNone) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(Icons.check_circle_outline, size: 15, color: Theme.of(ctx).colorScheme.primary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Currently marked as Don\'t Map (Cash / Offline)',
                      style: TextStyle(fontSize: 12, color: Theme.of(ctx).colorScheme.primary, fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
        actions: [
          Row(
            children: [
              OutlinedButton.icon(
                icon: const Icon(Icons.do_not_disturb_on_outlined, size: 16),
                label: const Text("Don't Map"),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Theme.of(ctx).colorScheme.error,
                  side: BorderSide(color: Theme.of(ctx).colorScheme.error.withOpacity(0.5)),
                ),
                onPressed: () => Navigator.pop(ctx, 'DONT_MAP'),
              ),
              const Spacer(),
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
              const SizedBox(width: 4),
              FilledButton(onPressed: () => Navigator.pop(ctx, 'SAVE'), child: const Text('Save')),
            ],
          ),
        ],
      ),
    );

    final accountId = (account['id'] ?? account['walletAccountId']).toString();
    final previousLast4 = account['last4Digits'];

    if (result == 'DONT_MAP') {
      // 1. Immediate optimistic update in shared reactive state
      ref.read(walletAccountsProvider.notifier).updateMapping(accountId, 'NONE');
      ref.read(pendingSuggestionsProvider.notifier).refreshAccountMappings(ref.read(walletAccountsProvider));
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle_outline, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Text('Marked "${account['name']}" as Don\'t Map ✓'),
              ],
            ),
            duration: const Duration(seconds: 2),
            backgroundColor: Colors.green.shade700,
          ),
        );
      }

      // 2. Background persistence (no screen reload or spinner)
      try {
        await _api.mapAccountLast4(accountId, 'NONE');
      } catch (e) {
        // 3. Rollback on failure
        ref.read(walletAccountsProvider.notifier).updateMapping(accountId, previousLast4);
        ref.read(pendingSuggestionsProvider.notifier).refreshAccountMappings(ref.read(walletAccountsProvider));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to update account: $e'),
              backgroundColor: Colors.red.shade700,
            ),
          );
        }
      }
    } else if (result == 'SAVE') {
      final digits = controller.text.trim();
      final newLast4 = digits.isEmpty ? null : digits;

      // 1. Immediate optimistic update in shared reactive state
      ref.read(walletAccountsProvider.notifier).updateMapping(accountId, newLast4);
      ref.read(pendingSuggestionsProvider.notifier).refreshAccountMappings(ref.read(walletAccountsProvider));
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle_outline, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Text(newLast4 == null
                    ? 'Reset mapping for "${account['name']}" ✓'
                    : 'Mapped "${account['name']}" to •••• $newLast4 ✓'),
              ],
            ),
            duration: const Duration(seconds: 2),
            backgroundColor: Colors.green.shade700,
          ),
        );
      }

      // 2. Background persistence (no screen reload or spinner)
      try {
        await _api.mapAccountLast4(accountId, newLast4);
      } catch (e) {
        // 3. Rollback on failure
        ref.read(walletAccountsProvider.notifier).updateMapping(accountId, previousLast4);
        ref.read(pendingSuggestionsProvider.notifier).refreshAccountMappings(ref.read(walletAccountsProvider));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to map account: $e'),
              backgroundColor: Colors.red.shade700,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accounts = ref.watch(walletAccountsProvider);
    final updateState = ref.watch(appUpdateProvider);

    final rateLimit = _walletProfile?['rateLimit'] as Map<String, dynamic>?;
    final remainingCalls = rateLimit?['remaining'] ?? 0;
    final capacityCalls = rateLimit?['capacity'] ?? 1500;
    final syncState = _walletProfile?['syncState'] ?? (_walletConnected ? 'idle' : 'disconnected');

    final filteredAccounts = accounts.where((a) {
      if (_accountSearchQuery.isEmpty) return true;
      final q = _accountSearchQuery.toLowerCase();
      final name = (a['name'] ?? '').toString().toLowerCase();
      final last4 = (a['last4Digits'] ?? '').toString().toLowerCase();
      return name.contains(q) || last4.contains(q);
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings & Configuration'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
              children: [
                // 1. BudgetBakers Wallet Connection & Health Card
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(20),
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
                              CircleAvatar(
                                radius: 16,
                                backgroundColor: theme.colorScheme.primaryContainer,
                                child: Icon(Icons.account_balance_wallet, size: 16, color: theme.colorScheme.primary),
                              ),
                              const SizedBox(width: 10),
                              const Text(
                                'Wallet API Connection',
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: _walletConnected
                                  ? (isDark ? const Color(0xFF064E3B).withOpacity(0.6) : Colors.green.shade50)
                                  : (isDark ? const Color(0xFF7F1D1D).withOpacity(0.6) : Colors.red.shade50),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: _walletConnected
                                    ? (isDark ? Colors.green.shade700 : Colors.green.shade300)
                                    : (isDark ? Colors.red.shade700 : Colors.red.shade300),
                                width: 0.8,
                              ),
                            ),
                            child: Text(
                              _walletConnected ? 'Connected' : 'Disconnected',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: _walletConnected
                                    ? (isDark ? const Color(0xFF4ADE80) : Colors.green.shade800)
                                    : (isDark ? const Color(0xFFF87171) : Colors.red.shade800),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Bank Sync State', style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant)),
                                const SizedBox(height: 2),
                                Row(
                                  children: [
                                    Container(
                                      width: 7,
                                      height: 7,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: syncState == 'syncing'
                                            ? Colors.orangeAccent
                                            : (_walletConnected ? const Color(0xFF4ADE80) : Colors.grey),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      syncState == 'syncing' ? 'Syncing...' : 'Idle / Up to date',
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          if (rateLimit != null)
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('API Quota', style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant)),
                                  const SizedBox(height: 2),
                                  Text(
                                    '$remainingCalls / $capacityCalls left',
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                      if (rateLimit != null) ...[
                        const SizedBox(height: 10),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: capacityCalls > 0 ? (remainingCalls / capacityCalls).clamp(0.0, 1.0) : 1.0,
                            minHeight: 5,
                            backgroundColor: isDark ? Colors.white12 : Colors.grey.shade200,
                            color: remainingCalls < 200
                                ? Colors.redAccent
                                : (remainingCalls < 500 ? Colors.orangeAccent : const Color(0xFF10B981)),
                          ),
                        ),
                      ],
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        height: 44,
                        child: FilledButton.tonalIcon(
                          icon: _isSyncing
                              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.sync, size: 18),
                          label: Text(_isSyncing ? 'Syncing Wallet...' : 'Force Sync Accounts & Categories'),
                          onPressed: _isSyncing ? null : _triggerWalletSync,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // 2. Account Last-4 Digit Mappings Card
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(20),
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
                              CircleAvatar(
                                radius: 16,
                                backgroundColor: theme.colorScheme.primaryContainer,
                                child: Icon(Icons.credit_card, size: 16, color: theme.colorScheme.primary),
                              ),
                              const SizedBox(width: 10),
                              const Text('Account Card Mappings', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                            ],
                          ),
                          Text('${accounts.length} active', style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Map bank accounts & credit cards to their last 4 digits so SMS transactions auto-assign to the correct account.',
                        style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        decoration: InputDecoration(
                          hintText: 'Search active accounts...',
                          prefixIcon: const Icon(Icons.search, size: 18),
                          filled: true,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                        ),
                        onChanged: (val) => setState(() => _accountSearchQuery = val.trim()),
                      ),
                      const SizedBox(height: 8),
                      ...filteredAccounts.map((acc) {
                        final last4 = acc['last4Digits'];
                        final type = (acc['accountType'] ?? 'General').toString();
                        final isNone = last4 == 'NONE';
                        final isMapped = last4 != null && !isNone && last4.toString().trim().isNotEmpty;
                        final accIndex = filteredAccounts.indexOf(acc);
                        final accColor = _getAccountColor(acc['color'], accIndex);
                        final accIcon = _getAccountIcon(acc['name'] ?? '', type);

                        return Card(
                          elevation: 0,
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                            side: BorderSide(
                              color: isDark ? const Color(0xFF334155).withOpacity(0.5) : const Color(0xFFE2E8F0),
                              width: 1,
                            ),
                          ),
                          color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                            leading: CircleAvatar(
                              radius: 17,
                              backgroundColor: accColor.withOpacity(0.18),
                              child: Icon(accIcon, size: 17, color: accColor),
                            ),
                            title: Text(
                              acc['name'] ?? 'Account',
                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                            ),
                            subtitle: Text(
                              type,
                              style: TextStyle(fontSize: 11.5, color: theme.colorScheme.onSurfaceVariant),
                            ),
                            trailing: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: isNone
                                    ? (isDark ? Colors.white10 : Colors.grey.shade100)
                                    : (isMapped
                                        ? (isDark ? const Color(0xFF064E3B).withOpacity(0.5) : Colors.green.shade50)
                                        : (isDark ? const Color(0xFF78350F).withOpacity(0.5) : Colors.orange.shade50)),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: isNone
                                      ? (isDark ? Colors.white24 : Colors.grey.shade300)
                                      : (isMapped
                                          ? (isDark ? Colors.green.shade700 : Colors.green.shade300)
                                          : (isDark ? Colors.orange.shade700 : Colors.orange.shade300)),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (isNone) ...[
                                    Icon(Icons.block, size: 12, color: isDark ? Colors.white70 : Colors.grey.shade700),
                                    const SizedBox(width: 4),
                                  ],
                                  Text(
                                    isNone
                                        ? "Don't Map"
                                        : (isMapped ? '•••• $last4' : 'Tap to Map'),
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.bold,
                                      color: isNone
                                          ? (isDark ? Colors.white70 : Colors.grey.shade700)
                                          : (isMapped
                                              ? (isDark ? const Color(0xFF4ADE80) : Colors.green.shade800)
                                              : (isDark ? const Color(0xFFFBBF24) : Colors.orange.shade800)),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            onTap: () => _showMapAccountDialog(acc),
                          ),
                        );
                      }),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // 5. App Updates & Version Card
                _buildAppUpdatesCard(theme, isDark, updateState),

                const SizedBox(height: 36),
              ],
            ),
    );
  }

  Widget _buildAppUpdatesCard(ThemeData theme, bool isDark, AppUpdateState updateState) {
    final info = updateState.updateInfo;
    final isAvailable = info != null && info.isUpdateAvailable;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
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
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: theme.colorScheme.primaryContainer,
                    child: Icon(Icons.system_update_rounded, size: 16, color: theme.colorScheme.primary),
                  ),
                  const SizedBox(width: 10),
                  const Text('App Updates', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: isDark ? Colors.white10 : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: isDark ? Colors.white24 : Colors.grey.shade300),
                ),
                child: Text(
                  'v${updateState.currentVersion}',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Keep WalletPro up to date with the latest features, improvements, and fixes directly within the app.',
            style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 14),

          // If an update is available
          if (isAvailable) ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.amber.shade900.withOpacity(isDark ? 0.2 : 0.08),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.amber.shade600.withOpacity(0.4)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.new_releases_rounded, size: 18, color: Colors.amber.shade600),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'New Version Available: ${info.tagName}',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: isDark ? Colors.amber.shade200 : Colors.amber.shade900,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (info.changelog.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Container(
                      constraints: const BoxConstraints(maxHeight: 120),
                      child: SingleChildScrollView(
                        child: Text(
                          info.changelog,
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.onSurfaceVariant,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),

                  if (updateState.isDownloading) ...[
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Downloading APK update...',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: theme.colorScheme.primary),
                            ),
                            Text(
                              '${(updateState.downloadProgress * 100).toStringAsFixed(0)}%',
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: updateState.downloadProgress > 0 ? updateState.downloadProgress : null,
                            minHeight: 6,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '${(updateState.receivedBytes / 1024 / 1024).toStringAsFixed(1)} MB / ${(updateState.totalBytes / 1024 / 1024).toStringAsFixed(1)} MB',
                              style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant),
                            ),
                            InkWell(
                              onTap: () => ref.read(appUpdateProvider.notifier).cancelDownload(),
                              child: Text(
                                'Cancel',
                                style: TextStyle(fontSize: 11, color: theme.colorScheme.error, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ] else if (updateState.isDownloaded) ...[
                    FilledButton.icon(
                      icon: const Icon(Icons.install_mobile_rounded, size: 18),
                      label: Text('Install Update (${info.tagName})'),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.green.shade700,
                        minimumSize: const Size.fromHeight(42),
                      ),
                      onPressed: () => ref.read(appUpdateProvider.notifier).installUpdate(),
                    ),
                  ] else ...[
                    FilledButton.icon(
                      icon: const Icon(Icons.download_rounded, size: 18),
                      label: Text(
                        info.apkSize > 0
                            ? 'Download & Install (${(info.apkSize / 1024 / 1024).toStringAsFixed(1)} MB)'
                            : 'Download & Install Update',
                      ),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(42),
                      ),
                      onPressed: () => ref.read(appUpdateProvider.notifier).downloadAndInstall(),
                    ),
                  ],
                ],
              ),
            ),
          ] else ...[
            // Up to date state
            Row(
              children: [
                Icon(Icons.check_circle_rounded, size: 20, color: Colors.green.shade600),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'WalletPro is up to date',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                      if (updateState.lastChecked != null)
                        Text(
                          'Checked ${DateFormatter.formatFull(updateState.lastChecked!)}',
                          style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant),
                        ),
                    ],
                  ),
                ),
                OutlinedButton.icon(
                  icon: updateState.isChecking
                      ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.refresh, size: 14),
                  label: Text(updateState.isChecking ? 'Checking...' : 'Check'),
                  onPressed: updateState.isChecking
                      ? null
                      : () => ref.read(appUpdateProvider.notifier).checkForUpdate(userInitiated: true),
                ),
              ],
            ),
          ],

          if (updateState.errorMessage != null) ...[
            const SizedBox(height: 8),
            Text(
              updateState.errorMessage!,
              style: TextStyle(fontSize: 12, color: theme.colorScheme.error),
            ),
          ],

          const Divider(height: 24),

          // Auto-check switch
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text('Auto-check for updates', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            subtitle: const Text('Notify when a new version is released', style: TextStyle(fontSize: 11)),
            value: updateState.autoCheckEnabled,
            onChanged: (val) {
              ref.read(appUpdateProvider.notifier).setAutoCheckEnabled(val);
            },
          ),
        ],
      ),
    );
  }
}
