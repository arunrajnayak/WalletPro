import 'package:flutter/foundation.dart';

class SmsParser {
  static final _amountRegex = RegExp(r'(?:Rs\.?|INR|₹)\s*([\d,]+\.?\d*)', caseSensitive: false);
  static final _accountRegex = RegExp(r'(?:A\/c|Acct|Card|a\/c|account)\s*(?:no\.?)?\s*[*xX]*([0-9]{3,5})', caseSensitive: false);
  static final _typeRegex = RegExp(r'\b(debited|credited|spent|withdrawn|transferred|deposited|sent|received)\b', caseSensitive: false);
  static final _upiRegex = RegExp(r'(?:UPI\s*(?:Ref|ref)(?:\s*(?:No|no)\.?)?|Ref\s*(?:No|no)\.?|UTR)[\s:\.\-]*([0-9]{6,16})', caseSensitive: false);
  static final _balanceRegex = RegExp(r'(?:Avl|Avail(?:able)?)?\s*Bal(?:ance)?\s*[:\s]*(?:INR|Rs\.?)?\s*([\d,]+\.?\d*)', caseSensitive: false);
  static final _merchantRegex = RegExp(r'(?:to\s+vpa|to|at)\s+([A-Za-z0-9\s\.\&\*\-]+?)(?:\s+(?:on|via|UPI|Ref|avl|bal|using|date|\.|\,)|$)', caseSensitive: false);

  // Hardcoded start date: 1st September 2026 UTC
  static final DateTime hardcodedStartDate = DateTime.utc(2026, 9, 1);

  static Map<String, dynamic>? parse(String smsText, {DateTime? messageDate}) {
    try {
      final date = (messageDate ?? DateTime.now()).toUtc();

      // Ignore SMS received prior to 1st September 2026
      if (date.isBefore(hardcodedStartDate)) {
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

      return {
        'amount': amount,
        'transactionType': transactionType,
        'accountLast4': accountMatch?.group(1),
        'referenceNumber': upiMatch?.group(1),
        'counterParty': merchantMatch?.group(1)?.trim(),
        'balance': double.tryParse(balanceMatch?.group(1)?.replaceAll(',', '') ?? ''),
        'transactionDate': date.toIso8601String(),
        'rawText': smsText,
      };
    } catch (e) {
      debugPrint('SMS parsing error: $e');
      return null;
    }
  }
}
