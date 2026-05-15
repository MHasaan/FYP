import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/api_service.dart';
import '../../services/auth_controller.dart';
import '../../services/incident_stream_service.dart';
import '../../theme/app_icons.dart';
import '../../widgets/eldercare_card.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/incident_tile.dart';
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

  Map<String, dynamic>? _selected;
  bool _detailLoading = false;

  StreamSubscription? _eventSub;

  @override
  void initState() {
    super.initState();
    _initialLoad();
    final stream = context.read<IncidentStreamService>();
    _eventSub = stream.newIncidentStream.listen((_) {
      // Debounce-style: just refresh the list whenever we hear about a new one.
      _load();
    });
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
        if (mounted) {
          setState(() => _patients = patients.cast<Map<String, dynamic>>());
        }
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
    try {
      await _api.acknowledgeIncident(id);
      if (mounted) context.read<IncidentStreamService>().markStatusLocally(id, 'acknowledged');
      await _load();
    } catch (e) {
      _showError('Failed to acknowledge: $e');
    }
  }

  Future<void> _resolve(int id) async {
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

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 1),
      initialDateRange: _dateRange ?? DateTimeRange(start: now.subtract(const Duration(days: 7)), end: now),
    );
    if (picked != null) {
      setState(() => _dateRange = picked);
      _load();
    }
  }

  void _resetFilters() {
    setState(() {
      _statusFilter = 'all';
      _eventFilter = 'all';
      _patientFilter = null;
      _dateRange = null;
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final auth = context.watch<AuthController>();
    final newCount = _incidents.where((i) => i['status'] == 'new').length;
    final ackCount = _incidents.where((i) => i['status'] == 'acknowledged').length;
    final resolvedCount = _incidents.where((i) => i['status'] == 'resolved').length;

    final isWide = MediaQuery.of(context).size.width >= 1100;

    return Column(
      children: [
        SectionHeader(
          title: 'Incidents',
          subtitle: 'Detected falls, seizures, and manual reports',
          icon: AppIcons.incidents,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: StatusPill(label: '$newCount new', kind: StatusKind.danger),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: StatusPill(label: '$ackCount ack', kind: StatusKind.warning),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: StatusPill(label: '$resolvedCount resolved', kind: StatusKind.success),
              ),
              IconButton.outlined(
                tooltip: 'Refresh',
                icon: const Icon(AppIcons.refresh, size: 18),
                onPressed: _load,
              ),
            ],
          ),
        ),
        _FilterBar(
          statusFilter: _statusFilter,
          eventFilter: _eventFilter,
          patientFilter: _patientFilter,
          patients: _patients,
          dateRange: _dateRange,
          showPatientFilter: auth.isCareTeam,
          onStatusChanged: (v) {
            setState(() => _statusFilter = v);
            _load();
          },
          onEventChanged: (v) {
            setState(() => _eventFilter = v);
            _load();
          },
          onPatientChanged: (v) {
            setState(() => _patientFilter = v);
            _load();
          },
          onPickDateRange: _pickDateRange,
          onReset: _resetFilters,
        ),
        const SizedBox(height: 8),
        Expanded(
          child: _loading
              ? const SkeletonList(count: 6)
              : _error != null
                  ? Center(
                      child: Text(_error!, style: TextStyle(color: cs.error)),
                    )
                  : _incidents.isEmpty
                      ? const EmptyState(
                          icon: AppIcons.incidents,
                          title: 'All quiet',
                          subtitle: 'No incidents match your filters. Real-time alerts will appear here as they happen.',
                        )
                      : isWide
                          ? Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Expanded(
                                  flex: 3,
                                  child: _buildList(),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  flex: 2,
                                  child: Padding(
                                    padding: const EdgeInsets.fromLTRB(0, 0, 24, 24),
                                    child: _IncidentDetailPanel(
                                      incident: _selected,
                                      loading: _detailLoading,
                                      onAck: _acknowledge,
                                      onResolve: _resolve,
                                      onSaveNotes: (id, notes) async {
                                        try {
                                          await _api.updateIncident(id, {'notes': notes});
                                          await _load();
                                        } catch (e) {
                                          _showError('Failed to save notes: $e');
                                        }
                                      },
                                    ),
                                  ),
                                ),
                              ],
                            )
                          : _buildList(),
        ),
        _FooterCount(showing: _incidents.length, total: _total),
      ],
    );
  }

  Widget _buildList() {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      itemCount: _incidents.length,
      itemBuilder: (_, i) {
        final inc = _incidents[i];
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: IncidentTile(
            incident: inc,
            selected: _selected?['id'] == inc['id'],
            onTap: () => setState(() => _selected = inc),
            onAcknowledge: () => _acknowledge(inc['id'] as int),
            onResolve: () => _resolve(inc['id'] as int),
          ),
        );
      },
    );
  }
}

