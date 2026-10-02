import { Router, Request, Response } from 'express';
import { authenticate } from '../middleware/auth';
import { prisma, ensureDbConstraints } from '../prisma';
import { SmsParser } from '../services/sms-parser';
import { DedupEngine, inFlightMutex } from '../services/dedup-engine';
import { CategoryAI } from '../services/category-ai';
import { WalletClient } from '../services/wallet-client';

const router = Router();
const smsParser = new SmsParser();
const dedupEngine = new DedupEngine();
const categoryAi = new CategoryAI();

// Hardcoded start date: 1st September 2026
const HARDCODED_START_DATE = new Date('2026-09-01T00:00:00.000Z');

// Debounce map to prevent redundant duplicate cleanups on concurrent queries
const lastCleanupByUser = new Map<string, number>();

/**
 * Deduplicate pending suggestions for a user.
 * If duplicate pending suggestions exist (e.g. from historical dual ingestion or timezone bugs),
 * keeps the earliest created one and cleans up surplus duplicates.
 */
async function cleanupPendingDuplicates(userId: string, force = false): Promise<void> {
  const lastRun = lastCleanupByUser.get(userId) || 0;
  if (!force && Date.now() - lastRun < 5 * 60 * 1000) {
    return;
  }
  lastCleanupByUser.set(userId, Date.now());

  try {
    const pending = await prisma.suggestion.findMany({
      where: {
        userId,
        status: 'pending',
        transactionDate: { gte: HARDCODED_START_DATE },
      },
      orderBy: { createdAt: 'asc' },
    });

    if (pending.length <= 1) return;

    const seenSignatures = new Set<string>();
    const duplicateIdsToDelete: string[] = [];

    for (const item of pending) {
      const amountStr = Number(item.amount).toFixed(2);
      const ref = (item.referenceNumber || '').trim();
      const raw = (item.rawText || '').replace(/\s+/g, ' ').trim().toLowerCase();
      const sourceId = (item.sourceId || '').trim();
      const d = item.transactionDate;
      const dateDay = `${d.getUTCFullYear()}-${d.getUTCMonth() + 1}-${d.getUTCDate()}`;

      let sig = '';
      if (sourceId) {
        sig = `src:${sourceId}`;
      } else if (ref) {
        sig = `ref:${amountStr}:${ref}`;
      } else if (raw.length > 10) {
        sig = `raw:${amountStr}:${raw.slice(0, 60)}`;
      } else {
        const last4 = (item.accountLast4 || '').trim();
        sig = `approx:${amountStr}:${dateDay}:${last4}`;
      }

      if (seenSignatures.has(sig)) {
        duplicateIdsToDelete.push(item.id);
      } else {
        seenSignatures.add(sig);
      }
    }

    if (duplicateIdsToDelete.length > 0) {
      console.log(`Auto-deduplicating ${duplicateIdsToDelete.length} surplus pending suggestions for user ${userId}`);
      await prisma.dedupEntry.updateMany({
        where: { suggestionId: { in: duplicateIdsToDelete } },
        data: { suggestionId: null },
      });
      await prisma.suggestion.deleteMany({
        where: {
          id: { in: duplicateIdsToDelete },
          userId,
          status: 'pending',
        },
      });
    }
  } catch (err: any) {
    console.warn('Note: cleanupPendingDuplicates:', err?.message || err);
  }
}

