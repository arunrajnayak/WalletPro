import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/utils/currency_formatter.dart';
import '../../core/utils/date_formatter.dart';
import '../../core/utils/account_sorter.dart';
import 'category_picker.dart';

/// State representation of the card's active form fields
class ReviewDeckCardState {
  String transactionType;
  String? selectedAccountId;
  String? selectedAccountName;
  String? selectedCategoryId;
  String? selectedCategoryName;
  String? selectedTransferToAccountId;
  String? selectedTransferToAccountName;

  ReviewDeckCardState({
    required this.transactionType,
    this.selectedAccountId,
    this.selectedAccountName,
    this.selectedCategoryId,
    this.selectedCategoryName,
    this.selectedTransferToAccountId,
    this.selectedTransferToAccountName,
  });

  bool get isTransfer => transactionType == 'transfer';

  /// Validates mandatory fields required for approval
  String? getValidationError() {
    if (isTransfer) {
      if (selectedAccountId == null) {
        return 'Please select From account for transfer';
      }
      if (selectedTransferToAccountId == null) {
        return 'Please select To account for transfer';
      }
      if (selectedAccountId == selectedTransferToAccountId) {
        return 'From and To accounts must be different';
      }
    } else {
      if (selectedAccountId == null) {
        return 'Please select an Account to approve';
      }
      if (selectedCategoryId == null) {
        return 'Please select a Category to approve';
      }
    }
    return null;
  }
}

/// A dedicated Tinder-style review card designed for swipe deck interaction
class ReviewDeckCard extends StatefulWidget {
  final Map<String, dynamic> suggestion;
  final List<dynamic> categories;
  final List<dynamic> accounts;
  final double approveOpacity;
  final double rejectOpacity;
  final bool highlightMissingFields;
  final void Function(ReviewDeckCardState state)? onStateChanged;

  const ReviewDeckCard({
    super.key,
    required this.suggestion,
    required this.categories,
    required this.accounts,
    this.approveOpacity = 0.0,
    this.rejectOpacity = 0.0,
    this.highlightMissingFields = false,
    this.onStateChanged,
  });

  @override
  State<ReviewDeckCard> createState() => ReviewDeckCardControllerState();
}

class ReviewDeckCardControllerState extends State<ReviewDeckCard> {
  late String _transactionType;
  String? _selectedCategoryId;
  String? _selectedCategoryName;
  String? _selectedAccountId;
  String? _selectedAccountName;
  String? _selectedTransferToAccountId;
  String? _selectedTransferToAccountName;
  bool _showRawText = false;

  ReviewDeckCardState get currentState => ReviewDeckCardState(
        transactionType: _transactionType,
        selectedAccountId: _selectedAccountId,
        selectedAccountName: _selectedAccountName,
        selectedCategoryId: _selectedCategoryId,
        selectedCategoryName: _selectedCategoryName,
        selectedTransferToAccountId: _selectedTransferToAccountId,
        selectedTransferToAccountName: _selectedTransferToAccountName,
      );

  @override
  void initState() {
    super.initState();
    _initFromSuggestion();
  }

