import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/api_service.dart';
import '../../services/auth_controller.dart';
import '../../theme/app_icons.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/eldercare_card.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/patient_avatar.dart';
import '../../widgets/section_header.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/status_pill.dart';
import 'patient_detail_screen.dart';
import 'patient_form.dart';

class PatientsScreen extends StatefulWidget {
  const PatientsScreen({super.key});

  @override
  State<PatientsScreen> createState() => _PatientsScreenState();
}

class _PatientsScreenState extends State<PatientsScreen> {
  final ApiService _api = ApiService();
  final TextEditingController _searchCtrl = TextEditingController();
  bool _loading = false;
  String? _error;
  List<Map<String, dynamic>> _patients = [];
  String _riskFilter = 'all';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final patients = await _api.getPatients();
      if (mounted) {
        setState(() {
          _patients = patients.cast<Map<String, dynamic>>();
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Could not load patients: $e';
          _loading = false;
        });
      }
    }
  }

  List<Map<String, dynamic>> get _filtered {
    final q = _searchCtrl.text.trim().toLowerCase();
    return _patients.where((p) {
      final name = (p['full_name']?.toString() ?? '').toLowerCase();
      if (q.isNotEmpty && !name.contains(q)) return false;
      if (_riskFilter == 'fall' && (p['fall_risk'] == null || p['fall_risk'] == 'none')) return false;
      if (_riskFilter == 'seizure' && (p['seizure_risk'] == null || p['seizure_risk'] == 'none')) return false;
      return true;
    }).toList();
  }

  Future<void> _openCreate() async {
    final result = await PatientFormDialog.show(context);
    if (result == true) await _load();
  }

  Future<void> _openEdit(Map<String, dynamic> p) async {
    final result = await PatientFormDialog.show(context, existing: p);
    if (result == true) await _load();
  }

  Future<void> _openDetail(Map<String, dynamic> p) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PatientDetailScreen(patient: p),
    ));
    _load();
  }

  Future<void> _delete(Map<String, dynamic> p) async {
    final confirm = await showConfirmDialog(
      context,
      title: 'Delete patient?',
      message: 'This removes the profile and unlinks any cameras. Existing incidents are kept for audit.',
      confirmLabel: 'Delete',
      destructive: true,
      icon: AppIcons.delete,
    );
    if (!confirm) return;
    try {
      await _api.deletePatient(p['id'] as int);
      await _load();
    } catch (e) {
      _showError('Failed to delete: $e');
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final canManage = auth.isCareTeam;

    return Column(
      children: [
        SectionHeader(
          title: 'Patients',
          subtitle: 'Profiles, risk attributes, and contact details',
          icon: AppIcons.patients,
          trailing: canManage
              ? FilledButton.icon(
                  onPressed: _openCreate,
                  icon: const Icon(AppIcons.add, size: 18),
                  label: const Text('Add patient'),
                )
              : null,
        ),
        _Toolbar(
          searchCtrl: _searchCtrl,
          riskFilter: _riskFilter,
          onSearch: () => setState(() {}),
          onRiskChanged: (v) => setState(() => _riskFilter = v),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: _loading
              ? const SkeletonList(count: 6)
              : _error != null
                  ? Center(child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)))
                  : _patients.isEmpty
                      ? EmptyState(
                          icon: AppIcons.patients,
                          title: 'No patients yet',
                          subtitle: 'Add your first patient profile to start monitoring.',
                          actionLabel: canManage ? 'Add patient' : null,
                          onAction: canManage ? _openCreate : null,
                          actionIcon: AppIcons.add,
                        )
                      : LayoutBuilder(
                          builder: (_, c) {
                            final crossAxis = c.maxWidth > 1200 ? 3 : c.maxWidth > 800 ? 2 : 1;
                            final filtered = _filtered;
                            if (filtered.isEmpty) {
                              return const EmptyState(
                                icon: AppIcons.search,
                                title: 'No matches',
                                subtitle: 'No patients match your filters.',
                              );
                            }
                            return GridView.builder(
                              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: crossAxis,
                                mainAxisSpacing: 12,
                                crossAxisSpacing: 12,
                                mainAxisExtent: 168,
                              ),
                              itemCount: filtered.length,
                              itemBuilder: (_, i) {
                                final p = filtered[i];
                                return _PatientCard(
                                  patient: p,
                                  canManage: canManage,
                                  onOpen: () => _openDetail(p),
                                  onEdit: () => _openEdit(p),
                                  onDelete: () => _delete(p),
                                );
                              },
                            );
                          },
                        ),
        ),
      ],
    );
  }
}

