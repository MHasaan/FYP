import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';

/// Standard card surface used throughout the app.
class EldercareCard extends StatefulWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final Color? color;
  final Color? borderColor;
  final double radius;
  final VoidCallback? onTap;
  final bool dense;

  const EldercareCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.margin,
    this.color,
    this.borderColor,
    this.radius = 20,
    this.onTap,
    this.dense = false,
  });

  @override
  State<EldercareCard> createState() => _EldercareCardState();
}

class _EldercareCardState extends State<EldercareCard> with SingleTickerProviderStateMixin {
  bool _hovering = false;
  late final AnimationController _pressCtrl;
  late final Animation<double> _pressScale;

  @override
  void initState() {
    super.initState();
    _pressCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 85),
      reverseDuration: const Duration(milliseconds: 200),
    );
    _pressScale = Tween<double>(begin: 1.0, end: 0.975).animate(
      CurvedAnimation(parent: _pressCtrl, curve: Curves.easeIn, reverseCurve: Curves.easeOutBack),
    );
  }

  @override
  void dispose() {
    _pressCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isLight = theme.brightness == Brightness.light;
    final effectivePadding = widget.dense ? const EdgeInsets.all(16) : widget.padding;
    final interactive = widget.onTap != null;
    final active = interactive && (_hovering || _pressCtrl.value > 0);

    Widget body = AnimatedBuilder(
      animation: _pressCtrl,
      builder: (_, child) => Transform.scale(
        scale: interactive ? _pressScale.value : 1.0,
        child: child,
      ),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: effectivePadding,
        decoration: BoxDecoration(
          color: widget.color ?? cs.surface,
          borderRadius: BorderRadius.circular(widget.radius),
          border: Border.all(
            color: active
                ? AppTheme.brandTeal.withValues(alpha: 0.35)
                : (widget.borderColor ?? cs.outlineVariant),
            width: active ? 1.5 : 1.0,
          ),
          boxShadow: active
              ? [
                  BoxShadow(
                    color: AppTheme.brandTeal.withValues(alpha: 0.12),
                    blurRadius: 28,
                    offset: const Offset(0, 8),
                    spreadRadius: 0,
                  ),
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isLight ? 0.04 : 0.18),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isLight ? 0.03 : 0.14),
                    blurRadius: 12,
                    offset: const Offset(0, 3),
                    spreadRadius: 0,
                  ),
                ],
        ),
        child: widget.child,
      ),
    );

    if (interactive) {
      body = MouseRegion(
        onEnter: (_) => setState(() => _hovering = true),
        onExit: (_) {
          setState(() => _hovering = false);
          _pressCtrl.reverse();
        },
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () {
            HapticFeedback.lightImpact();
            widget.onTap!();
          },
          onTapDown: (_) => _pressCtrl.forward(),
          onTapUp: (_) => _pressCtrl.reverse(),
          onTapCancel: () => _pressCtrl.reverse(),
          child: body,
        ),
      );
    }

    if (widget.margin != null) body = Padding(padding: widget.margin!, child: body);
    return body;
  }
}
