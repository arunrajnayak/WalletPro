export interface ParsedTransaction {
  amount: number;
  transactionType: 'expense' | 'income';
  accountLast4?: string;
  counterParty?: string;
  referenceNumber?: string;
  balance?: number;
  transactionDate: Date;
  source: 'sms' | 'email';
  rawText: string;
  confidence: number;
  bank?: string;
  transactionMode?: 'upi' | 'neft' | 'imps' | 'card' | 'netbanking' | 'atm' | 'unknown';
}

export class SmsParser {
  /**
   * Identifies the sending bank from sender header or text
   */
  private identifyBank(senderHeader?: string, text?: string): string | undefined {
    const combined = `${senderHeader || ''} ${text || ''}`.toUpperCase();
    if (combined.includes('HDFC')) return 'HDFC Bank';
    if (combined.includes('ICICI')) return 'ICICI Bank';
    if (combined.includes('SBI') || combined.includes('STATE BANK')) return 'State Bank of India';
    if (combined.includes('AXIS')) return 'Axis Bank';
    if (combined.includes('KOTAK')) return 'Kotak Mahindra Bank';
    if (combined.includes('PNB') || combined.includes('PUNJAB NATIONAL')) return 'Punjab National Bank';
    if (combined.includes('BOB') || combined.includes('BARODA')) return 'Bank of Baroda';
    if (combined.includes('INDUS')) return 'IndusInd Bank';
    if (combined.includes('YES')) return 'Yes Bank';
    return undefined;
  }

  /**
   * Parses an SMS text to extract structured transaction details.
   */
  public parse(text: string, date: Date = new Date(), senderHeader?: string): ParsedTransaction | null {
    if (!text || typeof text !== 'string') return null;

    // Discard OTPs, verification codes, or promotional spam
    const isOtp = /\b(?:otp|one\s*time\s*password|verification\s*code|secret\s*code|pin)\b/i.test(text);
    if (isOtp && !/(?:debited|spent|credited)/i.test(text)) {
      return null;
    }

    // 1. Transaction Type (Debit vs Credit)
    const isCredit = /\b(credited|deposited|added|received|refunded|inward)\b/i.test(text);
    const isDebit = /\b(debited|spent|deducted|paid|withdrawn|used\s+for|sent)\b/i.test(text);

    if (!isCredit && !isDebit) {
      return null;
    }
    const transactionType: 'expense' | 'income' = isCredit ? 'income' : 'expense';

    // 2. Amount Extraction (supports INR, Rs, ₹ with commas and decimals)
    const amountRegex = /(?:INR|Rs\.?|₹|INR\.)\s*([0-9,]+(?:\.[0-9]{1,2})?)/i;
    const amountMatch = text.match(amountRegex);
    if (!amountMatch) return null;

    const rawAmountStr = amountMatch[1].replace(/,/g, '');
    const amount = parseFloat(rawAmountStr);
    if (isNaN(amount) || amount <= 0) return null;

    // 3. Account / Card Last 4 Digits
    let accountLast4: string | undefined;
    const accountMatch = text.match(/(?:a\/c|acct|card|account|card\s*ending)\s*(?:no\.?)?[\s:\.\-]*[*xX]*([0-9]{3,5})/i);
    if (accountMatch) {
      accountLast4 = accountMatch[1];
    }

    // 4. UPI Ref / Reference / UTR Number
    let referenceNumber: string | undefined;
    const refMatch = text.match(/(?:upi\s*(?:ref|reference)?(?:\s*no\.?)?|ref\s*no\.?|utr|rrn|txn\s*id)[\s:\.\-]*([0-9a-zA-Z]{6,16})/i);
    if (refMatch) {
      referenceNumber = refMatch[1];
    }

    // 5. Available Balance
    let balance: number | undefined;
    const balMatch = text.match(/(?:avl(?:\.|ail)?\s*bal|avail(?:\.|able)?\s*bal|total\s*avail\.bal|bal(?:\s*is)?)\s*[:\s]*(?:INR|Rs\.?|₹)?\s*([0-9,]+(?:\.[0-9]{1,2})?)/i);
    if (balMatch) {
      balance = parseFloat(balMatch[1].replace(/,/g, ''));
    }

    // 6. Transaction Mode
    let transactionMode: ParsedTransaction['transactionMode'] = 'unknown';
    const lower = text.toLowerCase();
    if (lower.includes('upi') || lower.includes('@')) transactionMode = 'upi';
    else if (lower.includes('card') || lower.includes('pos')) transactionMode = 'card';
    else if (lower.includes('neft')) transactionMode = 'neft';
    else if (lower.includes('imps')) transactionMode = 'imps';
    else if (lower.includes('atm') || lower.includes('cash withdrawal')) transactionMode = 'atm';
    else if (lower.includes('netbanking')) transactionMode = 'netbanking';

    // 7. CounterParty / Merchant extraction
    let counterParty: string | undefined;
    // Matches patterns like "to VPA xyz@bank", "at AMAZON INDIA", "to Swiggy", "Info: UPI/123/Swiggy"
    const merchantMatch =
      text.match(/(?:to\s+vpa|to|at|info:[\w\/]+?\/)\s+([A-Za-z0-9\s\.\&\*\-]+?)(?:\s+(?:on|via|UPI|Ref|avl|bal|using|date|limit|\.|\,)|$)/i);
    if (merchantMatch) {
      counterParty = merchantMatch[1].trim().replace(/^[\s\.\-\*]+|[\s\.\-\*]+$/g, '');
      if (counterParty.length > 50) counterParty = counterParty.substring(0, 50).trim();
    }

    const bank = this.identifyBank(senderHeader, text);

    return {
      amount,
      transactionType,
      accountLast4,
      counterParty,
      referenceNumber,
      balance,
      transactionDate: date,
      source: 'sms',
      rawText: text,
      confidence: 0.9,
      bank,
      transactionMode,
    };
  }
}
