export interface ParsedTransaction {
  amount: number;
  transactionType: 'expense' | 'income';
  accountLast4?: string;
  counterParty?: string;
  referenceNumber?: string;
  balance?: number;
  transactionDate: Date;
  source: 'sms';
  rawText: string;
  confidence: number;
  bank?: string;
  transactionMode?: 'upi' | 'neft' | 'imps' | 'card' | 'netbanking' | 'atm' | 'fastag' | 'unknown';
  isOtp?: boolean;
}

export class SmsParser {
  /**
   * Identifies the sending bank from sender header or text
   */
  private identifyBank(senderHeader?: string, text?: string): string | undefined {
    const combined = `${senderHeader || ''} ${text || ''}`.toUpperCase();
    if (combined.includes('FASTAG')) {
      if (combined.includes('ICICI')) return 'ICICI Bank';
      if (combined.includes('HDFC')) return 'HDFC Bank';
      if (combined.includes('SBI') || combined.includes('STATE BANK')) return 'State Bank of India';
      if (combined.includes('PAYTM')) return 'Paytm';
      if (combined.includes('AXIS')) return 'Axis Bank';
      if (combined.includes('IDFC')) return 'IDFC First Bank';
      if (combined.includes('KOTAK')) return 'Kotak Mahindra Bank';
      return 'FASTag';
    }
    if (combined.includes('HDFC')) return 'HDFC Bank';
    if (combined.includes('ICICI')) return 'ICICI Bank';
    if (combined.includes('SBI') || combined.includes('STATE BANK')) return 'State Bank of India';
    if (combined.includes('AXIS')) return 'Axis Bank';
    if (combined.includes('KOTAK')) return 'Kotak Mahindra Bank';
    if (combined.includes('PNB') || combined.includes('PUNJAB NATIONAL')) return 'Punjab National Bank';
    if (combined.includes('BOB') || combined.includes('BARODA')) return 'Bank of Baroda';
    if (combined.includes('INDUS')) return 'IndusInd Bank';
    if (combined.includes('YES')) return 'Yes Bank';
    if (combined.includes('FLIPKART')) return 'Flipkart';
    if (combined.includes('AMAZON')) return 'Amazon Pay';
    return undefined;
  }

