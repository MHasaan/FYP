import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Inline logo mark + wordmark.
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

    final mark = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [fg, fg.withValues(alpha: 0.7)],
        ),
        borderRadius: BorderRadius.circular(size * 0.28),
      ),
      child: Icon(
        Icons.health_and_safety_rounded,
        color: Colors.white,
        size: size * 0.6,
      ),
    );

    if (!showWordmark) return mark;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        mark,
        SizedBox(width: size * 0.32),
        Text(
          'Eldercare',
          style: GoogleFonts.plusJakartaSans(
            fontWeight: FontWeight.w800,
            fontSize: size * 0.6,
            color: cs.onSurface,
            letterSpacing: -0.5,
          ),
        ),
      ],
    );
  }
}
