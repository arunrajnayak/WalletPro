import 'package:freezed_annotation/freezed_annotation.dart';

part 'wallet_category.freezed.dart';
part 'wallet_category.g.dart';

@freezed
class WalletCategory with _$WalletCategory {
  const factory WalletCategory({
    required String id,
    required String name,
    required String groupId,
    required String groupName,
    String? parentId,
    @Default(false) bool isCustom,
    String? color,
  }) = _WalletCategory;

  factory WalletCategory.fromJson(Map<String, dynamic> json) => _$WalletCategoryFromJson(json);
}