// ── Filter bar ──────────────────────────────────────────────────────────────
class _FilterBar extends StatelessWidget {
  final String statusFilter;
  final String eventFilter;
  final int? patientFilter;
  final List<Map<String, dynamic>> patients;
  final DateTimeRange? dateRange;
  final bool showPatientFilter;
  final ValueChanged<String> onStatusChanged;
  final ValueChanged<String> onEventChanged;
  final ValueChanged<int?> onPatientChanged;
  final VoidCallback onPickDateRange;
  final VoidCallback onReset;

  const _FilterBar({
    required this.statusFilter,
    required this.eventFilter,
    required this.patientFilter,
    required this.patients,
    required this.dateRange,
    required this.showPatientFilter,
    required this.onStatusChanged,
    required this.onEventChanged,
    required this.onPatientChanged,
    required this.onPickDateRange,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 0),
      child: EldercareCard(
        padding: const EdgeInsets.all(12),
        child: Wrap(
          spacing: 10,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 160,
              child: DropdownButtonFormField<String>(
                value: statusFilter,
                decoration: const InputDecoration(labelText: 'Status', isDense: true),
                items: const [
                  DropdownMenuItem(value: 'all', child: Text('All statuses')),
                  DropdownMenuItem(value: 'new', child: Text('New')),
                  DropdownMenuItem(value: 'acknowledged', child: Text('Acknowledged')),
                  DropdownMenuItem(value: 'resolved', child: Text('Resolved')),
                ],
                onChanged: (v) => onStatusChanged(v ?? 'all'),
              ),
            ),
            SizedBox(
              width: 160,
              child: DropdownButtonFormField<String>(
                value: eventFilter,
                decoration: const InputDecoration(labelText: 'Event type', isDense: true),
                items: const [
                  DropdownMenuItem(value: 'all', child: Text('All events')),
                  DropdownMenuItem(value: 'fall', child: Text('Fall')),
                  DropdownMenuItem(value: 'seizure', child: Text('Seizure')),
                  DropdownMenuItem(value: 'manual', child: Text('Manual')),
                ],
                onChanged: (v) => onEventChanged(v ?? 'all'),
              ),
            ),
            if (showPatientFilter)
              SizedBox(
                width: 220,
                child: DropdownButtonFormField<int?>(
                  value: patientFilter,
                  decoration: const InputDecoration(labelText: 'Patient', isDense: true),
                  items: [
                    const DropdownMenuItem<int?>(value: null, child: Text('All patients')),
                    ...patients.map((p) => DropdownMenuItem<int?>(
                          value: (p['id'] as num?)?.toInt(),
                          child: Text(p['full_name']?.toString() ?? 'Patient #${p['id']}'),
                        )),
                  ],
                  onChanged: onPatientChanged,
                ),
              ),
            SizedBox(
              child: OutlinedButton.icon(
                onPressed: onPickDateRange,
                icon: const Icon(AppIcons.calendar, size: 16),
                label: Text(
                  dateRange == null
                      ? 'Date range'
                      : '${_fmt(dateRange!.start)} → ${_fmt(dateRange!.end)}',
                ),
              ),
            ),
            TextButton.icon(
              onPressed: onReset,
              icon: const Icon(AppIcons.refresh, size: 16),
              label: const Text('Reset'),
              style: TextButton.styleFrom(foregroundColor: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  static String _fmt(DateTime d) => '${d.year}-${_pad(d.month)}-${_pad(d.day)}';
  static String _pad(int v) => v.toString().padLeft(2, '0');
}

// ── Detail panel ────────────────────────────────────────────────────────────
class _IncidentDetailPanel extends StatefulWidget {
  final Map<String, dynamic>? incident;
  final bool loading;
  final void Function(int id) onAck;
  final void Function(int id) onResolve;
  final Future<void> Function(int id, String notes) onSaveNotes;

  const _IncidentDetailPanel({
    required this.incident,
    required this.loading,
    required this.onAck,
    required this.onResolve,
    required this.onSaveNotes,
  });

  @override
  State<_IncidentDetailPanel> createState() => _IncidentDetailPanelState();
}

class _IncidentDetailPanelState extends State<_IncidentDetailPanel> {
  final TextEditingController _notesCtrl = TextEditingController();
  int? _lastIncidentId;
  bool _savingNotes = false;

  @override
  void didUpdateWidget(covariant _IncidentDetailPanel old) {
    super.didUpdateWidget(old);
    final id = widget.incident?['id'] as int?;
    if (id != _lastIncidentId) {
      _lastIncidentId = id;
      _notesCtrl.text = (widget.incident?['notes'] as String?) ?? '';
    }
  }

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
    final inc = widget.incident;
    if (inc == null) {
      return EldercareCard(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(40),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(AppIcons.info, size: 36, color: cs.onSurfaceVariant),
                const SizedBox(height: 12),
                Text('Select an incident to see details',
                    style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
              ],
            ),
          ),
        ),
      );
    }

    final status = (inc['status'] as String?) ?? 'new';
    final id = inc['id'] as int;
    final eventType = (inc['event_type'] as String?) ?? 'manual';
    final severity = inc['severity'] as String?;

    return EldercareCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(AppIcons.forEventType(eventType), color: cs.primary, size: 20),
              const SizedBox(width: 8),
              Text(
                'Incident #$id',
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              SeverityPill(severity: severity, dense: true),
              const SizedBox(width: 6),
              StatusPill.forIncidentStatus(status),
            ],
          ),
          const SizedBox(height: 14),
          _kv('Patient', inc['patient_name']?.toString() ?? (inc['patient_id'] != null ? '#${inc['patient_id']}' : '—')),
          _kv('Camera', inc['camera_name']?.toString() ?? (inc['camera_config_id'] != null ? '#${inc['camera_config_id']}' : '—')),
          _kv('Detected at', _formatDate(inc['detected_at'] as String?)),
          _kv('Acknowledged at', _formatDate(inc['acknowledged_at'] as String?)),
          _kv('Resolved at', _formatDate(inc['resolved_at'] as String?)),
          if (inc['confidence'] != null)
            _kv('Confidence', (inc['confidence'] as num).toStringAsFixed(3)),
          if (inc['threshold'] != null)
            _kv('Threshold', (inc['threshold'] as num).toStringAsFixed(3)),
          const SizedBox(height: 14),
          Text('Notes', style: theme.textTheme.labelLarge),
          const SizedBox(height: 6),
          TextField(
            controller: _notesCtrl,
            maxLines: 4,
            decoration: const InputDecoration(
              hintText: 'Add observations or follow-up actions',
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (status == 'new')
                FilledButton.icon(
                  onPressed: () => widget.onAck(id),
                  icon: const Icon(AppIcons.acknowledge, size: 16),
                  label: const Text('Acknowledge'),
                ),
              if (status != 'resolved')
                FilledButton.tonalIcon(
                  onPressed: () => widget.onResolve(id),
                  icon: const Icon(AppIcons.resolve, size: 16),
                  label: const Text('Resolve'),
                ),
              OutlinedButton.icon(
                onPressed: _savingNotes
                    ? null
                    : () async {
                        setState(() => _savingNotes = true);
                        try {
                          await widget.onSaveNotes(id, _notesCtrl.text);
                        } finally {
                          if (mounted) setState(() => _savingNotes = false);
                        }
                      },
                icon: const Icon(AppIcons.edit, size: 16),
                label: Text(_savingNotes ? 'Saving…' : 'Save notes'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 130,
            child: Text(k, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5)),
          ),
          Expanded(child: Text(v, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }
}

// ── Footer ──────────────────────────────────────────────────────────────────
class _FooterCount extends StatelessWidget {
  final int showing;
  final int total;

  const _FooterCount({required this.showing, required this.total});

  @override
  Widget build(BuildContext context) {
    if (total == 0) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 16),
      child: Text(
        'Showing $showing of $total',
        style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
      ),
    );
  }
}
