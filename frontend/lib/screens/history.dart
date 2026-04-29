import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../config/app_config.dart';

class _SeekIntent extends Intent {
  const _SeekIntent(this.seconds);
  final double seconds;
}

class _TogglePlayIntent extends Intent {
  const _TogglePlayIntent();
}

/// History Screen
/// Shows past sessions and their results
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final ApiService _api = ApiService();
  List<dynamic> _sessions = [];
  List<dynamic> _recordings = [];
  bool _isLoading = true;
  int _selectedView = 0;

  @override
  void initState() {
    super.initState();
    _fetchSessions();
  }

  @override
  void dispose() {
    _api.dispose();
    super.dispose();
  }

  Future<void> _fetchSessions() async {
    try {
      final sessions = await _api.getSessions();
      final recordings = await _api.getRecordings();
      if (mounted) {
        setState(() {
          _sessions = sessions;
          _recordings = recordings;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final child = _selectedView == 0
        ? _buildSessionsView(context, theme)
        : _buildRecordingsView(context, theme);

    return Scaffold(
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: colorScheme.primary))
          : RefreshIndicator(
              color: colorScheme.primary,
              backgroundColor: colorScheme.surface,
              onRefresh: _fetchSessions,
              child: child,
            ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(bottom: BorderSide(color: colorScheme.outlineVariant)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 640;
          final titleRow = Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  Icons.insights_rounded,
                  color: colorScheme.onPrimaryContainer,
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'Insights',
                style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
            ],
          );

          final segmented = _HistoryHeader(
            selectedIndex: _selectedView,
            sessionsCount: _sessions.length,
            recordingsCount: _recordings.length,
            onChanged: (value) => setState(() => _selectedView = value),
          );

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                titleRow,
                const SizedBox(height: 10),
                segmented,
              ],
            );
          }

          return Row(
            children: [
              titleRow,
              const Spacer(),
              segmented,
            ],
          );
        },
      ),
    );
  }

  Widget _buildSessionsView(BuildContext context, ThemeData theme) {
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;

    return Column(
      children: [
        _buildHeader(theme),
        Expanded(
          child: _sessions.isEmpty
              ? ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
                  children: [
                    SizedBox(
                      height: MediaQuery.of(context).size.height * 0.6,
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.history_rounded,
                              size: 64,
                              color: colorScheme.onSurface.withValues(alpha: 0.2),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No sessions yet',
                              style: textTheme.titleMedium?.copyWith(
                                color: colorScheme.onSurface.withValues(alpha: 0.6),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Start the pipeline to create a session',
                              style: textTheme.bodyMedium?.copyWith(
                                color: colorScheme.onSurface.withValues(alpha: 0.4),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                )
              : ListView.builder(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  itemCount: _sessions.length,
                  itemBuilder: (context, index) {
                    final session = _sessions[index] as Map<String, dynamic>;
                    return _SessionCard(
                      session: session,
                      colorScheme: theme.colorScheme,
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildRecordingsView(BuildContext context, ThemeData theme) {
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;

    return Column(
      children: [
        _buildHeader(theme),
        Expanded(
          child: _recordings.isEmpty
              ? ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
                  children: [
                    SizedBox(
                      height: MediaQuery.of(context).size.height * 0.6,
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.video_library_rounded,
                              size: 64,
                              color: colorScheme.onSurface.withValues(alpha: 0.2),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No recordings yet',
                              style: textTheme.titleMedium?.copyWith(
                                color: colorScheme.onSurface.withValues(alpha: 0.6),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Start and stop a recording from Multi-Cam controls',
                              style: textTheme.bodyMedium?.copyWith(
                                color: colorScheme.onSurface.withValues(alpha: 0.4),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                )
              : ListView.builder(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  itemCount: _recordings.length,
                  itemBuilder: (context, index) {
                    final recording = _recordings[index] as Map<String, dynamic>;
                    return _RecordingCard(
                      recording: recording,
                      colorScheme: theme.colorScheme,
                      onPlay: () {
                        showDialog<void>(
                          context: context,
                          builder: (_) => _RecordingPlayerDialog(recording: recording),
                        );
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _HistoryHeader extends StatelessWidget {
  final int selectedIndex;
  final int sessionsCount;
  final int recordingsCount;
  final ValueChanged<int> onChanged;

  const _HistoryHeader({
    required this.selectedIndex,
    required this.sessionsCount,
    required this.recordingsCount,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SegmentedButton<int>(
        segments: [
          ButtonSegment<int>(value: 0, label: Text('Sessions ($sessionsCount)'), icon: const Icon(Icons.history_rounded)),
          ButtonSegment<int>(value: 1, label: Text('Recordings ($recordingsCount)'), icon: const Icon(Icons.video_library_rounded)),
        ],
        selected: {selectedIndex},
        onSelectionChanged: (selection) => onChanged(selection.first),
        showSelectedIcon: false,
      ),
    );
  }
}

class _SessionCard extends StatefulWidget {
  final Map<String, dynamic> session;
  final ColorScheme colorScheme;

  const _SessionCard({
    required this.session,
    required this.colorScheme,
  });

  @override
  State<_SessionCard> createState() => _SessionCardState();
}

class _SessionCardState extends State<_SessionCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final statusColors = theme.extension<AppStatusColors>() ?? AppStatusColors.fallback;
    final status = widget.session['status']?.toString() ?? 'unknown';
    final isDark = theme.brightness == Brightness.dark;

    final statusColor = status == 'running'
        ? colorScheme.primary
        : status == 'completed'
            ? statusColors.success
            : statusColors.warning;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 16),
        transform: Matrix4.identity()..translateByDouble(_isHovered ? 5.0 : 0.0, 0.0, 0.0, 1.0),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest.withValues(alpha: isDark ? 0.3 : 0.5),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: _isHovered 
                ? statusColor.withValues(alpha: 0.5) 
                : colorScheme.outlineVariant.withValues(alpha: 0.5),
            width: 1.5,
          ),
          boxShadow: [
            if (_isHovered)
              BoxShadow(
                color: statusColor.withValues(alpha: 0.15),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
          ],
        ),
        child: ListTile(
          contentPadding: const EdgeInsets.all(20),
          leading: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              status == 'running'
                  ? Icons.play_circle_rounded
                  : Icons.check_circle_rounded,
              color: statusColor,
              size: 28,
            ),
          ),
          title: Text(
            widget.session['name']?.toString() ?? 'Session Analytics',
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              children: [
                Icon(Icons.videocam_rounded, size: 14, color: colorScheme.onSurface.withValues(alpha: 0.5)),
                const SizedBox(width: 4),
                Text(
                  widget.session['camera_source'] ?? 'Unknown Source',
                  style: TextStyle(color: colorScheme.onSurface.withValues(alpha: 0.7), fontWeight: FontWeight.w500),
                ),
                const SizedBox(width: 16),
                Icon(Icons.access_time_rounded, size: 14, color: colorScheme.onSurface.withValues(alpha: 0.5)),
                const SizedBox(width: 4),
                Text(
                  widget.session['started_at']?.toString().substring(0, 19) ?? 'Recently',
                  style: TextStyle(color: colorScheme.onSurface.withValues(alpha: 0.7), fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              PopupMenuButton<String>(
                icon: const Icon(Icons.download_rounded),
                tooltip: 'Export session',
                onSelected: (value) async {
                  final sessionId = widget.session['id'];
                  if (sessionId == null) return;
                  if (value == 'json') {
                    await launchUrl(
                      Uri.parse('${AppConfig.apiBaseUrl}/api/results/session/$sessionId/export/json'),
                      webOnlyWindowName: '_blank',
                    );
                  } else if (value == 'csv') {
                    await launchUrl(
                      Uri.parse('${AppConfig.apiBaseUrl}/api/results/session/$sessionId/export/csv'),
                      webOnlyWindowName: '_blank',
                    );
                  }
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'json', child: Text('Export Results JSON')),
                  PopupMenuItem(value: 'csv', child: Text('Export Results CSV')),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                ),
                child: Text(
                  status.toUpperCase(),
                  style: TextStyle(
                    color: statusColor,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecordingCard extends StatelessWidget {
  final Map<String, dynamic> recording;
  final ColorScheme colorScheme;
  final VoidCallback onPlay;

  const _RecordingCard({
    required this.recording,
    required this.colorScheme,
    required this.onPlay,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusColors = theme.extension<AppStatusColors>() ?? AppStatusColors.fallback;
    final status = (recording['status'] ?? 'unknown').toString();
    final isCompleted = status.toLowerCase() == 'completed';
    final stateColor = isCompleted ? statusColors.success : statusColors.warning;
    final fileSizeBytes = (recording['file_size_bytes'] as num?)?.toDouble() ?? 0;
    final fileSizeMb = fileSizeBytes / (1024 * 1024);
    final duration = (recording['duration_seconds'] as num?)?.toDouble() ?? 0;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        leading: CircleAvatar(
          backgroundColor: stateColor.withValues(alpha: 0.15),
          child: Icon(
            isCompleted ? Icons.play_circle_fill_rounded : Icons.radio_button_checked_rounded,
            color: stateColor,
          ),
        ),
        title: Text(recording['name']?.toString() ?? 'Recording #${recording['id']}'),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            '${duration.toStringAsFixed(1)}s • ${fileSizeMb > 0 ? '${fileSizeMb.toStringAsFixed(2)} MB' : 'size pending'} • ${recording['codec'] ?? 'codec pending'}',
            style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65)),
          ),
        ),
        trailing: FilledButton.icon(
          onPressed: isCompleted
              ? () {
                  showModalBottomSheet<void>(
                    context: context,
                    showDragHandle: true,
                    builder: (_) => SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Wrap(
                          children: [
                            ListTile(
                              leading: const Icon(Icons.play_circle_fill_rounded),
                              title: const Text('Play'),
                              onTap: () {
                                Navigator.of(context).pop();
                                onPlay();
                              },
                            ),
                            ListTile(
                              leading: const Icon(Icons.download_rounded),
                              title: const Text('Download Video'),
                              onTap: () async {
                                Navigator.of(context).pop();
                                await _openExternalUrl(
                                  Uri.parse('${AppConfig.apiBaseUrl}/api/recordings/${recording['id']}/download'),
                                );
                              },
                            ),
                            ListTile(
                              leading: const Icon(Icons.data_object_rounded),
                              title: const Text('Export JSON Metadata'),
                              onTap: () async {
                                Navigator.of(context).pop();
                                await _openExternalUrl(
                                  Uri.parse('${AppConfig.apiBaseUrl}/api/recordings/${recording['id']}/export/json'),
                                );
                              },
                            ),
                            ListTile(
                              leading: const Icon(Icons.table_chart_rounded),
                              title: const Text('Export CSV Metadata'),
                              onTap: () async {
                                Navigator.of(context).pop();
                                await _openExternalUrl(
                                  Uri.parse('${AppConfig.apiBaseUrl}/api/recordings/${recording['id']}/export/csv'),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }
              : null,
          icon: const Icon(Icons.more_horiz_rounded),
          label: const Text('Actions'),
        ),
      ),
    );
  }

  Future<void> _openExternalUrl(Uri uri) async {
    await launchUrl(uri, webOnlyWindowName: '_blank');
  }
}

class _RecordingPlayerDialog extends StatefulWidget {
  final Map<String, dynamic> recording;

  const _RecordingPlayerDialog({required this.recording});

  @override
  State<_RecordingPlayerDialog> createState() => _RecordingPlayerDialogState();
}

class _RecordingPlayerDialogState extends State<_RecordingPlayerDialog> {
  VideoPlayerController? _controller;
  double _playbackSpeed = 1.0;
  bool _isReady = false;
  String? _loadError;
  late final FocusNode _focusNode;

  String get _streamUrl => '${AppConfig.apiBaseUrl}/api/recordings/${widget.recording['id']}/stream';

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    try {
      final controller = VideoPlayerController.networkUrl(Uri.parse(_streamUrl));
      await controller.initialize();
      controller.setPlaybackSpeed(_playbackSpeed);
      setState(() {
        _controller = controller;
        _isReady = true;
      });
    } catch (e) {
      setState(() => _loadError = e.toString());
    }
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _controller?.dispose();
    super.dispose();
  }

  String _fmt(Duration d) {
    final totalSeconds = d.inSeconds;
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  void _seekBySeconds(double deltaSeconds) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    final current = controller.value.position;
    final target = current + Duration(milliseconds: (deltaSeconds * 1000).round());
    final bounded = target < Duration.zero
        ? Duration.zero
        : (target > controller.value.duration ? controller.value.duration : target);
    controller.seekTo(bounded);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;

    return Dialog(
      child: FocusableActionDetector(
        autofocus: true,
        focusNode: _focusNode,
        shortcuts: const <ShortcutActivator, Intent>{
          SingleActivator(LogicalKeyboardKey.space): _TogglePlayIntent(),
          SingleActivator(LogicalKeyboardKey.arrowLeft): _SeekIntent(-10),
          SingleActivator(LogicalKeyboardKey.arrowRight): _SeekIntent(10),
          SingleActivator(LogicalKeyboardKey.keyJ): _SeekIntent(-10),
          SingleActivator(LogicalKeyboardKey.keyL): _SeekIntent(10),
        },
        actions: <Type, Action<Intent>>{
          _TogglePlayIntent: CallbackAction<_TogglePlayIntent>(
            onInvoke: (intent) {
              final c = _controller;
              if (c == null || !c.value.isInitialized) return null;
              if (c.value.isPlaying) {
                c.pause();
              } else {
                c.play();
              }
              setState(() {});
              return null;
            },
          ),
          _SeekIntent: CallbackAction<_SeekIntent>(
            onInvoke: (intent) {
              _seekBySeconds(intent.seconds);
              return null;
            },
          ),
        },
        child: SizedBox(
          width: 880,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.recording['name']?.toString() ?? 'Recording Playback',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                if (_loadError != null)
                  Text('Failed to load recording: $_loadError')
                else if (!_isReady || controller == null)
                  const SizedBox(height: 280, child: Center(child: CircularProgressIndicator()))
                else
                  ValueListenableBuilder<VideoPlayerValue>(
                    valueListenable: controller,
                    builder: (context, value, _) {
                      final current = value.position;
                      final total = value.duration;
                      return Column(
                        children: [
                          AspectRatio(
                            aspectRatio: value.aspectRatio > 0 ? value.aspectRatio : 16 / 9,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: VideoPlayer(controller),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              IconButton(
                                tooltip: 'Back 10s (Left/J)',
                                onPressed: () => _seekBySeconds(-10),
                                icon: const Icon(Icons.replay_10_rounded),
                              ),
                              IconButton(
                                tooltip: 'Play/Pause (Space)',
                                onPressed: () {
                                  if (value.isPlaying) {
                                    controller.pause();
                                  } else {
                                    controller.play();
                                  }
                                  setState(() {});
                                },
                                icon: Icon(value.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded),
                              ),
                              IconButton(
                                tooltip: 'Forward 10s (Right/L)',
                                onPressed: () => _seekBySeconds(10),
                                icon: const Icon(Icons.forward_10_rounded),
                              ),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    VideoProgressIndicator(
                                      controller,
                                      allowScrubbing: true,
                                      padding: const EdgeInsets.symmetric(horizontal: 8),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(_fmt(current), style: Theme.of(context).textTheme.bodySmall),
                                          Text(_fmt(total), style: Theme.of(context).textTheme.bodySmall),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              DropdownButton<double>(
                                value: _playbackSpeed,
                                onChanged: (value) {
                                  if (value == null) return;
                                  setState(() => _playbackSpeed = value);
                                  controller.setPlaybackSpeed(value);
                                },
                                items: const [0.5, 1.0, 1.5, 2.0]
                                    .map((s) => DropdownMenuItem(value: s, child: Text('${s}x')))
                                    .toList(),
                              ),
                            ],
                          ),
                        ],
                      );
                    },
                  ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Close'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

