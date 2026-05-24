import 'dart:async';

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
import '../../widgets/empty_state.dart';
import '../../widgets/incident_tile.dart';
import '../../widgets/mobile_sheet.dart';
import '../../widgets/section_header.dart';
import '../../widgets/severity_pill.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/status_pill.dart';

class IncidentsScreen extends StatefulWidget {
  const IncidentsScreen({super.key});

  @override
  State<IncidentsScreen> createState() => _IncidentsScreenState();
}

class _IncidentsScreenState extends State<IncidentsScreen> {
  final ApiService _api = ApiService();
  bool _loading = false;
  String? _error;
  List<Map<String, dynamic>> _incidents = [];
  int _total = 0;

  String _statusFilter = 'all';
  String _eventFilter = 'all';
  int? _patientFilter;
  DateTimeRange? _dateRange;

  List<Map<String, dynamic>> _patients = [];

  StreamSubscription? _eventSub;

  @override
  void initState() {
    super.initState();
    _initialLoad();
    final stream = context.read<IncidentStreamService>();
    _eventSub = stream.newIncidentStream.listen((_) => _load());
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    super.dispose();
  }

  Future<void> _initialLoad() async {
    final auth = context.read<AuthController>();
    if (auth.isCareTeam) {
      try {
        final patients = await _api.getPatients();
        if (mounted) setState(() => _patients = patients.cast<Map<String, dynamic>>());
      } catch (_) {}
    }
    await _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final resp = await _api.getIncidents(
        status: _statusFilter == 'all' ? null : _statusFilter,
        eventType: _eventFilter == 'all' ? null : _eventFilter,
        patientId: _patientFilter,
        startTime: _dateRange?.start,
        endTime: _dateRange?.end,
        limit: 100,
      );
      final items = ((resp['items'] as List?) ?? const []).cast<Map<String, dynamic>>();
      if (mounted) {
        setState(() {
          _incidents = items;
          _total = (resp['total'] as num?)?.toInt() ?? items.length;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Could not load incidents: $e';
          _loading = false;
        });
      }
    }
  }

  Future<void> _acknowledge(int id) async {
    HapticFeedback.mediumImpact();
    try {
      await _api.acknowledgeIncident(id);
      if (mounted) context.read<IncidentStreamService>().markStatusLocally(id, 'acknowledged');
      await _load();
    } catch (e) {
      _showError('Failed to acknowledge: $e');
    }
  }

  Future<void> _resolve(int id) async {
    HapticFeedback.mediumImpact();
    try {
      await _api.resolveIncident(id);
      if (mounted) context.read<IncidentStreamService>().markStatusLocally(id, 'resolved');
      await _load();
    } catch (e) {
      _showError('Failed to resolve: $e');
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _openDetail(Map<String, dynamic> inc) async {
    HapticFeedback.selectionClick();
    await showMobileSheet(
      context: context,
      initialChildSize: 0.72,
      builder: (sheetCtx, scrollCtrl) {
        return IncidentDetailSheet(
          incident: inc,
          scrollController: scrollCtrl,
          onAck: () async {
            Navigator.of(sheetCtx).pop();
            await _acknowledge(inc['id'] as int);
          },
          onResolve: () async {
            Navigator.of(sheetCtx).pop();
            await _resolve(inc['id'] as int);
          },
          onSaveNotes: (notes) async {
            try {
              await _api.updateIncident(inc['id'] as int, {'notes': notes});
              await _load();
            } catch (e) {
              _showError('Failed to save notes: $e');
            }
          },
        );
      },
    );
  }

  Future<void> _openFilters() async {
    HapticFeedback.lightImpact();
    final res = await showMobileSheet<bool>(
      context: context,
      initialChildSize: 0.6,
      builder: (sheetCtx, scrollCtrl) => _FiltersSheet(
        scrollController: scrollCtrl,
        statusFilter: _statusFilter,
        eventFilter: _eventFilter,
        patientFilter: _patientFilter,
        patients: _patients,
        dateRange: _dateRange,
        showPatientFilter: context.read<AuthController>().isCareTeam,
        onApply: (status, event, patient, range) {
          setState(() {
            _statusFilter = status;
            _eventFilter = event;
            _patientFilter = patient;
            _dateRange = range;
          });
          Navigator.of(sheetCtx).pop(true);
        },
        onReset: () {
          setState(() {
            _statusFilter = 'all';
            _eventFilter = 'all';
            _patientFilter = null;
            _dateRange = null;
          });
          Navigator.of(sheetCtx).pop(true);
        },
      ),
    );
    if (res == true) _load();
  }

  bool get _hasActiveFilters =>
      _statusFilter != 'all' || _eventFilter != 'all' || _patientFilter != null || _dateRange != null;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final newCount = _incidents.where((i) => i['status'] == 'new').length;
    final ackCount = _incidents.where((i) => i['status'] == 'acknowledged').length;
    final resolvedCount = _incidents.where((i) => i['status'] == 'resolved').length;

    return Column(
      children: [
        SectionHeader(
          title: 'Incidents',
          subtitle: 'Detected falls, seizures, and manual reports',
          icon: AppIcons.incidents,
          trailing: IconButton.filledTonal(
            tooltip: 'Refresh',
            icon: const Icon(AppIcons.refresh, size: 18),
            onPressed: () {
              HapticFeedback.lightImpact();
              _load();
            },
          ),
        ),

        // Count pills
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Row(
            children: [
              StatusPill(label: '$newCount new', kind: StatusKind.danger, pulse: newCount > 0),
              const SizedBox(width: 8),
              StatusPill(label: '$ackCount ack', kind: StatusKind.warning),
              const SizedBox(width: 8),
              StatusPill(label: '$resolvedCount resolved', kind: StatusKind.success),
            ],
          ),
        ),

        // Filter trigger
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
          child: GestureDetector(
            onTap: _openFilters,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: _hasActiveFilters
                      ? AppTheme.brandTeal.withValues(alpha: 0.45)
                      : cs.outlineVariant,
                  width: _hasActiveFilters ? 1.5 : 1,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.tune_rounded,
                    color: _hasActiveFilters ? AppTheme.brandTeal : cs.onSurfaceVariant,
                    size: 18,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    _hasActiveFilters ? 'Filters active' : 'Filter incidents',
                    style: GoogleFonts.outfit(
                      fontWeight: FontWeight.w600,
                      fontSize: 13.5,
                      color: _hasActiveFilters ? AppTheme.brandTeal : cs.onSurface,
                    ),
                  ),
                  const Spacer(),
                  if (_hasActiveFilters)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppTheme.brandTeal,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        _activeFilterCount.toString(),
                        style: GoogleFonts.outfit(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 11,
                        ),
                      ),
                    )
                  else
                    Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
                ],
              ),
            ),
          ),
        ),

        Expanded(
          child: _loading
              ? const SkeletonList(count: 6)
              : _error != null
                  ? Center(child: Text(_error!, style: TextStyle(color: cs.error)))
                  : _incidents.isEmpty
                      ? EmptyState(
                          icon: AppIcons.incidents,
                          title: 'All quiet',
                          subtitle: 'No incidents match your filters. Real-time alerts will appear here as they happen.',
                          actionLabel: _hasActiveFilters ? 'Clear filters' : null,
                          onAction: _hasActiveFilters
                              ? () {
                                  setState(() {
                                    _statusFilter = 'all';
                                    _eventFilter = 'all';
                                    _patientFilter = null;
                                    _dateRange = null;
                                  });
                                  _load();
                                }
                              : null,
                        )
                      : RefreshIndicator(
                          color: AppTheme.brandTeal,
                          onRefresh: () async {
                            HapticFeedback.mediumImpact();
                            await _load();
                          },
                          child: ListView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                            itemCount: _incidents.length,
                            itemBuilder: (_, i) {
                              final inc = _incidents[i];
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: IncidentTile(
                                  incident: inc,
                                  onTap: () => _openDetail(inc),
                                  onAcknowledge: () => _acknowledge(inc['id'] as int),
                                  onResolve: () => _resolve(inc['id'] as int),
                                )
                                    .animate()
                                    .fadeIn(duration: 260.ms, delay: (i * 30).ms)
                                    .slideY(begin: 0.06, duration: 320.ms, curve: Curves.easeOutCubic),
                              );
                            },
                          ),
                        ),
        ),

        if (_total > 0)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Text(
              'Showing ${_incidents.length} of $_total',
              style: GoogleFonts.dmSans(
                color: cs.onSurfaceVariant,
                fontSize: 11.5,
              ),
            ),
          ),
      ],
    );
  }

  int get _activeFilterCount {
    int c = 0;
    if (_statusFilter != 'all') c++;
    if (_eventFilter != 'all') c++;
    if (_patientFilter != null) c++;
    if (_dateRange != null) c++;
    return c;
  }
}

