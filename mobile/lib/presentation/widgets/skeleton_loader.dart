import 'package:flutter/material.dart';

/// Lightweight, 60fps shimmer animation provider
class ShimmerLoading extends StatefulWidget {
  final Widget child;

  const ShimmerLoading({super.key, required this.child});

  @override
  State<ShimmerLoading> createState() => _ShimmerLoadingState();
}

class _ShimmerLoadingState extends State<ShimmerLoading> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final baseColor = isDark
        ? const Color(0xFF1E222D)
        : const Color(0xFFE2E8F0);
    final highlightColor = isDark
        ? const Color(0xFF2D3342)
        : const Color(0xFFF8FAFC);

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) {
            return LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                baseColor,
                highlightColor,
                baseColor,
              ],
              stops: const [0.0, 0.5, 1.0],
              transform: _SlidingGradientTransform(slidePercent: _controller.value),
            ).createShader(bounds);
          },
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

class _SlidingGradientTransform extends GradientTransform {
  final double slidePercent;

  const _SlidingGradientTransform({required this.slidePercent});

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) {
    return Matrix4.translationValues(bounds.width * (slidePercent * 2 - 1), 0.0, 0.0);
  }
}

/// Primitive skeleton box with customizable shape and dimensions
class SkeletonBox extends StatelessWidget {
  final double? width;
  final double? height;
  final double borderRadius;
  final EdgeInsetsGeometry? margin;

  const SkeletonBox({
    super.key,
    this.width,
    this.height,
    this.borderRadius = 8,
    this.margin,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: width,
      height: height,
      margin: margin,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1F2430) : const Color(0xFFE2E8F0),
        borderRadius: BorderRadius.circular(borderRadius),
      ),
    );
  }
}

/// Skeleton for DashboardScreen
class DashboardSkeleton extends StatelessWidget {
  const DashboardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return ShimmerLoading(
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          // 1. Hero Net Worth Card
          Container(
            height: 140,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonBox(width: 120, height: 14),
                SizedBox(height: 12),
                SkeletonBox(width: 180, height: 28),
                Spacer(),
                Row(
                  children: [
                    Expanded(child: SkeletonBox(height: 38, borderRadius: 10)),
                    SizedBox(width: 12),
                    Expanded(child: SkeletonBox(height: 38, borderRadius: 10)),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // 2. Action Grid (3 buttons)
          const Row(
            children: [
              Expanded(child: SkeletonBox(height: 72, borderRadius: 16)),
              SizedBox(width: 10),
              Expanded(child: SkeletonBox(height: 72, borderRadius: 16)),
              SizedBox(width: 10),
              Expanded(child: SkeletonBox(height: 72, borderRadius: 16)),
            ],
          ),

          const SizedBox(height: 16),

          // 3. SMS Cutoff banner
          const SkeletonBox(height: 64, borderRadius: 16),

          const SizedBox(height: 20),

          // 4. Section Title
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              SkeletonBox(width: 140, height: 18),
              SkeletonBox(width: 60, height: 14),
            ],
          ),

          const SizedBox(height: 12),

          // 5. Suggestion Card Skeleton
          const _SuggestionCardSkeleton(margin: EdgeInsets.symmetric(vertical: 6)),
          const _SuggestionCardSkeleton(margin: EdgeInsets.symmetric(vertical: 6)),
        ],
      ),
    );
  }
}

/// Skeleton for SuggestionsScreen (Review Queue)
class SuggestionListSkeleton extends StatelessWidget {
  const SuggestionListSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return ShimmerLoading(
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.only(top: 12, bottom: 24),
        children: const [
          _SuggestionCardSkeleton(margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8)),
          _SuggestionCardSkeleton(margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8)),
        ],
      ),
    );
  }
}

class _SuggestionCardSkeleton extends StatelessWidget {
  final EdgeInsetsGeometry margin;

  const _SuggestionCardSkeleton({required this.margin});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Meta Header
          Row(
            children: [
              SkeletonBox(width: 50, height: 20, borderRadius: 6),
              SizedBox(width: 10),
              SkeletonBox(width: 130, height: 14),
              Spacer(),
              SkeletonBox(width: 70, height: 20, borderRadius: 6),
            ],
          ),

          SizedBox(height: 16),

          // Hero Merchant & Amount
          Row(
            children: [
              SkeletonBox(width: 54, height: 54, borderRadius: 16),
              SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonBox(width: 160, height: 18),
                    SizedBox(height: 6),
                    SkeletonBox(width: 100, height: 12),
                  ],
                ),
              ),
              SkeletonBox(width: 90, height: 24),
            ],
          ),

          SizedBox(height: 16),

          // Type Toggle
          SkeletonBox(height: 48, borderRadius: 14),

          SizedBox(height: 14),

          // Stacked Category & Account Boxes
          SkeletonBox(height: 64, borderRadius: 16),
          SizedBox(height: 10),
          SkeletonBox(height: 64, borderRadius: 16),

          SizedBox(height: 18),

          // Action Buttons
          Row(
            children: [
              Expanded(flex: 2, child: SkeletonBox(height: 52, borderRadius: 16)),
              SizedBox(width: 12),
              Expanded(flex: 3, child: SkeletonBox(height: 52, borderRadius: 16)),
            ],
          ),
        ],
      ),
    );
  }
}
