import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Circular avatar with deterministic gradient fill + initials.
/// Each name maps to a unique two-tone gradient drawn from the brand palette.
class PatientAvatar extends StatelessWidget {
  final String? name;
  final double size;
  final Color? ringColor;
  final IconData? overrideIcon;
  final bool showShadow;

  const PatientAvatar({
    super.key,
    this.name,
    this.size = 40,
    this.ringColor,
    this.overrideIcon,
    this.showShadow = true,
  });

  String get _initials {
    final n = (name ?? '').trim();
    if (n.isEmpty) return '?';
    final parts = n.split(RegExp(r'\s+'));
    if (parts.length == 1) return parts[0].substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1)).toUpperCase();
  }

  // Curated two-tone gradients keyed deterministically off the name.
  static const List<List<Color>> _gradients = [
    [Color(0xFF01949A), Color(0xFF3D8D7A)], // teal → sage
    [Color(0xFFDC9750), Color(0xFFC2410C)], // amber → rust
    [Color(0xFF3D8D7A), Color(0xFF2A6B5E)], // sage deep
    [Color(0xFFFCB5AC), Color(0xFFDC9750)], // blush → amber
    [Color(0xFF6366F1), Color(0xFF8B5CF6)], // indigo → violet
    [Color(0xFF0EA5E9), Color(0xFF06B6D4)], // sky → cyan
    [Color(0xFF14B8A6), Color(0xFF0F766E)], // teal range
    [Color(0xFFEC4899), Color(0xFFBE185D)], // pink range
  ];

  List<Color> _gradient() {
    final n = (name ?? '').trim();
    if (n.isEmpty) return const [Color(0xFF8AADA6), Color(0xFF5F827B)];
    final hash = n.codeUnits.fold<int>(0, (a, b) => a + b);
    return _gradients[hash % _gradients.length];
  }

  @override
  Widget build(BuildContext context) {
    final colors = _gradient();

    final inner = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ),
        shape: BoxShape.circle,
        boxShadow: showShadow
            ? [
                BoxShadow(
                  color: colors.first.withValues(alpha: 0.32),
                  blurRadius: size * 0.3,
                  offset: Offset(0, size * 0.1),
                ),
              ]
            : null,
      ),
      alignment: Alignment.center,
      child: overrideIcon != null
          ? Icon(overrideIcon, color: Colors.white, size: size * 0.5)
          : Text(
              _initials,
              style: GoogleFonts.outfit(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: size * 0.38,
                letterSpacing: 0.3,
              ),
            ),
    );

    if (ringColor == null) return inner;
    return Container(
      padding: const EdgeInsets.all(2.5),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: ringColor!, width: 2),
      ),
      child: inner,
    );
  }
}
