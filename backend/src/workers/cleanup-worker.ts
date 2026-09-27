import cron from 'node-cron';
import { PrismaClient } from '@prisma/client';

const prisma = new PrismaClient();

export const startCleanupWorker = () => {
  // Run daily at midnight
  cron.schedule('0 0 * * *', async () => {
    console.log('🧹 Running cleanup worker...');
    
    try {
      const thirtyDaysAgo = new Date();
      thirtyDaysAgo.setDate(thirtyDaysAgo.getDate() - 30);

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

      console.log(`✅ Cleanup completed. Expired ${result.count} suggestions.`);
    } catch (error) {
      console.error('❌ Error in cleanup worker:', error);
    }
  });
};
