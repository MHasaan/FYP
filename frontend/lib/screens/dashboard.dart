import 'dart:async';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../services/api_service.dart';
import '../services/auth_controller.dart';
import '../services/incident_stream_service.dart';
import '../theme/app_icons.dart';
import '../theme/app_theme.dart';
import '../widgets/app_shell.dart';
import '../widgets/eldercare_card.dart';
import '../widgets/empty_state.dart';
import '../widgets/gradient_orbs.dart';
import '../widgets/incident_tile.dart';
import '../widgets/patient_avatar.dart';
import '../widgets/skeleton.dart';
import '../widgets/stat_tile.dart';
import '../widgets/status_pill.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final ApiService _api = ApiService();
  Timer? _refresh;

  bool _loading = true;
  String? _error;

  int _unresolvedCount = 0;
  int _todayCount = 0;
  int _ackMinutesAvg = 0;
  int _activePatients = 0;
  int _runningCameras = 0;
  int _totalCameras = 0;

  List<int> _trendByDay = List.filled(7, 0);
  Map<String, int> _byEventType = {'fall': 0, 'seizure': 0, 'manual': 0};

  List<Map<String, dynamic>> _recentIncidents = [];
  List<Map<String, dynamic>> _patientsAtRisk = [];

  bool get _backendOnline => _error == null;

  @override
  void initState() {
    super.initState();
    _load();
    _refresh = Timer.periodic(const Duration(seconds: 20), (_) => _load(silent: true));
  }

  @override
  void dispose() {
    _refresh?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final now = DateTime.now();
      final startOfToday = DateTime(now.year, now.month, now.day);
      final sevenDaysAgo = startOfToday.subtract(const Duration(days: 6));

      final results = await Future.wait<dynamic>([
        _api.getIncidents(status: 'new', limit: 1),
        _api.getIncidents(startTime: startOfToday, limit: 1),
        _api.getIncidents(startTime: sevenDaysAgo, limit: 200),
        _api.getIncidents(limit: 6),
        _api.getPatients(),
        _api.getInstances().catchError((_) => <dynamic>[]),
      ]);

      final unresolvedResp = results[0] as Map<String, dynamic>;
      final todayResp = results[1] as Map<String, dynamic>;
      final last7Resp = results[2] as Map<String, dynamic>;
      final recentResp = results[3] as Map<String, dynamic>;
      final patients = (results[4] as List).cast<Map<String, dynamic>>();
      final instances = (results[5] as List).cast<Map<String, dynamic>>();

      final last7 = ((last7Resp['items'] as List?) ?? const []).cast<Map<String, dynamic>>();

      final trend = List<int>.filled(7, 0);
      int falls = 0, seizures = 0;
      int ackTotalMins = 0, ackCount = 0;
      for (final inc in last7) {
        // detected_at is ISO 8601 UTC ("…Z"); convert to local so day buckets
        // line up with the user's perception of "today" in their timezone.
        final detected = DateTime.tryParse(inc['detected_at']?.toString() ?? '')?.toLocal();
        if (detected != null) {
          final dayIdx = 6 - now.difference(detected).inDays;
          if (dayIdx >= 0 && dayIdx < 7) trend[dayIdx]++;
        }
        final ev = (inc['event_type'] as String?)?.toLowerCase();
        if (ev == 'fall') falls++;
        if (ev == 'seizure') seizures++;
        final ack = inc['acknowledged_at']?.toString();
        if (detected != null && ack != null) {
          final ackDt = DateTime.tryParse(ack);
          if (ackDt != null) {
            ackTotalMins += ackDt.difference(detected).inMinutes.abs();
            ackCount++;
          }
        }
      }

      final running = instances.where((i) => (i['status'] as String?)?.toLowerCase() == 'running').length;
      final patientsAtRisk = patients.where((p) {
        final fr = (p['fall_risk'] as String?) ?? 'none';
        final sr = (p['seizure_risk'] as String?) ?? 'none';
        return fr == 'high' || fr == 'medium' || sr == 'high' || sr == 'medium';
      }).take(5).toList();

      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = null;
        _unresolvedCount = (unresolvedResp['total'] as num?)?.toInt() ?? 0;
        _todayCount = (todayResp['total'] as num?)?.toInt() ?? 0;
        _ackMinutesAvg = ackCount == 0 ? 0 : (ackTotalMins ~/ ackCount);
        _activePatients = patients.length;
        _runningCameras = running;
        _totalCameras = instances.length;
        _trendByDay = trend;
        _byEventType = {
          'fall': falls,
          'seizure': seizures,
          'manual': last7.where((i) => (i['event_type'] as String?)?.toLowerCase() == 'manual').length,
        };
        _recentIncidents = ((recentResp['items'] as List?) ?? const []).cast<Map<String, dynamic>>();
        _patientsAtRisk = patientsAtRisk;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load dashboard data.';
      });
    }
  }

  void _navigateToIncidents(BuildContext context) {
    final shell = context.findAncestorStateOfType<AppShellState>();
    shell?.selectByKey('incidents');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final auth = context.watch<AuthController>();
    final stream = context.watch<IncidentStreamService>();
    final severity = theme.extension<IncidentSeverityColors>() ?? IncidentSeverityColors.light;
    final status = theme.extension<AppStatusColors>() ?? AppStatusColors.fallback;

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
            child: _HeroHeader(
              greeting: _greeting(auth.fullName),
              subtitle: _subtitleForRole(auth.role, _unresolvedCount),
              isLive: stream.isLive,
              unresolved: _unresolvedCount,
              onTapAlerts: () => _navigateToIncidents(context),
            ),
          ),

          // KPI grid
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            sliver: SliverLayoutBuilder(
              builder: (_, constraints) {
                final w = constraints.crossAxisExtent;
                final cols = w > 900 ? 4 : w > 540 ? 2 : 2;
                return SliverGrid.count(
                  crossAxisCount: cols,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: cols == 4 ? 1.4 : 1.25,
                  children: _loading
                      ? List.generate(4, (_) => const SkeletonBox(height: 140, radius: 18))
                      : [
                          StatTile(
                            label: 'Unresolved alerts',
                            value: '$_unresolvedCount',
                            icon: AppIcons.incidents,
                            accent: _unresolvedCount > 0 ? severity.critical : status.success,
                            subtitle: _unresolvedCount > 0 ? 'Needs attention' : 'All clear',
                            onTap: _unresolvedCount > 0 ? () => _navigateToIncidents(context) : null,
                          ),
                          StatTile(
                            label: 'Alerts today',
                            value: '$_todayCount',
                            icon: AppIcons.alert,
                            accent: AppTheme.brandTeal,
                            subtitle: _todayCount == 0 ? 'No events yet' : 'Past 24 hours',
                          ),
                          StatTile(
                            label: auth.isCareTeam ? 'Active patients' : 'Family overview',
                            value: '$_activePatients',
                            icon: AppIcons.patients,
                            accent: AppTheme.brandSage,
                            subtitle: _activePatients == 1 ? 'Profile' : 'Profiles',
                          ),
                          if (auth.isCareTeam)
                            StatTile(
                              label: 'Cameras live',
                              value: '$_runningCameras / $_totalCameras',
                              icon: AppIcons.cameras,
                              accent: AppTheme.brandAmber,
                              subtitle: _totalCameras == 0
                                  ? 'None registered'
                                  : '${(_runningCameras / (_totalCameras == 0 ? 1 : _totalCameras) * 100).toStringAsFixed(0)}% online',
                            )
                          else
                            StatTile(
                              label: 'Avg ack time',
                              value: '${_ackMinutesAvg}m',
                              icon: AppIcons.acknowledge,
                              accent: AppTheme.brandSage,
                              subtitle: 'Past 7 days',
                            ),
                        ]
                          .animate(interval: 70.ms)
                          .fade(duration: 350.ms)
                          .slideY(begin: 0.1, duration: 380.ms, curve: Curves.easeOutCubic)
                          .toList(),
                );
              },
            ),
          ),

          // Trend chart
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: _TrendChart(
                values: _trendByDay,
                accent: AppTheme.brandTeal,
                loading: _loading,
              ),
            ),
          ),

          // Event-type breakdown
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: _BreakdownChart(
                data: _byEventType,
                colors: {
                  'fall': severity.critical,
                  'seizure': severity.high,
                  'manual': AppTheme.brandAmber,
                },
                loading: _loading,
              ),
            ),
          ),

          // Recent incidents
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: _RecentIncidentsCard(
                incidents: _recentIncidents,
                loading: _loading,
                onSeeAll: () => _navigateToIncidents(context),
              ),
            ),
          ),

          // Patients at risk
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              child: _PatientsAtRiskCard(
                patients: _patientsAtRisk,
                loading: _loading,
              ),
            ),
          ),

          if (!_backendOnline)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                child: EldercareCard(
                  child: Row(
                    children: [
                      Icon(Icons.cloud_off_rounded, color: cs.error),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _error ?? 'Backend offline',
                          style: theme.textTheme.bodyMedium?.copyWith(color: cs.error),
                        ),
                      ),
                      TextButton(onPressed: _load, child: const Text('Retry')),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _greeting(String name) {
    final hour = DateTime.now().hour;
    final greeting = hour < 5
        ? 'Good evening'
        : hour < 12
            ? 'Good morning'
            : hour < 18
                ? 'Good afternoon'
                : 'Good evening';
    final first = name.split(' ').first.trim();
    return first.isEmpty ? greeting : '$greeting, $first';
  }

  String _subtitleForRole(String role, int unresolved) {
    if (unresolved > 0) {
      return unresolved == 1
          ? 'You have 1 unresolved alert that needs your attention.'
          : 'You have $unresolved unresolved alerts that need your attention.';
    }
    if (role == 'admin') return 'System overview at a glance.';
    if (role == 'caregiver') return 'Your assigned patients are calm.';
    return 'Your family member is calm.';
  }
}

