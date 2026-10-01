import { Router, Request, Response } from 'express';
import { authenticate } from '../middleware/auth';
import { prisma } from '../prisma';
import { WalletClient, CreateRecordRequest } from '../services/wallet-client';

const router = Router();

// Default account display order matching the BudgetBakers Wallet home app
const DEFAULT_APP_ACCOUNT_ORDER = [
  'HDFC sb',
  'SBI sb',
  'Cash',
  'Mutual funds',
  'Zerodha',
  'NPS',
  'Upstox',
  'EPF',
  'Amazon Pay',
  'Flipkart GC',
  'SBI cashback',
  'Tata Neu',
  'HSBC Live+',
  'Axis Flipkart',
  'Swiggy HDFC',
  'Jupiter Edge',
  'Cred indusind',
  'Amazon ICICI',
  'Ola SBI',
  'IDFC wealth',
  'Axis Rewards',
  'PhonePe',
  'Fastag',
  'Axis forex',
  'LIC',
  'ICICI platinum',
];

// POST /api/wallet/connect - Store Wallet API token
router.post('/connect', authenticate, async (req: Request, res: Response) => {
  const userId = req.user.id;
  const { token } = req.body;
  
  if (!token || typeof token !== 'string') {
    return res.status(400).json({ error: 'Token is required' });
  }

  try {
    const client = new WalletClient(token.trim());
    const isValid = await client.verifyConnection();
    
    if (!isValid) {
      return res.status(400).json({ error: 'Unable to verify BudgetBakers Wallet token' });
    }

    await prisma.user.update({
      where: { id: userId },
      data: { walletApiToken: token.trim() }
    });

    res.json({ message: 'Wallet connected successfully' });
  } catch (error: any) {
    res.status(400).json({ error: 'Connection failed', details: error.message });
  }
});

// GET /api/wallet/profile - Return connection status, syncState, rateLimit, and budget settings
router.get('/profile', authenticate, async (req: Request, res: Response) => {
  const userId = req.user.id;
  const user = await prisma.user.findUnique({ where: { id: userId } });

  if (!user || !user.walletApiToken) {
    return res.json({
      connected: false,
      syncState: 'disconnected',
      rateLimit: null,
      budgetSettings: null,
      accountsCount: 0,
      categoriesCount: 0,
    });
  }

  try {
    const client = new WalletClient(user.walletApiToken);
    const [profile, accountsCount, categoriesCount] = await Promise.all([
      client.getClientProfile().catch(() => null),
      prisma.walletAccount.count({ where: { userId, isActive: true } }),
      prisma.walletCategoryCache.count({ where: { userId } }),
    ]);

    res.json({
      connected: true,
      syncState: profile?.syncState || 'idle',
      rateLimit: profile?.rateLimit || null,
      budgetSettings: profile?.budgetSettings || null,
      baseCurrency: profile?.baseCurrency || 'INR',
      accountsCount,
      categoriesCount,
    });
  } catch (err: any) {
    res.status(500).json({ error: 'Failed to fetch Wallet profile', details: err.message });
  }
});

// GET /api/wallet/accounts - Get accounts (returns active accounts only by default; pass ?includeArchived=true for all)
router.get('/accounts', authenticate, async (req: Request, res: Response) => {
  const userId = req.user.id;
  const includeArchived = req.query.includeArchived === 'true';

  const accounts = await prisma.walletAccount.findMany({
    where: {
      userId,
      ...(!includeArchived ? { isActive: true } : {}),
    },
    orderBy: { name: 'asc' },
  });

  res.json(accounts);
});

