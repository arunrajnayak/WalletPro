import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../core/utils/stats_parser.dart';
import '../../../data/datasources/remote/api_client.dart';
import '../../providers/pending_count_provider.dart';
import '../../providers/suggestions_provider.dart';

class SuggestionDetailScreen extends ConsumerStatefulWidget {
  final String suggestionId;

  const SuggestionDetailScreen({super.key, required this.suggestionId});

  @override
  ConsumerState<SuggestionDetailScreen> createState() => _SuggestionDetailScreenState();
}

class _SuggestionDetailScreenState extends ConsumerState<SuggestionDetailScreen> {
  final ApiClient _api = ApiClient();
  Map<String, dynamic>? _suggestion;
  bool _isLoading = true;
  String? _error;
  bool _isActioning = false;

  @override
  void initState() {
    super.initState();
    _fetchDetail();
  }

  Future<void> _fetchDetail() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final data = await _api.getSuggestionById(widget.suggestionId);
      if (mounted) {
        setState(() {
          _suggestion = data;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to load transaction details: $e';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _handleApprove() async {
    if (_isActioning || _suggestion == null) return;
    setState(() => _isActioning = true);

    try {
      await _api.approveSuggestion(widget.suggestionId);
      ref.read(pendingSuggestionsProvider.notifier).removeSuggestion(widget.suggestionId);
      final currentPending = ref.read(pendingCountProvider);
      ref.read(pendingCountProvider.notifier).state = (currentPending - 1).clamp(0, 9999);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Transaction approved and synced ✓'),
            backgroundColor: Color(0xFF16A34A),
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isActioning = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Approval failed: $e'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    }
  }

  Future<void> _handleReject() async {
    if (_isActioning || _suggestion == null) return;
    setState(() => _isActioning = true);

    try {
      await _api.rejectSuggestion(widget.suggestionId);
      ref.read(pendingSuggestionsProvider.notifier).removeSuggestion(widget.suggestionId);
      final currentPending = ref.read(pendingCountProvider);
      ref.read(pendingCountProvider.notifier).state = (currentPending - 1).clamp(0, 9999);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Transaction rejected')),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isActioning = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Reject failed: $e'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Transaction Details'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
            onPressed: _fetchDetail,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.error_outline_rounded, size: 48, color: theme.colorScheme.error),
                        const SizedBox(height: 12),
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        FilledButton(onPressed: _fetchDetail, child: const Text('Retry')),
                      ],
                    ),
                  ),
                )
              : _buildContent(theme, isDark),
    );
  }

  Widget _buildContent(ThemeData theme, bool isDark) {
    final s = _suggestion!;
    final amount = parseDouble(s['amount']);
    final type = (s['transactionType'] ?? 'expense').toString().toLowerCase();
    final isExpense = type == 'expense';
    final isTransfer = type == 'transfer';
    final status = (s['status'] ?? 'pending').toString().toLowerCase();
    final merchant = (s['counterParty'] ?? s['note'] ?? 'Unknown Merchant').toString();
    final rawText = (s['rawText'] ?? '').toString();
    final refNo = s['referenceNumber']?.toString();
    final last4 = s['accountLast4']?.toString();
    final catName = s['walletCategoryName']?.toString() ?? 'Uncategorized';
    final accName = s['walletAccountName']?.toString();

    DateTime? txDate;
    if (s['transactionDate'] != null) {
      txDate = DateTime.tryParse(s['transactionDate'].toString());
    }

    Color statusColor;
    String statusLabel;
    if (status == 'approved' || status == 'synced') {
      statusColor = const Color(0xFF16A34A);
      statusLabel = 'Approved & Synced';
    } else if (status == 'rejected') {
      statusColor = const Color(0xFFDC2626);
      statusLabel = 'Rejected';
    } else {
      statusColor = const Color(0xFFF59E0B);
      statusLabel = 'Pending Review';
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
      children: [
        // 1. Hero Card
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF0F172A) : Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(isDark ? 0.3 : 0.06),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: statusColor.withOpacity(0.4), width: 1),
                    ),
                    child: Text(
                      statusLabel,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.bold,
                        color: statusColor,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: (isExpense
                              ? Colors.redAccent
                              : (isTransfer ? Colors.blueAccent : Colors.greenAccent))
                          .withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      type.toUpperCase(),
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        color: isExpense
                            ? Colors.redAccent
                            : (isTransfer ? Colors.blueAccent : Colors.greenAccent),
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                merchant,
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                '${isExpense ? '-' : (isTransfer ? '' : '+')}${CurrencyFormatter.formatINR(amount)}',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.5,
                  color: isExpense
                      ? const Color(0xFFF87171)
                      : (isTransfer ? const Color(0xFF60A5FA) : const Color(0xFF4ADE80)),
                ),
              ),
              if (txDate != null) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    Icon(Icons.calendar_today_rounded,
                        size: 14, color: theme.colorScheme.onSurfaceVariant),
                    const SizedBox(width: 6),
                    Text(
                      DateFormatter.formatFull(txDate),
                      style: TextStyle(
                        fontSize: 12.5,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),

        const SizedBox(height: 16),

        // 2. Metadata Section
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF0F172A) : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
            ),
          ),
          child: Column(
            children: [
              _buildMetaTile(
                icon: Icons.category_rounded,
                iconColor: const Color(0xFF8B5CF6),
                title: 'Category',
                value: catName,
                theme: theme,
              ),
              const Divider(height: 20),
              _buildMetaTile(
                icon: Icons.account_balance_rounded,
                iconColor: const Color(0xFF3B82F6),
                title: 'Account',
                value: accName ?? (last4 != null ? 'Card •••• $last4' : 'Not Assigned'),
                theme: theme,
              ),
              if (refNo != null && refNo.isNotEmpty) ...[
                const Divider(height: 20),
                _buildMetaTile(
                  icon: Icons.tag_rounded,
                  iconColor: const Color(0xFF10B981),
                  title: 'Ref Number',
                  value: refNo,
                  theme: theme,
                  onCopy: () {
                    Clipboard.setData(ClipboardData(text: refNo));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Reference number copied to clipboard')),
                    );
                  },
                ),
              ],
            ],
          ),
        ),

        const SizedBox(height: 16),

        // 3. Raw SMS Text Card
        if (rawText.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF0F172A) : Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
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
                        Icon(Icons.sms_rounded, size: 16, color: theme.colorScheme.primary),
                        const SizedBox(width: 8),
                        const Text(
                          'Original SMS Message',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(Icons.copy_rounded, size: 16),
                      tooltip: 'Copy SMS',
                      visualDensity: VisualDensity.compact,
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: rawText));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('SMS text copied to clipboard')),
                        );
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: SelectableText(
                    rawText,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
        ],

        // 4. Action Buttons (only if pending)
        if (status == 'pending') ...[
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.close_rounded, color: Colors.redAccent),
                  label: const Text('Reject', style: TextStyle(color: Colors.redAccent)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.redAccent),
                    minimumSize: const Size.fromHeight(48),
                  ),
                  onPressed: _isActioning ? null : _handleReject,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: FilledButton.icon(
                  icon: const Icon(Icons.check_rounded),
                  label: const Text('Approve & Sync'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF16A34A),
                    minimumSize: const Size.fromHeight(48),
                  ),
                  onPressed: _isActioning ? null : _handleApprove,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildMetaTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String value,
    required ThemeData theme,
    VoidCallback? onCopy,
  }) {
    return Row(
      children: [
        CircleAvatar(
          radius: 16,
          backgroundColor: iconColor.withOpacity(0.15),
          child: Icon(icon, size: 16, color: iconColor),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 11.5,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
        if (onCopy != null)
          IconButton(
            icon: const Icon(Icons.copy_rounded, size: 16),
            tooltip: 'Copy',
            visualDensity: VisualDensity.compact,
            onPressed: onCopy,
          ),
      ],
    );
  }
}
