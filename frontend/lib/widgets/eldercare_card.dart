import 'package:flutter/material.dart';

/// Standard card surface used throughout the app.
/// Replaces ad-hoc Container + BoxDecoration usage with a consistent look.
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
    this.radius = 16,
    this.onTap,
    this.dense = false,
  });

  @override
  State<EldercareCard> createState() => _EldercareCardState();
}

class _EldercareCardState extends State<EldercareCard> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final effectivePadding = widget.dense ? const EdgeInsets.all(16) : widget.padding;

    final interactive = widget.onTap != null;
    final raise = interactive && _hovering;

    final body = AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOut,
      transform: raise ? (Matrix4.identity()..translate(0.0, -1.5, 0.0)) : Matrix4.identity(),
      padding: effectivePadding,
      decoration: BoxDecoration(
        color: widget.color ?? cs.surface,
        borderRadius: BorderRadius.circular(widget.radius),
        border: Border.all(
          color: raise
              ? cs.primary.withValues(alpha: 0.4)
              : (widget.borderColor ?? cs.outlineVariant),
        ),
        boxShadow: raise
            ? [
                BoxShadow(
                  color: cs.primary.withValues(alpha: 0.10),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ]
            : const [],
      ),
      child: widget.child,
    );

    Widget result = body;
    if (interactive) {
      result = MouseRegion(
        onEnter: (_) => setState(() => _hovering = true),
        onExit: (_) => setState(() => _hovering = false),
        cursor: SystemMouseCursors.click,
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(widget.radius),
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(widget.radius),
            child: body,
          ),
        ),
      );
    }
    if (widget.margin != null) result = Padding(padding: widget.margin!, child: result);
    return result;
  }
}
