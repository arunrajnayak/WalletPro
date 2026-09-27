import 'package:flutter/material.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../data/datasources/remote/api_client.dart';

class InsightsScreen extends StatefulWidget {
  const InsightsScreen({super.key});

  @override
  State<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends State<InsightsScreen> {
  final ApiClient _api = ApiClient();

  bool _isLoading = true;
  String? _error;

  // Selected period: 0 = This Month, 1 = Last Month, 2 = Past 6 Months
  int _selectedPeriodIndex = 0;

  Map<String, dynamic>? _monthlyData;
  List<dynamic> _budgets = [];
  List<dynamic> _cardinality = [];
  List<dynamic> _merchants = [];
  List<dynamic> _trends = [];

  @override
  void initState() {
    super.initState();
    _loadInsights();
  }

  Future<void> _loadInsights({bool forceRefresh = false}) async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final now = DateTime.now();
      int? queryYear;
      int? queryMonth;

      if (_selectedPeriodIndex == 1) {
        // Last Month
        final prevMonth = DateTime(now.year, now.month - 1, 1);
        queryYear = prevMonth.year;
        queryMonth = prevMonth.month;
      }

      final futures = await Future.wait([
        _api.getInsightsMonthly(year: queryYear, month: queryMonth, forceRefresh: forceRefresh),
        _api.getInsightsBudgets(forceRefresh: forceRefresh),
        _api.getInsightsCardinality(forceRefresh: forceRefresh),
        _api.getInsightsMerchants(forceRefresh: forceRefresh),
        _api.getInsightsTrends(forceRefresh: forceRefresh),
      ]);

      if (mounted) {
        setState(() {
          _monthlyData = futures[0] as Map<String, dynamic>;
          _budgets = (futures[1] as Map<String, dynamic>)['budgets'] ?? [];
          _cardinality = (futures[2] as Map<String, dynamic>)['cardinality'] ?? [];
          _merchants = (futures[3] as Map<String, dynamic>)['merchants'] ?? [];
          _trends = (futures[4] as Map<String, dynamic>)['trends'] ?? [];
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to load insights: $e';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Insights & Analytics'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
            onPressed: () => _loadInsights(forceRefresh: true),
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
                        FilledButton.icon(
                          icon: const Icon(Icons.refresh),
                          label: const Text('Retry'),
                          onPressed: () => _loadInsights(forceRefresh: true),
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: () => _loadInsights(forceRefresh: true),
                  child: ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    children: [
                      // 1. Period Selector Tabs
                      _buildPeriodSelector(theme, isDark),

                      const SizedBox(height: 16),

                      // 2. Net Cashflow Hero Card
                      _buildCashflowHeroCard(theme, isDark),

                      const SizedBox(height: 16),

                      // 3. Live Budget Progress Section
                      if (_budgets.isNotEmpty) ...[
                        _buildBudgetsSection(theme, isDark),
                        const SizedBox(height: 16),
                      ],

                      // 4. Category Breakdown Section
                      _buildCategorySection(theme, isDark),

                      const SizedBox(height: 16),

                      // 5. Discretionary vs Essential ("Must" vs "Want") Section
                      if (_cardinality.isNotEmpty) ...[
                        _buildCardinalitySection(theme, isDark),
                        const SizedBox(height: 16),
                      ],

                      // 6. Top Merchants Section
                      if (_merchants.isNotEmpty) ...[
                        _buildMerchantsSection(theme, isDark),
                        const SizedBox(height: 16),
                      ],

                      // 7. Monthly Trends Chart Section
                      if (_trends.isNotEmpty) ...[
                        _buildTrendsSection(theme, isDark),
                        const SizedBox(height: 24),
                      ],
                    ],
                  ),
                ),
    );
  }

  Widget _buildPeriodSelector(ThemeData theme, bool isDark) {
    return Container(
      height: 42,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.5),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          _buildPeriodTab('This Month', 0, theme, isDark),
          const SizedBox(width: 4),
          _buildPeriodTab('Last Month', 1, theme, isDark),
          const SizedBox(width: 4),
          _buildPeriodTab('6-Mo Trends', 2, theme, isDark),
        ],
      ),
    );
  }

  Widget _buildPeriodTab(String title, int index, ThemeData theme, bool isDark) {
    final isSelected = _selectedPeriodIndex == index;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          if (_selectedPeriodIndex != index) {
            setState(() => _selectedPeriodIndex = index);
            _loadInsights();
          }
        },
        child: Container(
          decoration: BoxDecoration(
            color: isSelected
                ? (isDark ? theme.colorScheme.surface : Colors.white)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
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
          child: Text(
            title,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              color: isSelected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant.withOpacity(0.8),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCashflowHeroCard(ThemeData theme, bool isDark) {
    final totalExpenses = (_monthlyData?['totalExpenses'] as num?)?.toDouble() ?? 0.0;
    final totalIncome = (_monthlyData?['totalIncome'] as num?)?.toDouble() ?? 0.0;
    final netSavings = (_monthlyData?['netSavings'] as num?)?.toDouble() ?? 0.0;
    final savingsRate = _monthlyData?['savingsRate']?.toString() ?? '0';
    final txCount = _monthlyData?['transactionCount'] ?? 0;
    final isPositiveSavings = netSavings >= 0;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.colorScheme.outlineVariant.withOpacity(0.5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.2 : 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'NET CASHFLOW',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.8,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: isPositiveSavings
                      ? Colors.green.shade50
                      : Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isPositiveSavings ? Colors.green.shade200 : Colors.red.shade200,
                    width: 0.8,
                  ),
                ),
                child: Text(
                  '$savingsRate% Savings Rate',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.bold,
                    color: isPositiveSavings ? Colors.green.shade800 : Colors.red.shade800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            CurrencyFormatter.formatINR(netSavings),
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
              color: isPositiveSavings
                  ? (isDark ? const Color(0xFF4ADE80) : const Color(0xFF16A34A))
                  : (isDark ? const Color(0xFFF87171) : const Color(0xFFDC2626)),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '$txCount total transactions recorded',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const Divider(height: 24),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.arrow_downward_rounded, size: 14, color: Colors.green.shade700),
                        const SizedBox(width: 4),
                        Text(
                          'Income',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      CurrencyFormatter.formatINR(totalIncome),
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: isDark ? const Color(0xFF4ADE80) : Colors.green.shade700,
                      ),
                    ),
                  ],
                ),
              ),
              Container(width: 1, height: 36, color: theme.colorScheme.outlineVariant.withOpacity(0.5)),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.arrow_upward_rounded, size: 14, color: Colors.red.shade700),
                        const SizedBox(width: 4),
                        Text(
                          'Expenses',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      CurrencyFormatter.formatINR(totalExpenses),
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: isDark ? const Color(0xFFF87171) : Colors.red.shade700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBudgetsSection(ThemeData theme, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Live Budget Health',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
            Text(
              '${_budgets.length} active',
              style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 130,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: _budgets.length,
            itemBuilder: (context, index) {
              final b = _budgets[index];
              final limit = (b['limit'] as num?)?.toDouble() ?? 0.0;
              final spent = (b['spent'] as num?)?.toDouble() ?? 0.0;
              final remaining = (b['remaining'] as num?)?.toDouble() ?? 0.0;
              final percentage = (b['percentage'] as num?)?.toInt() ?? 0;
              final status = b['status'] ?? 'on_track';

              Color progressColor;
              if (status == 'exceeded') {
                progressColor = Colors.red.shade600;
              } else if (status == 'warning') {
                progressColor = Colors.orange.shade600;
              } else {
                progressColor = Colors.green.shade600;
              }

              return Container(
                width: 220,
                margin: const EdgeInsets.only(right: 12),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: theme.colorScheme.outlineVariant.withOpacity(0.6)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            b['name'] ?? 'Budget',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: progressColor.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '$percentage%',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: progressColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: (percentage / 100).clamp(0.0, 1.0),
                            backgroundColor: theme.colorScheme.surfaceContainerHighest,
                            color: progressColor,
                            minHeight: 6,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Spent: ${CurrencyFormatter.formatINR(spent, compact: true)}',
                              style: TextStyle(fontSize: 10.5, color: theme.colorScheme.onSurfaceVariant),
                            ),
                            Text(
                              'Cap: ${CurrencyFormatter.formatINR(limit, compact: true)}',
                              style: TextStyle(fontSize: 10.5, color: theme.colorScheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ],
                    ),
                    Text(
                      remaining > 0
                          ? '${CurrencyFormatter.formatINR(remaining)} left'
                          : 'Limit exceeded!',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: remaining > 0 ? theme.colorScheme.onSurface : Colors.red.shade700,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildCategorySection(ThemeData theme, bool isDark) {
    final categories = (_monthlyData?['categorySummary'] as List<dynamic>?) ?? [];

    return Container(
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
              const Text(
                'Spending by Category',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              Text(
                '${categories.length} categories',
                style: TextStyle(fontSize: 11.5, color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (categories.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(child: Text('No expense records for this period')),
            )
          else
            ...categories.take(6).map((cat) {
              final name = cat['categoryName'] ?? 'Uncategorized';
              final amt = (cat['amount'] as num?)?.toDouble() ?? 0.0;
              final pct = double.tryParse(cat['percentage']?.toString() ?? '0') ?? 0.0;

              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            CircleAvatar(
                              radius: 14,
                              backgroundColor: theme.colorScheme.primaryContainer.withOpacity(0.5),
                              child: Icon(Icons.category_outlined, size: 14, color: theme.colorScheme.primary),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              name,
                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
                            ),
                          ],
                        ),
                        Text(
                          CurrencyFormatter.formatINR(amt),
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: (pct / 100).clamp(0.01, 1.0),
                        backgroundColor: theme.colorScheme.surfaceContainerHighest,
                        color: theme.colorScheme.primary,
                        minHeight: 5,
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildCardinalitySection(ThemeData theme, bool isDark) {
    return Container(
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
              const Text(
                'Needs vs. Wants (Cardinality)',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.purple.shade50,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'Wallet Native',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.purple.shade800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Discretionary vs essential spending breakdown',
            style: TextStyle(fontSize: 11.5, color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 14),
          Row(
            children: _cardinality.map((item) {
              final cardType = item['cardinality']?.toString().toLowerCase() ?? 'other';
              final amt = (item['amount'] as num?)?.toDouble() ?? 0.0;
              final pct = item['percentage']?.toString() ?? '0';

              String label;
              Color color;
              if (cardType == 'must' || cardType == 'need') {
                label = 'Needs (Must)';
                color = const Color(0xFF0284C7); // Sky blue
              } else if (cardType == 'want') {
                label = 'Wants (Fun)';
                color = const Color(0xFFD97706); // Amber
              } else {
                label = 'Other';
                color = const Color(0xFF64748B); // Slate
              }

              return Expanded(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: color.withOpacity(0.25)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color)),
                      const SizedBox(height: 4),
                      Text(
                        CurrencyFormatter.formatINR(amt, compact: true),
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                      Text('$pct%', style: TextStyle(fontSize: 10.5, color: theme.colorScheme.onSurfaceVariant)),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildMerchantsSection(ThemeData theme, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.colorScheme.outlineVariant.withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Top Spending Merchants',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          ..._merchants.take(5).map((m) {
            final name = m['merchant'] ?? 'Merchant';
            final amt = (m['amount'] as num?)?.toDouble() ?? 0.0;
            final count = m['count'] ?? 1;

            return ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              leading: CircleAvatar(
                radius: 16,
                backgroundColor: theme.colorScheme.secondaryContainer.withOpacity(0.4),
                child: const Icon(Icons.storefront_outlined, size: 16),
              ),
              title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
              subtitle: Text('$count transaction${count > 1 ? 's' : ''}', style: const TextStyle(fontSize: 11)),
              trailing: Text(
                CurrencyFormatter.formatINR(amt),
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildTrendsSection(ThemeData theme, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.colorScheme.outlineVariant.withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '6-Month Financial Trends',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          Text(
            'Historical comparison of monthly income and expenses',
            style: TextStyle(fontSize: 11.5, color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          Column(
            children: _trends.map((t) {
              final month = t['month'] ?? '';
              final exp = (t['expenses'] as num?)?.toDouble() ?? 0.0;
              final inc = (t['income'] as num?)?.toDouble() ?? 0.0;

              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    SizedBox(
                      width: 65,
                      child: Text(
                        month,
                        style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold),
                      ),
                    ),
                    Expanded(
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Container(width: 8, height: 8, color: Colors.green.shade600),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  CurrencyFormatter.formatINR(inc, compact: true),
                                  style: TextStyle(fontSize: 11, color: Colors.green.shade700, fontWeight: FontWeight.w600),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Container(width: 8, height: 8, color: Colors.red.shade600),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  CurrencyFormatter.formatINR(exp, compact: true),
                                  style: TextStyle(fontSize: 11, color: Colors.red.shade700, fontWeight: FontWeight.w600),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
