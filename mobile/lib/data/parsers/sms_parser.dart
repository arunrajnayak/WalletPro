import 'package:flutter/foundation.dart';

class SmsParser {
  static final _amountRegex = RegExp(r'(?:Rs\.?|INR|₹)\s*([\d,]+\.?\d*)', caseSensitive: false);
  static final _accountRegex = RegExp(r'(?:A\/c|Acct|Card|a\/c|account|ending\s*in)\s*(?:no\.?)?\s*[*xX]*([0-9]{3,5})', caseSensitive: false);
  static final _typeRegex = RegExp(r'\b(debited|credited|spent|withdrawn|transferred|deposited|sent|received|used|using|charged|paid|payment|txn|transaction|order\s+placed|order\s+confirmed|placed|refund(?:ed|\s+processed|\s+initiated|\s+of)?|cashback(?:\s+received|\s+credited)?|added|recharge\s+successful|bill\s+payment)\b', caseSensitive: false);
  static final _upiRegex = RegExp(r'(?:UPI\s*(?:Ref|ref)(?:\s*(?:No|no)\.?)?|Ref(?:\s*(?:No|no)\.?)?|UTR)[\s:\.\-]*([0-9]{6,16})', caseSensitive: false);
  static final _amazonOrderRegex = RegExp(r'(?:order\s*(?:#|no\.?|id)?\s*|#\s*)([0-9]{3}-[0-9]{7}-[0-9]{7})', caseSensitive: false);
  static final _balanceRegex = RegExp(r'(?:Avl|Avail(?:able)?|Updated|Total)?\s*Bal(?:ance)?\s*[:\s]*(?:INR|Rs\.?)?\s*([\d,]+\.?\d*)', caseSensitive: false);
  static final _merchantRegex = RegExp(r'(?:to\s+vpa|to|at|from)\s+([A-Za-z0-9\s\&\*\-]+?)(?:\s+(?:for|on|via|with|using|UPI|Ref|avl|bal|date|limit)|[\.,]|$)', caseSensitive: false);
  static final _orderItemRegex = RegExp(r'(?:order\s+placed(?::|\s+for)?|order\s+of)\s*(?:Rs\.?|INR|₹)?\s*[\d,]+\.?\d*\s+(?:for|of)\s+([^.\n,]+)', caseSensitive: false);

  // Strict Anti-Spam / Promotional & Logistics filters
  static final _spamPromoRegex = RegExp(r'\b(deal|deals|discount|flat\s*(?:rs\.?|inr|₹)|win\b|chance\s+to\s+win|up\s+to\s*(?:rs\.?|inr|₹)|offer|offers|coupon|coupons|price\s+drop|save\s*(?:rs\.?|inr|₹)|cashback\s+on\b|quiz|jackpot|lightning\s+deal|scratch\s*card|tap\s+to\s+reveal|unlocked\s+a\s+scratch\s*card|spin\s+(?:to|&)\s+win)\b', caseSensitive: false);
  static final _cartWishlistRegex = RegExp(r'\b(items?\s+in\s+your\s+cart|complete\s+your\s+(?:order|purchase)|continue\s+shopping|wishlist|buy\s+again|recommended\s+for\s+you)\b', caseSensitive: false);
  static final _logisticsRegex = RegExp(r'\b(delivered\b|dispatched\b|shipped\b|out\s+for\s+delivery|arriving\s+(?:today|tomorrow|by)|track\s+your\s+package|handed\s+to\s+resident|delivery\s+attempted|package\s+arrived|rate\s+your|review\s+your|how\s+was|share\s+your\s+feedback)\b', caseSensitive: false);

  // Hardcoded start date: 1st September 2026 UTC
  static final DateTime hardcodedStartDate = DateTime.utc(2026, 9, 1);

