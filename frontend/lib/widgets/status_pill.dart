import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';

enum StatusKind { neutral, success, warning, danger, info, primary }

/// A rounded pill with a coloured (optionally pulsing) dot + label.
/// Use the `pulse: true` form for live indicators (e.g. "Live", "New").
class StatusPill extends StatelessWidget {
  final String label;
  final StatusKind kind;
  final IconData? icon;
  final bool dense;
  final bool pulse;

  const StatusPill({
    super.key,
    required this.label,
    this.kind = StatusKind.neutral,
    this.icon,
    this.dense = false,
    this.pulse = false,
  });

  factory StatusPill.forPipelineStatus(String? status) {
    final s = (status ?? '').toLowerCase();
    switch (s) {
      case 'running':
        return const StatusPill(label: 'Running', kind: StatusKind.success, pulse: true);
      case 'paused':
        return const StatusPill(label: 'Paused', kind: StatusKind.warning);
      case 'stopped':
        return const StatusPill(label: 'Stopped', kind: StatusKind.danger);
      case 'idle':
      default:
        return StatusPill(
          label: (status?.isNotEmpty ?? false) ? _capitalize(status!) : 'Idle',
          kind: StatusKind.neutral,
        );
    }
  }

  factory StatusPill.forIncidentStatus(String? status) {
    final s = (status ?? '').toLowerCase();
    switch (s) {
      case 'new':
        return const StatusPill(label: 'New', kind: StatusKind.danger, pulse: true);
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
      StatusKind.danger  => status.danger,
      StatusKind.info    => status.info,
      StatusKind.primary => cs.primary,
      StatusKind.neutral => cs.onSurfaceVariant,
    };

    final hPad = dense ? 9.0 : 11.0;
    final vPad = dense ? 4.0 : 5.0;

    return Container(
      padding: EdgeInsets.symmetric(horizontal: hPad, vertical: vPad),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: dense ? 12 : 14, color: color),
            SizedBox(width: dense ? 5 : 6),
          ] else ...[
            _Dot(color: color, dense: dense, pulse: pulse),
            SizedBox(width: dense ? 5 : 6),
          ],
          Text(
            label,
            style: GoogleFonts.outfit(
              color: color,
              fontWeight: FontWeight.w700,
              fontSize: dense ? 11 : 12,
              letterSpacing: 0.1,
            ),
          ),
        ],
      ),
    );
  }
}

class _Dot extends StatefulWidget {
  final Color color;
  final bool dense;
  final bool pulse;
  const _Dot({required this.color, required this.dense, required this.pulse});

  @override
  State<_Dot> createState() => _DotState();
}

class _DotState extends State<_Dot> with SingleTickerProviderStateMixin {
  AnimationController? _ctrl;

  @override
  void initState() {
    super.initState();
    if (widget.pulse) {
      _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))
        ..repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.dense ? 7.0 : 8.5;
    final core = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
    );
    if (!widget.pulse || _ctrl == null) return core;
    return SizedBox(
      width: size + 6,
      height: size + 6,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedBuilder(
            animation: _ctrl!,
            builder: (_, __) {
              final t = _ctrl!.value;
              return Container(
                width: size + 6 * t,
                height: size + 6 * t,
                decoration: BoxDecoration(
                  color: widget.color.withValues(alpha: 0.35 * (1 - t)),
                  shape: BoxShape.circle,
                ),
              );
            },
          ),
          core,
        ],
      ),
    );
  }
}
