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
  private db: any;

  constructor(db?: any) {
    this.db = db || prisma;
  }

  /**
   * Generates a hash for a transaction to allow fast exact matches.
   */
  private generateHash(userId: string, date: Date, amount: number, last4?: string): string {
    const dateStr = date.toISOString().split('T')[0];
    const data = `${userId}|${dateStr}|${amount.toFixed(2)}|${last4 || ''}`;
    return crypto.createHash('sha256').update(data).digest('hex');
  }

  /**
   * Finds any duplicate transaction across sourceId, referenceNumber, rawText, and fuzzy matches.
   * Returns details including the matched suggestion ID if found.
   */
  public async findDuplicate(
    userId: string,
    transactionDate: Date,
    amount: number,
    referenceNumber?: string,
    accountLast4?: string,
    rawText?: string,
    sourceId?: string,
    counterParty?: string
  ): Promise<{ isDuplicate: boolean; matchedSuggestionId?: string }> {
    const cleanRef = referenceNumber?.trim();
    const cleanCounterParty = counterParty?.trim();

    // Layer 0: Exact sourceId match (if provided)
    if (sourceId) {
      const existingBySourceId = await this.db.suggestion.findFirst({
        where: {
          userId,
          sourceId: String(sourceId),
        },
        select: { id: true },
      });
      if (existingBySourceId) {
        return { isDuplicate: true, matchedSuggestionId: existingBySourceId.id };
      }
    }

    // Layer 1: Exact reference number match (UPI Ref / RRN / UTR / Order ID)
    if (cleanRef && cleanRef.length > 0) {
      const suggestionRefMatch = await this.db.suggestion.findFirst({
        where: {
          userId,
          referenceNumber: cleanRef,
          status: { in: ['pending', 'approved', 'synced'] },
        },
        select: { id: true },
      });
      if (suggestionRefMatch) {
        return { isDuplicate: true, matchedSuggestionId: suggestionRefMatch.id };
      }

      const exactRefMatch = await this.db.dedupEntry.findFirst({
        where: { userId, referenceNumber: cleanRef },
        select: { suggestionId: true },
      });
      if (exactRefMatch) {
        return { isDuplicate: true, matchedSuggestionId: exactRefMatch.suggestionId || undefined };
      }
    }

    // Layer 2: Exact normalized full rawText match within a 4-hour window
    // (Never match just a 40-char prefix, and don't match identical recurring SMS across days)
    if (rawText && rawText.trim().length > 10) {
      const normalized = rawText.replace(/\s+/g, ' ').trim();
      const rawWindowStart = new Date(transactionDate.getTime() - 4 * 3600 * 1000);
      const rawWindowEnd = new Date(transactionDate.getTime() + 4 * 3600 * 1000);

      const rawTextMatches = await this.db.suggestion.findMany({
        where: {
          userId,
          status: { in: ['pending', 'approved', 'synced'] },
          rawText: normalized,
          amount,
          transactionDate: { gte: rawWindowStart, lte: rawWindowEnd },
        },
        select: { id: true, sourceId: true },
      });

      for (const match of rawTextMatches) {
        // If both have distinct SMS source IDs, they are two separate physical SMS messages received by the phone!
        if (sourceId && match.sourceId && sourceId.startsWith('sms_') && match.sourceId.startsWith('sms_') && sourceId !== match.sourceId) {
          continue;
        }
        return { isDuplicate: true, matchedSuggestionId: match.id };
      }
    }

    // Layer 3: Fuzzy match (same amount within tight +/- 10 min window)
    // Primarily designed for cross-source pairing (e.g. Bank SMS + Amazon App Push for the same purchase)
    const windowStart = new Date(transactionDate.getTime() - 10 * 60000);
    const windowEnd = new Date(transactionDate.getTime() + 10 * 60000);

    const accountFilter = accountLast4
      ? { OR: [{ accountLast4 }, { accountLast4: null }] }
      : {};

    const isGenericMerchant = (c?: string | null) => {
      if (!c) return true;
      const lower = c.trim().toLowerCase();
      return ['vpa', 'amazon', 'upi', 'fastag toll', 'unknown'].includes(lower);
    };

    // Check pending or active suggestions candidates within the 10m window
    const pendingCandidates = await this.db.suggestion.findMany({
      where: {
        userId,
        amount,
        status: { in: ['pending', 'approved', 'synced'] },
        ...accountFilter,
        transactionDate: { gte: windowStart, lte: windowEnd },
      },
      select: {
        id: true,
        referenceNumber: true,
        counterParty: true,
        accountLast4: true,
        sourceId: true,
      },
    });

    for (const cand of pendingCandidates) {
      // Guard 1: Conflicting reference numbers -> NOT a duplicate!
      if (cleanRef && cand.referenceNumber && cand.referenceNumber.trim().length > 0) {
        if (cleanRef.toLowerCase() !== cand.referenceNumber.trim().toLowerCase()) {
          continue;
        }
      }

      // Guard 2: Conflicting merchants -> NOT a duplicate!
      if (cleanCounterParty && cand.counterParty && !isGenericMerchant(cleanCounterParty) && !isGenericMerchant(cand.counterParty)) {
        if (cleanCounterParty.toLowerCase() !== cand.counterParty.trim().toLowerCase()) {
          continue;
        }
      }

      // Guard 3: Conflicting account last 4 -> NOT a duplicate!
      if (accountLast4 && cand.accountLast4 && accountLast4.trim().length > 0 && cand.accountLast4.trim().length > 0) {
        if (accountLast4.trim().toLowerCase() !== cand.accountLast4.trim().toLowerCase()) {
          continue;
        }
      }

      // Guard 4: Same-source guard: two separate SMS events from bank with distinct sourceIds -> NOT a duplicate!
      if (sourceId && cand.sourceId && sourceId.startsWith('sms_') && cand.sourceId.startsWith('sms_') && sourceId !== cand.sourceId) {
        continue;
      }

      return { isDuplicate: true, matchedSuggestionId: cand.id };
    }

    // Check dedupEntry candidates within the 10m window
    const dedupCandidates = await this.db.dedupEntry.findMany({
      where: {
        userId,
        amount,
        ...accountFilter,
        transactionDate: { gte: windowStart, lte: windowEnd },
      },
      select: {
        suggestionId: true,
        referenceNumber: true,
        accountLast4: true,
        source: true,
      },
    });

    for (const cand of dedupCandidates) {
      // Guard 1: Conflicting reference numbers -> NOT a duplicate!
      if (cleanRef && cand.referenceNumber && cand.referenceNumber.trim().length > 0) {
        if (cleanRef.toLowerCase() !== cand.referenceNumber.trim().toLowerCase()) {
          continue;
        }
      }

      // Guard 3: Conflicting account last 4 -> NOT a duplicate!
      if (accountLast4 && cand.accountLast4 && accountLast4.trim().length > 0 && cand.accountLast4.trim().length > 0) {
        if (accountLast4.trim().toLowerCase() !== cand.accountLast4.trim().toLowerCase()) {
          continue;
        }
      }

      return { isDuplicate: true, matchedSuggestionId: cand.suggestionId || undefined };
    }

    return { isDuplicate: false };
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
    sourceId?: string,
    counterParty?: string
  ): Promise<boolean> {
    const res = await this.findDuplicate(
      userId,
      transactionDate,
      amount,
      referenceNumber,
      accountLast4,
      rawText,
      sourceId,
      counterParty
    );
    return res.isDuplicate;
  }

  /**
   * Enriches an existing pending suggestion with missing details from a duplicate incoming transaction
   * (e.g. adding accountLast4 from bank SMS to an Amazon notification, or adding rich note/orderId from an Amazon notification to a bank SMS).
   */
  public async enrichPendingSuggestion(
    existingSuggestionId: string,
    updates: {
      accountLast4?: string;
      matchedAccountId?: string;
      note?: string;
      referenceNumber?: string;
      counterParty?: string;
    }
  ): Promise<void> {
    try {
      const existing = await this.db.suggestion.findUnique({
        where: { id: existingSuggestionId },
      });
      if (!existing || existing.status !== 'pending') return;

      const dataToUpdate: any = {};
      if (!existing.accountLast4 && updates.accountLast4) {
        dataToUpdate.accountLast4 = updates.accountLast4;
        if (updates.matchedAccountId) {
          dataToUpdate.walletAccountId = updates.matchedAccountId;
        }
      }
      if (!existing.referenceNumber && updates.referenceNumber) {
        dataToUpdate.referenceNumber = updates.referenceNumber;
      }
      if ((!existing.note || existing.note.trim() === '') && updates.note) {
        dataToUpdate.note = updates.note;
      }

      if (Object.keys(dataToUpdate).length > 0) {
        console.log(`Enriching pending suggestion ${existingSuggestionId} with:`, dataToUpdate);
        await this.db.suggestion.update({
          where: { id: existingSuggestionId },
          data: dataToUpdate,
        });
      }
    } catch (err: any) {
      console.warn('Failed to enrich pending suggestion:', err?.message || err);
    }
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
    await this.db.dedupEntry.create({
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
      const pendingOtpSuggestions = await this.db.suggestion.findMany({
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
          await this.db.suggestion.update({
            where: { id: otpSugg.id },
            data: {
              status: 'rejected',
              actionedAt: new Date(),
              note: ((otpSugg.note || '') + ' [Auto-rejected: Confirmed transaction SMS arrived within 15min]').trim(),
            },
          });
          await this.db.dedupEntry.deleteMany({
            where: { suggestionId: otpSugg.id },
          });
        }
        return { shouldDiscardIncoming: false, supersededOtpId: pendingOtpSuggestions[0].id };
      }

      return { shouldDiscardIncoming: false };
    } else {
      // Incoming is an OTP transaction message.
      // If a confirmed transaction already exists within 15 minutes, discard this OTP.
      const existingConfirmedTxn = await this.db.suggestion.findFirst({
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

