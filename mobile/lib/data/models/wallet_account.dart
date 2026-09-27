class WalletAccount {
  final String id;
  final String name;
  final String currencyCode;
  final String accountType;
  final String? last4Digits;
  final double balance;

  const WalletAccount({
    required this.id,
    required this.name,
    required this.currencyCode,
    required this.accountType,
    this.last4Digits,
    required this.balance,
  });

  factory WalletAccount.fromJson(Map<String, dynamic> json) => WalletAccount(
        id: json['id'] as String,
        name: json['name'] as String,
        currencyCode: json['currencyCode'] as String? ?? 'INR',
        accountType: json['accountType'] as String? ?? 'General',
        last4Digits: json['last4Digits'] as String?,
        balance: (json['balance'] as num?)?.toDouble() ?? 0.0,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'currencyCode': currencyCode,
        'accountType': accountType,
        'last4Digits': last4Digits,
        'balance': balance,
      };
}
