import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../data/datasources/local/notification_service.dart';
import '../../../data/datasources/remote/api_client.dart';
import '../../../core/utils/date_formatter.dart';
import '../../providers/theme_provider.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final ApiClient _api = ApiClient();
  bool _isLoading = true;
  bool _isSyncing = false;
  bool _notifListenerEnabled = false;

  // Wallet State
  List<dynamic> _accounts = [];
  bool _walletConnected = false;
  Map<String, dynamic>? _walletProfile;

  String _accountSearchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    setState(() => _isLoading = true);
    try {
      final futures = await Future.wait([
        _api.getUserProfile(),
        _api.getWalletAccounts(includeArchived: false),
        _api.getWalletProfile().catchError((_) => <String, dynamic>{}),
        NotificationService.isNotificationListenerEnabled(),
      ]);

      final profile = futures[0] as Map<String, dynamic>;
      final accounts = futures[1] as List<dynamic>;
      final walletProfile = futures[2] as Map<String, dynamic>;
      final notifEnabled = futures[3] as bool;

      if (mounted) {
        setState(() {
          _walletConnected = profile['walletApiToken'] != null;
          _accounts = accounts;
          _walletProfile = walletProfile;
          _notifListenerEnabled = notifEnabled;
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

  Future<void> _triggerWalletSync() async {
    setState(() => _isSyncing = true);
    try {
      final res = await _api.syncWallet();
      await _loadSettings();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Synced ${res['accountsCount']} accounts & ${res['categoriesCount']} categories from Wallet',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sync failed: $e')),
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

    if (result == 'DONT_MAP') {
      try {
        await _api.mapAccountLast4(account['id'], 'NONE');
        await _loadSettings();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Marked "${account['name']}" as Don\'t Map')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to update account: $e')),
          );
        }
      }
    } else if (result == 'SAVE') {
      final digits = controller.text.trim();
      try {
        await _api.mapAccountLast4(account['id'], digits.isEmpty ? null : digits);
        await _loadSettings();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(digits.isEmpty
                  ? 'Reset mapping for ${account['name']}'
                  : 'Mapped ${account['name']} to •••• $digits'),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to map account: $e')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final currentThemeMode = ref.watch(themeModeProvider);

    final rateLimit = _walletProfile?['rateLimit'] as Map<String, dynamic>?;
    final remainingCalls = rateLimit?['remaining'] ?? 0;
    final capacityCalls = rateLimit?['capacity'] ?? 1500;
    final syncState = _walletProfile?['syncState'] ?? (_walletConnected ? 'idle' : 'disconnected');

    final filteredAccounts = _accounts.where((a) {
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
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: _walletConnected ? Colors.green.shade50 : Colors.red.shade50,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              _walletConnected ? 'Connected' : 'Disconnected',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: _walletConnected ? Colors.green.shade800 : Colors.red.shade800,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Bank Sync State', style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant)),
                                const SizedBox(height: 2),
                                Text(
                                  syncState == 'syncing' ? 'Syncing...' : 'Idle / Up to date',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
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

                // 2. App Theme Mode Preference Card
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
                        children: [
                          CircleAvatar(
                            radius: 16,
                            backgroundColor: theme.colorScheme.secondaryContainer,
                            child: Icon(Icons.palette_outlined, size: 16, color: theme.colorScheme.secondary),
                          ),
                          const SizedBox(width: 10),
                          const Text('App Appearance', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          _buildThemeOption(
                            label: 'System',
                            icon: Icons.brightness_auto,
                            isSelected: currentThemeMode == ThemeMode.system,
                            onTap: () => ref.read(themeModeProvider.notifier).setThemeMode(ThemeMode.system),
                            theme: theme,
                          ),
                          const SizedBox(width: 8),
                          _buildThemeOption(
                            label: 'Light',
                            icon: Icons.light_mode_outlined,
                            isSelected: currentThemeMode == ThemeMode.light,
                            onTap: () => ref.read(themeModeProvider.notifier).setThemeMode(ThemeMode.light),
                            theme: theme,
                          ),
                          const SizedBox(width: 8),
                          _buildThemeOption(
                            label: 'Dark',
                            icon: Icons.dark_mode_outlined,
                            isSelected: currentThemeMode == ThemeMode.dark,
                            onTap: () => ref.read(themeModeProvider.notifier).setThemeMode(ThemeMode.dark),
                            theme: theme,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // 3. Automations & Alerts Card
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
                        children: [
                          CircleAvatar(
                            radius: 16,
                            backgroundColor: theme.colorScheme.primaryContainer,
                            child: Icon(Icons.bolt, size: 16, color: theme.colorScheme.primary),
                          ),
                          const SizedBox(width: 10),
                          const Text('Automations & Alerts', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 14),

                      // Feature 1: Real-time SMS Detection
                      Row(
                        children: [
                          Icon(Icons.mark_email_read_outlined, size: 20, color: theme.colorScheme.primary),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Real-time SMS Scanning', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                                Text('Auto-ingests incoming bank messages (from Sep 1, 2026)', style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant)),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.green.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.green.shade300, width: 0.8),
                            ),
                            child: Text('Active', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.green.shade900)),
                          ),
                        ],
                      ),
                      const Divider(height: 24),

                      // Feature 2: 4-Hour Review Reminder
                      Row(
                        children: [
                          Icon(Icons.alarm, size: 20, color: theme.colorScheme.primary),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('4-Hour Review Reminders', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                                Text('Alerts every 4 hours only if reviews are pending', style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant)),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.blue.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.blue.shade300, width: 0.8),
                            ),
                            child: Text('Every 4 hrs', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blue.shade900)),
                          ),
                        ],
                      ),
                      const Divider(height: 24),

                      // Feature 3: Notification Listener (UPI & Bank App Push Alerts)
                      Row(
                        children: [
                          Icon(Icons.notifications_active_outlined, size: 20, color: theme.colorScheme.primary),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('UPI & Banking Push Alerts', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                                Text('Auto-captures GPay, PhonePe, Paytm, CRED & bank push notifications', style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant)),
                              ],
                            ),
                          ),
                          OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              side: BorderSide(
                                color: _notifListenerEnabled ? Colors.green : theme.colorScheme.primary,
                              ),
                            ),
                            onPressed: () async {
                              await NotificationService.openNotificationListenerSettings();
                              final enabled = await NotificationService.isNotificationListenerEnabled();
                              if (mounted) setState(() => _notifListenerEnabled = enabled);
                            },
                            child: Text(
                              _notifListenerEnabled ? 'Active ✓' : 'Grant Access',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: _notifListenerEnabled ? Colors.green.shade800 : theme.colorScheme.primary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // 4. Account Last-4 Digit Mappings Card
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
                          Text('${_accounts.length} active', style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant)),
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
                        final type = acc['accountType'] ?? 'General';
                        final isNone = last4 == 'NONE';
                        final isMapped = last4 != null && !isNone && last4.toString().trim().isNotEmpty;

                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(acc['name'] ?? 'Account', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                          subtitle: Text(type, style: const TextStyle(fontSize: 12)),
                          trailing: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: isNone
                                  ? (isDark ? Colors.white10 : Colors.grey.shade100)
                                  : (isMapped ? Colors.green.shade50 : Colors.orange.shade50),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: isNone
                                    ? (isDark ? Colors.white24 : Colors.grey.shade300)
                                    : (isMapped ? Colors.green.shade200 : Colors.orange.shade200),
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
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: isNone
                                        ? (isDark ? Colors.white70 : Colors.grey.shade700)
                                        : (isMapped ? Colors.green.shade800 : Colors.orange.shade800),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          onTap: () => _showMapAccountDialog(acc),
                        );
                      }),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
    );
  }

  Widget _buildThemeOption({
    required String label,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
    required ThemeData theme,
  }) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? theme.colorScheme.primaryContainer : theme.colorScheme.surfaceContainerHighest.withOpacity(0.4),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? theme.colorScheme.primary : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: Column(
            children: [
              Icon(
                icon,
                size: 20,
                color: isSelected ? theme.colorScheme.onPrimaryContainer : theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  color: isSelected ? theme.colorScheme.onPrimaryContainer : theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
