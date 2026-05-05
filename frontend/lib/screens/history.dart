import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../config/app_config.dart';

class _SeekIntent extends Intent {
  const _SeekIntent(this.seconds);
  final double seconds;
}

class _TogglePlayIntent extends Intent {
  const _TogglePlayIntent();
}

/// History Screen
/// Shows past sessions and their results
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final ApiService _api = ApiService();
  List<dynamic> _sessions = [];
  List<dynamic> _recordings = [];
  List<dynamic> _incidents = [];
  List<dynamic> _patients = [];
  bool _isLoading = true;
  bool _isIncidentLoading = false;
  int _selectedView = 0;
  int _incidentTotal = 0;
  int? _incidentPatientFilter;
  String _incidentStatusFilter = 'all';
  String _incidentEventTypeFilter = 'all';
  DateTimeRange? _incidentDateRange;
  String? _incidentError;

  @override
  void initState() {
    super.initState();
    _fetchSessions();
  }

  @override
  void dispose() {
    _api.dispose();
    super.dispose();
  }

  Future<void> _fetchSessions() async {
    if (mounted) {
      setState(() => _isLoading = true);
    }

    try {
      final sessionsFuture = _api.getSessions();
      final recordingsFuture = _api.getRecordings();

      final sessions = await sessionsFuture;
      final recordings = await recordingsFuture;

      if (mounted) {
        setState(() {
          _sessions = sessions;
          _recordings = recordings;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }

    try {
      final patients = await _api.getPatients();
      if (mounted) {
        setState(() => _patients = patients);
      }
    } catch (_) {}

    await _loadIncidents();
  }

  Future<void> _loadIncidents() async {
    if (mounted) {
      setState(() {
        _isIncidentLoading = true;
        _incidentError = null;
      });
    }

    try {
      final response = await _api.getIncidents(
        patientId: _incidentPatientFilter,
        status: _incidentStatusFilter == 'all' ? null : _incidentStatusFilter,
        eventType: _incidentEventTypeFilter == 'all' ? null : _incidentEventTypeFilter,
        startTime: _incidentDateRange?.start,
        endTime: _incidentDateRange?.end,
      );
      if (!mounted) return;
      final items = (response['items'] as List<dynamic>? ?? const []);
      final total = response['total'];
      setState(() {
        _incidents = items;
        _incidentTotal = total is num ? total.toInt() : items.length;
        _isIncidentLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _incidents = [];
        _incidentTotal = 0;
        _isIncidentLoading = false;
        _incidentError = 'Sign in as admin/caregiver to review incidents.';
      });
    }
  }

  Future<void> _pickIncidentDateRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 1),
      initialDateRange: _incidentDateRange,
    );
    if (picked == null) return;
    setState(() => _incidentDateRange = picked);
    await _loadIncidents();
  }

  Future<void> _acknowledgeIncident(int incidentId) async {
    try {
      await _api.acknowledgeIncident(incidentId);
      await _loadIncidents();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to acknowledge incident: $e')),
      );
    }
  }

  Future<void> _resolveIncident(int incidentId) async {
    try {
      await _api.resolveIncident(incidentId);
      await _loadIncidents();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to resolve incident: $e')),
      );
    }
  }

  String _formatIncidentDate(dynamic rawValue) {
    if (rawValue == null) return '-';
    try {
      final parsed = DateTime.parse(rawValue.toString()).toLocal();
      return '${parsed.year.toString().padLeft(4, '0')}-${parsed.month.toString().padLeft(2, '0')}-${parsed.day.toString().padLeft(2, '0')} '
          '${parsed.hour.toString().padLeft(2, '0')}:${parsed.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return rawValue.toString();
    }
  }

  void _showIncidentDetails(Map<String, dynamic> incident) {
    showDialog<void>(
      context: context,
      builder: (context) {
        final details = incident['details'];
        final detailsMap = details is Map ? Map<String, dynamic>.from(details) : null;
        final detailsText = detailsMap != null
            ? const JsonEncoder.withIndent('  ').convert(detailsMap)
            : (details?.toString() ?? '{}');
        return AlertDialog(
          title: Text('Incident #${incident['id'] ?? '-'} details'),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: SelectableText(
                'Event: ${incident['event_type'] ?? '-'}\n'
                'Status: ${incident['status'] ?? '-'}\n'
                'Severity: ${incident['severity'] ?? '-'}\n'
                'Detected: ${_formatIncidentDate(incident['detected_at'])}\n'
                'Patient ID: ${incident['patient_id'] ?? '-'}\n'
                'Camera ID: ${incident['camera_config_id'] ?? '-'}\n'
                'Session ID: ${incident['session_id'] ?? '-'}\n'
                'Confidence: ${incident['confidence'] ?? '-'}\n'
                'Threshold: ${incident['threshold'] ?? '-'}\n\n'
                'Details:\n$detailsText',
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final child = switch (_selectedView) {
      0 => _buildSessionsView(context, theme),
      1 => _buildRecordingsView(context, theme),
      _ => _buildIncidentsView(context, theme),
    };

    return Scaffold(
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: colorScheme.primary))
          : RefreshIndicator(
              color: colorScheme.primary,
              backgroundColor: colorScheme.surface,
              onRefresh: _fetchSessions,
              child: child,
            ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(bottom: BorderSide(color: colorScheme.outlineVariant)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 640;
          final titleRow = Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  Icons.insights_rounded,
                  color: colorScheme.onPrimaryContainer,
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'Insights',
                style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
            ],
          );

          final segmented = _HistoryHeader(
            selectedIndex: _selectedView,
            sessionsCount: _sessions.length,
            recordingsCount: _recordings.length,
            incidentsCount: _incidentTotal,
            onChanged: (value) => setState(() => _selectedView = value),
          );

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                titleRow,
                const SizedBox(height: 10),
                segmented,
              ],
            );
          }

          return Row(
            children: [
              titleRow,
              const Spacer(),
              segmented,
            ],
          );
        },
      ),
    );
  }

  Widget _buildSessionsView(BuildContext context, ThemeData theme) {
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;

    return Column(
      children: [
        _buildHeader(theme),
        Expanded(
          child: _sessions.isEmpty
              ? ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
                  children: [
                    SizedBox(
                      height: MediaQuery.of(context).size.height * 0.6,
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.history_rounded,
                              size: 64,
                              color: colorScheme.onSurface.withValues(alpha: 0.2),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No sessions yet',
                              style: textTheme.titleMedium?.copyWith(
                                color: colorScheme.onSurface.withValues(alpha: 0.6),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Start the pipeline to create a session',
                              style: textTheme.bodyMedium?.copyWith(
                                color: colorScheme.onSurface.withValues(alpha: 0.4),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                )
              : ListView.builder(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  itemCount: _sessions.length,
                  itemBuilder: (context, index) {
                    final session = _sessions[index] as Map<String, dynamic>;
                    return Align(
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1120),
                        child: _SessionCard(
                          session: session,
                          colorScheme: theme.colorScheme,
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildRecordingsView(BuildContext context, ThemeData theme) {
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;

    return Column(
      children: [
        _buildHeader(theme),
        Expanded(
          child: _recordings.isEmpty
              ? ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
                  children: [
                    SizedBox(
                      height: MediaQuery.of(context).size.height * 0.6,
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.video_library_rounded,
                              size: 64,
                              color: colorScheme.onSurface.withValues(alpha: 0.2),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No recordings yet',
                              style: textTheme.titleMedium?.copyWith(
                                color: colorScheme.onSurface.withValues(alpha: 0.6),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Start and stop a recording from Multi-Cam controls',
                              style: textTheme.bodyMedium?.copyWith(
                                color: colorScheme.onSurface.withValues(alpha: 0.4),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                )
              : ListView.builder(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  itemCount: _recordings.length,
                  itemBuilder: (context, index) {
                    final recording = _recordings[index] as Map<String, dynamic>;
                    return Align(
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1120),
                        child: _RecordingCard(
                          recording: recording,
                          colorScheme: theme.colorScheme,
                          onPlay: () {
                            showDialog<void>(
                              context: context,
                              builder: (_) => _RecordingPlayerDialog(recording: recording),
                            );
                          },
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildIncidentsView(BuildContext context, ThemeData theme) {
    final colorScheme = theme.colorScheme;

    return Column(
      children: [
        _buildHeader(theme),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: colorScheme.surface,
            border: Border(bottom: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5))),
          ),
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1120),
              child: Wrap(
                spacing: 10,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: 170,
                    child: DropdownButtonFormField<String>(
                      value: _incidentStatusFilter,
                      decoration: const InputDecoration(labelText: 'Status', isDense: true),
                      items: const [
                        DropdownMenuItem(value: 'all', child: Text('All')),
                        DropdownMenuItem(value: 'new', child: Text('New')),
                        DropdownMenuItem(value: 'acknowledged', child: Text('Acknowledged')),
                        DropdownMenuItem(value: 'resolved', child: Text('Resolved')),
                      ],
                      onChanged: (value) => setState(() => _incidentStatusFilter = value ?? 'all'),
                    ),
                  ),
                  SizedBox(
                    width: 170,
                    child: DropdownButtonFormField<String>(
                      value: _incidentEventTypeFilter,
                      decoration: const InputDecoration(labelText: 'Type', isDense: true),
                      items: const [
                        DropdownMenuItem(value: 'all', child: Text('All')),
                        DropdownMenuItem(value: 'fall', child: Text('Fall')),
                        DropdownMenuItem(value: 'seizure', child: Text('Seizure')),
                        DropdownMenuItem(value: 'manual', child: Text('Manual')),
                      ],
                      onChanged: (value) => setState(() => _incidentEventTypeFilter = value ?? 'all'),
                    ),
                  ),
                  SizedBox(
                    width: 260,
                    child: DropdownButtonFormField<int?>(
                      value: _incidentPatientFilter,
                      decoration: const InputDecoration(labelText: 'Patient', isDense: true),
                      items: [
                        const DropdownMenuItem<int?>(value: null, child: Text('All patients')),
                        ..._patients.map((raw) {
                          final patient = Map<String, dynamic>.from(raw as Map);
                          final patientId = (patient['id'] as num?)?.toInt();
                          final name = patient['full_name']?.toString() ?? 'Patient #${patient['id'] ?? '-'}';
                          return DropdownMenuItem<int?>(
                            value: patientId,
                            child: Text(name, overflow: TextOverflow.ellipsis),
                          );
                        }),
                      ],
                      onChanged: (value) => setState(() => _incidentPatientFilter = value),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: _pickIncidentDateRange,
                    icon: const Icon(Icons.date_range_rounded),
                    label: Text(
                      _incidentDateRange == null
                          ? 'Any date'
                          : '${_incidentDateRange!.start.toLocal().toString().substring(0, 10)} → ${_incidentDateRange!.end.toLocal().toString().substring(0, 10)}',
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: _loadIncidents,
                    icon: const Icon(Icons.search_rounded),
                    label: const Text('Apply'),
                  ),
                  TextButton.icon(
                    onPressed: () async {
                      setState(() {
                        _incidentStatusFilter = 'all';
                        _incidentEventTypeFilter = 'all';
                        _incidentPatientFilter = null;
                        _incidentDateRange = null;
                      });
                      await _loadIncidents();
                    },
                    icon: const Icon(Icons.clear_rounded),
                    label: const Text('Clear'),
                  ),
                ],
              ),
            ),
          ),
        ),
        Expanded(
          child: _isIncidentLoading
              ? const Center(child: CircularProgressIndicator())
              : _incidentError != null
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            _incidentError!,
                            style: TextStyle(color: colorScheme.error, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    )
                  : _incidents.isEmpty
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: const [
                            Padding(
                              padding: EdgeInsets.all(24),
                              child: Text('No incidents found for the selected filters.'),
                            ),
                          ],
                        )
                      : ListView.builder(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.all(16),
                          itemCount: _incidents.length,
                          itemBuilder: (context, index) {
                            final incident = Map<String, dynamic>.from(_incidents[index] as Map);
                            final incidentId = (incident['id'] as num?)?.toInt();
                            final status = (incident['status'] ?? '').toString().toLowerCase();
                            return Align(
                              alignment: Alignment.topCenter,
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: 1120),
                                child: _IncidentCard(
                                  incident: incident,
                                  onOpenDetails: () => _showIncidentDetails(incident),
                                  onAcknowledge: incidentId != null && status == 'new'
                                      ? () => _acknowledgeIncident(incidentId)
                                      : null,
                                  onResolve: incidentId != null && status != 'resolved'
                                      ? () => _resolveIncident(incidentId)
                                      : null,
                                  formatDate: _formatIncidentDate,
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

class _HistoryHeader extends StatelessWidget {
  final int selectedIndex;
  final int sessionsCount;
  final int recordingsCount;
  final int incidentsCount;
  final ValueChanged<int> onChanged;

  const _HistoryHeader({
    required this.selectedIndex,
    required this.sessionsCount,
    required this.recordingsCount,
    required this.incidentsCount,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SegmentedButton<int>(
        segments: [
          ButtonSegment<int>(value: 0, label: Text('Sessions ($sessionsCount)'), icon: const Icon(Icons.history_rounded)),
          ButtonSegment<int>(value: 1, label: Text('Recordings ($recordingsCount)'), icon: const Icon(Icons.video_library_rounded)),
          ButtonSegment<int>(value: 2, label: Text('Incidents ($incidentsCount)'), icon: const Icon(Icons.warning_amber_rounded)),
        ],
        selected: {selectedIndex},
        onSelectionChanged: (selection) => onChanged(selection.first),
        showSelectedIcon: false,
      ),
    );
  }
}

class _SessionCard extends StatefulWidget {
  final Map<String, dynamic> session;
  final ColorScheme colorScheme;

  const _SessionCard({
    required this.session,
    required this.colorScheme,
  });

  @override
  State<_SessionCard> createState() => _SessionCardState();
}

class _SessionCardState extends State<_SessionCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final statusColors = theme.extension<AppStatusColors>() ?? AppStatusColors.fallback;
    final status = widget.session['status']?.toString() ?? 'unknown';
    final isDark = theme.brightness == Brightness.dark;

    final statusColor = status == 'running'
        ? colorScheme.primary
        : status == 'completed'
            ? statusColors.success
            : statusColors.warning;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 16),
        transform: Matrix4.identity()..translateByDouble(_isHovered ? 5.0 : 0.0, 0.0, 0.0, 1.0),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest.withValues(alpha: isDark ? 0.3 : 0.5),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: _isHovered 
                ? statusColor.withValues(alpha: 0.5) 
                : colorScheme.outlineVariant.withValues(alpha: 0.5),
            width: 1.5,
          ),
          boxShadow: [
            if (_isHovered)
              BoxShadow(
                color: statusColor.withValues(alpha: 0.15),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
          ],
        ),
        child: ListTile(
          contentPadding: const EdgeInsets.all(20),
          leading: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              status == 'running'
                  ? Icons.play_circle_rounded
                  : Icons.check_circle_rounded,
              color: statusColor,
              size: 28,
            ),
          ),
          title: Text(
            widget.session['name']?.toString() ?? 'Session Analytics',
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              children: [
                Icon(Icons.videocam_rounded, size: 14, color: colorScheme.onSurface.withValues(alpha: 0.5)),
                const SizedBox(width: 4),
                Text(
                  widget.session['camera_source'] ?? 'Unknown Source',
                  style: TextStyle(color: colorScheme.onSurface.withValues(alpha: 0.7), fontWeight: FontWeight.w500),
                ),
                const SizedBox(width: 16),
                Icon(Icons.access_time_rounded, size: 14, color: colorScheme.onSurface.withValues(alpha: 0.5)),
                const SizedBox(width: 4),
                Text(
                  widget.session['started_at']?.toString().substring(0, 19) ?? 'Recently',
                  style: TextStyle(color: colorScheme.onSurface.withValues(alpha: 0.7), fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              PopupMenuButton<String>(
                icon: const Icon(Icons.download_rounded),
                tooltip: 'Export session',
                onSelected: (value) async {
                  final sessionId = widget.session['id'];
                  if (sessionId == null) return;
                  if (value == 'json') {
                    await launchUrl(
                      Uri.parse('${AppConfig.apiBaseUrl}/api/results/session/$sessionId/export/json'),
                      webOnlyWindowName: '_blank',
                    );
                  } else if (value == 'csv') {
                    await launchUrl(
                      Uri.parse('${AppConfig.apiBaseUrl}/api/results/session/$sessionId/export/csv'),
                      webOnlyWindowName: '_blank',
                    );
                  }
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'json', child: Text('Export Results JSON')),
                  PopupMenuItem(value: 'csv', child: Text('Export Results CSV')),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                ),
                child: Text(
                  status.toUpperCase(),
                  style: TextStyle(
                    color: statusColor,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _IncidentCard extends StatelessWidget {
  final Map<String, dynamic> incident;
  final VoidCallback onOpenDetails;
  final Future<void> Function()? onAcknowledge;
  final Future<void> Function()? onResolve;
  final String Function(dynamic) formatDate;

  const _IncidentCard({
    required this.incident,
    required this.onOpenDetails,
    required this.onAcknowledge,
    required this.onResolve,
    required this.formatDate,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final statusColors = theme.extension<AppStatusColors>() ?? AppStatusColors.fallback;
    final eventType = (incident['event_type'] ?? 'manual').toString();
    final status = (incident['status'] ?? 'new').toString();
    final severity = (incident['severity'] ?? 'warning').toString();

    final statusColor = switch (status) {
      'resolved' => statusColors.success,
      'acknowledged' => colorScheme.primary,
      _ => colorScheme.error,
    };
    final typeIcon = switch (eventType) {
      'fall' => Icons.personal_injury_rounded,
      'seizure' => Icons.bolt_rounded,
      _ => Icons.flag_rounded,
    };

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: statusColor.withValues(alpha: 0.15),
                  child: Icon(typeIcon, color: statusColor),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${eventType.toUpperCase()} incident #${incident['id'] ?? '-'}',
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Detected ${formatDate(incident['detected_at'])}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurface.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    status.toUpperCase(),
                    style: TextStyle(
                      color: statusColor,
                      fontWeight: FontWeight.w700,
                      fontSize: 11,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 14,
              runSpacing: 8,
              children: [
                Text('Severity: $severity'),
                Text('Patient: ${incident['patient_id'] ?? '-'}'),
                Text('Camera: ${incident['camera_config_id'] ?? '-'}'),
                Text('Confidence: ${incident['confidence'] ?? '-'}'),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: onOpenDetails,
                  icon: const Icon(Icons.open_in_new_rounded),
                  label: const Text('Details'),
                ),
                FilledButton.tonalIcon(
                  onPressed: onAcknowledge == null ? null : () => onAcknowledge!(),
                  icon: const Icon(Icons.check_circle_outline_rounded),
                  label: const Text('Acknowledge'),
                ),
                FilledButton.icon(
                  onPressed: onResolve == null ? null : () => onResolve!(),
                  icon: const Icon(Icons.task_alt_rounded),
                  label: const Text('Resolve'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RecordingCard extends StatelessWidget {
  final Map<String, dynamic> recording;
  final ColorScheme colorScheme;
  final VoidCallback onPlay;

  const _RecordingCard({
    required this.recording,
    required this.colorScheme,
    required this.onPlay,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusColors = theme.extension<AppStatusColors>() ?? AppStatusColors.fallback;
    final status = (recording['status'] ?? 'unknown').toString();
    final isCompleted = status.toLowerCase() == 'completed';
    final stateColor = isCompleted ? statusColors.success : statusColors.warning;
    final fileSizeBytes = (recording['file_size_bytes'] as num?)?.toDouble() ?? 0;
    final fileSizeMb = fileSizeBytes / (1024 * 1024);
    final duration = (recording['duration_seconds'] as num?)?.toDouble() ?? 0;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        leading: CircleAvatar(
          backgroundColor: stateColor.withValues(alpha: 0.15),
          child: Icon(
            isCompleted ? Icons.play_circle_fill_rounded : Icons.radio_button_checked_rounded,
            color: stateColor,
          ),
        ),
        title: Text(recording['name']?.toString() ?? 'Recording #${recording['id']}'),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            '${duration.toStringAsFixed(1)}s • ${fileSizeMb > 0 ? '${fileSizeMb.toStringAsFixed(2)} MB' : 'size pending'} • ${recording['codec'] ?? 'codec pending'}',
            style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65)),
          ),
        ),
        trailing: FilledButton.icon(
          onPressed: isCompleted
              ? () {
                  showModalBottomSheet<void>(
                    context: context,
                    showDragHandle: true,
                    builder: (_) => SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Wrap(
                          children: [
                            ListTile(
                              leading: const Icon(Icons.play_circle_fill_rounded),
                              title: const Text('Play'),
                              onTap: () {
                                Navigator.of(context).pop();
                                onPlay();
                              },
                            ),
                            ListTile(
                              leading: const Icon(Icons.download_rounded),
                              title: const Text('Download Video'),
                              onTap: () async {
                                Navigator.of(context).pop();
                                await _openExternalUrl(
                                  Uri.parse('${AppConfig.apiBaseUrl}/api/recordings/${recording['id']}/download'),
                                );
                              },
                            ),
                            ListTile(
                              leading: const Icon(Icons.data_object_rounded),
                              title: const Text('Export JSON Metadata'),
                              onTap: () async {
                                Navigator.of(context).pop();
                                await _openExternalUrl(
                                  Uri.parse('${AppConfig.apiBaseUrl}/api/recordings/${recording['id']}/export/json'),
                                );
                              },
                            ),
                            ListTile(
                              leading: const Icon(Icons.table_chart_rounded),
                              title: const Text('Export CSV Metadata'),
                              onTap: () async {
                                Navigator.of(context).pop();
                                await _openExternalUrl(
                                  Uri.parse('${AppConfig.apiBaseUrl}/api/recordings/${recording['id']}/export/csv'),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }
              : null,
          icon: const Icon(Icons.more_horiz_rounded),
          label: const Text('Actions'),
        ),
      ),
    );
  }

  Future<void> _openExternalUrl(Uri uri) async {
    await launchUrl(uri, webOnlyWindowName: '_blank');
  }
}

class _RecordingPlayerDialog extends StatefulWidget {
  final Map<String, dynamic> recording;

  const _RecordingPlayerDialog({required this.recording});

  @override
  State<_RecordingPlayerDialog> createState() => _RecordingPlayerDialogState();
}

class _RecordingPlayerDialogState extends State<_RecordingPlayerDialog> {
  VideoPlayerController? _controller;
  double _playbackSpeed = 1.0;
  bool _isReady = false;
  String? _loadError;
  late final FocusNode _focusNode;

  String get _streamUrl => '${AppConfig.apiBaseUrl}/api/recordings/${widget.recording['id']}/stream';

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    try {
      final controller = VideoPlayerController.networkUrl(Uri.parse(_streamUrl));
      await controller.initialize();
      controller.setPlaybackSpeed(_playbackSpeed);
      setState(() {
        _controller = controller;
        _isReady = true;
      });
    } catch (e) {
      setState(() => _loadError = e.toString());
    }
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _controller?.dispose();
    super.dispose();
  }

  String _fmt(Duration d) {
    final totalSeconds = d.inSeconds;
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  void _seekBySeconds(double deltaSeconds) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    final current = controller.value.position;
    final target = current + Duration(milliseconds: (deltaSeconds * 1000).round());
    final bounded = target < Duration.zero
        ? Duration.zero
        : (target > controller.value.duration ? controller.value.duration : target);
    controller.seekTo(bounded);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;

    return Dialog(
      child: FocusableActionDetector(
        autofocus: true,
        focusNode: _focusNode,
        shortcuts: const <ShortcutActivator, Intent>{
          SingleActivator(LogicalKeyboardKey.space): _TogglePlayIntent(),
          SingleActivator(LogicalKeyboardKey.arrowLeft): _SeekIntent(-10),
          SingleActivator(LogicalKeyboardKey.arrowRight): _SeekIntent(10),
          SingleActivator(LogicalKeyboardKey.keyJ): _SeekIntent(-10),
          SingleActivator(LogicalKeyboardKey.keyL): _SeekIntent(10),
        },
        actions: <Type, Action<Intent>>{
          _TogglePlayIntent: CallbackAction<_TogglePlayIntent>(
            onInvoke: (intent) {
              final c = _controller;
              if (c == null || !c.value.isInitialized) return null;
              if (c.value.isPlaying) {
                c.pause();
              } else {
                c.play();
              }
              setState(() {});
              return null;
            },
          ),
          _SeekIntent: CallbackAction<_SeekIntent>(
            onInvoke: (intent) {
              _seekBySeconds(intent.seconds);
              return null;
            },
          ),
        },
        child: SizedBox(
          width: 880,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.recording['name']?.toString() ?? 'Recording Playback',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                if (_loadError != null)
                  Text('Failed to load recording: $_loadError')
                else if (!_isReady || controller == null)
                  const SizedBox(height: 280, child: Center(child: CircularProgressIndicator()))
                else
                  ValueListenableBuilder<VideoPlayerValue>(
                    valueListenable: controller,
                    builder: (context, value, _) {
                      final current = value.position;
                      final total = value.duration;
                      return Column(
                        children: [
                          AspectRatio(
                            aspectRatio: value.aspectRatio > 0 ? value.aspectRatio : 16 / 9,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: VideoPlayer(controller),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              IconButton(
                                tooltip: 'Back 10s (Left/J)',
                                onPressed: () => _seekBySeconds(-10),
                                icon: const Icon(Icons.replay_10_rounded),
                              ),
                              IconButton(
                                tooltip: 'Play/Pause (Space)',
                                onPressed: () {
                                  if (value.isPlaying) {
                                    controller.pause();
                                  } else {
                                    controller.play();
                                  }
                                  setState(() {});
                                },
                                icon: Icon(value.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded),
                              ),
                              IconButton(
                                tooltip: 'Forward 10s (Right/L)',
                                onPressed: () => _seekBySeconds(10),
                                icon: const Icon(Icons.forward_10_rounded),
                              ),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    VideoProgressIndicator(
                                      controller,
                                      allowScrubbing: true,
                                      padding: const EdgeInsets.symmetric(horizontal: 8),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(_fmt(current), style: Theme.of(context).textTheme.bodySmall),
                                          Text(_fmt(total), style: Theme.of(context).textTheme.bodySmall),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              DropdownButton<double>(
                                value: _playbackSpeed,
                                onChanged: (value) {
                                  if (value == null) return;
                                  setState(() => _playbackSpeed = value);
                                  controller.setPlaybackSpeed(value);
                                },
                                items: const [0.5, 1.0, 1.5, 2.0]
                                    .map((s) => DropdownMenuItem(value: s, child: Text('${s}x')))
                                    .toList(),
                              ),
                            ],
                          ),
                        ],
                      );
                    },
                  ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Close'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

