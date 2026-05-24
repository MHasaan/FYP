import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'animated_counter.dart';
import 'eldercare_card.dart';

/// Numeric KPI tile with animated counter, accent glow, and soft trend.
class StatTile extends StatelessWidget {
  final String label;
  final String value;
  final String? subtitle;
  final IconData icon;
  final Color? accent;
  final VoidCallback? onTap;

  const StatTile({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.subtitle,
    this.accent,
    this.onTap,
  });

  /// Try to parse the value as a number for the count-up animation.
  /// Falls back to a static string if it isn't numeric.
  int? get _intValue {
    final cleaned = value.replaceAll(RegExp(r'[^\d-]'), '');
    return int.tryParse(cleaned);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final color = accent ?? cs.primary;
    final intVal = _intValue;
    final isNumeric = intVal != null && value.trim() == intVal.toString();

    return EldercareCard(
      onTap: onTap,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      color.withValues(alpha: 0.20),
                      color.withValues(alpha: 0.10),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: color.withValues(alpha: 0.22)),
                  boxShadow: [
                    BoxShadow(
                      color: color.withValues(alpha: 0.15),
                      blurRadius: 14,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const Spacer(),
            ],
          ),
          const SizedBox(height: 16),
          if (isNumeric)
            AnimatedCounter(
              value: intVal,
              style: GoogleFonts.outfit(
                fontWeight: FontWeight.w700,
                fontSize: 30,
                color: cs.onSurface,
                letterSpacing: -1,
              ),
            )
          else
            Text(
              value,
              style: GoogleFonts.outfit(
                fontWeight: FontWeight.w700,
                fontSize: 30,
                color: cs.onSurface,
                letterSpacing: -1,
              ),
            ),
          const SizedBox(height: 4),
          Text(
            label,
            style: GoogleFonts.dmSans(
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w500,
              fontSize: 13,
              height: 1.2,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 6),
            Text(
              subtitle!,
              style: GoogleFonts.dmSans(
                color: color,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
