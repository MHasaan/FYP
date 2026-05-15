import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Severity-coded chip used for incidents (Critical/High/Medium/Low).
class SeverityPill extends StatelessWidget {
  final String? severity;
  final bool dense;

  const SeverityPill({super.key, required this.severity, this.dense = false});

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

    final hPad = dense ? 8.0 : 10.0;
    final vPad = dense ? 3.0 : 5.0;

    return Container(
      padding: EdgeInsets.symmetric(horizontal: hPad, vertical: vPad),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        _label.toUpperCase(),
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w800,
          fontSize: dense ? 10 : 11,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
