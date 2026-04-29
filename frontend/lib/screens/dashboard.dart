import 'package:flutter/material.dart';
import 'dart:async';
import 'package:fl_chart/fl_chart.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';

class DashboardScreen extends StatefulWidget {
  final void Function(int)? onNavigate;
  const DashboardScreen({super.key, this.onNavigate});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final ApiService _api = ApiService();
  static const Duration _dashboardRequestTimeout = Duration(seconds: 4);
  Map<String, dynamic>? _pipelineStatus;
  Map<String, dynamic>? _health;
  List<double> _fpsHistory = [];
  List<Map<String, dynamic>> _modelStats = [];
  Map<String, int> _instanceStatusCounts = {'running': 0, 'paused': 0, 'stopped': 0, 'idle': 0};
  bool _isLoading = true;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _fetchData();
    _refreshTimer = Timer.periodic(const Duration(seconds: 3), (_) => _fetchData());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _api.dispose();
    super.dispose();
  }

  Future<void> _fetchData() async {
    try {
      final results = await Future.wait<dynamic>([
        _api.getPipelineStatus().timeout(_dashboardRequestTimeout),
        _api.checkHealth().timeout(_dashboardRequestTimeout),
        _api.getInstances().timeout(_dashboardRequestTimeout),
      ]).timeout(_dashboardRequestTimeout + const Duration(seconds: 1));
      
      final status = results[0] as Map<String, dynamic>;
      final health = results[1] as Map<String, dynamic>;
      final instances = results[2] as List<dynamic>;

      final statusCounts = {'running': 0, 'paused': 0, 'stopped': 0, 'idle': 0};
      for (final raw in instances) {
        if (raw is! Map<String, dynamic>) continue;
        final key = (raw['status'] as String? ?? 'idle').toLowerCase();
        if (statusCounts.containsKey(key)) {
          statusCounts[key] = (statusCounts[key] ?? 0) + 1;
        }
      }

      final activeSessionId = status['active_session_id'] as int?;
      List<Map<String, dynamic>> modelStats = [];
      if (activeSessionId != null) {
        try {
          final sessionStats = await _api.getSessionStats(activeSessionId).timeout(_dashboardRequestTimeout);
          modelStats = (sessionStats['models'] as List<dynamic>? ?? const []).whereType<Map<String, dynamic>>().toList();
        } catch (_) {
          modelStats = [];
        }
      }

      final fps = (status['fps'] as num?)?.toDouble() ?? 0;
      var fpsHistory = List<double>.from(_fpsHistory)..add(fps);
      if (fpsHistory.length > 40) fpsHistory = fpsHistory.sublist(fpsHistory.length - 40);

      if (mounted) {
        setState(() {
          _pipelineStatus = status;
          _health = health;
          _instanceStatusCounts = statusCounts;
          _modelStats = modelStats;
          _fpsHistory = fpsHistory;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _health = {'status': 'offline'};
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isWide = MediaQuery.of(context).size.width > 900;

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _fetchData,
        color: colorScheme.primary,
        backgroundColor: colorScheme.surface,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.symmetric(
            horizontal: isWide ? 32 : 16,
            vertical: isWide ? 40 : 24,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_isLoading)
                LinearProgressIndicator(
                  minHeight: 2,
                  backgroundColor: colorScheme.surface.withValues(alpha: 0),
                  valueColor: AlwaysStoppedAnimation<Color>(colorScheme.primary),
                ),
              if (_isLoading) const SizedBox(height: 24),

              // Page Header
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Overview',
                        style: theme.textTheme.displaySmall?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Real-time metrics and pipeline orchestration',
                        style: theme.textTheme.bodyLarge?.copyWith(color: colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                  const SizedBox(width: 16, height: 16),
                  _buildQuickActions(theme),
                ],
              ),
              const SizedBox(height: 32),

              // KPI Cards - Bento Top Row
              _buildKPICards(theme),
              const SizedBox(height: 24),

              // Bento Grid Layout
              if (isWide)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 5, child: _buildMainAnalytics(theme)),
                    const SizedBox(width: 24),
                    Expanded(flex: 3, child: _buildSideAnalytics(theme)),
                  ],
                )
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildMainAnalytics(theme),
                    const SizedBox(height: 24),
                    _buildSideAnalytics(theme),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuickActions(ThemeData theme) {
    final colorScheme = theme.colorScheme;
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        FilledButton.tonalIcon(
          onPressed: () => widget.onNavigate?.call(1),
          icon: const Icon(Icons.view_module_rounded, size: 20),
          label: const Text('Monitor'),
        ),
        OutlinedButton.icon(
          onPressed: () => widget.onNavigate?.call(3),
          icon: const Icon(Icons.tune_rounded, size: 20),
          label: const Text('Admin'),
          style: OutlinedButton.styleFrom(
            foregroundColor: colorScheme.onSurface,
          ),
        ),
      ],
    );
  }

  Widget _buildKPICards(ThemeData theme) {
    final colorScheme = theme.colorScheme;
    final statusColors = theme.extension<AppStatusColors>() ?? AppStatusColors.fallback;
    final isOnline = _health?['status'] == 'ok';
    final isRunning = _pipelineStatus?['is_running'] == true;
    final fps = _pipelineStatus?['fps']?.toString() ?? '0';
    final framesProcessed = _pipelineStatus?['frames_processed']?.toString() ?? '0';

    return LayoutBuilder(builder: (context, constraints) {
      final double width = (constraints.maxWidth - (16 * 3)) / 4;
      final double cardWidth = width < 220 ? double.infinity : width; // Stack if too small

      return Wrap(
        spacing: 16,
        runSpacing: 16,
        children: [
          _StatCard(
            title: 'System Status',
            value: isOnline ? 'Online' : 'Offline',
            icon: Icons.dns_rounded,
            color: isOnline ? statusColors.success : colorScheme.error,
            width: cardWidth,
          ),
          _StatCard(
            title: 'Pipeline Engine',
            value: isRunning ? 'Active' : 'Stopped',
            icon: Icons.memory_rounded,
            color: isRunning ? colorScheme.primary : statusColors.warning,
            width: cardWidth,
          ),
          _StatCard(
            title: 'Current FPS',
            value: '$fps fps',
            icon: Icons.speed_rounded,
            color: colorScheme.secondary,
            width: cardWidth,
          ),
          _StatCard(
            title: 'Processed Frames',
            value: framesProcessed,
            icon: Icons.photo_library_rounded,
            color: colorScheme.onSurface,
            width: cardWidth,
          ),
        ],
      );
    });
  }

  Widget _buildMainAnalytics(ThemeData theme) {
    final colorScheme = theme.colorScheme;
    return Column(
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'FPS History & Performance',
                  style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  height: 250,
                  child: _FpsSparkline(
                    values: _fpsHistory,
                    lineColor: colorScheme.primary,
                    gridColor: colorScheme.outlineVariant.withValues(alpha: 0.65),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Camera Instances Distribution',
                  style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  height: 200,
                  child: _LabeledBarChart(
                    values: {
                      'Running': (_instanceStatusCounts['running'] ?? 0).toDouble(),
                      'Paused': (_instanceStatusCounts['paused'] ?? 0).toDouble(),
                      'Stopped': (_instanceStatusCounts['stopped'] ?? 0).toDouble(),
                      'Idle': (_instanceStatusCounts['idle'] ?? 0).toDouble(),
                    },
                    barColor: colorScheme.tertiary,
                    valueSuffix: '',
                    emptyLabel: 'No instance data',
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSideAnalytics(ThemeData theme) {
    final colorScheme = theme.colorScheme;
    final statusColors = theme.extension<AppStatusColors>() ?? AppStatusColors.fallback;
    final detectionByModel = <String, double>{};
    final latencyByModel = <String, double>{};

    for (final row in _modelStats) {
      final model = (row['model_name'] as String?) ?? 'unknown';
      final detections = (row['total_detections'] as num?)?.toDouble() ?? 0;
      final latency = (row['avg_processing_time_ms'] as num?)?.toDouble() ?? 0;
      detectionByModel[model] = detections;
      latencyByModel[model] = latency;
    }

    final models = _pipelineStatus?['models_loaded'] as List<dynamic>? ?? [];

    return Column(
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.auto_awesome, color: colorScheme.primary),
                    const SizedBox(width: 12),
                    Text(
                      'Active ML Models',
                      style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (models.isEmpty)
                  Text('No models loaded', style: theme.textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant))
                else
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: models
                        .map((m) => Chip(
                              label: Text(m.toString()),
                              visualDensity: VisualDensity.compact,
                            ))
                        .toList(),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Detection Counts',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 180,
                  child: _LabeledBarChart(
                    values: detectionByModel,
                    barColor: statusColors.success,
                    valueSuffix: '',
                    emptyLabel: 'No detection stats yet',
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Average Latency',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 180,
                  child: _LabeledBarChart(
                    values: latencyByModel,
                    barColor: statusColors.warning,
                    valueSuffix: 'ms',
                    emptyLabel: 'No timing data yet',
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;
  final double width;

  const _StatCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    required this.width,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final cardChild = Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              Icon(Icons.more_horiz, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.55)),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            value,
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            title,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );

    return SizedBox(
      width: width,
      child: Card(child: cardChild),
    );
  }
}

// Chart wrappers
class _FpsSparkline extends StatelessWidget {
  final List<double> values;
  final Color lineColor;
  final Color gridColor;

  const _FpsSparkline({
    required this.values,
    required this.lineColor,
    required this.gridColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (values.isEmpty) {
      return const Center(child: Text('No FPS data recorded yet.'));
    }

    final dataPoints = values.asMap().entries.map((e) {
      return FlSpot(e.key.toDouble(), e.value);
    }).toList();

    final maxY = (values.reduce((a, b) => a > b ? a : b) * 1.2).clamp(30.0, 150.0);

    return LineChart(
      LineChartData(
        minY: 0,
        maxY: maxY.toDouble(),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (value) => FlLine(color: gridColor, strokeWidth: 1),
        ),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              getTitlesWidget: (val, meta) => Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text(
                  val.toInt().toString(),
                  style: theme.textTheme.labelSmall?.copyWith(color: colorScheme.onSurfaceVariant) ??
                      TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 12),
                  textAlign: TextAlign.right,
                ),
              ),
            ),
          ),
          bottomTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(show: false),
        lineBarsData: [
          LineChartBarData(
            spots: dataPoints,
            isCurved: true,
            color: lineColor,
            barWidth: 3,
            isStrokeCapRound: true,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: lineColor.withOpacity(0.15),
            ),
          ),
        ],
      ),
    );
  }
}

