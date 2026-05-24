import 'dart:convert';

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../services/api_service.dart';
import '../../services/auth_controller.dart';
import '../../services/download_service.dart' as ds;
import '../../theme/app_icons.dart';
import '../../theme/app_theme.dart';
import '../../widgets/eldercare_card.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/incident_tile.dart';
import '../../widgets/section_header.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/stat_tile.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  final ApiService _api = ApiService();
  bool _loading = false;
  String? _error;

  List<Map<String, dynamic>> _patients = [];
  List<Map<String, dynamic>> _cameras = [];

  int? _patientFilter;
  int? _cameraFilter;
  DateTimeRange _range = DateTimeRange(
    start: DateTime.now().subtract(const Duration(days: 30)),
    end: DateTime.now(),
  );

  Map<String, dynamic>? _summary;
  List<Map<String, dynamic>> _incidents = [];

  @override
  void initState() {
    super.initState();
    _initLookups();
  }

  Future<void> _initLookups() async {
    try {
      final results = await Future.wait([
        _api.getPatients(),
        _api.getCameraConfigs(),
      ]);
      if (mounted) {
        setState(() {
          _patients = results[0].cast<Map<String, dynamic>>();
          _cameras = results[1].cast<Map<String, dynamic>>();
        });
      }
    } catch (_) {}
    await _generate();
  }

  Future<void> _generate() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final futures = <Future>[
        _api.getIncidentReport(
          patientId: _patientFilter,
          cameraConfigId: _cameraFilter,
          startTime: _range.start,
          endTime: _range.end,
        ),
        _api.getIncidents(
          patientId: _patientFilter,
          cameraConfigId: _cameraFilter,
          startTime: _range.start,
          endTime: _range.end,
          limit: 100,
        ),
      ];
      final results = await Future.wait(futures);
      final summary = results[0] as Map<String, dynamic>;
      final incs = results[1] as Map<String, dynamic>;
      if (mounted) {
        setState(() {
          _summary = summary;
          _incidents = ((incs['items'] as List?) ?? const []).cast<Map<String, dynamic>>();
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Could not generate report: $e';
        });
      }
    }
  }

  Future<void> _pickRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDateRange: _range,
    );
    if (picked != null) {
      setState(() => _range = picked);
      await _generate();
    }
  }

  Future<void> _exportJson() async {
    final payload = {
      'filters': {
        'patient_id': _patientFilter,
        'camera_config_id': _cameraFilter,
        'start': _range.start.toIso8601String(),
        'end': _range.end.toIso8601String(),
      },
      'summary': _summary,
      'incidents': _incidents,
    };
    await ds.downloadJsonFile(
      'eldercare-report-${DateTime.now().millisecondsSinceEpoch}.json',
      const JsonEncoder.withIndent('  ').convert(payload),
    );
  }

  Future<void> _exportCsv() async {
    final buf = StringBuffer();
    buf.writeln('id,event_type,severity,status,patient_id,camera_config_id,confidence,threshold,detected_at,acknowledged_at,resolved_at');
    for (final i in _incidents) {
      buf.writeln([
        i['id'],
        i['event_type'],
        i['severity'],
        i['status'],
        i['patient_id'],
        i['camera_config_id'],
        i['confidence'],
        i['threshold'],
        i['detected_at'],
        i['acknowledged_at'],
        i['resolved_at'],
      ].map(_csvCell).join(','));
    }
    await ds.downloadTextFile(
      'eldercare-incidents-${DateTime.now().millisecondsSinceEpoch}.csv',
      buf.toString(),
      mimeType: 'text/csv;charset=utf-8',
    );
  }

  String _csvCell(dynamic v) {
    if (v == null) return '';
    final s = v.toString();
    if (s.contains(',') || s.contains('"') || s.contains('\n')) {
      return '"${s.replaceAll('"', '""')}"';
    }
    return s;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final auth = context.watch<AuthController>();
    final isCareTeam = auth.isCareTeam;

    final summary = _summary;
    final byEvent = (summary?['by_event_type'] as Map?)?.cast<String, dynamic>() ?? {};
    final byStatus = (summary?['by_status'] as Map?)?.cast<String, dynamic>() ?? {};
    final bySeverity = (summary?['by_severity'] as Map?)?.cast<String, dynamic>() ?? {};
    final total = (summary?['total'] as num?)?.toInt() ??
        byEvent.values.fold<int>(0, (a, b) => a + ((b as num?)?.toInt() ?? 0));
    final falls = (byEvent['fall'] as num?)?.toInt() ?? 0;
    final seizures = (byEvent['seizure'] as num?)?.toInt() ?? 0;
    final resolved = (byStatus['resolved'] as num?)?.toInt() ?? 0;

    return Column(
      children: [
        SectionHeader(
          title: 'Reports',
          subtitle: 'Incident history and trends',
          icon: AppIcons.reports,
          trailing: PopupMenuButton<String>(
            tooltip: 'Export',
            icon: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppTheme.brandTeal.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(AppIcons.export, color: AppTheme.brandTeal, size: 18),
            ),
            onSelected: (v) {
              HapticFeedback.lightImpact();
              if (v == 'json') _exportJson();
              if (v == 'csv') _exportCsv();
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'csv',
                child: Row(children: [
                  Icon(AppIcons.export, size: 16, color: AppTheme.brandSage),
                  const SizedBox(width: 10),
                  const Text('Export as CSV'),
                ]),
              ),
              PopupMenuItem(
                value: 'json',
                child: Row(children: [
                  Icon(AppIcons.export, size: 16, color: AppTheme.brandSage),
                  const SizedBox(width: 10),
                  const Text('Export as JSON'),
                ]),
              ),
            ],
          ),
        ),

        // Filter row — horizontal scroll on narrow screens
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Row(
            children: [
              if (isCareTeam) ...[
                SizedBox(
                  width: 200,
                  child: DropdownButtonFormField<int?>(
                    value: _patientFilter,
                    decoration: const InputDecoration(labelText: 'Patient', isDense: true),
                    items: [
                      const DropdownMenuItem<int?>(value: null, child: Text('All patients')),
                      ..._patients.map((p) => DropdownMenuItem<int?>(
                            value: (p['id'] as num).toInt(),
                            child: Text(p['full_name']?.toString() ?? 'Patient #${p['id']}'),
                          )),
                    ],
                    onChanged: (v) => setState(() => _patientFilter = v),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 200,
                  child: DropdownButtonFormField<int?>(
                    value: _cameraFilter,
                    decoration: const InputDecoration(labelText: 'Camera', isDense: true),
                    items: [
                      const DropdownMenuItem<int?>(value: null, child: Text('All cameras')),
                      ..._cameras.map((c) => DropdownMenuItem<int?>(
                            value: (c['id'] as num).toInt(),
                            child: Text(c['name']?.toString() ?? 'Camera #${c['id']}'),
                          )),
                    ],
                    onChanged: (v) => setState(() => _cameraFilter = v),
                  ),
                ),
                const SizedBox(width: 10),
              ],
              OutlinedButton.icon(
                onPressed: _pickRange,
                icon: const Icon(AppIcons.calendar, size: 16),
                label: Text('${_fmt(_range.start)} → ${_fmt(_range.end)}'),
              ),
              const SizedBox(width: 10),
              FilledButton.icon(
                onPressed: _loading ? null : () { HapticFeedback.lightImpact(); _generate(); },
                icon: const Icon(AppIcons.chart, size: 16),
                label: Text(_loading ? 'Generating…' : 'Generate'),
                style: FilledButton.styleFrom(backgroundColor: AppTheme.brandTeal),
              ),
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? const SkeletonList(count: 5)
              : _error != null
                  ? Center(child: Text(_error!, style: TextStyle(color: cs.error)))
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      children: [
                        // KPI tiles
                        LayoutBuilder(builder: (_, c) {
                          final cols = c.maxWidth > 900 ? 4 : 2;
                          final tileWidth = (c.maxWidth - (cols - 1) * 12) / cols;
                          return Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            children: [
                              SizedBox(width: tileWidth, child: StatTile(label: 'Total incidents', value: '$total', icon: AppIcons.incidents)),
                              SizedBox(width: tileWidth, child: StatTile(label: 'Falls', value: '$falls', icon: AppIcons.fall, accent: theme.extension<IncidentSeverityColors>()?.critical)),
                              SizedBox(width: tileWidth, child: StatTile(label: 'Seizures', value: '$seizures', icon: AppIcons.seizure, accent: theme.extension<IncidentSeverityColors>()?.high)),
                              SizedBox(width: tileWidth, child: StatTile(label: 'Resolved', value: '$resolved', icon: AppIcons.resolve, accent: theme.extension<AppStatusColors>()?.success)),
                            ],
                          );
                        }),
                        const SizedBox(height: 16),
                        // Charts row
                        if (total > 0) ...[
                          LayoutBuilder(builder: (_, c) {
                            final wide = c.maxWidth > 900;
                            final byEventChart = _buildBarChart(
                              context,
                              title: 'By event type',
                              data: byEvent.map((k, v) => MapEntry(k, ((v as num?)?.toInt() ?? 0))),
                              accent: cs.primary,
                            );
                            final bySeverityChart = _buildBarChart(
                              context,
                              title: 'By severity',
                              data: bySeverity.map((k, v) => MapEntry(k, ((v as num?)?.toInt() ?? 0))),
                              accent: cs.tertiary,
                            );
                            if (wide) {
                              return Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(child: byEventChart),
                                  const SizedBox(width: 12),
                                  Expanded(child: bySeverityChart),
                                ],
                              );
                            }
                            return Column(children: [byEventChart, const SizedBox(height: 12), bySeverityChart]);
                          }),
                          const SizedBox(height: 16),
                        ],
                        // Incident detail rows
                        EldercareCard(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Incidents', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                              const SizedBox(height: 8),
                              if (_incidents.isEmpty)
                                const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 32),
                                  child: EmptyState(
                                    icon: AppIcons.incidents,
                                    title: 'No incidents in this range',
                                    subtitle: 'Try widening the date range or removing filters.',
                                  ),
                                )
                              else
                                ..._incidents.take(50).map(
                                      (i) => Padding(
                                        padding: const EdgeInsets.only(bottom: 8),
                                        child: IncidentTile(incident: i),
                                      ),
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

  /// Round up to the next "nice" power-of-10 boundary so chart axis labels are
  /// readable: 1, 2, 5, 10, 20, 50, 100, 200, 500, 1000, etc.
  static double _niceMax(int dataMax) {
    if (dataMax <= 0) return 5;
    final magnitude = math.pow(10, (math.log(dataMax) / math.ln10).floor()).toDouble();
    final normalized = dataMax / magnitude;
    final niceNormalized = normalized <= 1 ? 1.0 : normalized <= 2 ? 2.0 : normalized <= 5 ? 5.0 : 10.0;
    return niceNormalized * magnitude;
  }

  Widget _buildBarChart(
    BuildContext context, {
    required String title,
    required Map<String, int> data,
    required Color accent,
  }) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final entries = data.entries.toList();
    final dataMax = entries.isEmpty ? 0 : entries.map((e) => e.value).reduce((a, b) => a > b ? a : b);
    final maxY = _niceMax(dataMax);
    final interval = maxY / 4;  // 4 horizontal grid lines + label per chart

    return EldercareCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          SizedBox(
            height: 200,
            child: entries.isEmpty || dataMax == 0
                ? Center(child: Text('No data', style: TextStyle(color: cs.onSurfaceVariant)))
                : BarChart(
                    BarChartData(
                      maxY: maxY,
                      minY: 0,
                      alignment: BarChartAlignment.spaceAround,
                      gridData: FlGridData(
                        show: true,
                        drawVerticalLine: false,
                        horizontalInterval: interval,
                        getDrawingHorizontalLine: (_) => FlLine(
                          color: cs.outlineVariant.withValues(alpha: 0.4),
                          strokeWidth: 1,
                          dashArray: [4, 4],
                        ),
                      ),
                      borderData: FlBorderData(show: false),
                      titlesData: FlTitlesData(
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 40,
                            interval: interval,
                            getTitlesWidget: (value, meta) {
                              // Only render labels that align with the grid lines,
                              // so they don't pile up on top of each other.
                              if ((value % interval).abs() > 0.01 && value != maxY) {
                                return const SizedBox.shrink();
                              }
                              return Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: Text(
                                  value.toInt().toString(),
                                  style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                                  textAlign: TextAlign.right,
                                ),
                              );
                            },
                          ),
                        ),
                        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 32,
                            getTitlesWidget: (value, meta) {
                              final i = value.toInt();
                              if (i < 0 || i >= entries.length) return const SizedBox.shrink();
                              return Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(
                                  entries[i].key,
                                  style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      barGroups: [
                        for (var i = 0; i < entries.length; i++)
                          BarChartGroupData(
                            x: i,
                            barRods: [
                              BarChartRodData(
                                toY: entries[i].value.toDouble(),
                                color: accent,
                                width: 18,
                                borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  static String _fmt(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
