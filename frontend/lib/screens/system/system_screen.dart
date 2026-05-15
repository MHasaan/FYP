import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/api_service.dart';
import '../../services/incident_stream_service.dart';
import '../../services/storage_service.dart';
import '../../theme/app_icons.dart';
import '../../widgets/eldercare_card.dart';
import '../../widgets/section_header.dart';
import '../../widgets/status_pill.dart';

class SystemScreen extends StatefulWidget {
  const SystemScreen({super.key});

  @override
  State<SystemScreen> createState() => _SystemScreenState();
}

class _SystemScreenState extends State<SystemScreen> {
  final ApiService _api = ApiService();
  Map<String, dynamic>? _health;
  bool _loadingHealth = false;

  @override
  void initState() {
    super.initState();
    _loadHealth();
  }

  Future<void> _loadHealth() async {
    setState(() => _loadingHealth = true);
    try {
      final h = await _api.checkHealth();
      if (mounted) setState(() => _health = h);
    } catch (_) {
      if (mounted) setState(() => _health = null);
    } finally {
      if (mounted) setState(() => _loadingHealth = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final stream = context.watch<IncidentStreamService>();
    final storage = context.watch<StorageService>();
    final mode = storage.themeMode;

    return ListView(
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 32),
      children: [
        SectionHeader(
          title: 'System',
          subtitle: 'Health, alerts, and global preferences',
          icon: AppIcons.system,
          trailing: IconButton.outlined(
            icon: const Icon(AppIcons.refresh, size: 18),
            onPressed: _loadHealth,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: EldercareCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Backend health',
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 12),
                if (_loadingHealth)
                  const LinearProgressIndicator()
                else if (_health == null)
                  Row(
                    children: [
                      const StatusPill(label: 'Offline', kind: StatusKind.danger),
                      const SizedBox(width: 8),
                      Text('Could not reach API', style: TextStyle(color: cs.onSurfaceVariant)),
                    ],
                  )
                else
                  Row(
                    children: [
                      const StatusPill(label: 'Online', kind: StatusKind.success),
                      const SizedBox(width: 8),
                      Text(
                        _health!['status']?.toString() ?? '',
                        style: TextStyle(color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    StatusPill(
                      label: stream.isLive ? 'Live alerts: WebSocket' : 'Live alerts: polling',
                      kind: stream.isLive ? StatusKind.success : StatusKind.warning,
                    ),
                    const SizedBox(width: 8),
                    Text('${stream.unresolvedCount} unresolved',
                        style: TextStyle(color: cs.onSurfaceVariant)),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: EldercareCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Appearance',
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 12),
                SegmentedButton<ThemeMode>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: ThemeMode.system, label: Text('System')),
                    ButtonSegment(value: ThemeMode.light, label: Text('Light')),
                    ButtonSegment(value: ThemeMode.dark, label: Text('Dark')),
                  ],
                  selected: {mode},
                  onSelectionChanged: (s) => storage.setThemeMode(s.first),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: EldercareCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Advanced modules',
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Text(
                  'Webhooks, schedules, push notifications, ROI editing, and recordings remain available through their REST endpoints. UI consolidation for these modules is planned in a follow-up.',
                  style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant, height: 1.5),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
