import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/api_service.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_theme.dart';
import '../../widgets/eldercare_card.dart';

/// Shows a single Visual Search job. Polls until status reaches a terminal
/// state, then shows the annotated output + detections list.
class VisualSearchResultScreen extends StatefulWidget {
  final int jobId;
  const VisualSearchResultScreen({super.key, required this.jobId});

  @override
  State<VisualSearchResultScreen> createState() => _VisualSearchResultScreenState();
}

class _VisualSearchResultScreenState extends State<VisualSearchResultScreen> {
  final ApiService _api = ApiService();
  Map<String, dynamic>? _job;
  String? _error;
  Timer? _poller;
  Uint8List? _outputBytes;
  bool _loadingOutput = false;

  @override
  void initState() {
    super.initState();
    _fetch();
    // Poll every 2s while still in a non-terminal state.
    _poller = Timer.periodic(const Duration(seconds: 2), (_) {
      final status = _job?['status'];
      if (status == 'completed' || status == 'failed') return;
      _fetch();
    });
  }

  @override
  void dispose() {
    _poller?.cancel();
    super.dispose();
  }

  Future<void> _fetch() async {
    try {
      final job = await _api.getGroundingDinoJob(widget.jobId);
      if (!mounted) return;
      setState(() {
        _job = job;
        _error = null;
      });
      // Once we have a completed image output, fetch the bytes for display.
      // Videos are handled differently (just show the file path + open).
      final isImage = job['input_type'] == 'image';
      if (job['status'] == 'completed' &&
          isImage &&
          _outputBytes == null &&
          !_loadingOutput) {
        _fetchOutputImage();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is ApiException ? 'HTTP ${e.statusCode}: ${e.message}' : e.toString();
      });
    }
  }

  Future<void> _fetchOutputImage() async {
    setState(() => _loadingOutput = true);
    try {
      final bytes = await _api.downloadGroundingDinoOutput(widget.jobId);
      if (!mounted) return;
      setState(() {
        if (bytes != null) _outputBytes = Uint8List.fromList(bytes);
        _loadingOutput = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingOutput = false);
    }
  }

  void _openFullscreen(Uint8List bytes) {
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _FullscreenImageView(bytes: bytes),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final job = _job;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Visual search'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(AppIcons.refresh),
            onPressed: _fetch,
          ),
        ],
      ),
      body: SafeArea(
        child: job == null
            ? Center(
                child: _error != null
                    ? Padding(
                        padding: const EdgeInsets.all(20),
                        child: Text(_error!, style: TextStyle(color: cs.error)),
                      )
                    : const CircularProgressIndicator(),
              )
            : _buildContent(job),
      ),
    );
  }

  Widget _buildContent(Map<String, dynamic> job) {
    final cs = Theme.of(context).colorScheme;
    final status = (job['status'] ?? '').toString();
    final prompt = (job['prompt'] ?? '').toString();
    final name = (job['name'] ?? '').toString();
    final inputType = (job['input_type'] ?? 'image').toString();
    final detections = (job['detections'] is List)
        ? List<Map<String, dynamic>>.from(
            (job['detections'] as List).whereType<Map>().map((m) => Map<String, dynamic>.from(m)))
        : <Map<String, dynamic>>[];
    final summary =
        (job['summary'] is Map) ? Map<String, dynamic>.from(job['summary']) : <String, dynamic>{};

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        // Header card
        EldercareCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    inputType == 'video' ? Icons.movie_creation_rounded : Icons.image_rounded,
                    color: AppTheme.brandTeal,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      name.isNotEmpty ? name : 'Visual search #${job['id']}',
                      style: GoogleFonts.outfit(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                        color: cs.onSurface,
                      ),
                    ),
                  ),
                  _StatusChip(status: status),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                prompt,
                style: GoogleFonts.dmSans(
                  fontSize: 13.5,
                  color: cs.onSurfaceVariant,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 14),

        // Status / progress card
        if (status == 'queued' || status == 'running')
          EldercareCard(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                const SizedBox(
                  width: 22, height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.5, color: AppTheme.brandTeal),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    status == 'queued'
                        ? 'Queued — waiting for the ML engine to pick this up…'
                        : 'Running detection…',
                    style: GoogleFonts.outfit(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: cs.onSurface,
                    ),
                  ),
                ),
              ],
            ),
          ),

        if (status == 'failed')
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cs.errorContainer,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.error_outline_rounded, color: cs.error),
                    const SizedBox(width: 8),
                    Text(
                      'Detection failed',
                      style: GoogleFonts.outfit(
                        fontWeight: FontWeight.w700,
                        color: cs.error,
                      ),
                    ),
                  ],
                ),
                if ((job['error'] ?? '').toString().isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    job['error'].toString(),
                    style: GoogleFonts.dmSans(fontSize: 13, color: cs.onErrorContainer),
                  ),
                ],
              ],
            ),
          ),

        if (status == 'completed') ...[
          // Annotated output — capped to ~320px tall so a tall photo doesn't
          // dominate the screen. Tap opens a fullscreen viewer with pinch-zoom.
          if (inputType == 'image')
            EldercareCard(
              padding: const EdgeInsets.all(8),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: _outputBytes != null
                    ? InkWell(
                        onTap: () => _openFullscreen(_outputBytes!),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 320),
                          child: Stack(
                            alignment: Alignment.bottomRight,
                            children: [
                              SizedBox(
                                width: double.infinity,
                                child: Image.memory(
                                  _outputBytes!,
                                  fit: BoxFit.contain,
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.all(8),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.55),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.zoom_out_map_rounded,
                                          size: 14, color: Colors.white),
                                      SizedBox(width: 4),
                                      Text('Tap to enlarge',
                                          style: TextStyle(
                                              fontSize: 11,
                                              color: Colors.white,
                                              fontWeight: FontWeight.w600)),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : Container(
                        height: 220,
                        alignment: Alignment.center,
                        child: const CircularProgressIndicator(),
                      ),
              ),
            )
          else
            EldercareCard(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.movie_filter_rounded, color: AppTheme.brandTeal),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Annotated video ready on the server. Open via the API output URL to view.',
                      style: GoogleFonts.dmSans(fontSize: 13, color: cs.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
            ),

          const SizedBox(height: 14),

          // Summary
          EldercareCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Summary',
                    style: GoogleFonts.outfit(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurfaceVariant,
                      letterSpacing: 0.4,
                    )),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _SummaryChip(
                      label: '${summary['total_detections'] ?? detections.length} detections',
                      icon: Icons.center_focus_strong_rounded,
                    ),
                    if (summary['sampled_frames'] is num)
                      _SummaryChip(
                        label: '${summary['sampled_frames']} frames sampled',
                        icon: Icons.movie_creation_outlined,
                      ),
                    if (job['processing_ms'] is num)
                      _SummaryChip(
                        label: '${(job['processing_ms'] as num).toStringAsFixed(0)} ms',
                        icon: Icons.timer_outlined,
                      ),
                  ],
                ),
                if (summary['counts'] is Map && (summary['counts'] as Map).isNotEmpty) ...[
                  const SizedBox(height: 12),
                  for (final entry in (summary['counts'] as Map).entries)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        children: [
                          Container(
                            width: 8, height: 8,
                            decoration: BoxDecoration(
                              color: AppTheme.brandTeal,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              entry.key.toString(),
                              style: GoogleFonts.dmSans(fontSize: 13.5),
                            ),
                          ),
                          Text(
                            '${entry.value}',
                            style: GoogleFonts.outfit(
                              fontWeight: FontWeight.w700,
                              fontSize: 13.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 14),

          // Detections list (cap at 50 to avoid jank on long videos).
          if (detections.isNotEmpty)
            EldercareCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Detections',
                      style: GoogleFonts.outfit(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: cs.onSurfaceVariant,
                        letterSpacing: 0.4,
                      )),
                  const SizedBox(height: 10),
                  for (final det in detections.take(50))
                    _DetectionRow(det: det),
                  if (detections.length > 50) ...[
                    const SizedBox(height: 6),
                    Text(
                      '+ ${detections.length - 50} more',
                      style: GoogleFonts.dmSans(
                        fontSize: 12,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String status;
  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = switch (status) {
      'completed' => AppTheme.brandSage,
      'failed' => cs.error,
      'running' => AppTheme.brandTeal,
      _ => cs.outline,
    };
    final label = switch (status) {
      'completed' => 'Done',
      'failed' => 'Failed',
      'running' => 'Running',
      'queued' => 'Queued',
      _ => status,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: GoogleFonts.outfit(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: color,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

class _SummaryChip extends StatelessWidget {
  final String label;
  final IconData icon;
  const _SummaryChip({required this.label, required this.icon});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppTheme.brandTeal),
          const SizedBox(width: 6),
          Text(
            label,
            style: GoogleFonts.dmSans(fontSize: 12, color: cs.onSurface),
          ),
        ],
      ),
    );
  }
}

class _DetectionRow extends StatelessWidget {
  final Map<String, dynamic> det;
  const _DetectionRow({required this.det});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final label = (det['label'] ?? '').toString();
    final conf = (det['confidence'] is num) ? (det['confidence'] as num).toDouble() : 0.0;
    final box = (det['box'] is List) ? det['box'] as List : const [];
    final boxStr = box.length == 4
        ? '[${box[0]}, ${box[1]} → ${box[2]}, ${box[3]}]'
        : '';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: GoogleFonts.outfit(fontWeight: FontWeight.w700, fontSize: 13.5),
                ),
                if (boxStr.isNotEmpty)
                  Text(
                    boxStr,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          Text(
            '${(conf * 100).toStringAsFixed(0)}%',
            style: GoogleFonts.outfit(
              fontWeight: FontWeight.w700,
              fontSize: 13,
              color: AppTheme.brandTeal,
            ),
          ),
        ],
      ),
    );
  }
}

class _FullscreenImageView extends StatelessWidget {
  final Uint8List bytes;
  const _FullscreenImageView({required this.bytes});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Detection result'),
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 1,
          maxScale: 6,
          child: Image.memory(bytes, fit: BoxFit.contain),
        ),
      ),
    );
  }
}
