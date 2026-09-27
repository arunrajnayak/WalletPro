import 'package:intl/intl.dart';

class DateFormatter {
  static String formatRelative(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);
    
    if (difference.inDays == 0) return 'Today';
    if (difference.inDays == 1) return 'Yesterday';
    return '${difference.inDays} days ago';
  }

  static String formatIndian(DateTime date) {
    return DateFormat('dd-MMM-yyyy').format(date);
  }

  static String formatFull(DateTime date) {
    return DateFormat('dd-MMM-yyyy, hh:mm a').format(date);
  }
}
