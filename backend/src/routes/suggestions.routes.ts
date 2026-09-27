import { Router, Request, Response } from 'express';
import { authenticate } from '../middleware/auth';
import { prisma } from '../prisma';
import { SmsParser } from '../services/sms-parser';
import { DedupEngine } from '../services/dedup-engine';
import { CategoryAI } from '../services/category-ai';
import { WalletClient } from '../services/wallet-client';

const router = Router();
const smsParser = new SmsParser();
const dedupEngine = new DedupEngine();
const categoryAi = new CategoryAI();

/**
 * Returns effective cutoff date based on user preferences.
 * Precedence: lastReviewedDate (sliding window) > syncStartDate.
 */
function getCutoffDate(prefs: any): Date | null {
  if (!prefs) return null;
  const dateStr = prefs.lastReviewedDate || prefs.syncStartDate;
  if (!dateStr) return null;
  const d = new Date(dateStr);
  return isNaN(d.getTime()) ? null : d;
}

// GET /api/suggestions - List pending suggestions
router.get('/', authenticate, async (req: Request, res: Response) => {
  const userId = req.user.id;
  const { status, source, limit = '50', offset = '0', ignoreCutoff } = req.query;

  const filters: any = { userId };
  if (status) filters.status = status as string;
  if (source) filters.source = source as string;

  // Apply sliding window cutoff to pending suggestions unless explicitly ignored
  if (ignoreCutoff !== 'true' && (!status || status === 'pending')) {
    const user = await prisma.user.findUnique({
      where: { id: userId },
      select: { preferences: true },
    });
    const cutoff = getCutoffDate(user?.preferences);
    if (cutoff) {
      filters.transactionDate = { gte: cutoff };
    }
  }

  const suggestions = await prisma.suggestion.findMany({
    where: filters,
    orderBy: { transactionDate: 'desc' },
    take: parseInt(limit as string, 10),
    skip: parseInt(offset as string, 10),
  });

  res.json(suggestions);
});

// GET /api/suggestions/stats - Get counts by status
router.get('/stats', authenticate, async (req: Request, res: Response) => {
  const userId = req.user.id;

  const counts = await prisma.suggestion.groupBy({
    by: ['status'],
    where: { userId },
    _count: true,
  });

  const stats = {
    pending: 0,
    approved: 0,
    rejected: 0,
    synced: 0,
    expired: 0,
    total: 0,
  };

  for (const item of counts) {
    // @ts-ignore
    stats[item.status] = item._count;
    stats.total += item._count;
  }

  res.json(stats);
});

