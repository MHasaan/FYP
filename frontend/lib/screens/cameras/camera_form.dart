import 'package:flutter/material.dart';

import '../../services/api_service.dart';
import '../../theme/app_icons.dart';
import '../../widgets/form_field_box.dart';

/// Models actually wired in the ML manager today (see WORKER_FACTORIES in
/// `ml_manager/manager/pipeline_manager.py`). The other names are reserved
/// for future workers; we still surface them so the UI matches the FRs but
/// disable selection until the worker exists.
const Set<String> kWiredModels = {'pose', 'fall_detection', 'test'};
const Set<String> kPlannedModels = {'yolo', 'seizure_detection'};

class CameraFormDialog extends StatefulWidget {
  final Map<String, dynamic>? existing;

  const CameraFormDialog({super.key, this.existing});

  static Future<bool?> show(BuildContext context, {Map<String, dynamic>? existing}) {
    return showDialog<bool>(
      context: context,
      builder: (_) => CameraFormDialog(existing: existing),
    );
  }

  @override
  State<CameraFormDialog> createState() => _CameraFormDialogState();
}

class _CameraFormDialogState extends State<CameraFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _api = ApiService();

  late TextEditingController _name;
  late TextEditingController _location;
  late TextEditingController _group;
  late TextEditingController _source;
  late TextEditingController _fps;

  String _sourceType = 'rtsp';
  String _resolution = '640x480';
  int? _patientId;
  Set<String> _models = {};
  bool _autoStart = true;

  List<Map<String, dynamic>> _patients = [];
  bool _busy = false;
  String? _error;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?['name']?.toString() ?? '');
    _location = TextEditingController(text: e?['location']?.toString() ?? '');
    _group = TextEditingController(text: e?['group_name']?.toString() ?? '');
    _source = TextEditingController(text: e?['source_url']?.toString() ?? '');
    _fps = TextEditingController(text: (e?['fps'] ?? 30).toString());
    _sourceType = (e?['source_type'] as String?) ?? 'rtsp';
    final w = (e?['width'] as num?)?.toInt() ?? 640;
    final h = (e?['height'] as num?)?.toInt() ?? 480;
    _resolution = '${w}x$h';
    _patientId = (e?['patient_id'] as num?)?.toInt();
    final em = e?['enabled_models'];
    if (em is List) _models = em.map((e) => e.toString()).toSet();
    if (_models.isEmpty) _models = {'pose', 'fall_detection'};
    // Auto-start defaults ON for new cameras; OFF when editing existing config
    // (we don't want to surprise the user by spawning a pipeline on edit).
    _autoStart = !_isEdit;
    _loadPatients();
  }

  @override
  void dispose() {
    _name.dispose();
    _location.dispose();
    _group.dispose();
    _source.dispose();
    _fps.dispose();
    super.dispose();
  }

  Future<void> _loadPatients() async {
    try {
      final res = await _api.getPatients();
      if (mounted) setState(() => _patients = res.cast<Map<String, dynamic>>());
    } catch (_) {}
  }

  /// Returns only the models that are actually wired in the ML manager.
  List<String> get _wiredEnabledModels =>
      _models.where(kWiredModels.contains).toList();

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final parts = _resolution.split('x');
    final width = int.tryParse(parts[0]) ?? 640;
    final height = int.tryParse(parts.length > 1 ? parts[1] : '480') ?? 480;
    final wiredModels = _wiredEnabledModels;
    final cameraPayload = <String, dynamic>{
      'name': _name.text.trim(),
      'location': _location.text.trim().isEmpty ? null : _location.text.trim(),
      'group_name': _group.text.trim().isEmpty ? null : _group.text.trim(),
      'source_type': _sourceType,
      'source_url': _source.text.trim(),
      'fps': int.tryParse(_fps.text.trim()) ?? 30,
      'width': width,
      'height': height,
      'patient_id': _patientId,
      // Only send wired models to the backend; the planned-but-unwired ones
      // would be silently dropped by the ML pipeline anyway.
      'enabled_models': wiredModels,
    };
    try {
      Map<String, dynamic> camera;
      if (_isEdit) {
        camera = await _api.updateCameraConfig(widget.existing!['id'] as int, cameraPayload);
      } else {
        camera = await _api.createCameraConfig(cameraPayload);
      }

      // For brand-new cameras the user can opt to spin up a pipeline instance
      // immediately. This is the bridge into the ML manager — without it, the
      // camera_config row is just metadata and pose/fall never run.
      if (!_isEdit && _autoStart) {
        try {
          final cameraId = (camera['id'] as num).toInt();
          final instance = await _api.createInstance({
            'name': _name.text.trim(),
            'camera_config_id': cameraId,
            'enabled_models': wiredModels.isEmpty ? ['pose'] : wiredModels,
            'model_configs': <String, dynamic>{},
          });
          final instanceId = (instance['id'] as num).toInt();
          // Fire-and-forget start command; ML manager processes async.
          // ignore: discarded_futures
          _api.controlInstance(instanceId, 'start');
        } catch (e) {
          // Camera was saved successfully; instance creation is the optional
          // bridge step. Surface a soft warning rather than failing the form.
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('Camera saved, but failed to start monitoring: $e'),
            ));
          }
        }
      }

      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 720),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(AppIcons.cameras, color: cs.primary),
                  const SizedBox(width: 10),
                  Text(
                    _isEdit ? 'Edit camera' : 'Add camera',
                    style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(AppIcons.close),
                    onPressed: () => Navigator.of(context).pop(false),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Divider(height: 1),
              const SizedBox(height: 12),
              Expanded(
                child: SingleChildScrollView(
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        FormFieldBox(
                          label: 'Name',
                          required: true,
                          child: TextFormField(
                            controller: _name,
                            validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: FormFieldBox(
                                label: 'Location',
                                child: TextFormField(controller: _location),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: FormFieldBox(
                                label: 'Group',
                                child: TextFormField(controller: _group),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        FormFieldBox(
                          label: 'Assigned patient',
                          child: DropdownButtonFormField<int?>(
                            value: _patientId,
                            items: [
                              const DropdownMenuItem<int?>(value: null, child: Text('Unassigned')),
                              ..._patients.map((p) => DropdownMenuItem<int?>(
                                    value: (p['id'] as num).toInt(),
                                    child: Text(p['full_name']?.toString() ?? 'Patient #${p['id']}'),
                                  )),
                            ],
                            onChanged: (v) => setState(() => _patientId = v),
                          ),
                        ),
                        const SizedBox(height: 12),
                        FormFieldBox(
                          label: 'Source type',
                          required: true,
                          child: SegmentedButton<String>(
                            style: SegmentedButton.styleFrom(visualDensity: VisualDensity.compact),
                            showSelectedIcon: false,
                            segments: const [
                              ButtonSegment(value: 'rtsp', label: Text('RTSP')),
                              ButtonSegment(value: 'http', label: Text('HTTP')),
                              ButtonSegment(value: 'usb', label: Text('USB')),
                              ButtonSegment(value: 'video_file', label: Text('File')),
                            ],
                            selected: {_sourceType},
                            onSelectionChanged: (s) => setState(() => _sourceType = s.first),
                          ),
                        ),
                        const SizedBox(height: 12),
                        FormFieldBox(
                          label: 'Source URL / device path',
                          required: true,
                          helper: _sourceType == 'usb' ? 'e.g. 0 (default camera)' : (_sourceType == 'video_file' ? 'e.g. /videos/sample.mp4' : 'e.g. rtsp://camera.local/stream'),
                          child: TextFormField(
                            controller: _source,
                            validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: FormFieldBox(
                                label: 'FPS',
                                child: TextFormField(
                                  controller: _fps,
                                  keyboardType: TextInputType.number,
                                  validator: (v) {
                                    final n = int.tryParse(v ?? '');
                                    if (n == null || n < 1 || n > 60) return '1–60';
                                    return null;
                                  },
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: FormFieldBox(
                                label: 'Resolution',
                                child: DropdownButtonFormField<String>(
                                  value: _resolution,
                                  items: const [
                                    DropdownMenuItem(value: '640x480', child: Text('640 × 480')),
                                    DropdownMenuItem(value: '1280x720', child: Text('1280 × 720')),
                                    DropdownMenuItem(value: '1920x1080', child: Text('1920 × 1080')),
                                  ],
                                  onChanged: (v) => setState(() => _resolution = v ?? '640x480'),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        FormFieldBox(
                          label: 'Detection models',
                          required: true,
                          helper:
                              'Pick at least one. "test" is a no-op passthrough — use it for a plain live feed without ML. Greyed-out models are not yet wired.',
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            children: const ['test', 'pose', 'fall_detection', 'yolo', 'seizure_detection'].map((m) {
                              final wired = kWiredModels.contains(m);
                              final selected = _models.contains(m);
                              final chip = FilterChip(
                                label: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(m),
                                    if (!wired) ...[
                                      const SizedBox(width: 4),
                                      Icon(Icons.lock_outline_rounded,
                                          size: 12, color: cs.onSurfaceVariant),
                                    ],
                                  ],
                                ),
                                selected: selected,
                                onSelected: wired
                                    ? (v) {
                                        setState(() {
                                          if (v) {
                                            _models.add(m);
                                          } else {
                                            _models.remove(m);
                                          }
                                        });
                                      }
                                    : null,
                              );
                              return wired
                                  ? chip
                                  : Tooltip(
                                      message: 'Not yet wired in the ML manager',
                                      child: chip,
                                    );
                            }).toList(),
                          ),
                        ),
                        if (!_isEdit) ...[
                          const SizedBox(height: 14),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: cs.primaryContainer.withValues(alpha: 0.4),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: cs.primaryContainer),
                            ),
                            child: Row(
                              children: [
                                Switch(
                                  value: _autoStart,
                                  onChanged: (v) => setState(() => _autoStart = v),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        'Start monitoring right away',
                                        style: theme.textTheme.bodyMedium?.copyWith(
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'Creates a pipeline instance and starts pose/fall detection on this camera. You can stop it any time.',
                                        style: theme.textTheme.bodySmall?.copyWith(
                                          color: cs.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        if (_error != null) ...[
                          const SizedBox(height: 16),
                          Text(_error!, style: TextStyle(color: cs.error)),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _busy ? null : () => Navigator.of(context).pop(false),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: (_busy || _wiredEnabledModels.isEmpty) ? null : _save,
                    icon: const Icon(AppIcons.check, size: 18),
                    label: Text(_busy
                        ? 'Saving…'
                        : (_isEdit
                            ? 'Save'
                            : (_autoStart ? 'Create & start' : 'Create camera'))),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
