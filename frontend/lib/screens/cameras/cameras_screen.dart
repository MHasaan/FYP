import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../services/api_service.dart';
import '../../services/auth_controller.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_theme.dart';
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
  Map<int, Map<String, dynamic>> _instancesByCamera = {};
  String _query = '';
  Timer? _statusRefresh;
  final Set<int> _controlBusy = {};

  @override
  void initState() {
    super.initState();
    _load();
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
    } catch (_) {}
  }

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
    HapticFeedback.lightImpact();
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

  Future<void> _startMonitoring(Map<String, dynamic> camera) async {
    final cameraId = (camera['id'] as num).toInt();
    HapticFeedback.mediumImpact();
    setState(() => _controlBusy.add(cameraId));
    try {
      final stored = (camera['enabled_models'] as List?)?.map((e) => e.toString()).toList() ?? const <String>[];
      final wired = stored.where(kWiredModels.contains).toList();
      final enabled = wired.isEmpty ? <String>['pose'] : wired;

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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to start: $e')));
      }
    } finally {
      if (mounted) setState(() => _controlBusy.remove(cameraId));
    }
  }

  Future<void> _stopMonitoring(Map<String, dynamic> camera) async {
    final cameraId = (camera['id'] as num).toInt();
    final instance = _instancesByCamera[cameraId];
    if (instance == null) return;
    HapticFeedback.mediumImpact();
    setState(() => _controlBusy.add(cameraId));
    try {
      await _api.controlInstance((instance['id'] as num).toInt(), 'stop');
      await _refreshInstances();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to stop: $e')));
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
          subtitle: 'Live feeds and uploaded videos',
          icon: AppIcons.cameras,
          trailing: canManage
              ? IconButton.filled(
                  style: IconButton.styleFrom(
                    backgroundColor: AppTheme.brandTeal,
                    foregroundColor: Colors.white,
                  ),
                  tooltip: 'Add camera',
                  icon: const Icon(AppIcons.add, size: 20),
                  onPressed: _openCreate,
                )
              : null,
        ),

        // Single Add camera action — the camera form itself handles both
        // live sources (RTSP/HTTP/USB) and video file uploads, so a separate
        // "Upload video" entry would be redundant. Pick "File" in the form's
        // source-type selector to upload a video.
        if (canManage)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: _ActionChip(
              label: 'Add camera or upload video',
              icon: AppIcons.add,
              accent: AppTheme.brandTeal,
              onTap: _openCreate,
            ),
          ),

        // Search
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: TextField(
            onChanged: (v) => setState(() => _query = v),
            decoration: const InputDecoration(
              prefixIcon: Icon(AppIcons.search, size: 18),
              hintText: 'Search by name, location, or group',
              isDense: true,
            ),
          ),
        ),

        Expanded(
          child: _loading
              ? const SkeletonList(count: 6)
              : _error != null
                  ? Center(child: Text(_error!, style: TextStyle(color: cs.error)))
                  : _cameras.isEmpty
                      ? EmptyState(
                          icon: AppIcons.cameras,
                          title: 'No cameras yet',
                          subtitle: canManage
                              ? 'Add a live RTSP feed or upload a video file to run detection on.'
                              : 'No cameras have been registered yet.',
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
                          : RefreshIndicator(
                              color: AppTheme.brandTeal,
                              onRefresh: () async {
                                HapticFeedback.mediumImpact();
                                await _load();
                              },
                              child: ListView.builder(
                                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                                itemCount: filtered.length,
                                itemBuilder: (_, i) {
                                  final c = filtered[i];
                                  final pid = (c['patient_id'] as num?)?.toInt();
                                  final patient = pid == null ? null : _patientNames[pid];
                                  final cameraId = (c['id'] as num).toInt();
                                  final instance = _instancesByCamera[cameraId];
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 10),
                                    child: _CameraRow(
                                      camera: c,
                                      patientLabel: patient,
                                      instance: instance,
                                      canManage: canManage,
                                      busy: _controlBusy.contains(cameraId),
                                      onEdit: () => _openEdit(c),
                                      onDelete: () => _delete(c),
                                      onStart: () => _startMonitoring(c),
                                      onStop: () => _stopMonitoring(c),
                                    ).animate()
                                        .fadeIn(duration: 240.ms, delay: (i * 30).ms)
                                        .slideY(begin: 0.05, duration: 300.ms),
                                  );
                                },
                              ),
                            ),
        ),
      ],
    );
  }
}

