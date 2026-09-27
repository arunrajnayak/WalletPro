import 'package:flutter/services.dart';
import '../parsers/sms_parser.dart';
import '../remote/api_client.dart';

class SmsReaderService {
  static const MethodChannel _channel = MethodChannel('com.walletpro/sms');

  /// Check if READ_SMS permission is granted
  Future<bool> hasPermission() async {
    try {
      final res = await _channel.invokeMethod<bool>('hasSmsPermission');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Request READ_SMS & RECEIVE_SMS permissions
  Future<bool> requestPermission() async {
    try {
      final res = await _channel.invokeMethod<bool>('requestSmsPermission');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Read raw SMS messages from Android inbox
  Future<List<Map<String, dynamic>>> readInbox({DateTime? sinceDate, int limit = 300}) async {
    try {
      final millis = sinceDate?.millisecondsSinceEpoch ?? 0;
      final res = await _channel.invokeListMethod<dynamic>('readInbox', {
        'sinceMillis': millis,
        'limit': limit,
      });

      if (res == null) return [];
      return res.map((item) => Map<String, dynamic>.from(item as Map)).toList();
    } catch (e) {
      return [];
    }
  }

  /// High-level function: scan inbox, parse bank transactions, and send them to backend
  Future<Map<String, int>> scanAndSyncInbox({
    DateTime? sinceDate,
    required ApiClient apiClient,
    void Function(int current, int total)? onProgress,
  }) async {
    final granted = await hasPermission();
    if (!granted) {
      final requested = await requestPermission();
      if (!requested) {
        throw Exception('SMS permission not granted');
      }
    }

    final rawMessages = await readInbox(sinceDate: sinceDate, limit: 500);
    int detected = 0;
    int created = 0;

    for (int i = 0; i < rawMessages.length; i++) {
      final msg = rawMessages[i];
      final body = msg['body']?.toString() ?? '';
      final dateMillis = msg['date'] as int? ?? 0;
      final msgDate = DateTime.fromMillisecondsSinceEpoch(dateMillis);

      if (onProgress != null) {
        onProgress(i + 1, rawMessages.length);
      }

      final parsed = SmsParser.parse(body, messageDate: msgDate, cutoffDate: sinceDate);
      if (parsed != null) {
        detected++;
        try {
          final res = await apiClient.createSuggestion({
            'text': body,
            'date': msgDate.toIso8601String(),
            'source': 'sms',
            'parsedData': parsed,
          });
          if (res['ignored'] != true && res['id'] != null) {
            created++;
          }
        } catch (_) {
          // Ignore duplicate (409) or failed single item so batch scan continues
        }
      }
    }

    return {
      'scanned': rawMessages.length,
      'detected': detected,
      'created': created,
    };
  }
}
