import 'package:flutter/material.dart';
import '../theme/app_icons.dart';
import '../theme/app_theme.dart';
import 'severity_pill.dart';
import 'status_pill.dart';

/// List row for incidents.
class IncidentTile extends StatelessWidget {
  final Map<String, dynamic> incident;
  final VoidCallback? onTap;
  final VoidCallback? onAcknowledge;
  final VoidCallback? onResolve;
  final bool selected;

  const IncidentTile({
    super.key,
    required this.incident,
    this.onTap,
    this.onAcknowledge,
    this.onResolve,
    this.selected = false,
  });

  String _formatTimeAgo(String? iso) {
    if (iso == null || iso.isEmpty) return '—';
    final dt = DateTime.tryParse(iso)?.toLocal();
    if (dt == null) return iso;
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final colors = theme.extension<IncidentSeverityColors>() ?? IncidentSeverityColors.light;
    final severity = (incident['severity'] as String?) ?? 'medium';
    final stripeColor = colors.forSeverity(severity);
    final eventType = (incident['event_type'] as String?) ?? 'manual';
    final status = (incident['status'] as String?) ?? 'new';
    final patientName = incident['patient_name']?.toString() ??
        (incident['patient_id'] != null ? 'Patient #${incident['patient_id']}' : 'Unknown patient');
    final cameraName = incident['camera_name']?.toString() ??
        (incident['camera_config_id'] != null ? 'Camera #${incident['camera_config_id']}' : '—');
    final detectedAt = incident['detected_at'] as String?;
    final confidence = incident['confidence'];
    final threshold = incident['threshold'];

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          decoration: BoxDecoration(
            color: selected ? cs.primaryContainer.withValues(alpha: 0.3) : cs.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? cs.primary : cs.outlineVariant,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: IntrinsicHeight(
            child: Row(
              children: [
                Container(
                  width: 4,
                  decoration: BoxDecoration(
                    color: stripeColor,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(12),
                      bottomLeft: Radius.circular(12),
                    ),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: stripeColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            AppIcons.forEventType(eventType),
                            color: stripeColor,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      patientName,
                                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    '· ${_capitalize(eventType)}',
                                    style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Icon(AppIcons.cameras, size: 12, color: cs.onSurfaceVariant),
                                  const SizedBox(width: 4),
                                  Flexible(
                                    child: Text(
                                      cameraName,
                                      style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Icon(Icons.access_time_rounded, size: 12, color: cs.onSurfaceVariant),
                                  const SizedBox(width: 4),
                                  Text(
                                    _formatTimeAgo(detectedAt),
                                    style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                                  ),
                                ],
                              ),
                              if (confidence != null) ...[
                                const SizedBox(height: 4),
                                Text(
                                  'Confidence: ${(confidence as num).toStringAsFixed(2)}'
                                  '${threshold != null ? "  ·  threshold ${(threshold as num).toStringAsFixed(2)}" : ""}',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: cs.onSurfaceVariant,
                                    fontFeatures: const [FontFeature.tabularFigures()],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SeverityPill(severity: severity, dense: true),
                                const SizedBox(width: 6),
                                StatusPill.forIncidentStatus(status),
                              ],
                            ),
                            if (status != 'resolved' && (onAcknowledge != null || onResolve != null)) ...[
                              const SizedBox(height: 6),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (status == 'new' && onAcknowledge != null)
                                    TextButton.icon(
                                      onPressed: onAcknowledge,
                                      icon: const Icon(AppIcons.acknowledge, size: 16),
                                      label: const Text('Ack'),
                                      style: TextButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        minimumSize: Size.zero,
                                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                      ),
                                    ),
                                  if (onResolve != null)
                                    TextButton.icon(
                                      onPressed: onResolve,
                                      icon: const Icon(AppIcons.resolve, size: 16),
                                      label: const Text('Resolve'),
                                      style: TextButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        minimumSize: Size.zero,
                                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _capitalize(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}
