import { Router, Request, Response } from 'express';
import { prisma } from '../prisma';
import { PortfolioTracker } from '../services/portfolio-tracker';
import { env } from '../config/env';

const router = Router();
const portfolioTracker = new PortfolioTracker();

/**
 * Middleware to verify cron requests if CRON_SECRET is set
 */
const verifyCronSecret = (req: Request, res: Response, next: () => void) => {
  if (env.CRON_SECRET) {
    const authHeader = req.headers.authorization;
    if (authHeader !== `Bearer ${env.CRON_SECRET}`) {
      return res.status(401).json({ error: 'Unauthorized cron request' });
    }
  }
  next();
};

/**
 * GET /api/cron/nav
 * Daily cron (e.g. 4:00 PM IST after market close)
 * Refreshes all portfolio holdings (MFs, Stocks, NPS) and generates value suggestions
 */
router.get('/nav', verifyCronSecret, async (_req: Request, res: Response) => {
  try {
    const users = await prisma.user.findMany({ select: { id: true } });
    let totalSuggestions = 0;

    for (const u of users) {
      await portfolioTracker.refreshAllHoldings(u.id);
      const suggestions = await portfolioTracker.generateValueSuggestions(u.id);
      totalSuggestions += suggestions.length;
    }

    res.json({
      status: 'ok',
      message: 'NAV refresh completed',
      usersProcessed: users.length,
      suggestionsGenerated: totalSuggestions
    });
  } catch (err: any) {
    console.error('Cron NAV error:', err);
    res.status(500).json({ error: 'Cron NAV failed', details: err.message });
  }
});

/**
 * GET /api/cron/cleanup
 * Daily cron to expire pending suggestions older than 30 days
 */
router.get('/cleanup', verifyCronSecret, async (_req: Request, res: Response) => {
  try {
    const thirtyDaysAgo = new Date(Date.now() - 30 * 24 * 60 * 60 * 1000);

    const result = await prisma.suggestion.updateMany({
      where: {
        status: 'pending',
        createdAt: { lt: thirtyDaysAgo }
      },
      data: {
        status: 'expired',
        actionedAt: new Date()
      }
    });

    res.json({
      status: 'ok',
      message: 'Cleanup completed',
      expiredCount: result.count
    });
  } catch (err: any) {
    console.error('Cron cleanup error:', err);
    res.status(500).json({ error: 'Cron cleanup failed', details: err.message });
  }
});

export default router;