// ── Filters bottom sheet ──────────────────────────────────────────────────────
class _FiltersSheet extends StatefulWidget {
  final ScrollController scrollController;
  final String statusFilter;
  final String eventFilter;
  final int? patientFilter;
  final List<Map<String, dynamic>> patients;
  final DateTimeRange? dateRange;
  final bool showPatientFilter;
  final void Function(String status, String event, int? patient, DateTimeRange? range) onApply;
  final VoidCallback onReset;

  const _FiltersSheet({
    required this.scrollController,
    required this.statusFilter,
    required this.eventFilter,
    required this.patientFilter,
    required this.patients,
    required this.dateRange,
    required this.showPatientFilter,
    required this.onApply,
    required this.onReset,
  });

  @override
  State<_FiltersSheet> createState() => _FiltersSheetState();
}

class _FiltersSheetState extends State<_FiltersSheet> {
  late String _status = widget.statusFilter;
  late String _event = widget.eventFilter;
  late int? _patient = widget.patientFilter;
  late DateTimeRange? _range = widget.dateRange;

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 1),
      initialDateRange: _range ?? DateTimeRange(start: now.subtract(const Duration(days: 7)), end: now),
    );
    if (picked != null) setState(() => _range = picked);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListView(
      controller: widget.scrollController,
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        Text(
          'Filter incidents',
          style: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: -0.3),
        ),
        const SizedBox(height: 4),
        Text(
          'Narrow down what you see',
          style: GoogleFonts.dmSans(color: cs.onSurfaceVariant, fontSize: 13),
        ),
        const SizedBox(height: 24),

        _SegmentBlock(
          label: 'Status',
          options: const ['all', 'new', 'acknowledged', 'resolved'],
          labels: const ['All', 'New', 'Ack', 'Resolved'],
          value: _status,
          onChanged: (v) => setState(() => _status = v),
        ),
        const SizedBox(height: 18),

        _SegmentBlock(
          label: 'Event type',
          options: const ['all', 'fall', 'seizure', 'manual'],
          labels: const ['All', 'Fall', 'Seizure', 'Manual'],
          value: _event,
          onChanged: (v) => setState(() => _event = v),
        ),

        if (widget.showPatientFilter) ...[
          const SizedBox(height: 18),
          Text(
            'Patient',
            style: GoogleFonts.outfit(fontWeight: FontWeight.w600, fontSize: 13),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<int?>(
            value: _patient,
            decoration: const InputDecoration(isDense: true),
            items: [
              const DropdownMenuItem<int?>(value: null, child: Text('All patients')),
              ...widget.patients.map((p) => DropdownMenuItem<int?>(
                    value: (p['id'] as num?)?.toInt(),
                    child: Text(p['full_name']?.toString() ?? 'Patient #${p['id']}'),
                  )),
            ],
            onChanged: (v) => setState(() => _patient = v),
          ),
        ],

        const SizedBox(height: 18),
        Text(
          'Date range',
          style: GoogleFonts.outfit(fontWeight: FontWeight.w600, fontSize: 13),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _pickRange,
          icon: const Icon(AppIcons.calendar, size: 16),
          label: Text(
            _range == null
                ? 'Any time'
                : '${_fmt(_range!.start)} → ${_fmt(_range!.end)}',
          ),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
            alignment: Alignment.centerLeft,
          ),
        ),

        const SizedBox(height: 28),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: widget.onReset,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                child: const Text('Reset'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: FilledButton(
                onPressed: () => widget.onApply(_status, _event, _patient, _range),
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.brandTeal,
                  minimumSize: const Size.fromHeight(48),
                ),
                child: const Text('Apply filters'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  String _fmt(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

// ── Segmented option row ──────────────────────────────────────────────────────
class _SegmentBlock extends StatelessWidget {
  final String label;
  final List<String> options;
  final List<String> labels;
  final String value;
  final ValueChanged<String> onChanged;

  const _SegmentBlock({
    required this.label,
    required this.options,
    required this.labels,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: GoogleFonts.outfit(fontWeight: FontWeight.w600, fontSize: 13)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: List.generate(options.length, (i) {
            final isSelected = options[i] == value;
            return GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                onChanged(options[i]);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppTheme.brandTeal.withValues(alpha: 0.14)
                      : cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isSelected ? AppTheme.brandTeal : cs.outlineVariant,
                    width: isSelected ? 1.5 : 1,
                  ),
                ),
                child: Text(
                  labels[i],
                  style: GoogleFonts.outfit(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: isSelected ? AppTheme.brandTeal : cs.onSurface,
                  ),
                ),
              ),
            );
          }),
        ),
      ],
    );
  }
}

