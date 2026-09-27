import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Item configuration for the [LiquidGlassNavBar].
class LiquidGlassNavItem {
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final int badgeCount;

  const LiquidGlassNavItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    this.badgeCount = 0,
  });
}

/// Ultra-modern floating Liquid Glass Navigation Bar with real-time backdrop blur,
/// specular glass border reflections, animated fluid droplet pill indicators,
/// glowing badge droplets, and tactile haptic feedback.
class LiquidGlassNavBar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<LiquidGlassNavItem> items;

  const LiquidGlassNavBar({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return Padding(
      padding: EdgeInsets.only(
        left: 18,
        right: 18,
        bottom: bottomInset > 0 ? bottomInset + 6 : 18,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
          child: Container(
            height: 68,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              // Frosted liquid glass background
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isDark
                    ? [
                        const Color(0xFF1E293B).withOpacity(0.72),
                        const Color(0xFF0F172A).withOpacity(0.62),
                      ]
                    : [
                        Colors.white.withOpacity(0.88),
                        Colors.white.withOpacity(0.68),
                      ],
              ),
              // Specular glass perimeter highlight
              border: Border.all(
                color: isDark
                    ? Colors.white.withOpacity(0.18)
                    : Colors.white.withOpacity(0.90),
                width: 1.2,
              ),
              // Floating ambient glow + soft drop shadow
              boxShadow: [
                BoxShadow(
                  color: isDark
                      ? Colors.black.withOpacity(0.55)
                      : const Color(0xFF475569).withOpacity(0.18),
                  blurRadius: 28,
                  spreadRadius: -2,
                  offset: const Offset(0, 10),
                ),
                BoxShadow(
                  color: isDark
                      ? theme.colorScheme.primary.withOpacity(0.12)
                      : theme.colorScheme.primary.withOpacity(0.08),
                  blurRadius: 16,
                  spreadRadius: 0,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Stack(
              children: [
                // Top specular highlight reflection beam (simulates overhead light catching glass bevel)
                Positioned(
                  top: 0,
                  left: 24,
                  right: 24,
                  height: 1.2,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.transparent,
                          isDark
                              ? Colors.white.withOpacity(0.35)
                              : Colors.white.withOpacity(0.95),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),

                // Navigation items row
                Row(
                  children: List.generate(items.length, (index) {
                    final item = items[index];
                    final isSelected = index == selectedIndex;

                    return Expanded(
                      child: _LiquidNavItemTile(
                        item: item,
                        isSelected: isSelected,
                        onTap: () {
                          HapticFeedback.lightImpact();
                          onDestinationSelected(index);
                        },
                      ),
                    );
                  }),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LiquidNavItemTile extends StatelessWidget {
  final LiquidGlassNavItem item;
  final bool isSelected;
  final VoidCallback onTap;

  const _LiquidNavItemTile({
    required this.item,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primary = theme.colorScheme.primary;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Center(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            // Liquid active droplet capsule
            gradient: isSelected
                ? LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: isDark
                        ? [
                            primary.withOpacity(0.34),
                            primary.withOpacity(0.12),
                          ]
                        : [
                            primary.withOpacity(0.20),
                            primary.withOpacity(0.08),
                          ],
                  )
                : null,
            border: isSelected
                ? Border.all(
                    color: primary.withOpacity(isDark ? 0.50 : 0.35),
                    width: 1.0,
                  )
                : Border.all(color: Colors.transparent, width: 1.0),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: primary.withOpacity(isDark ? 0.32 : 0.18),
                      blurRadius: 10,
                      spreadRadius: -1,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Icon with badge
              Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  AnimatedScale(
                    scale: isSelected ? 1.10 : 1.0,
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeOutBack,
                    child: Icon(
                      isSelected ? item.selectedIcon : item.icon,
                      size: 22,
                      color: isSelected
                          ? primary
                          : (isDark ? Colors.white60 : Colors.black54),
                    ),
                  ),
                  if (item.badgeCount > 0)
                    Positioned(
                      top: -5,
                      right: -10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          gradient: const LinearGradient(
                            colors: [Color(0xFFFF5252), Color(0xFFFF7A00)],
                          ),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.95),
                            width: 1.2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFFF5252).withOpacity(0.50),
                              blurRadius: 8,
                              spreadRadius: 0,
                            ),
                          ],
                        ),
                        constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                        child: Text(
                          item.badgeCount > 99 ? '99+' : '${item.badgeCount}',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                            height: 1.1,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 3),
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 200),
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected
                      ? primary
                      : (isDark ? Colors.white60 : Colors.black54),
                  letterSpacing: -0.1,
                ),
                child: Text(
                  item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
