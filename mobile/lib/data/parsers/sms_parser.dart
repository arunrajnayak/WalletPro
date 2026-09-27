import 'package:flutter/foundation.dart';

class SmsParser {
  static final _amountRegex = RegExp(r'(?:Rs\.?|INR|₹)\s*([\d,]+\.?\d*)', caseSensitive: false);
  static final _accountRegex = RegExp(r'(?:A\/c|Acct|Card|a\/c)\s*(?:no\.?)?\s*[xX*]*([0-9]{3,5})', caseSensitive: false);
  static final _typeRegex = RegExp(r'\b(debited|credited|spent|withdrawn|transferred|deposited|sent|received)\b', caseSensitive: false);
  static final _upiRegex = RegExp(r'(?:UPI\s*(?:Ref|ref)(?:\s*(?:No|no)\.?)?|Ref\s*(?:No|no)\.?)\s*[:\s]*([0-9]{12})', caseSensitive: false);
  static final _balanceRegex = RegExp(r'(?:Avl|Avail(?:able)?)?\s*Bal(?:ance)?\s*[:\s]*(?:INR|Rs\.?)?\s*([\d,]+\.?\d*)', caseSensitive: false);

  static Map<String, dynamic> parse(String smsText) {
    try {
      final amountMatch = _amountRegex.firstMatch(smsText);
      final accountMatch = _accountRegex.firstMatch(smsText);
      final typeMatch = _typeRegex.firstMatch(smsText);
      final upiMatch = _upiRegex.firstMatch(smsText);
      final balanceMatch = _balanceRegex.firstMatch(smsText);

      return {
        'amount': amountMatch?.group(1),
        'accountLast4': accountMatch?.group(1),
        'transactionType': typeMatch?.group(1),
        'referenceNumber': upiMatch?.group(1),
        'balance': balanceMatch?.group(1),
      };
    } catch (e) {
      debugPrint('SMS parsing error: $e');
      return {};
    }
  }
}
