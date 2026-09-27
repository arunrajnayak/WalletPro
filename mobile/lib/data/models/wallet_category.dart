class WalletCategory {
  final String id;
  final String name;
  final String groupId;
  final String groupName;
  final String? parentId;
  final bool isCustom;
  final String? color;

  const WalletCategory({
    required this.id,
    required this.name,
    required this.groupId,
    required this.groupName,
    this.parentId,
    this.isCustom = false,
    this.color,
  });

  factory WalletCategory.fromJson(Map<String, dynamic> json) => WalletCategory(
        id: json['id'] as String,
        name: json['name'] as String,
        groupId: json['groupId'] as String,
        groupName: json['groupName'] as String,
        parentId: json['parentId'] as String?,
        isCustom: json['isCustom'] as bool? ?? false,
        color: json['color'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'groupId': groupId,
        'groupName': groupName,
        'parentId': parentId,
        'isCustom': isCustom,
        'color': color,
      };
}
