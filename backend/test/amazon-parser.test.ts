import { SmsParser } from '../src/services/sms-parser';

function assert(condition: boolean, message: string) {
  if (!condition) {
    console.error(`❌ FAILED: ${message}`);
    process.exit(1);
  }
}

async function runTests() {
  console.log('🧪 Starting Amazon Notification & Anti-Spam Unit Tests...\n');
  const parser = new SmsParser();
  const testDate = new Date('2026-10-11T12:00:00Z');

  // --- POSITIVE TEST CASES ---
  console.log('--- Testing Positive Transactions ---');

  // 1. Amazon Pay UPI payment to merchant
  {
    const text = 'Amazon Pay: Paid ₹450 to Starbucks on Amazon Pay UPI';
    const res = parser.parse(text, testDate);
    assert(res !== null, 'Should parse Amazon Pay UPI payment');
    assert(res!.amount === 450, `Expected amount 450, got ${res?.amount}`);
    assert(res!.transactionType === 'expense', 'Expected expense');
    assert(res!.counterParty === 'Starbucks', `Expected Starbucks, got ${res?.counterParty}`);
    assert(res!.transactionMode === 'upi', 'Expected upi mode');
    console.log('  ✅ 1. Amazon Pay UPI to Starbucks passed');
  }

  // 2. Amazon Pay UPI sent to person with UPI Ref
  {
    const text = 'Amazon Pay: ₹500 sent to Ramesh using Amazon Pay UPI. Ref: 428719283749';
    const res = parser.parse(text, testDate);
    assert(res !== null, 'Should parse sent UPI');
    assert(res!.amount === 500, `Expected 500, got ${res?.amount}`);
    assert(res!.counterParty === 'Ramesh', `Expected Ramesh, got ${res?.counterParty}`);
    assert(res!.referenceNumber === '428719283749', `Expected ref 428719283749, got ${res?.referenceNumber}`);
    console.log('  ✅ 2. Amazon Pay UPI sent to Ramesh passed');
  }

  // 3. Amazon Pay UPI received money
  {
    const text = 'Amazon Pay: Received ₹200 from Rohan on Amazon Pay UPI. UPI Ref: 123456789012';
    const res = parser.parse(text, testDate);
    assert(res !== null, 'Should parse incoming UPI');
    assert(res!.amount === 200, `Expected 200, got ${res?.amount}`);
    assert(res!.transactionType === 'income', 'Expected income');
    assert(res!.counterParty === 'Rohan', `Expected Rohan, got ${res?.counterParty}`);
    assert(res!.referenceNumber === '123456789012', `Expected ref 123456789012, got ${res?.referenceNumber}`);
    console.log('  ✅ 3. Amazon Pay UPI received from Rohan passed');
  }

  // 4. Amazon Shopping Order Placed
  {
    const text = 'Amazon.in: Order Placed: ₹1,499.00 for Apple AirPods Case. Order #402-1234567-1234567';
    const res = parser.parse(text, testDate);
    assert(res !== null, 'Should parse Amazon shopping order');
    assert(res!.amount === 1499, `Expected 1499, got ${res?.amount}`);
    assert(res!.transactionType === 'expense', 'Expected expense');
    assert(res!.counterParty === 'Amazon', `Expected Amazon, got ${res?.counterParty}`);
    assert(res!.referenceNumber === '402-1234567-1234567', `Expected order ID, got ${res?.referenceNumber}`);
    assert(res!.note === 'Order: Apple AirPods Case', `Expected note, got ${res?.note}`);
    console.log('  ✅ 4. Amazon Shopping Order Placed with Order ID and Note passed');
  }

  // 5. Amazon order with alternate format
  {
    const text = 'Amazon: Your order of ₹899 for boAt Airdopes 141 has been placed';
    const res = parser.parse(text, testDate);
    assert(res !== null, 'Should parse order format 2');
    assert(res!.amount === 899, `Expected 899, got ${res?.amount}`);
    assert(res!.counterParty === 'Amazon', 'Expected Amazon');
    assert(res!.note === 'Order: boAt Airdopes 141', `Expected item note, got ${res?.note}`);
    console.log('  ✅ 5. Amazon Order of ₹899 for boAt Airdopes passed');
  }

  // 6. Amazon Pay Balance spent
  {
    const text = 'Amazon Pay: Paid ₹349 using Amazon Pay balance at Swiggy';
    const res = parser.parse(text, testDate);
    assert(res !== null, 'Should parse Amazon Pay balance');
    assert(res!.amount === 349, `Expected 349, got ${res?.amount}`);
    assert(res!.transactionMode === 'wallet', `Expected wallet mode, got ${res?.transactionMode}`);
    assert(res!.counterParty === 'Swiggy', `Expected Swiggy, got ${res?.counterParty}`);
    console.log('  ✅ 6. Amazon Pay Balance payment passed');
  }

  // 7. Amazon Pay Cashback
  {
    const text = 'Amazon Pay: Cashback received: ₹25 added to Amazon Pay balance';
    const res = parser.parse(text, testDate);
    assert(res !== null, 'Should parse cashback');
    assert(res!.amount === 25, `Expected 25, got ${res?.amount}`);
    assert(res!.transactionType === 'income', 'Expected income for cashback');
    assert(res!.counterParty === 'Amazon Pay Cashback', `Expected Amazon Pay Cashback, got ${res?.counterParty}`);
    console.log('  ✅ 7. Amazon Pay Cashback passed');
  }

  // 8. Amazon Refund
  {
    const text = 'Amazon Pay: Refund of ₹899 processed for order #402-9876543-9876543';
    const res = parser.parse(text, testDate);
    assert(res !== null, 'Should parse refund');
    assert(res!.amount === 899, `Expected 899, got ${res?.amount}`);
    assert(res!.transactionType === 'income', 'Expected income for refund');
    assert(res!.counterParty === 'Amazon Refund', 'Expected Amazon Refund');
    assert(res!.referenceNumber === '402-9876543-9876543', 'Expected order ID');
    console.log('  ✅ 8. Amazon Refund passed');
  }

  // 9. Bill Payment
  {
    const text = 'Amazon Pay: Bill payment successful: ₹750 paid for BESCOM';
    const res = parser.parse(text, testDate);
    assert(res !== null, 'Should parse bill payment');
    assert(res!.amount === 750, `Expected 750, got ${res?.amount}`);
    assert(res!.counterParty === 'BESCOM', `Expected BESCOM, got ${res?.counterParty}`);
    assert(res!.note === 'Bill Payment: BESCOM', `Expected note, got ${res?.note}`);
    console.log('  ✅ 9. Amazon Pay Bill Payment passed');
  }

  // 10. Mobile Recharge
  {
    const text = 'Amazon Pay: Recharge successful: ₹299 paid for mobile 9876543210';
    const res = parser.parse(text, testDate);
    assert(res !== null, 'Should parse recharge');
    assert(res!.amount === 299, `Expected 299, got ${res?.amount}`);
    assert(res!.counterParty === 'Amazon Pay Recharge', 'Expected Recharge counterparty');
    assert(res!.note === 'Recharge: 9876543210', `Expected note, got ${res?.note}`);
    console.log('  ✅ 10. Amazon Pay Mobile Recharge passed');
  }

  // 11. Amazon Pay ICICI Card
  {
    const text = '₹2,500 spent on Amazon Pay ICICI Bank Credit Card ending in 4321 at Croma on 11-Oct-26';
    const res = parser.parse(text, testDate);
    assert(res !== null, 'Should parse ICICI Amazon Card');
    assert(res!.amount === 2500, `Expected 2500, got ${res?.amount}`);
    assert(res!.accountLast4 === '4321', `Expected last4 4321, got ${res?.accountLast4}`);
    assert(res!.bank === 'ICICI Bank', `Expected ICICI Bank, got ${res?.bank}`);
    assert(res!.counterParty === 'Croma', `Expected Croma, got ${res?.counterParty}`);
    console.log('  ✅ 11. Amazon Pay ICICI Credit Card payment passed');
  }

  // --- NEGATIVE / ANTI-SPAM TEST CASES ---
  console.log('\n--- Testing Negative Anti-Spam & Delivery Filters ---');

  const negativeCases = [
    { name: 'Deal of the Day', text: 'Amazon.in: Deal of the day! Flat ₹500 off on smartwatches' },
    { name: 'Win Cashback Offer', text: 'Amazon Pay: Win up to ₹100 cashback! Pay electricity bill today' },
    { name: 'Price Drop Alert', text: 'Amazon.in: Price drop! Sony WH-1000XM4 is now ₹19,990 (was ₹24,990)' },
    { name: 'Cart Reminder', text: 'Amazon.in: Complete your purchase! Pay ₹1,499 now for items in your cart' },
    { name: 'Coupon Promo', text: 'Amazon.in: Save ₹200 with coupon on your next fashion order' },
    { name: 'Daily Quiz', text: 'Amazon Pay: Daily quiz: Answer 5 questions and win ₹5,000' },
    { name: 'Delivered Update', text: 'Amazon.in: Your order of ₹1,499 has been delivered' },
    { name: 'Out for Delivery', text: 'Amazon.in: Out for delivery: Your package will arrive today by 8 PM' },
    { name: 'Dispatched Update', text: 'Amazon.in: Shipped: Order #402-1234567-1234567 has been dispatched' },
    { name: 'Product Review Request', text: 'Amazon.in: Rate your recent purchase: How was the Apple AirPods Case?' },
  ];

  for (const tc of negativeCases) {
    const res = parser.parse(tc.text, testDate);
    assert(res === null, `Spam/Logistics alert "${tc.name}" must NOT be parsed as transaction! Got: ${JSON.stringify(res)}`);
    console.log(`  🛡️ Blocked spam/delivery: ${tc.name}`);
  }

  console.log('\n🎉 ALL 21 AMAZON NOTIFICATION & ANTI-SPAM TESTS PASSED SUCCESSFULLY!\n');
}

runTests().catch((err) => {
  console.error('Test execution error:', err);
  process.exit(1);
});
