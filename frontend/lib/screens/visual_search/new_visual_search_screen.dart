import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/api_service.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_theme.dart';
import '../../widgets/eldercare_card.dart';
import '../../widgets/section_header.dart';

/// Form for kicking off a new Visual Search (GroundingDINO) job.
/// Picks an image, short video, or a live camera frame. On submit,
/// uploads (or triggers frame capture) and pops back with the new job row.
class NewVisualSearchScreen extends StatefulWidget {
  const NewVisualSearchScreen({super.key});

  @override
  State<NewVisualSearchScreen> createState() => _NewVisualSearchScreenState();
}

enum _InputKind { image, video, liveCamera }

enum _Stage { idle, picking, uploading, done, error }

class _NewVisualSearchScreenState extends State<NewVisualSearchScreen> {
  final ApiService _api = ApiService();
  final TextEditingController _promptCtrl = TextEditingController(
    text: 'person . wheelchair . walker .',
  );
  final TextEditingController _nameCtrl = TextEditingController();

  _InputKind _kind = _InputKind.image;
  PlatformFile? _picked;
  double _boxThreshold = 0.35;
  double _textThreshold = 0.25;

  _Stage _stage = _Stage.idle;
  int _sentBytes = 0;
  int _totalBytes = 0;
  String? _error;

