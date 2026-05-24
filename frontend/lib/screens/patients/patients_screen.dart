import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../services/api_service.dart';
import '../../services/auth_controller.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_theme.dart';
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
    HapticFeedback.lightImpact();
    final result = await PatientFormDialog.show(context);
    if (result == true) await _load();
  }

  Future<void> _openEdit(Map<String, dynamic> p) async {
    final result = await PatientFormDialog.show(context, existing: p);
    if (result == true) await _load();
  }

  Future<void> _openDetail(Map<String, dynamic> p) async {
    HapticFeedback.selectionClick();
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
    final cs = Theme.of(context).colorScheme;
    final filtered = _filtered;
    final isWide = MediaQuery.of(context).size.width > 800;

    return Column(
      children: [
        SectionHeader(
          title: 'Patients',
          subtitle: 'Profiles, risk attributes, and contact details',
          icon: AppIcons.patients,
          trailing: canManage
              ? IconButton.filled(
                  style: IconButton.styleFrom(
                    backgroundColor: AppTheme.brandTeal,
                    foregroundColor: Colors.white,
                  ),
                  tooltip: 'Add patient',
                  icon: const Icon(AppIcons.add, size: 20),
                  onPressed: _openCreate,
                )
              : null,
        ),

        // Search + risk filter
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Column(
            children: [
              TextField(
                controller: _searchCtrl,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  prefixIcon: Icon(AppIcons.search, size: 18),
                  hintText: 'Search by name',
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _RiskChip(
                      label: 'All',
                      icon: AppIcons.patients,
                      selected: _riskFilter == 'all',
                      onTap: () => setState(() => _riskFilter = 'all'),
                    ),
                    const SizedBox(width: 8),
                    _RiskChip(
                      label: 'Fall risk',
                      icon: AppIcons.fall,
                      color: cs.error,
                      selected: _riskFilter == 'fall',
                      onTap: () => setState(() => _riskFilter = 'fall'),
                    ),
                    const SizedBox(width: 8),
                    _RiskChip(
                      label: 'Seizure risk',
                      icon: AppIcons.seizure,
                      color: AppTheme.brandAmber,
                      selected: _riskFilter == 'seizure',
                      onTap: () => setState(() => _riskFilter = 'seizure'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        Expanded(
          child: _loading
              ? const SkeletonList(count: 6)
              : _error != null
                  ? Center(child: Text(_error!, style: TextStyle(color: cs.error)))
                  : _patients.isEmpty
                      ? EmptyState(
                          icon: AppIcons.patients,
                          title: 'No patients yet',
                          subtitle: 'Add your first patient profile to start monitoring.',
                          actionLabel: canManage ? 'Add patient' : null,
                          onAction: canManage ? _openCreate : null,
                          actionIcon: AppIcons.add,
                        )
                      : filtered.isEmpty
                          ? const EmptyState(
                              icon: AppIcons.search,
                              title: 'No matches',
                              subtitle: 'Try a different search or filter.',
                            )
                          : RefreshIndicator(
                              color: AppTheme.brandTeal,
                              onRefresh: () async {
                                HapticFeedback.mediumImpact();
                                await _load();
                              },
                              child: isWide
                                  ? GridView.builder(
                                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                                      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                                        maxCrossAxisExtent: 360,
                                        mainAxisSpacing: 12,
                                        crossAxisSpacing: 12,
                                        mainAxisExtent: 110,
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
                                        )
                                            .animate()
                                            .fadeIn(duration: 260.ms, delay: (i * 25).ms)
                                            .slideY(begin: 0.06, duration: 320.ms);
                                      },
                                    )
                                  : ListView.builder(
                                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                                      itemCount: filtered.length,
                                      itemBuilder: (_, i) {
                                        final p = filtered[i];
                                        return Padding(
                                          padding: const EdgeInsets.only(bottom: 10),
                                          child: _PatientCard(
                                            patient: p,
                                            canManage: canManage,
                                            onOpen: () => _openDetail(p),
                                            onEdit: () => _openEdit(p),
                                            onDelete: () => _delete(p),
                                          )
                                              .animate()
                                              .fadeIn(duration: 260.ms, delay: (i * 25).ms)
                                              .slideY(begin: 0.06, duration: 320.ms),
                                        );
                                      },
                                    ),
                            ),
        ),
      ],
    );
  }
}

class _RiskChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color? color;
  final bool selected;
  final VoidCallback onTap;

  const _RiskChip({
    required this.label,
    required this.icon,
    this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final accent = color ?? AppTheme.brandTeal;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? accent.withValues(alpha: 0.14) : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? accent : cs.outlineVariant,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: selected ? accent : cs.onSurfaceVariant),
            const SizedBox(width: 6),
            Text(
              label,
              style: GoogleFonts.outfit(
                fontWeight: FontWeight.w600,
                fontSize: 12.5,
                color: selected ? accent : cs.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

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
    if (dobStr == null) return '';
    final dob = DateTime.tryParse(dobStr);
    if (dob == null) return '';
    final age = DateTime.now().difference(dob).inDays ~/ 365;
    return '$age yrs';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fall = patient['fall_risk'] as String?;
    final seiz = patient['seizure_risk'] as String?;
    final hasRisk = (fall != null && fall != 'none') || (seiz != null && seiz != 'none');
    final age = _ageString();

    return EldercareCard(
      onTap: onOpen,
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          PatientAvatar(name: patient['full_name']?.toString(), size: 52),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  patient['full_name']?.toString() ?? 'Unknown',
                  style: GoogleFonts.outfit(
                    fontWeight: FontWeight.w700,
                    fontSize: 15.5,
                    color: cs.onSurface,
                    letterSpacing: -0.2,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (age.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    age,
                    style: GoogleFonts.dmSans(
                      fontSize: 12,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Wrap(
                  spacing: 5,
                  runSpacing: 4,
                  children: [
                    if (fall != null && fall != 'none')
                      StatusPill(label: 'Fall: $fall', kind: _riskKind(fall), icon: AppIcons.fall, dense: true),
                    if (seiz != null && seiz != 'none')
                      StatusPill(label: 'Seizure: $seiz', kind: _riskKind(seiz), icon: AppIcons.seizure, dense: true),
                    if (!hasRisk)
                      const StatusPill(label: 'No risk flags', kind: StatusKind.success, dense: true),
                  ],
                ),
              ],
            ),
          ),
          if (canManage)
            PopupMenuButton<String>(
              icon: Icon(AppIcons.more, size: 20, color: cs.onSurfaceVariant),
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
