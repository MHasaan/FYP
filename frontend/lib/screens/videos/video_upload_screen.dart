import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/api_service.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_theme.dart';
import '../../widgets/eldercare_card.dart';
import '../../widgets/section_header.dart';

/// "Run model on video" — picks a video file from the device, uploads it to
/// the backend, then creates a CameraConfig + starts a pipeline so the ML
/// manager processes it. All in one screen.
class VideoUploadScreen extends StatefulWidget {
  const VideoUploadScreen({super.key});

  @override
  State<VideoUploadScreen> createState() => _VideoUploadScreenState();
}

enum _UploadStage { idle, picking, uploading, creating, starting, done, error }

class _VideoUploadScreenState extends State<VideoUploadScreen> {
  final ApiService _api = ApiService();
  final TextEditingController _nameCtrl = TextEditingController();

  PlatformFile? _picked;
  _UploadStage _stage = _UploadStage.idle;
  int _sentBytes = 0;
  int _totalBytes = 0;
  String? _error;
  String? _serverPath;
  int? _createdInstanceId;

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickVideo() async {
    HapticFeedback.lightImpact();
    setState(() {
      _stage = _UploadStage.picking;
      _error = null;
    });
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.video,
        allowMultiple: false,
        withData: kIsWeb,
      );
      if (result == null || result.files.isEmpty) {
        setState(() => _stage = _UploadStage.idle);
        return;
      }
      final f = result.files.single;
      setState(() {
        _picked = f;
        _stage = _UploadStage.idle;
        if (_nameCtrl.text.trim().isEmpty) {
          _nameCtrl.text = f.name.replaceAll(RegExp(r'\.[^.]+$'), '');
        }
      });
    } catch (e) {
      setState(() {
        _stage = _UploadStage.error;
        _error = 'Could not open file picker: $e';
      });
    }
  }

  Future<void> _runDetection() async {
    if (_picked == null) return;
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Give this video a name first')),
      );
      return;
    }

    HapticFeedback.mediumImpact();

    // Step 1: upload
    setState(() {
      _stage = _UploadStage.uploading;
      _error = null;
      _sentBytes = 0;
      _totalBytes = _picked!.size;
    });

    Map<String, dynamic> uploadResp;
    try {
      uploadResp = await _api.uploadVideo(
        filePath: kIsWeb ? null : _picked!.path,
        bytes: kIsWeb ? _picked!.bytes : null,
        filename: _picked!.name,
        onProgress: (sent, total) {
          if (mounted) setState(() => _sentBytes = sent);
        },
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _stage = _UploadStage.error;
          _error = 'Upload failed: $e';
        });
      }
      return;
    }

    _serverPath = uploadResp['path'] as String?;
    if (_serverPath == null || _serverPath!.isEmpty) {
      if (mounted) {
        setState(() {
          _stage = _UploadStage.error;
          _error = 'Backend did not return a video path';
        });
      }
      return;
    }

    // Step 2: create camera config pointing at the uploaded file
    if (mounted) setState(() => _stage = _UploadStage.creating);

    int cameraConfigId;
    try {
      final created = await _api.createCameraConfig({
        'name': name,
        'source_type': 'video_file',
        'source_url': _serverPath,
        'fps': 25,
        'width': 1280,
        'height': 720,
        'enabled_models': ['pose', 'fall_detection'],
      });
      cameraConfigId = (created['id'] as num).toInt();
    } catch (e) {
      if (mounted) {
        setState(() {
          _stage = _UploadStage.error;
          _error = 'Could not register camera config: $e';
        });
      }
      return;
    }

    // Step 3: create + start a pipeline instance
    if (mounted) setState(() => _stage = _UploadStage.starting);

    try {
      final instance = await _api.createInstance({
        'name': name,
        'camera_config_id': cameraConfigId,
        'enabled_models': ['pose', 'fall_detection'],
        'model_configs': const {},
      });
      _createdInstanceId = (instance['id'] as num).toInt();
      await _api.controlInstance(_createdInstanceId!, 'start');
    } catch (e) {
      if (mounted) {
        setState(() {
          _stage = _UploadStage.error;
          _error = 'Detection started, but failed to launch: $e';
        });
      }
      return;
    }

    if (mounted) {
      HapticFeedback.heavyImpact();
      setState(() => _stage = _UploadStage.done);
    }
  }

  void _reset() {
    HapticFeedback.lightImpact();
    setState(() {
      _picked = null;
      _stage = _UploadStage.idle;
      _sentBytes = 0;
      _totalBytes = 0;
      _error = null;
      _serverPath = null;
      _createdInstanceId = null;
      _nameCtrl.clear();
    });
  }

  double get _uploadProgress {
    if (_totalBytes <= 0) return 0;
    return (_sentBytes / _totalBytes).clamp(0.0, 1.0);
  }

  bool get _isWorking =>
      _stage == _UploadStage.uploading ||
      _stage == _UploadStage.creating ||
      _stage == _UploadStage.starting;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Upload video'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(0, 0, 0, 24),
          children: [
            const SectionHeader(
              title: 'Run detection on a video',
              subtitle: 'Pick a video, we upload it, then the ML engine analyses it.',
              icon: AppIcons.cameras,
            ),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_picked == null) ...[
                    _PickerCard(
                      onTap: _pickVideo,
                      picking: _stage == _UploadStage.picking,
                    ),
                  ] else ...[
                    _PickedFileCard(
                      file: _picked!,
                      onRemove: _isWorking ? null : _reset,
                    ),
                    const SizedBox(height: 14),
                    EldercareCard(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Detection name',
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
                            enabled: !_isWorking,
                            decoration: const InputDecoration(
                              hintText: 'e.g. Living room — Mar 16',
                              isDense: true,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  if (_isWorking) ...[
                    const SizedBox(height: 16),
                    _ProgressCard(
                      stage: _stage,
                      sentBytes: _sentBytes,
                      totalBytes: _totalBytes,
                      progress: _uploadProgress,
                    ),
                  ],

                  if (_stage == _UploadStage.done) ...[
                    const SizedBox(height: 16),
                    _DoneCard(
                      instanceId: _createdInstanceId,
                      onAnother: _reset,
                    ),
                  ],

                  if (_stage == _UploadStage.error && _error != null) ...[
                    const SizedBox(height: 16),
                    _ErrorCard(message: _error!, onRetry: _reset),
                  ],

                  if (_picked != null && _stage != _UploadStage.done && _stage != _UploadStage.error) ...[
                    const SizedBox(height: 24),
                    SizedBox(
                      height: 54,
                      child: FilledButton.icon(
                        onPressed: _isWorking ? null : _runDetection,
                        icon: const Icon(Icons.play_arrow_rounded, size: 22),
                        label: Text(_isWorking ? 'Working…' : 'Run detection'),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.brandTeal,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Picker (empty state) ──────────────────────────────────────────────────────
class _PickerCard extends StatelessWidget {
  final VoidCallback onTap;
  final bool picking;

  const _PickerCard({required this.onTap, required this.picking});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: picking ? null : onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 24),
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: AppTheme.brandTeal.withValues(alpha: 0.35),
              width: 1.5,
              strokeAlign: BorderSide.strokeAlignInside,
            ),
          ),
          child: Column(
            children: [
              Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppTheme.brandTeal.withValues(alpha: 0.16),
                      AppTheme.brandSage.withValues(alpha: 0.10),
                    ],
                  ),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.video_file_rounded,
                    color: AppTheme.brandTeal, size: 36),
              ).animate(onPlay: (c) => c.repeat(reverse: true))
                  .scaleXY(begin: 1.0, end: 1.06, duration: 1600.ms),
              const SizedBox(height: 18),
              Text(
                picking ? 'Opening picker…' : 'Tap to choose a video',
                style: GoogleFonts.outfit(
                  fontWeight: FontWeight.w700,
                  fontSize: 17,
                  color: cs.onSurface,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'MP4 / MOV / AVI · up to 500 MB',
                style: GoogleFonts.dmSans(
                  fontSize: 12.5,
                  color: cs.onSurfaceVariant,
                ),
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
            child: Icon(Icons.movie_creation_rounded,
                color: AppTheme.brandTeal, size: 22),
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
                  style: GoogleFonts.dmSans(
                    fontSize: 12,
                    color: cs.onSurfaceVariant,
                  ),
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

class _ProgressCard extends StatelessWidget {
  final _UploadStage stage;
  final int sentBytes;
  final int totalBytes;
  final double progress;

  const _ProgressCard({
    required this.stage,
    required this.sentBytes,
    required this.totalBytes,
    required this.progress,
  });

  String get _stageLabel {
    switch (stage) {
      case _UploadStage.uploading: return 'Uploading…';
      case _UploadStage.creating:  return 'Registering camera…';
      case _UploadStage.starting:  return 'Starting detection…';
      default: return 'Working…';
    }
  }

  String _humanSize(int bytes) {
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isUpload = stage == _UploadStage.uploading;
    return EldercareCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2.5, color: AppTheme.brandTeal),
              ),
              const SizedBox(width: 12),
              Text(
                _stageLabel,
                style: GoogleFonts.outfit(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: cs.onSurface,
                ),
              ),
              const Spacer(),
              if (isUpload && totalBytes > 0)
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
          if (isUpload && totalBytes > 0) ...[
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 8,
                backgroundColor: cs.surfaceContainerHighest,
                color: AppTheme.brandTeal,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${_humanSize(sentBytes)} of ${_humanSize(totalBytes)}',
              style: GoogleFonts.dmSans(
                fontSize: 12,
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _DoneCard extends StatelessWidget {
  final int? instanceId;
  final VoidCallback onAnother;

  const _DoneCard({required this.instanceId, required this.onAnother});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppTheme.brandSage.withValues(alpha: 0.18),
            AppTheme.brandTeal.withValues(alpha: 0.10),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.brandSage.withValues(alpha: 0.40)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: const BoxDecoration(
                  color: AppTheme.brandSage,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check_rounded, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Detection running',
                  style: GoogleFonts.outfit(
                    fontWeight: FontWeight.w700,
                    fontSize: 17,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Your video is being analysed. Detected falls or seizures will appear in the Incidents tab.',
            style: GoogleFonts.dmSans(
              fontSize: 13,
              height: 1.5,
            ),
          ),
          if (instanceId != null) ...[
            const SizedBox(height: 6),
            Text(
              'Pipeline instance #$instanceId',
              style: TextStyle(
                fontSize: 11,
                color: Colors.black.withValues(alpha: 0.6),
                fontFamily: 'monospace',
              ),
            ),
          ],
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: onAnother,
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Run another video'),
          ),
        ],
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorCard({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.errorContainer,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.error.withValues(alpha: 0.30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.error_outline_rounded, color: cs.error),
              const SizedBox(width: 10),
              Text(
                'Something went wrong',
                style: GoogleFonts.outfit(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: cs.error,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            message,
            style: GoogleFonts.dmSans(fontSize: 13, color: cs.onErrorContainer),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Try again'),
          ),
        ],
      ),
    );
  }
}
