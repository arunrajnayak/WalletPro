import 'package:intl/intl.dart';

class CurrencyFormatter {
  static final NumberFormat _indianRupeeFormat = NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: 2,
  );

  static String formatINR(double amount) {
    return _indianRupeeFormat.format(amount);
  }
}
