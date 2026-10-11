import { DedupEngine } from '../src/services/dedup-engine';

function assert(condition: boolean, message: string) {
  if (!condition) {
    console.error(`❌ FAILED: ${message}`);
    process.exit(1);
  }
}

class InMemoryDb {
  suggestions: any[] = [];
  dedupEntries: any[] = [];
  users: any[] = [];

  private matchesCondition(item: any, where: any): boolean {
    for (const [key, val] of Object.entries(where)) {
      if (key === 'OR' && Array.isArray(val)) {
        const anyMatch = val.some((cond) => this.matchesCondition(item, cond));
        if (!anyMatch) return false;
        continue;
      }
      if (key === 'NOT' && typeof val === 'object' && val !== null) {
        if (this.matchesCondition(item, val)) return false;
        continue;
      }

      const itemVal = item[key];
      if (val && typeof val === 'object' && !(val instanceof Date)) {
        if ('in' in val && Array.isArray((val as any).in)) {
          if (!(val as any).in.includes(itemVal)) return false;
        }
        if ('gte' in val) {
          const itemTime = itemVal instanceof Date ? itemVal.getTime() : new Date(itemVal).getTime();
          const gteTime = (val as any).gte instanceof Date ? (val as any).gte.getTime() : new Date((val as any).gte).getTime();
          if (itemTime < gteTime) return false;
        }
        if ('lte' in val) {
          const itemTime = itemVal instanceof Date ? itemVal.getTime() : new Date(itemVal).getTime();
          const lteTime = (val as any).lte instanceof Date ? (val as any).lte.getTime() : new Date((val as any).lte).getTime();
          if (itemTime > lteTime) return false;
        }
        if ('contains' in val) {
          const str = String(itemVal || '');
          const target = String((val as any).contains);
          if ((val as any).mode === 'insensitive') {
            if (!str.toLowerCase().includes(target.toLowerCase())) return false;
          } else {
            if (!str.includes(target)) return false;
          }
        }
      } else {
        if (val === null) {
          if (itemVal !== null && itemVal !== undefined) return false;
        } else if (itemVal !== val) {
          return false;
        }
      }
    }
    return true;
  }

  user = {
    create: async ({ data }: any) => {
      this.users.push(data);
      return data;
    },
    deleteMany: async ({ where }: any) => {
      this.users = this.users.filter((u) => !this.matchesCondition(u, where));
      return { count: 0 };
    },
  };

  suggestion = {
    create: async ({ data }: any) => {
      const row = { id: 'sugg_' + Math.random().toString(36).substring(2), ...data };
      this.suggestions.push(row);
      return row;
    },
    findFirst: async ({ where }: any) => {
      return this.suggestions.find((s) => this.matchesCondition(s, where)) || null;
    },
    findMany: async ({ where }: any) => {
      return this.suggestions.filter((s) => this.matchesCondition(s, where));
    },
    findUnique: async ({ where }: any) => {
      return this.suggestions.find((s) => s.id === where.id) || null;
    },
    update: async ({ where, data }: any) => {
      const idx = this.suggestions.findIndex((s) => s.id === where.id);
      if (idx !== -1) {
        this.suggestions[idx] = { ...this.suggestions[idx], ...data };
        return this.suggestions[idx];
      }
      return null;
    },
    deleteMany: async ({ where }: any) => {
      const before = this.suggestions.length;
      this.suggestions = this.suggestions.filter((s) => !this.matchesCondition(s, where));
      return { count: before - this.suggestions.length };
    },
  };

  dedupEntry = {
    create: async ({ data }: any) => {
      const row = { id: 'dedup_' + Math.random().toString(36).substring(2), ...data };
      this.dedupEntries.push(row);
      return row;
    },
    findFirst: async ({ where }: any) => {
      return this.dedupEntries.find((d) => this.matchesCondition(d, where)) || null;
    },
    findMany: async ({ where }: any) => {
      return this.dedupEntries.filter((d) => this.matchesCondition(d, where));
    },
    deleteMany: async ({ where }: any) => {
      const before = this.dedupEntries.length;
      this.dedupEntries = this.dedupEntries.filter((d) => !this.matchesCondition(d, where));
      return { count: before - this.dedupEntries.length };
    },
  };
}

