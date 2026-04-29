import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../services/ws_service.dart';

/// Live Feed Screen
/// Shows real-time video feed with ML results overlay
class LiveFeedScreen extends StatefulWidget {
  const LiveFeedScreen({super.key});

  @override
  State<LiveFeedScreen> createState() => _LiveFeedScreenState();
}

class _LiveFeedScreenState extends State<LiveFeedScreen> {
  final WsService _ws = WsService();
  Uint8List? _currentFrame;
  Map<String, dynamic>? _currentResults;
  double _totalProcessingTime = 0;
  bool _showOverlay = true;

  // Stream subscriptions for proper cleanup
  StreamSubscription<Map<String, dynamic>>? _feedSubscription;
  StreamSubscription<Map<String, dynamic>>? _resultsSubscription;

  @override
  void initState() {
    super.initState();
    _ws.connectFeed();
    _ws.connectResults();

    _feedSubscription = _ws.feedStream.listen((data) {
      if (mounted && data['image'] != null) {
        setState(() {
          _currentFrame = base64Decode(data['image'] as String);
        });
      }
    });

    _resultsSubscription = _ws.resultsStream.listen((data) {
      if (mounted) {
        setState(() {
          _currentResults = data;
          _totalProcessingTime = (data['total_processing_time_ms'] ?? 0).toDouble();
        });
      }
    });
  }

  @override
  void dispose() {
    // Cancel stream subscriptions to prevent memory leaks
    _feedSubscription?.cancel();
    _resultsSubscription?.cancel();
    _ws.disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;

    return Scaffold(
      body: Column(
        children: [
          // Header toolbar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.videocam_rounded,
                        color: colorScheme.onPrimaryContainer,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Live',
                      style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ],
                );

                final controlsRow = Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '${_totalProcessingTime.toStringAsFixed(1)} ms',
                        style: TextStyle(
                          color: colorScheme.onPrimaryContainer,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: Icon(
                        _showOverlay
                            ? Icons.layers_rounded
                            : Icons.layers_clear_rounded,
                      ),
                      onPressed: () {
                        setState(() => _showOverlay = !_showOverlay);
                      },
                      tooltip: 'Toggle results overlay',
                    ),
                  ],
                );

                if (compact) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      titleRow,
                      const SizedBox(height: 6),
                      controlsRow,
                    ],
                  );
                }

                return Row(
                  children: [
                    titleRow,
                    const Spacer(),
                    controlsRow,
                  ],
                );
              },
            ),
          ),

          // Video feed area
          Expanded(
            flex: 3,
            child: Container(
              color: colorScheme.inverseSurface,
              child: _currentFrame != null
                  ? Center(
                      child: Image.memory(
                        _currentFrame!,
                        fit: BoxFit.contain,
                        gaplessPlayback: true,
                      ),
                    )
                  : Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.videocam_off_rounded,
                            size: 64,
                            color: colorScheme.onInverseSurface.withValues(alpha: 0.3),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No feed available',
                            style: TextStyle(
                              color: colorScheme.onInverseSurface.withValues(alpha: 0.5),
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Start the pipeline from Settings to see live video',
                            style: TextStyle(
                              color: colorScheme.onInverseSurface.withValues(alpha: 0.3),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
          ),

          // Results panel
          if (_showOverlay && _currentResults != null)
            Expanded(
              flex: 1,
              child: _buildResultsPanel(colorScheme),
            ),
        ],
      ),
    );
  }

  Widget _buildResultsPanel(ColorScheme colorScheme) {
    final results = _currentResults?['results'] as Map<String, dynamic>? ?? {};
    final timing = _currentResults?['timing'] as Map<String, dynamic>? ?? {};
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(top: BorderSide(color: colorScheme.outlineVariant)),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.analytics_rounded,
                    color: colorScheme.onPrimaryContainer,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  'Real-Time Analysis',
                  style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'FRAME #${_currentResults?['frame_id'] ?? '-'}',
                    style: TextStyle(
                      color: colorScheme.onPrimaryContainer,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...results.entries.map((entry) {
              final modelTime = timing[entry.key]?.toString() ?? '-';
              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                  ),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  leading: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: colorScheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      _getModelIcon(entry.key),
                      color: colorScheme.primary,
                    ),
                  ),
                  title: Text(
                    entry.key.toUpperCase(),
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      _formatResult(entry.value),
                      style: TextStyle(
                        color: colorScheme.onSurface.withValues(alpha: 0.7),
                        height: 1.3,
                      ),
                    ),
                  ),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${modelTime}ms',
                        style: TextStyle(
                          color: colorScheme.primary,
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                      ),
                      Text(
                        'Latency',
                        style: TextStyle(
                          color: colorScheme.onSurface.withValues(alpha: 0.5),
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  IconData _getModelIcon(String modelName) {
    switch (modelName) {
      case 'pose':
        return Icons.accessibility_new_rounded;
      case 'yolo':
        return Icons.crop_free_rounded;
      case 'custom_model_1':
        return Icons.psychology_rounded;
      case 'custom_model_2':
        return Icons.psychology_alt_rounded;
      default:
        return Icons.model_training_rounded;
    }
  }

  String _formatResult(dynamic result) {
    if (result is Map) {
      return result.entries
          .take(3)
          .map((e) => '${e.key}: ${e.value}')
          .join(', ');
    }
    if (result is List) {
      return '${result.length} detections';
    }
    return result.toString();
  }
}
