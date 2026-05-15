import 'dart:async';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/api_service.dart';
import '../services/auth_controller.dart';
import '../services/incident_stream_service.dart';
import '../theme/app_icons.dart';
import '../theme/app_theme.dart';
import '../widgets/app_shell.dart';
import '../widgets/eldercare_card.dart';
import '../widgets/empty_state.dart';
import '../widgets/incident_tile.dart';
import '../widgets/patient_avatar.dart';
import '../widgets/section_header.dart';
import '../widgets/skeleton.dart';
import '../widgets/stat_tile.dart';
import '../widgets/status_pill.dart';

/// Role-aware operations cockpit. Replaces the legacy ML pipeline tech-ops view.
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

  // KPIs
  int _unresolvedCount = 0;
  int _todayCount = 0;
  int _ackMinutesAvg = 0;
  int _activePatients = 0;
  int _runningCameras = 0;
  int _totalCameras = 0;

  // Charts
  List<int> _trendByDay = List.filled(7, 0);
  Map<String, int> _byEventType = {'fall': 0, 'seizure': 0, 'manual': 0};

  // Lists
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

      final last7 = ((last7Resp['items'] as List?) ?? const [])
          .cast<Map<String, dynamic>>();

      final trend = List<int>.filled(7, 0);
      int falls = 0, seizures = 0;
      int ackTotalMins = 0, ackCount = 0;
      for (final inc in last7) {
        final detected = DateTime.tryParse(inc['detected_at']?.toString() ?? '');
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

    final greeting = _greeting(auth.fullName);

    return ListView(
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 32),
      children: [
        SectionHeader(
          title: greeting,
          subtitle: _subtitleForRole(auth.role, _unresolvedCount),
          icon: AppIcons.dashboard,
          trailing: stream.isLive
              ? const StatusPill(label: 'Live', kind: StatusKind.success, dense: true)
              : const StatusPill(label: 'Polling', kind: StatusKind.warning, dense: true),
        ),

        if (_unresolvedCount > 0)
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
            child: _AlertBanner(
              count: _unresolvedCount,
              onTap: () => _navigateToIncidents(context),
            ),
          ),

        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: LayoutBuilder(
            builder: (_, c) {
              final cols = c.maxWidth > 1180 ? 4 : c.maxWidth > 720 ? 2 : 1;
              final width = (c.maxWidth - (cols - 1) * 12) / cols;
              if (_loading) {
                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: List.generate(
                    4,
                    (_) => SizedBox(width: width, child: const SkeletonBox(height: 124, radius: 16)),
                  ),
                );
              }
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  SizedBox(
                    width: width,
                    child: StatTile(
                      label: 'Unresolved alerts',
                      value: '$_unresolvedCount',
                      icon: AppIcons.incidents,
                      accent: _unresolvedCount > 0 ? severity.critical : status.success,
                      subtitle: _unresolvedCount > 0 ? 'Needs attention' : 'All clear',
                      onTap: _unresolvedCount > 0 ? () => _navigateToIncidents(context) : null,
                    ),
                  ),
                  SizedBox(
                    width: width,
                    child: StatTile(
                      label: 'Alerts today',
                      value: '$_todayCount',
                      icon: AppIcons.alert,
                      accent: cs.primary,
                      subtitle: _todayCount == 0 ? 'No events yet' : 'Past 24 hours',
                    ),
                  ),
                  SizedBox(
                    width: width,
                    child: StatTile(
                      label: auth.isCareTeam ? 'Active patients' : 'Family overview',
                      value: '$_activePatients',
                      icon: AppIcons.patients,
                      accent: cs.tertiary,
                      subtitle: _activePatients == 1 ? 'Profile' : 'Profiles',
                    ),
                  ),
                  if (auth.isCareTeam)
                    SizedBox(
                      width: width,
                      child: StatTile(
                        label: 'Cameras running',
                        value: '$_runningCameras / $_totalCameras',
                        icon: AppIcons.cameras,
                        accent: status.info,
                        subtitle: _totalCameras == 0
                            ? 'None registered'
                            : '${(_runningCameras / (_totalCameras == 0 ? 1 : _totalCameras) * 100).toStringAsFixed(0)}% live',
                      ),
                    )
                  else
                    SizedBox(
                      width: width,
                      child: StatTile(
                        label: 'Avg ack time',
                        value: '${_ackMinutesAvg}m',
                        icon: AppIcons.acknowledge,
                        accent: status.success,
                        subtitle: 'Past 7 days',
                      ),
                    ),
                ],
              );
            },
          ),
        ),

        const SizedBox(height: 16),

        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: LayoutBuilder(
            builder: (_, c) {
              final wide = c.maxWidth > 880;
              final trend = _TrendChart(values: _trendByDay, accent: cs.primary, loading: _loading);
              final breakdown = _BreakdownChart(
                data: _byEventType,
                colors: {
                  'fall': severity.critical,
                  'seizure': severity.high,
                  'manual': cs.tertiary,
                },
                loading: _loading,
              );
              if (wide) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 3, child: trend),
                    const SizedBox(width: 12),
                    Expanded(flex: 2, child: breakdown),
                  ],
                );
              }
              return Column(children: [trend, const SizedBox(height: 12), breakdown]);
            },
          ),
        ),

        const SizedBox(height: 16),

        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: LayoutBuilder(
            builder: (_, c) {
              final wide = c.maxWidth > 980;
              final recent = _RecentIncidents(
                incidents: _recentIncidents,
                loading: _loading,
                onSeeAll: () => _navigateToIncidents(context),
              );
              final risk = _PatientsAtRisk(
                patients: _patientsAtRisk,
                loading: _loading,
              );
              if (wide) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 3, child: recent),
                    const SizedBox(width: 12),
                    Expanded(flex: 2, child: risk),
                  ],
                );
              }
              return Column(children: [recent, const SizedBox(height: 12), risk]);
            },
          ),
        ),

        if (!_backendOnline) ...[
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
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
                  TextButton(
                    onPressed: _load,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
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

// ── Alert banner ────────────────────────────────────────────────────────────
class _AlertBanner extends StatelessWidget {
  final int count;
  final VoidCallback onTap;

  const _AlertBanner({required this.count, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final severity = theme.extension<IncidentSeverityColors>() ?? IncidentSeverityColors.light;
    final color = severity.critical;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [color, color.withValues(alpha: 0.85)],
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.25),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(AppIcons.incidents, color: Colors.white),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$count unresolved alert${count == 1 ? '' : 's'}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Tap to review and acknowledge.',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_rounded, color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Trend chart ─────────────────────────────────────────────────────────────
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
              Text('Alerts past 7 days',
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 180,
            child: loading
                ? const SkeletonBox(height: 180, radius: 12)
                : LineChart(
                    LineChartData(
                      gridData: const FlGridData(show: true, drawVerticalLine: false),
                      borderData: FlBorderData(show: false),
                      titlesData: FlTitlesData(
                        leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 28)),
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
                                child: Text(labels[i],
                                    style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
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
                            for (var i = 0; i < values.length; i++) FlSpot(i.toDouble(), values[i].toDouble()),
                          ],
                          isCurved: true,
                          color: accent,
                          barWidth: 3,
                          dotData: const FlDotData(show: true),
                          belowBarData: BarAreaData(
                            show: true,
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [accent.withValues(alpha: 0.25), accent.withValues(alpha: 0.0)],
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

// ── Breakdown chart ─────────────────────────────────────────────────────────
class _BreakdownChart extends StatelessWidget {
  final Map<String, int> data;
  final Map<String, Color> colors;
  final bool loading;

  const _BreakdownChart({required this.data, required this.colors, required this.loading});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final total = data.values.fold<int>(0, (a, b) => a + b);

    return EldercareCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('By event type',
              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          SizedBox(
            height: 180,
            child: loading
                ? const SkeletonBox(height: 180, radius: 12)
                : (total == 0
                    ? Center(
                        child: Text('No alerts in the past 7 days',
                            style: TextStyle(color: cs.onSurfaceVariant)),
                      )
                    : Row(
                        children: [
                          Expanded(
                            child: PieChart(
                              PieChartData(
                                sectionsSpace: 2,
                                centerSpaceRadius: 32,
                                sections: data.entries.map((e) {
                                  final color = colors[e.key] ?? cs.primary;
                                  return PieChartSectionData(
                                    value: e.value.toDouble(),
                                    color: color,
                                    title: e.value == 0 ? '' : '${e.value}',
                                    titleStyle: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 12,
                                    ),
                                    radius: 42,
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
                                    Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                                    const SizedBox(width: 8),
                                    Text(_label(e.key), style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
                                    const SizedBox(width: 6),
                                    Text('· ${e.value}', style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
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

  String _label(String key) {
    switch (key) {
      case 'fall': return 'Fall';
      case 'seizure': return 'Seizure';
      case 'manual': return 'Manual';
      default: return key;
    }
  }
}

// ── Recent incidents ────────────────────────────────────────────────────────
class _RecentIncidents extends StatelessWidget {
  final List<Map<String, dynamic>> incidents;
  final bool loading;
  final VoidCallback onSeeAll;

  const _RecentIncidents({
    required this.incidents,
    required this.loading,
    required this.onSeeAll,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return EldercareCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(AppIcons.incidents, color: theme.colorScheme.primary, size: 18),
              const SizedBox(width: 8),
              Text('Recent alerts',
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              const Spacer(),
              TextButton(
                onPressed: onSeeAll,
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
              padding: const EdgeInsets.symmetric(vertical: 36),
              child: Center(
                child: Text('No alerts yet — all quiet.',
                    style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ),
            )
          else
            ...incidents.take(5).map((i) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: IncidentTile(incident: i),
                )),
        ],
      ),
    );
  }
}

// ── Patients at risk ────────────────────────────────────────────────────────
class _PatientsAtRisk extends StatelessWidget {
  final List<Map<String, dynamic>> patients;
  final bool loading;

  const _PatientsAtRisk({required this.patients, required this.loading});

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
              Icon(AppIcons.risk, color: cs.error, size: 18),
              const SizedBox(width: 8),
              Text('Patients at risk',
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 12),
          if (loading) ...[
            for (int i = 0; i < 3; i++)
              const Padding(padding: EdgeInsets.only(bottom: 8), child: SkeletonRow(height: 56)),
          ] else if (patients.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: EmptyState(
                icon: AppIcons.patients,
                title: 'No risk flags',
                subtitle: 'Patients with elevated fall or seizure risk will appear here.',
              ),
            )
          else
            ...patients.map((p) {
              final fr = (p['fall_risk'] as String?) ?? 'none';
              final sr = (p['seizure_risk'] as String?) ?? 'none';
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    PatientAvatar(name: p['full_name']?.toString(), size: 36),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        p['full_name']?.toString() ?? 'Unknown',
                        style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (fr != 'none')
                      Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: StatusPill(label: 'Fall: $fr', kind: StatusKind.danger, dense: true, icon: AppIcons.fall),
                      ),
                    if (sr != 'none')
                      Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: StatusPill(label: 'Seizure: $sr', kind: StatusKind.warning, dense: true, icon: AppIcons.seizure),
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