// GET /api/wallet/quickview - Return live accounts with balances, colors, total net worth, and budgets
router.get('/quickview', authenticate, async (req: Request, res: Response) => {
  const userId = req.user.id;
  const user = await prisma.user.findUnique({ where: { id: userId } });

  // Get mapped last 4 digits from local DB
  const localAccounts = await prisma.walletAccount.findMany({
    where: { userId },
  });
  const localMap = new Map(localAccounts.map(a => [a.walletAccountId, a]));

  if (!user || !user.walletApiToken) {
    const fallbackAccounts = localAccounts
      .filter(a => a.isActive)
      .map(a => ({
        id: a.walletAccountId,
        walletAccountId: a.walletAccountId,
        name: a.name,
        accountType: a.accountType,
        currencyCode: a.currencyCode,
        color: null,
        balance: 0,
        last4Digits: a.last4Digits,
        isActive: a.isActive,
      }));

    return res.json({
      connected: false,
      accounts: fallbackAccounts,
      summary: {
        totalAssets: 0,
        totalLiabilities: 0,
        netWorth: 0,
        accountsCount: fallbackAccounts.length,
      },
      budgets: [],
      recentRecords: [],
    });
  }

  try {
    const client = new WalletClient(user.walletApiToken);

    // Fetch accounts and recent records
    const [remoteAccounts, recentRecords] = await Promise.all([
      client.getAllAccounts({ archived: false }).catch(err => {
        console.warn('Failed to fetch remote accounts:', err.message);
        return [];
      }),
      client.getRecords({ limit: 15 }).catch(err => {
        console.warn('Failed to fetch recent records:', err.response?.data || err.message);
        return [];
      }),
    ]);

    let accountsList: any[] = [];
    if (remoteAccounts.length > 0) {
      accountsList = remoteAccounts
        .filter((a: any) => !a.archived)
        .map((a: any) => {
          const localAcc = localMap.get(a.id);
          const rawBal = a.balance?.currentBalance ?? a.balance?.rawCurrentBalance ?? a.balance?.initial ?? 0;
          const balance = typeof rawBal === 'number' ? rawBal : parseFloat(rawBal) || 0;

          return {
            id: a.id,
            walletAccountId: a.id,
            name: a.name,
            accountType: a.accountType || 'General',
            currencyCode: a.currencyCode || a.balance?.currencyCode || 'INR',
            color: a.color || null,
            balance: balance,
            last4Digits: localAcc?.last4Digits || null,
            isBankSync: a.isBankSync || false,
            isInvestmentAccount: a.isInvestmentAccount || false,
            recordCount: a.recordStats?.recordCount ?? 0,
            archived: a.archived || false,
          };
        });
    } else {
      accountsList = localAccounts
        .filter(a => a.isActive)
        .map(a => ({
          id: a.walletAccountId,
          walletAccountId: a.walletAccountId,
          name: a.name,
          accountType: a.accountType,
          currencyCode: a.currencyCode,
          color: null,
          balance: 0,
          last4Digits: a.last4Digits,
          isBankSync: false,
          isInvestmentAccount: false,
          recordCount: 0,
          archived: false,
        }));
    }

    // Sort accounts according to user preferences or default app layout (matching BudgetBakers app)
    const prefs = (user?.preferences as Record<string, any>) || {};
    const preferredOrder: string[] = Array.isArray(prefs.accountOrder) && prefs.accountOrder.length > 0
      ? prefs.accountOrder
      : DEFAULT_APP_ACCOUNT_ORDER;

    const getOrderIndex = (acc: any) => {
      const idIdx = preferredOrder.indexOf(acc.id) !== -1
        ? preferredOrder.indexOf(acc.id)
        : preferredOrder.indexOf(acc.walletAccountId);
      if (idIdx !== -1) return idIdx;

      const nameLower = (acc.name || '').trim().toLowerCase();
      const nameIdx = preferredOrder.findIndex(p => p.trim().toLowerCase() === nameLower);
      if (nameIdx !== -1) return nameIdx;

      return 999;
    };

    accountsList.sort((a, b) => {
      const idxA = getOrderIndex(a);
      const idxB = getOrderIndex(b);
      if (idxA !== idxB) return idxA - idxB;
      return a.name.localeCompare(b.name);
    });

    let totalAssets = 0;
    let totalLiabilities = 0;
    for (const acc of accountsList) {
      if (acc.balance >= 0) {
        totalAssets += acc.balance;
      } else {
        totalLiabilities += Math.abs(acc.balance);
      }
    }
    const netWorth = totalAssets - totalLiabilities;

    res.json({
      connected: true,
      accounts: accountsList,
      summary: {
        totalAssets,
        totalLiabilities,
        netWorth,
        accountsCount: accountsList.length,
      },
      budgets: [],
      recentRecords: recentRecords || [],
    });
  } catch (err: any) {
    console.error('Quickview error:', err.message);
    res.status(500).json({ error: 'Failed to load quickview data', details: err.message });
  }
});

// PATCH /api/wallet/accounts/reorder - Save custom account display order
router.patch('/accounts/reorder', authenticate, async (req: Request, res: Response) => {
  const userId = req.user.id;
  const { accountOrder } = req.body;

  if (!Array.isArray(accountOrder)) {
    return res.status(400).json({ error: 'accountOrder array is required' });
  }

  const user = await prisma.user.findUnique({ where: { id: userId } });
  const prefs = (user?.preferences as Record<string, any>) || {};

  await prisma.user.update({
    where: { id: userId },
    data: {
      preferences: {
        ...prefs,
        accountOrder,
      },
    },
  });

  res.json({ message: 'Account order updated successfully', accountOrder });
});