// ── Detail bottom sheet ───────────────────────────────────────────────────────
class IncidentDetailSheet extends StatefulWidget {
  final Map<String, dynamic> incident;
  final ScrollController scrollController;
  final VoidCallback onAck;
  final VoidCallback onResolve;
  final Future<void> Function(String notes) onSaveNotes;

  const IncidentDetailSheet({
    super.key,
    required this.incident,
    required this.scrollController,
    required this.onAck,
    required this.onResolve,
    required this.onSaveNotes,
  });

  @override
  State<IncidentDetailSheet> createState() => _IncidentDetailSheetState();
}

class _IncidentDetailSheetState extends State<IncidentDetailSheet> {
  late final TextEditingController _notesCtrl =
      TextEditingController(text: (widget.incident['notes'] as String?) ?? '');
  bool _savingNotes = false;

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  String _formatDate(String? iso) {
    if (iso == null) return '—';
    final dt = DateTime.tryParse(iso)?.toLocal();
    if (dt == null) return iso;
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}'
        ' ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final colors = theme.extension<IncidentSeverityColors>() ?? IncidentSeverityColors.light;
    final inc = widget.incident;
    final eventType = (inc['event_type'] as String?) ?? 'manual';
    final severity = inc['severity'] as String?;
    final status = (inc['status'] as String?) ?? 'new';
    final id = inc['id'] as int;
    final stripeColor = colors.forSeverity(severity);

