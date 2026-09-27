import 'package:flutter/material.dart';

class CategoryPicker extends StatefulWidget {
  final List<dynamic> categories;
  final String? selectedCategoryId;
  final ValueChanged<Map<String, dynamic>> onSelect;

  const CategoryPicker({
    super.key,
    required this.categories,
    this.selectedCategoryId,
    required this.onSelect,
  });

  /// Static helper to display the CategoryPicker modal bottom sheet
  static Future<Map<String, dynamic>?> show(
    BuildContext context, {
    required List<dynamic> categories,
    String? selectedCategoryId,
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

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() {
        _filter = _searchController.text.trim().toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final filtered = widget.categories.where((cat) {
      if (_filter.isEmpty) return true;
      final name = (cat['name'] ?? '').toString().toLowerCase();
      final group = (cat['groupName'] ?? '').toString().toLowerCase();
      return name.contains(_filter) || group.contains(_filter);
    }).toList();

    // Group categories by groupName
    final Map<String, List<dynamic>> grouped = {};
    for (final cat in filtered) {
      final groupName = cat['groupName'] ?? 'General';
      grouped.putIfAbsent(groupName, () => []).add(cat);
    }

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
                  itemCount: grouped.keys.length,
                  itemBuilder: (context, groupIndex) {
                    final groupName = grouped.keys.elementAt(groupIndex);
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
