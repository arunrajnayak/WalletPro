import 'package:flutter/foundation.dart';

class SmsParser {
  static final _amountRegex = RegExp(r'(?:Rs\.?|INR|₹)\s*([\d,]+\.?\d*)', caseSensitive: false);
  static final _accountRegex = RegExp(r'(?:A\/c|Acct|Card|a\/c|account)\s*(?:no\.?)?\s*[*xX]*([0-9]{3,5})', caseSensitive: false);
  static final _typeRegex = RegExp(r'\b(debited|credited|spent|withdrawn|transferred|deposited|sent|received|used|using|charged|paid|payment|txn|transaction)\b', caseSensitive: false);
  static final _upiRegex = RegExp(r'(?:UPI\s*(?:Ref|ref)(?:\s*(?:No|no)\.?)?|Ref\s*(?:No|no)\.?|UTR)[\s:\.\-]*([0-9]{6,16})', caseSensitive: false);
  static final _balanceRegex = RegExp(r'(?:Avl|Avail(?:able)?|Updated|Total)?\s*Bal(?:ance)?\s*[:\s]*(?:INR|Rs\.?)?\s*([\d,]+\.?\d*)', caseSensitive: false);
  static final _merchantRegex = RegExp(r'(?:to\s+vpa|to|at)\s+([A-Za-z0-9\s\.\&\*\-]+?)(?:\s+(?:for|on|via|UPI|Ref|avl|bal|using|date|\.|\,)|$)', caseSensitive: false);

  // Hardcoded start date: 1st September 2026 UTC
  static final DateTime hardcodedStartDate = DateTime.utc(2026, 9, 1);

  static Map<String, dynamic>? parse(String smsText, {DateTime? messageDate}) {
    try {
      final date = (messageDate ?? DateTime.now()).toUtc();

      // Ignore SMS received prior to 1st September 2026
      if (date.isBefore(hardcodedStartDate)) {
        return null;
      }

      // Filter out non-transactional OTPs (login/verify), but allow transaction OTPs (txn of INR...)
      final isOtp = RegExp(r'\b(otp|one\s*time\s*password|verification\s*code|secret\s*code|pin)\b', caseSensitive: false).hasMatch(smsText);
      final isOtpWithTxn = isOtp && RegExp(r'\b(txn|transaction|purchase|payment|pay|charging)\b', caseSensitive: false).hasMatch(smsText);

      if (isOtp && !isOtpWithTxn && !RegExp(r'\b(debited|spent|credited)\b', caseSensitive: false).hasMatch(smsText)) {
        return null;
      }

      final amountMatch = _amountRegex.firstMatch(smsText);
      final typeMatch = _typeRegex.firstMatch(smsText);

      if (amountMatch == null || typeMatch == null) {
        return null; // Not a financial transaction
      }

      final rawAmountStr = amountMatch.group(1)?.replaceAll(',', '');
      final amount = double.tryParse(rawAmountStr ?? '') ?? 0.0;
      if (amount <= 0) return null;

      final isCredit = RegExp(r'\b(credited|deposited|added|received)\b', caseSensitive: false).hasMatch(typeMatch.group(1)!);
      final transactionType = isCredit ? 'income' : 'expense';

      final accountMatch = _accountRegex.firstMatch(smsText);
      final upiMatch = _upiRegex.firstMatch(smsText);
      final balanceMatch = _balanceRegex.firstMatch(smsText);
      final merchantMatch = _merchantRegex.firstMatch(smsText);

      String? counterParty = merchantMatch?.group(1)?.trim();
      if (counterParty == null || counterParty.isEmpty || counterParty.toLowerCase() == 'vpa') {
        if (RegExp(r'flipkart', caseSensitive: false).hasMatch(smsText)) {
          counterParty = 'Flipkart';
        } else if (RegExp(r'amazon', caseSensitive: false).hasMatch(smsText)) {
          counterParty = 'Amazon';
        } else if (RegExp(r'swiggy', caseSensitive: false).hasMatch(smsText)) {
          counterParty = 'Swiggy';
        } else if (RegExp(r'zomato', caseSensitive: false).hasMatch(smsText)) {
          counterParty = 'Zomato';
        } else if (RegExp(r'uber', caseSensitive: false).hasMatch(smsText)) {
          counterParty = 'Uber';
        } else if (RegExp(r'ola', caseSensitive: false).hasMatch(smsText)) {
          counterParty = 'Ola';
        } else if (RegExp(r'blinkit', caseSensitive: false).hasMatch(smsText)) {
          counterParty = 'Blinkit';
        } else if (RegExp(r'zepto', caseSensitive: false).hasMatch(smsText)) {
          counterParty = 'Zepto';
        } else if (RegExp(r'myntra', caseSensitive: false).hasMatch(smsText)) {
          counterParty = 'Myntra';
        }
      }

      // Date extraction from message text if present (e.g. "on 03-10-26 21:48:10")
      DateTime effectiveDate = date;
      final dateMatch = RegExp(r'\bon\s+([0-3]?[0-9])[-/]([0-1]?[0-9])[-/](20\d{2}|\d{2})\s+([0-2]?[0-9]:[0-5][0-9](?::[0-5][0-9])?)', caseSensitive: false).firstMatch(smsText);
      if (dateMatch != null) {
        final day = int.tryParse(dateMatch.group(1) ?? '') ?? 1;
        final month = int.tryParse(dateMatch.group(2) ?? '') ?? 1;
        var year = int.tryParse(dateMatch.group(3) ?? '') ?? 2026;
        if (year < 100) year += 2000;
        final timeParts = (dateMatch.group(4) ?? '').split(':');
        final hours = int.tryParse(timeParts.isNotEmpty ? timeParts[0] : '') ?? 0;
        final minutes = int.tryParse(timeParts.length > 1 ? timeParts[1] : '') ?? 0;
        final seconds = int.tryParse(timeParts.length > 2 ? timeParts[2] : '') ?? 0;

        final extractedUtc = DateTime.utc(year, month, day, hours, minutes, seconds).subtract(const Duration(minutes: 330)); // IST to UTC
        if (extractedUtc.isAfter(hardcodedStartDate)) {
          effectiveDate = extractedUtc;
        }
      }

      return {
        'amount': amount,
        'transactionType': transactionType,
        'accountLast4': accountMatch?.group(1),
        'referenceNumber': upiMatch?.group(1),
        'counterParty': counterParty,
        'balance': double.tryParse(balanceMatch?.group(1)?.replaceAll(',', '') ?? ''),
        'transactionDate': effectiveDate.toIso8601String(),
        'rawText': smsText,
        'isOtp': isOtpWithTxn,
      };
    } catch (e) {
      debugPrint('SMS parsing error: $e');
      return null;
    }
  }
}
