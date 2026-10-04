import crypto from 'crypto';
import { prisma } from '../prisma';

export class InFlightMutex {
  private active = new Set<string>();

  public async acquire(key: string): Promise<() => void> {
    const start = Date.now();
    while (this.active.has(key)) {
      if (Date.now() - start > 10000) break;
      await new Promise((resolve) => setTimeout(resolve, 50));
    }
    this.active.add(key);
    return () => {
      this.active.delete(key);
    };
  }
}

export const inFlightMutex = new InFlightMutex();

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
   * Checks if a transaction is a duplicate across sourceId, referenceNumber, rawText, and fuzzy matches.
   * Returns true if duplicate, false otherwise.
   */
  public async isDuplicate(
    userId: string,
    transactionDate: Date,
    amount: number,
    referenceNumber?: string,
    accountLast4?: string,
    rawText?: string,
    sourceId?: string
  ): Promise<boolean> {
    // Layer 0: Exact sourceId match (if provided)
    if (sourceId) {
      const existingBySourceId = await prisma.suggestion.findFirst({
        where: {
          userId,
          sourceId: String(sourceId),
        },
      });
      if (existingBySourceId) return true;
    }

    // Layer 1: Exact reference number match
    if (referenceNumber && referenceNumber.trim().length > 0) {
      const cleanRef = referenceNumber.trim();
      const exactRefMatch = await prisma.dedupEntry.findFirst({
        where: { userId, referenceNumber: cleanRef },
      });
      if (exactRefMatch) return true;

      const suggestionRefMatch = await prisma.suggestion.findFirst({
        where: {
          userId,
          referenceNumber: cleanRef,
          status: { in: ['pending', 'approved', 'synced'] },
        },
      });
      if (suggestionRefMatch) return true;
    }

    // Layer 2: Exact or normalized rawText match (same SMS content)
    if (rawText && rawText.trim().length > 10) {
      const normalized = rawText.replace(/\s+/g, ' ').trim();
      const rawTextMatch = await prisma.suggestion.findFirst({
        where: {
          userId,
          status: { in: ['pending', 'approved', 'synced'] },
          rawText: {
            contains: normalized.slice(0, 40),
            mode: 'insensitive',
          },
          amount,
        },
      });
      if (rawTextMatch) return true;
    }

    // Layer 3: Fuzzy match (same amount, matching or null accountLast4, +/- 10 min window + 5.5h timezone tolerance)
    const windowStart = new Date(transactionDate.getTime() - 10 * 60000);
    const windowEnd = new Date(transactionDate.getTime() + 10 * 60000);

    // Accommodate potential 5.5h (330 min) UTC vs IST client-server serialization discrepancies
    const istOffsetMillis = 330 * 60000;
    const tzEarlyStart = new Date(windowStart.getTime() - istOffsetMillis);
    const tzEarlyEnd = new Date(windowEnd.getTime() - istOffsetMillis);
    const tzLateStart = new Date(windowStart.getTime() + istOffsetMillis);
    const tzLateEnd = new Date(windowEnd.getTime() + istOffsetMillis);

    const dateFilters: Array<{ transactionDate: { gte: Date; lte: Date } }> = [
      { transactionDate: { gte: windowStart, lte: windowEnd } },
      { transactionDate: { gte: tzEarlyStart, lte: tzEarlyEnd } },
      { transactionDate: { gte: tzLateStart, lte: tzLateEnd } },
    ];

    const accountFilter = accountLast4
      ? { OR: [{ accountLast4 }, { accountLast4: null }] }
      : {};

    const fuzzyMatch = await prisma.dedupEntry.findFirst({
      where: {
        userId,
        amount,
        ...accountFilter,
        OR: dateFilters,
      },
    });

    if (fuzzyMatch) return true;

    // Layer 4: Check pending or active suggestions
    const pendingMatch = await prisma.suggestion.findFirst({
      where: {
        userId,
        amount,
        status: { in: ['pending', 'approved', 'synced'] },
        ...accountFilter,
        OR: dateFilters,
      },
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
        hash,
      },
    });
  }

  /**
   * Handles deduplication and pairing between OTP messages and confirmed debit/credit messages.
   * - If incoming is a confirmed transaction (not OTP):
   *   Finds any existing pending OTP suggestion within 15 minutes with matching amount and account.
   *   Rejects the OTP suggestion (and purges its dedup entry) so the confirmed transaction replaces it.
   * - If incoming is an OTP message:
   *   Checks if a confirmed transaction already exists within 15 minutes.
   *   If so, returns true (indicating this OTP should be discarded/skipped).
   */
  public async handleOtpPairing(
    userId: string,
    amount: number,
    transactionDate: Date,
    accountLast4?: string,
    isIncomingOtp: boolean = false
  ): Promise<{ shouldDiscardIncoming: boolean; supersededOtpId?: string }> {
    const window15mStart = new Date(transactionDate.getTime() - 15 * 60000);
    const window15mEnd = new Date(transactionDate.getTime() + 15 * 60000);

    const accountFilter = accountLast4
      ? { OR: [{ accountLast4 }, { accountLast4: null }] }
      : {};

    if (!isIncomingOtp) {
      // Incoming is a confirmed transaction message.
      // Look for pending OTP suggestions within 15 minutes.
      const pendingOtpSuggestions = await prisma.suggestion.findMany({
        where: {
          userId,
          status: 'pending',
          amount,
          ...accountFilter,
          transactionDate: { gte: window15mStart, lte: window15mEnd },
          OR: [
            { note: { contains: '[OTP Transaction]' } },
            { rawText: { contains: 'OTP', mode: 'insensitive' } },
          ],
        },
      });

      if (pendingOtpSuggestions.length > 0) {
        for (const otpSugg of pendingOtpSuggestions) {
          console.log(`Auto-rejecting pending OTP suggestion ${otpSugg.id} superseded by confirmed transaction SMS`);
          await prisma.suggestion.update({
            where: { id: otpSugg.id },
            data: {
              status: 'rejected',
              actionedAt: new Date(),
              note: ((otpSugg.note || '') + ' [Auto-rejected: Confirmed transaction SMS arrived within 15min]').trim(),
            },
          });
          await prisma.dedupEntry.deleteMany({
            where: { suggestionId: otpSugg.id },
          });
        }
        return { shouldDiscardIncoming: false, supersededOtpId: pendingOtpSuggestions[0].id };
      }

      return { shouldDiscardIncoming: false };
    } else {
      // Incoming is an OTP transaction message.
      // If a confirmed transaction already exists within 15 minutes, discard this OTP.
      const existingConfirmedTxn = await prisma.suggestion.findFirst({
        where: {
          userId,
          status: { in: ['pending', 'approved', 'synced'] },
          amount,
          ...accountFilter,
          transactionDate: { gte: window15mStart, lte: window15mEnd },
          NOT: {
            OR: [
              { note: { contains: '[OTP Transaction]' } },
              { rawText: { contains: 'OTP', mode: 'insensitive' } },
            ],
          },
        },
      });

      if (existingConfirmedTxn) {
        console.log(`Discarding incoming OTP message: Confirmed transaction ${existingConfirmedTxn.id} already exists`);
        return { shouldDiscardIncoming: true };
      }

      return { shouldDiscardIncoming: false };
    }
  }
}

