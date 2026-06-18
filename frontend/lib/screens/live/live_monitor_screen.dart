import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/api_service.dart';
import '../../services/auth_controller.dart';
import '../../services/multi_instance_ws_service.dart';
import '../../theme/app_icons.dart';
import '../../widgets/eldercare_card.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/section_header.dart';
import '../../widgets/status_pill.dart';

// Models actually wired in the ML manager (see WORKER_FACTORIES in
// ml_manager/manager/pipeline_manager.py). Other names are reserved.
const Set<String> _kWiredModels = {
  'pose',
  'fall_detection',
  'seizure_detection',
  'test',
};

const Map<String, String> _kModelLabels = {
  'pose': 'Pose detection',
  'fall_detection': 'Fall detection',
  'seizure_detection': 'Seizure detection',
  'test': 'Test (passthrough)',
};

const Map<String, String> _kModelDescriptions = {
  'pose':
      '18-point body keypoints. Auto-required when fall or seizure detection is on.',
  'fall_detection':
      'Sliding-window fall classifier driven by pose, patches, and motion.',
  'seizure_detection':
      'Sliding-window seizure classifier driven by pose and kinematics.',
  'test':
      'No-op worker — streams frames through with no ML cost. Useful for verifying the pipeline.',
};

const String _kUngroupedKey = '_ungrouped_';

class LiveMonitorScreen extends StatefulWidget {
  const LiveMonitorScreen({super.key});

  @override
  State<LiveMonitorScreen> createState() => _LiveMonitorScreenState();
}

