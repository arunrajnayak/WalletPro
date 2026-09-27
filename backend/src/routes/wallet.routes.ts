import { Router, Request, Response } from 'express';
import { authenticate } from '../middleware/auth';
import { prisma } from '../prisma';
import { WalletClient } from '../services/wallet-client';

const router = Router();

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

    // Fetch accounts, budgets, and recent records
    const [remoteAccounts, remoteBudgets, recentRecords] = await Promise.all([
      client.getAllAccounts({ archived: false }).catch(err => {
        console.warn('Failed to fetch remote accounts:', err.message);
        return [];
      }),
      client.getBudgets().catch(err => {
        console.warn('Failed to fetch budgets:', err.message);
        return [];
      }),
      client.getRecords({ limit: 15, sortBy: ['-recordDate'] }).catch(err => {
        console.warn('Failed to fetch recent records:', err.message);
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
      budgets: remoteBudgets || [],
      recentRecords: recentRecords || [],
    });
  } catch (err: any) {
    console.error('Quickview error:', err.message);
    res.status(500).json({ error: 'Failed to load quickview data', details: err.message });
  }
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
    const records = await client.getRecords({
      limit,
      sortBy: ['-recordDate'],
      ...(accountId ? { accountId } : {}),
    });
    res.json(records);
  } catch (err: any) {
    res.status(500).json({ error: 'Failed to fetch records', details: err.message });
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

  // Clean last4Digits: strip extra spaces/special chars, keep digits & commas for multi-card mappings
  const cleanedDigits = typeof last4Digits === 'string'
    ? last4Digits.replace(/[^0-9,\s]/g, '').trim() || null
    : null;

  const account = await prisma.walletAccount.update({
    where: { id },
    data: { last4Digits: cleanedDigits },
  });

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

export default router;
