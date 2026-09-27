class PortfolioHolding {
  final String id;
  final String type;
  final String name;
  final String code;
  final double units;
  final double avgCost;
  final double currentNav;
  final double currentValue;
  final double previousNav;
  final double changePercent;

  const PortfolioHolding({
    required this.id,
    required this.type,
    required this.name,
    required this.code,
    required this.units,
    required this.avgCost,
    required this.currentNav,
    required this.currentValue,
    required this.previousNav,
    required this.changePercent,
  });

  factory PortfolioHolding.fromJson(Map<String, dynamic> json) => PortfolioHolding(
        id: json['id'] as String,
        type: json['type'] as String,
        name: json['name'] as String,
        code: json['code'] as String,
        units: (json['units'] as num?)?.toDouble() ?? 0.0,
        avgCost: (json['avgCost'] as num?)?.toDouble() ?? 0.0,
        currentNav: (json['currentNav'] as num?)?.toDouble() ?? 0.0,
        currentValue: (json['currentValue'] as num?)?.toDouble() ?? 0.0,
        previousNav: (json['previousNav'] as num?)?.toDouble() ?? 0.0,
        changePercent: (json['changePercent'] as num?)?.toDouble() ?? 0.0,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'name': name,
        'code': code,
        'units': units,
        'avgCost': avgCost,
        'currentNav': currentNav,
        'currentValue': currentValue,
        'previousNav': previousNav,
        'changePercent': changePercent,
      };
}
