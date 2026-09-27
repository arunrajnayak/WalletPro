import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

  // Sliding Window Settings
  DateTime? _lastReviewedDate;
  DateTime? _syncStartDate;
  bool _autoAdvanceWindow = true;

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
      ]);

      final profile = futures[0] as Map<String, dynamic>;
      final accounts = futures[1] as List<dynamic>;
      final walletProfile = futures[2] as Map<String, dynamic>;

      final prefs = (profile['preferences'] as Map<String, dynamic>?) ?? {};

      DateTime? revDate;
      DateTime? strtDate;
      if (prefs['lastReviewedDate'] != null) {
        revDate = DateTime.tryParse(prefs['lastReviewedDate']);
      }
      if (prefs['syncStartDate'] != null) {
        strtDate = DateTime.tryParse(prefs['syncStartDate']);
      }

      if (mounted) {
        setState(() {
          _lastReviewedDate = revDate;
          _syncStartDate = strtDate;
          _autoAdvanceWindow = prefs['autoAdvanceWindow'] ?? true;
          _walletConnected = profile['walletApiToken'] != null;
          _accounts = accounts;
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

  Future<void> _saveWindowSettings({DateTime? newDate, bool? autoAdvance}) async {
    try {
      final res = await _api.updatePreferences(
        lastReviewedDate: newDate ?? _lastReviewedDate,
        syncStartDate: newDate ?? _syncStartDate,
        autoAdvanceWindow: autoAdvance ?? _autoAdvanceWindow,
      );
      final prefs = (res['preferences'] as Map<String, dynamic>?) ?? {};
      if (mounted) {
        setState(() {
          if (prefs['lastReviewedDate'] != null) {
            _lastReviewedDate = DateTime.tryParse(prefs['lastReviewedDate']);
          }
          if (autoAdvance != null) {
            _autoAdvanceWindow = autoAdvance;
          }
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Detection window updated successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update window: $e')),
        );
      }
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final initialDate = _lastReviewedDate ?? _syncStartDate ?? now;

    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate.isAfter(now) ? now : initialDate,
      firstDate: DateTime(2020),
      lastDate: now,
      helpText: 'SELECT DETECTION START DATE',
      confirmText: 'SET START DATE',
    );

    if (picked != null) {
      final startOfDay = DateTime(picked.year, picked.month, picked.day);
      await _saveWindowSettings(newDate: startOfDay);
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
    final controller = TextEditingController(text: account['last4Digits'] ?? '');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Map "${account['name']}"'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter the last 4 digits of your card or bank account from transaction SMS alerts:',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              keyboardType: TextInputType.text,
              maxLength: 10,
              decoration: InputDecoration(
                labelText: 'Last 4 Digits (e.g. 1234 or 08f7)',
                filled: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save Mapping')),
        ],
      ),
    );

    if (confirmed == true) {
      final digits = controller.text.trim();
      try {
        await _api.mapAccountLast4(account['id'], digits);
        await _loadSettings();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Mapped ${account['name']} to •••• $digits')),
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
    final effectiveCutoff = _lastReviewedDate ?? _syncStartDate;

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
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                            onTap: () => ref.read(themeModeProvider.notifier).state = ThemeMode.system,
                            theme: theme,
                          ),
                          const SizedBox(width: 8),
                          _buildThemeOption(
                            label: 'Light',
                            icon: Icons.light_mode_outlined,
                            isSelected: currentThemeMode == ThemeMode.light,
                            onTap: () => ref.read(themeModeProvider.notifier).state = ThemeMode.light,
                            theme: theme,
                          ),
                          const SizedBox(width: 8),
                          _buildThemeOption(
                            label: 'Dark',
                            icon: Icons.dark_mode_outlined,
                            isSelected: currentThemeMode == ThemeMode.dark,
                            onTap: () => ref.read(themeModeProvider.notifier).state = ThemeMode.dark,
                            theme: theme,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // 3. Sliding Window / Detection Date Card
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
                            child: Icon(Icons.history_toggle_off, size: 16, color: theme.colorScheme.primary),
                          ),
                          const SizedBox(width: 10),
                          const Text('Detection Window (Sliding Filter)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Transactions prior to this date are automatically skipped to avoid processing old historical messages.',
                        style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
                      ),
                      const Divider(height: 24),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(
                          radius: 18,
                          backgroundColor: theme.colorScheme.surfaceContainerHighest,
                          child: const Icon(Icons.calendar_today, size: 18),
                        ),
                        title: const Text('Reviewed Up To (Cutoff Date)', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                        subtitle: Text(
                          effectiveCutoff != null
                              ? DateFormatter.formatFull(effectiveCutoff)
                              : 'Not set (all transactions processed)',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: effectiveCutoff != null ? theme.colorScheme.primary : null,
                          ),
                        ),
                        trailing: OutlinedButton(
                          onPressed: _pickDate,
                          child: const Text('Change'),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Auto-Advance Sliding Window', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                        subtitle: const Text(
                          'Automatically move the cutoff date forward upon reviewing transactions.',
                          style: TextStyle(fontSize: 12),
                        ),
                        value: _autoAdvanceWindow,
                        onChanged: (val) => _saveWindowSettings(autoAdvance: val),
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

                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(acc['name'] ?? 'Account', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                          subtitle: Text(type, style: const TextStyle(fontSize: 12)),
                          trailing: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: last4 != null ? Colors.green.shade50 : Colors.orange.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: last4 != null ? Colors.green.shade200 : Colors.orange.shade200,
                              ),
                            ),
                            child: Text(
                              last4 != null ? '•••• $last4' : 'Tap to Map',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: last4 != null ? Colors.green.shade800 : Colors.orange.shade800,
                              ),
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
