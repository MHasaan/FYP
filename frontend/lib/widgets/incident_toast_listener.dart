import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/incident_stream_service.dart';
import '../theme/app_icons.dart';
import '../theme/app_theme.dart';

/// Top-anchored animated banner that slides in whenever a new incident event
/// arrives via [IncidentStreamService.newIncidentStream]. Replaces the basic
/// SnackBar treatment.
class IncidentToastListener extends StatefulWidget {
  final Widget child;
  const IncidentToastListener({super.key, required this.child});

  @override
  State<IncidentToastListener> createState() => _IncidentToastListenerState();
}

class _IncidentToastListenerState extends State<IncidentToastListener>
    with SingleTickerProviderStateMixin {
  StreamSubscription<Map<String, dynamic>>? _sub;
  late final AnimationController _ctrl;
  Map<String, dynamic>? _current;
  Timer? _dismissTimer;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final stream = context.read<IncidentStreamService>();
      _sub = stream.newIncidentStream.listen(_onIncident);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _dismissTimer?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _onIncident(Map<String, dynamic> e) {
    if (!mounted) return;
    setState(() => _current = e);
    _ctrl.forward(from: 0);
    _dismissTimer?.cancel();
    _dismissTimer = Timer(const Duration(seconds: 5), _dismiss);
  }

  void _dismiss() {
    if (!mounted) return;
    _ctrl.reverse().whenComplete(() {
      if (mounted) setState(() => _current = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (_current != null)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, -1.4),
                    end: Offset.zero,
                  ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic)),
                  child: FadeTransition(
                    opacity: _ctrl,
                    child: _Banner(
                      incident: _current!,
                      onDismiss: _dismiss,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _Banner extends StatelessWidget {
  final Map<String, dynamic> incident;
  final VoidCallback onDismiss;

  const _Banner({required this.incident, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<IncidentSeverityColors>() ?? IncidentSeverityColors.light;
    final color = colors.forSeverity(incident['severity'] as String?);
    final patient = incident['patient_name']?.toString() ?? 'a patient';
    final eventType = (incident['event_type'] as String?)?.toUpperCase() ?? 'ALERT';
    final cameraName = incident['camera_name']?.toString();

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Material(
          elevation: 6,
          shadowColor: color.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(14),
          color: Colors.white,
          clipBehavior: Clip.antiAlias,
          child: IntrinsicHeight(
            child: Row(
              children: [
                Container(width: 6, color: color),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    child: Row(
                      children: [
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            AppIcons.forEventType(incident['event_type'] as String?),
                            color: color,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '$eventType detected — $patient',
                                style: const TextStyle(
                                  color: Colors.black,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (cameraName != null) ...[
                                const SizedBox(height: 2),
                                Text(
                                  cameraName,
                                  style: TextStyle(
                                    color: Colors.black.withValues(alpha: 0.6),
                                    fontSize: 12,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, size: 18, color: Colors.black54),
                          onPressed: onDismiss,
                          tooltip: 'Dismiss',
                          visualDensity: VisualDensity.compact,
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
}
