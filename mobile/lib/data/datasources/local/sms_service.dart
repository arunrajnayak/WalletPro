import 'package:flutter/services.dart';
import '../../parsers/sms_parser.dart';
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

  // Hardcoded start date: 1st September 2026
  static final DateTime hardcodedStartDate = DateTime(2026, 9, 1);

  /// Read raw SMS messages from Android inbox (default from 1st September 2026)
  Future<List<Map<String, dynamic>>> readInbox({DateTime? sinceDate, int limit = 500}) async {
    try {
      final effectiveDate = sinceDate ?? hardcodedStartDate;
      final millis = effectiveDate.millisecondsSinceEpoch;
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

  /// High-level function: scan inbox from 1st September 2026, parse bank transactions, and send them to backend
  Future<Map<String, int>> scanAndSyncInbox({
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

    final rawMessages = await readInbox(sinceDate: hardcodedStartDate, limit: 500);
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

      if (msgDate.isBefore(hardcodedStartDate)) {
        continue;
      }

      final parsed = SmsParser.parse(body, messageDate: msgDate);
      if (parsed != null) {
        detected++;
        // Transaction date matches SMS received date
        parsed['transactionDate'] = msgDate.toIso8601String();

        // Pass Android SMS ID as sourceId for deduplication & to avoid re-parsing reviewed SMS
        final androidMsgId = msg['id']?.toString() ?? msg['_id']?.toString();
        if (androidMsgId != null && androidMsgId.isNotEmpty) {
          parsed['sourceId'] = androidMsgId;
        }

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
