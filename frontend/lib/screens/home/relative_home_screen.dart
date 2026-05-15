import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/api_service.dart';
import '../../services/auth_controller.dart';
import '../../services/incident_stream_service.dart';
import '../../theme/app_icons.dart';
import '../../widgets/eldercare_card.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/incident_tile.dart';
import '../../widgets/patient_avatar.dart';
import '../../widgets/section_header.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/status_pill.dart';

/// Home screen for the patient_relative role.
class RelativeHomeScreen extends StatefulWidget {
  const RelativeHomeScreen({super.key});

  @override
  State<RelativeHomeScreen> createState() => _RelativeHomeScreenState();
}

class _RelativeHomeScreenState extends State<RelativeHomeScreen> {
  final ApiService _api = ApiService();
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _patients = [];
  List<Map<String, dynamic>> _incidents = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final patients = await _api.getPatients();
      final ps = patients.cast<Map<String, dynamic>>();
      List<Map<String, dynamic>> incidents = [];
      if (ps.isNotEmpty) {
        final resp = await _api.getIncidents(limit: 25);
        incidents = ((resp['items'] as List?) ?? const []).cast<Map<String, dynamic>>();
      }
      if (mounted) {
        setState(() {
          _patients = ps;
          _incidents = incidents;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Could not load family overview: $e';
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final auth = context.watch<AuthController>();
    final stream = context.watch<IncidentStreamService>();

    return Column(
      children: [
        SectionHeader(
          title: 'Hello, ${auth.fullName.split(' ').first}',
          subtitle: 'Your family member\'s monitoring at a glance',
          icon: AppIcons.home,
          trailing: IconButton.outlined(
            icon: const Icon(AppIcons.refresh, size: 18),
            onPressed: _load,
          ),
        ),
        Expanded(
          child: _loading
              ? const SkeletonList(count: 4)
              : _error != null
                  ? Center(child: Text(_error!, style: TextStyle(color: cs.error)))
                  : _patients.isEmpty
                      ? const EmptyState(
                          icon: AppIcons.patients,
                          title: 'Not yet linked',
                          subtitle: 'Ask the administrator to link your account to a patient profile.',
                        )
                      : ListView(
                          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                          children: [
                            for (final p in _patients) _PatientCard(patient: p),
                            const SizedBox(height: 16),
                            EldercareCard(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(AppIcons.incidents, color: cs.primary),
                                      const SizedBox(width: 8),
                                      Text('Recent alerts',
                                          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                                      const Spacer(),
                                      if (stream.unresolvedCount > 0)
                                        StatusPill(
                                          label: '${stream.unresolvedCount} new',
                                          kind: StatusKind.danger,
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  if (_incidents.isEmpty)
                                    Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 24),
                                      child: Center(
                                        child: Text('No alerts. All quiet.',
                                            style: TextStyle(color: cs.onSurfaceVariant)),
                                      ),
                                    )
                                  else
                                    for (final i in _incidents.take(10))
                                      Padding(
                                        padding: const EdgeInsets.only(bottom: 8),
                                        child: IncidentTile(incident: i),
                                      ),
                                ],
                              ),
                            ),
                          ],
                        ),
        ),
      ],
    );
  }
}

class _PatientCard extends StatelessWidget {
  final Map<String, dynamic> patient;
  const _PatientCard({required this.patient});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: EldercareCard(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            PatientAvatar(name: patient['full_name']?.toString(), size: 56),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    patient['full_name']?.toString() ?? 'Unknown',
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    children: [
                      if (patient['fall_risk'] != null && patient['fall_risk'] != 'none')
                        StatusPill(
                          label: 'Fall: ${patient['fall_risk']}',
                          icon: AppIcons.fall,
                          kind: StatusKind.danger,
                          dense: true,
                        ),
                      if (patient['seizure_risk'] != null && patient['seizure_risk'] != 'none')
                        StatusPill(
                          label: 'Seizure: ${patient['seizure_risk']}',
                          icon: AppIcons.seizure,
                          kind: StatusKind.warning,
                          dense: true,
                        ),
                      if ((patient['fall_risk'] == null || patient['fall_risk'] == 'none') &&
                          (patient['seizure_risk'] == null || patient['seizure_risk'] == 'none'))
                        const StatusPill(label: 'No risk flags', kind: StatusKind.success, dense: true),
                    ],
                  ),
                  if (patient['risk_notes'] != null && patient['risk_notes'].toString().isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      patient['risk_notes'].toString(),
                      style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
