import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_icons.dart';
import '../theme/app_theme.dart';
import 'severity_pill.dart';
import 'status_pill.dart';

/// Mobile-first incident tile.
///
/// Severity-coloured left stripe + soft glow on `new` incidents. The whole row
/// is tappable; quick acknowledge/resolve actions are shown inline when the
/// incident isn't resolved yet. Use within an `IncidentSwipeable` to add
/// swipe-to-acknowledge / swipe-to-resolve.
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

  String _capitalize(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isLight = theme.brightness == Brightness.light;
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
    final isNew = status == 'new';

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: () {
          if (onTap != null) HapticFeedback.selectionClick();
          onTap?.call();
        },
        borderRadius: BorderRadius.circular(18),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          decoration: BoxDecoration(
            color: selected
                ? AppTheme.brandTeal.withValues(alpha: isLight ? 0.06 : 0.10)
                : cs.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected
                  ? AppTheme.brandTeal.withValues(alpha: 0.45)
                  : cs.outlineVariant,
              width: selected ? 1.5 : 1.0,
            ),
            boxShadow: isNew
                ? [
                    BoxShadow(
                      color: stripeColor.withValues(alpha: 0.16),
                      blurRadius: 22,
                      offset: const Offset(0, 6),
                    ),
                  ]
                : [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: isLight ? 0.03 : 0.18),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
          ),
          child: IntrinsicHeight(
            child: Row(
              children: [
                // Severity stripe
                Container(
                  width: 5,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [stripeColor, stripeColor.withValues(alpha: 0.7)],
                    ),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(18),
                      bottomLeft: Radius.circular(18),
                    ),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Top row: icon + name + severity/status
                        Row(
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    stripeColor.withValues(alpha: 0.20),
                                    stripeColor.withValues(alpha: 0.10),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: stripeColor.withValues(alpha: 0.28)),
                              ),
                              child: Icon(
                                AppIcons.forEventType(eventType),
                                color: stripeColor,
                                size: 22,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    patientName,
                                    style: GoogleFonts.outfit(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 15,
                                      color: cs.onSurface,
                                      letterSpacing: -0.2,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _capitalize(eventType),
                                    style: GoogleFonts.dmSans(
                                      fontSize: 12.5,
                                      color: stripeColor,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            SeverityPill(severity: severity, dense: true),
                          ],
                        ),
                        const SizedBox(height: 12),
                        // Meta row: camera + time + status
                        Row(
                          children: [
                            Icon(AppIcons.cameras, size: 13, color: cs.onSurfaceVariant),
                            const SizedBox(width: 5),
                            Flexible(
                              child: Text(
                                cameraName,
                                style: GoogleFonts.dmSans(
                                  fontSize: 12,
                                  color: cs.onSurfaceVariant,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Icon(Icons.access_time_rounded, size: 13, color: cs.onSurfaceVariant),
                            const SizedBox(width: 4),
                            Text(
                              _formatTimeAgo(detectedAt),
                              style: GoogleFonts.dmSans(
                                fontSize: 12,
                                color: cs.onSurfaceVariant,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const Spacer(),
                            StatusPill.forIncidentStatus(status),
                          ],
                        ),
                        // Quick actions for new/acknowledged
                        if (status != 'resolved' && (onAcknowledge != null || onResolve != null)) ...[
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              if (status == 'new' && onAcknowledge != null)
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () {
                                      HapticFeedback.lightImpact();
                                      onAcknowledge!();
                                    },
                                    icon: const Icon(AppIcons.acknowledge, size: 14),
                                    label: const Text('Acknowledge'),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: AppTheme.brandTeal,
                                      side: BorderSide(color: AppTheme.brandTeal.withValues(alpha: 0.4)),
                                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                                      textStyle: GoogleFonts.outfit(fontWeight: FontWeight.w600, fontSize: 12),
                                    ),
                                  ),
                                ),
                              if (status == 'new' && onAcknowledge != null && onResolve != null)
                                const SizedBox(width: 8),
                              if (onResolve != null)
                                Expanded(
                                  child: FilledButton.icon(
                                    onPressed: () {
                                      HapticFeedback.lightImpact();
                                      onResolve!();
                                    },
                                    icon: const Icon(AppIcons.resolve, size: 14),
                                    label: const Text('Resolve'),
                                    style: FilledButton.styleFrom(
                                      backgroundColor: AppTheme.brandSage,
                                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                                      textStyle: GoogleFonts.outfit(fontWeight: FontWeight.w600, fontSize: 12),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ],
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
}
