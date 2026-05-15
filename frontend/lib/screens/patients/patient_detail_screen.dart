import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/api_service.dart';
import '../../services/auth_controller.dart';
import '../../theme/app_icons.dart';
import '../../widgets/eldercare_card.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/incident_tile.dart';
import '../../widgets/patient_avatar.dart';
import '../../widgets/role_badge.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/status_pill.dart';
import 'patient_form.dart';

class PatientDetailScreen extends StatefulWidget {
  final Map<String, dynamic> patient;
  const PatientDetailScreen({super.key, required this.patient});

  @override
  State<PatientDetailScreen> createState() => _PatientDetailScreenState();
}

class _PatientDetailScreenState extends State<PatientDetailScreen> with SingleTickerProviderStateMixin {
  late TabController _tabs;
  final ApiService _api = ApiService();
  late Map<String, dynamic> _patient;

  bool _loadingCameras = false;
  bool _loadingIncidents = false;
  List<Map<String, dynamic>> _cameras = [];
  List<Map<String, dynamic>> _incidents = [];

  @override
  void initState() {
    super.initState();
    _patient = widget.patient;
    _tabs = TabController(length: 3, vsync: this);
    _loadCameras();
    _loadIncidents();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _refreshPatient() async {
    try {
      final all = await _api.getPatients();
      final me = all.cast<Map<String, dynamic>>().firstWhere(
            (p) => p['id'] == _patient['id'],
            orElse: () => _patient,
          );
      setState(() => _patient = me);
    } catch (_) {}
  }

  Future<void> _loadCameras() async {
    setState(() => _loadingCameras = true);
    try {
      final cams = await _api.getCameraConfigs();
      final mine = cams.cast<Map<String, dynamic>>().where((c) => c['patient_id'] == _patient['id']).toList();
      if (mounted) setState(() {
        _cameras = mine;
        _loadingCameras = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingCameras = false);
    }
  }

  Future<void> _loadIncidents() async {
    setState(() => _loadingIncidents = true);
    try {
      final resp = await _api.getIncidents(patientId: _patient['id'] as int, limit: 50);
      final items = ((resp['items'] as List?) ?? const []).cast<Map<String, dynamic>>();
      if (mounted) setState(() {
        _incidents = items;
        _loadingIncidents = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingIncidents = false);
    }
  }

  Future<void> _edit() async {
    final result = await PatientFormDialog.show(context, existing: _patient);
    if (result == true) await _refreshPatient();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final auth = context.watch<AuthController>();
    final canEdit = auth.isCareTeam;

    return Scaffold(
      appBar: AppBar(
        title: Text(_patient['full_name']?.toString() ?? 'Patient'),
        actions: [
          if (canEdit)
            TextButton.icon(
              onPressed: _edit,
              icon: const Icon(AppIcons.edit, size: 16),
              label: const Text('Edit'),
            ),
          const SizedBox(width: 8),
        ],
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'Overview'),
            Tab(text: 'Cameras'),
            Tab(text: 'Incidents'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _buildOverview(theme, cs),
          _buildCameras(),
          _buildIncidents(),
        ],
      ),
    );
  }

  Widget _buildOverview(ThemeData theme, ColorScheme cs) {
    final p = _patient;
    final dobStr = p['date_of_birth']?.toString();
    final dob = dobStr == null ? null : DateTime.tryParse(dobStr);
    final age = dob == null ? null : (DateTime.now().difference(dob).inDays ~/ 365);

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        EldercareCard(
          child: Row(
            children: [
              PatientAvatar(name: p['full_name']?.toString(), size: 64),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p['full_name']?.toString() ?? 'Unknown',
                      style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      [
                        if (age != null) '$age yrs',
                        if (p['gender'] != null && p['gender'] != 'prefer_not_to_say') p['gender'].toString(),
                      ].join(' · '),
                      style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      children: [
                        if (p['fall_risk'] != null && p['fall_risk'] != 'none')
                          StatusPill(label: 'Fall: ${p['fall_risk']}', kind: StatusKind.danger, icon: AppIcons.fall, dense: true),
                        if (p['seizure_risk'] != null && p['seizure_risk'] != 'none')
                          StatusPill(label: 'Seizure: ${p['seizure_risk']}', kind: StatusKind.warning, icon: AppIcons.seizure, dense: true),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        EldercareCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Profile', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              _row('Date of birth', dob == null ? '—' : '${dob.year}-${dob.month.toString().padLeft(2, '0')}-${dob.day.toString().padLeft(2, '0')}'),
              _row('Gender', p['gender']?.toString() ?? '—'),
              _row('Address', p['address']?.toString() ?? '—'),
              _row('Risk notes', p['risk_notes']?.toString() ?? '—'),
            ],
          ),
        ),
        const SizedBox(height: 16),
        EldercareCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Primary contact', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              _row('Name', p['primary_contact_name']?.toString() ?? '—'),
              _row('Phone', p['primary_contact_phone']?.toString() ?? '—'),
              _row('Email', p['primary_contact_email']?.toString() ?? '—'),
            ],
          ),
        ),
        const SizedBox(height: 16),
        EldercareCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Care team', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              Row(
                children: [
                  const RoleBadge(role: 'caregiver'),
                  const SizedBox(width: 8),
                  Text(p['caregiver_id'] == null ? 'Unassigned' : 'Caregiver #${p['caregiver_id']}'),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const RoleBadge(role: 'patient_relative'),
                  const SizedBox(width: 8),
                  Text(p['relative_user_id'] == null ? 'No family user linked' : 'User #${p['relative_user_id']}'),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _row(String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(k, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          ),
          Expanded(child: Text(v, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }

  Widget _buildCameras() {
    if (_loadingCameras) return const SkeletonList(count: 4);
    if (_cameras.isEmpty) {
      return const EmptyState(
        icon: AppIcons.cameras,
        title: 'No cameras assigned',
        subtitle: 'Assign cameras from the Cameras screen to start monitoring this patient.',
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(24),
      itemCount: _cameras.length,
      itemBuilder: (_, i) {
        final c = _cameras[i];
        return EldercareCard(
          margin: const EdgeInsets.only(bottom: 12),
          child: Row(
            children: [
              const Icon(AppIcons.cameras, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(c['name']?.toString() ?? 'Camera', style: const TextStyle(fontWeight: FontWeight.w700)),
                    if (c['location'] != null && c['location'].toString().isNotEmpty)
                      Text(c['location'].toString(), style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12)),
                  ],
                ),
              ),
              Text(c['source_type']?.toString() ?? '—', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildIncidents() {
    if (_loadingIncidents) return const SkeletonList(count: 5);
    if (_incidents.isEmpty) {
      return const EmptyState(
        icon: AppIcons.incidents,
        title: 'No incidents on record',
        subtitle: 'When alerts trigger for this patient, they will appear here.',
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(24),
      itemCount: _incidents.length,
      itemBuilder: (_, i) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: IncidentTile(incident: _incidents[i]),
      ),
    );
  }
}
