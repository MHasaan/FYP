import 'package:flutter/material.dart';

import '../../services/api_service.dart';
import '../../theme/app_icons.dart';
import '../../widgets/form_field_box.dart';

class DetectionRuleFormDialog extends StatefulWidget {
  final Map<String, dynamic>? existing;
  final List<Map<String, dynamic>> cameras;
  final List<Map<String, dynamic>> patients;

  const DetectionRuleFormDialog({
    super.key,
    this.existing,
    required this.cameras,
    required this.patients,
  });

  static Future<bool?> show(
    BuildContext context, {
    Map<String, dynamic>? existing,
    required List<Map<String, dynamic>> cameras,
    required List<Map<String, dynamic>> patients,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (_) => DetectionRuleFormDialog(
        existing: existing,
        cameras: cameras,
        patients: patients,
      ),
    );
  }

  @override
  State<DetectionRuleFormDialog> createState() => _DetectionRuleFormDialogState();
}

class _DetectionRuleFormDialogState extends State<DetectionRuleFormDialog> {
  final _api = ApiService();
  String _scope = 'global';
  int? _cameraId;
  int? _patientId;
  double _sensitivity = 0.5;
  bool _fallEnabled = true;
  bool _seizureEnabled = true;
  double _fallThreshold = 0.7;
  double _seizureThreshold = 0.7;
  late TextEditingController _notes;
  bool _busy = false;
  String? _error;
  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _notes = TextEditingController(text: e?['notes']?.toString() ?? '');
    if (e != null) {
      _cameraId = (e['camera_config_id'] as num?)?.toInt();
      _patientId = (e['patient_id'] as num?)?.toInt();
      if (_cameraId != null) {
        _scope = 'camera';
      } else if (_patientId != null) {
        _scope = 'patient';
      } else {
        _scope = 'global';
      }
      _sensitivity = ((e['sensitivity'] as num?)?.toDouble() ?? 0.5).clamp(0.0, 1.0);
      _fallEnabled = e['fall_enabled'] != false;
      _seizureEnabled = e['seizure_enabled'] != false;
      _fallThreshold = ((e['fall_threshold'] as num?)?.toDouble() ?? 0.7).clamp(0.05, 0.99);
      _seizureThreshold = ((e['seizure_threshold'] as num?)?.toDouble() ?? 0.7).clamp(0.05, 0.99);
    }
  }

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_scope == 'camera' && _cameraId == null) {
      setState(() => _error = 'Pick a camera');
      return;
    }
    if (_scope == 'patient' && _patientId == null) {
      setState(() => _error = 'Pick a patient');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final payload = <String, dynamic>{
      'camera_config_id': _scope == 'camera' ? _cameraId : null,
      'patient_id': _scope == 'patient' ? _patientId : null,
      'sensitivity': _sensitivity,
      'fall_enabled': _fallEnabled,
      'seizure_enabled': _seizureEnabled,
      'fall_threshold': _fallThreshold,
      'seizure_threshold': _seizureThreshold,
      'notes': _notes.text.trim().isEmpty ? null : _notes.text.trim(),
    };
    try {
      if (_isEdit) {
        await _api.updateDetectionSetting(widget.existing!['id'] as int, payload);
      } else {
        await _api.createDetectionSetting(payload);
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
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 760),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(AppIcons.detectionRules, color: cs.primary),
                  const SizedBox(width: 10),
                  Text(
                    _isEdit ? 'Edit detection rule' : 'New detection rule',
                    style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const Spacer(),
                  IconButton(icon: const Icon(AppIcons.close), onPressed: () => Navigator.of(context).pop(false)),
                ],
              ),
              const SizedBox(height: 8),
              const Divider(height: 1),
              const SizedBox(height: 12),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      FormFieldBox(
                        label: 'Scope',
                        required: true,
                        helper: 'Per-camera overrides per-patient, which overrides global default.',
                        child: SegmentedButton<String>(
                          style: SegmentedButton.styleFrom(visualDensity: VisualDensity.compact),
                          showSelectedIcon: false,
                          segments: const [
                            ButtonSegment(value: 'global', label: Text('Global')),
                            ButtonSegment(value: 'patient', label: Text('Patient')),
                            ButtonSegment(value: 'camera', label: Text('Camera')),
                          ],
                          selected: {_scope},
                          onSelectionChanged: (s) => setState(() => _scope = s.first),
                        ),
                      ),
                      if (_scope == 'camera') ...[
                        const SizedBox(height: 12),
                        FormFieldBox(
                          label: 'Apply to camera',
                          required: true,
                          child: DropdownButtonFormField<int>(
                            value: _cameraId,
                            items: widget.cameras
                                .map((c) => DropdownMenuItem(
                                      value: (c['id'] as num).toInt(),
                                      child: Text(c['name']?.toString() ?? 'Camera #${c['id']}'),
                                    ))
                                .toList(),
                            onChanged: (v) => setState(() => _cameraId = v),
                          ),
                        ),
                      ],
                      if (_scope == 'patient') ...[
                        const SizedBox(height: 12),
                        FormFieldBox(
                          label: 'Apply to patient',
                          required: true,
                          child: DropdownButtonFormField<int>(
                            value: _patientId,
                            items: widget.patients
                                .map((p) => DropdownMenuItem(
                                      value: (p['id'] as num).toInt(),
                                      child: Text(p['full_name']?.toString() ?? 'Patient #${p['id']}'),
                                    ))
                                .toList(),
                            onChanged: (v) => setState(() => _patientId = v),
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      _SliderField(
                        label: 'Sensitivity',
                        helper: 'Higher = more sensitive, more false positives.',
                        value: _sensitivity,
                        min: 0.0,
                        max: 1.0,
                        onChanged: (v) => setState(() => _sensitivity = v),
                      ),
                      const SizedBox(height: 12),
                      _ToggleSliderField(
                        label: 'Fall detection',
                        enabled: _fallEnabled,
                        threshold: _fallThreshold,
                        onEnabledChanged: (v) => setState(() => _fallEnabled = v),
                        onThresholdChanged: (v) => setState(() => _fallThreshold = v),
                      ),
                      const SizedBox(height: 12),
                      _ToggleSliderField(
                        label: 'Seizure detection',
                        enabled: _seizureEnabled,
                        threshold: _seizureThreshold,
                        onEnabledChanged: (v) => setState(() => _seizureEnabled = v),
                        onThresholdChanged: (v) => setState(() => _seizureThreshold = v),
                      ),
                      const SizedBox(height: 12),
                      FormFieldBox(
                        label: 'Notes',
                        child: TextField(controller: _notes, maxLines: 2),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Text(_error!, style: TextStyle(color: cs.error)),
                      ],
                    ],
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
                    onPressed: _busy ? null : _save,
                    icon: const Icon(AppIcons.check, size: 18),
                    label: Text(_busy ? 'Saving…' : (_isEdit ? 'Save' : 'Create rule')),
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

class _SliderField extends StatelessWidget {
  final String label;
  final String? helper;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  const _SliderField({
    required this.label,
    this.helper,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return FormFieldBox(
      label: '$label  (${value.toStringAsFixed(2)})',
      helper: helper,
      child: Slider(
        value: value,
        min: min,
        max: max,
        divisions: 20,
        onChanged: onChanged,
        label: value.toStringAsFixed(2),
      ),
    );
  }
}

class _ToggleSliderField extends StatelessWidget {
  final String label;
  final bool enabled;
  final double threshold;
  final ValueChanged<bool> onEnabledChanged;
  final ValueChanged<double> onThresholdChanged;

  const _ToggleSliderField({
    required this.label,
    required this.enabled,
    required this.threshold,
    required this.onEnabledChanged,
    required this.onThresholdChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Switch(value: enabled, onChanged: onEnabledChanged),
              const SizedBox(width: 6),
              Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
              const Spacer(),
              Text('Threshold: ${threshold.toStringAsFixed(2)}',
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
            ],
          ),
          Slider(
            value: threshold.clamp(0.05, 0.99),
            min: 0.05,
            max: 0.99,
            divisions: 19,
            onChanged: enabled ? onThresholdChanged : null,
          ),
        ],
      ),
    );
  }
}