    return ListView(
      controller: widget.scrollController,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
      children: [
        // Hero header
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [stripeColor, stripeColor.withValues(alpha: 0.78)],
            ),
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: stripeColor.withValues(alpha: 0.30),
                blurRadius: 22,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.22),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
                ),
                child: Icon(AppIcons.forEventType(eventType), color: Colors.white, size: 28),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _eventTitle(eventType),
                      style: GoogleFonts.cormorantGaramond(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        height: 1.05,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Incident #$id',
                      style: GoogleFonts.dmSans(
                        fontSize: 12.5,
                        color: Colors.white.withValues(alpha: 0.85),
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  SeverityPill(severity: severity, dense: true, filled: false),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Status row
        StatusPill.forIncidentStatus(status),

        const SizedBox(height: 20),

        // Key-value grid
        _DetailRow(
          icon: AppIcons.patients,
          label: 'Patient',
          value: inc['patient_name']?.toString() ??
              (inc['patient_id'] != null ? '#${inc['patient_id']}' : '—'),
        ),
        _DetailRow(
          icon: AppIcons.cameras,
          label: 'Camera',
          value: inc['camera_name']?.toString() ??
              (inc['camera_config_id'] != null ? '#${inc['camera_config_id']}' : '—'),
        ),
        _DetailRow(
          icon: Icons.access_time_rounded,
          label: 'Detected',
          value: _formatDate(inc['detected_at'] as String?),
        ),
        if (inc['acknowledged_at'] != null)
          _DetailRow(
            icon: AppIcons.acknowledge,
            label: 'Acknowledged',
            value: _formatDate(inc['acknowledged_at'] as String?),
          ),
        if (inc['resolved_at'] != null)
          _DetailRow(
            icon: AppIcons.resolve,
            label: 'Resolved',
            value: _formatDate(inc['resolved_at'] as String?),
          ),
        if (inc['confidence'] != null)
          _DetailRow(
            icon: Icons.precision_manufacturing_rounded,
            label: 'Confidence',
            value: (inc['confidence'] as num).toStringAsFixed(3),
          ),

        const SizedBox(height: 20),

        Text(
          'Notes',
          style: GoogleFonts.outfit(fontWeight: FontWeight.w600, fontSize: 14),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _notesCtrl,
          maxLines: 4,
          decoration: const InputDecoration(
            hintText: 'Add observations or follow-up actions…',
          ),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerRight,
          child: OutlinedButton.icon(
            onPressed: _savingNotes
                ? null
                : () async {
                    setState(() => _savingNotes = true);
                    try {
                      await widget.onSaveNotes(_notesCtrl.text);
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Notes saved')),
                        );
                      }
                    } finally {
                      if (mounted) setState(() => _savingNotes = false);
                    }
                  },
            icon: const Icon(AppIcons.edit, size: 16),
            label: Text(_savingNotes ? 'Saving…' : 'Save notes'),
          ),
        ),

        const SizedBox(height: 24),

        // Action buttons
        Row(
          children: [
            if (status == 'new')
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: widget.onAck,
                  icon: const Icon(AppIcons.acknowledge, size: 18),
                  label: const Text('Acknowledge'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.brandTeal,
                    side: BorderSide(color: AppTheme.brandTeal.withValues(alpha: 0.5), width: 1.5),
                    minimumSize: const Size.fromHeight(50),
                  ),
                ),
              ),
            if (status == 'new' && status != 'resolved') const SizedBox(width: 10),
            if (status != 'resolved')
              Expanded(
                child: FilledButton.icon(
                  onPressed: widget.onResolve,
                  icon: const Icon(AppIcons.resolve, size: 18),
                  label: const Text('Resolve'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.brandSage,
                    minimumSize: const Size.fromHeight(50),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  String _eventTitle(String eventType) {
    switch (eventType.toLowerCase()) {
      case 'fall': return 'Fall detected';
      case 'seizure': return 'Seizure detected';
      case 'manual': return 'Manual alert';
      default: return 'Alert';
    }
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _DetailRow({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppTheme.brandTeal.withValues(alpha: 0.7)),
          const SizedBox(width: 12),
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: GoogleFonts.dmSans(
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w500,
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.dmSans(
                fontWeight: FontWeight.w600,
                fontSize: 13.5,
                color: cs.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