// ── Hero header ───────────────────────────────────────────────────────────────
class _HeroHeader extends StatelessWidget {
  final String greeting;
  final String subtitle;
  final bool isLive;
  final int unresolved;
  final VoidCallback onTapAlerts;

  const _HeroHeader({
    required this.greeting,
    required this.subtitle,
    required this.isLive,
    required this.unresolved,
    required this.onTapAlerts,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(
          height: 250,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF01949A),
                Color(0xFF3D8D7A),
                Color(0xFF2A6B5E),
              ],
              stops: [0.0, 0.55, 1.0],
            ),
            borderRadius: BorderRadius.only(
              bottomLeft: Radius.circular(28),
              bottomRight: Radius.circular(28),
            ),
          ),
        ),
        const Positioned.fill(
          child: ClipRRect(
            borderRadius: BorderRadius.only(
              bottomLeft: Radius.circular(28),
              bottomRight: Radius.circular(28),
            ),
            child: SizedBox(height: 250),
          ),
        ),
        ClipRRect(
          borderRadius: const BorderRadius.only(
            bottomLeft: Radius.circular(28),
            bottomRight: Radius.circular(28),
          ),
          child: SizedBox(
            height: 250,
            width: double.infinity,
            child: GradientOrbs.brand(),
          ),
        ),
        SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _LivePulseDot(isLive: isLive),
                          const SizedBox(width: 6),
                          Text(
                            isLive ? 'Live' : 'Polling',
                            style: GoogleFonts.outfit(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 11,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Text(
                  greeting,
                  style: GoogleFonts.cormorantGaramond(
                    fontSize: 34,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    height: 1.05,
                    letterSpacing: -0.5,
                  ),
                )
                    .animate()
                    .fadeIn(duration: 400.ms)
                    .slideX(begin: -0.1, duration: 500.ms, curve: Curves.easeOutCubic),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  style: GoogleFonts.dmSans(
                    fontSize: 13.5,
                    color: Colors.white.withValues(alpha: 0.82),
                    height: 1.45,
                  ),
                ).animate(delay: 150.ms).fadeIn(duration: 400.ms),
                const SizedBox(height: 14),
                if (unresolved > 0)
                  _AlertBanner(count: unresolved, onTap: onTapAlerts)
                      .animate(delay: 250.ms)
                      .fadeIn(duration: 350.ms)
                      .slideY(begin: 0.15, duration: 400.ms, curve: Curves.easeOutCubic),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _LivePulseDot extends StatefulWidget {
  final bool isLive;
  const _LivePulseDot({required this.isLive});

  @override
  State<_LivePulseDot> createState() => _LivePulseDotState();
}

class _LivePulseDotState extends State<_LivePulseDot> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.isLive ? const Color(0xFF34D399) : const Color(0xFFFDE68A);
    return SizedBox(
      width: 14,
      height: 14,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (widget.isLive)
            AnimatedBuilder(
              animation: _ctrl,
              builder: (_, __) {
                final t = _ctrl.value;
                return Container(
                  width: 8 + 6 * t,
                  height: 8 + 6 * t,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.4 * (1 - t)),
                    shape: BoxShape.circle,
                  ),
                );
              },
            ),
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
        ],
      ),
    );
  }
}

