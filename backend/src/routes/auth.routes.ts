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

// PATCH /api/auth/preferences - Update user preferences
router.patch('/preferences', authenticate, async (req: Request, res: Response) => {
  const userId = req.user.id;

  const user = await prisma.user.findUnique({ where: { id: userId } });
  if (!user) {
    return res.status(404).json({ error: 'User not found' });
  }

  const existingPrefs = (user.preferences as Record<string, any>) || {};
  const { syncStartDate, lastReviewedDate, autoAdvanceWindow, ...otherPrefs } = req.body;

  const updatedPrefs = {
    ...existingPrefs,
    ...otherPrefs,
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
