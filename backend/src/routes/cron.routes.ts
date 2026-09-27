import { Router, Request, Response } from 'express';
import { prisma } from '../prisma';
import { env } from '../config/env';

const router = Router();

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
 * Disabled: User manages investment tracking manually.
 */
router.get('/nav', verifyCronSecret, async (_req: Request, res: Response) => {
  res.json({
    status: 'disabled',
    message: 'Investment / portfolio sync feature is disabled. Investments are managed manually.',
  });
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