class _AlertBanner extends StatelessWidget {
  final int count;
  final VoidCallback onTap;

  const _AlertBanner({required this.count, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.mediumImpact();
        onTap();
      },
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.30)),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFFFCB5AC).withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(AppIcons.incidents, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$count unresolved alert${count == 1 ? '' : 's'}',
                    style: GoogleFonts.outfit(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 14.5,
                    ),
                  ),
                  Text(
                    'Tap to review',
                    style: GoogleFonts.dmSans(
                      color: Colors.white.withValues(alpha: 0.78),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 18),
          ],
        ),
      ),
    );
  }
}

// ── Trend chart card ──────────────────────────────────────────────────────────
class _TrendChart extends StatelessWidget {
  final List<int> values;
  final Color accent;
  final bool loading;

  const _TrendChart({required this.values, required this.accent, required this.loading});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return EldercareCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(AppIcons.trend, color: accent, size: 18),
              const SizedBox(width: 8),
              Text(
                'Alerts past 7 days',
                style: GoogleFonts.outfit(fontWeight: FontWeight.w700, fontSize: 15),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 170,
            child: loading
                ? const SkeletonBox(height: 170, radius: 12)
                : LineChart(
                    LineChartData(
                      gridData: FlGridData(
                        show: true,
                        drawVerticalLine: false,
                        getDrawingHorizontalLine: (_) => FlLine(
                          color: cs.outlineVariant.withValues(alpha: 0.5),
                          strokeWidth: 1,
                          dashArray: [4, 4],
                        ),
                      ),
                      borderData: FlBorderData(show: false),
                      titlesData: FlTitlesData(
                        leftTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: true, reservedSize: 28),
                        ),
                        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 28,
                            getTitlesWidget: (value, meta) {
                              const labels = ['-6d', '-5d', '-4d', '-3d', '-2d', 'Yest.', 'Today'];
                              final i = value.toInt();
                              if (i < 0 || i >= labels.length) return const SizedBox.shrink();
                              return Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(
                                  labels[i],
                                  style: GoogleFonts.dmSans(
                                    fontSize: 10,
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      minX: 0,
                      maxX: 6,
                      minY: 0,
                      maxY: (values.fold<int>(0, (a, b) => b > a ? b : a) + 1).toDouble(),
                      lineBarsData: [
                        LineChartBarData(
                          spots: [
                            for (var i = 0; i < values.length; i++)
                              FlSpot(i.toDouble(), values[i].toDouble()),
                          ],
                          isCurved: true,
                          gradient: LinearGradient(
                            colors: [accent, AppTheme.brandSage],
                          ),
                          barWidth: 3.5,
                          dotData: FlDotData(
                            show: true,
                            getDotPainter: (spot, _, __, ___) => FlDotCirclePainter(
                              radius: 4,
                              color: Colors.white,
                              strokeWidth: 2.5,
                              strokeColor: accent,
                            ),
                          ),
                          belowBarData: BarAreaData(
                            show: true,
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [accent.withValues(alpha: 0.30), accent.withValues(alpha: 0.0)],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

// ── Breakdown chart card ──────────────────────────────────────────────────────
class _BreakdownChart extends StatelessWidget {
  final Map<String, int> data;
  final Map<String, Color> colors;
  final bool loading;

  const _BreakdownChart({required this.data, required this.colors, required this.loading});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final total = data.values.fold<int>(0, (a, b) => a + b);

    return EldercareCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Event type breakdown',
            style: GoogleFonts.outfit(fontWeight: FontWeight.w700, fontSize: 15),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 170,
            child: loading
                ? const SkeletonBox(height: 170, radius: 12)
                : (total == 0
                    ? Center(
                        child: Text(
                          'No alerts in the past 7 days',
                          style: GoogleFonts.dmSans(color: cs.onSurfaceVariant),
                        ),
                      )
                    : Row(
                        children: [
                          Expanded(
                            child: PieChart(
                              PieChartData(
                                sectionsSpace: 3,
                                centerSpaceRadius: 32,
                                startDegreeOffset: -90,
                                sections: data.entries.map((e) {
                                  final color = colors[e.key] ?? cs.primary;
                                  return PieChartSectionData(
                                    value: e.value.toDouble(),
                                    color: color,
                                    title: e.value == 0 ? '' : '${e.value}',
                                    titleStyle: GoogleFonts.outfit(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 12,
                                    ),
                                    radius: 44,
                                  );
                                }).toList(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: data.entries.map((e) {
                              final color = colors[e.key] ?? cs.primary;
                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 4),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 10,
                                      height: 10,
                                      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      _label(e.key),
                                      style: GoogleFonts.dmSans(fontWeight: FontWeight.w600, fontSize: 12.5),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      '· ${e.value}',
                                      style: GoogleFonts.dmSans(color: cs.onSurfaceVariant, fontSize: 12),
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                          ),
                        ],
                      )),
          ),
        ],
      ),
    );
  }

  String _label(String k) {
    switch (k) {
      case 'fall': return 'Fall';
      case 'seizure': return 'Seizure';
      case 'manual': return 'Manual';
      default: return k;
    }
  }
}

// ── Recent incidents ──────────────────────────────────────────────────────────
class _RecentIncidentsCard extends StatelessWidget {
  final List<Map<String, dynamic>> incidents;
  final bool loading;
  final VoidCallback onSeeAll;

  const _RecentIncidentsCard({
    required this.incidents,
    required this.loading,
    required this.onSeeAll,
  });

  @override
  Widget build(BuildContext context) {
    return EldercareCard(
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
              TextButton(
                onPressed: onSeeAll,
                style: TextButton.styleFrom(
                  foregroundColor: AppTheme.brandTeal,
                  textStyle: GoogleFonts.outfit(fontWeight: FontWeight.w600, fontSize: 13),
                ),
                child: const Text('See all'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (loading) ...[
            for (int i = 0; i < 3; i++)
              const Padding(padding: EdgeInsets.only(bottom: 8), child: SkeletonRow()),
          ] else if (incidents.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  'No alerts yet — all quiet.',
                  style: GoogleFonts.dmSans(color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ),
            )
          else
            ...incidents.take(4).map((i) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: IncidentTile(incident: i),
                )),
        ],
      ),
    );
  }
}

// ── Patients at risk ──────────────────────────────────────────────────────────
class _PatientsAtRiskCard extends StatelessWidget {
  final List<Map<String, dynamic>> patients;
  final bool loading;

  const _PatientsAtRiskCard({required this.patients, required this.loading});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return EldercareCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(AppIcons.risk, color: cs.error, size: 18),
              const SizedBox(width: 8),
              Text(
                'Patients at risk',
                style: GoogleFonts.outfit(fontWeight: FontWeight.w700, fontSize: 15),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (loading) ...[
            for (int i = 0; i < 3; i++)
              const Padding(padding: EdgeInsets.only(bottom: 8), child: SkeletonRow(height: 56)),
          ] else if (patients.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: EmptyState(
                icon: AppIcons.patients,
                title: 'No risk flags',
                subtitle: 'Patients with elevated fall or seizure risk appear here.',
              ),
            )
          else
            ...patients.map((p) {
              final fr = (p['fall_risk'] as String?) ?? 'none';
              final sr = (p['seizure_risk'] as String?) ?? 'none';
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    PatientAvatar(name: p['full_name']?.toString(), size: 40),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            p['full_name']?.toString() ?? 'Unknown',
                            style: GoogleFonts.outfit(fontWeight: FontWeight.w700, fontSize: 14),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Wrap(
                            spacing: 4,
                            runSpacing: 4,
                            children: [
                              if (fr != 'none')
                                StatusPill(label: 'Fall: $fr', kind: StatusKind.danger, dense: true, icon: AppIcons.fall),
                              if (sr != 'none')
                                StatusPill(label: 'Seizure: $sr', kind: StatusKind.warning, dense: true, icon: AppIcons.seizure),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}
