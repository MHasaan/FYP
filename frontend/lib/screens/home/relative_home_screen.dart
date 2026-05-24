import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../services/api_service.dart';
import '../../services/auth_controller.dart';
import '../../services/incident_stream_service.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_theme.dart';
import '../../widgets/eldercare_card.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/gradient_orbs.dart';
import '../../widgets/incident_tile.dart';
import '../../widgets/patient_avatar.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/status_pill.dart';

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
    final cs = Theme.of(context).colorScheme;
    final auth = context.watch<AuthController>();
    final stream = context.watch<IncidentStreamService>();
    final firstName = auth.fullName.split(' ').first;

    return RefreshIndicator(
      color: AppTheme.brandTeal,
      onRefresh: () async {
        HapticFeedback.mediumImpact();
        await _load();
      },
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: _Hero(
              firstName: firstName,
              unresolved: stream.unresolvedCount,
            ),
          ),

          if (_loading)
            const SliverPadding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 24),
              sliver: SliverToBoxAdapter(child: SkeletonList(count: 4)),
            )
          else if (_error != null)
            SliverFillRemaining(
              child: Center(child: Text(_error!, style: TextStyle(color: cs.error))),
            )
          else if (_patients.isEmpty)
            const SliverFillRemaining(
              child: EmptyState(
                icon: AppIcons.patients,
                title: 'Not yet linked',
                subtitle: 'Ask the administrator to link your account to a patient profile.',
              ),
            )
          else ...[
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              sliver: SliverList.builder(
                itemCount: _patients.length,
                itemBuilder: (_, i) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _PatientCard(patient: _patients[i])
                        .animate()
                        .fadeIn(duration: 260.ms, delay: (i * 70).ms)
                        .slideY(begin: 0.08, duration: 320.ms, curve: Curves.easeOutCubic),
                  );
                },
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              sliver: SliverToBoxAdapter(
                child: EldercareCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(AppIcons.incidents, color: AppTheme.brandTeal, size: 18),
                          const SizedBox(width: 8),
                          Text(
                            'Recent alerts',
                            style: GoogleFonts.outfit(fontWeight: FontWeight.w700, fontSize: 15),
                          ),
                          const Spacer(),
                          if (stream.unresolvedCount > 0)
                            StatusPill(
                              label: '${stream.unresolvedCount} new',
                              kind: StatusKind.danger,
                              pulse: true,
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (_incidents.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 24),
                          child: Center(
                            child: Text(
                              'No alerts. All quiet.',
                              style: GoogleFonts.dmSans(color: cs.onSurfaceVariant),
                            ),
                          ),
                        )
                      else
                        for (final inc in _incidents.take(10))
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: IncidentTile(incident: inc),
                          ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  final String firstName;
  final int unresolved;

  const _Hero({required this.firstName, required this.unresolved});

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 18) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(
          height: 220,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF01949A), Color(0xFF3D8D7A)],
            ),
            borderRadius: BorderRadius.only(
              bottomLeft: Radius.circular(28),
              bottomRight: Radius.circular(28),
            ),
          ),
        ),
        ClipRRect(
          borderRadius: const BorderRadius.only(
            bottomLeft: Radius.circular(28),
            bottomRight: Radius.circular(28),
          ),
          child: SizedBox(height: 220, width: double.infinity, child: GradientOrbs.brand()),
        ),
        SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 28, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _greeting(),
                  style: GoogleFonts.dmSans(
                    color: Colors.white.withValues(alpha: 0.78),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  firstName.isEmpty ? 'Hello' : firstName,
                  style: GoogleFonts.cormorantGaramond(
                    fontSize: 38,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    height: 1.0,
                    letterSpacing: -0.5,
                  ),
                ).animate().fadeIn(duration: 400.ms).slideX(begin: -0.1, duration: 500.ms),
                const SizedBox(height: 10),
                Text(
                  unresolved == 0
                      ? 'Your family is calm and well-watched.'
                      : unresolved == 1
                          ? 'You have 1 alert that needs attention.'
                          : 'You have $unresolved alerts that need attention.',
                  style: GoogleFonts.dmSans(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: 13.5,
                    height: 1.4,
                  ),
                ).animate(delay: 150.ms).fadeIn(duration: 400.ms),
              ],
            ),
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
    final cs = Theme.of(context).colorScheme;
    return EldercareCard(
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          PatientAvatar(name: patient['full_name']?.toString(), size: 60),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  patient['full_name']?.toString() ?? 'Unknown',
                  style: GoogleFonts.outfit(
                    fontWeight: FontWeight.w700,
                    fontSize: 17,
                    color: cs.onSurface,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
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
                      const StatusPill(label: 'Calm', kind: StatusKind.success, dense: true),
                  ],
                ),
                if (patient['risk_notes'] != null && patient['risk_notes'].toString().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    patient['risk_notes'].toString(),
                    style: GoogleFonts.dmSans(
                      fontSize: 12.5,
                      color: cs.onSurfaceVariant,
                      height: 1.4,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
