import 'package:flutter/material.dart';
import '../../core/utils/date_formatter.dart';
import 'category_picker.dart';

class SuggestionCard extends StatefulWidget {
  final Map<String, dynamic> suggestion;
  final List<dynamic> categories;
  final List<dynamic> accounts;
  final Future<void> Function(String id, {String? walletAccountId, String? walletCategoryId, String? walletCategoryName}) onApprove;
  final Future<void> Function(String id) onReject;

  const SuggestionCard({
    super.key,
    required this.suggestion,
    required this.categories,
    required this.accounts,
    required this.onApprove,
    required this.onReject,
  });

  @override
  State<SuggestionCard> createState() => _SuggestionCardState();
}

class _SuggestionCardState extends State<SuggestionCard> {
  String? _selectedCategoryId;
  String? _selectedCategoryName;
  String? _selectedAccountId;
  String? _selectedAccountName;
  bool _showRawText = false;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _selectedCategoryId = widget.suggestion['walletCategoryId'];
    _selectedCategoryName = widget.suggestion['walletCategoryName'];
    _selectedAccountId = widget.suggestion['walletAccountId'];

    // If account not mapped, try matching by last 4 digits
    final last4 = widget.suggestion['accountLast4'];
    if (_selectedAccountId == null && last4 != null) {
      final match = widget.accounts.firstWhere(
        (acc) => acc['last4Digits'] == last4,
        orElse: () => null,
      );
      if (match != null) {
        _selectedAccountId = match['walletAccountId'];
        _selectedAccountName = match['name'];
      }
    } else if (_selectedAccountId != null) {
      final match = widget.accounts.firstWhere(
        (acc) => acc['walletAccountId'] == _selectedAccountId,
        orElse: () => null,
      );
      if (match != null) {
        _selectedAccountName = match['name'];
      }
    }

