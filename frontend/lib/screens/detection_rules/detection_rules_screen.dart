import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/api_service.dart';
import '../../services/auth_controller.dart';
import '../../theme/app_icons.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/eldercare_card.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/section_header.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/status_pill.dart';
import 'rule_form.dart';

class DetectionRulesScreen extends StatefulWidget {
  const DetectionRulesScreen({super.key});

  @override
  State<DetectionRulesScreen> createState() => _DetectionRulesScreenState();
}

class _DetectionRulesScreenState extends State<DetectionRulesScreen> {
  final ApiService _api = ApiService();
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _rules = [];
  List<Map<String, dynamic>> _cameras = [];
  List<Map<String, dynamic>> _patients = [];

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
      final results = await Future.wait([
        _api.getDetectionSettings(),
        _api.getCameraConfigs(),
        _api.getPatients(),
      ]);
      if (mounted) {
        setState(() {
          _rules = (results[0]).cast<Map<String, dynamic>>();
          _cameras = (results[1]).cast<Map<String, dynamic>>();
          _patients = (results[2]).cast<Map<String, dynamic>>();
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Could not load detection rules: $e';
          _loading = false;
        });
      }
    }
  }

  Future<void> _openCreate() async {
    final res = await DetectionRuleFormDialog.show(
      context,
      cameras: _cameras,
      patients: _patients,
    );
    if (res == true) await _load();
  }

  Future<void> _openEdit(Map<String, dynamic> rule) async {
    final res = await DetectionRuleFormDialog.show(
      context,
      existing: rule,
      cameras: _cameras,
      patients: _patients,
    );
    if (res == true) await _load();
  }

  Future<void> _delete(Map<String, dynamic> rule) async {
    final confirm = await showConfirmDialog(
      context,
      title: 'Delete this rule?',
      message: 'Detection will fall back to a higher-scope rule (or the global default).',
      confirmLabel: 'Delete',
      destructive: true,
      icon: AppIcons.delete,
    );
    if (!confirm) return;
    try {
      await _api.deleteDetectionSetting(rule['id'] as int);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    }
  }

  String _scopeLabel(Map<String, dynamic> r) {
    final cid = r['camera_config_id'];
    final pid = r['patient_id'];
    if (cid != null) {
      final cam = _cameras.firstWhere(
        (c) => c['id'] == cid,
        orElse: () => <String, dynamic>{},
      );
      return 'Camera: ${cam['name']?.toString() ?? '#$cid'}';
    }
    if (pid != null) {
      final p = _patients.firstWhere(
        (p) => p['id'] == pid,
        orElse: () => <String, dynamic>{},
      );
      return 'Patient: ${p['full_name']?.toString() ?? '#$pid'}';
    }
    return 'Global default';
  }

  StatusKind _scopeKind(Map<String, dynamic> r) {
    if (r['camera_config_id'] != null) return StatusKind.primary;
    if (r['patient_id'] != null) return StatusKind.info;
    return StatusKind.neutral;
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final canManage = auth.isCareTeam;
    final cs = Theme.of(context).colorScheme;

    return Column(
      children: [
        SectionHeader(
          title: 'Detection rules',
          subtitle: 'Sensitivity, fall and seizure thresholds, per-camera or per-patient',
          icon: AppIcons.detectionRules,
          trailing: canManage
              ? FilledButton.icon(
                  onPressed: _openCreate,
                  icon: const Icon(AppIcons.add, size: 18),
                  label: const Text('Add rule'),
                )
              : null,
        ),
        Expanded(
          child: _loading
              ? const SkeletonList(count: 5)
              : _error != null
                  ? Center(child: Text(_error!, style: TextStyle(color: cs.error)))
                  : _rules.isEmpty
                      ? EmptyState(
                          icon: AppIcons.detectionRules,
                          title: 'No rules yet',
                          subtitle: 'Add a global default first, then narrow per camera or patient.',
                          actionLabel: canManage ? 'Add first rule' : null,
                          onAction: canManage ? _openCreate : null,
                          actionIcon: AppIcons.add,
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                          itemCount: _rules.length,
                          itemBuilder: (_, i) {
                            final r = _rules[i];
                            final fallEnabled = r['fall_enabled'] != false;
                            final seizEnabled = r['seizure_enabled'] != false;
                            final fallTh = (r['fall_threshold'] as num?)?.toDouble();
                            final seizTh = (r['seizure_threshold'] as num?)?.toDouble();
                            final sens = (r['sensitivity'] as num?)?.toDouble();
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: EldercareCard(
                                onTap: canManage ? () => _openEdit(r) : null,
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: cs.primaryContainer,
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Icon(AppIcons.detectionRules, color: cs.onPrimaryContainer, size: 20),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              StatusPill(label: _scopeLabel(r), kind: _scopeKind(r), dense: true),
                                              const SizedBox(width: 8),
                                              if (sens != null)
                                                Text('Sensitivity ${sens.toStringAsFixed(2)}',
                                                    style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
                                            ],
                                          ),
                                          const SizedBox(height: 6),
                                          Wrap(
                                            spacing: 8,
                                            runSpacing: 4,
                                            children: [
                                              StatusPill(
                                                label: fallEnabled
                                                    ? 'Fall: ${fallTh?.toStringAsFixed(2) ?? '—'}'
                                                    : 'Fall off',
                                                kind: fallEnabled ? StatusKind.danger : StatusKind.neutral,
                                                icon: AppIcons.fall,
                                                dense: true,
                                              ),
                                              StatusPill(
                                                label: seizEnabled
                                                    ? 'Seizure: ${seizTh?.toStringAsFixed(2) ?? '—'}'
                                                    : 'Seizure off',
                                                kind: seizEnabled ? StatusKind.warning : StatusKind.neutral,
                                                icon: AppIcons.seizure,
                                                dense: true,
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (canManage)
                                      IconButton(
                                        icon: const Icon(AppIcons.delete, size: 18),
                                        color: cs.error,
                                        onPressed: () => _delete(r),
                                      ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
        ),
      ],
    );
  }
}