class _LabeledBarChart extends StatelessWidget {
  final Map<String, double> values;
  final Color barColor;
  final String valueSuffix;
  final String emptyLabel;

  const _LabeledBarChart({
    required this.values,
    required this.barColor,
    required this.valueSuffix,
    required this.emptyLabel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (values.isEmpty || values.values.every((v) => v == 0)) {
      return Center(child: Text(emptyLabel));
    }

    final keys = values.keys.toList();
    final maxValue = values.values.reduce((a, b) => a > b ? a : b);
    final upperLimit = (maxValue * 1.2).clamp(10.0, double.infinity);

    final barGroups = keys.asMap().entries.map((e) {
      final idx = e.key;
      final val = values[e.value] ?? 0;
      return BarChartGroupData(
        x: idx,
        barRods: [
          BarChartRodData(
            toY: val,
            color: barColor,
            width: 24,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
            backDrawRodData: BackgroundBarChartRodData(
              show: true,
              toY: upperLimit,
              color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
            ),
          ),
        ],
      );
    }).toList();

    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: upperLimit,
        barTouchData: BarTouchData(
          enabled: true,
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => colorScheme.surfaceContainerHighest,
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              return BarTooltipItem(
                '${keys[groupIndex]}\n${rod.toY.toStringAsFixed(1)}$valueSuffix',
                theme.textTheme.labelLarge?.copyWith(
                      color: colorScheme.onSurface,
                      fontWeight: FontWeight.w800,
                    ) ??
                    TextStyle(color: colorScheme.onSurface, fontWeight: FontWeight.w800),
              );
            },
          ),
        ),
        titlesData: FlTitlesData(
          show: true,
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (double value, TitleMeta meta) {
                final text = keys[value.toInt()];
                return Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Text(
                    text.length > 10 ? '${text.substring(0, 8)}...' : text,
                    style: theme.textTheme.labelSmall?.copyWith(color: colorScheme.onSurfaceVariant) ??
                        TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 11),
                  ),
                );
              },
            ),
          ),
          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        barGroups: barGroups,
      ),
    );
  }
}

