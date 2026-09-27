import 'package:freezed_annotation/freezed_annotation.dart';

part 'portfolio_holding.freezed.dart';
part 'portfolio_holding.g.dart';

@freezed
class PortfolioHolding with _$PortfolioHolding {
  const factory PortfolioHolding({
    required String id,
    required String type,
    required String name,
    required String code,
    required double units,
    required double avgCost,
    required double currentNav,
    required double currentValue,
    required double previousNav,
    required double changePercent,
  }) = _PortfolioHolding;

  factory PortfolioHolding.fromJson(Map<String, dynamic> json) => _$PortfolioHoldingFromJson(json);
}
