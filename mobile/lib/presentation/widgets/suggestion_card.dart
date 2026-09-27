import 'package:flutter/material.dart';
import '../../core/utils/date_formatter.dart';
import 'category_picker.dart';

class SuggestionCard extends StatefulWidget {
  final Map<String, dynamic> suggestion;
  final List<dynamic> categories;
  final List<dynamic> accounts;
  final Future<void> Function(
    String id, {
    String? walletAccountId,
    String? walletCategoryId,
    String? walletCategoryName,
    String? transactionType,
    bool? isTransfer,
    String? transferToAccountId,
  }) onApprove;
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
  late String _transactionType;
  String? _selectedCategoryId;
  String? _selectedCategoryName;
  String? _selectedAccountId;
  String? _selectedAccountName;
  String? _selectedTransferToAccountId;
  String? _selectedTransferToAccountName;
  bool _showRawText = false;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _transactionType = (widget.suggestion['transactionType'] ?? 'expense').toString().toLowerCase();
    if (_transactionType != 'expense' && _transactionType != 'income' && _transactionType != 'transfer') {
      _transactionType = 'expense';
    }

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

  void _openAccountPicker({bool isTarget = false}) async {
    // Filter active accounts only (do not show archived accounts)
    final activeAccounts = widget.accounts
        .where((a) => a['isActive'] != false && a['archived'] != true)
        .where((a) {
          if (isTarget && _selectedAccountId != null) {
            return a['walletAccountId'] != _selectedAccountId;
          }
          if (!isTarget && _transactionType == 'transfer' && _selectedTransferToAccountId != null) {
            return a['walletAccountId'] != _selectedTransferToAccountId;
          }
          return true;
        })
        .toList();

    final acc = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        String searchQuery = '';
        return StatefulBuilder(
          builder: (context, setModalState) {
            final filteredAccounts = activeAccounts.where((a) {
              if (searchQuery.isEmpty) return true;
              final q = searchQuery.toLowerCase();
              final name = (a['name'] ?? '').toString().toLowerCase();
              final last4 = (a['last4Digits'] ?? '').toString().toLowerCase();
              final type = (a['accountType'] ?? '').toString().toLowerCase();
              return name.contains(q) || last4.contains(q) || type.contains(q);
            }).toList();

            final title = isTarget
                ? 'Select Destination Account (To)'
                : (_transactionType == 'transfer'
                    ? 'Select Source Account (From)'
                    : 'Select Wallet Account');

            return Container(
              height: MediaQuery.of(context).size.height * 0.65,
              padding: const EdgeInsets.only(top: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade400,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          '${activeAccounts.length} active',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  ),
                  if (activeAccounts.length > 5)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      child: TextField(
                        decoration: InputDecoration(
                          hintText: 'Search active accounts...',
                          prefixIcon: const Icon(Icons.search, size: 20),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onChanged: (val) {
                          setModalState(() {
                            searchQuery = val.trim();
                          });
                        },
                      ),
                    ),
                  const Divider(height: 12),
                  Expanded(
                    child: filteredAccounts.isEmpty
                        ? const Center(
                            child: Padding(
                              padding: EdgeInsets.all(24),
                              child: Text('No matching active accounts found'),
                            ),
                          )
                        : ListView.builder(
                            itemCount: filteredAccounts.length,
                            itemBuilder: (_, idx) {
                              final a = filteredAccounts[idx];
                              final isSel = isTarget
                                  ? a['walletAccountId'] == _selectedTransferToAccountId
                                  : a['walletAccountId'] == _selectedAccountId;
                              final type = (a['accountType'] ?? 'General').toString();
                              IconData icon = Icons.account_balance_outlined;
                              if (type.toLowerCase().contains('credit')) {
                                icon = Icons.credit_card;
                              } else if (type.toLowerCase().contains('cash')) {
                                icon = Icons.payments_outlined;
                              }

                              return ListTile(
                                leading: CircleAvatar(
                                  radius: 18,
                                  backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                                  child: Icon(icon, size: 18, color: Theme.of(context).colorScheme.onPrimaryContainer),
                                ),
                                title: Text(
                                  a['name'] ?? 'Account',
                                  style: TextStyle(
                                    fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                                  ),
                                ),
                                subtitle: Text(
                                  a['last4Digits'] != null
                                      ? 'Mapped: •••• ${a['last4Digits']} • $type'
                                      : type,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: a['last4Digits'] != null ? Colors.green.shade700 : null,
                                  ),
                                ),
                                trailing: isSel
                                    ? const Icon(Icons.check_circle, color: Colors.blue)
                                    : null,
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
      },
    );

    if (acc != null) {
      setState(() {
        if (isTarget) {
          _selectedTransferToAccountId = acc['walletAccountId'];
          _selectedTransferToAccountName = acc['name'];
        } else {
          _selectedAccountId = acc['walletAccountId'];
          _selectedAccountName = acc['name'];
        }
      });
    }
  }

  Future<void> _handleApprove() async {
    if (_isProcessing) return;

    if (_transactionType == 'transfer') {
      if (_selectedAccountId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please select the source account (From)'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }
      if (_selectedTransferToAccountId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please select the destination account (To) for transfer'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }
      if (_selectedAccountId == _selectedTransferToAccountId) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Source and destination accounts must be different'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }
    }

    setState(() => _isProcessing = true);
    try {
      final isTransfer = _transactionType == 'transfer';
      await widget.onApprove(
        widget.suggestion['id'],
        walletAccountId: _selectedAccountId,
        walletCategoryId: isTransfer ? null : _selectedCategoryId,
        walletCategoryName: isTransfer ? 'Transfer' : _selectedCategoryName,
        transactionType: _transactionType,
        isTransfer: isTransfer,
        transferToAccountId: isTransfer ? _selectedTransferToAccountId : null,
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
    final isExpense = _transactionType == 'expense';
    final isIncome = _transactionType == 'income';
    final isTransfer = _transactionType == 'transfer';
    final amount = double.tryParse(widget.suggestion['amount']?.toString() ?? '0') ?? 0.0;
    final counterParty = widget.suggestion['counterParty'] ?? 'Unknown Merchant';
    final rawText = widget.suggestion['rawText'] ?? '';
    final last4 = widget.suggestion['accountLast4'];

    DateTime? txDate;
    if (widget.suggestion['transactionDate'] != null) {
      txDate = DateTime.tryParse(widget.suggestion['transactionDate'].toString());
    }

    String amountPrefix;
    Color amountColor;
    if (isTransfer) {
      amountPrefix = '⇄ ';
      amountColor = Colors.blue.shade700;
    } else if (isIncome) {
      amountPrefix = '+';
      amountColor = Colors.green.shade700;
    } else {
      amountPrefix = '-';
      amountColor = Colors.red.shade700;
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
          if (isTransfer && _selectedTransferToAccountId == null) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Please select destination account before approving transfer'),
                backgroundColor: Colors.orange,
              ),
            );
            return false;
          }
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
                                  fontWeight: FontWeight.w600,
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
                    '$amountPrefix₹${amount.toStringAsFixed(2)}',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: amountColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 10),

              // Transaction Type Selector (Expense | Income | Transfer) + Source Badge
              Row(
                children: [
                  ChoiceChip(
                    label: const Text('Expense'),
                    selected: isExpense,
                    selectedColor: Colors.red.shade100,
                    labelStyle: TextStyle(
                      fontSize: 11,
                      fontWeight: isExpense ? FontWeight.bold : FontWeight.normal,
                      color: isExpense ? Colors.red.shade900 : null,
                    ),
                    visualDensity: VisualDensity.compact,
                    onSelected: (val) {
                      if (val) setState(() => _transactionType = 'expense');
                    },
                  ),
                  const SizedBox(width: 6),
                  ChoiceChip(
                    label: const Text('Income'),
                    selected: isIncome,
                    selectedColor: Colors.green.shade100,
                    labelStyle: TextStyle(
                      fontSize: 11,
                      fontWeight: isIncome ? FontWeight.bold : FontWeight.normal,
                      color: isIncome ? Colors.green.shade900 : null,
                    ),
                    visualDensity: VisualDensity.compact,
                    onSelected: (val) {
                      if (val) setState(() => _transactionType = 'income');
                    },
                  ),
                  const SizedBox(width: 6),
                  ChoiceChip(
                    avatar: Icon(
                      Icons.swap_horiz,
                      size: 14,
                      color: isTransfer ? Colors.blue.shade900 : null,
                    ),
                    label: const Text('Transfer'),
                    selected: isTransfer,
                    selectedColor: Colors.blue.shade100,
                    labelStyle: TextStyle(
                      fontSize: 11,
                      fontWeight: isTransfer ? FontWeight.bold : FontWeight.normal,
                      color: isTransfer ? Colors.blue.shade900 : null,
                    ),
                    visualDensity: VisualDensity.compact,
                    onSelected: (val) {
                      if (val) setState(() => _transactionType = 'transfer');
                    },
                  ),
                  const Spacer(),
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

              // Transfer Accounts Selector Box OR Standard Category & Account Chips
              if (isTransfer) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.35),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Row(
                    children: [
                      // FROM (Source) Account
                      Expanded(
                        child: InkWell(
                          onTap: () => _openAccountPicker(isTarget: false),
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surface,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: _selectedAccountId != null
                                    ? theme.colorScheme.outlineVariant
                                    : Colors.orange.shade300,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(Icons.arrow_upward, size: 12, color: Colors.red.shade700),
                                    const SizedBox(width: 4),
                                    Text(
                                      'FROM (Source)',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.grey.shade600,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _selectedAccountName ?? (last4 != null ? '•••• $last4' : 'Select Account'),
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: _selectedAccountName != null
                                        ? theme.colorScheme.onSurface
                                        : Colors.orange.shade800,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 6),
                        child: Icon(Icons.arrow_forward_rounded, color: Colors.blue, size: 18),
                      ),
                      // TO (Destination) Account
                      Expanded(
                        child: InkWell(
                          onTap: () => _openAccountPicker(isTarget: true),
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surface,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: _selectedTransferToAccountId != null
                                    ? theme.colorScheme.outlineVariant
                                    : Colors.orange.shade400,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(Icons.arrow_downward, size: 12, color: Colors.green.shade700),
                                    const SizedBox(width: 4),
                                    Text(
                                      'TO (Destination)',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.grey.shade600,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _selectedTransferToAccountName ?? 'Select Account',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: _selectedTransferToAccountName != null
                                        ? theme.colorScheme.onSurface
                                        : Colors.orange.shade800,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ] else ...[
                const SizedBox(height: 8),
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
                      onPressed: () => _openAccountPicker(isTarget: false),
                    ),
                  ],
                ),
              ],

              // Raw SMS preview (toggleable)
              if (rawText.isNotEmpty) ...[
                const SizedBox(height: 8),
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
                      backgroundColor: isTransfer ? Colors.blue.shade700 : Colors.green.shade700,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    ),
                    icon: _isProcessing
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                          )
                        : Icon(isTransfer ? Icons.swap_horiz : Icons.check, size: 16),
                    label: Text(isTransfer ? 'Transfer & Sync' : 'Approve & Sync'),
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