class _LiveMonitorScreenState extends State<LiveMonitorScreen> {
  final ApiService _api = ApiService();
  final MultiInstanceWsService _ws = MultiInstanceWsService();

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _instances = [];
  Map<int, Map<String, dynamic>> _camerasById = {};
  Map<int, String> _patientNames = {};
  final Set<int> _connectedIds = {};

  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _load();
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 6),
      (_) => _refresh(),
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _ws.disconnectAll();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _api.getInstances(),
        _api.getCameraConfigs(),
        _api.getPatients(),
      ]);
      if (!mounted) return;
      _applyData(
        results[0].cast<Map<String, dynamic>>(),
        results[1].cast<Map<String, dynamic>>(),
        results[2].cast<Map<String, dynamic>>(),
        clearLoading: true,
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Could not load cameras: $e';
          _loading = false;
        });
      }
    }
  }

  // Silent background refresh — does not show the loading spinner.
  Future<void> _refresh() async {
    try {
      final results = await Future.wait([
        _api.getInstances(),
        _api.getCameraConfigs(),
        _api.getPatients(),
      ]);
      if (!mounted) return;
      _applyData(
        results[0].cast<Map<String, dynamic>>(),
        results[1].cast<Map<String, dynamic>>(),
        results[2].cast<Map<String, dynamic>>(),
        clearLoading: false,
      );
    } catch (_) {}
  }

  void _applyData(
    List<Map<String, dynamic>> instances,
    List<Map<String, dynamic>> cameras,
    List<Map<String, dynamic>> patients, {
    required bool clearLoading,
  }) {
    // Reconcile WebSocket connections: connect newly seen instances, drop
    // ones that were deleted. Connections persist while the instance is
    // listed regardless of running/stopped status — the channel is idle
    // when no frames are being published, so no waste.
    final newIds = instances
        .map((i) => (i['id'] as num).toInt())
        .toSet();
    final toConnect = newIds.difference(_connectedIds);
    final toDisconnect = _connectedIds.difference(newIds);

    for (final id in toDisconnect) {
      _ws.disconnectInstance(id);
    }
    for (final id in toConnect) {
      _ws.connectInstance(id);
    }

    setState(() {
      _instances = instances;
      _camerasById = {
        for (final c in cameras)
          if (c['id'] != null) (c['id'] as num).toInt(): c
      };
      _patientNames = {
        for (final p in patients)
          if (p['id'] != null)
            (p['id'] as num).toInt():
                (p['full_name']?.toString() ?? 'Patient #${p['id']}')
      };
      _connectedIds
        ..clear()
        ..addAll(newIds);
      if (clearLoading) _loading = false;
    });
  }

  // ── Grouping helpers ────────────────────────────────────────────────────

  bool _isLive(Map<String, dynamic> i) {
    final s = (i['status'] as String?)?.toLowerCase();
    return s == 'running' || s == 'paused';
  }

  Map<String, List<Map<String, dynamic>>> _groupByName(
      List<Map<String, dynamic>> items) {
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final inst in items) {
      final cid = (inst['camera_config_id'] as num?)?.toInt();
      final cam = cid == null ? null : _camerasById[cid];
      final raw = (cam?['group_name'] as String?)?.trim();
      final key = (raw == null || raw.isEmpty) ? _kUngroupedKey : raw;
      groups.putIfAbsent(key, () => []).add(inst);
    }
    // Stable, friendly order: ungrouped last within each section.
    final keys = groups.keys.toList()
      ..sort((a, b) {
        if (a == _kUngroupedKey) return 1;
        if (b == _kUngroupedKey) return -1;
        return a.toLowerCase().compareTo(b.toLowerCase());
      });
    return {for (final k in keys) k: groups[k]!};
  }

  // ── Actions ─────────────────────────────────────────────────────────────

  Future<void> _onTileChanged() async {
    // Lightweight refresh after a control/settings/delete action.
    await _refresh();
  }

  // ── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Text(_error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error)),
      );
    }

    final live = _instances.where(_isLive).toList();
    final stopped =
        _instances.where((i) => !_isLive(i)).toList();

    final liveGroups = _groupByName(live);
    final stoppedGroups = _groupByName(stopped);

    return Column(
      children: [
        SectionHeader(
          title: 'Live Monitor',
          subtitle: _instances.isEmpty
              ? 'No cameras yet'
              : '${live.length} live · ${stopped.length} idle',
          icon: AppIcons.live,
          trailing: IconButton.outlined(
            icon: const Icon(AppIcons.refresh, size: 18),
            onPressed: _load,
            tooltip: 'Refresh cameras',
          ),
        ),
        Expanded(
          child: _instances.isEmpty
              ? const EmptyState(
                  icon: AppIcons.cameras,
                  title: 'No cameras yet',
                  subtitle:
                      'Add a camera in the Cameras screen to start live monitoring.',
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                    children: [
                      if (live.isNotEmpty) ...[
                        _SectionTitle(
                          icon: Icons.fiber_manual_record_rounded,
                          iconColor: Colors.redAccent,
                          label: 'Live now',
                          count: live.length,
                        ),
                        for (final entry in liveGroups.entries)
                          _GroupBlock(
                            label: entry.key == _kUngroupedKey
                                ? null
                                : entry.key,
                            instances: entry.value,
                            buildTile: (inst) => _buildTile(inst,
                                compact: false),
                          ),
                        const SizedBox(height: 8),
                      ],
                      if (stopped.isNotEmpty) ...[
                        _SectionTitle(
                          icon: Icons.pause_circle_outline_rounded,
                          iconColor:
                              Theme.of(context).colorScheme.onSurfaceVariant,
                          label: 'Idle',
                          count: stopped.length,
                        ),
                        for (final entry in stoppedGroups.entries)
                          _GroupBlock(
                            label: entry.key == _kUngroupedKey
                                ? null
                                : entry.key,
                            instances: entry.value,
                            buildTile: (inst) => _buildTile(inst,
                                compact: true),
                          ),
                      ],
                    ],
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildTile(Map<String, dynamic> instance, {required bool compact}) {
    final cid = (instance['camera_config_id'] as num?)?.toInt();
    final cam = cid == null ? null : _camerasById[cid];
    final pid = cam == null ? null : (cam['patient_id'] as num?)?.toInt();
    final patientName = pid == null ? null : _patientNames[pid];

    return _CameraTile(
      key: ValueKey('inst-${instance['id']}'),
      instance: instance,
      camera: cam,
      patientName: patientName,
      ws: _ws,
      api: _api,
      compact: compact,
      onChanged: _onTileChanged,
      canControl: context.read<AuthController>().isCareTeam,
    );
  }
}

// ── Section title row ────────────────────────────────────────────────────

class _SectionTitle extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final int count;
  const _SectionTitle({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.count,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
      child: Row(
        children: [
          Icon(icon, size: 14, color: iconColor),
          const SizedBox(width: 8),
          Text(
            label,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              '$count',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Group block (label + responsive grid) ───────────────────────────────

class _GroupBlock extends StatelessWidget {
  final String? label;
  final List<Map<String, dynamic>> instances;
  final Widget Function(Map<String, dynamic>) buildTile;

  const _GroupBlock({
    required this.label,
    required this.instances,
    required this.buildTile,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (label != null) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
              child: Row(
                children: [
                  Icon(Icons.folder_outlined,
                      size: 14, color: theme.colorScheme.primary),
                  const SizedBox(width: 6),
                  Text(
                    label!,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.primary,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),
            ),
          ],
          LayoutBuilder(
            builder: (ctx, c) {
              // Tile sizing — wider tiles for live (compact=false), tighter
              // for idle.
              final maxWidth = c.maxWidth;
              const minTile = 320.0;
              final cols = (maxWidth / minTile).floor().clamp(1, 4);
              final tileWidth = (maxWidth - (cols - 1) * 12) / cols;

              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final inst in instances)
                    SizedBox(
                      width: tileWidth,
                      child: buildTile(inst),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

// ── Camera tile (live preview + controls) ───────────────────────────────

class _CameraTile extends StatefulWidget {
  final Map<String, dynamic> instance;
  final Map<String, dynamic>? camera;
  final String? patientName;
  final MultiInstanceWsService ws;
  final ApiService api;
  final bool compact;
  final bool canControl;
  final Future<void> Function() onChanged;

  const _CameraTile({
    super.key,
    required this.instance,
    required this.camera,
    required this.patientName,
    required this.ws,
    required this.api,
    required this.compact,
    required this.canControl,
    required this.onChanged,
  });

  @override
  State<_CameraTile> createState() => _CameraTileState();
}

class _CameraTileState extends State<_CameraTile> {
  Uint8List? _frame;
  Map<String, dynamic>? _results;
  double _latency = 0;
  bool _busy = false;
  StreamSubscription<Map<String, dynamic>>? _feedSub;
  StreamSubscription<Map<String, dynamic>>? _resultsSub;

  int get _id => (widget.instance['id'] as num).toInt();
  String get _status =>
      (widget.instance['status'] as String?)?.toLowerCase() ?? 'idle';
  bool get _isRunning => _status == 'running';
  bool get _isPaused => _status == 'paused';

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  @override
  void didUpdateWidget(covariant _CameraTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldId = (oldWidget.instance['id'] as num).toInt();
    if (oldId != _id) {
      _unsubscribe();
      _subscribe();
      _frame = null;
      _results = null;
    }
  }

  @override
  void dispose() {
    _unsubscribe();
    super.dispose();
  }

  void _subscribe() {
    _feedSub = widget.ws.getFeedStream(_id).listen((data) {
      if (!mounted) return;
      final img = data['image'];
      if (img is String) {
        try {
          final decoded = base64Decode(img);
          setState(() {
            _frame = decoded;
          });
        } catch (_) {}
      }
    });
    _resultsSub = widget.ws.getResultsStream(_id).listen((data) {
      if (!mounted) return;
      setState(() {
        _results = data;
        final t = data['total_processing_time_ms'];
        if (t is num) _latency = t.toDouble();
      });
    });
  }

  void _unsubscribe() {
    _feedSub?.cancel();
    _resultsSub?.cancel();
    _feedSub = null;
    _resultsSub = null;
  }

  Future<void> _control(String action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.api.controlInstance(_id, action);
      await widget.onChanged();
    } catch (e) {
      _toast('Failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openSettings() async {
    final result = await showModalBottomSheet<_SettingsResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _CameraSettingsSheet(
        instance: widget.instance,
        camera: widget.camera,
      ),
    );
    if (result == null) return;
    if (_busy) return;

    setState(() => _busy = true);
    try {
      if (result.modelsChanged) {
        await widget.api.updateInstanceModels(_id, result.enabledModels);
      }
      if (result.modelConfigs.isNotEmpty) {
        await widget.api.updateInstanceConfig(_id, result.modelConfigs);
      }
      _toast(result.modelsChanged
          ? 'Models updated — pipeline restarted'
          : 'Settings applied');
      await widget.onChanged();
    } catch (e) {
      _toast('Failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete this monitor?'),
        content: Text(
          'This stops monitoring "${widget.instance['name'] ?? 'this camera'}" '
          'and removes the pipeline instance. The camera configuration is kept.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton.tonal(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.errorContainer,
              foregroundColor: Theme.of(context).colorScheme.onErrorContainer,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || _busy) return;

    setState(() => _busy = true);
    try {
      await widget.api.deleteInstance(_id);
      await widget.onChanged();
    } catch (e) {
      _toast('Failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final cameraName = (widget.camera?['name']?.toString())
        ?? (widget.instance['name']?.toString())
        ?? 'Camera';
    final groupName = widget.camera?['group_name']?.toString();
    final enabledModels = (widget.instance['enabled_models'] as List?)
            ?.map((e) => e.toString())
            .where(_kWiredModels.contains)
            .toList() ??
        const <String>[];

    final lastError = widget.instance['last_error']?.toString();
    final hasError = lastError != null && lastError.isNotEmpty;

    return EldercareCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Live preview / placeholder ──────────────────────────────
          AspectRatio(
            aspectRatio: 16 / 9,
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(16)),
              child: _PreviewSurface(
                frame: _isRunning ? _frame : null,
                status: _status,
                latencyMs: _latency,
                hasError: hasError,
                results: _results,
              ),
            ),
          ),

          // ── Body ─────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        cameraName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    StatusPill.forPipelineStatus(_status),
                  ],
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (groupName != null && groupName.isNotEmpty)
                      _Chip(
                        icon: Icons.folder_outlined,
                        text: groupName,
                        color: cs.primary,
                      ),
                    if (widget.patientName != null)
                      _Chip(
                        icon: AppIcons.patients,
                        text: widget.patientName!,
                        color: cs.tertiary,
                      ),
                    for (final m in enabledModels)
                      _Chip(
                        icon: _modelIcon(m),
                        text: _kModelLabels[m] ?? m,
                        color: cs.onSurfaceVariant,
                      ),
                  ],
                ),
                if (hasError) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: cs.errorContainer.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.error_outline,
                            size: 14, color: cs.error),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            lastError,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 11, color: cs.onErrorContainer),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                _Controls(
                  isRunning: _isRunning,
                  isPaused: _isPaused,
                  busy: _busy,
                  canControl: widget.canControl,
                  onStart: () => _control('start'),
                  onStop: () => _control('stop'),
                  onPause: () => _control('pause'),
                  onResume: () => _control('resume'),
                  onSettings: _openSettings,
                  onDelete: _delete,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Preview surface ─────────────────────────────────────────────────────

class _PreviewSurface extends StatelessWidget {
  final Uint8List? frame;
  final String status;
  final double latencyMs;
  final bool hasError;
  final Map<String, dynamic>? results;

  const _PreviewSurface({
    required this.frame,
    required this.status,
    required this.latencyMs,
    required this.hasError,
    this.results,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                cs.inverseSurface,
                Color.alphaBlend(
                    cs.primary.withValues(alpha: 0.10), cs.inverseSurface),
              ],
            ),
          ),
        ),
        if (frame != null)
          Image.memory(frame!, fit: BoxFit.cover, gaplessPlayback: true)
        else
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: 0.18),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    hasError
                        ? Icons.error_outline
                        : (status == 'running'
                            ? Icons.hourglass_top_rounded
                            : Icons.videocam_off_rounded),
                    size: 26,
                    color: hasError
                        ? cs.error
                        : cs.primary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  hasError
                      ? 'Error'
                      : (status == 'running'
                          ? 'Waiting for frames…'
                          : (status == 'paused' ? 'Paused' : 'Stopped')),
                  style: TextStyle(
                    color: cs.onInverseSurface.withValues(alpha: 0.85),
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        if (frame != null && latencyMs > 0)
          Positioned(
            top: 8,
            right: 8,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '${latencyMs.toStringAsFixed(0)} ms',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 10,
                ),
              ),
            ),
          ),
        if (status == 'running')
          Positioned(
            top: 8,
            left: 8,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.redAccent.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(999),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.fiber_manual_record_rounded,
                      size: 8, color: Colors.white),
                  SizedBox(width: 4),
                  Text(
                    'LIVE',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 9,
                      letterSpacing: 0.8,
                    ),
                  ),
                ],
              ),
            ),
          ),
        // ── Detection result pills (fall / seizure) ─────────────────
        if (frame != null) _DetectionOverlay(results: results),
      ],
    );
  }
}

