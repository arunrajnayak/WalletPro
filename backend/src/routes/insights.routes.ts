import { Router, Request, Response } from 'express';
import { authenticate } from '../middleware/auth';
import { prisma } from '../prisma';
import { WalletClient } from '../services/wallet-client';

const router = Router();

function getMonthBoundaries(year?: number, month?: number) {
  const now = new Date();
  const y = year ?? now.getFullYear();
  const m = month !== undefined ? month : now.getMonth();

  const startOfMonth = new Date(Date.UTC(y, m, 1, 0, 0, 0));
  const endOfMonth = new Date(Date.UTC(y, m + 1, 1, 0, 0, 0));

  const startStr = startOfMonth.toISOString().split('T')[0];
  const endStr = endOfMonth.toISOString().split('T')[0];
  const monthKey = `${y}-${String(m + 1).padStart(2, '0')}`;

  return { startOfMonth, endOfMonth, startStr, endStr, monthKey };
}

// GET /api/insights/monthly - Monthly breakdown powered by Wallet records aggregation
router.get('/monthly', authenticate, async (req: Request, res: Response) => {
  const userId = req.user.id;
  const user = await prisma.user.findUnique({ where: { id: userId } });
  
  const queryYear = req.query.year ? parseInt(req.query.year as string) : undefined;
  const queryMonth = req.query.month ? parseInt(req.query.month as string) - 1 : undefined;
  const { startStr, endStr, monthKey, startOfMonth } = getMonthBoundaries(queryYear, queryMonth);

  // If Wallet is connected, use BudgetBakers native /records/aggregation for 100% accurate live data
  if (user?.walletApiToken) {
    try {
      const client = new WalletClient(user.walletApiToken);

      const [expenseRes, incomeRes, categoryRes] = await Promise.all([
        client.getRecordsAggregation({
          recordType: 'expense',
          isTransfer: false,
          recordDate: [`gte.${startStr}`, `lt.${endStr}`],
          compute: ['amount:absSum'],
        }).catch(() => null),

        client.getRecordsAggregation({
          recordType: 'income',
          isTransfer: false,
          recordDate: [`gte.${startStr}`, `lt.${endStr}`],
          compute: ['amount:sum'],
        }).catch(() => null),

        client.getRecordsAggregation({
          recordType: 'expense',
          isTransfer: false,
          recordDate: [`gte.${startStr}`, `lt.${endStr}`],
          groupBy: ['category:id', 'category:name'],
          compute: ['amount:absSum'],
          sortBy: ['-amount:absSum'],
          limit: 20,
        }).catch(() => null),
      ]);

      const totalExpenses = expenseRes?.results?.[0]?.['amount:absSum'] ?? 0;
      const totalIncome = incomeRes?.results?.[0]?.['amount:sum'] ?? 0;
      const transactionCount = (expenseRes?.results?.[0]?.count ?? 0) + (incomeRes?.results?.[0]?.count ?? 0);

      const categorySummary = (categoryRes?.results || []).map((cat: any) => ({
        categoryId: cat['category:id'] || 'unknown',
        categoryName: cat['category:name'] || 'Uncategorized',
        amount: Math.abs(cat['amount:absSum'] ?? 0),
        count: cat.count ?? 1,
        percentage: totalExpenses > 0 ? ((Math.abs(cat['amount:absSum'] ?? 0) / totalExpenses) * 100).toFixed(1) : '0',
      }));

      return res.json({
        month: monthKey,
        totalExpenses,
        totalIncome,
        netSavings: totalIncome - totalExpenses,
        savingsRate: totalIncome > 0 ? (((totalIncome - totalExpenses) / totalIncome) * 100).toFixed(1) : '0',
        categorySummary,
        transactionCount,
        source: 'wallet_native',
      });
    } catch (err: any) {
      console.warn('Native aggregation failed, falling back to local records:', err.message);
    }
  }

  // Fallback: Group synced suggestions for this month from local DB
  const suggestions = await prisma.suggestion.findMany({
    where: {
      userId,
      status: { in: ['approved', 'synced'] },
      transactionDate: { gte: startOfMonth },
    },
  });

  let totalExpenses = 0;
  let totalIncome = 0;
  const categoryMap: Record<string, { categoryId: string; categoryName: string; amount: number; count: number }> = {};

  for (const s of suggestions) {
    const amt = Number(s.amount);
    if (s.transactionType === 'expense') {
      totalExpenses += amt;
      const catKey = s.walletCategoryId || 'unknown';
      const catName = s.walletCategoryName || 'Uncategorized';
      if (!categoryMap[catKey]) {
        categoryMap[catKey] = { categoryId: catKey, categoryName: catName, amount: 0, count: 0 };
      }
      categoryMap[catKey].amount += amt;
      categoryMap[catKey].count += 1;
    } else if (s.transactionType === 'income') {
      totalIncome += amt;
    }
  }

  const categorySummary = Object.values(categoryMap)
    .sort((a, b) => b.amount - a.amount)
    .map(c => ({
      ...c,
      percentage: totalExpenses > 0 ? ((c.amount / totalExpenses) * 100).toFixed(1) : '0',
    }));

  res.json({
    month: monthKey,
    totalExpenses,
    totalIncome,
    netSavings: totalIncome - totalExpenses,
    savingsRate: totalIncome > 0 ? (((totalIncome - totalExpenses) / totalIncome) * 100).toFixed(1) : '0',
    categorySummary,
    transactionCount: suggestions.length,
    source: 'local_db',
  });
});