// GET /api/wallet/records - Get records from BudgetBakers Wallet
router.get('/records', authenticate, async (req: Request, res: Response) => {
  const userId = req.user.id;
  const user = await prisma.user.findUnique({ where: { id: userId } });
  if (!user || !user.walletApiToken) {
    return res.status(400).json({ error: 'Wallet not connected' });
  }

  try {
    const client = new WalletClient(user.walletApiToken);
    const limit = Math.min(Number(req.query.limit) || 20, 50);
    const accountId = req.query.accountId as string | undefined;
    const recordType = req.query.recordType as string | undefined;
    const counterParty = req.query.counterParty as string | undefined;

    const filters: any = { limit };
    if (accountId) filters.accountId = accountId;
    if (recordType === 'expense' || recordType === 'income') filters.recordType = recordType;
    if (counterParty && counterParty.trim().length > 0) filters.counterParty = `contains-i.${counterParty.trim()}`;

    const records = await client.getRecords(filters);
    res.json(records);
  } catch (err: any) {
    console.error('Records fetch error:', err.response?.data || err.message);
    res.status(500).json({ error: 'Failed to fetch records', details: err.response?.data || err.message });
  }
});

// PATCH /api/wallet/accounts/:id/map-last4 - Map bank account last 4 digits to Wallet account
router.patch('/accounts/:id/map-last4', authenticate, async (req: Request, res: Response) => {
  const userId = req.user.id;
  const id = req.params.id as string;
  const { last4Digits } = req.body;

  const existing = await prisma.walletAccount.findUnique({ where: { id } });
  if (!existing || existing.userId !== userId) {
    return res.status(404).json({ error: 'Account not found' });
  }

  // Clean last4Digits: support explicit NONE to mark accounts that don't need SMS/card mapping (e.g. Cash)
  const isNone = typeof last4Digits === 'string' && (
    last4Digits.trim().toUpperCase() === 'NONE' ||
    last4Digits.trim().toUpperCase() === 'SKIP' ||
    last4Digits.trim().toUpperCase() === 'N/A' ||
    last4Digits.trim().toUpperCase() === 'DONT_MAP'
  );

  const cleanedDigits = isNone
    ? 'NONE'
    : (typeof last4Digits === 'string'
        ? last4Digits.replace(/[^0-9,\s]/g, '').trim() || null
        : null);

  const account = await prisma.walletAccount.update({
    where: { id },
    data: { last4Digits: cleanedDigits },
  });

  // When mapping changes, update pending suggestions for the user:
  // 1. Clear previous mappings pointing to this account if digits changed or removed
  await prisma.suggestion.updateMany({
    where: {
      userId,
      status: 'pending',
      walletAccountId: account.walletAccountId,
    },
    data: {
      walletAccountId: null,
    },
  });

  // 2. If valid digits provided (and not NONE), link all pending suggestions matching these digits
  if (cleanedDigits && cleanedDigits !== 'NONE') {
    const digits = cleanedDigits.split(/[,;\s]+/).map(d => d.trim()).filter(d => d.length >= 2);
    if (digits.length > 0) {
      await prisma.suggestion.updateMany({
        where: {
          userId,
          status: 'pending',
          accountLast4: { in: digits },
        },
        data: {
          walletAccountId: account.walletAccountId,
        },
      });
    }
  }

  res.json(account);
});

// GET /api/wallet/categories - Get cached categories
router.get('/categories', authenticate, async (req: Request, res: Response) => {
  const userId = req.user.id;

  const categories = await prisma.walletCategoryCache.findMany({
    where: { userId },
    orderBy: [{ groupName: 'asc' }, { name: 'asc' }],
  });

  res.json(categories);
});

