import { Router, Request, Response } from 'express';
import { authenticate } from '../middleware/auth';
import { prisma, ensureDbConstraints } from '../prisma';
import { SmsParser } from '../services/sms-parser';
import { DedupEngine } from '../services/dedup-engine';
import { CategoryAI } from '../services/category-ai';
import { WalletClient } from '../services/wallet-client';

const router = Router();
const smsParser = new SmsParser();
const dedupEngine = new DedupEngine();
const categoryAi = new CategoryAI();

// Hardcoded start date: 1st September 2026
const HARDCODED_START_DATE = new Date('2026-09-01T00:00:00.000Z');

// GET /api/suggestions - List suggestions
router.get('/', authenticate, async (req: Request, res: Response) => {
  const userId = req.user.id;
  const { status, source, limit = '50', offset = '0' } = req.query;

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
  const take = isApprovedOrRejected ? 100 : Math.min(parseInt(limit as string, 10) || 50, 100);

  const suggestions = await prisma.suggestion.findMany({
    where: filters,
    orderBy: { transactionDate: 'desc' },
    take,
    skip: parseInt(offset as string, 10) || 0,
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

  // Check 1st September 2026 start date cutoff
  if (transactionDate < HARDCODED_START_DATE) {
    return res.status(200).json({
      ignored: true,
      reason: 'Transaction date is prior to 1st September 2026',
      transactionDate: transactionDate.toISOString(),
      startDate: HARDCODED_START_DATE.toISOString(),
    });
  }

  // Once reviewed or created, same SMS should not be parsed again:
  // If sourceId (Android SMS ID) is provided, check if suggestion already exists
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
      rawText: parsed.rawText || text,
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

  res.status(201).json(suggestion);
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
