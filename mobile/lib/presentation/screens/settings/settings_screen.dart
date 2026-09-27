import 'package:flutter/material.dart';
import '../../../data/datasources/remote/api_client.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/utils/date_formatter.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
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

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    setState(() => _isLoading = true);
    try {
      final profile = await _api.getUserProfile();
      final prefs = (profile['preferences'] as Map<String, dynamic>?) ?? {};

      if (prefs['lastReviewedDate'] != null) {
        _lastReviewedDate = DateTime.tryParse(prefs['lastReviewedDate']);
      }
      if (prefs['syncStartDate'] != null) {
        _syncStartDate = DateTime.tryParse(prefs['syncStartDate']);
      }
      _autoAdvanceWindow = prefs['autoAdvanceWindow'] ?? true;
      _walletConnected = profile['walletApiToken'] != null;

      // Load accounts
      _accounts = await _api.getWalletAccounts();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading settings: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
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
      // Set to beginning of that selected day
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
        title: Text('Map "${account['name']}"'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Enter the last 4 digits of your card or bank account:'),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              maxLength: 4,
              decoration: const InputDecoration(
                labelText: 'Last 4 Digits (e.g. 08f7 or 1234)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _api.mapAccountLast4(account['id'], controller.text.trim());
        await _loadSettings();
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
    final effectiveCutoff = _lastReviewedDate ?? _syncStartDate;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadSettings,
            tooltip: 'Reload',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // ----------------------------------------------------
                // Section 1: Sliding Window / Reviewed Date
                // ----------------------------------------------------
                Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(color: theme.colorScheme.outlineVariant),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Row(
                        children: [
                          Icon(Icons.history_toggle_off, color: theme.colorScheme.primary),
                          const SizedBox(width: 12),
                          Text(
                            'Detection Window (Sliding Filter)',
                            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Transactions dated prior to this date are automatically ignored so old SMS messages do not flood your queue.',
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                      const Divider(height: 24),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(
                          backgroundColor: theme.colorScheme.primaryContainer,
                          child: Icon(Icons.calendar_today, color: theme.colorScheme.onPrimaryContainer, size: 20),
                        ),
                        title: const Text('Reviewed Up To (Cutoff Date)'),
                        subtitle: Text(
                          effectiveCutoff != null
                              ? DateFormatter.formatFull(effectiveCutoff)
                              : 'Not set (all transactions processed)',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: effectiveCutoff != null ? theme.colorScheme.primary : null,
                          ),
                        ),
                        trailing: OutlinedButton(
                          onPressed: _pickDate,
                          child: const Text('Change Date'),
                        ),
                      ),
                      const SizedBox(height: 8),
                      // Quick Presets
                      Wrap(
                        spacing: 8,
                        children: [
                          ActionChip(
                            label: const Text('Today'),
                            onPressed: () {
                              final now = DateTime.now();
                              _saveWindowSettings(newDate: DateTime(now.year, now.month, now.day));
                            },
                          ),
                          ActionChip(
                            label: const Text('7 Days Ago'),
                            onPressed: () {
                              final d = DateTime.now().subtract(const Duration(days: 7));
                              _saveWindowSettings(newDate: DateTime(d.year, d.month, d.day));
                            },
                          ),
                          ActionChip(
                            label: const Text('1st of Month'),
                            onPressed: () {
                              final now = DateTime.now();
                              _saveWindowSettings(newDate: DateTime(now.year, now.month, 1));
                            },
                          ),
                        ],
                      ),
                      const Divider(height: 24),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Auto-Advance Sliding Window'),
                        subtitle: const Text(
                          'Automatically move the cutoff date forward to the transaction date whenever you approve or reject a transaction.',
                        ),
                        value: _autoAdvanceWindow,
                        onChanged: (val) => _saveWindowSettings(autoAdvance: val),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // ----------------------------------------------------
                // Section 2: BudgetBakers Wallet Connection
                // ----------------------------------------------------
                Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(color: theme.colorScheme.outlineVariant),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Row(
                        children: [
                          Icon(Icons.account_balance_wallet, color: theme.colorScheme.primary),
                          const SizedBox(width: 12),
                          Text(
                            'BudgetBakers Wallet Connection',
                            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          _walletConnected ? Icons.check_circle : Icons.error,
                          color: _walletConnected ? Colors.green : Colors.orange,
                        ),
                        title: Text(_walletConnected ? 'Wallet Pro Connected' : 'Not Connected'),
                        subtitle: const Text('Direct REST API v2.0 integration'),
                        trailing: FilledButton.tonalIcon(
                          icon: _isSyncing
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.sync, size: 18),
                          label: const Text('Sync Now'),
                          onPressed: _isSyncing ? null : _triggerWalletSync,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // ----------------------------------------------------
                // Section 3: Account Last-4 Digit Mapping
                // ----------------------------------------------------
                Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(color: theme.colorScheme.outlineVariant),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Row(
                        children: [
                          Icon(Icons.credit_card, color: theme.colorScheme.primary),
                          const SizedBox(width: 12),
                          Text(
                            'Bank Account Mapping (Last 4 Digits)',
                            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Map your bank card/account numbers so incoming SMS can automatically assign transactions to the right Wallet account.',
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: 12),
                      if (_accounts.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Text('No accounts found. Tap "Sync Now" above to load your accounts.'),
                        )
                      else
                        ..._accounts.map((acc) {
                          final last4 = acc['last4Digits'];
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(acc['name'] ?? 'Account'),
                            subtitle: Text(
                              last4 != null ? 'Card / Acct: •••• $last4' : 'No digits mapped',
                              style: TextStyle(color: last4 != null ? Colors.green : Colors.grey),
                            ),
                            trailing: IconButton(
                              icon: const Icon(Icons.edit, size: 20),
                              onPressed: () => _showMapAccountDialog(acc),
                            ),
                          );
                        }),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // ----------------------------------------------------
                // Section 4: System Information
                // ----------------------------------------------------
                Card(
                  elevation: 0,
                  color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.3),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(color: theme.colorScheme.outlineVariant),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Text(
                        'Server Configuration',
                        style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Backend: ${ApiConstants.backendBaseUrl}',
                        style: theme.textTheme.bodySmall,
                      ),
                      Text(
                        'Database: Neon Serverless PostgreSQL',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
