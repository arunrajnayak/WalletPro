import 'package:flutter/services.dart';

class NotificationListenerService {
  static const MethodChannel _channel = MethodChannel('com.walletpro/notifications');

  static Future<void> startListening() async {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onNotificationReceived') {
        // Handle notification
      }
    });
  }
}
