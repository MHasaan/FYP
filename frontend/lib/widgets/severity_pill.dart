import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';

/// Severity-coded chip used for incidents (Critical/High/Medium/Low).
class SeverityPill extends StatelessWidget {
  final String? severity;
  final bool dense;
  final bool filled;

  const SeverityPill({
    super.key,
    required this.severity,
    this.dense = false,
    this.filled = false,
  });

  String get _label {
    final s = (severity ?? '').toLowerCase();
    if (s.isEmpty) return '—';
    return s[0].toUpperCase() + s.substring(1);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<IncidentSeverityColors>() ?? IncidentSeverityColors.light;
    final color = colors.forSeverity(severity);

    final hPad = dense ? 9.0 : 11.0;
    final vPad = dense ? 3.0 : 5.0;

    if (filled) {
      return Container(
        padding: EdgeInsets.symmetric(horizontal: hPad, vertical: vPad),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [color, color.withValues(alpha: 0.78)],
          ),
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.32),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Text(
          _label.toUpperCase(),
          style: GoogleFonts.outfit(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: dense ? 10 : 11,
            letterSpacing: 0.6,
          ),
        ),
      );
    }

    return Container(
      padding: EdgeInsets.symmetric(horizontal: hPad, vertical: vPad),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.32)),
      ),
      child: Text(
        _label.toUpperCase(),
        style: GoogleFonts.outfit(
          color: color,
          fontWeight: FontWeight.w800,
          fontSize: dense ? 10 : 11,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}