// GET /api/insights/cardinality - Discretionary vs Essential ("Must" vs "Want" vs "Need") spending
router.get('/cardinality', authenticate, async (req: Request, res: Response) => {
  const userId = req.user.id;
  const user = await prisma.user.findUnique({ where: { id: userId } });

  if (!user?.walletApiToken) {
    return res.json({ cardinality: [] });
  }

  const { startStr, endStr } = getMonthBoundaries();

  try {
    const client = new WalletClient(user.walletApiToken);
    const agg = await client.getRecordsAggregation({
      recordType: 'expense',
      isTransfer: false,
      recordDate: [`gte.${startStr}`, `lt.${endStr}`],
      groupBy: ['category:cardinality'],
      compute: ['amount:absSum'],
    });

    let total = 0;
    const items = (agg?.results || []).map((row: any) => {
      const amt = row['amount:absSum'] ?? 0;
      total += amt;
      return {
        cardinality: row['category:cardinality'] || 'other',
        amount: amt,
        count: row.count ?? 0,
      };
    });

    const cardinality = items.map((item: any) => ({
      ...item,
      percentage: total > 0 ? ((item.amount / total) * 100).toFixed(1) : '0',
    }));

    res.json({ cardinality, total });
  } catch (err: any) {
    console.warn('Cardinality aggregation error:', err.message);
    res.json({ cardinality: [], total: 0 });
  }
});

// GET /api/insights/merchants - Top spending merchants / payees
router.get('/merchants', authenticate, async (req: Request, res: Response) => {
  const userId = req.user.id;
  const user = await prisma.user.findUnique({ where: { id: userId } });

  if (!user?.walletApiToken) {
    return res.json({ merchants: [] });
  }

  const { startStr, endStr } = getMonthBoundaries();

  try {
    const client = new WalletClient(user.walletApiToken);
    const agg = await client.getRecordsAggregation({
      recordType: 'expense',
      isTransfer: false,
      recordDate: [`gte.${startStr}`, `lt.${endStr}`],
      groupBy: ['counterParty'],
      compute: ['amount:absSum'],
      sortBy: ['-amount:absSum'],
      limit: 10,
    });

    const merchants = (agg?.results || [])
      .filter((row: any) => row.counterParty && row.counterParty.trim().length > 0)
      .map((row: any) => ({
        merchant: row.counterParty,
        amount: row['amount:absSum'] ?? 0,
        count: row.count ?? 0,
      }));

    res.json({ merchants });
  } catch (err: any) {
    console.warn('Merchants aggregation error:', err.message);
    res.json({ merchants: [] });
  }
});