// POST /api/wallet/sync - Force sync accounts and categories from BudgetBakers Wallet
router.post('/sync', authenticate, async (req: Request, res: Response) => {
  const user = await prisma.user.findUnique({ where: { id: req.user.id } });

  if (!user || !user.walletApiToken) {
    return res.status(400).json({ error: 'Wallet not connected. Please provide your Wallet API token first.' });
  }

  try {
    const client = new WalletClient(user.walletApiToken);
    // Fetch all accounts across pages and all categories
    const [accounts, categories] = await Promise.all([
      client.getAllAccounts(),
      client.getCategories(),
    ]);

    // 1. Sync accounts to DB with accurate active/archived status
    const remoteAccountIds: string[] = [];
    for (const acc of accounts) {
      remoteAccountIds.push(acc.id);
      const isArchived = acc.archived === true || acc.archived === 'true';

      await prisma.walletAccount.upsert({
        where: { userId_walletAccountId: { userId: user.id, walletAccountId: acc.id } },
        update: {
          name: acc.name,
          currencyCode: acc.currencyCode || 'INR',
          accountType: acc.accountType || 'General',
          isActive: !isArchived,
          syncedAt: new Date(),
        },
        create: {
          userId: user.id,
          walletAccountId: acc.id,
          name: acc.name,
          currencyCode: acc.currencyCode || 'INR',
          accountType: acc.accountType || 'General',
          isActive: !isArchived,
          syncedAt: new Date(),
        },
      });
    }

    // Mark accounts previously in DB but missing from remote as inactive
    if (remoteAccountIds.length > 0) {
      await prisma.walletAccount.updateMany({
        where: {
          userId: user.id,
          walletAccountId: { notIn: remoteAccountIds },
        },
        data: {
          isActive: false,
        },
      });
    }

    // 2. Sync categories to cache
    for (const cat of categories) {
      await prisma.walletCategoryCache.upsert({
        where: { userId_walletCategoryId: { userId: user.id, walletCategoryId: cat.id } },
        update: {
          name: cat.name,
          groupId: cat.group?.id || 'others',
          groupName: cat.group?.name || 'Others',
          parentId: cat.parentId || null,
          isCustom: !!cat.customCategory,
          syncedAt: new Date()
        },
        create: {
          userId: user.id,
          walletCategoryId: cat.id,
          name: cat.name,
          groupId: cat.group?.id || 'others',
          groupName: cat.group?.name || 'Others',
          parentId: cat.parentId || null,
          isCustom: !!cat.customCategory,
          syncedAt: new Date()
        }
      });
    }

    res.json({
      message: 'Sync complete',
      accountsCount: accounts.length,
      categoriesCount: categories.length
    });
  } catch (err: any) {
    console.error('Wallet sync error:', err.response?.data || err.message);
    res.status(500).json({ error: 'Sync failed', details: err.response?.data || err.message });
  }
});

// POST /api/wallet/records - Create financial records in batch (1 to 50)
router.post('/records', authenticate, async (req: Request, res: Response) => {
  const userId = req.user.id;
  const user = await prisma.user.findUnique({ where: { id: userId } });
  if (!user || !user.walletApiToken) {
    return res.status(400).json({ error: 'Wallet not connected' });
  }

  const { records } = req.body;
  if (!Array.isArray(records) || records.length === 0) {
    return res.status(400).json({ error: 'records array is required' });
  }

  try {
    const client = new WalletClient(user.walletApiToken);
    const result = await client.createRecords(records);
    res.json(result);
  } catch (err: any) {
    console.error('Create records error:', err.response?.data || err.message);
    res.status(500).json({ error: 'Failed to create records', details: err.response?.data || err.message });
  }
});

function extractAccountBalance(accountObj: any): number | null {
  if (!accountObj) return null;
  const b = accountObj.balance;
  if (typeof b === 'number' && !isNaN(b)) {
    return b;
  }
  if (b && typeof b === 'object') {
    const candidate = b.currentBalance ?? b.rawCurrentBalance ?? b.initial;
    if (typeof candidate === 'number' && !isNaN(candidate)) {
      return candidate;
    }
    if (typeof candidate === 'string') {
      const parsed = parseFloat(candidate);
      if (!isNaN(parsed)) return parsed;
    }
  }
  if (typeof accountObj.currentBalance === 'number' && !isNaN(accountObj.currentBalance)) {
    return accountObj.currentBalance;
  }
  return null;
}