async function runDedupTests() {
  console.log('🧪 Starting Deduplication & Same-Amount Transaction Tests...\n');

  const db = new InMemoryDb();
  const dedup = new DedupEngine(db);
  const testUserId = 'test_user_dedup_' + Date.now();

  try {
    // Create temporary test user
    await db.user.create({
      data: {
        id: testUserId,
        firebaseUid: 'fb_' + testUserId,
        email: `${testUserId}@example.com`,
      },
    });

    const baseDate = new Date('2026-10-11T10:00:00.000Z');

    // TEST 1: Two transactions with SAME AMOUNT (₹100) but DIFFERENT reference numbers within 2 minutes
    console.log('--- Test 1: Same Amount, Different Reference Numbers within 2 minutes ---');
    {
      const date1 = new Date(baseDate.getTime());
      const date2 = new Date(baseDate.getTime() + 2 * 60 * 1000); // 2 mins later

      // Record first transaction
      await db.suggestion.create({
        data: {
          userId: testUserId,
          source: 'sms',
          amount: 100,
          transactionType: 'expense',
          counterParty: 'Fruit Vendor',
          referenceNumber: '111111111111',
          rawText: 'Dear Customer, Rs 100 debited from a/c **1234 to Fruit Vendor Ref 111111111111',
          transactionDate: date1,
          status: 'pending',
        },
      });

      // Check second transaction with Ref 222222222222
      const dup = await dedup.findDuplicate(
        testUserId,
        date2,
        100,
        '222222222222',
        '1234',
        'Dear Customer, Rs 100 debited from a/c **1234 to Flower Shop Ref 222222222222',
        undefined,
        'Flower Shop'
      );

      assert(!dup.isDuplicate, 'Two same-value transactions with DIFFERENT reference numbers must NOT be duplicates!');
      console.log('  ✅ Passed: Distinct reference numbers correctly identified as separate transactions');
    }

    // TEST 2: Two transactions with SAME AMOUNT (₹50) but DIFFERENT merchants within 2 minutes
    console.log('\n--- Test 2: Same Amount, Different Merchants within 2 minutes ---');
    {
      const date1 = new Date(baseDate.getTime());
      const date2 = new Date(baseDate.getTime() + 2 * 60 * 1000);

      await db.suggestion.create({
        data: {
          userId: testUserId,
          source: 'sms',
          amount: 50,
          transactionType: 'expense',
          counterParty: 'Starbucks',
          rawText: 'Dear Customer, Rs 50 debited to Starbucks',
          transactionDate: date1,
          status: 'pending',
        },
      });

      const dup = await dedup.findDuplicate(
        testUserId,
        date2,
        50,
        undefined,
        '1234',
        'Dear Customer, Rs 50 debited to Chai Point',
        undefined,
        'Chai Point'
      );

      assert(!dup.isDuplicate, 'Two same-value transactions to DIFFERENT merchants must NOT be duplicates!');
      console.log('  ✅ Passed: Different merchants correctly identified as separate transactions');
    }

    // TEST 3: Same Amount, Same Day, 5.5 hours apart (Lunch vs Evening Tea)
    console.log('\n--- Test 3: Same Amount, 5.5 Hours Apart on Same Day ---');
    {
      const dateLunch = new Date('2026-10-11T06:30:00.000Z'); // 12:00 PM IST
      const dateTea = new Date('2026-10-11T12:00:00.000Z');   // 5:30 PM IST (5.5h later)

      await db.suggestion.create({
        data: {
          userId: testUserId,
          source: 'sms',
          amount: 80,
          transactionType: 'expense',
          counterParty: 'Lunch Cafe',
          rawText: 'Dear Customer, Rs 80.00 debited from a/c **1234 for Lunch Cafe',
          transactionDate: dateLunch,
          status: 'pending',
        },
      });

      const dup = await dedup.findDuplicate(
        testUserId,
        dateTea,
        80,
        undefined,
        '1234',
        'Dear Customer, Rs 80.00 debited from a/c **1234 for Evening Snacks',
        undefined,
        'Evening Snacks'
      );

      assert(!dup.isDuplicate, 'Transactions 5.5 hours apart must NOT be duplicates!');
      console.log('  ✅ Passed: 5.5-hour timezone offset no longer causes false duplicate match');
    }

    // TEST 4: Same Amount, Days Apart with Standard Bank Boilerplate Header
    console.log('\n--- Test 4: Same Amount on Different Days with Common Bank Header ---');
    {
      const dateMon = new Date('2026-10-05T10:00:00.000Z');
      const dateWed = new Date('2026-10-07T10:00:00.000Z');

      await db.suggestion.create({
        data: {
          userId: testUserId,
          source: 'sms',
          amount: 200,
          transactionType: 'expense',
          counterParty: 'Pharmacy',
          rawText: 'Dear Customer, INR 200.00 debited from HDFC Bank A/c **1234 on 05-OCT-26 to Pharmacy',
          transactionDate: dateMon,
          status: 'pending',
        },
      });

      // Next transaction shares the first 40 chars ("Dear Customer, INR 200.00 debited from H")
      const dup = await dedup.findDuplicate(
        testUserId,
        dateWed,
        200,
        undefined,
        '1234',
        'Dear Customer, INR 200.00 debited from HDFC Bank A/c **1234 on 07-OCT-26 to Grocery',
        undefined,
        'Grocery'
      );

      assert(!dup.isDuplicate, 'Transactions days apart sharing boilerplate prefix must NOT be duplicates!');
      console.log('  ✅ Passed: rawText prefix slice bug eliminated; separate days preserved');
    }

    // TEST 5: True Duplicate: Bank SMS + App Notification with SAME Reference Number
    console.log('\n--- Test 5: Bank SMS + App Notification with Matching Reference Number ---');
    {
      const notifDate = new Date('2026-10-11T15:00:00.000Z');
      const smsDate = new Date('2026-10-11T15:00:30.000Z'); // 30s later

      const notifSugg = await db.suggestion.create({
        data: {
          userId: testUserId,
          source: 'sms',
          amount: 1499,
          transactionType: 'expense',
          counterParty: 'Amazon',
          note: 'Order: Apple AirPods Case',
          referenceNumber: '402-1234567-1234567',
          rawText: 'Amazon.in: Order Placed: ₹1,499.00 for Apple AirPods Case. Order #402-1234567-1234567',
          transactionDate: notifDate,
          status: 'pending',
        },
      });

      const dup = await dedup.findDuplicate(
        testUserId,
        smsDate,
        1499,
        '402-1234567-1234567',
        '5678',
        'Alert: Rs 1,499.00 spent on Card ending 5678 at AMAZON INDIA for Order #402-1234567-1234567',
        undefined,
        'Amazon'
      );

      assert(dup.isDuplicate, 'Matching order ID MUST be detected as duplicate!');
      assert(dup.matchedSuggestionId === notifSugg.id, 'Should match existing notification suggestion ID');
      console.log('  ✅ Passed: Cross-source duplicate recognized via reference number');
    }

    // TEST 6: True Duplicate: Exact SourceId
    console.log('\n--- Test 6: Exact SourceId Re-read ---');
    {
      const date = new Date('2026-10-11T16:00:00.000Z');
      const srcId = 'sms_hdfc_1788220800000';

      await db.suggestion.create({
        data: {
          userId: testUserId,
          source: 'sms',
          amount: 350,
          transactionType: 'expense',
          sourceId: srcId,
          rawText: 'Rs 350 debited from A/c **1234',
          transactionDate: date,
          status: 'pending',
        },
      });

      const dup = await dedup.findDuplicate(
        testUserId,
        date,
        350,
        undefined,
        '1234',
        'Rs 350 debited from A/c **1234',
        srcId
      );

      assert(dup.isDuplicate, 'Matching sourceId MUST be detected as duplicate!');
      console.log('  ✅ Passed: Exact sourceId deduplicated');
    }

    // TEST 7: Recurring Identical FASTag Toll 24 Hours Apart
    console.log('\n--- Test 7: Recurring Identical FASTag Toll 24 Hours Apart ---');
    {
      const day1 = new Date('2026-10-10T08:00:00.000Z');
      const day2 = new Date('2026-10-11T08:00:00.000Z');
      const tollText = 'FASTag A/c debited by Rs. 45.00 for toll plaza A';

      await db.suggestion.create({
        data: {
          userId: testUserId,
          source: 'sms',
          amount: 45,
          transactionType: 'expense',
          counterParty: 'FASTag Toll',
          rawText: tollText,
          transactionDate: day1,
          status: 'pending',
        },
      });

      const dup = await dedup.findDuplicate(
        testUserId,
        day2,
        45,
        undefined,
        undefined,
        tollText,
        undefined,
        'FASTag Toll'
      );

      assert(!dup.isDuplicate, 'Recurring toll with identical text 24 hours apart must NOT be duplicate!');
      console.log('  ✅ Passed: Recurring identical text across days accepted');
    }

    // TEST 8: Two Bank SMS with Same Amount & Unknown Counterparty within 5 Minutes (Separate SMS events)
    console.log('\n--- Test 8: Two Bank SMS events with Same Amount and Distinct sourceId ---');
    {
      const sms1Date = new Date('2026-10-11T09:00:00.000Z');
      const sms2Date = new Date('2026-10-11T09:03:00.000Z'); // 3 mins later

      await db.suggestion.create({
        data: {
          userId: testUserId,
          source: 'sms',
          sourceId: 'sms_bank_1001',
          amount: 20,
          transactionType: 'expense',
          counterParty: 'VPA',
          rawText: 'Sent Rs.20.00 from Bank A/c to VPA',
          transactionDate: sms1Date,
          status: 'pending',
        },
      });

      const dup = await dedup.findDuplicate(
        testUserId,
        sms2Date,
        20,
        undefined,
        undefined,
        'Sent Rs.20.00 from Bank A/c to VPA',
        'sms_bank_1002',
        'VPA'
      );

      assert(!dup.isDuplicate, 'Two separate bank SMS events with distinct source IDs must NOT be merged!');
      console.log('  ✅ Passed: Same-source distinct SMS events are preserved');
    }

    // TEST 9: Cross-source Enrichment (Bank SMS enriches Amazon App push)
    console.log('\n--- Test 9: Suggestion Enrichment Across Sources ---');
    {
      const notif = await db.suggestion.create({
        data: {
          userId: testUserId,
          source: 'app_notification',
          amount: 999,
          counterParty: 'Amazon',
          note: 'Amazon Order #123',
          referenceNumber: '123-456',
          status: 'pending',
        },
      });

      await dedup.enrichPendingSuggestion(notif.id, {
        accountLast4: '4321',
        matchedAccountId: 'acc_uuid_4321',
      });

      const updated = await db.suggestion.findUnique({ where: { id: notif.id } });
      assert(updated.accountLast4 === '4321', 'Pending suggestion accountLast4 should be enriched');
      assert(updated.walletAccountId === 'acc_uuid_4321', 'Pending suggestion walletAccountId should be enriched');
      console.log('  ✅ Passed: Suggestion enrichment succeeded');
    }

    // TEST 10: Confirmed SMS Auto-supersedes Pending OTP Suggestion
    console.log('\n--- Test 10: Confirmed SMS Supersedes Pending OTP ---');
    {
      const now = new Date();
      const otpSugg = await db.suggestion.create({
        data: {
          userId: testUserId,
          amount: 500,
          accountLast4: '9999',
          transactionDate: now,
          status: 'pending',
          note: '[OTP Transaction] OTP 123456 for Rs 500',
          rawText: 'Your OTP is 123456 for txn of Rs 500 on card 9999',
        },
      });

      const pairResult = await dedup.handleOtpPairing(testUserId, 500, now, '9999', false);
      assert(!pairResult.shouldDiscardIncoming, 'Incoming confirmed SMS must not be discarded');
      assert(pairResult.supersededOtpId === otpSugg.id, 'Superseded OTP ID must match');

      const reloadedOtp = await db.suggestion.findUnique({ where: { id: otpSugg.id } });
      assert(reloadedOtp.status === 'rejected', 'Superseded OTP suggestion must be auto-rejected');
      console.log('  ✅ Passed: Confirmed SMS superseded OTP transaction correctly');
    }

    console.log('\n🎉 ALL 10 DEDUPLICATION & SAME-AMOUNT TESTS PASSED SUCCESSFULLY!\n');
  } finally {
    // Cleanup test data
    await db.dedupEntry.deleteMany({ where: { userId: testUserId } });
    await db.suggestion.deleteMany({ where: { userId: testUserId } });
    await db.user.deleteMany({ where: { id: testUserId } });
  }
}

runDedupTests().catch((err) => {
  console.error('Test error:', err);
  process.exit(1);
});
