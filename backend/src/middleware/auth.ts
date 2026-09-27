import { Request, Response, NextFunction } from 'express';
import { prisma } from '../prisma';
import { env } from '../config/env';

// Add user to Request type
declare global {
  namespace Express {
    interface Request {
      user?: any;
    }
  }
}

/**
 * Authentication middleware optimized for personal/single-user deployment.
 * 
 * In Single-User Mode (default for personal use):
 * 1. If API_SECRET_KEY is configured in env, verifies 'x-api-key' or 'Bearer <key>'.
 * 2. If no key is configured or matched, automatically resolves to the single personal user.
 * 3. Automatically ensures the personal user exists in PostgreSQL and syncs WALLET_API_TOKEN from env if present.
 */
export const authenticate = async (req: Request, res: Response, next: NextFunction) => {
  try {
    const authHeader = req.headers.authorization;
    const apiKeyHeader = req.headers['x-api-key'] as string | undefined;

    // Check Single-User Mode
    if (env.SINGLE_USER_MODE) {
      // If user specified an API_SECRET_KEY, verify it
      if (env.API_SECRET_KEY) {
        const providedToken = apiKeyHeader || (authHeader?.startsWith('Bearer ') ? authHeader.slice(7) : null);
        if (!providedToken || providedToken !== env.API_SECRET_KEY) {
          return res.status(401).json({ error: 'Unauthorized: Invalid API secret key' });
        }
      }

      const uid = env.PERSONAL_USER_ID;

      // Find or create the personal user
      let user = await prisma.user.findUnique({
        where: { firebaseUid: uid },
      });

      if (!user) {
        user = await prisma.user.create({
          data: {
            firebaseUid: uid,
            displayName: 'Personal User',
            walletApiToken: env.WALLET_API_TOKEN || null,
          },
        });
      } else if (env.WALLET_API_TOKEN && !user.walletApiToken) {
        // Sync WALLET_API_TOKEN from env if not already populated
        user = await prisma.user.update({
          where: { id: user.id },
          data: { walletApiToken: env.WALLET_API_TOKEN },
        });
      }

      req.user = user;
      return next();
    }

    // Standard Multi-User Flow (Fallback)
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      return res.status(401).json({ error: 'Unauthorized: No token provided' });
    }

    const token = authHeader.split('Bearer ')[1];
    const uid = token.trim();

    let user = await prisma.user.findUnique({
      where: { firebaseUid: uid },
    });

    if (!user) {
      user = await prisma.user.create({
        data: { firebaseUid: uid },
      });
    }

    req.user = user;
    next();
  } catch (error) {
    console.error('Auth error:', error);
    res.status(401).json({ error: 'Unauthorized: Authentication failed' });
  }
};
