import 'dart:async';
import 'package:flutter/material.dart';

class CategoryPicker extends StatefulWidget {
  final List<dynamic> categories;
  final String? selectedCategoryId;
  final List<Map<String, dynamic>>? recentCategories;
  final ValueChanged<Map<String, dynamic>> onSelect;

  const CategoryPicker({
    super.key,
    required this.categories,
    this.selectedCategoryId,
    this.recentCategories,
    required this.onSelect,
  });

  /// Static helper to display the CategoryPicker modal bottom sheet
  static Future<Map<String, dynamic>?> show(
    BuildContext context, {
    required List<dynamic> categories,
    String? selectedCategoryId,
    List<Map<String, dynamic>>? recentCategories,
  }) {
    return showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (_, scrollController) => Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: CategoryPicker(
            categories: categories,
            selectedCategoryId: selectedCategoryId,
            recentCategories: recentCategories,
            onSelect: (cat) => Navigator.pop(ctx, cat),
          ),
        ),
      ),
    );
  }

  @override
  State<CategoryPicker> createState() => _CategoryPickerState();
}

class _CategoryPickerState extends State<CategoryPicker> {
  final TextEditingController _searchController = TextEditingController();
  String _filter = '';
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
  }

  void _onSearchChanged() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 150), () {
      if (mounted) {
        final newFilter = _searchController.text.trim().toLowerCase();
        if (_filter != newFilter) {
          setState(() {
            _filter = newFilter;
          });
        }
      }
    });
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    int getUsage(dynamic c) {
      if (c is! Map) return 0;
      final u = c['usageCount'];
      if (u is int) return u;
      return int.tryParse(u?.toString() ?? '') ?? 0;
    }

    final filtered = widget.categories.where((cat) {
      if (_filter.isEmpty) return true;
      final name = (cat['name'] ?? '').toString().toLowerCase();
      final group = (cat['groupName'] ?? '').toString().toLowerCase();
      return name.contains(_filter) || group.contains(_filter);
    }).toList();

    if (_filter.isNotEmpty) {
      filtered.sort((a, b) {
        final uA = getUsage(a);
        final uB = getUsage(b);
        if (uB != uA) return uB.compareTo(uA);
        return (a['name'] ?? '').toString().compareTo((b['name'] ?? '').toString());
      });
    }

    // Group categories by groupName
    final Map<String, List<dynamic>> grouped = {};
    for (final cat in filtered) {
      final groupName = cat['groupName'] ?? 'General';
      grouped.putIfAbsent(groupName, () => []).add(cat);
    }

    for (final group in grouped.values) {
      group.sort((a, b) {
        final uA = getUsage(a);
        final uB = getUsage(b);
        if (uB != uA) return uB.compareTo(uA);
        return (a['name'] ?? '').toString().compareTo((b['name'] ?? '').toString());
      });
    }

    final sortedGroupKeys = grouped.keys.toList()
      ..sort((gA, gB) {
        final totalUsageA = grouped[gA]!.fold<int>(0, (sum, c) => sum + getUsage(c));
        final totalUsageB = grouped[gB]!.fold<int>(0, (sum, c) => sum + getUsage(c));
        if (totalUsageB != totalUsageA) return totalUsageB.compareTo(totalUsageA);
        return gA.compareTo(gB);
      });

    final popularCategories = widget.categories
        .where((c) => getUsage(c) > 0)
        .toList()
      ..sort((a, b) => getUsage(b).compareTo(getUsage(a)));
    final topPopular = popularCategories.take(6).toList();

    return Column(
      children: [
        // Handle bar
        Center(
          child: Container(
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: theme.colorScheme.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),

        // Title
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Select Category',
                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
        ),

        // Search Field
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Search categories...',
              prefixIcon: const Icon(Icons.search),
              filled: true,
              fillColor: theme.colorScheme.surfaceContainerHighest.withOpacity(0.5),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
            ),
          ),
        ),

        const SizedBox(height: 8),

        // Recent Categories Quick Chips (if available and not searching)
        if (_filter.isEmpty && widget.recentCategories != null && widget.recentCategories!.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.history_rounded, size: 14, color: theme.colorScheme.primary),
                    const SizedBox(width: 6),
                    Text(
                      'RECENT FOR THIS ACCOUNT',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: widget.recentCategories!.map((cat) {
                    final isSel = cat['id'] == widget.selectedCategoryId;
                    return InkWell(
                      onTap: () {
                        final match = widget.categories.firstWhere(
                          (c) => (c['walletCategoryId'] == cat['id'] || c['id'] == cat['id']),
                          orElse: () => {'walletCategoryId': cat['id'], 'name': cat['name']},
                        );
                        widget.onSelect(match as Map<String, dynamic>);
                      },
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                        decoration: BoxDecoration(
                          color: isSel
                              ? theme.colorScheme.primaryContainer
                              : theme.colorScheme.surfaceContainerHighest.withOpacity(0.5),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isSel ? theme.colorScheme.primary : theme.colorScheme.outlineVariant.withOpacity(0.5),
                            width: isSel ? 1.5 : 1.0,
                          ),
                        ),
                        child: Text(
                          cat['name'] ?? 'Category',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: isSel ? FontWeight.bold : FontWeight.w600,
                            color: isSel ? theme.colorScheme.onPrimaryContainer : theme.colorScheme.onSurface,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const Divider(height: 18),
              ],
            ),
          ),
        ],

        // Popular Categories from user history (if not searching)
        if (_filter.isEmpty && topPopular.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.star_rounded, size: 14, color: Color(0xFFF59E0B)),
                    const SizedBox(width: 6),
                    Text(
                      'POPULAR CATEGORIES',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: topPopular.map((cat) {
                    final catId = cat['walletCategoryId'] ?? cat['id'];
                    final isSel = catId == widget.selectedCategoryId;
                    return InkWell(
                      onTap: () {
                        widget.onSelect(cat as Map<String, dynamic>);
                      },
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                        decoration: BoxDecoration(
                          color: isSel
                              ? theme.colorScheme.primaryContainer
                              : theme.colorScheme.surfaceContainerHighest.withOpacity(0.5),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isSel ? theme.colorScheme.primary : theme.colorScheme.outlineVariant.withOpacity(0.5),
                            width: isSel ? 1.5 : 1.0,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              cat['name'] ?? 'Category',
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: isSel ? FontWeight.bold : FontWeight.w600,
                                color: isSel ? theme.colorScheme.onPrimaryContainer : theme.colorScheme.onSurface,
                              ),
                            ),
                            if (isSel) ...[
                              const SizedBox(width: 4),
                              Icon(Icons.check, size: 13, color: theme.colorScheme.primary),
                            ],
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const Divider(height: 18),
              ],
            ),
          ),
        ],

        // Category List
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.search_off, size: 48, color: theme.colorScheme.outline),
                      const SizedBox(height: 8),
                      Text('No categories match "$_filter"', style: theme.textTheme.bodyMedium),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: sortedGroupKeys.length,
                  itemBuilder: (context, groupIndex) {
                    final groupName = sortedGroupKeys[groupIndex];
                    final groupItems = grouped[groupName]!;

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 16, bottom: 6, left: 4),
                          child: Text(
                            groupName.toUpperCase(),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.1,
                            ),
                          ),
                        ),
                        ...groupItems.map((cat) {
                          final isSelected = cat['walletCategoryId'] == widget.selectedCategoryId;
                          return Card(
                            elevation: 0,
                            color: isSelected
                                ? theme.colorScheme.primaryContainer.withOpacity(0.4)
                                : theme.colorScheme.surface,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(
                                color: isSelected
                                    ? theme.colorScheme.primary
                                    : theme.colorScheme.outlineVariant.withOpacity(0.5),
                              ),
                            ),
                            margin: const EdgeInsets.symmetric(vertical: 3),
                            child: ListTile(
                              dense: true,
                              title: Text(
                                cat['name'] ?? 'Unnamed Category',
                                style: TextStyle(
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                ),
                              ),
                              trailing: isSelected
                                  ? Icon(Icons.check_circle, color: theme.colorScheme.primary, size: 20)
                                  : null,
                              onTap: () => widget.onSelect(cat),
                            ),
                          );
                        }),
                      ],
                    );
                  },
                ),
        ),
      ],
    );
  }
}