  /**
   * Parses an SMS text to extract structured transaction details.
   */
  public parse(text: string, date: Date = new Date(), senderHeader?: string): ParsedTransaction | null {
    if (!text || typeof text !== 'string') return null;

    // Discard OTPs, verification codes, or promotional spam EXCEPT when the OTP is for a transaction
    const isOtp = /\b(?:otp|one\s*time\s*password|verification\s*code|secret\s*code|pin)\b/i.test(text);
    const isOtpWithTxn = isOtp && /\b(?:txn|transaction|purchase|payment|pay|charging)\b/i.test(text);

    if (isOtp && !isOtpWithTxn && !/(?:debited|spent|credited)/i.test(text)) {
      return null;
    }

    const isFastag = /\b(?:fastag|toll|parking|plaza)\b/i.test(text);

    // 1. Transaction Type (Debit vs Credit)
    const isCredit = /\b(credited|deposited|added|received|refunded|inward)\b/i.test(text);
    const isDebit =
      /\b(debited|spent|deducted|paid|payment(?:\s+of)?|withdrawn|used(?:\s+for)?|using|sent|charged|txn\s+of|transaction\s+of)\b/i.test(text) ||
      isOtpWithTxn ||
      isFastag;

    if (!isCredit && !isDebit) {
      return null;
    }
    const transactionType: 'expense' | 'income' = isCredit ? 'income' : 'expense';

    // 2. Amount Extraction (supports INR, Rs, ₹ with commas and decimals)
    const amountRegex = /(?:INR|Rs\.?|₹|INR\.)\s*([0-9,]+(?:\.[0-9]+)?)/i;
    const amountMatch = text.match(amountRegex);
    if (!amountMatch) return null;

    const rawAmountStr = amountMatch[1].replace(/,/g, '');
    const amount = parseFloat(rawAmountStr);
    if (isNaN(amount) || amount <= 0) return null;

    // 3. Account / Card Last 4 Digits & FASTag Vehicle Number
    let accountLast4: string | undefined;
    const accountMatch = text.match(/(?:a\/c|acct|card|account|card\s*ending)\s*(?:no\.?)?[\s:\.\-]*[*xX]*([0-9]{3,5})/i);
    if (accountMatch) {
      accountLast4 = accountMatch[1];
    } else if (isFastag || /\b[A-Z]{2}\s?[0-9]{1,2}\s?[A-Z]{1,3}\s?[0-9]{4}\b/i.test(text)) {
      // Indian vehicle registration number (e.g. "KA20ME4025", "MH 12 AB 1234")
      const vehicleMatch = text.match(/\b[A-Z]{2}\s?[0-9]{1,2}\s?[A-Z]{1,3}\s?([0-9]{4})\b/i);
      if (vehicleMatch) {
        accountLast4 = vehicleMatch[1];
      }
    }

    // 4. UPI Ref / Reference / UTR Number
    let referenceNumber: string | undefined;
    const refMatch = text.match(/(?:upi\s*(?:ref|reference)?(?:\s*no\.?)?|ref\s*no\.?|utr|rrn|txn\s*id)[\s:\.\-]*([0-9a-zA-Z]{6,16})/i);
    if (refMatch) {
      referenceNumber = refMatch[1];
    }

    // 5. Available Balance
    let balance: number | undefined;
    const balMatch = text.match(/(?:avl(?:\.|ail)?\s*bal|avail(?:\.|able)?\s*bal|total\s*avail\.bal|updated\s*bal(?:ance)?|bal(?:\s*is)?)\s*[:\s]*(?:INR|Rs\.?|₹)?\s*([0-9,]+(?:\.[0-9]+)?)/i);
    if (balMatch) {
      balance = parseFloat(balMatch[1].replace(/,/g, ''));
    }

    // 6. Transaction Mode
    let transactionMode: ParsedTransaction['transactionMode'] = 'unknown';
    const lower = text.toLowerCase();
    if (isFastag) transactionMode = 'fastag';
    else if (lower.includes('upi') || lower.includes('@')) transactionMode = 'upi';
    else if (lower.includes('gift card')) transactionMode = 'card';
    else if (lower.includes('card') || lower.includes('pos')) transactionMode = 'card';
    else if (lower.includes('neft')) transactionMode = 'neft';
    else if (lower.includes('imps')) transactionMode = 'imps';
    else if (lower.includes('atm') || lower.includes('cash withdrawal')) transactionMode = 'atm';
    else if (lower.includes('netbanking')) transactionMode = 'netbanking';

    // 7. CounterParty / Merchant extraction
    let counterParty: string | undefined;
    // Matches patterns like "to VPA xyz@bank", "at AMAZON INDIA", "to Swiggy.", "paid at Orion Uptown Mall for KA20ME4025"
    const merchantMatch =
      text.match(/(?:to\s+vpa|to|at|info:[\w\/]+?\/)\s+([A-Za-z0-9\s\&\*\-]+?)(?:\s+(?:for|on|via|with|using|UPI|Ref|avl|bal|date|limit)|[\.,]|$)/i);
    if (merchantMatch) {
      counterParty = merchantMatch[1].trim().replace(/^[\s\.\-\*]+|[\s\.\-\*]+$/g, '');
      if (counterParty.length > 50) counterParty = counterParty.substring(0, 50).trim();
    }

    if (!counterParty || counterParty.toLowerCase() === 'vpa') {
      if (isFastag) counterParty = 'FASTag Toll';
      else if (/flipkart/i.test(text)) counterParty = 'Flipkart';
      else if (/amazon/i.test(text)) counterParty = 'Amazon';
      else if (/swiggy/i.test(text)) counterParty = 'Swiggy';
      else if (/zomato/i.test(text)) counterParty = 'Zomato';
      else if (/uber/i.test(text)) counterParty = 'Uber';
      else if (/ola/i.test(text)) counterParty = 'Ola';
      else if (/blinkit/i.test(text)) counterParty = 'Blinkit';
      else if (/zepto/i.test(text)) counterParty = 'Zepto';
      else if (/myntra/i.test(text)) counterParty = 'Myntra';
    }

    const bank = this.identifyBank(senderHeader, text);

    // 8. Date extraction from text if present (e.g. "on 03-10-26 21:48:10")
    let parsedDate = date;
    const dateMatch = text.match(/\bon\s+([0-3]?[0-9])[-/]([0-1]?[0-9])[-/](20\d{2}|\d{2})\s+([0-2]?[0-9]:[0-5][0-9](?::[0-5][0-9])?)/i);
    if (dateMatch) {
      const day = parseInt(dateMatch[1], 10);
      const month = parseInt(dateMatch[2], 10) - 1;
      let year = parseInt(dateMatch[3], 10);
      if (year < 100) year += 2000;
      const timeParts = dateMatch[4].split(':');
      const hours = parseInt(timeParts[0], 10);
      const minutes = parseInt(timeParts[1], 10);
      const seconds = timeParts[2] ? parseInt(timeParts[2], 10) : 0;

      const extracted = new Date(Date.UTC(year, month, day, hours, minutes, seconds));
      // Convert IST (UTC+5:30) to UTC
      const istToUtc = new Date(extracted.getTime() - 330 * 60000);
      if (!isNaN(istToUtc.getTime())) {
        parsedDate = istToUtc;
      }
    }

    return {
      amount,
      transactionType,
      accountLast4,
      counterParty,
      referenceNumber,
      balance,
      transactionDate: parsedDate,
      source: 'sms',
      rawText: text,
      confidence: isOtpWithTxn ? 0.8 : 0.9,
      bank,
      transactionMode,
      isOtp: isOtpWithTxn,
    };
  }
}
