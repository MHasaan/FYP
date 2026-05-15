import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/api_service.dart';
import '../../services/auth_controller.dart';
import '../../theme/app_icons.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/eldercare_card.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/section_header.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/status_pill.dart';
import 'camera_form.dart';

class CamerasScreen extends StatefulWidget {
  const CamerasScreen({super.key});

  @override
  State<CamerasScreen> createState() => _CamerasScreenState();
}

class _CamerasScreenState extends State<CamerasScreen> {
  final ApiService _api = ApiService();
  bool _loading = false;
  String? _error;
  List<Map<String, dynamic>> _cameras = [];
  Map<int, String> _patientNames = {};
  // camera_config_id → instance map (most recent active instance, if any)
  Map<int, Map<String, dynamic>> _instancesByCamera = {};
  String _query = '';
  Timer? _statusRefresh;
  // camera_config_id → "starting" / "stopping" while a control command is in flight
  final Set<int> _controlBusy = {};

  @override
  void initState() {
    super.initState();
    _load();
    // Lightweight status refresh — keeps the Status pill accurate without
    // the heavy full reload.
    _statusRefresh = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _refreshInstances(silent: true),
    );
  }

  @override
  void dispose() {
    _statusRefresh?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _api.getCameraConfigs(),
        _api.getPatients(),
        _api.getInstances(),
      ]);
      if (mounted) {
        final cams = (results[0]).cast<Map<String, dynamic>>();
        final patients = (results[1]).cast<Map<String, dynamic>>();
        final instances = (results[2]).cast<Map<String, dynamic>>();
        setState(() {
          _cameras = cams;
          _patientNames = {
            for (final p in patients)
              if (p['id'] != null) (p['id'] as num).toInt(): (p['full_name']?.toString() ?? 'Patient #${p['id']}')
          };
          _instancesByCamera = _indexInstancesByCamera(instances);
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Could not load cameras: $e';
          _loading = false;
        });
      }
    }
  }

  Future<void> _refreshInstances({bool silent = false}) async {
    try {
      final instances = (await _api.getInstances()).cast<Map<String, dynamic>>();
      if (mounted) {
        setState(() {
          _instancesByCamera = _indexInstancesByCamera(instances);
        });
      }
    } catch (_) {
      // Silent failure — periodic refresh shouldn't break the screen.
    }
  }

  /// Pick the most recently-created instance per camera_config_id (an admin
  /// could have multiple historical instances for the same camera).
  Map<int, Map<String, dynamic>> _indexInstancesByCamera(
      List<Map<String, dynamic>> instances) {
    final map = <int, Map<String, dynamic>>{};
    for (final inst in instances) {
      final cid = (inst['camera_config_id'] as num?)?.toInt();
      if (cid == null) continue;
      final existing = map[cid];
      if (existing == null) {
        map[cid] = inst;
        continue;
      }
      // Prefer running > paused > anything else; otherwise newest id wins.
      final newPriority = _statusPriority(inst['status'] as String?);
      final oldPriority = _statusPriority(existing['status'] as String?);
      if (newPriority > oldPriority) {
        map[cid] = inst;
      } else if (newPriority == oldPriority) {
        final newId = (inst['id'] as num).toInt();
        final oldId = (existing['id'] as num).toInt();
        if (newId > oldId) map[cid] = inst;
      }
    }
    return map;
  }

  int _statusPriority(String? status) {
    switch ((status ?? '').toLowerCase()) {
      case 'running': return 4;
      case 'paused': return 3;
      case 'idle': return 2;
      case 'stopped': return 1;
      default: return 0;
    }
  }

  Future<void> _openCreate() async {
    final res = await CameraFormDialog.show(context);
    if (res == true) await _load();
  }

  Future<void> _openEdit(Map<String, dynamic> c) async {
    final res = await CameraFormDialog.show(context, existing: c);
    if (res == true) await _load();
  }

  Future<void> _delete(Map<String, dynamic> c) async {
    final cameraId = c['id'] as int;
    final hasRunning = _instancesByCamera[cameraId]?['status'] == 'running';
    if (hasRunning) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Stop monitoring before deleting this camera.'),
      ));
      return;
    }
    final confirm = await showConfirmDialog(
      context,
      title: 'Delete camera?',
      message: 'This removes the camera configuration. Existing incidents are kept for audit.',
      confirmLabel: 'Delete',
      destructive: true,
      icon: AppIcons.delete,
    );
    if (!confirm) return;
    try {
      await _api.deleteCameraConfig(cameraId);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to delete: $e')));
      }
    }
  }

  /// Create a pipeline instance for this camera + start it. Used for cameras
  /// that didn't have monitoring auto-started at creation time.
  Future<void> _startMonitoring(Map<String, dynamic> camera) async {
    final cameraId = (camera['id'] as num).toInt();
    setState(() => _controlBusy.add(cameraId));
    try {
      // Re-use the camera's stored enabled_models, but filter out unwired ones.
      final stored = (camera['enabled_models'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          const <String>[];
      final wired = stored.where(kWiredModels.contains).toList();
      final enabled = wired.isEmpty ? <String>['pose'] : wired;

      // If an idle/stopped instance already exists for this camera, just start it.
      final existing = _instancesByCamera[cameraId];
      int instanceId;
      if (existing != null) {
        instanceId = (existing['id'] as num).toInt();
      } else {
        final created = await _api.createInstance({
          'name': camera['name']?.toString() ?? 'Camera $cameraId',
          'camera_config_id': cameraId,
          'enabled_models': enabled,
          'model_configs': (camera['model_configs'] as Map?) ?? const {},
        });
        instanceId = (created['id'] as num).toInt();
      }
      await _api.controlInstance(instanceId, 'start');
      await _refreshInstances();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed to start monitoring: $e'),
        ));
      }
    } finally {
      if (mounted) setState(() => _controlBusy.remove(cameraId));
    }
  }

  Future<void> _stopMonitoring(Map<String, dynamic> camera) async {
    final cameraId = (camera['id'] as num).toInt();
    final instance = _instancesByCamera[cameraId];
    if (instance == null) return;
    setState(() => _controlBusy.add(cameraId));
    try {
      await _api.controlInstance((instance['id'] as num).toInt(), 'stop');
      await _refreshInstances();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed to stop: $e'),
        ));
      }
    } finally {
      if (mounted) setState(() => _controlBusy.remove(cameraId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final canManage = auth.isCareTeam;
    final cs = Theme.of(context).colorScheme;

    final filtered = _cameras.where((c) {
      if (_query.isEmpty) return true;
      final q = _query.toLowerCase();
      final n = (c['name']?.toString() ?? '').toLowerCase();
      final loc = (c['location']?.toString() ?? '').toLowerCase();
      final grp = (c['group_name']?.toString() ?? '').toLowerCase();
      return n.contains(q) || loc.contains(q) || grp.contains(q);
    }).toList();

    return Column(
      children: [
        SectionHeader(
          title: 'Cameras',
          subtitle: 'Register cameras and start fall / pose monitoring',
          icon: AppIcons.cameras,
          trailing: canManage
              ? FilledButton.icon(
                  onPressed: _openCreate,
                  icon: const Icon(AppIcons.add, size: 18),
                  label: const Text('Add camera'),
                )
              : null,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 0),
          child: EldercareCard(
            padding: const EdgeInsets.all(12),
            child: TextField(
              onChanged: (v) => setState(() => _query = v),
              decoration: const InputDecoration(
                prefixIcon: Icon(AppIcons.search, size: 18),
                hintText: 'Search by name, location, or group',
                isDense: true,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: _loading
              ? const SkeletonList(count: 6)
              : _error != null
                  ? Center(child: Text(_error!, style: TextStyle(color: cs.error)))
                  : _cameras.isEmpty
                      ? EmptyState(
                          icon: AppIcons.cameras,
                          title: 'No cameras registered',
                          subtitle: 'Add your first camera to begin live monitoring.',
                          actionLabel: canManage ? 'Add camera' : null,
                          onAction: canManage ? _openCreate : null,
                          actionIcon: AppIcons.add,
                        )
                      : filtered.isEmpty
                          ? const EmptyState(
                              icon: AppIcons.search,
                              title: 'No matches',
                              subtitle: 'Try a different search term.',
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                              itemCount: filtered.length,
                              itemBuilder: (_, i) {
                                final c = filtered[i];
                                final pid = (c['patient_id'] as num?)?.toInt();
                                final patient = pid == null ? null : _patientNames[pid];
                                final cameraId = (c['id'] as num).toInt();
                                final instance = _instancesByCamera[cameraId];
                                return _CameraRow(
                                  camera: c,
                                  patientLabel: patient,
                                  instance: instance,
                                  canManage: canManage,
                                  busy: _controlBusy.contains(cameraId),
                                  onEdit: () => _openEdit(c),
                                  onDelete: () => _delete(c),
                                  onStart: () => _startMonitoring(c),
                                  onStop: () => _stopMonitoring(c),
                                );
                              },
                            ),
        ),
      ],
    );
  }
}

class _CameraRow extends StatelessWidget {
  final Map<String, dynamic> camera;
  final String? patientLabel;
  final Map<String, dynamic>? instance;
  final bool canManage;
  final bool busy;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onStart;
  final VoidCallback onStop;

  const _CameraRow({
    required this.camera,
    required this.patientLabel,
    required this.instance,
    required this.canManage,
    required this.busy,
    required this.onEdit,
    required this.onDelete,
    required this.onStart,
    required this.onStop,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final source = camera['source_type']?.toString() ?? '—';
    final url = camera['source_url']?.toString() ?? '';
    final group = camera['group_name']?.toString();
    final location = camera['location']?.toString();

    final status = (instance?['status'] as String?)?.toLowerCase();
    final isRunning = status == 'running';
    final isPaused = status == 'paused';

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: EldercareCard(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isRunning
                    ? cs.primary.withValues(alpha: 0.18)
                    : cs.primaryContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                AppIcons.cameras,
                color: isRunning ? cs.primary : cs.onPrimaryContainer,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          camera['name']?.toString() ?? 'Camera',
                          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (instance != null)
                        StatusPill.forPipelineStatus(instance!['status'] as String?)
                      else
                        const StatusPill(label: 'Not monitored', kind: StatusKind.neutral, dense: true),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 12,
                    runSpacing: 4,
                    children: [
                      if (location != null && location.isNotEmpty)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(AppIcons.location, size: 12, color: cs.onSurfaceVariant),
                            const SizedBox(width: 4),
                            Text(location, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
                          ],
                        ),
                      if (group != null && group.isNotEmpty)
                        Text('Group: $group', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
                      if (patientLabel != null)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(AppIcons.patients, size: 12, color: cs.tertiary),
                            const SizedBox(width: 4),
                            Text(patientLabel!,
                                style: TextStyle(color: cs.tertiary, fontSize: 12, fontWeight: FontWeight.w600)),
                          ],
                        ),
                    ],
                  ),
                  if (url.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      url,
                      style: TextStyle(color: cs.onSurfaceVariant, fontSize: 11, fontFamily: 'monospace'),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            StatusPill(label: source.toUpperCase(), kind: StatusKind.info, dense: true),
            if (canManage) ...[
              const SizedBox(width: 6),
              if (busy)
                const SizedBox(
                  width: 28,
                  height: 28,
                  child: Padding(
                    padding: EdgeInsets.all(4),
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else if (isRunning || isPaused)
                IconButton(
                  icon: const Icon(AppIcons.stop, size: 20),
                  onPressed: onStop,
                  tooltip: 'Stop monitoring',
                  color: cs.error,
                )
              else
                IconButton.filledTonal(
                  icon: const Icon(AppIcons.start, size: 20),
                  onPressed: onStart,
                  tooltip: 'Start monitoring',
                ),
              IconButton(
                icon: const Icon(AppIcons.edit, size: 18),
                onPressed: onEdit,
                tooltip: 'Edit',
              ),
              IconButton(
                icon: const Icon(AppIcons.delete, size: 18),
                onPressed: onDelete,
                tooltip: 'Delete',
                color: cs.error,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