// GET /api/suggestions - List suggestions
router.get('/', authenticate, async (req: Request, res: Response) => {
  const userId = req.user.id;
  const { status, source, limit = '50', offset = '0' } = req.query;

  // Run self-healing cleanup on pending suggestions when loading pending queue
  if (!status || status === 'pending') {
    await cleanupPendingDuplicates(userId);
  }

  const filters: any = { userId };
  if (status) {
    if (status === 'approved') {
      filters.status = { in: ['approved', 'synced'] };
    } else {
      filters.status = status as string;
    }
  }
  if (source) filters.source = source as string;

  // Filter pending suggestions from 1st September 2026 onwards
  if (!status || status === 'pending') {
    filters.transactionDate = { gte: HARDCODED_START_DATE };
  }

  // Show only last 100 records for approved and rejected tabs sorted by date
  const isApprovedOrRejected = status === 'approved' || status === 'rejected';
  let take: number | undefined;
  if (isApprovedOrRejected) {
    take = 100;
  } else if (limit && limit !== 'all') {
    take = Math.min(parseInt(limit as string, 10) || 500, 1000);
  } else {
    take = 1000; // Return all pending cards
  }

  const suggestions = await prisma.suggestion.findMany({
    where: filters,
    orderBy: [
      { transactionDate: 'desc' },
      { createdAt: 'desc' },
    ],
    take,
    skip: parseInt(offset as string, 10) || 0,
  });

  const mapped = suggestions.map((s) => ({
    ...s,
    amount: Number(s.amount),
  }));

  res.json(mapped);
});

