import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';

/// Brand logo — custom EKG pulse mark + Cormorant Garamond wordmark.
/// No system icons. Fully painted.
class AppLogo extends StatelessWidget {
  final double size;
  final bool showWordmark;
  final Color? color;

  const AppLogo({
    super.key,
    this.size = 32,
    this.showWordmark = true,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fg = color ?? cs.primary;
    final isLight = Theme.of(context).brightness == Brightness.light;

    final mark = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.brandTeal,
            AppTheme.brandSage,
          ],
        ),
        borderRadius: BorderRadius.circular(size * 0.28),
        boxShadow: [
          BoxShadow(
            color: AppTheme.brandTeal.withValues(alpha: 0.30),
            blurRadius: size * 0.4,
            offset: Offset(0, size * 0.1),
          ),
        ],
      ),
      child: CustomPaint(
        painter: _EkgPainter(Colors.white.withValues(alpha: 0.92)),
      ),
    );

    if (!showWordmark) return mark;

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        mark,
        SizedBox(width: size * 0.30),
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Eldercare',
              style: GoogleFonts.cormorantGaramond(
                fontWeight: FontWeight.w700,
                fontSize: size * 0.68,
                color: isLight ? const Color(0xFF0F1C1A) : const Color(0xFFF2F7F5),
                letterSpacing: 0.2,
                height: 1.0,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Paints a clean EKG heartbeat signature — the product's core metaphor.
class _EkgPainter extends CustomPainter {
  final Color color;
  const _EkgPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = size.width * 0.07
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    final w = size.width;
    final h = size.height;

    final path = Path()
      ..moveTo(w * 0.05, h * 0.52)
      ..lineTo(w * 0.25, h * 0.52)
      ..lineTo(w * 0.36, h * 0.22)
      ..lineTo(w * 0.48, h * 0.78)
      ..lineTo(w * 0.60, h * 0.38)
      ..lineTo(w * 0.70, h * 0.52)
      ..lineTo(w * 0.95, h * 0.52);

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_EkgPainter old) => old.color != color;
}