// POST /api/suggestions - Create a suggestion (from raw SMS text or structured transaction)
router.post('/', authenticate, async (req: Request, res: Response) => {
  const userId = req.user.id;
  const { text, date, source, parsedData } = req.body;

  let parsed = parsedData;

  // If raw text provided, parse on backend
  if (!parsed && text) {
    parsed = smsParser.parse(text, date ? new Date(date) : new Date());
  }

  if (!parsed || !parsed.amount) {
    return res.status(400).json({ error: 'Could not extract valid transaction details' });
  }

  const transactionDate = new Date(parsed.transactionDate || date || Date.now());
  const amount = Number(parsed.amount);

  // Check Sliding Window / Start Date Cutoff
  const user = await prisma.user.findUnique({
    where: { id: userId },
    select: { preferences: true },
  });
  const cutoff = getCutoffDate(user?.preferences);
  if (cutoff && transactionDate < cutoff) {
    return res.status(200).json({
      ignored: true,
      reason: 'Transaction date is prior to sliding window cutoff date',
      transactionDate: transactionDate.toISOString(),
      cutoffDate: cutoff.toISOString(),
    });
  }

  // Check duplicate
  const isDup = await dedupEngine.isDuplicate(
    userId,
    transactionDate,
    amount,
    parsed.referenceNumber,
    parsed.accountLast4
  );

  if (isDup) {
    return res.status(409).json({ message: 'Duplicate transaction detected', parsed });
  }

  // Auto-match Wallet account if accountLast4 matches a mapped account
  let matchedAccountId: string | undefined;
  if (parsed.accountLast4) {
    const activeMappedAccounts = await prisma.walletAccount.findMany({
      where: { userId, isActive: true, last4Digits: { not: null } },
    });

    const matchedAccount = activeMappedAccounts.find((acc) => {
      if (!acc.last4Digits) return false;
      const digitsList = acc.last4Digits.split(/[,;\s]+/).map((s) => s.trim());
      return digitsList.includes(parsed.accountLast4) || acc.last4Digits === parsed.accountLast4;
    });

    if (matchedAccount) {
      matchedAccountId = matchedAccount.walletAccountId;
    }
  }

  // Get AI Category suggestion
  const aiSuggestion = await categoryAi.suggestCategory(
    userId,
    parsed.counterParty || '',
    amount,
    parsed.transactionType || 'expense'
  );

  const suggestion = await prisma.suggestion.create({
    data: {
      userId,
      source: source || 'sms',
      amount,
      currencyCode: parsed.currencyCode || 'INR',
      transactionType: parsed.transactionType || 'expense',
      counterParty: parsed.counterParty,
      referenceNumber: parsed.referenceNumber,
      accountLast4: parsed.accountLast4,
      walletAccountId: matchedAccountId,
      walletCategoryId: aiSuggestion.categoryId,
      walletCategoryName: aiSuggestion.categoryName,
      rawText: parsed.rawText || text,
      sourceId: parsed.sourceId,
      transactionDate,
      aiConfidence: aiSuggestion.confidence,
      aiSuggestedCategory: aiSuggestion.categoryId,
      parsedData: parsed,
    },
  });

  await dedupEngine.recordTransaction(
    userId,
    transactionDate,
    amount,
    source || 'sms',
    parsed.referenceNumber,
    parsed.accountLast4,
    suggestion.id
  );

  res.status(201).json(suggestion);
});

// Helper to advance sliding window
async function advanceSlidingWindowIfNeeded(userId: string, transactionDate: Date) {
  try {
    const user = await prisma.user.findUnique({
      where: { id: userId },
      select: { preferences: true },
    });
    const prefs = (user?.preferences as Record<string, any>) || {};
    const autoAdvance = prefs.autoAdvanceWindow !== false; // default true

    if (autoAdvance) {
      const currentCutoff = prefs.lastReviewedDate ? new Date(prefs.lastReviewedDate) : null;
      if (!currentCutoff || transactionDate > currentCutoff) {
        await prisma.user.update({
          where: { id: userId },
          data: {
            preferences: {
              ...prefs,
              lastReviewedDate: transactionDate.toISOString(),
            },
          },
        });
        return transactionDate.toISOString();
      }
    }
  } catch (err) {
    console.error('Error auto-advancing sliding window:', err);
  }
  return null;
}

