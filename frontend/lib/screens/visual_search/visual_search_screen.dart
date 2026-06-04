import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/api_service.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_theme.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/eldercare_card.dart';
import '../../widgets/section_header.dart';
import 'new_visual_search_screen.dart';
import 'visual_search_result_screen.dart';

/// "Visual Search" — landing tab for GroundingDINO open-set object detection.
///
/// Shows a list of the user's past jobs and a CTA to start a new search.
/// Designed to look right on both phone (full-bleed list) and web (same
/// layout, naturally wider).
class VisualSearchScreen extends StatefulWidget {
  const VisualSearchScreen({super.key});

  @override
  State<VisualSearchScreen> createState() => _VisualSearchScreenState();
}

class _VisualSearchScreenState extends State<VisualSearchScreen> {
  final ApiService _api = ApiService();
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _jobs = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final resp = await _api.listGroundingDinoJobs(limit: 100);
      final items = (resp['items'] as List? ?? const [])
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m))
          .toList();
      if (!mounted) return;
      setState(() {
        _jobs = items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is ApiException ? 'HTTP ${e.statusCode}: ${e.message}' : e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _startNew() async {
    HapticFeedback.lightImpact();
    final created = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(builder: (_) => const NewVisualSearchScreen()),
    );
    if (created != null) {
      // Jump straight into the result screen so the user sees progress;
      // refresh the list on return.
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => VisualSearchResultScreen(jobId: (created['id'] as num).toInt()),
        ),
      );
    }
    if (mounted) _load();
  }

  Future<void> _openJob(Map<String, dynamic> job) async {
    HapticFeedback.selectionClick();
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VisualSearchResultScreen(jobId: (job['id'] as num).toInt()),
      ),
    );
    if (mounted) _load();
  }

  Future<void> _deleteJob(Map<String, dynamic> job) async {
    HapticFeedback.mediumImpact();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete search?'),
        content: Text(
            'This will remove the job and its annotated output. The original upload is also deleted.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton.tonal(
            style: FilledButton.styleFrom(foregroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      await _api.deleteGroundingDinoJob((job['id'] as num).toInt());
      if (!mounted) return;
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Delete failed: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _startNew,
        backgroundColor: AppTheme.brandTeal,
        foregroundColor: Colors.white,
        icon: const Icon(AppIcons.visualSearch),
        label: const Text('New search'),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: _buildBody(),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading && _jobs.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null && _jobs.isEmpty) {
      return ListView(
        children: [
          const SizedBox(height: 80),
          EmptyState(
            icon: Icons.cloud_off_rounded,
            title: 'Could not load searches',
            subtitle: _error,
            actionLabel: 'Try again',
            actionIcon: AppIcons.refresh,
            onAction: _load,
          ),
        ],
      );
    }

    if (_jobs.isEmpty) {
      return ListView(
        children: [
          const SizedBox(height: 80),
          EmptyState(
            icon: AppIcons.visualSearch,
            title: 'No visual searches yet',
            subtitle:
                'Upload an image or short video and describe what to look for in plain English — '
                'e.g. "person . wheelchair . walker ." — and the system will draw boxes around what it finds.',
            actionLabel: 'Start a search',
            actionIcon: AppIcons.visualSearch,
            onAction: _startNew,
          ),
        ],
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 96),
      children: [
        const SectionHeader(
          title: 'Visual searches',
          subtitle: 'Open-set object detection on your images and videos.',
          icon: AppIcons.visualSearch,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            children: [
              for (final job in _jobs)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _JobTile(
                    job: job,
                    onTap: () => _openJob(job),
                    onDelete: () => _deleteJob(job),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _JobTile extends StatelessWidget {
  final Map<String, dynamic> job;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _JobTile({required this.job, required this.onTap, required this.onDelete});

  Color _statusColor(BuildContext ctx, String status) {
    switch (status) {
      case 'completed':
        return AppTheme.brandSage;
      case 'failed':
        return Theme.of(ctx).colorScheme.error;
      case 'running':
        return AppTheme.brandTeal;
      default:
        return Theme.of(ctx).colorScheme.outline;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'completed':
        return 'Done';
      case 'failed':
        return 'Failed';
      case 'running':
        return 'Running';
      case 'queued':
        return 'Queued';
      default:
        return status;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final status = (job['status'] ?? '').toString();
    final inputType = (job['input_type'] ?? 'image').toString();
    final prompt = (job['prompt'] ?? '').toString();
    final name = (job['name'] ?? '').toString();
    final summary = (job['summary'] is Map) ? Map<String, dynamic>.from(job['summary']) : {};
    final total = summary['total_detections'];

    return EldercareCard(
      padding: const EdgeInsets.all(14),
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppTheme.brandTeal.withValues(alpha: 0.16),
                  AppTheme.brandSage.withValues(alpha: 0.10),
                ],
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              inputType == 'video'
                  ? Icons.movie_creation_rounded
                  : Icons.image_rounded,
              color: AppTheme.brandTeal,
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
                  name.isNotEmpty ? name : prompt,
                  style: GoogleFonts.outfit(
                    fontWeight: FontWeight.w700,
                    fontSize: 14.5,
                    color: cs.onSurface,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  prompt,
                  style: GoogleFonts.dmSans(
                    fontSize: 12,
                    color: cs.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: _statusColor(context, status).withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        _statusLabel(status),
                        style: GoogleFonts.outfit(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: _statusColor(context, status),
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                    if (total is num) ...[
                      const SizedBox(width: 8),
                      Text(
                        '$total detections',
                        style: GoogleFonts.dmSans(
                          fontSize: 11.5,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Delete',
            icon: const Icon(AppIcons.delete, size: 20),
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}
