import axios from 'axios';
import { prisma } from '../prisma';

export class PortfolioTracker {
  /**
   * Fetch latest NAV for Mutual Funds from mfapi.in (open API)
   */
  public async fetchMFNav(schemeCode: string): Promise<number | null> {
    try {
      const res = await axios.get(`https://api.mfapi.in/mf/${schemeCode}/latest`, { timeout: 10000 });
      if (res.data && res.data.data && res.data.data.length > 0) {
        return parseFloat(res.data.data[0].nav);
      }
      return null;
    } catch (err) {
      console.error(`Failed to fetch NAV for ${schemeCode}:`, err);
      return null;
    }
  }

  /**
   * Refresh all holdings (Mutual Funds, Stocks, NPS) for a user
   */
  public async refreshAllHoldings(userId: string) {
    const holdings = await prisma.portfolioHolding.findMany({
      where: { userId }
    });

    for (const holding of holdings) {
      let nav: number | null = null;

      if (holding.type === 'mutual_fund') {
        nav = await this.fetchMFNav(holding.code);
      } else if (holding.type === 'stock') {
        // In personal mode, can fetch from free quote APIs or retain current value
        nav = Number(holding.currentNav);
      } else if (holding.type === 'nps') {
        nav = Number(holding.currentNav);
      }

      if (nav && nav > 0) {
        const units = Number(holding.units);
        const currentValue = nav * units;
        
        await prisma.portfolioHolding.update({
          where: { id: holding.id },
          data: {
            previousNav: holding.currentNav,
            currentNav: nav,
            currentValue,
            navUpdatedAt: new Date()
          }
        });
      }
    }
  }

  /**
   * Generate suggestions for value changes in investment holdings
   * to sync with BudgetBakers Wallet.
   */
  public async generateValueSuggestions(userId: string) {
    const holdings = await prisma.portfolioHolding.findMany({
      where: { userId }
    });

    const suggestions = [];

    for (const holding of holdings) {
      const currentNav = Number(holding.currentNav);
      const previousNav = Number(holding.previousNav);
      const units = Number(holding.units);

      if (previousNav > 0 && currentNav > 0 && currentNav !== previousNav) {
        const diff = (currentNav - previousNav) * units;
        const absDiff = Math.abs(diff);

        // Only create suggestion if change is meaningful (>= ₹1.00)
        if (absDiff >= 1.0) {
          const isGain = diff > 0;
          const transactionType = isGain ? 'income' : 'expense';
          const typeLabel = holding.type === 'mutual_fund' ? 'Mutual Fund' : holding.type === 'nps' ? 'NPS' : 'Stock';
          
          const suggestion = await prisma.suggestion.create({
            data: {
              userId,
              source: holding.type === 'nps' ? 'nps' : 'portfolio',
              status: 'pending',
              amount: absDiff,
              currencyCode: 'INR',
              transactionType,
              counterParty: `${typeLabel} Value Update`,
              note: `${holding.name} (${holding.code}): NAV changed from ₹${previousNav.toFixed(2)} to ₹${currentNav.toFixed(2)}`,
              walletAccountId: holding.walletAccountId,
              transactionDate: new Date(),
              aiConfidence: 0.99,
            }
          });

          // Mark previousNav as caught up to prevent duplicate suggestions
          await prisma.portfolioHolding.update({
            where: { id: holding.id },
            data: { previousNav: currentNav }
          });

          suggestions.push(suggestion);
        }
      }
    }

    return suggestions;
  }
}