  static Map<String, dynamic>? parse(String smsText, {DateTime? messageDate, String? senderHeader}) {
    try {
      final date = (messageDate ?? DateTime.now()).toUtc();

      // Ignore SMS received prior to 1st September 2026
      if (date.isBefore(hardcodedStartDate)) {
        return null;
      }

      // Filter out promotional marketing, cart reminders, and shipping/delivery alerts
      if (_spamPromoRegex.hasMatch(smsText) || _cartWishlistRegex.hasMatch(smsText) || _logisticsRegex.hasMatch(smsText)) {
        return null;
      }

      // Filter out non-transactional OTPs (login/verify), but allow transaction OTPs (txn of INR...)
      final isOtp = RegExp(r'\b(otp|one\s*time\s*password|verification\s*code|secret\s*code|pin)\b', caseSensitive: false).hasMatch(smsText);
      final isOtpWithTxn = isOtp && RegExp(r'\b(txn|transaction|purchase|payment|pay|charging)\b', caseSensitive: false).hasMatch(smsText);

      if (isOtp && !isOtpWithTxn && !RegExp(r'\b(debited|spent|credited)\b', caseSensitive: false).hasMatch(smsText)) {
        return null;
      }

      final isFastag = RegExp(r'\b(fastag|toll|parking|plaza)\b', caseSensitive: false).hasMatch(smsText);

      final amountMatch = _amountRegex.firstMatch(smsText);
      final typeMatch = _typeRegex.firstMatch(smsText);

      if (amountMatch == null || (typeMatch == null && !isFastag)) {
        return null; // Not a financial transaction
      }

      final rawAmountStr = amountMatch.group(1)?.replaceAll(',', '');
      final amount = double.tryParse(rawAmountStr ?? '') ?? 0.0;
      if (amount <= 0) return null;

      final matchedType = typeMatch?.group(1)?.toLowerCase() ?? '';
      final isCredit = RegExp(r'\b(credited|deposited|added|received|refunded|inward)\b', caseSensitive: false).hasMatch(matchedType) ||
          matchedType.startsWith('cashback') ||
          matchedType.startsWith('refund');
      final transactionType = isCredit ? 'income' : 'expense';

      final accountMatch = _accountRegex.firstMatch(smsText);
      String? accountLast4 = accountMatch?.group(1);
      if (accountLast4 == null && (isFastag || RegExp(r'\b[A-Z]{2}\s?[0-9]{1,2}\s?[A-Z]{1,3}\s?[0-9]{4}\b', caseSensitive: false).hasMatch(smsText))) {
        final vehicleMatch = RegExp(r'\b[A-Z]{2}\s?[0-9]{1,2}\s?[A-Z]{1,3}\s?([0-9]{4})\b', caseSensitive: false).firstMatch(smsText);
        accountLast4 = vehicleMatch?.group(1);
      }

      final upiMatch = _upiRegex.firstMatch(smsText);
      final amazonOrderMatch = _amazonOrderRegex.firstMatch(smsText);
      final referenceNumber = upiMatch?.group(1) ?? amazonOrderMatch?.group(1);

      final balanceMatch = _balanceRegex.firstMatch(smsText);
      final merchantMatch = _merchantRegex.firstMatch(smsText);

      final lowerText = smsText.toLowerCase();
      final isAmazonText = lowerText.contains('amazon') || (senderHeader != null && senderHeader.toLowerCase().contains('amazon'));
      String? note;

      String? counterParty = merchantMatch?.group(1)?.trim();

      // Amazon-specific merchant, note, and counterparty heuristics
      if (isAmazonText) {
        final orderItemMatch = _orderItemRegex.firstMatch(smsText);
        if (orderItemMatch != null) {
          final rawItem = orderItemMatch.group(1)?.trim() ?? '';
          final cleanItem = rawItem.replaceAll(RegExp(r'\s+(?:has\s+been\s+placed|is\s+confirmed|placed|confirmed)$', caseSensitive: false), '').trim();
          if (cleanItem.isNotEmpty) {
            note = 'Order: $cleanItem';
          }
        }

        if (lowerText.contains('order placed') || lowerText.contains('order confirmed') || lowerText.contains('your order of')) {
          counterParty = 'Amazon';
        } else if (lowerText.contains('insurance')) {
          counterParty = 'Amazon Pay Insurance';
          note = 'Insurance Payment';
        } else if (lowerText.contains('cashback')) {
          counterParty = 'Amazon Pay Cashback';
        } else if (lowerText.contains('refund')) {
          counterParty = 'Amazon Refund';
        } else if (lowerText.contains('bill payment')) {
          final billerMatch = RegExp(r'(?:for|to)\s+([A-Za-z0-9\s\-]+?)(?:\s+(?:bill|successful)|$)', caseSensitive: false).firstMatch(smsText);
          counterParty = billerMatch?.group(1)?.trim() ?? 'Amazon Pay Bill Payment';
          note = 'Bill Payment: $counterParty';
        } else if (lowerText.contains('recharge')) {
          final mobileMatch = RegExp(r'(?:for|mobile)\s*([0-9]{10})', caseSensitive: false).firstMatch(smsText);
          final target = mobileMatch?.group(1);
          counterParty = 'Amazon Pay Recharge';
          note = target != null ? 'Recharge: $target' : 'Mobile Recharge';
        }

        if (lowerText.contains('was paid on amazon') || lowerText.contains('using amazon pay balance') || lowerText.contains('at amazon.in')) {
          if (counterParty == null || counterParty.toLowerCase().contains('amazon') || RegExp(r'^(?:check|view|download|track|verify|click)\b', caseSensitive: false).hasMatch(counterParty)) {
            counterParty = lowerText.contains('insurance') ? 'Amazon Pay Insurance' : 'Amazon';
          }
          if (note == null && lowerText.contains('amazon pay balance')) {
            note = 'Amazon Pay Balance';
          }
        }
      }

      // Discard any counterParty that is an infinitive action verb phrase (e.g. "check order details", "click here", "view details")
      if (counterParty != null && RegExp(r'^(?:check|view|download|track|verify|click|know|see|pay|get|manage)\b', caseSensitive: false).hasMatch(counterParty)) {
        counterParty = isAmazonText ? (lowerText.contains('insurance') ? 'Amazon Pay Insurance' : 'Amazon') : null;
      }

      if (counterParty != null) {
        // Strip trailing .in or .com (e.g. "Amazon.in" -> "Amazon")
        counterParty = counterParty.replaceAll(RegExp(r'\.(?:in|com)$', caseSensitive: false), '').trim();
      }

      if (counterParty == null || counterParty.isEmpty || counterParty.toLowerCase() == 'vpa' || counterParty.toLowerCase() == 'amazon pay upi') {
        if (isFastag) {
          counterParty = 'FASTag Toll';
        } else if (isAmazonText) {
          counterParty = 'Amazon';
        } else if (RegExp(r'flipkart', caseSensitive: false).hasMatch(smsText)) {
          counterParty = 'Flipkart';
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

      String? transactionMode;
      if (isFastag) {
        transactionMode = 'fastag';
      } else if (lowerText.contains('amazon pay balance') || lowerText.contains('amazon pay wallet')) {
        transactionMode = 'wallet';
      } else if (lowerText.contains('gift card') || lowerText.contains('card')) {
        transactionMode = 'card';
      } else if (lowerText.contains('upi') || lowerText.contains('@')) {
        transactionMode = 'upi';
      }

      return {
        'amount': amount,
        'transactionType': transactionType,
        'accountLast4': accountLast4,
        'referenceNumber': referenceNumber,
        'counterParty': counterParty,
        'note': note,
        'balance': double.tryParse(balanceMatch?.group(1)?.replaceAll(',', '') ?? ''),
        'transactionDate': effectiveDate.toIso8601String(),
        'rawText': smsText,
        'isOtp': isOtpWithTxn,
        'transactionMode': transactionMode,
      };
    } catch (e) {
      debugPrint('SMS parsing error: $e');
      return null;
    }
  }
}
