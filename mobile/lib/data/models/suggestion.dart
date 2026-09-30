enum SuggestionStatus { pending, approved, rejected, synced, expired }
enum SuggestionSource { sms, portfolio, nps }
enum TransactionType { expense, income }

class Suggestion {
  final String id;
  final SuggestionSource source;
  final SuggestionStatus status;
  final double amount;
  final String currencyCode;
  final TransactionType transactionType;
  final String? counterParty;
  final String? note;
  final String? referenceNumber;
  final String? accountLast4;
  final String? walletAccountId;
  final String? walletCategoryId;
  final String? walletCategoryName;
  final double? aiConfidence;
  final DateTime transactionDate;
  final DateTime createdAt;

  const Suggestion({
    required this.id,
    required this.source,
    required this.status,
    required this.amount,
    required this.currencyCode,
    required this.transactionType,
    this.counterParty,
    this.note,
    this.referenceNumber,
    this.accountLast4,
    this.walletAccountId,
    this.walletCategoryId,
    this.walletCategoryName,
    this.aiConfidence,
    required this.transactionDate,
    required this.createdAt,
  });

  factory Suggestion.fromJson(Map<String, dynamic> json) => Suggestion(
        id: json['id'] as String,
        source: SuggestionSource.values.byName(json['source'] as String? ?? 'sms'),
        status: SuggestionStatus.values.byName(json['status'] as String? ?? 'pending'),
        amount: (json['amount'] is num)
            ? (json['amount'] as num).toDouble()
            : double.tryParse(json['amount']?.toString() ?? '0') ?? 0.0,
        currencyCode: json['currencyCode'] as String? ?? 'INR',
        transactionType: TransactionType.values.byName(json['transactionType'] as String? ?? 'expense'),
        counterParty: json['counterParty'] as String?,
        note: json['note'] as String?,
        referenceNumber: json['referenceNumber'] as String?,
        accountLast4: json['accountLast4'] as String?,
        walletAccountId: json['walletAccountId'] as String?,
        walletCategoryId: json['walletCategoryId'] as String?,
        walletCategoryName: json['walletCategoryName'] as String?,
        aiConfidence: (json['aiConfidence'] is num)
            ? (json['aiConfidence'] as num).toDouble()
            : double.tryParse(json['aiConfidence']?.toString() ?? ''),
        transactionDate: DateTime.parse(json['transactionDate'] as String),
        createdAt: DateTime.parse(json['createdAt'] as String),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'source': source.name,
        'status': status.name,
        'amount': amount,
        'currencyCode': currencyCode,
        'transactionType': transactionType.name,
        'counterParty': counterParty,
        'note': note,
        'referenceNumber': referenceNumber,
        'accountLast4': accountLast4,
        'walletAccountId': walletAccountId,
        'walletCategoryId': walletCategoryId,
        'walletCategoryName': walletCategoryName,
        'aiConfidence': aiConfidence,
        'transactionDate': transactionDate.toIso8601String(),
        'createdAt': createdAt.toIso8601String(),
      };
}
