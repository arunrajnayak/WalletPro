import { Router, Request, Response } from 'express';
import { authenticate } from '../middleware/auth';
import { prisma } from '../prisma';
import { WalletClient } from '../services/wallet-client';

const router = Router();

// GET /api/insights/monthly - Monthly breakdown
router.get('/monthly', authenticate, async (req: Request, res: Response) => {
  const userId = req.user.id;
  const now = new Date();
  const startOfMonth = new Date(now.getFullYear(), now.getMonth(), 1);

  // Group synced suggestions for this month
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
    } else {
      totalIncome += amt;
    }
  }

  res.json({
    month: `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}`,
    totalExpenses,
    totalIncome,
    netSavings: totalIncome - totalExpenses,
    categorySummary: Object.values(categoryMap).sort((a, b) => b.amount - a.amount),
    transactionCount: suggestions.length,
  });
});

// GET /api/insights/budgets - Live BudgetBakers budgets if connected
router.get('/budgets', authenticate, async (req: Request, res: Response) => {
  const user = await prisma.user.findUnique({ where: { id: req.user.id } });

  if (!user || !user.walletApiToken) {
    return res.json({ budgets: [] });
  }

  try {
    const client = new WalletClient(user.walletApiToken);
    const budgets = await client.getBudgets();
    res.json({ budgets });
  } catch (err: any) {
    res.status(500).json({ error: 'Failed to fetch budgets', details: err.message });
  }
});

// GET /api/insights/trends - Past 6 months trend
router.get('/trends', authenticate, async (req: Request, res: Response) => {
  const userId = req.user.id;
  const sixMonthsAgo = new Date();
  sixMonthsAgo.setMonth(sixMonthsAgo.getMonth() - 6);

  const suggestions = await prisma.suggestion.findMany({
    where: {
      userId,
      status: { in: ['approved', 'synced'] },
      transactionDate: { gte: sixMonthsAgo },
    },
    orderBy: { transactionDate: 'asc' },
  });

  const monthBuckets: Record<string, { month: string; expenses: number; income: number }> = {};

  for (const s of suggestions) {
    const m = s.transactionDate.toISOString().substring(0, 7); // YYYY-MM
    if (!monthBuckets[m]) {
      monthBuckets[m] = { month: m, expenses: 0, income: 0 };
    }
    const amt = Number(s.amount);
    if (s.transactionType === 'expense') {
      monthBuckets[m].expenses += amt;
    } else {
      monthBuckets[m].income += amt;
    }
  }

  res.json({
    trends: Object.values(monthBuckets),
  });
});

export default router;
