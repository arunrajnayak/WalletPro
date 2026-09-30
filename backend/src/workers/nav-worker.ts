import cron from 'node-cron';
import { prisma } from '../prisma';
import { PortfolioTracker } from '../services/portfolio-tracker';

const portfolioTracker = new PortfolioTracker();

export const startNavWorker = () => {
  // Run daily at 4:00 PM IST (10:30 AM UTC)
  cron.schedule('30 10 * * *', async () => {
    console.log('🔄 Running NAV refresh worker...');
    
    try {
      const users = await prisma.user.findMany({
        where: {
          portfolioHoldings: { some: {} }
        }
      });

      for (const user of users) {
        await portfolioTracker.refreshAllHoldings(user.id);
        await portfolioTracker.generateValueSuggestions(user.id);
      }
      
      console.log('✅ NAV refresh completed');
    } catch (error) {
      console.error('❌ Error in NAV refresh worker:', error);
    }
  });
};