// PATCH /api/suggestions/:id/approve - Approve and post transaction to BudgetBakers Wallet
router.patch('/:id/approve', authenticate, async (req: Request, res: Response) => {
  const userId = req.user.id;
  const id = req.params.id as string;
  const { walletAccountId, walletCategoryId, walletCategoryName, note } = req.body;

  const suggestion = await prisma.suggestion.findUnique({ where: { id } });
  if (!suggestion || suggestion.userId !== userId) {
    return res.status(404).json({ error: 'Suggestion not found' });
  }

  const user = await prisma.user.findUnique({ where: { id: userId } });
  const finalAccountId = walletAccountId || suggestion.walletAccountId;
  const finalCategoryId = walletCategoryId || suggestion.walletCategoryId;

  let walletRecordId: string | undefined;
  let syncStatus = 'approved';

  // If user has Wallet API connected and account is selected, post to Wallet!
  if (user?.walletApiToken && finalAccountId) {
    try {
      const client = new WalletClient(user.walletApiToken);
      const isExpense = suggestion.transactionType === 'expense';
      const signedAmount = isExpense ? -Number(suggestion.amount) : Number(suggestion.amount);

      const recordReq = {
        accountId: finalAccountId,
        amount: signedAmount,
        recordDate: suggestion.transactionDate.toISOString(),
        categoryId: finalCategoryId || undefined,
        counterParty: suggestion.counterParty || undefined,
        note: note || suggestion.note || (suggestion.referenceNumber ? `Ref: ${suggestion.referenceNumber}` : undefined),
        recordState: 'cleared' as const,
      };

      const result = await client.createRecords([recordReq]);

      if (result.results && result.results[0] && result.results[0].success) {
        walletRecordId = result.results[0].id;
        syncStatus = 'synced';
      }
    } catch (err: any) {
      console.error('Wallet posting error:', err.response?.data || err.message);
      syncStatus = 'approved';
    }
  }

  const updated = await prisma.suggestion.update({
    where: { id },
    data: {
      status: syncStatus,
      walletAccountId: finalAccountId,
      walletCategoryId: finalCategoryId,
      walletCategoryName: walletCategoryName || suggestion.walletCategoryName,
      walletRecordId,
      actionedAt: new Date(),
    },
  });

  // Learn merchant -> category preference
  if (suggestion.counterParty && finalCategoryId) {
    await categoryAi.recordCategorySelection(
      userId,
      suggestion.counterParty,
      finalCategoryId,
      walletCategoryName
    );
  }

  // Auto-advance sliding window
  const newCutoff = await advanceSlidingWindowIfNeeded(userId, suggestion.transactionDate);

  res.json({
    suggestion: updated,
    syncedToWallet: syncStatus === 'synced',
    walletRecordId,
    slidingWindowUpdated: !!newCutoff,
    newCutoffDate: newCutoff,
  });
});

// PATCH /api/suggestions/:id/reject - Reject a suggestion
router.patch('/:id/reject', authenticate, async (req: Request, res: Response) => {
  const userId = req.user.id;
  const id = req.params.id as string;

  const suggestion = await prisma.suggestion.findUnique({ where: { id, userId } });
  if (!suggestion) {
    return res.status(404).json({ error: 'Suggestion not found' });
  }

  const updated = await prisma.suggestion.update({
    where: { id, userId },
    data: { status: 'rejected', actionedAt: new Date() },
  });

  // Auto-advance sliding window even on rejection, since transaction was reviewed
  const newCutoff = await advanceSlidingWindowIfNeeded(userId, suggestion.transactionDate);

  res.json({
    suggestion: updated,
    slidingWindowUpdated: !!newCutoff,
    newCutoffDate: newCutoff,
  });
});

// POST /api/suggestions/batch - Batch approve or reject
router.post('/batch', authenticate, async (req: Request, res: Response) => {
  const userId = req.user.id;
  const { action, ids, walletAccountId, walletCategoryId } = req.body;

  if (!Array.isArray(ids) || ids.length === 0) {
    return res.status(400).json({ error: 'ids array is required' });
  }

  if (action === 'reject') {
    await prisma.suggestion.updateMany({
      where: { id: { in: ids }, userId },
      data: { status: 'rejected', actionedAt: new Date() },
    });
    return res.json({ message: `Rejected ${ids.length} suggestions` });
  }

  if (action === 'approve') {
    await prisma.suggestion.updateMany({
      where: { id: { in: ids }, userId },
      data: {
        status: 'approved',
        walletAccountId: walletAccountId || undefined,
        walletCategoryId: walletCategoryId || undefined,
        actionedAt: new Date(),
      },
    });
    return res.json({ message: `Approved ${ids.length} suggestions` });
  }

  res.status(400).json({ error: 'Invalid action. Must be approve or reject' });
});

export default router;