  @override
  void didUpdateWidget(covariant ReviewDeckCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.suggestion['id'] != widget.suggestion['id']) {
      _initFromSuggestion();
    }
  }

  void _notifyStateChanged() {
    widget.onStateChanged?.call(currentState);
  }

  void _initFromSuggestion() {
    _transactionType = (widget.suggestion['transactionType'] ?? 'expense').toString().toLowerCase();
    if (_transactionType != 'expense' && _transactionType != 'income' && _transactionType != 'transfer') {
      _transactionType = 'expense';
    }

    _selectedCategoryId = widget.suggestion['walletCategoryId'];
    _selectedCategoryName = widget.suggestion['walletCategoryName'];
    _selectedAccountId = widget.suggestion['walletAccountId'];

    // Try matching account by last 4 digits if not mapped
    final last4 = widget.suggestion['accountLast4']?.toString().trim();
    if (_selectedAccountId == null && last4 != null && last4.isNotEmpty && last4 != 'NONE') {
      final match = widget.accounts.firstWhere(
        (acc) {
          final accLast4 = acc['last4Digits']?.toString().trim();
          return accLast4 != null && accLast4.isNotEmpty && accLast4 != 'NONE' && accLast4 == last4;
        },
        orElse: () => null,
      );
      if (match != null) {
        _selectedAccountId = match['walletAccountId'] ?? match['id'];
        _selectedAccountName = match['name'];
      }
    } else if (_selectedAccountId != null) {
      final match = widget.accounts.firstWhere(
        (acc) => (acc['walletAccountId'] == _selectedAccountId || acc['id'] == _selectedAccountId),
        orElse: () => null,
      );
      if (match != null) {
        _selectedAccountName = match['name'];
      }
    }

    // Match category name if ID is present
    if (_selectedCategoryId != null && _selectedCategoryName == null) {
      final catMatch = widget.categories.firstWhere(
        (cat) => (cat['walletCategoryId'] == _selectedCategoryId || cat['id'] == _selectedCategoryId),
        orElse: () => null,
      );
      if (catMatch != null) {
        _selectedCategoryName = catMatch['name'];
      }
    }

    _notifyStateChanged();
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
      _notifyStateChanged();
    }
  }

  void _openAccountPicker({bool isTarget = false}) async {
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
      _notifyStateChanged();
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
    final source = (widget.suggestion['source'] ?? 'SMS').toString().toUpperCase();
    final aiConfidence = widget.suggestion['aiConfidence'] != null
        ? double.tryParse(widget.suggestion['aiConfidence'].toString())
        : null;

    DateTime? txDate;
    if (widget.suggestion['transactionDate'] != null) {
      txDate = DateTime.tryParse(widget.suggestion['transactionDate'].toString());
    }

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
      heroIcon = Icons.south_west_rounded;
    } else {
      formattedAmount = '-${CurrencyFormatter.formatINR(amountNum)}';
      amountColor = isDark ? const Color(0xFFF87171) : const Color(0xFFDC2626);
      heroBgColor = isDark ? const Color(0xFF7F1D1D).withOpacity(0.35) : const Color(0xFFFEF2F2);
      heroIcon = Icons.north_east_rounded;
    }

    final isCategoryMissing = !isTransfer && _selectedCategoryId == null;
    final isAccountMissing = !isTransfer && _selectedAccountId == null;
    final isTransferFromMissing = isTransfer && _selectedAccountId == null;
    final isTransferToMissing = isTransfer && _selectedTransferToAccountId == null;

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withOpacity(0.6),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.35 : 0.08),
            blurRadius: 16,
            spreadRadius: 1,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          children: [
            // Scrollable Card Content
            SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 1. Top Badges Row
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.6),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              source == 'SMS' ? Icons.sms_outlined : Icons.notifications_active_outlined,
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
                        Expanded(
                          child: Text(
                            DateFormatter.formatFull(txDate),
                            style: TextStyle(
                              color: theme.colorScheme.onSurfaceVariant,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
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

                  // 2. Hero Transaction Info
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: heroBgColor,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: amountColor.withOpacity(0.3),
                            width: 1.5,
                          ),
                        ),
                        child: Center(
                          child: Icon(heroIcon, color: amountColor, size: 26),
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
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          formattedAmount,
                          style: TextStyle(
                            color: amountColor,
                            fontWeight: FontWeight.w800,
                            fontSize: 22,
                            letterSpacing: -0.5,
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // 3. Transaction Type Segmented Toggle
                  Container(
                    height: 44,
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
                          onTap: () {
                            setState(() => _transactionType = 'expense');
                            _notifyStateChanged();
                          },
                        ),
                        const SizedBox(width: 4),
                        _buildTypeOption(
                          title: 'Income',
                          icon: Icons.south_west_rounded,
                          isSelected: isIncome,
                          activeColor: const Color(0xFF16A34A),
                          activeBgColor: isDark ? const Color(0xFF052E16) : Colors.white,
                          onTap: () {
                            setState(() => _transactionType = 'income');
                            _notifyStateChanged();
                          },
                        ),
                        const SizedBox(width: 4),
                        _buildTypeOption(
                          title: 'Transfer',
                          icon: Icons.swap_horiz_rounded,
                          isSelected: isTransfer,
                          activeColor: const Color(0xFF2563EB),
                          activeBgColor: isDark ? const Color(0xFF172554) : Colors.white,
                          onTap: () {
                            setState(() => _transactionType = 'transfer');
                            _notifyStateChanged();
                          },
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 14),

                  // 4. Category & Account Fields
                  if (isTransfer) ...[
                    // Transfer: From Account & To Account
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1E293B).withOpacity(0.5) : const Color(0xFFF0F7FF),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isDark ? const Color(0xFF3B82F6).withOpacity(0.3) : const Color(0xFFBFDBFE),
                          width: 1.2,
                        ),
                      ),
                      child: Column(
                        children: [
                          _buildAccountSelectorTile(
                            label: 'FROM ACCOUNT',
                            accountName: _selectedAccountName,
                            isMissing: isTransferFromMissing,
                            isWarning: widget.highlightMissingFields && isTransferFromMissing,
                            iconColor: Colors.red.shade400,
                            iconBgColor: isDark ? Colors.red.shade900.withOpacity(0.4) : const Color(0xFFFEF2F2),
                            onTap: () => _openAccountPicker(isTarget: false),
                          ),
                          const SizedBox(height: 10),
                          _buildAccountSelectorTile(
                            label: 'TO ACCOUNT',
                            accountName: _selectedTransferToAccountName,
                            isMissing: isTransferToMissing,
                            isWarning: widget.highlightMissingFields && isTransferToMissing,
                            iconColor: Colors.green.shade400,
                            iconBgColor: isDark ? Colors.green.shade900.withOpacity(0.4) : const Color(0xFFF0FDF4),
                            onTap: () => _openAccountPicker(isTarget: true),
                          ),
                        ],
                      ),
                    ),
                  ] else ...[
                    // Standard: Category & Account
                    _buildSelectionTile(
                      icon: Icons.category_rounded,
                      iconColor: theme.colorScheme.primary,
                      iconBg: theme.colorScheme.primary.withOpacity(0.12),
                      label: 'CATEGORY',
                      value: _selectedCategoryName,
                      placeholder: 'Select Category',
                      isMissing: isCategoryMissing,
                      isWarning: widget.highlightMissingFields && isCategoryMissing,
                      onTap: _openCategoryPicker,
                    ),
                    const SizedBox(height: 10),
                    _buildSelectionTile(
                      icon: Icons.account_balance_wallet_rounded,
                      iconColor: const Color(0xFF2563EB),
                      iconBg: const Color(0xFF2563EB).withOpacity(0.12),
                      label: 'ACCOUNT',
                      value: _selectedAccountName,
                      placeholder: 'Select Wallet Account',
                      isMissing: isAccountMissing,
                      isWarning: widget.highlightMissingFields && isAccountMissing,
                      onTap: () => _openAccountPicker(isTarget: false),
                    ),
                  ],

                  // 5. Collapsible Original Message
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
                                fontSize: 12,
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
                                  fontSize: 11.5,
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

                  const SizedBox(height: 16),

                  // 6. Subtle Swipe Guide Footnote
                  Center(
                    child: Text(
                      '👈 Swipe left to reject • Swipe right to approve 👉',
                      style: TextStyle(
                        fontSize: 11,
                        color: theme.colorScheme.outline.withOpacity(0.8),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ========================================================
            // STAMP OVERLAYS (Tinder Style)
            // ========================================================

            // 1. APPROVE Stamp (Top Left)
            if (widget.approveOpacity > 0.01)
              Positioned(
                top: 24,
                left: 20,
                child: Opacity(
                  opacity: widget.approveOpacity.clamp(0.0, 1.0),
                  child: Transform.rotate(
                    angle: -0.26, // -15 degrees
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF16A34A), width: 3.5),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.green.withOpacity(0.2),
                            blurRadius: 8,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                      child: const Text(
                        'APPROVE',
                        style: TextStyle(
                          color: Color(0xFF16A34A),
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 2,
                        ),
                      ),
                    ),
                  ),
                ),
              ),

            // 2. REJECT Stamp (Top Right)
            if (widget.rejectOpacity > 0.01)
              Positioned(
                top: 24,
                right: 20,
                child: Opacity(
                  opacity: widget.rejectOpacity.clamp(0.0, 1.0),
                  child: Transform.rotate(
                    angle: 0.26, // +15 degrees
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFDC2626), width: 3.5),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.red.withOpacity(0.2),
                            blurRadius: 8,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                      child: const Text(
                        'REJECT',
                        style: TextStyle(
                          color: Color(0xFFDC2626),
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 2,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
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
            border: isSelected ? Border.all(color: activeColor.withOpacity(0.4), width: 1.2) : null,
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
                size: 15,
                color: isSelected ? activeColor : Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.7),
              ),
              const SizedBox(width: 4),
              Text(
                title,
                style: TextStyle(
                  fontSize: 13,
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

  Widget _buildSelectionTile({
    required IconData icon,
    required Color iconColor,
    required Color iconBg,
    required String label,
    required String? value,
    required String placeholder,
    required bool isMissing,
    required bool isWarning,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final borderColor = isWarning
        ? Colors.red.shade500
        : (isMissing
            ? Colors.orange.shade400
            : (value != null ? theme.colorScheme.primary.withOpacity(0.4) : theme.colorScheme.outlineVariant.withOpacity(0.4)));

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isWarning
              ? Colors.red.withOpacity(0.06)
              : theme.colorScheme.surfaceContainerHighest.withOpacity(0.25),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor, width: isWarning ? 2.0 : 1.2),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 20, color: iconColor),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.6,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      if (isMissing) ...[
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
                              fontSize: 8.5,
                              fontWeight: FontWeight.bold,
                              color: Colors.orange.shade800,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value ?? placeholder,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      color: value != null ? theme.colorScheme.onSurface : Colors.orange.shade800,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Icon(Icons.keyboard_arrow_down_rounded, size: 22, color: theme.colorScheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }

  Widget _buildAccountSelectorTile({
    required String label,
    required String? accountName,
    required bool isMissing,
    required bool isWarning,
    required Color iconColor,
    required Color iconBgColor,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final borderColor = isWarning
        ? Colors.red.shade500
        : (isMissing ? Colors.orange.shade400 : theme.colorScheme.outlineVariant.withOpacity(0.6));

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: borderColor, width: isWarning ? 2.0 : 1.2),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: iconBgColor,
              child: Icon(Icons.account_balance_outlined, size: 16, color: iconColor),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      if (isMissing) ...[
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
                              fontSize: 8.5,
                              fontWeight: FontWeight.bold,
                              color: Colors.orange.shade800,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    accountName ?? 'Tap to select account',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: accountName != null ? theme.colorScheme.onSurface : Colors.orange.shade800,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Icon(
              accountName != null ? Icons.keyboard_arrow_down_rounded : Icons.touch_app_rounded,
              size: 20,
              color: accountName != null ? Colors.grey : Colors.orange.shade700,
            ),
          ],
        ),
      ),
    );
  }
}
