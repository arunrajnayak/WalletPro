import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'review_deck_card.dart';

class DeckActionHistory {
  final Map<String, dynamic> item;
  final String action; // 'approved' | 'rejected'
  final ReviewDeckCardState state;

  DeckActionHistory({
    required this.item,
    required this.action,
    required this.state,
  });
}

class SwipeableReviewDeck extends StatefulWidget {
  final List<dynamic> suggestions;
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
  final Future<void> Function(dynamic restoredItem)? onUndo;
  final VoidCallback onRefresh;
  final VoidCallback onScanSms;

  const SwipeableReviewDeck({
    super.key,
    required this.suggestions,
    required this.categories,
    required this.accounts,
    required this.onApprove,
    required this.onReject,
    this.onUndo,
    required this.onRefresh,
    required this.onScanSms,
  });

  @override
  State<SwipeableReviewDeck> createState() => _SwipeableReviewDeckState();
}

class _SwipeableReviewDeckState extends State<SwipeableReviewDeck>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<Offset> _slideAnimation;

  Offset _dragOffset = Offset.zero;
  bool _isAnimating = false;
  bool _highlightMissingFields = false;

  final Map<String, ReviewDeckCardState> _cardStates = {};
  final List<DeckActionHistory> _history = [];
  int _sessionApprovedCount = 0;
  int _sessionRejectedCount = 0;
  int _initialCount = 0;

  @override
  void initState() {
    super.initState();
    _initialCount = widget.suggestions.length;
    _slideAnimation = const AlwaysStoppedAnimation(Offset.zero);
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    _animController.addListener(() {
      setState(() {
        _dragOffset = _slideAnimation.value;
      });
    });
    _animController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _isAnimating = false;
      }
    });
  }

  @override
  void didUpdateWidget(covariant SwipeableReviewDeck oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_initialCount == 0 && widget.suggestions.isNotEmpty) {
      _initialCount = widget.suggestions.length;
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  ReviewDeckCardState _getOrCreateCardState(Map<String, dynamic> suggestion) {
    final id = suggestion['id'].toString();
    if (!_cardStates.containsKey(id)) {
      final type = (suggestion['transactionType'] ?? 'expense').toString().toLowerCase();
      _cardStates[id] = ReviewDeckCardState(
        transactionType: type == 'income' || type == 'transfer' ? type : 'expense',
        selectedAccountId: suggestion['walletAccountId'],
        selectedAccountName: suggestion['walletAccountName'],
        selectedCategoryId: suggestion['walletCategoryId'],
        selectedCategoryName: suggestion['walletCategoryName'],
      );
    }
    return _cardStates[id]!;
  }

  void _onCardStateChanged(String id, ReviewDeckCardState state) {
    _cardStates[id] = state;
  }

  void _triggerBounceBack([String? errorMessage]) {
    final screenWidth = MediaQuery.of(context).size.width;
    HapticFeedback.heavyImpact();

    setState(() {
      _highlightMissingFields = true;
      _isAnimating = true;
    });

    _slideAnimation = Tween<Offset>(
      begin: _dragOffset,
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animController,
      curve: Curves.elasticOut,
    ));

    _animController.forward(from: 0.0);

    if (errorMessage != null && mounted) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Expanded(child: Text(errorMessage)),
            ],
          ),
          backgroundColor: Colors.orange.shade800,
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }

    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _highlightMissingFields = false);
    });
  }

  void _completeSwipe(bool isApprove) {
    if (widget.suggestions.isEmpty || _isAnimating) return;
    final screenWidth = MediaQuery.of(context).size.width;
    final topItem = widget.suggestions.first as Map<String, dynamic>;
    final cardState = _getOrCreateCardState(topItem);

    if (isApprove) {
      final validationError = cardState.getValidationError();
      if (validationError != null) {
        _triggerBounceBack(validationError);
        return;
      }
    }

    setState(() => _isAnimating = true);
    final targetX = isApprove ? screenWidth * 1.4 : -screenWidth * 1.4;

    _slideAnimation = Tween<Offset>(
      begin: _dragOffset,
      end: Offset(targetX, 0),
    ).animate(CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutQuad,
    ));

    HapticFeedback.lightImpact();

    _animController.forward(from: 0.0).then((_) async {
      _history.add(DeckActionHistory(
        item: topItem,
        action: isApprove ? 'approved' : 'rejected',
        state: cardState,
      ));

      if (isApprove) {
        _sessionApprovedCount++;
      } else {
        _sessionRejectedCount++;
      }

      setState(() {
        _dragOffset = Offset.zero;
        _isAnimating = false;
      });

      if (isApprove) {
        await widget.onApprove(
          topItem['id'],
          walletAccountId: cardState.selectedAccountId,
          walletCategoryId: cardState.isTransfer ? null : cardState.selectedCategoryId,
          walletCategoryName: cardState.isTransfer ? 'Transfer' : cardState.selectedCategoryName,
          transactionType: cardState.transactionType,
          isTransfer: cardState.isTransfer,
          transferToAccountId: cardState.isTransfer ? cardState.selectedTransferToAccountId : null,
        );
      } else {
        await widget.onReject(topItem['id']);
      }
    });
  }

  Future<void> _handleUndo() async {
    if (_history.isEmpty || _isAnimating) return;
    final lastAction = _history.removeLast();

    HapticFeedback.mediumImpact();
    if (lastAction.action == 'approved') {
      _sessionApprovedCount = (_sessionApprovedCount - 1).clamp(0, 9999);
    } else {
      _sessionRejectedCount = (_sessionRejectedCount - 1).clamp(0, 9999);
    }

    if (widget.onUndo != null) {
      await widget.onUndo!(lastAction.item);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final suggestions = widget.suggestions;

    if (suggestions.isEmpty) {
      return _buildCelebrationScreen(theme);
    }

    final topItem = suggestions.first as Map<String, dynamic>;
    final topCardState = _getOrCreateCardState(topItem);
    final screenWidth = MediaQuery.of(context).size.width;
    final dragDx = _dragOffset.dx;

    final approveOpacity = (dragDx / 90).clamp(0.0, 1.0);
    final rejectOpacity = (-dragDx / 90).clamp(0.0, 1.0);
    final dragFraction = (dragDx.abs() / 150).clamp(0.0, 1.0);

    return Column(
      children: [
        // 1. Progress Header
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 8),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '${suggestions.length} pending',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.onPrimaryContainer,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Reviewing 1 of ${suggestions.length}',
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  if (_sessionApprovedCount > 0 || _sessionRejectedCount > 0)
                    Text(
                      '✓ $_sessionApprovedCount   ✕ $_sessionRejectedCount',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.outline,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: _initialCount > 0
                      ? ((_initialCount - suggestions.length) / _initialCount).clamp(0.0, 1.0)
                      : 0.0,
                  backgroundColor: theme.colorScheme.surfaceContainerHighest.withOpacity(0.5),
                  color: theme.colorScheme.primary,
                  minHeight: 5,
                ),
              ),
            ],
          ),
        ),

        // 2. Interactive Card Stack
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Stack(
              children: [
                // 3rd Card in Stack (Deep Backdrop)
                if (suggestions.length > 2)
                  Positioned.fill(
                    child: Transform.scale(
                      scale: 0.88,
                      child: Transform.translate(
                        offset: const Offset(0, 26),
                        child: Opacity(
                          opacity: 0.55,
                          child: ReviewDeckCard(
                            key: Key('deck_card_2_${suggestions[2]['id']}'),
                            suggestion: suggestions[2] as Map<String, dynamic>,
                            categories: widget.categories,
                            accounts: widget.accounts,
                          ),
                        ),
                      ),
                    ),
                  ),

                // 2nd Card in Stack (Smooth Transitioning)
                if (suggestions.length > 1)
                  Positioned.fill(
                    child: Transform.scale(
                      scale: ui.lerpDouble(0.94, 1.0, dragFraction)!,
                      child: Transform.translate(
                        offset: Offset(0, ui.lerpDouble(13.0, 0.0, dragFraction)!),
                        child: Opacity(
                          opacity: ui.lerpDouble(0.85, 1.0, dragFraction)!,
                          child: ReviewDeckCard(
                            key: Key('deck_card_1_${suggestions[1]['id']}'),
                            suggestion: suggestions[1] as Map<String, dynamic>,
                            categories: widget.categories,
                            accounts: widget.accounts,
                          ),
                        ),
                      ),
                    ),
                  ),

                // Top Card (Fully Interactive)
                Positioned.fill(
                  child: GestureDetector(
                    onHorizontalDragStart: (_) {
                      if (_isAnimating) return;
                      _animController.stop();
                    },
                    onHorizontalDragUpdate: (details) {
                      if (_isAnimating) return;
                      setState(() {
                        _dragOffset = Offset(_dragOffset.dx + details.primaryDelta!, 0);
                      });
                    },
                    onHorizontalDragEnd: (details) {
                      if (_isAnimating) return;
                      final velocityX = details.primaryVelocity ?? 0.0;
                      if (_dragOffset.dx > 100 || velocityX > 600) {
                        _completeSwipe(true);
                      } else if (_dragOffset.dx < -100 || velocityX < -600) {
                        _completeSwipe(false);
                      } else {
                        // Snap back smoothly to center
                        _slideAnimation = Tween<Offset>(
                          begin: _dragOffset,
                          end: Offset.zero,
                        ).animate(CurvedAnimation(
                          parent: _animController,
                          curve: Curves.easeOutBack,
                        ));
                        _animController.forward(from: 0.0);
                      }
                    },
                    child: Transform.translate(
                      offset: _dragOffset,
                      child: Transform.rotate(
                        angle: (_dragOffset.dx / screenWidth) * 0.35,
                        child: ReviewDeckCard(
                          key: Key('deck_card_top_${topItem['id']}'),
                          suggestion: topItem,
                          categories: widget.categories,
                          accounts: widget.accounts,
                          approveOpacity: approveOpacity,
                          rejectOpacity: rejectOpacity,
                          highlightMissingFields: _highlightMissingFields,
                          onStateChanged: (st) => _onCardStateChanged(topItem['id'].toString(), st),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        // 3. Floating Tinder Action Controls Bar
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 6, 24, 20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // ↺ Undo Button
              _buildActionButton(
                icon: Icons.replay_rounded,
                size: 50,
                iconSize: 24,
                color: const Color(0xFFF59E0B),
                bgColor: const Color(0xFFFFFBEB),
                darkBgColor: const Color(0xFF451A03).withOpacity(0.4),
                isEnabled: _history.isNotEmpty && !_isAnimating,
                tooltip: 'Undo last swipe',
                onTap: _handleUndo,
              ),

              // ❌ Reject Button (Swipe Left)
              _buildActionButton(
                icon: Icons.close_rounded,
                size: 64,
                iconSize: 32,
                color: const Color(0xFFDC2626),
                bgColor: const Color(0xFFFEF2F2),
                darkBgColor: const Color(0xFF450A0A).withOpacity(0.5),
                isEnabled: !_isAnimating,
                tooltip: 'Reject (Swipe Left)',
                onTap: () => _completeSwipe(false),
              ),

              // ✅ Approve & Sync Button (Swipe Right)
              _buildActionButton(
                icon: topCardState.isTransfer ? Icons.swap_horiz_rounded : Icons.check_rounded,
                size: 64,
                iconSize: 32,
                color: const Color(0xFF16A34A),
                bgColor: const Color(0xFFF0FDF4),
                darkBgColor: const Color(0xFF052E16).withOpacity(0.5),
                isEnabled: !_isAnimating,
                tooltip: topCardState.isTransfer ? 'Transfer & Sync (Swipe Right)' : 'Approve & Sync (Swipe Right)',
                onTap: () => _completeSwipe(true),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required double size,
    required double iconSize,
    required Color color,
    required Color bgColor,
    required Color darkBgColor,
    required bool isEnabled,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Opacity(
      opacity: isEnabled ? 1.0 : 0.35,
      child: Tooltip(
        message: tooltip,
        child: InkWell(
          onTap: isEnabled ? onTap : null,
          customBorder: const CircleBorder(),
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isDark ? darkBgColor : bgColor,
              border: Border.all(
                color: color.withOpacity(isDark ? 0.4 : 0.3),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: color.withOpacity(isDark ? 0.2 : 0.12),
                  blurRadius: 10,
                  spreadRadius: 1,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Center(
              child: Icon(
                icon,
                color: color,
                size: iconSize,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCelebrationScreen(ThemeData theme) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 90,
              height: 90,
              decoration: BoxDecoration(
                color: Colors.green.shade100.withOpacity(0.4),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.check_circle_outline_rounded,
                size: 56,
                color: Colors.green.shade700,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'All Caught Up! 🎉',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'You have reviewed all pending transaction suggestions.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            if (_sessionApprovedCount > 0 || _sessionRejectedCount > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.4),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: theme.colorScheme.outlineVariant.withOpacity(0.5),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.check_circle_rounded, color: Color(0xFF16A34A), size: 18),
                        const SizedBox(width: 6),
                        Text(
                          '$_sessionApprovedCount Approved',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                      ],
                    ),
                    const SizedBox(width: 16),
                    Container(width: 1, height: 16, color: Colors.grey.shade400),
                    const SizedBox(width: 16),
                    Row(
                      children: [
                        const Icon(Icons.cancel_rounded, color: Color(0xFFDC2626), size: 18),
                        const SizedBox(width: 6),
                        Text(
                          '$_sessionRejectedCount Rejected',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton.icon(
                icon: const Icon(Icons.sms_outlined),
                label: const Text('Scan SMS Inbox For New Messages'),
                onPressed: widget.onScanSms,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Refresh Queue'),
                onPressed: widget.onRefresh,
              ),
            ),
            if (_history.isNotEmpty) ...[
              const SizedBox(height: 12),
              TextButton.icon(
                icon: const Icon(Icons.replay_rounded, size: 18),
                label: const Text('Undo Last Review'),
                onPressed: _handleUndo,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
