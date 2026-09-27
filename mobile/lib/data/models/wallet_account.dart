import 'package:freezed_annotation/freezed_annotation.dart';

part 'wallet_account.freezed.dart';
part 'wallet_account.g.dart';

@freezed
class WalletAccount with _$WalletAccount {
  const factory WalletAccount({
    required String id,
    required String name,
    required String currencyCode,
    required String accountType,
    String? last4Digits,
    required double balance,
  }) = _WalletAccount;

  factory WalletAccount.fromJson(Map<String, dynamic> json) => _$WalletAccountFromJson(json);
}