// GET /api/suggestions/stats - Get counts by status
router.get('/stats', authenticate, async (req: Request, res: Response) => {
  const userId = req.user.id;

  // Run self-healing cleanup before computing stats
  await cleanupPendingDuplicates(userId);

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

// GET /api/suggestions/recent-categories - Get 3-5 last used categories for an account
router.get('/recent-categories', authenticate, async (req: Request, res: Response) => {
  try {
    const userId = req.user.id;
    const { accountId, limit = '5' } = req.query;

    if (!accountId || typeof accountId !== 'string') {
      return res.json([]);
    }

    // Find recent approved or synced suggestions for this account with non-null category
    const recent = await prisma.suggestion.findMany({
      where: {
        userId,
        walletAccountId: accountId,
        walletCategoryId: { not: null },
        status: { in: ['approved', 'synced'] },
      },
      orderBy: [
        { actionedAt: 'desc' },
        { createdAt: 'desc' },
      ],
      select: {
        walletCategoryId: true,
        walletCategoryName: true,
      },
      take: 40,
    });

    // Deduplicate by category ID while preserving most recent order
    const seen = new Set<string>();
    const categories: Array<{ id: string; name: string }> = [];
    const maxItems = Math.min(Math.max(parseInt(limit as string, 10) || 5, 1), 10);

    for (const item of recent) {
      if (item.walletCategoryId && !seen.has(item.walletCategoryId)) {
        seen.add(item.walletCategoryId);
        categories.push({
          id: item.walletCategoryId,
          name: item.walletCategoryName || 'Category',
        });
        if (categories.length >= maxItems) break;
      }
    }

    return res.json(categories);
  } catch (error: any) {
    return res.status(500).json({ error: 'Failed to fetch recent categories', details: error.message });
  }
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

  // Check 1st September 2026 start date cutoff
  if (transactionDate < HARDCODED_START_DATE) {
    return res.status(200).json({
      ignored: true,
      reason: 'Transaction date is prior to 1st September 2026',
      transactionDate: transactionDate.toISOString(),
      startDate: HARDCODED_START_DATE.toISOString(),
    });
  }

  const rawTextToSave = (parsed.rawText || text || '').trim();

  // In-flight mutex lock based on user and message fingerprint to eliminate race conditions
  const lockKey = `${userId}:${parsed.sourceId || amount.toFixed(2) + '_' + (parsed.referenceNumber || rawTextToSave.slice(0, 30))}`;
  const releaseLock = await inFlightMutex.acquire(lockKey);

  try {
    // 1. Once reviewed or created, same SMS sourceId should not be parsed again:
    if (parsed.sourceId) {
      const existingBySourceId = await prisma.suggestion.findFirst({
        where: { userId, sourceId: String(parsed.sourceId) },
      });
      if (existingBySourceId) {
        return res.status(409).json({
          message: 'SMS message already processed',
          suggestionId: existingBySourceId.id,
          status: existingBySourceId.status,
        });
      }
    }

    // 2. Exact rawText check: identical SMS content for this user should not be duplicated
    if (rawTextToSave.length > 10) {
      const existingByRawText = await prisma.suggestion.findFirst({
        where: {
          userId,
          rawText: rawTextToSave,
          status: { in: ['pending', 'approved', 'synced'] },
        },
      });
      if (existingByRawText) {
        return res.status(409).json({
          message: 'Transaction with identical message text already exists',
          suggestionId: existingByRawText.id,
          status: existingByRawText.status,
        });
      }
    }

    // 3. Multi-layer deduplication check (ref number, fuzzy date, amount, accountLast4, rawText)
    const isDup = await dedupEngine.isDuplicate(
      userId,
      transactionDate,
      amount,
      parsed.referenceNumber,
      parsed.accountLast4,
      rawTextToSave,
      parsed.sourceId ? String(parsed.sourceId) : undefined
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

    await ensureDbConstraints();

    const suggestion = await prisma.suggestion.create({
      data: {
        userId,
        source: 'sms',
        amount,
        currencyCode: parsed.currencyCode || 'INR',
        transactionType: parsed.transactionType || 'expense',
        counterParty: parsed.counterParty,
        referenceNumber: parsed.referenceNumber,
        accountLast4: parsed.accountLast4,
        walletAccountId: matchedAccountId,
        walletCategoryId: aiSuggestion.categoryId,
        walletCategoryName: aiSuggestion.categoryName,
        rawText: rawTextToSave,
        sourceId: parsed.sourceId ? String(parsed.sourceId) : undefined,
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
      'sms',
      parsed.referenceNumber,
      parsed.accountLast4,
      suggestion.id
    );

    return res.status(201).json({
      ...suggestion,
      amount: Number(suggestion.amount),
    });
  } finally {
    releaseLock();
  }
});

// POST /api/suggestions/bulk - Batch ingestion of multiple detected SMS transactions
router.post('/bulk', authenticate, async (req: Request, res: Response) => {
  const userId = req.user.id;
  const { transactions } = req.body;

  if (!Array.isArray(transactions) || transactions.length === 0) {
    return res.status(400).json({ error: 'transactions array is required and must not be empty' });
  }

  // Pre-fetch active mapped accounts once for the entire batch
  const activeMappedAccounts = await prisma.walletAccount.findMany({
    where: { userId, isActive: true, last4Digits: { not: null } },
  });

  const createdItems: any[] = [];
  let ignoredCount = 0;
  let duplicateCount = 0;

  for (const item of transactions) {
    let parsed = item.parsedData;
    if (!parsed && item.text) {
      parsed = smsParser.parse(item.text, item.date ? new Date(item.date) : new Date());
    }

    if (!parsed || !parsed.amount) {
      ignoredCount++;
      continue;
    }

    const transactionDate = new Date(parsed.transactionDate || item.date || Date.now());
    const amount = Number(parsed.amount);

    if (transactionDate < HARDCODED_START_DATE) {
      ignoredCount++;
      continue;
    }

    const rawTextToSave = (parsed.rawText || item.text || '').trim();

    // Check sourceId duplicate
    if (parsed.sourceId) {
      const existingBySourceId = await prisma.suggestion.findFirst({
        where: { userId, sourceId: String(parsed.sourceId) },
        select: { id: true },
      });
      if (existingBySourceId) {
        duplicateCount++;
        continue;
      }
    }

    // Check rawText duplicate
    if (rawTextToSave.length > 10) {
      const existingByRawText = await prisma.suggestion.findFirst({
        where: {
          userId,
          rawText: rawTextToSave,
          status: { in: ['pending', 'approved', 'synced'] },
        },
        select: { id: true },
      });
      if (existingByRawText) {
        duplicateCount++;
        continue;
      }
    }

    // Multi-layer dedup check
    const isDup = await dedupEngine.isDuplicate(
      userId,
      transactionDate,
      amount,
      parsed.referenceNumber,
      parsed.accountLast4,
      rawTextToSave,
      parsed.sourceId ? String(parsed.sourceId) : undefined
    );

    if (isDup) {
      duplicateCount++;
      continue;
    }

    // Account mapping match
    let matchedAccountId: string | undefined;
    if (parsed.accountLast4) {
      const matchedAccount = activeMappedAccounts.find((acc) => {
        if (!acc.last4Digits) return false;
        const digitsList = acc.last4Digits.split(/[,;\s]+/).map((s: string) => s.trim());
        return digitsList.includes(parsed.accountLast4) || acc.last4Digits === parsed.accountLast4;
      });
      if (matchedAccount) {
        matchedAccountId = matchedAccount.walletAccountId;
      }
    }

    // AI Category suggestion
    const aiSuggestion = await categoryAi.suggestCategory(
      userId,
      parsed.counterParty || '',
      amount,
      parsed.transactionType || 'expense'
    );

    const suggestion = await prisma.suggestion.create({
      data: {
        userId,
        source: 'sms',
        amount,
        currencyCode: parsed.currencyCode || 'INR',
        transactionType: parsed.transactionType || 'expense',
        counterParty: parsed.counterParty,
        referenceNumber: parsed.referenceNumber,
        accountLast4: parsed.accountLast4,
        walletAccountId: matchedAccountId,
        walletCategoryId: aiSuggestion.categoryId,
        walletCategoryName: aiSuggestion.categoryName,
        rawText: rawTextToSave,
        sourceId: parsed.sourceId ? String(parsed.sourceId) : undefined,
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
      'sms',
      parsed.referenceNumber,
      parsed.accountLast4,
      suggestion.id
    );

    createdItems.push({
      ...suggestion,
      amount: Number(suggestion.amount),
    });
  }

  res.status(201).json({
    totalReceived: transactions.length,
    created: createdItems.length,
    duplicates: duplicateCount,
    ignored: ignoredCount,
    items: createdItems,
  });
});

// PATCH /api/suggestions/:id/approve - Approve and post transaction to BudgetBakers Wallet
router.patch('/:id/approve', authenticate, async (req: Request, res: Response) => {
  const userId = req.user.id;
  const id = req.params.id as string;
  const {
    walletAccountId,
    walletCategoryId,
    walletCategoryName,
    note,
    transactionType,
    isTransfer,
    transferToAccountId,
  } = req.body;

  const suggestion = await prisma.suggestion.findUnique({ where: { id } });
  if (!suggestion || suggestion.userId !== userId) {
    return res.status(404).json({ error: 'Suggestion not found' });
  }

  const user = await prisma.user.findUnique({ where: { id: userId } });
  const finalAccountId = walletAccountId || suggestion.walletAccountId;
  const finalCategoryId = walletCategoryId || suggestion.walletCategoryId;
  const isTransferTx = isTransfer === true || transactionType === 'transfer';

  // Enforce mandatory requirements
  if (isTransferTx) {
    if (!finalAccountId) {
      return res.status(400).json({ error: 'From account is mandatory for transfers' });
    }
    if (!transferToAccountId) {
      return res.status(400).json({ error: 'To account is mandatory for transfers' });
    }
    if (finalAccountId === transferToAccountId) {
      return res.status(400).json({ error: 'From and To accounts must be different' });
    }
  } else {
    if (!finalAccountId) {
      return res.status(400).json({ error: 'Account is mandatory to approve transaction' });
    }
    if (!finalCategoryId) {
      return res.status(400).json({ error: 'Category is mandatory to approve transaction' });
    }
  }

  let walletRecordId: string | undefined;
  let syncStatus = 'approved';

  // If user has Wallet API connected and account is selected, post to Wallet!
  if (user?.walletApiToken && finalAccountId) {
    try {
      const client = new WalletClient(user.walletApiToken);

      let recordReq: any;
      if (isTransferTx && transferToAccountId) {
        // Paired Transfer between Account A (source) and Account B (target)
        recordReq = {
          accountId: finalAccountId,
          amount: -Math.abs(Number(suggestion.amount)), // Amount leaving source account A
          recordDate: suggestion.transactionDate.toISOString(),
          counterParty: suggestion.counterParty || undefined,
          note: note || suggestion.note || (suggestion.referenceNumber ? `Ref: ${suggestion.referenceNumber}` : undefined),
          recordState: 'cleared' as const,
          transfer: {
            pairingMode: 'new',
            accountId: transferToAccountId,
          },
        };
      } else {
        const txType = transactionType || suggestion.transactionType;
        const isExpense = txType === 'expense';
        const signedAmount = isExpense ? -Number(suggestion.amount) : Number(suggestion.amount);

        recordReq = {
          accountId: finalAccountId,
          amount: signedAmount,
          recordDate: suggestion.transactionDate.toISOString(),
          categoryId: finalCategoryId || undefined,
          counterParty: suggestion.counterParty || undefined,
          note: note || suggestion.note || (suggestion.referenceNumber ? `Ref: ${suggestion.referenceNumber}` : undefined),
          recordState: 'cleared' as const,
        };
      }

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

  await ensureDbConstraints();

  const updateData = {
    status: syncStatus,
    transactionType: isTransferTx ? 'transfer' : (transactionType || suggestion.transactionType),
    walletAccountId: finalAccountId,
    walletCategoryId: isTransferTx ? null : finalCategoryId,
    walletCategoryName: isTransferTx ? 'Transfer' : (walletCategoryName || suggestion.walletCategoryName),
    walletRecordId,
    parsedData: {
      ...((suggestion.parsedData as any) || {}),
      ifTransfer: isTransferTx,
      transferToAccountId: isTransferTx ? transferToAccountId : undefined,
    },
    actionedAt: new Date(),
  };

  let updated;
  try {
    updated = await prisma.suggestion.update({
      where: { id },
      data: updateData,
    });
  } catch (updateErr: any) {
    if (updateErr?.code === 'P2003' || updateErr?.message?.includes('suggestions_wallet_account_id_fkey')) {
      console.warn('Recovering from foreign key constraint on wallet_account_id: dropping constraint and retrying...');
      try {
        await prisma.$executeRawUnsafe(`
          ALTER TABLE "suggestions" DROP CONSTRAINT IF EXISTS "suggestions_wallet_account_id_fkey";
        `);
        updated = await prisma.suggestion.update({
          where: { id },
          data: updateData,
        });
      } catch (retryErr: any) {
        console.error('Retry after dropping constraint failed:', retryErr);
        throw retryErr;
      }
    } else {
      throw updateErr;
    }
  }

  // Learn merchant -> category preference
  if (suggestion.counterParty && finalCategoryId) {
    await categoryAi.recordCategorySelection(
      userId,
      suggestion.counterParty,
      finalCategoryId,
      walletCategoryName
    );
  }

  res.json({
    suggestion: updated,
    syncedToWallet: syncStatus === 'synced',
    walletRecordId,
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

  res.json({
    suggestion: updated,
  });
});

// PATCH /api/suggestions/:id/reset - Reset suggestion back to pending (Undo)
router.patch('/:id/reset', authenticate, async (req: Request, res: Response) => {
  const userId = req.user.id;
  const id = req.params.id as string;

  const suggestion = await prisma.suggestion.findUnique({ where: { id, userId } });
  if (!suggestion) {
    return res.status(404).json({ error: 'Suggestion not found' });
  }

  // If already synced to Wallet, delete the record from BudgetBakers
  if (suggestion.walletRecordId) {
    try {
      const user = await prisma.user.findUnique({ where: { id: userId } });
      if (user?.walletApiToken) {
        const walletClient = new WalletClient(user.walletApiToken);
        await walletClient.deleteRecords([suggestion.walletRecordId]);
      }
    } catch (err) {
      console.warn('Failed to delete synced wallet record during reset:', err);
    }
  }

  const updated = await prisma.suggestion.update({
    where: { id, userId },
    data: {
      status: 'pending',
      actionedAt: null,
      walletRecordId: null,
    },
  });

  res.json({
    suggestion: updated,
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
    await ensureDbConstraints();
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
