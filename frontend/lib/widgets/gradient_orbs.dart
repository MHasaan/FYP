import 'package:flutter/material.dart';

/// Decorative animated background orbs in brand colors. Used behind hero
/// gradient headers (dashboard, splash, login).
class GradientOrbs extends StatefulWidget {
  final List<_Orb> orbs;

  const GradientOrbs({super.key, required this.orbs});

  /// Default arrangement using brand palette (cream, blush, amber).
  factory GradientOrbs.brand() {
    return const GradientOrbs(orbs: [
      _Orb(color: Color(0xFFFFFACD), alpha: 0.20, dx: 0.85, dy: 0.18, size: 0.42),
      _Orb(color: Color(0xFFFCB5AC), alpha: 0.18, dx: 0.10, dy: 0.70, size: 0.55),
      _Orb(color: Color(0xFFDC9750), alpha: 0.10, dx: 0.72, dy: 0.55, size: 0.18),
      _Orb(color: Color(0xFFFFFFFF), alpha: 0.06, dx: 0.25, dy: 0.30, size: 0.30),
    ]);
  }

  @override
  State<GradientOrbs> createState() => _GradientOrbsState();
}

class _GradientOrbsState extends State<GradientOrbs> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(seconds: 12))..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => CustomPaint(
        painter: _OrbPainter(widget.orbs, _ctrl.value),
        size: Size.infinite,
      ),
    );
  }
}

class _Orb {
  final Color color;
  final double alpha;
  final double dx;
  final double dy;
  final double size;
  const _Orb({
    required this.color,
    required this.alpha,
    required this.dx,
    required this.dy,
    required this.size,
  });
}

class _OrbPainter extends CustomPainter {
  final List<_Orb> orbs;
  final double t;

  _OrbPainter(this.orbs, this.t);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    final tau = t * 2 * 3.14159;

    for (var i = 0; i < orbs.length; i++) {
      final o = orbs[i];
      // Gentle floating drift unique per orb
      final phase = i * 0.7;
      final driftX = 0.025 * (i.isEven ? 1 : -1) * (1 + 0.3 * (i % 2));
      final driftY = 0.020 * ((i + 1) % 2 == 0 ? 1 : -1);

      final dx = (o.dx + driftX * (1 + 0.5 * (tau + phase).remainder(6.283))).clamp(0.0, 1.0);
      final dy = (o.dy + driftY * (1 + 0.6 * (tau - phase).remainder(6.283))).clamp(0.0, 1.0);

      paint.color = o.color.withValues(alpha: o.alpha);
      canvas.drawCircle(
        Offset(dx * size.width, dy * size.height),
        o.size * size.width,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_OrbPainter old) => old.t != t || old.orbs != orbs;
}