// ── toolbar ─────────────────────────────────────────────────────────────────
class _Toolbar extends StatelessWidget {
  final TextEditingController searchCtrl;
  final String riskFilter;
  final VoidCallback onSearch;
  final ValueChanged<String> onRiskChanged;

  const _Toolbar({
    required this.searchCtrl,
    required this.riskFilter,
    required this.onSearch,
    required this.onRiskChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 0),
      child: EldercareCard(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: searchCtrl,
                onChanged: (_) => onSearch(),
                decoration: const InputDecoration(
                  prefixIcon: Icon(AppIcons.search, size: 18),
                  hintText: 'Search by name',
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 220,
              child: DropdownButtonFormField<String>(
                value: riskFilter,
                decoration: const InputDecoration(labelText: 'Risk', isDense: true),
                items: const [
                  DropdownMenuItem(value: 'all', child: Text('Any risk profile')),
                  DropdownMenuItem(value: 'fall', child: Text('Fall risk')),
                  DropdownMenuItem(value: 'seizure', child: Text('Seizure risk')),
                ],
                onChanged: (v) => onRiskChanged(v ?? 'all'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── card ────────────────────────────────────────────────────────────────────
class _PatientCard extends StatelessWidget {
  final Map<String, dynamic> patient;
  final bool canManage;
  final VoidCallback onOpen;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _PatientCard({
    required this.patient,
    required this.canManage,
    required this.onOpen,
    required this.onEdit,
    required this.onDelete,
  });

  String _ageString() {
    final dobStr = patient['date_of_birth']?.toString();
    if (dobStr == null) return '—';
    final dob = DateTime.tryParse(dobStr);
    if (dob == null) return '—';
    final age = DateTime.now().difference(dob).inDays ~/ 365;
    return '$age yrs';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final fall = patient['fall_risk'] as String?;
    final seiz = patient['seizure_risk'] as String?;

    return EldercareCard(
      onTap: onOpen,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              PatientAvatar(name: patient['full_name']?.toString(), size: 44),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      patient['full_name']?.toString() ?? 'Unknown',
                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _ageString(),
                      style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              if (canManage)
                PopupMenuButton<String>(
                  icon: const Icon(AppIcons.more, size: 18),
                  onSelected: (v) {
                    if (v == 'edit') onEdit();
                    if (v == 'delete') onDelete();
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'edit', child: Text('Edit')),
                    PopupMenuItem(value: 'delete', child: Text('Delete')),
                  ],
                ),
            ],
          ),
          const Spacer(),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              if (fall != null && fall != 'none')
                StatusPill(label: 'Fall: $fall', kind: _riskKind(fall), icon: AppIcons.fall, dense: true),
              if (seiz != null && seiz != 'none')
                StatusPill(label: 'Seizure: $seiz', kind: _riskKind(seiz), icon: AppIcons.seizure, dense: true),
              if ((fall == null || fall == 'none') && (seiz == null || seiz == 'none'))
                const StatusPill(label: 'No risk flags', kind: StatusKind.success, dense: true),
            ],
          ),
        ],
      ),
    );
  }

  StatusKind _riskKind(String? r) {
    switch (r) {
      case 'high': return StatusKind.danger;
      case 'medium': return StatusKind.warning;
      case 'low': return StatusKind.info;
      default: return StatusKind.neutral;
    }
  }
}
