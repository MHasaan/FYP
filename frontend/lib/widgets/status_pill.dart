import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

enum StatusKind { neutral, success, warning, danger, info, primary }

/// A small rounded pill with a coloured dot + label. Used for instance status,
/// incident status, role badges, etc.
class StatusPill extends StatelessWidget {
  final String label;
  final StatusKind kind;
  final IconData? icon;
  final bool dense;

  const StatusPill({
    super.key,
    required this.label,
    this.kind = StatusKind.neutral,
    this.icon,
    this.dense = false,
  });

  /// Convenience: build a pill from an instance/pipeline status string.
  factory StatusPill.forPipelineStatus(String? status) {
    final s = (status ?? '').toLowerCase();
    switch (s) {
      case 'running':
        return StatusPill(label: 'Running', kind: StatusKind.success);
      case 'paused':
        return StatusPill(label: 'Paused', kind: StatusKind.warning);
      case 'stopped':
        return StatusPill(label: 'Stopped', kind: StatusKind.danger);
      case 'idle':
      default:
        return StatusPill(label: status?.isNotEmpty == true ? _capitalize(status!) : 'Idle', kind: StatusKind.neutral);
    }
  }

  /// Convenience: build a pill from an incident status string.
  factory StatusPill.forIncidentStatus(String? status) {
    final s = (status ?? '').toLowerCase();
    switch (s) {
      case 'new':
        return const StatusPill(label: 'New', kind: StatusKind.danger);
      case 'acknowledged':
        return const StatusPill(label: 'Acknowledged', kind: StatusKind.warning);
      case 'resolved':
        return const StatusPill(label: 'Resolved', kind: StatusKind.success);
      default:
        return StatusPill(label: status ?? '—', kind: StatusKind.neutral);
    }
  }

  static String _capitalize(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final status = theme.extension<AppStatusColors>() ?? AppStatusColors.fallback;
    final color = switch (kind) {
      StatusKind.success => status.success,
      StatusKind.warning => status.warning,
      StatusKind.danger => status.danger,
      StatusKind.info => status.info,
      StatusKind.primary => cs.primary,
      StatusKind.neutral => cs.onSurfaceVariant,
    };

    final hPad = dense ? 8.0 : 10.0;
    final vPad = dense ? 3.0 : 5.0;

    return Container(
      padding: EdgeInsets.symmetric(horizontal: hPad, vertical: vPad),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: dense ? 12 : 14, color: color),
            SizedBox(width: dense ? 4 : 6),
          ] else ...[
            Container(
              width: dense ? 6 : 8,
              height: dense ? 6 : 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            SizedBox(width: dense ? 4 : 6),
          ],
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w700,
              fontSize: dense ? 11 : 12,
            ),
          ),
        ],
      ),
    );
  }
}