// ── Detection result overlay ─────────────────────────────────────────────

class _DetectionOverlay extends StatelessWidget {
  final Map<String, dynamic>? results;

  const _DetectionOverlay({this.results});

  @override
  Widget build(BuildContext context) {
    final r = results?['results'] as Map?;
    if (r == null) return const SizedBox.shrink();

    final pills = <Widget>[];

    final fd = r['fall_detection'] as Map?;
    if (fd != null) {
      final prob = (fd['probability'] as num?)?.toDouble() ?? 0.0;
      final isAlert = fd['is_fall'] == true;
      pills.add(_DetectionPill(label: 'FALL', probability: prob, isAlert: isAlert));
    }

    final sd = r['seizure_detection'] as Map?;
    if (sd != null) {
      final prob = (sd['probability'] as num?)?.toDouble() ?? 0.0;
      final isAlert = sd['is_seizure'] == true;
      pills.add(_DetectionPill(label: 'SEIZURE', probability: prob, isAlert: isAlert));
    }

    if (pills.isEmpty) return const SizedBox.shrink();

    return Positioned(
      bottom: 8,
      left: 8,
      child: Wrap(spacing: 4, children: pills),
    );
  }
}

class _DetectionPill extends StatelessWidget {
  final String label;
  final double probability;
  final bool isAlert;

