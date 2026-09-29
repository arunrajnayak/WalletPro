import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/utils/currency_formatter.dart';
import '../../core/utils/date_formatter.dart';
import '../../core/utils/account_sorter.dart';
import 'category_picker.dart';

class SuggestionCard extends StatefulWidget {
  final Map<String, dynamic> suggestion;
  final List<dynamic> categories;
  final List<dynamic> accounts;
  final EdgeInsetsGeometry? margin;
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
    this.margin,
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
    _initFromSuggestion();
  }

  @override
  void didUpdateWidget(covariant SuggestionCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.suggestion['id'] != widget.suggestion['id'] ||
        oldWidget.suggestion['walletAccountId'] != widget.suggestion['walletAccountId'] ||
        oldWidget.suggestion['walletCategoryId'] != widget.suggestion['walletCategoryId'] ||
        oldWidget.accounts != widget.accounts) {
      _initFromSuggestion();
    }
  }

  void _initFromSuggestion() {
    void apply() {
      _transactionType = (widget.suggestion['transactionType'] ?? 'expense').toString().toLowerCase();
      if (_transactionType != 'expense' && _transactionType != 'income' && _transactionType != 'transfer') {
        _transactionType = 'expense';
      }

      _selectedCategoryId = widget.suggestion['walletCategoryId'];
      _selectedCategoryName = widget.suggestion['walletCategoryName'];
      _selectedAccountId = widget.suggestion['walletAccountId'];

      // If account not mapped or matches newly mapped digits, try matching by last 4 digits
      final last4 = widget.suggestion['accountLast4']?.toString().trim();
      if (last4 != null && last4.isNotEmpty && last4.toUpperCase() != 'NONE') {
        final match = widget.accounts.firstWhere(
          (acc) {
            final accLast4 = acc['last4Digits']?.toString().trim();
            if (accLast4 == null || accLast4.isEmpty || accLast4.toUpperCase() == 'NONE') return false;
            final digitsList = accLast4.split(RegExp(r'[,;\s]+')).map((s) => s.trim()).toList();
            return digitsList.contains(last4) || accLast4 == last4;
          },
          orElse: () => null,
        );
        if (match != null) {
          _selectedAccountId = match['walletAccountId'] ?? match['id'];
          _selectedAccountName = match['name'];
        }
      }

      if (_selectedAccountId != null && _selectedAccountName == null) {
        final match = widget.accounts.firstWhere(
          (acc) => (acc['walletAccountId'] == _selectedAccountId || acc['id'] == _selectedAccountId),
          orElse: () => null,
        );
        if (match != null) {
          _selectedAccountName = match['name'];
        }
      }

      // Fallback category name if id is present
      if (_selectedCategoryId != null && _selectedCategoryName == null) {
        final catMatch = widget.categories.firstWhere(
          (cat) => (cat['walletCategoryId'] == _selectedCategoryId || cat['id'] == _selectedCategoryId),
          orElse: () => null,
        );
        if (catMatch != null) {
          _selectedCategoryName = catMatch['name'];
        }
      }
    }

    if (mounted) {
      setState(apply);
    } else {
      apply();
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

    AccountSorter.sortAccounts(activeAccounts);

    final acc = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        String searchQuery = '';
        return StatefulBuilder(
          builder: (context, setModalState) {
            final filteredAccounts = activeAccounts.where((a) {
              if (searchQuery.isEmpty) return true;
              final q = searchQuery.toLowerCase();
              final name = (a['name'] ?? '').toString().toLowerCase();
              final rawLast4 = (a['last4Digits'] ?? '').toString();
              final last4 = (rawLast4 != 'NONE') ? rawLast4.toLowerCase() : '';
              final type = (a['accountType'] ?? '').toString().toLowerCase();
              return name.contains(q) || last4.contains(q) || type.contains(q);
            }).toList();

            final title = isTarget
                ? 'Select To Account'
                : (_transactionType == 'transfer'
                    ? 'Select From Account'
                    : 'Select Wallet Account');

            return Container(
              height: MediaQuery.of(context).size.height * 0.7,
              padding: const EdgeInsets.only(top: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 44,
                      height: 5,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade400,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.5),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '${activeAccounts.length} active',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Theme.of(context).colorScheme.onPrimaryContainer,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (activeAccounts.length > 5)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                      child: TextField(
                        decoration: InputDecoration(
                          hintText: 'Search active accounts...',
                          prefixIcon: const Icon(Icons.search, size: 20),
                          filled: true,
                          fillColor: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.4),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide.none,
                          ),
                        ),
                        onChanged: (val) {
                          setModalState(() {
                            searchQuery = val.trim();
                          });
                        },
                      ),
                    ),
                  const Divider(height: 16),
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
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
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

                              return Card(
                                elevation: 0,
                                color: isSel
                                    ? Theme.of(context).colorScheme.primaryContainer.withOpacity(0.35)
                                    : Theme.of(context).colorScheme.surface,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  side: BorderSide(
                                    color: isSel
                                        ? Theme.of(context).colorScheme.primary
                                        : Theme.of(context).colorScheme.outlineVariant.withOpacity(0.5),
                                    width: isSel ? 1.5 : 1,
                                  ),
                                ),
                                margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                                child: ListTile(
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                  leading: CircleAvatar(
                                    radius: 20,
                                    backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                                    child: Icon(icon, size: 20, color: Theme.of(context).colorScheme.onPrimaryContainer),
                                  ),
                                  title: Text(
                                    a['name'] ?? 'Account',
                                    style: TextStyle(
                                      fontWeight: isSel ? FontWeight.bold : FontWeight.w600,
                                      fontSize: 15,
                                    ),
                                  ),
                                  subtitle: Builder(
                                    builder: (context) {
                                      final accLast4 = a['last4Digits'];
                                      final isNone = accLast4 == 'NONE';
                                      final isMapped = accLast4 != null && !isNone && accLast4.toString().trim().isNotEmpty;
                                      return Text(
                                        isMapped
                                            ? 'Mapped: •••• $accLast4 • $type'
                                            : (isNone ? '$type • (Don\'t Map)' : type),
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: isMapped ? FontWeight.w600 : FontWeight.normal,
                                          color: isMapped
                                              ? Colors.green.shade700
                                              : (isNone ? Theme.of(context).colorScheme.outline : null),
                                        ),
                                      );
                                    },
                                  ),
                                  trailing: isSel
                                      ? Icon(Icons.check_circle_rounded, color: Theme.of(context).colorScheme.primary, size: 22)
                                      : const Icon(Icons.chevron_right, size: 20, color: Colors.grey),
                                  onTap: () => Navigator.pop(ctx, a as Map<String, dynamic>),
                                ),
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

  Future<bool> _handleApprove() async {
    if (_isProcessing) return false;

    if (_transactionType == 'transfer') {
      if (_selectedAccountId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please select From account for transfer'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 2),
          ),
        );
        return false;
      }
      if (_selectedTransferToAccountId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please select To account for transfer'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 2),
          ),
        );
        return false;
      }
      if (_selectedAccountId == _selectedTransferToAccountId) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('From and To accounts must be different'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 2),
          ),
        );
        return false;
      }
    } else {
      if (_selectedAccountId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please select an Account to approve'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 2),
          ),
        );
        return false;
      }
      if (_selectedCategoryId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please select a Category to approve'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 2),
          ),
        );
        return false;
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
      return true;
    } catch (_) {
      return false;
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
    final isDark = theme.brightness == Brightness.dark;
    final isExpense = _transactionType == 'expense';
    final isIncome = _transactionType == 'income';
    final isTransfer = _transactionType == 'transfer';

    final amountNum = double.tryParse(widget.suggestion['amount']?.toString() ?? '0') ?? 0.0;
    final counterParty = (widget.suggestion['counterParty'] ?? 'Unknown Merchant').toString();
    final rawText = (widget.suggestion['rawText'] ?? '').toString();
    final rawLast4 = widget.suggestion['accountLast4']?.toString().trim();
    final last4 = (rawLast4 != null && rawLast4.isNotEmpty && rawLast4 != 'NONE') ? rawLast4 : null;
    final source = (widget.suggestion['source'] ?? 'SMS').toString().toUpperCase();
    final note = widget.suggestion['note']?.toString();
    final refNumber = widget.suggestion['referenceNumber']?.toString();
    final aiConfidence = widget.suggestion['aiConfidence'] != null
        ? double.tryParse(widget.suggestion['aiConfidence'].toString())
        : null;

    DateTime? txDate;
    if (widget.suggestion['transactionDate'] != null) {
      txDate = DateTime.tryParse(widget.suggestion['transactionDate'].toString());
    }

    // Hero amount styling
    String formattedAmount;
    Color amountColor;
    Color heroBgColor;
    IconData heroIcon;

    if (isTransfer) {
      formattedAmount = '⇄ ${CurrencyFormatter.formatINR(amountNum)}';
      amountColor = isDark ? const Color(0xFF60A5FA) : const Color(0xFF1D4ED8);
      heroBgColor = isDark ? const Color(0xFF1E3A8A).withOpacity(0.35) : const Color(0xFFEFF6FF);
      heroIcon = Icons.swap_horiz_rounded;
    } else if (isIncome) {
      formattedAmount = '+${CurrencyFormatter.formatINR(amountNum)}';
      amountColor = isDark ? const Color(0xFF4ADE80) : const Color(0xFF15803D);
      heroBgColor = isDark ? const Color(0xFF064E3B).withOpacity(0.35) : const Color(0xFFF0FDF4);
      heroIcon = Icons.arrow_downward_rounded;
    } else {
      formattedAmount = '-${CurrencyFormatter.formatINR(amountNum)}';
      amountColor = isDark ? const Color(0xFFF87171) : const Color(0xFFDC2626);
      heroBgColor = isDark ? const Color(0xFF7F1D1D).withOpacity(0.35) : const Color(0xFFFEF2F2);
      heroIcon = Icons.arrow_upward_rounded;
    }

    final cardMargin = widget.margin ?? const EdgeInsets.symmetric(horizontal: 16, vertical: 10);

    return Dismissible(
      key: Key(widget.suggestion['id']),
      direction: DismissDirection.horizontal,
      background: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 28),
        margin: cardMargin,
        decoration: BoxDecoration(
          color: const Color(0xFF16A34A),
          borderRadius: BorderRadius.circular(22),
        ),
        child: const Row(
          children: [
            Icon(Icons.check_circle_rounded, color: Colors.white, size: 30),
            SizedBox(width: 10),
            Text(
              'Approve & Sync',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ],
        ),
      ),
      secondaryBackground: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 28),
        margin: cardMargin,
        decoration: BoxDecoration(
          color: const Color(0xFFDC2626),
          borderRadius: BorderRadius.circular(22),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text(
              'Reject',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
            ),
            SizedBox(width: 10),
            Icon(Icons.cancel_rounded, color: Colors.white, size: 30),
          ],
        ),
      ),
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          final approved = await _handleApprove();
          return approved;
        } else {
          await _handleReject();
          return true;
        }
      },
      child: Container(
        margin: cardMargin,
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: theme.colorScheme.outlineVariant.withOpacity(0.6),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(isDark ? 0.25 : 0.05),
              blurRadius: 14,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ==========================================
              // 1. TOP METADATA ROW: Source, Timestamp & AI Confidence
              // ==========================================
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.65),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          source == 'SMS' ? Icons.sms_outlined : Icons.mail_outline_rounded,
                          size: 13,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          source,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (txDate != null) ...[
                    const SizedBox(width: 10),
                    Icon(
                      Icons.access_time_rounded,
                      size: 14,
                      color: theme.colorScheme.onSurfaceVariant.withOpacity(0.7),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      DateFormatter.formatFull(txDate),
                      style: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                  const Spacer(),
                  if (aiConfidence != null && aiConfidence >= 0.5)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF581C87).withOpacity(0.4) : const Color(0xFFF3E8FF),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isDark ? const Color(0xFFA855F7).withOpacity(0.4) : const Color(0xFFD8B4FE),
                          width: 0.8,
                        ),
                      ),
                      child: Text(
                        '✨ AI ${(aiConfidence * 100).toInt()}% match',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: isDark ? const Color(0xFFD8B4FE) : const Color(0xFF7E22CE),
                        ),
                      ),
                    ),
                ],
              ),

              const SizedBox(height: 16),

              // ==========================================
              // 2. HERO TRANSACTION: Merchant Avatar, Name & Amount
              // ==========================================
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      color: heroBgColor,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: amountColor.withOpacity(0.3),
                        width: 1.5,
                      ),
                    ),
                    child: Center(
                      child: Icon(
                        heroIcon,
                        color: amountColor,
                        size: 26,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      counterParty,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                        letterSpacing: -0.3,
                        height: 1.25,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    formattedAmount,
                    style: TextStyle(
                      color: amountColor,
                      fontWeight: FontWeight.w800,
                      fontSize: 23,
                      letterSpacing: -0.5,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 18),

              // ==========================================
              // 3. TRANSACTION TYPE TOGGLE (Expense | Income | Transfer)
              // ==========================================
              Container(
                height: 48,
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.4),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    _buildTypeOption(
                      title: 'Expense',
                      icon: Icons.north_east_rounded,
                      isSelected: isExpense,
                      activeColor: const Color(0xFFDC2626),
                      activeBgColor: isDark ? const Color(0xFF450A0A) : Colors.white,
                      onTap: () => setState(() => _transactionType = 'expense'),
                    ),
                    const SizedBox(width: 4),
                    _buildTypeOption(
                      title: 'Income',
                      icon: Icons.south_west_rounded,
                      isSelected: isIncome,
                      activeColor: const Color(0xFF16A34A),
                      activeBgColor: isDark ? const Color(0xFF052E16) : Colors.white,
                      onTap: () => setState(() => _transactionType = 'income'),
                    ),
                    const SizedBox(width: 4),
                    _buildTypeOption(
                      title: 'Transfer',
                      icon: Icons.swap_horiz_rounded,
                      isSelected: isTransfer,
                      activeColor: const Color(0xFF2563EB),
                      activeBgColor: isDark ? const Color(0xFF172554) : Colors.white,
                      onTap: () => setState(() => _transactionType = 'transfer'),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // ==========================================
              // 4. CATEGORY & ACCOUNT SELECTION
              // ==========================================
              if (isTransfer) ...[
                // Transfer Mode: Stacked Source and Destination Accounts
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF1E293B).withOpacity(0.5)
                        : const Color(0xFFF0F7FF),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: isDark
                          ? const Color(0xFF3B82F6).withOpacity(0.3)
                          : const Color(0xFFBFDBFE),
                      width: 1.2,
                    ),
                  ),
                  child: Column(
                    children: [
                      // FROM Account
                      InkWell(
                        onTap: () => _openAccountPicker(isTarget: false),
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surface,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: _selectedAccountId != null
                                  ? theme.colorScheme.outlineVariant.withOpacity(0.6)
                                  : Colors.orange.shade400,
                              width: 1.2,
                            ),
                          ),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 18,
                                backgroundColor: isDark
                                    ? Colors.red.shade900.withOpacity(0.4)
                                    : Colors.red.shade50,
                                child: Icon(Icons.arrow_upward_rounded, size: 18, color: Colors.red.shade700),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Text(
                                          'FROM',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: 0.8,
                                            color: _selectedAccountId != null
                                                ? (isDark ? Colors.blue.shade300 : const Color(0xFF2563EB))
                                                : Colors.red.shade700,
                                          ),
                                        ),
                                        if (_selectedAccountId == null) ...[
                                          const SizedBox(width: 6),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                            decoration: BoxDecoration(
                                              color: Colors.red.withOpacity(0.12),
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              'REQUIRED',
                                              style: TextStyle(
                                                fontSize: 9,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.red.shade700,
                                              ),
                                            ),
                                          ),
                                        ],
                                        if (last4 != null) ...[
                                          const SizedBox(width: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                            decoration: BoxDecoration(
                                              color: Colors.red.withOpacity(0.1),
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              'SMS: •••• $last4',
                                              style: TextStyle(
                                                fontSize: 9.5,
                                                fontWeight: FontWeight.w600,
                                                color: Colors.red.shade700,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      _selectedAccountName ??
                                          (last4 != null ? 'Select From account (•••• $last4)' : 'Select From account'),
                                      style: TextStyle(
                                        fontSize: 14.5,
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
                              const Icon(Icons.keyboard_arrow_down_rounded, size: 22, color: Colors.grey),
                            ],
                          ),
                        ),
                      ),

                      // Connector
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          children: [
                            const Expanded(child: Divider(thickness: 1)),
                            Container(
                              padding: const EdgeInsets.all(5),
                              decoration: const BoxDecoration(
                                color: Color(0xFF2563EB),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.arrow_downward_rounded,
                                size: 14,
                                color: Colors.white,
                              ),
                            ),
                            const Expanded(child: Divider(thickness: 1)),
                          ],
                        ),
                      ),

                      // TO Account
                      InkWell(
                        onTap: () => _openAccountPicker(isTarget: true),
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surface,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: _selectedTransferToAccountId != null
                                  ? theme.colorScheme.outlineVariant.withOpacity(0.6)
                                  : Colors.orange.shade600,
                              width: _selectedTransferToAccountId != null ? 1.2 : 1.5,
                            ),
                          ),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 18,
                                backgroundColor: isDark
                                    ? Colors.green.shade900.withOpacity(0.4)
                                    : Colors.green.shade50,
                                child: Icon(Icons.arrow_downward_rounded, size: 18, color: Colors.green.shade700),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Text(
                                          'TO',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: 0.8,
                                            color: _selectedTransferToAccountId != null
                                                ? (isDark ? Colors.green.shade300 : const Color(0xFF16A34A))
                                                : Colors.orange.shade700,
                                          ),
                                        ),
                                        if (_selectedTransferToAccountId == null) ...[
                                          const SizedBox(width: 6),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                            decoration: BoxDecoration(
                                              color: Colors.orange.withOpacity(0.15),
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              'REQUIRED',
                                              style: TextStyle(
                                                fontSize: 9,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.orange.shade800,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      _selectedTransferToAccountName ?? 'Select To account',
                                      style: TextStyle(
                                        fontSize: 14.5,
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
                              Icon(
                                _selectedTransferToAccountId != null
                                    ? Icons.keyboard_arrow_down_rounded
                                    : Icons.touch_app_rounded,
                                size: 22,
                                color: _selectedTransferToAccountId != null ? Colors.grey : Colors.orange.shade700,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ] else ...[
                // Expense & Income Mode: Stacked Full-Width Category & Account Pickers
                // 1. Category Selector
                InkWell(
                  onTap: _openCategoryPicker,
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: _selectedCategoryName != null
                            ? theme.colorScheme.primary.withOpacity(0.4)
                            : Colors.orange.shade400,
                        width: 1.2,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            Icons.category_rounded,
                            size: 20,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    'CATEGORY',
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.6,
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                  if (_selectedCategoryId == null) ...[
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                      decoration: BoxDecoration(
                                        color: Colors.orange.withOpacity(0.15),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        'REQUIRED',
                                        style: TextStyle(
                                          fontSize: 9,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.orange.shade800,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 3),
                              Text(
                                _selectedCategoryName ?? 'Select Category',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: _selectedCategoryName != null
                                      ? theme.colorScheme.onSurface
                                      : Colors.orange.shade800,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          Icons.keyboard_arrow_down_rounded,
                          size: 24,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                // 2. Account Selector
                InkWell(
                  onTap: () => _openAccountPicker(isTarget: false),
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: _selectedAccountName != null
                            ? theme.colorScheme.primary.withOpacity(0.4)
                            : Colors.orange.shade400,
                        width: 1.2,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: const Color(0xFF2563EB).withOpacity(0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.account_balance_wallet_rounded,
                            size: 20,
                            color: Color(0xFF2563EB),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    'ACCOUNT',
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.6,
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                  if (_selectedAccountId == null) ...[
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                      decoration: BoxDecoration(
                                        color: Colors.orange.withOpacity(0.15),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        'REQUIRED',
                                        style: TextStyle(
                                          fontSize: 9,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.orange.shade800,
                                        ),
                                      ),
                                    ),
                                  ],
                                  if (last4 != null) ...[
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                      decoration: BoxDecoration(
                                        color: Colors.green.withOpacity(0.12),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        'SMS: •••• $last4',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.green.shade700,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 3),
                              Text(
                                _selectedAccountName ??
                                    (last4 != null
                                        ? 'Select account (•••• $last4)'
                                        : 'Select Account'),
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
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
                        Icon(
                          Icons.keyboard_arrow_down_rounded,
                          size: 24,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ],
                    ),
                  ),
                ),
              ],

              // Optional Note / Reference Info
              if ((refNumber != null && refNumber.isNotEmpty) || (note != null && note.isNotEmpty)) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.25),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (refNumber != null && refNumber.isNotEmpty)
                        Row(
                          children: [
                            Icon(Icons.receipt_long_outlined, size: 15, color: theme.colorScheme.outline),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Ref: $refNumber',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.outline,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                      if (refNumber != null && refNumber.isNotEmpty && note != null && note.isNotEmpty)
                        const SizedBox(height: 6),
                      if (note != null && note.isNotEmpty)
                        Row(
                          children: [
                            Icon(Icons.sticky_note_2_outlined, size: 15, color: theme.colorScheme.outline),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                note,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.outline,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ],

              // ==========================================
              // 5. COLLAPSIBLE ORIGINAL SMS MESSAGE
              // ==========================================
              if (rawText.isNotEmpty) ...[
                const SizedBox(height: 14),
                InkWell(
                  onTap: () => setState(() => _showRawText = !_showRawText),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: theme.colorScheme.outlineVariant.withOpacity(0.4),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.sms_outlined,
                          size: 16,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _showRawText ? 'Hide original message' : 'View original message',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                            fontSize: 12.5,
                          ),
                        ),
                        const Spacer(),
                        Icon(
                          _showRawText ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                          size: 20,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ],
                    ),
                  ),
                ),
                if (_showRawText)
                  Container(
                    margin: const EdgeInsets.only(top: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.35),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: theme.colorScheme.outlineVariant.withOpacity(0.4),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: SelectableText(
                            rawText,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontFamily: 'monospace',
                              fontSize: 12,
                              height: 1.4,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.copy_rounded, size: 18),
                          tooltip: 'Copy SMS',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: rawText));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Message copied to clipboard'),
                                duration: Duration(seconds: 1),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
              ],

              const SizedBox(height: 20),

              // ==========================================
              // 6. SPACIOUS ACTION BUTTONS (Reject & Approve)
              // ==========================================
              Row(
                children: [
                  // Reject Button
                  Expanded(
                    flex: 2,
                    child: SizedBox(
                      height: 52,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          foregroundColor: isDark ? const Color(0xFFF87171) : const Color(0xFFDC2626),
                          side: BorderSide(
                            color: isDark ? const Color(0xFF7F1D1D) : const Color(0xFFFECACA),
                            width: 1.5,
                          ),
                          backgroundColor: isDark
                              ? const Color(0xFF450A0A).withOpacity(0.3)
                              : const Color(0xFFFEF2F2),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        icon: const Icon(Icons.close_rounded, size: 20),
                        label: const FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            'Reject',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                            maxLines: 1,
                          ),
                        ),
                        onPressed: _isProcessing ? null : _handleReject,
                      ),
                    ),
                  ),

                  const SizedBox(width: 12),

                  // Approve & Sync Button
                  Expanded(
                    flex: 3,
                    child: SizedBox(
                      height: 52,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          backgroundColor: isTransfer
                              ? const Color(0xFF2563EB)
                              : const Color(0xFF16A34A),
                          foregroundColor: Colors.white,
                          elevation: 1,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        icon: _isProcessing
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2.4,
                                ),
                              )
                            : Icon(
                                isTransfer ? Icons.swap_horiz_rounded : Icons.check_circle_outline_rounded,
                                size: 20,
                              ),
                        label: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            isTransfer ? 'Transfer & Sync' : 'Approve & Sync',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                            maxLines: 1,
                          ),
                        ),
                        onPressed: _isProcessing ? null : _handleApprove,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTypeOption({
    required String title,
    required IconData icon,
    required bool isSelected,
    required Color activeColor,
    required Color activeBgColor,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            color: isSelected ? activeBgColor : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: isSelected
                ? Border.all(color: activeColor.withOpacity(0.4), width: 1.2)
                : null,
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.04),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          alignment: Alignment.center,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 16,
                color: isSelected ? activeColor : Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.7),
              ),
              const SizedBox(width: 5),
              Text(
                title,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                  color: isSelected ? activeColor : Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.7),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