    // Fallback category name if id is present
    if (_selectedCategoryId != null && _selectedCategoryName == null) {
      final catMatch = widget.categories.firstWhere(
        (cat) => cat['walletCategoryId'] == _selectedCategoryId,
        orElse: () => null,
      );
      if (catMatch != null) {
        _selectedCategoryName = catMatch['name'];
      }
    }
  }

  void _openCategoryPicker() async {
    final cat = await CategoryPicker.show(
      context,
      categories: widget.categories,
      selectedCategoryId: _selectedCategoryId,
    );
    if (cat != null) {
      setState(() {
        _selectedCategoryId = cat['walletCategoryId'];
        _selectedCategoryName = cat['name'];
      });
    }
  }

  void _openAccountPicker() async {
    final acc = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Select Wallet Account',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: widget.accounts.length,
                  itemBuilder: (_, idx) {
                    final a = widget.accounts[idx];
                    final isSel = a['walletAccountId'] == _selectedAccountId;
                    return ListTile(
                      title: Text(a['name'] ?? 'Account'),
                      subtitle: Text(
                        a['last4Digits'] != null ? 'Card/Acct: •••• ${a['last4Digits']}' : (a['accountType'] ?? 'General'),
                      ),
                      trailing: isSel ? const Icon(Icons.check, color: Colors.blue) : null,
                      onTap: () => Navigator.pop(ctx, a as Map<String, dynamic>),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );

    if (acc != null) {
      setState(() {
        _selectedAccountId = acc['walletAccountId'];
        _selectedAccountName = acc['name'];
      });
    }
  }

  Future<void> _handleApprove() async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);
    try {
      await widget.onApprove(
        widget.suggestion['id'],
        walletAccountId: _selectedAccountId,
        walletCategoryId: _selectedCategoryId,
        walletCategoryName: _selectedCategoryName,
      );
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _handleReject() async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);
    try {
      await widget.onReject(widget.suggestion['id']);
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isExpense = (widget.suggestion['transactionType'] ?? 'expense').toString().toLowerCase() == 'expense';
    final amount = double.tryParse(widget.suggestion['amount']?.toString() ?? '0') ?? 0.0;
    final counterParty = widget.suggestion['counterParty'] ?? 'Unknown Merchant';
    final rawText = widget.suggestion['rawText'] ?? '';
    final last4 = widget.suggestion['accountLast4'];

    DateTime? txDate;
    if (widget.suggestion['transactionDate'] != null) {
      txDate = DateTime.tryParse(widget.suggestion['transactionDate'].toString());
    }

    return Dismissible(
      key: Key(widget.suggestion['id']),
      direction: DismissDirection.horizontal,
      background: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 24),
        decoration: BoxDecoration(
          color: Colors.green.shade600,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Row(
          children: [
            Icon(Icons.check, color: Colors.white, size: 28),
            SizedBox(width: 8),
            Text('Approve', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
      ),
      secondaryBackground: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        decoration: BoxDecoration(
          color: Colors.red.shade600,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text('Reject', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
            SizedBox(width: 8),
            Icon(Icons.close, color: Colors.white, size: 28),
          ],
        ),
      ),
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          await _handleApprove();
        } else {
          await _handleReject();
        }
        return true;
      },
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top Row: Counterparty & Amount
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          counterParty,
                          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            if (txDate != null)
                              Text(
                                DateFormatter.formatFull(txDate),
                                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                              ),
                            if (last4 != null) ...[
                              Text(' • ', style: TextStyle(color: theme.colorScheme.outline)),
                              Text(
                                '•••• $last4',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontWeight: FontWeight.w640,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '${isExpense ? '-' : '+'}₹${amount.toStringAsFixed(2)}',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: isExpense ? Colors.red.shade700 : Colors.green.shade700,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // Chip Pickers Row (Category & Account)
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  // Category Chip
                  ActionChip(
                    avatar: Icon(
                      Icons.category_outlined,
                      size: 16,
                      color: _selectedCategoryName != null ? theme.colorScheme.primary : theme.colorScheme.outline,
                    ),
                    label: Text(
                      _selectedCategoryName ?? 'Select Category',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: _selectedCategoryName != null ? FontWeight.bold : FontWeight.normal,
                        color: _selectedCategoryName != null ? theme.colorScheme.primary : null,
                      ),
                    ),
                    onPressed: _openCategoryPicker,
                  ),

                  // Account Chip
                  ActionChip(
                    avatar: Icon(
                      Icons.account_balance_outlined,
                      size: 16,
                      color: _selectedAccountName != null ? theme.colorScheme.primary : theme.colorScheme.outline,
                    ),
                    label: Text(
                      _selectedAccountName ?? (last4 != null ? 'Acct: •••• $last4' : 'Select Account'),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: _selectedAccountName != null ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                    onPressed: _openAccountPicker,
                  ),

                  // Source Badge
                  Chip(
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    labelPadding: const EdgeInsets.symmetric(horizontal: 8),
                    label: Text(
                      (widget.suggestion['source'] ?? 'SMS').toString().toUpperCase(),
                      style: TextStyle(fontSize: 10, color: theme.colorScheme.onSurfaceVariant),
                    ),
                    backgroundColor: theme.colorScheme.surfaceContainerHighest.withOpacity(0.4),
                    side: BorderSide.none,
                  ),
                ],
              ),

              // Raw SMS preview (toggleable)
              if (rawText.isNotEmpty) ...[
                const SizedBox(height: 6),
                GestureDetector(
                  onTap: () => setState(() => _showRawText = !_showRawText),
                  child: Row(
                    children: [
                      Icon(
                        _showRawText ? Icons.arrow_drop_up : Icons.arrow_drop_down,
                        size: 18,
                        color: theme.colorScheme.outline,
                      ),
                      Text(
                        _showRawText ? 'Hide original message' : 'View original message',
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
                      ),
                    ],
                  ),
                ),
                if (_showRawText)
                  Container(
                    margin: const EdgeInsets.only(top: 6),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      rawText,
                      style: theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace', fontSize: 11),
                    ),
                  ),
              ],

              const SizedBox(height: 12),

              // Action buttons (Reject / Approve)
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red.shade700,
                      side: BorderSide(color: Colors.red.shade200),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    icon: const Icon(Icons.close, size: 16),
                    label: const Text('Reject'),
                    onPressed: _isProcessing ? null : _handleReject,
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.green.shade700,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    ),
                    icon: _isProcessing
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                          )
                        : const Icon(Icons.check, size: 16),
                    label: const Text('Approve & Sync'),
                    onPressed: _isProcessing ? null : _handleApprove,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
