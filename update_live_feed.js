const fs = require('fs');
let code = fs.readFileSync('d:/FYP/project/frontend/lib/screens/live_feed.dart', 'utf8');

// Add imports
if (!code.includes('app_theme.dart')) {
  code = code.replace(
    import '../services/ws_service.dart';,
    import '../services/ws_service.dart';\nimport '../theme/app_theme.dart';\nimport '../widgets/glass_card.dart';
  );
}

// Replace colorScheme and Scaffold
code = code.replace(
    Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(,
    Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: AppTheme.background,
);

let startIdx = code.indexOf('          // Header toolbar');
let endIdx = code.indexOf('          // Video feed area');
if (startIdx !== -1 && endIdx !== -1) {
  let oldHeader = code.substring(startIdx, endIdx);
  let newHeader =           // Header toolbar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            decoration: BoxDecoration(
              color: AppTheme.surfaceHighlight,
              border: Border(bottom: BorderSide(color: AppTheme.primary.withOpacity(0.1))),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 640;
                final titleRow = Row(
                  children: [
                    Icon(Icons.videocam_rounded, color: AppTheme.primary, size: 28),
                    const SizedBox(width: 12),
                    Text(
                      'Live Feed',
                      style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textPrimary,
                          ),
                    ),
                  ],
                );

                final controlsRow = Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppTheme.primary.withOpacity(0.3)),
                      ),
                      child: Text(
                        '\\x24{_totalProcessingTime.toStringAsFixed(1)} ms',
                        style: const TextStyle(
                          color: AppTheme.primary,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    IconButton(
                      icon: Icon(
                        _showOverlay
                            ? Icons.layers_rounded
                            : Icons.layers_clear_rounded,
                        color: _showOverlay ? AppTheme.primary : AppTheme.textSecondary,
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
                      const SizedBox(height: 12),
                      controlsRow,
                    ],
                  );
                }

                return Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    titleRow,
                    controlsRow,
                  ],
                );
              },
            ),
          ),

;
  code = code.replace(oldHeader, newHeader);
}

// Replace _buildResultsPanel definition
let resultsPanelStart = code.indexOf('  Widget _buildResultsPanel(');
if (resultsPanelStart !== -1) {
  let oldResultsPanel = code.substring(resultsPanelStart);
  let newResultsPanel =   Widget _buildResultsPanel(ThemeData theme) {
    final results = _currentResults?['results'] as Map<String, dynamic>? ?? {};
    final timing = _currentResults?['timing'] as Map<String, dynamic>? ?? {};

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppTheme.surfaceHighlight,
        border: Border(top: BorderSide(color: AppTheme.primary.withOpacity(0.1))),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.analytics_rounded, color: AppTheme.primary),
                const SizedBox(width: 12),
                Text(
                  'Real-Time Analysis',
                  style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary,
                      ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.primary.withOpacity(0.3)),
                  ),
                  child: Text(
                    'FRAME #\\x24{_currentResults?['frame_id'] ?? '-'}',
                    style: const TextStyle(
                      color: AppTheme.primary,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            if (results.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: Text(
                    'Waiting for detection results...',
                    style: TextStyle(color: AppTheme.textSecondary),
                  ),
                ),
              )
            else
              ...results.entries.map((entry) {
                final modelTime = timing[entry.key]?.toString() ?? '-';
                return Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: GlassCard(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppTheme.primary.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            _getModelIcon(entry.key),
                            color: AppTheme.primary,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                entry.key.toUpperCase(),
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold, 
                                  fontSize: 16,
                                  color: AppTheme.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                _formatResult(entry.value),
                                style: const TextStyle(
                                  color: AppTheme.textSecondary,
                                  height: 1.4,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              '\\x24{modelTime}ms',
                              style: const TextStyle(
                                color: AppTheme.primary,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            const Text(
                              'Latency',
                              style: TextStyle(
                                color: AppTheme.textSecondary,
                                fontSize: 11,
                              ),
                            ),
                          ],
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
          .take(4)
          .map((e) => '\\x24{e.key}: \\x24{e.value}')
          .join(', ');
    }
    if (result is List) {
      return '\\x24{result.length} detections';
    }
    return result.toString();
  }
}
;
  code = code.replace(oldResultsPanel, newResultsPanel);
}

// Call to _buildResultsPanel: colorScheme => theme
code = code.replace('_buildResultsPanel(colorScheme)', '_buildResultsPanel(theme)');

fs.writeFileSync('d:/FYP/project/frontend/lib/screens/live_feed.dart', code);
console.log('live_feed.dart replaced successfully!');
