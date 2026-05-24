import 'dart:ui';
import 'package:flutter/material.dart';

/// Frosted-glass card using BackdropFilter blur.
///
/// Best used over varied backgrounds (gradients, images). On uniform surfaces,
/// the blur effect is subtle. Use sparingly on mobile — limit to a few visible
/// at once for smooth performance.
class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final double radius;
  final double blur;
  final double opacity;
  final Color? tint;
  final Color? borderColor;
  final VoidCallback? onTap;

  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.margin,
    this.radius = 22,
    this.blur = 18,
    this.opacity = 0.12,
    this.tint,
    this.borderColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final baseTint = tint ?? (isLight ? Colors.white : const Color(0xFF111E1C));

    final card = ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                baseTint.withValues(alpha: opacity + 0.06),
                baseTint.withValues(alpha: opacity),
              ],
            ),
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(
              color: borderColor ??
                  Colors.white.withValues(alpha: isLight ? 0.4 : 0.12),
              width: 1,
            ),
          ),
          child: child,
        ),
      ),
    );

    Widget result = card;
    if (onTap != null) {
      result = Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(radius),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(radius),
          child: card,
        ),
      );
    }

    if (margin != null) result = Padding(padding: margin!, child: result);
    return result;
  }
}
