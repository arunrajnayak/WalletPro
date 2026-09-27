import 'package:intl/intl.dart';

class CurrencyFormatter {
  static final NumberFormat _indianFormat = NumberFormat('#,##,##0.00', 'en_IN');
  static final NumberFormat _compactIndianFormat = NumberFormat('#,##,##0', 'en_IN');

  static String formatINR(num? amount, {bool compact = false}) {
    if (amount == null) return '₹0.00';
    final val = amount.toDouble();
    final isNegative = val < 0;
    final absVal = val.abs();

    if (compact) {
      if (absVal >= 10000000) {
        return '${isNegative ? '-' : ''}₹${(absVal / 10000000).toStringAsFixed(2)} Cr';
      } else if (absVal >= 100000) {
        return '${isNegative ? '-' : ''}₹${(absVal / 100000).toStringAsFixed(2)} L';
      }
    }

    final formatted = _indianFormat.format(absVal);
    return '${isNegative ? '-' : ''}₹$formatted';
  }
}