class _ActionChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color accent;
  final VoidCallback onTap;

  const _ActionChip({
    required this.label,
    required this.icon,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: accent.withValues(alpha: 0.30)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: accent, size: 18),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  style: GoogleFonts.outfit(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: accent,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
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
    final cs = Theme.of(context).colorScheme;
    final source = camera['source_type']?.toString() ?? '—';
    final url = camera['source_url']?.toString() ?? '';
    final group = camera['group_name']?.toString();
    final location = camera['location']?.toString();
    final status = (instance?['status'] as String?)?.toLowerCase();
    final isRunning = status == 'running';
    final isPaused = status == 'paused';

    return EldercareCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: isRunning
                        ? [AppTheme.brandTeal.withValues(alpha: 0.25), AppTheme.brandSage.withValues(alpha: 0.18)]
                        : [cs.surfaceContainerHighest, cs.surfaceContainerHighest],
                  ),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isRunning ? AppTheme.brandTeal.withValues(alpha: 0.40) : cs.outlineVariant,
                  ),
                ),
                child: Icon(
                  AppIcons.cameras,
                  color: isRunning ? AppTheme.brandTeal : cs.onSurfaceVariant,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      camera['name']?.toString() ?? 'Camera',
                      style: GoogleFonts.outfit(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: cs.onSurface,
                        letterSpacing: -0.2,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Wrap(
                      spacing: 8,
                      runSpacing: 2,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        StatusPill(
                          label: source.toUpperCase(),
                          kind: StatusKind.info,
                          dense: true,
                        ),
                        if (location != null && location.isNotEmpty)
                          Text(location, style: GoogleFonts.dmSans(fontSize: 11.5, color: cs.onSurfaceVariant)),
                        if (group != null && group.isNotEmpty)
                          Text('· $group', style: GoogleFonts.dmSans(fontSize: 11.5, color: cs.onSurfaceVariant)),
                      ],
                    ),
                  ],
                ),
              ),
              if (instance != null)
                StatusPill.forPipelineStatus(instance!['status'] as String?)
              else
                const StatusPill(label: 'Idle', kind: StatusKind.neutral, dense: true),
            ],
          ),

          if (patientLabel != null || url.isNotEmpty) ...[
            const SizedBox(height: 10),
            if (patientLabel != null)
              Row(
                children: [
                  Icon(AppIcons.patients, size: 12, color: AppTheme.brandSage),
                  const SizedBox(width: 4),
                  Text(
                    patientLabel!,
                    style: GoogleFonts.dmSans(
                      fontSize: 12,
                      color: AppTheme.brandSage,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            if (url.isNotEmpty) ...[
              if (patientLabel != null) const SizedBox(height: 4),
              Text(
                url,
                style: TextStyle(
                  color: cs.onSurfaceVariant,
                  fontSize: 11,
                  fontFamily: 'monospace',
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],

          if (canManage) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                if (busy)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                else if (isRunning || isPaused)
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onStop,
                      icon: const Icon(AppIcons.stop, size: 16),
                      label: const Text('Stop'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: cs.error,
                        side: BorderSide(color: cs.error.withValues(alpha: 0.4)),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                    ),
                  )
                else
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: onStart,
                      icon: const Icon(AppIcons.start, size: 16),
                      label: const Text('Start'),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.brandTeal,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                    ),
                  ),
                const SizedBox(width: 8),
                IconButton.outlined(
                  icon: const Icon(AppIcons.edit, size: 18),
                  onPressed: onEdit,
                  tooltip: 'Edit',
                ),
                IconButton.outlined(
                  icon: Icon(AppIcons.delete, size: 18, color: cs.error),
                  onPressed: onDelete,
                  tooltip: 'Delete',
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
