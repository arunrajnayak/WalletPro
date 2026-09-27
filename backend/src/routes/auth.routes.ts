import { Router, Request, Response } from 'express';
import { authenticate } from '../middleware/auth';
import { PrismaClient } from '@prisma/client';

const router = Router();
const prisma = new PrismaClient();

// POST /api/auth/login
router.post('/login', authenticate, async (req: Request, res: Response) => {
  // @ts-ignore - authenticate middleware attaches user
  const user = req.user;
  res.json({ message: 'Login successful', user });
});

// GET /api/auth/profile
router.get('/profile', authenticate, async (req: Request, res: Response) => {
  // @ts-ignore
  const user = req.user;
  
  const fullUser = await prisma.user.findUnique({
    where: { id: user.id },
    select: {
      id: true,
      email: true,
      displayName: true,
      walletApiToken: true, // Should probably omit or mask this in real app
      createdAt: true
    }
  });
  
  res.json(fullUser);
});

export default router;
