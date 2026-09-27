import { Router, Request, Response } from 'express';
import { authenticate } from '../middleware/auth';
import { prisma } from '../prisma';

const router = Router();

// POST /api/auth/login
router.post('/login', authenticate, async (req: Request, res: Response) => {
  const user = req.user;
  res.json({ message: 'Login successful', user });
});

// GET /api/auth/profile
router.get('/profile', authenticate, async (req: Request, res: Response) => {
  const user = req.user;
  
  const fullUser = await prisma.user.findUnique({
    where: { id: user.id },
    select: {
      id: true,
      email: true,
      displayName: true,
      walletApiToken: true,
      preferences: true,
      createdAt: true
    }
  });
  
  res.json(fullUser);
});

// PATCH /api/auth/preferences - Update user preferences (sliding window, sync start date, etc.)
router.patch('/preferences', authenticate, async (req: Request, res: Response) => {
  const userId = req.user.id;
  const { syncStartDate, lastReviewedDate, autoAdvanceWindow } = req.body;

  const user = await prisma.user.findUnique({ where: { id: userId } });
  if (!user) {
    return res.status(404).json({ error: 'User not found' });
  }

  const existingPrefs = (user.preferences as Record<string, any>) || {};

  const updatedPrefs = {
    ...existingPrefs,
    ...(syncStartDate !== undefined && { syncStartDate }),
    ...(lastReviewedDate !== undefined && { lastReviewedDate }),
    ...(autoAdvanceWindow !== undefined && { autoAdvanceWindow: !!autoAdvanceWindow }),
  };

  const updatedUser = await prisma.user.update({
    where: { id: userId },
    data: { preferences: updatedPrefs },
    select: {
      id: true,
      preferences: true,
    }
  });

  res.json({
    message: 'Preferences updated successfully',
    preferences: updatedUser.preferences,
  });
});

export default router;
