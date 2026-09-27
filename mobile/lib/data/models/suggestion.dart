import 'package:freezed_annotation/freezed_annotation.dart';

part 'suggestion.freezed.dart';
part 'suggestion.g.dart';

enum SuggestionStatus { pending, approved, rejected, synced, expired }
enum SuggestionSource { sms, email, portfolio, nps }
enum TransactionType { expense, income }

@freezed
class Suggestion with _$Suggestion {
  const factory Suggestion({
    required String id,
    required SuggestionSource source,
    required SuggestionStatus status,
    required double amount,
    required String currencyCode,
    required TransactionType transactionType,
    String? counterParty,
    String? note,
    String? referenceNumber,
    String? accountLast4,
    String? walletAccountId,
    String? walletCategoryId,
    String? walletCategoryName,
    double? aiConfidence,
    required DateTime transactionDate,
    required DateTime createdAt,
  }) = _Suggestion;

  factory Suggestion.fromJson(Map<String, dynamic> json) => _$SuggestionFromJson(json);
}
