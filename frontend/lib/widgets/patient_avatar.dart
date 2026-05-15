import 'package:flutter/material.dart';

/// Circular avatar showing a patient's initials, with optional status ring.
class PatientAvatar extends StatelessWidget {
  final String? name;
  final double size;
  final Color? ringColor;
  final IconData? overrideIcon;

  const PatientAvatar({
    super.key,
    this.name,
    this.size = 40,
    this.ringColor,
    this.overrideIcon,
  });

  String get _initials {
    final n = (name ?? '').trim();
    if (n.isEmpty) return '?';
    final parts = n.split(RegExp(r'\s+'));
    if (parts.length == 1) return parts[0].substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1)).toUpperCase();
  }

  Color _bgColor(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final n = (name ?? '').trim();
    if (n.isEmpty) return cs.surfaceContainerHighest;
    // Deterministic colour pick from a curated palette.
    const palette = [
      Color(0xFF0F766E), Color(0xFFB45309), Color(0xFF6366F1),
      Color(0xFF7C3AED), Color(0xFF0369A1), Color(0xFF15803D),
      Color(0xFFC2410C), Color(0xFF0E7490),
    ];
    final hash = n.codeUnits.fold<int>(0, (a, b) => a + b);
    return palette[hash % palette.length];
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bg = _bgColor(context);
    final fg = bg.computeLuminance() < 0.5 ? Colors.white : cs.onSurface;

    final inner = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: bg.withValues(alpha: 0.18),
        shape: BoxShape.circle,
        border: Border.all(color: bg.withValues(alpha: 0.45), width: 1),
      ),
      alignment: Alignment.center,
      child: overrideIcon != null
          ? Icon(overrideIcon, color: bg, size: size * 0.5)
          : Text(
              _initials,
              style: TextStyle(
                color: fg.withValues(alpha: 0.9),
                fontWeight: FontWeight.w700,
                fontSize: size * 0.38,
              ),
            ),
    );

    if (ringColor == null) return inner;
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: ringColor!, width: 2),
      ),
      child: inner,
    );
  }
}
