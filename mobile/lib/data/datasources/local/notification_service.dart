import 'package:flutter/services.dart';

class NotificationService {
  static const MethodChannel _channel = MethodChannel('com.walletpro/notifications');
  static void Function()? onNewTransaction;

  /// Initialize notification channel and reminder scheduler
  static Future<void> init({void Function()? onTransactionDetected}) async {
    onNewTransaction = onTransactionDetected;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onNewTransactionReceived') {
        onNewTransaction?.call();
      }
    });

    try {
      await _channel.invokeMethod('requestPostNotificationPermission');
      await _channel.invokeMethod('scheduleReviewReminder');
    } catch (_) {}
  }

  /// Inform native layer of current pending count so 4-hour review reminder stays accurate
  static Future<void> updatePendingCount(int count) async {
    try {
      await _channel.invokeMethod('updatePendingCount', {'count': count});
    } catch (_) {}
  }

  /// Check whether user has granted Notification Access for listening to UPI / bank push alerts
  static Future<bool> isNotificationListenerEnabled() async {
    try {
      final res = await _channel.invokeMethod<bool>('isNotificationListenerEnabled');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Open Android Special App Access settings for Notification Access
  static Future<bool> openNotificationListenerSettings() async {
    try {
      final res = await _channel.invokeMethod<bool>('openNotificationListenerSettings');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Check if the app was launched by tapping a pending review notification
  static Future<String?> getInitialRoute() async {
    try {
      final route = await _channel.invokeMethod<String?>('getInitialRoute');
      return route;
    } catch (_) {
      return null;
    }
  }
}