  const _DetectionPill({
    required this.label,
    required this.probability,
    required this.isAlert,
  });

  @override
  Widget build(BuildContext context) {
    final pct = (probability * 100).toStringAsFixed(0);
    final Color bg = isAlert
        ? Colors.red.withValues(alpha: 0.85)
        : probability >= 0.5
            ? Colors.orange.withValues(alpha: 0.85)
            : Colors.black.withValues(alpha: 0.55);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$label $pct%',
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: 9,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

// ── Per-tile control bar ────────────────────────────────────────────────

class _Controls extends StatelessWidget {
  final bool isRunning;
  final bool isPaused;
  final bool busy;
  final bool canControl;
  final VoidCallback onStart;
  final VoidCallback onStop;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onSettings;
  final VoidCallback onDelete;

  const _Controls({
    required this.isRunning,
    required this.isPaused,
    required this.busy,
    required this.canControl,
    required this.onStart,
    required this.onStop,
    required this.onPause,
    required this.onResume,
    required this.onSettings,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final children = <Widget>[];

    if (busy) {
      children.add(const SizedBox(
        width: 32,
        height: 32,
        child: Padding(
          padding: EdgeInsets.all(6),
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ));
    } else if (canControl) {
      if (!isRunning && !isPaused) {
        children.add(FilledButton.tonalIcon(
          onPressed: onStart,
          icon: const Icon(AppIcons.start, size: 16),
          label: const Text('Start'),
        ));
      }
      if (isRunning) {
        children.add(OutlinedButton.icon(
          onPressed: onPause,
          icon: const Icon(AppIcons.pause, size: 16),
          label: const Text('Pause'),
        ));
      }
      if (isPaused) {
        children.add(OutlinedButton.icon(
          onPressed: onResume,
          icon: const Icon(AppIcons.resume, size: 16),
          label: const Text('Resume'),
        ));
      }
      if (isRunning || isPaused) {
        children.add(IconButton(
          onPressed: onStop,
          icon: const Icon(AppIcons.stop),
          tooltip: 'Stop',
          color: cs.error,
          visualDensity: VisualDensity.compact,
        ));
      }
    }

    children.add(const Spacer());

    if (canControl) {
      children.add(IconButton(
        onPressed: busy ? null : onSettings,
        icon: const Icon(Icons.tune_rounded),
        tooltip: 'Camera settings',
        visualDensity: VisualDensity.compact,
      ));
      children.add(IconButton(
        onPressed: busy ? null : onDelete,
        icon: const Icon(AppIcons.delete),
        tooltip: 'Delete monitor',
        color: cs.error,
        visualDensity: VisualDensity.compact,
      ));
    }

    return Row(children: children);
  }
}

// ── Generic chip ────────────────────────────────────────────────────────

class _Chip extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;
  const _Chip(
      {required this.icon, required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

IconData _modelIcon(String name) {
  switch (name) {
    case 'pose':
      return Icons.accessibility_new_rounded;
    case 'fall_detection':
      return AppIcons.fall;
    case 'seizure_detection':
      return AppIcons.seizure;
    case 'test':
      return Icons.bug_report_outlined;
  }
  return Icons.smart_toy_outlined;
}

// ── Settings sheet ──────────────────────────────────────────────────────

class _SettingsResult {
  final List<String> enabledModels;
  final Map<String, dynamic> modelConfigs;
  final bool modelsChanged;
  _SettingsResult({
    required this.enabledModels,
    required this.modelConfigs,
    required this.modelsChanged,
  });
}

class _CameraSettingsSheet extends StatefulWidget {
  final Map<String, dynamic> instance;
  final Map<String, dynamic>? camera;

  const _CameraSettingsSheet({required this.instance, required this.camera});

  @override
  State<_CameraSettingsSheet> createState() => _CameraSettingsSheetState();
}

class _CameraSettingsSheetState extends State<_CameraSettingsSheet> {
  late Set<String> _models;
  late double _fallThreshold;
  late double _alertThreshold;
  late double _seizureThreshold;
  late double _seizureAlertThreshold;
  late double _poseConfidence;
  late Set<String> _initialModels;

  @override
  void initState() {
    super.initState();
    final em = (widget.instance['enabled_models'] as List?)
            ?.map((e) => e.toString())
            .where(_kWiredModels.contains)
            .toSet() ??
        <String>{};
    _models = Set<String>.from(em);
    _initialModels = Set<String>.from(em);

    final mc =
        (widget.instance['model_configs'] as Map?)?.cast<String, dynamic>() ??
            {};
    final fall = (mc['fall_detection'] as Map?)?.cast<String, dynamic>() ?? {};
    final seizure = (mc['seizure_detection'] as Map?)?.cast<String, dynamic>() ?? {};
    final pose = (mc['pose'] as Map?)?.cast<String, dynamic>() ?? {};

    _fallThreshold = ((fall['threshold'] as num?) ?? 0.5).toDouble();
    _alertThreshold = ((fall['alert_threshold'] as num?) ?? 0.75).toDouble();
    _seizureThreshold = ((seizure['threshold'] as num?) ?? 0.5).toDouble();
    _seizureAlertThreshold = ((seizure['alert_threshold'] as num?) ?? 0.75).toDouble();
    _poseConfidence =
        ((pose['confidence_threshold'] as num?) ?? 0.25).toDouble();
  }

  void _toggleModel(String name, bool on) {
    setState(() {
      if (on) {
        _models.add(name);
        // Both detection models require pose. Patches/global/kinematics get
        // auto-expanded server-side, so no need to surface them here.
        if (name == 'fall_detection' || name == 'seizure_detection') {
          _models.add('pose');
        }
      } else {
        _models.remove(name);
        // If pose is removed, neither detection model can run.
        if (name == 'pose') {
          _models.remove('fall_detection');
          _models.remove('seizure_detection');
        }
      }
    });
  }

  void _save() {
    final modelsChanged = !setEquals(_models, _initialModels);
    final configs = <String, dynamic>{};
    if (_models.contains('pose')) {
      configs['pose'] = {'confidence_threshold': _poseConfidence};
    }
    if (_models.contains('fall_detection')) {
      configs['fall_detection'] = {
        'threshold': _fallThreshold,
        'alert_threshold': _alertThreshold,
      };
    }
    if (_models.contains('seizure_detection')) {
      configs['seizure_detection'] = {
        'threshold': _seizureThreshold,
        'alert_threshold': _seizureAlertThreshold,
      };
    }
    Navigator.pop(
      context,
      _SettingsResult(
        enabledModels: _models.toList(),
        modelConfigs: configs,
        modelsChanged: modelsChanged,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final cameraName = widget.camera?['name']?.toString() ??
        widget.instance['name']?.toString() ??
        'Camera';

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 24,
          right: 24,
          top: 16,
          bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: cs.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Icon(Icons.tune_rounded, color: cs.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Camera settings',
                          style: theme.textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        Text(
                          cameraName,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(AppIcons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const Divider(height: 24),

              // ── Models ─────────────────────────────────────────────
              Text('Enabled models', style: _sectionStyle(theme)),
              const SizedBox(height: 8),
              for (final name in _kWiredModels)
                _ModelRow(
                  name: name,
                  enabled: _models.contains(name),
                  onChanged: (v) => _toggleModel(name, v),
                ),

              const SizedBox(height: 16),

              // ── Pose tuning ────────────────────────────────────────
              if (_models.contains('pose')) ...[
                Text('Pose detection', style: _sectionStyle(theme)),
                const SizedBox(height: 4),
                _SliderRow(
                  label: 'Keypoint confidence threshold',
                  value: _poseConfidence,
                  min: 0.05,
                  max: 0.9,
                  divisions: 17,
                  onChanged: (v) => setState(() => _poseConfidence = v),
                ),
                const SizedBox(height: 12),
              ],

              // ── Fall detection tuning ──────────────────────────────
              if (_models.contains('fall_detection')) ...[
                Text('Fall detection', style: _sectionStyle(theme)),
                const SizedBox(height: 4),
                _SliderRow(
                  label: 'Fall threshold',
                  value: _fallThreshold,
                  min: 0.10,
                  max: 0.95,
                  divisions: 17,
                  onChanged: (v) => setState(() => _fallThreshold = v),
                ),
                const SizedBox(height: 6),
                _SliderRow(
                  label: 'High-confidence alert',
                  value: _alertThreshold,
                  min: 0.10,
                  max: 0.99,
                  divisions: 17,
                  onChanged: (v) => setState(() => _alertThreshold = v),
                ),
                const SizedBox(height: 12),
              ],

              // ── Seizure detection tuning ───────────────────────────
              if (_models.contains('seizure_detection')) ...[
                Text('Seizure detection', style: _sectionStyle(theme)),
                const SizedBox(height: 4),
                _SliderRow(
                  label: 'Seizure threshold',
                  value: _seizureThreshold,
                  min: 0.10,
                  max: 0.95,
                  divisions: 17,
                  onChanged: (v) => setState(() => _seizureThreshold = v),
                ),
                const SizedBox(height: 6),
                _SliderRow(
                  label: 'High-confidence alert',
                  value: _seizureAlertThreshold,
                  min: 0.10,
                  max: 0.99,
                  divisions: 17,
                  onChanged: (v) => setState(() => _seizureAlertThreshold = v),
                ),
                const SizedBox(height: 12),
              ],

              const SizedBox(height: 8),
              Row(
                children: [
                  if (!setEquals(_models, _initialModels))
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: cs.tertiaryContainer.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.info_outline,
                                size: 14, color: cs.onTertiaryContainer),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'Pipeline will restart to apply model changes.',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: cs.onTertiaryContainer,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _save,
                    icon: const Icon(AppIcons.check, size: 16),
                    label: const Text('Apply'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  TextStyle? _sectionStyle(ThemeData theme) =>
      theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800);
}

class _ModelRow extends StatelessWidget {
  final String name;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  const _ModelRow({
    required this.name,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final label = _kModelLabels[name] ?? name;
    final desc = _kModelDescriptions[name] ?? '';
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Container(
        decoration: BoxDecoration(
          color: enabled
              ? cs.primaryContainer.withValues(alpha: 0.4)
              : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(10),
        ),
        child: SwitchListTile(
          value: enabled,
          onChanged: onChanged,
          dense: true,
          title: Row(
            children: [
              Icon(_modelIcon(name), size: 16, color: cs.primary),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          subtitle: Text(
            desc,
            style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
          ),
        ),
      ),
    );
  }
}

class _SliderRow extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double> onChanged;

  const _SliderRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(fontSize: 12),
              ),
            ),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: cs.primaryContainer,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                value.toStringAsFixed(2),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: cs.onPrimaryContainer,
                ),
              ),
            ),
          ],
        ),
        Slider(
          value: value,
          min: min,
          max: max,
          divisions: divisions,
          onChanged: onChanged,
        ),
      ],
    );
  }
}