  // Live camera state
  List<Map<String, dynamic>> _cameras = [];
  int? _selectedCameraId;
  bool _loadingCameras = false;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _promptCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadCameras() async {
    if (_cameras.isNotEmpty || _loadingCameras) return;
    setState(() => _loadingCameras = true);
    try {
      final list = await _api.getCameraConfigs();
      if (mounted) {
        setState(() {
          _cameras = list.cast<Map<String, dynamic>>();
          if (_cameras.isNotEmpty && _selectedCameraId == null) {
            _selectedCameraId = _cameras.first['id'] as int;
          }
          _loadingCameras = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loadingCameras = false);
    }
  }

  Future<void> _pickFile() async {
    HapticFeedback.lightImpact();
    setState(() {
      _stage = _Stage.picking;
      _error = null;
    });
    try {
      final result = await FilePicker.platform.pickFiles(
        type: _kind == _InputKind.image ? FileType.image : FileType.video,
        allowMultiple: false,
        withData: kIsWeb,
      );
      if (result == null || result.files.isEmpty) {
        setState(() => _stage = _Stage.idle);
        return;
      }
      final f = result.files.single;
      setState(() {
        _picked = f;
        _stage = _Stage.idle;
        if (_nameCtrl.text.trim().isEmpty) {
          _nameCtrl.text = f.name.replaceAll(RegExp(r'\.[^.]+$'), '');
        }
      });
    } catch (e) {
      setState(() {
        _stage = _Stage.error;
        _error = 'Could not open file picker: $e';
      });
    }
  }

  Future<void> _submit() async {
    final prompt = _promptCtrl.text.trim();
    if (prompt.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a text prompt')),
      );
      return;
    }

    if (_kind == _InputKind.liveCamera) {
      if (_selectedCameraId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Select a camera first')),
        );
        return;
      }
      HapticFeedback.mediumImpact();
      setState(() {
        _stage = _Stage.uploading;
        _error = null;
      });
      try {
        final job = await _api.submitGroundingDinoLiveFrameJob(
          cameraConfigId: _selectedCameraId!,
          prompt: prompt,
          name: _nameCtrl.text.trim().isEmpty ? null : _nameCtrl.text.trim(),
          boxThreshold: _boxThreshold,
          textThreshold: _textThreshold,
        );
        if (!mounted) return;
        HapticFeedback.heavyImpact();
        Navigator.pop(context, job);
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _stage = _Stage.error;
          _error = e is ApiException ? 'HTTP ${e.statusCode}: ${e.message}' : e.toString();
        });
      }
      return;
    }

    if (_picked == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pick a file first')),
      );
      return;
    }

    HapticFeedback.mediumImpact();
    setState(() {
      _stage = _Stage.uploading;
      _sentBytes = 0;
      _totalBytes = _picked!.size;
      _error = null;
    });

    try {
      final job = await _api.submitGroundingDinoJob(
        inputType: _kind == _InputKind.image ? 'image' : 'video',
        prompt: prompt,
        name: _nameCtrl.text.trim().isEmpty ? null : _nameCtrl.text.trim(),
        boxThreshold: _boxThreshold,
        textThreshold: _textThreshold,
        filePath: kIsWeb ? null : _picked!.path,
        bytes: kIsWeb ? _picked!.bytes : null,
        filename: _picked!.name,
        onProgress: (sent, total) {
          if (mounted) setState(() => _sentBytes = sent);
        },
      );
      if (!mounted) return;
      HapticFeedback.heavyImpact();
      Navigator.pop(context, job);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _stage = _Stage.error;
        _error = e is ApiException ? 'HTTP ${e.statusCode}: ${e.message}' : e.toString();
      });
    }
  }

  double get _uploadProgress {
    if (_totalBytes <= 0) return 0;
    return (_sentBytes / _totalBytes).clamp(0.0, 1.0);
  }

  bool get _busy => _stage == _Stage.uploading || _stage == _Stage.picking;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('New visual search')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(0, 0, 0, 32),
          children: [
            const SectionHeader(
              title: 'Find anything with a description',
              subtitle:
                  'Upload a file or capture a live camera frame. Describe what to look for — separate phrases with periods, e.g. "person . wheelchair . walker ."',
              icon: AppIcons.visualSearch,
            ),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Input kind selector
                  SegmentedButton<_InputKind>(
                    segments: const [
                      ButtonSegment(
                        value: _InputKind.image,
                        label: Text('Image'),
                        icon: Icon(Icons.image_rounded),
                      ),
                      ButtonSegment(
                        value: _InputKind.video,
                        label: Text('Video'),
                        icon: Icon(Icons.movie_creation_rounded),
                      ),
                      ButtonSegment(
                        value: _InputKind.liveCamera,
                        label: Text('Live Camera'),
                        icon: Icon(Icons.videocam_rounded),
                      ),
                    ],
                    selected: {_kind},
                    onSelectionChanged: _busy
                        ? null
                        : (set) {
                            final next = set.first;
                            setState(() {
                              _kind = next;
                              _picked = null;
                            });
                            if (next == _InputKind.liveCamera) _loadCameras();
                          },
                  ),
                  const SizedBox(height: 16),

                  // File picker / camera selector
                  if (_kind == _InputKind.liveCamera)
                    _CameraPickerCard(
                      cameras: _cameras,
                      selectedId: _selectedCameraId,
                      loading: _loadingCameras,
                      enabled: !_busy,
                      onChanged: (id) => setState(() => _selectedCameraId = id),
                    )
                  else if (_picked == null)
                    _PickerCard(
                      kind: _kind,
                      onTap: _pickFile,
                      picking: _stage == _Stage.picking,
                    )
                  else
                    _PickedFileCard(
                      file: _picked!,
                      onRemove: _busy ? null : () => setState(() => _picked = null),
                    ),

                  const SizedBox(height: 16),

                  // Prompt
                  EldercareCard(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Text prompt',
                          style: GoogleFonts.outfit(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: cs.onSurfaceVariant,
                            letterSpacing: 0.4,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _promptCtrl,
                          enabled: !_busy,
                          maxLines: 2,
                          decoration: const InputDecoration(
                            hintText: 'e.g. person . wheelchair . walker .',
                            isDense: true,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Phrases are separated by periods. Lowercase, singular nouns work best.',
                          style: GoogleFonts.dmSans(
                            fontSize: 11.5,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Name (optional)
                  EldercareCard(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Label (optional)',
                          style: GoogleFonts.outfit(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: cs.onSurfaceVariant,
                            letterSpacing: 0.4,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _nameCtrl,
                          enabled: !_busy,
                          decoration: const InputDecoration(
                            hintText: 'e.g. Living room — bedside check',
                            isDense: true,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Thresholds
                  EldercareCard(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Detection thresholds',
                          style: GoogleFonts.outfit(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: cs.onSurfaceVariant,
                            letterSpacing: 0.4,
                          ),
                        ),
                        const SizedBox(height: 6),
                        _ThresholdRow(
                          label: 'Box threshold',
                          value: _boxThreshold,
                          onChanged: _busy ? null : (v) => setState(() => _boxThreshold = v),
                        ),
                        _ThresholdRow(
                          label: 'Text threshold',
                          value: _textThreshold,
                          onChanged: _busy ? null : (v) => setState(() => _textThreshold = v),
                        ),
                      ],
                    ),
                  ),

                  if (_stage == _Stage.uploading) ...[
                    const SizedBox(height: 16),
                    if (_kind == _InputKind.liveCamera)
                      _CapturingCard()
                    else
                      _ProgressCard(
                        sentBytes: _sentBytes,
                        totalBytes: _totalBytes,
                        progress: _uploadProgress,
                      ),
                  ],

                  if (_stage == _Stage.error && _error != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: cs.errorContainer,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: cs.error.withValues(alpha: 0.30)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.error_outline_rounded, color: cs.error),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _error!,
                              style: GoogleFonts.dmSans(
                                fontSize: 13,
                                color: cs.onErrorContainer,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 24),
                  SizedBox(
                    height: 54,
                    child: FilledButton.icon(
                      onPressed: _busy ? null : _submit,
                      icon: Icon(
                        _kind == _InputKind.liveCamera
                            ? Icons.camera_alt_rounded
                            : Icons.search_rounded,
                        size: 22,
                      ),
                      label: Text(
                        _busy
                            ? (_kind == _InputKind.liveCamera
                                ? 'Capturing frame…'
                                : 'Uploading…')
                            : (_kind == _InputKind.liveCamera
                                ? 'Capture & search'
                                : 'Run visual search'),
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.brandTeal,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ThresholdRow extends StatelessWidget {
  final String label;
  final double value;
  final ValueChanged<double>? onChanged;

  const _ThresholdRow({required this.label, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        SizedBox(
          width: 120,
          child: Text(
            label,
            style: GoogleFonts.dmSans(fontSize: 13, color: cs.onSurfaceVariant),
          ),
        ),
        Expanded(
          child: Slider(
            value: value,
            min: 0.05,
            max: 0.9,
            divisions: 17,
            label: value.toStringAsFixed(2),
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 44,
          child: Text(
            value.toStringAsFixed(2),
            textAlign: TextAlign.right,
            style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

class _CameraPickerCard extends StatelessWidget {
  final List<Map<String, dynamic>> cameras;
  final int? selectedId;
  final bool loading;
  final bool enabled;
  final ValueChanged<int?> onChanged;

  const _CameraPickerCard({
    required this.cameras,
    required this.selectedId,
    required this.loading,
    required this.enabled,
    required this.onChanged,
  });

  String _sourceLabel(Map<String, dynamic> cam) {
    final type = (cam['source_type'] as String? ?? '').replaceAll('_', ' ');
    final url = cam['source_url'] as String? ?? '';
    final short = url.length > 30 ? '${url.substring(0, 27)}…' : url;
    return '$type · $short';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return EldercareCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.videocam_rounded, color: AppTheme.brandTeal, size: 20),
              const SizedBox(width: 8),
              Text(
                'Select camera',
                style: GoogleFonts.outfit(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurfaceVariant,
                  letterSpacing: 0.4,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (loading)
            const Center(
              child: SizedBox(
                height: 24,
                width: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: AppTheme.brandTeal,
                ),
              ),
            )
          else if (cameras.isEmpty)
            Text(
              'No cameras configured. Add a camera in the Cameras tab first.',
              style: GoogleFonts.dmSans(fontSize: 13, color: cs.onSurfaceVariant),
            )
          else
            DropdownButtonFormField<int>(
              value: selectedId,
              isExpanded: true,
              decoration: const InputDecoration(isDense: true),
              items: cameras.map((cam) {
                final id = cam['id'] as int;
                final name = cam['name'] as String? ?? 'Camera $id';
                return DropdownMenuItem<int>(
                  value: id,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        name,
                        style: GoogleFonts.outfit(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        _sourceLabel(cam),
                        style: GoogleFonts.dmSans(
                          fontSize: 11,
                          color: cs.onSurfaceVariant,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                );
              }).toList(),
              onChanged: enabled ? onChanged : null,
            ),
          const SizedBox(height: 10),
          Text(
            'A single frame will be captured from this source at the moment you tap "Capture & search".',
            style: GoogleFonts.dmSans(fontSize: 11.5, color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _PickerCard extends StatelessWidget {
  final _InputKind kind;
  final VoidCallback onTap;
  final bool picking;
  const _PickerCard({required this.kind, required this.onTap, required this.picking});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: picking ? null : onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: AppTheme.brandTeal.withValues(alpha: 0.35),
              width: 1.5,
            ),
          ),
          child: Column(
            children: [
              Icon(
                kind == _InputKind.image ? Icons.image_rounded : Icons.video_file_rounded,
                color: AppTheme.brandTeal,
                size: 40,
              ),
              const SizedBox(height: 14),
              Text(
                picking
                    ? 'Opening picker…'
                    : kind == _InputKind.image
                        ? 'Tap to choose an image'
                        : 'Tap to choose a video',
                style: GoogleFonts.outfit(
                  fontWeight: FontWeight.w700,
                  fontSize: 15.5,
                  color: cs.onSurface,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                kind == _InputKind.image
                    ? 'JPG / PNG / WEBP · up to 25 MB'
                    : 'MP4 / MOV / AVI · up to 200 MB',
                style: GoogleFonts.dmSans(fontSize: 12, color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PickedFileCard extends StatelessWidget {
  final PlatformFile file;
  final VoidCallback? onRemove;
  const _PickedFileCard({required this.file, this.onRemove});

  String _humanSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return EldercareCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppTheme.brandTeal.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.attachment_rounded, color: AppTheme.brandTeal, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  file.name,
                  style: GoogleFonts.outfit(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: cs.onSurface,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  _humanSize(file.size),
                  style: GoogleFonts.dmSans(fontSize: 12, color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
          if (onRemove != null)
            IconButton(
              icon: const Icon(Icons.close_rounded, size: 20),
              tooltip: 'Remove',
              onPressed: onRemove,
            ),
        ],
      ),
    );
  }
}

class _CapturingCard extends StatelessWidget {
  const _CapturingCard();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return EldercareCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          const SizedBox(
            width: 18, height: 18,
            child: CircularProgressIndicator(strokeWidth: 2.5, color: AppTheme.brandTeal),
          ),
          const SizedBox(width: 12),
          Text(
            'Queuing frame capture…',
            style: GoogleFonts.outfit(
              fontWeight: FontWeight.w700,
              fontSize: 14.5,
              color: cs.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProgressCard extends StatelessWidget {
  final int sentBytes;
  final int totalBytes;
  final double progress;

  const _ProgressCard({
    required this.sentBytes,
    required this.totalBytes,
    required this.progress,
  });

  String _humanSize(int bytes) {
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return EldercareCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const SizedBox(
                width: 18, height: 18,
                child: CircularProgressIndicator(strokeWidth: 2.5, color: AppTheme.brandTeal),
              ),
              const SizedBox(width: 12),
              Text(
                'Uploading…',
                style: GoogleFonts.outfit(
                  fontWeight: FontWeight.w700,
                  fontSize: 14.5,
                  color: cs.onSurface,
                ),
              ),
              const Spacer(),
              if (totalBytes > 0)
                Text(
                  '${(progress * 100).toStringAsFixed(0)}%',
                  style: GoogleFonts.outfit(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: AppTheme.brandTeal,
                  ),
                ),
            ],
          ),
          if (totalBytes > 0) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 7,
                backgroundColor: cs.surfaceContainerHighest,
                color: AppTheme.brandTeal,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '${_humanSize(sentBytes)} of ${_humanSize(totalBytes)}',
              style: GoogleFonts.dmSans(fontSize: 12, color: cs.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }
}
