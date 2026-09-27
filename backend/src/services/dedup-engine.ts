import crypto from 'crypto';
import { prisma } from '../prisma';

export class DedupEngine {
  /**
   * Generates a hash for a transaction to allow fast exact matches.
   */
  private generateHash(userId: string, date: Date, amount: number, last4?: string): string {
    const dateStr = date.toISOString().split('T')[0];
    const data = `${userId}|${dateStr}|${amount.toFixed(2)}|${last4 || ''}`;
    return crypto.createHash('sha256').update(data).digest('hex');
  }

  /**
   * Checks if a transaction is a duplicate.
   * Returns true if duplicate, false otherwise.
   */
  public async isDuplicate(
    userId: string,
    transactionDate: Date,
    amount: number,
    referenceNumber?: string,
    accountLast4?: string
  ): Promise<boolean> {
    // Layer 1: Exact reference number match
    if (referenceNumber) {
      const exactRefMatch = await prisma.dedupEntry.findFirst({
        where: { userId, referenceNumber }
      });
      if (exactRefMatch) return true;
    }

    // Layer 2: Fuzzy match (same amount, same account_last4, +/- 10 min window)
    const windowStart = new Date(transactionDate.getTime() - 10 * 60000);
    const windowEnd = new Date(transactionDate.getTime() + 10 * 60000);

    const fuzzyMatch = await prisma.dedupEntry.findFirst({
      where: {
        userId,
        amount,
        accountLast4: accountLast4 || undefined,
        transactionDate: {
          gte: windowStart,
          lte: windowEnd
        }
      }
    });

    if (fuzzyMatch) return true;

    // Layer 3: Check pending suggestions
    const pendingMatch = await prisma.suggestion.findFirst({
      where: {
        userId,
        amount,
        accountLast4: accountLast4 || undefined,
        status: { in: ['pending', 'approved', 'synced'] },
        transactionDate: {
          gte: windowStart,
          lte: windowEnd
        }
      }
    });

    return !!pendingMatch;
  }

  /**
   * Records a transaction in the dedup table.
   */
  public async recordTransaction(
    userId: string,
    transactionDate: Date,
    amount: number,
    source: string,
    referenceNumber?: string,
    accountLast4?: string,
    suggestionId?: string
  ) {
    const hash = this.generateHash(userId, transactionDate, amount, accountLast4);
    await prisma.dedupEntry.create({
      data: {
        userId,
        referenceNumber,
        amount,
        accountLast4,
        transactionDate,
        source,
        suggestionId,
        hash
      }
    });
  }
}
