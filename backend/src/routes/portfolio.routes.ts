import { Router, Request, Response } from 'express';
import { authenticate } from '../middleware/auth';
import { prisma } from '../prisma';
import { PortfolioTracker } from '../services/portfolio-tracker';

const router = Router();
const portfolioTracker = new PortfolioTracker();

// GET /api/portfolio - List all holdings
router.get('/', authenticate, async (req: Request, res: Response) => {
  const userId = req.user.id;
  const { type } = req.query;

  const where: any = { userId };
  if (type) where.type = type;

  const holdings = await prisma.portfolioHolding.findMany({
    where,
    orderBy: { currentValue: 'desc' }
  });
  
  res.json(holdings);
});

// GET /api/portfolio/summary - Portfolio totals and breakdown
router.get('/summary', authenticate, async (req: Request, res: Response) => {
  const userId = req.user.id;
  
  const holdings = await prisma.portfolioHolding.findMany({
    where: { userId }
  });

  let totalValue = 0;
  let totalInvested = 0;
  const holdingsByType = {
    mutual_fund: { count: 0, value: 0 },
    stock: { count: 0, value: 0 },
    nps: { count: 0, value: 0 }
  };

  for (const h of holdings) {
    const val = Number(h.currentValue);
    const invested = Number(h.avgCost) * Number(h.units);
    totalValue += val;
    totalInvested += invested;

    const t = h.type as 'mutual_fund' | 'stock' | 'nps';
    if (holdingsByType[t]) {
      holdingsByType[t].count += 1;
      holdingsByType[t].value += val;
    }
  }

  const totalGainLoss = totalValue - totalInvested;
  const totalChangePercent = totalInvested > 0 ? (totalGainLoss / totalInvested) * 100 : 0;

  res.json({
    totalValue,
    totalInvested,
    totalGainLoss,
    totalChangePercent,
    holdingsByType,
    holdingsCount: holdings.length
  });
});

// POST /api/portfolio/holdings - Add a new holding
router.post('/holdings', authenticate, async (req: Request, res: Response) => {
  const userId = req.user.id;
  const { type, name, code, units, avgCost, currentNav, walletAccountId } = req.body;

  if (!type || !name || !code || units === undefined || avgCost === undefined) {
    return res.status(400).json({ error: 'Missing required holding fields (type, name, code, units, avgCost)' });
  }

  let nav = currentNav ? Number(currentNav) : Number(avgCost);

  // If mutual fund, attempt to fetch current NAV from mfapi.in
  if (type === 'mutual_fund') {
    const liveNav = await portfolioTracker.fetchMFNav(code);
    if (liveNav) nav = liveNav;
  }

  const numUnits = Number(units);
  const currentValue = nav * numUnits;

  const holding = await prisma.portfolioHolding.upsert({
    where: { userId_type_code: { userId, type, code } },
    update: {
      name,
      units: numUnits,
      avgCost: Number(avgCost),
      currentNav: nav,
      previousNav: nav,
      currentValue,
      walletAccountId: walletAccountId || undefined,
      navUpdatedAt: new Date(),
    },
    create: {
      userId,
      type,
      name,
      code,
      units: numUnits,
      avgCost: Number(avgCost),
      currentNav: nav,
      previousNav: nav,
      currentValue,
      walletAccountId: walletAccountId || undefined,
      navUpdatedAt: new Date(),
    }
  });

  res.status(201).json(holding);
});

// PATCH /api/portfolio/holdings/:id - Update an existing holding
router.patch('/holdings/:id', authenticate, async (req: Request, res: Response) => {
  const userId = req.user.id;
  const id = req.params.id as string;
  const { units, avgCost, currentNav, walletAccountId } = req.body;

  const existing = await prisma.portfolioHolding.findUnique({ where: { id } });
  if (!existing || existing.userId !== userId) {
    return res.status(404).json({ error: 'Holding not found' });
  }

  const updatedUnits = units !== undefined ? Number(units) : Number(existing.units);
  const updatedNav = currentNav !== undefined ? Number(currentNav) : Number(existing.currentNav);
  const currentValue = updatedNav * updatedUnits;

  const holding = await prisma.portfolioHolding.update({
    where: { id },
    data: {
      units: updatedUnits,
      avgCost: avgCost !== undefined ? Number(avgCost) : undefined,
      currentNav: updatedNav,
      currentValue,
      walletAccountId: walletAccountId !== undefined ? walletAccountId : existing.walletAccountId,
      navUpdatedAt: new Date()
    }
  });

  res.json(holding);
});

// DELETE /api/portfolio/holdings/:id - Remove a holding
router.delete('/holdings/:id', authenticate, async (req: Request, res: Response) => {
  const userId = req.user.id;
  const id = req.params.id as string;

  await prisma.portfolioHolding.deleteMany({
    where: { id, userId }
  });

  res.json({ message: 'Holding deleted' });
});

// POST /api/portfolio/refresh - Force refresh all holdings from live feeds
router.post('/refresh', authenticate, async (req: Request, res: Response) => {
  const userId = req.user.id;
  
  await portfolioTracker.refreshAllHoldings(userId);
  const suggestions = await portfolioTracker.generateValueSuggestions(userId);
  
  res.json({
    message: 'Portfolio refreshed',
    generatedSuggestionsCount: suggestions.length
  });
});

// POST /api/portfolio/generate-suggestions - Generate suggestions for value changes
router.post('/generate-suggestions', authenticate, async (req: Request, res: Response) => {
  const userId = req.user.id;
  const suggestions = await portfolioTracker.generateValueSuggestions(userId);
  res.json({ suggestions });
});

export default router;