// POST /api/wallet/accounts/:id/update-balance - Manually update investment account value by recording an income/expense record
router.post('/accounts/:id/update-balance', authenticate, async (req: Request, res: Response) => {
  const userId = req.user.id;
  const id = req.params.id as string;
  const { newValue, currentValue: clientCurrentValue, note, recordDate } = req.body;

  if (typeof newValue !== 'number' || isNaN(newValue) || newValue < 0) {
    return res.status(400).json({ error: 'Valid positive newValue is required' });
  }

  const user = await prisma.user.findUnique({ where: { id: userId } });
  if (!user || !user.walletApiToken) {
    return res.status(400).json({ error: 'Wallet not connected' });
  }

  // Find account in DB or Wallet API
  const account = await prisma.walletAccount.findFirst({
    where: {
      userId,
      OR: [
        { id },
        { walletAccountId: id },
      ],
    },
  });

  const walletAccountId = account?.walletAccountId || id;
  const accountName = account?.name || 'Investment Account';

  try {
    const client = new WalletClient(user.walletApiToken);

    // Always query live accounts from Wallet API to get authoritative current balance
    WalletClient.clearCache();
    const allAccs = await client.getAllAccounts({ archived: false }).catch(err => {
      console.warn('[UpdateBalance] Failed to fetch live accounts:', err.message);
      return [];
    });

    const match = allAccs.find((a: any) =>
      a.id === walletAccountId ||
      (a.name && accountName && a.name.trim().toLowerCase() === accountName.trim().toLowerCase())
    );

    const liveBal = extractAccountBalance(match);

    let currentBal: number;
    if (liveBal !== null) {
      currentBal = liveBal;
    } else if (typeof clientCurrentValue === 'number' && !isNaN(clientCurrentValue) && clientCurrentValue > 0) {
      // Fallback only if live balance could not be extracted from Wallet API and client passed positive value
      currentBal = clientCurrentValue;
    } else {
      return res.status(400).json({
        error: `Could not verify current balance for account '${accountName}'. Please refresh the dashboard and try again.`,
      });
    }

    const diff = Number((newValue - currentBal).toFixed(2));
    if (Math.abs(diff) < 0.01) {
      return res.status(400).json({ error: 'New value is identical to current balance' });
    }

    const isIncome = diff > 0;
    const signedAmount = diff; // positive for income (+diff), negative for expense (-abs(diff))

    console.log(
      `[UpdateBalance] Account: "${accountName}" (${walletAccountId}), LiveBal: ${liveBal}, ClientVal: ${clientCurrentValue}, UsedCurrent: ${currentBal}, NewValue: ${newValue}, Diff: ${diff}, Type: ${isIncome ? 'income' : 'expense'}`
    );

    // Resolve category "Investment value update" under "Investments"
    const catCache = await prisma.walletCategoryCache.findFirst({
      where: {
        userId,
        name: { equals: 'Investment value update', mode: 'insensitive' },
      },
    });
    let categoryId = catCache?.walletCategoryId;
    if (!categoryId) {
      const parentCat = await prisma.walletCategoryCache.findFirst({
        where: {
          userId,
          name: { equals: 'Investments', mode: 'insensitive' },
        },
      });
      categoryId = parentCat?.walletCategoryId || '5c5c2328-005a-8000-8000-000000000000';
    }

    const txDate = recordDate ? new Date(recordDate) : new Date();

    const recordReq: CreateRecordRequest = {
      accountId: walletAccountId,
      amount: signedAmount,
      recordDate: txDate.toISOString(),
      categoryId,
      note: note || `Investment value update: ${accountName}`,
      recordState: 'cleared',
    };

    const batchResult = await client.createRecords([recordReq]);

    if (!batchResult.results || !batchResult.results[0] || !batchResult.results[0].success) {
      const err = batchResult.results?.[0]?.error || 'Failed to create record in Wallet';
      return res.status(500).json({ error: err, details: batchResult });
    }

    const walletRecordId = batchResult.results[0].id;

    // Record in local suggestions as synced for audit history
    await prisma.suggestion.create({
      data: {
        userId,
        source: 'manual',
        status: 'synced',
        amount: Math.abs(diff),
        currencyCode: account?.currencyCode || 'INR',
        transactionType: isIncome ? 'income' : 'expense',
        counterParty: 'Investment value update',
        note: note || `Investment value update: ${accountName}`,
        walletAccountId,
        walletCategoryId: categoryId,
        walletCategoryName: 'Investment value update',
        walletRecordId,
        transactionDate: txDate,
        actionedAt: new Date(),
      },
    }).catch(err => {
      console.warn('Could not create suggestion history entry:', err.message);
    });

    res.json({
      success: true,
      diff,
      transactionType: isIncome ? 'income' : 'expense',
      oldValue: currentBal,
      newValue,
      walletRecordId,
    });
  } catch (err: any) {
    console.error('Update balance error:', err.response?.data || err.message);
    res.status(500).json({ error: 'Failed to update investment value', details: err.response?.data || err.message });
  }
});

export default router;

