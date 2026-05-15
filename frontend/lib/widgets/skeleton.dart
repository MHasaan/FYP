import 'package:flutter/material.dart';

/// Animated shimmer block used as a loading placeholder.
class SkeletonBox extends StatefulWidget {
  final double width;
  final double height;
  final double radius;

  const SkeletonBox({
    super.key,
    this.width = double.infinity,
    this.height = 16,
    this.radius = 8,
  });

  @override
  State<SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<SkeletonBox> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1300),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final base = cs.surfaceContainerHighest;
    final highlight = cs.surfaceContainerHigh;
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        final t = _ctrl.value;
        return ClipRRect(
          borderRadius: BorderRadius.circular(widget.radius),
          child: SizedBox(
            width: widget.width,
            height: widget.height,
            child: Stack(
              children: [
                Positioned.fill(child: Container(color: base)),
                Positioned.fill(
                  child: ShaderMask(
                    blendMode: BlendMode.srcATop,
                    shaderCallback: (rect) {
                      final dx = rect.width * (t * 2 - 1);
                      return LinearGradient(
                        begin: Alignment(-1 + dx / rect.width, 0),
                        end: Alignment(1 + dx / rect.width, 0),
                        colors: [
                          base.withValues(alpha: 0),
                          highlight.withValues(alpha: 0.9),
                          base.withValues(alpha: 0),
                        ],
                        stops: const [0.35, 0.5, 0.65],
                      ).createShader(rect);
                    },
                    child: Container(color: base),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Convenience: a card-shaped skeleton row used in list screens.
class SkeletonRow extends StatelessWidget {
  final double height;
  final EdgeInsetsGeometry margin;

  const SkeletonRow({
    super.key,
    this.height = 72,
    this.margin = const EdgeInsets.only(bottom: 10),
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: margin,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Row(
        children: [
          const SkeletonBox(width: 40, height: 40, radius: 10),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                SkeletonBox(height: 14, width: 180),
                SizedBox(height: 8),
                SkeletonBox(height: 12, width: 120),
              ],
            ),
          ),
          const SizedBox(width: 12),
          const SkeletonBox(width: 60, height: 22, radius: 999),
        ],
      ),
    );
  }
}

/// List of N skeleton rows for the loading state of incident / patient / camera lists.
class SkeletonList extends StatelessWidget {
  final int count;
  final EdgeInsetsGeometry padding;

  const SkeletonList({
    super.key,
    this.count = 6,
    this.padding = const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
  });

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: padding,
      itemCount: count,
      itemBuilder: (_, __) => const SkeletonRow(),
    );
  }
}