// GET /api/insights/budgets - Live BudgetBakers budgets with health & progress
router.get('/budgets', authenticate, async (req: Request, res: Response) => {
  const user = await prisma.user.findUnique({ where: { id: req.user.id } });

  if (!user || !user.walletApiToken) {
    return res.json({ budgets: [] });
  }

  try {
    const client = new WalletClient(user.walletApiToken);
    const rawBudgets = await client.getBudgets();

    const budgets = (rawBudgets || []).map((b: any) => {
      const limit = Number(b.amount?.value ?? b.amount ?? 0);
      const spent = Math.abs(Number(b.spent?.value ?? b.spent ?? 0));
      const remaining = Math.max(0, limit - spent);
      const percentage = limit > 0 ? Math.min(100, Math.round((spent / limit) * 100)) : 0;

      let status = 'on_track';
      if (percentage >= 100) {
        status = 'exceeded';
      } else if (percentage >= 80) {
        status = 'warning';
      }

      return {
        id: b.id,
        name: b.name || 'Budget',
        limit,
        spent,
        remaining,
        percentage,
        status,
        period: b.period || 'monthly',
        currencyCode: b.amount?.currencyCode || 'INR',
        categoryIds: b.categoryIds || [],
        accountIds: b.accountIds || [],
      };
    });

    res.json({ budgets });
  } catch (err: any) {
    console.error('Failed to fetch budgets:', err.message);
    res.status(500).json({ error: 'Failed to fetch budgets', details: err.message });
  }
});

// GET /api/insights/trends - Multi-month trends powered by Wallet aggregation
router.get('/trends', authenticate, async (req: Request, res: Response) => {
  const userId = req.user.id;
  const user = await prisma.user.findUnique({ where: { id: userId } });

  const now = new Date();
  const sixMonthsAgo = new Date(Date.UTC(now.getFullYear(), now.getMonth() - 5, 1));
  const sixMonthsAgoStr = sixMonthsAgo.toISOString().split('T')[0];

  if (user?.walletApiToken) {
    try {
      const client = new WalletClient(user.walletApiToken);
      const agg = await client.getRecordsAggregation({
        isTransfer: false,
        recordDate: [`gte.${sixMonthsAgoStr}`],
        groupBy: ['month', 'recordType'],
        compute: ['amount:absSum'],
        sortBy: ['+month'],
      });

      const monthMap: Record<string, { month: string; expenses: number; income: number }> = {};

      // Seed all 6 months in order
      for (let i = 5; i >= 0; i--) {
        const d = new Date(Date.UTC(now.getFullYear(), now.getMonth() - i, 1));
        const mKey = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}`;
        monthMap[mKey] = { month: mKey, expenses: 0, income: 0 };
      }

      for (const row of agg?.results || []) {
        const m = row.month;
        if (monthMap[m]) {
          const amt = row['amount:absSum'] ?? 0;
          if (row.recordType === 'expense') {
            monthMap[m].expenses += amt;
          } else if (row.recordType === 'income') {
            monthMap[m].income += amt;
          }
        }
      }

      return res.json({ trends: Object.values(monthMap) });
    } catch (err: any) {
      console.warn('Native trends aggregation error, falling back to local:', err.message);
    }
  }

  // Fallback: local suggestions
  const suggestions = await prisma.suggestion.findMany({
    where: {
      userId,
      status: { in: ['approved', 'synced'] },
      transactionDate: { gte: sixMonthsAgo },
    },
    orderBy: { transactionDate: 'asc' },
  });

  const monthBuckets: Record<string, { month: string; expenses: number; income: number }> = {};
  for (let i = 5; i >= 0; i--) {
    const d = new Date(Date.UTC(now.getFullYear(), now.getMonth() - i, 1));
    const mKey = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}`;
    monthBuckets[mKey] = { month: mKey, expenses: 0, income: 0 };
  }

  for (const s of suggestions) {
    const m = s.transactionDate.toISOString().substring(0, 7);
    if (monthBuckets[m]) {
      const amt = Number(s.amount);
      if (s.transactionType === 'expense') {
        monthBuckets[m].expenses += amt;
      } else if (s.transactionType === 'income') {
        monthBuckets[m].income += amt;
      }
    }
  }

  res.json({
    trends: Object.values(monthBuckets),
  });
});

export default router;
