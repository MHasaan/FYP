import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import '../services/storage_service.dart';
import 'package:http/http.dart' as http;
import '../theme/app_theme.dart';

/// Settings Screen
/// Camera configuration and pipeline control
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final ApiService _api = ApiService();
  final _cameraSourceController = TextEditingController();
  final _deviceTokenController = TextEditingController();
  final _deviceNameController = TextEditingController();
  final _userIdController = TextEditingController();
  final _testTitleController = TextEditingController(text: 'FYP Test Notification');
  final _testBodyController = TextEditingController(text: 'This is a test push notification from FYP backend.');
  final _webhookNameController = TextEditingController();
  final _webhookUrlController = TextEditingController();
  final _webhookSecretController = TextEditingController();
  final _webhookEventsController = TextEditingController(text: 'alert');
  final _scheduleNameController = TextEditingController();
  final _scheduleCronController = TextEditingController(text: '0 9 * * 1-5');
  final _scheduleDurationController = TextEditingController();
  final _scheduleModelsController = TextEditingController(text: 'yolo');
  final _roiNameController = TextEditingController();
  final _roiDescriptionController = TextEditingController();
  String _selectedSourceType = 'usb';
  String _selectedTokenPlatform = 'fcm';
  bool _isStarting = false;
  bool _isStopping = false;
  bool _isLoadingAlerts = false;
  bool _isLoadingDeviceTokens = false;
  bool _isSendingTestPush = false;
  bool _isLoadingWebhooks = false;
  bool _isLoadingSchedules = false;
  bool _isLoadingLogs = false;
  bool _isLoadingROIZones = false;
  bool _isSavingROIZone = false;
  List<Map<String, dynamic>> _alertRules = [];
  List<Map<String, dynamic>> _deviceTokens = [];
  List<Map<String, dynamic>> _webhooks = [];
  List<Map<String, dynamic>> _scheduledJobs = [];
  List<Map<String, dynamic>> _cameraConfigs = [];
  List<Map<String, dynamic>> _activityLogs = [];
  List<Map<String, dynamic>> _roiZones = [];
  Map<String, dynamic>? _logStatistics;
  String _selectedLogSeverity = '';
  int _logLimit = 30;
  int? _selectedScheduleCameraId;
  int? _selectedROICameraId;
  int? _editingROIZoneId;
  String _selectedROIColor = '#FF0000';
  final List<Offset> _roiDraftPoints = [];
  Map<String, dynamic>? _pipelineStatus;

  final List<Map<String, String>> _sourceTypes = [
    {'type': 'usb', 'label': 'USB Camera', 'hint': '0'},
    {'type': 'rtsp', 'label': 'IP Camera (RTSP)', 'hint': 'rtsp://192.168.1.100:554/stream'},
    {'type': 'http', 'label': 'IP Camera (HTTP)', 'hint': 'http://192.168.1.100:8080/video'},
    {'type': 'video_file', 'label': 'Video File', 'hint': '/videos/sample.mp4'},
  ];

  @override
  void initState() {
    super.initState();
    _fetchStatus();
    _loadAlertRules();
    _loadDeviceTokens();
    _loadWebhooks();
    _loadScheduledJobs();
    _loadCameraConfigs();
    _loadROIZones();
    _loadActivityLogs();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _cameraSourceController.text = context.read<StorageService>().lastCameraSource;
        // Auto-select type based on value
        final val = _cameraSourceController.text;
        if (val.startsWith('http')) {
          setState(() => _selectedSourceType = 'http');
        } else if (val.startsWith('rtsp')) {
          setState(() => _selectedSourceType = 'rtsp');
        } else if (val.startsWith('/')) {
          setState(() => _selectedSourceType = 'video_file');
        } else {
          setState(() => _selectedSourceType = 'usb');
        }
      }
    });
  }

  @override
  void dispose() {
    _cameraSourceController.dispose();
    _deviceTokenController.dispose();
    _deviceNameController.dispose();
    _userIdController.dispose();
    _testTitleController.dispose();
    _testBodyController.dispose();
    _webhookNameController.dispose();
    _webhookUrlController.dispose();
    _webhookSecretController.dispose();
    _webhookEventsController.dispose();
    _scheduleNameController.dispose();
    _scheduleCronController.dispose();
    _scheduleDurationController.dispose();
    _scheduleModelsController.dispose();
    _roiNameController.dispose();
    _roiDescriptionController.dispose();
    _api.dispose();
    super.dispose();
  }

  Future<void> _loadDeviceTokens() async {
    setState(() => _isLoadingDeviceTokens = true);
    try {
      final tokens = await _api.getDeviceTokens();
      if (!mounted) {
        return;
      }
      setState(() {
        _deviceTokens = tokens.whereType<Map<String, dynamic>>().toList();
      });
    } catch (_) {
      // Keep existing list if backend call fails.
    } finally {
      if (mounted) {
        setState(() => _isLoadingDeviceTokens = false);
      }
    }
  }

  String _maskToken(String token) {
    if (token.length <= 14) {
      return token;
    }
    return '${token.substring(0, 8)}...${token.substring(token.length - 6)}';
  }

  Future<void> _registerDeviceToken() async {
    final token = _deviceTokenController.text.trim();
    if (token.isEmpty) {
      return;
    }

    try {
      await _api.registerDeviceToken({
        'device_token': token,
        'platform': _selectedTokenPlatform,
        'device_name': _deviceNameController.text.trim().isEmpty ? null : _deviceNameController.text.trim(),
        'user_id': _userIdController.text.trim().isEmpty ? null : _userIdController.text.trim(),
      });

      _deviceTokenController.clear();
      _deviceNameController.clear();
      _userIdController.clear();
      await _loadDeviceTokens();

      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Device token registered'),
          backgroundColor: AppTheme.success,
        ),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to register token: $e'),
          backgroundColor: AppTheme.error,
        ),
      );
    }
  }

  Future<void> _toggleDeviceToken(Map<String, dynamic> token, bool enabled) async {
    final id = token['id'] as int?;
    if (id == null) {
      return;
    }
    try {
      await _api.updateDeviceToken(id, {'is_active': enabled});
      await _loadDeviceTokens();
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to update token: $e'),
          backgroundColor: AppTheme.error,
        ),
      );
    }
  }

  Future<void> _deleteDeviceToken(Map<String, dynamic> token) async {
    final id = token['id'] as int?;
    if (id == null) {
      return;
    }
    try {
      await _api.deleteDeviceToken(id);
      await _loadDeviceTokens();
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to delete token: $e'),
          backgroundColor: AppTheme.error,
        ),
      );
    }
  }

  Future<void> _sendTestPush() async {
    setState(() => _isSendingTestPush = true);
    try {
      final result = await _api.sendTestNotification({
        'title': _testTitleController.text.trim().isEmpty
            ? 'FYP Test Notification'
            : _testTitleController.text.trim(),
        'body': _testBodyController.text.trim().isEmpty
            ? 'This is a test push notification from FYP backend.'
            : _testBodyController.text.trim(),
        'platform': _selectedTokenPlatform,
      });

      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Test dispatch completed for ${result['sent_to'] ?? 0} device(s)'),
          backgroundColor: AppTheme.success,
        ),
      );
      await _loadDeviceTokens();
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to send test push: $e'),
          backgroundColor: AppTheme.error,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSendingTestPush = false);
      }
    }
  }

  Future<void> _loadWebhooks() async {
    setState(() => _isLoadingWebhooks = true);
    try {
      final webhooks = await _api.getWebhooks();
      if (!mounted) {
        return;
      }
      setState(() {
        _webhooks = webhooks.whereType<Map<String, dynamic>>().toList();
      });
    } catch (_) {
      // Keep existing list if backend call fails.
    } finally {
      if (mounted) {
        setState(() => _isLoadingWebhooks = false);
      }
    }
  }

  Future<void> _createWebhook() async {
    final name = _webhookNameController.text.trim();
    final url = _webhookUrlController.text.trim();
    if (name.isEmpty || url.isEmpty) {
      return;
    }

    final events = _webhookEventsController.text
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    try {
      await _api.createWebhook({
        'name': name,
        'url': url,
        'secret_key': _webhookSecretController.text.trim().isEmpty ? null : _webhookSecretController.text.trim(),
        'headers': <String, dynamic>{},
        'events': events,
        'retry_count': 3,
      });

      _webhookNameController.clear();
      _webhookUrlController.clear();
      _webhookSecretController.clear();
      _webhookEventsController.text = 'alert';

      await _loadWebhooks();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Webhook created'),
          backgroundColor: AppTheme.success,
        ),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to create webhook: $e'),
          backgroundColor: AppTheme.error,
        ),
      );
    }
  }

  Future<void> _toggleWebhook(Map<String, dynamic> webhook, bool enabled) async {
    final id = webhook['id'] as int?;
    if (id == null) {
      return;
    }
    try {
      await _api.updateWebhook(id, {'is_active': enabled});
      await _loadWebhooks();
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to update webhook: $e'),
          backgroundColor: AppTheme.error,
        ),
      );
    }
  }

  Future<void> _deleteWebhook(Map<String, dynamic> webhook) async {
    final id = webhook['id'] as int?;
    if (id == null) {
      return;
    }
    try {
      await _api.deleteWebhook(id);
      await _loadWebhooks();
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to delete webhook: $e'),
          backgroundColor: AppTheme.error,
        ),
      );
    }
  }

  Future<void> _testWebhook(Map<String, dynamic> webhook) async {
    final id = webhook['id'] as int?;
    if (id == null) {
      return;
    }
    try {
      final result = await _api.testWebhook(id);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Webhook test status: ${result['status_code'] ?? 'unknown'}'),
          backgroundColor: AppTheme.success,
        ),
      );
      await _loadWebhooks();
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Webhook test failed: $e'),
          backgroundColor: AppTheme.error,
        ),
      );
    }
  }

  Future<void> _loadCameraConfigs() async {
    try {
      final cameras = await _api.getCameraConfigs();
      if (!mounted) {
        return;
      }
      final parsed = cameras.whereType<Map<String, dynamic>>().toList();
      setState(() {
        _cameraConfigs = parsed;
        if (_selectedScheduleCameraId == null && parsed.isNotEmpty) {
          _selectedScheduleCameraId = parsed.first['id'] as int?;
        }
        if (_selectedROICameraId == null && parsed.isNotEmpty) {
          _selectedROICameraId = parsed.first['id'] as int?;
        }
      });
    } catch (_) {
      // best effort only
    }
  }

  Future<void> _loadScheduledJobs() async {
    setState(() => _isLoadingSchedules = true);
    try {
      final jobs = await _api.getScheduledJobs();
      if (!mounted) {
        return;
      }
      setState(() {
        _scheduledJobs = jobs.whereType<Map<String, dynamic>>().toList();
      });
    } catch (_) {
      // Keep existing list if backend call fails.
    } finally {
      if (mounted) {
        setState(() => _isLoadingSchedules = false);
      }
    }
  }

  Future<void> _createScheduledJob() async {
    final name = _scheduleNameController.text.trim();
    final cron = _scheduleCronController.text.trim();
    final cameraId = _selectedScheduleCameraId;
    if (name.isEmpty || cron.isEmpty || cameraId == null) {
      return;
    }

    final models = _scheduleModelsController.text
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    final duration = int.tryParse(_scheduleDurationController.text.trim());

    try {
      await _api.createScheduledJob({
        'name': name,
        'camera_config_id': cameraId,
        'enabled_models': models,
        'model_configs': <String, dynamic>{},
        'cron_expression': cron,
        'duration_minutes': duration,
      });
      _scheduleNameController.clear();
      _scheduleCronController.text = '0 9 * * 1-5';
      _scheduleDurationController.clear();
      _scheduleModelsController.text = 'yolo';
      await _loadScheduledJobs();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Scheduled job created'),
          backgroundColor: AppTheme.success,
        ),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to create schedule: $e'),
          backgroundColor: AppTheme.error,
        ),
      );
    }
  }

  Future<void> _toggleScheduledJob(Map<String, dynamic> job, bool enabled) async {
    final id = job['id'] as int?;
    if (id == null) {
      return;
    }
    try {
      await _api.updateScheduledJob(id, {'is_active': enabled});
      await _loadScheduledJobs();
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to update schedule: $e'),
          backgroundColor: AppTheme.error,
        ),
      );
    }
  }

  Future<void> _runScheduledJobNow(Map<String, dynamic> job) async {
    final id = job['id'] as int?;
    if (id == null) {
      return;
    }
    try {
      final result = await _api.runScheduledJobNow(id);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['message']?.toString() ?? 'Scheduled job triggered'),
          backgroundColor: AppTheme.success,
        ),
      );
      await _loadScheduledJobs();
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to run schedule: $e'),
          backgroundColor: AppTheme.error,
        ),
      );
    }
  }

  Future<void> _deleteScheduledJob(Map<String, dynamic> job) async {
    final id = job['id'] as int?;
    if (id == null) {
      return;
    }
    try {
      await _api.deleteScheduledJob(id);
      await _loadScheduledJobs();
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to delete schedule: $e'),
          backgroundColor: AppTheme.error,
        ),
      );
    }
  }

  Future<void> _loadROIZones() async {
    setState(() => _isLoadingROIZones = true);
    try {
      final zones = await _api.getROIZones(cameraConfigId: _selectedROICameraId);
      if (!mounted) {
        return;
      }
      setState(() {
        _roiZones = zones.whereType<Map<String, dynamic>>().toList();
      });
    } catch (_) {
      // Keep existing ROI list if backend call fails.
    } finally {
      if (mounted) {
        setState(() => _isLoadingROIZones = false);
      }
    }
  }

  void _clearROIDraft({bool clearText = false}) {
    setState(() {
      _editingROIZoneId = null;
      _roiDraftPoints.clear();
      _selectedROIColor = '#FF0000';
      if (clearText) {
        _roiNameController.clear();
        _roiDescriptionController.clear();
      }
    });
  }

  void _startEditROIZone(Map<String, dynamic> zone) {
    final coords = (zone['coordinates'] as List<dynamic>? ?? <dynamic>[])
        .whereType<List<dynamic>>()
        .where((p) => p.length >= 2)
        .map((p) {
          final dx = (p[0] as num?)?.toDouble() ?? 0.0;
          final dy = (p[1] as num?)?.toDouble() ?? 0.0;
          return Offset(dx.clamp(0.0, 1.0), dy.clamp(0.0, 1.0));
        }).toList();

    setState(() {
      _editingROIZoneId = zone['id'] as int?;
      _selectedROICameraId = zone['camera_config_id'] as int?;
      _roiNameController.text = zone['name']?.toString() ?? '';
      _roiDescriptionController.text = zone['description']?.toString() ?? '';
      _selectedROIColor = zone['color']?.toString() ?? '#FF0000';
      _roiDraftPoints
        ..clear()
        ..addAll(coords);
    });
  }

  Future<void> _saveROIZone() async {
    final cameraId = _selectedROICameraId;
    final zoneName = _roiNameController.text.trim();
    if (cameraId == null || zoneName.isEmpty || _roiDraftPoints.length < 3) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Select camera, enter name, and add at least 3 ROI points.'),
          backgroundColor: AppTheme.warning,
        ),
      );
      return;
    }

    setState(() => _isSavingROIZone = true);
    final isCreate = _editingROIZoneId == null;
    final payload = <String, dynamic>{
      'camera_config_id': cameraId,
      'name': zoneName,
      'description': _roiDescriptionController.text.trim().isEmpty
          ? null
          : _roiDescriptionController.text.trim(),
      'zone_type': 'polygon',
      'coordinates': _roiDraftPoints
          .map((p) => [
                double.parse(p.dx.toStringAsFixed(4)),
                double.parse(p.dy.toStringAsFixed(4)),
              ])
          .toList(),
      'color': _selectedROIColor,
      'trigger_on_enter': true,
      'trigger_on_exit': false,
      'trigger_on_stay': false,
      'stay_threshold_seconds': 5,
    };

    try {
      if (isCreate) {
        await _api.createROIZone(payload);
      } else {
        await _api.updateROIZone(_editingROIZoneId!, payload);
      }

      _clearROIDraft(clearText: true);
      await _loadROIZones();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isCreate ? 'ROI zone created' : 'ROI zone updated'),
          backgroundColor: AppTheme.success,
        ),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to save ROI zone: $e'),
          backgroundColor: AppTheme.error,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSavingROIZone = false);
      }
    }
  }

  Future<void> _deleteROIZone(Map<String, dynamic> zone) async {
    final zoneId = zone['id'] as int?;
    if (zoneId == null) {
      return;
    }
    try {
      await _api.deleteROIZone(zoneId);
      await _loadROIZones();
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to delete ROI zone: $e'),
          backgroundColor: AppTheme.error,
        ),
      );
    }
  }

  Future<void> _toggleROIZone(Map<String, dynamic> zone, bool enabled) async {
    final zoneId = zone['id'] as int?;
    if (zoneId == null) {
      return;
    }
    try {
      await _api.updateROIZone(zoneId, {'is_active': enabled});
      await _loadROIZones();
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to update ROI zone: $e'),
          backgroundColor: AppTheme.error,
        ),
      );
    }
  }

  void _addROIPoint(Offset normalizedPoint) {
    setState(() {
      _roiDraftPoints.add(
        Offset(
          normalizedPoint.dx.clamp(0.0, 1.0),
          normalizedPoint.dy.clamp(0.0, 1.0),
        ),
      );
    });
  }

  void _removeLastROIPoint() {
    if (_roiDraftPoints.isEmpty) {
      return;
    }
    setState(() {
      _roiDraftPoints.removeLast();
    });
  }

  Future<void> _loadActivityLogs() async {
    setState(() => _isLoadingLogs = true);
    try {
      final logsResponse = await _api.getActivityLogs(
        severity: _selectedLogSeverity.isEmpty ? null : _selectedLogSeverity,
        limit: _logLimit,
      );
      final stats = await _api.getLogStatistics(hours: 24);

      if (!mounted) {
        return;
      }

      final items = (logsResponse['items'] as List<dynamic>? ?? <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .toList();

      setState(() {
        _activityLogs = items;
        _logStatistics = stats;
      });
    } catch (_) {
      // Best effort rendering if API temporarily unavailable.
    } finally {
      if (mounted) {
        setState(() => _isLoadingLogs = false);
      }
    }
  }

  Future<Map<String, dynamic>?> _fetchStatus() async {
    try {
      final status = await _api.getPipelineStatus();
      if (mounted) {
        setState(() => _pipelineStatus = status);
      }
      return status;
    } catch (e) {
      // Backend may be offline
      return null;
    }
  }

  Future<void> _syncPipelineStatus({
    required bool expectedRunning,
    int retries = 6,
    Duration interval = const Duration(milliseconds: 700),
  }) async {
    for (var attempt = 0; attempt < retries; attempt++) {
      final status = await _fetchStatus();
      final isRunning = status?['is_running'] == true;
      if (isRunning == expectedRunning) {
        return;
      }
      if (attempt < retries - 1) {
        await Future.delayed(interval);
      }
    }
  }

  Future<void> _loadAlertRules() async {
    setState(() => _isLoadingAlerts = true);
    try {
      final rules = await _api.getAlertRules();
      if (!mounted) {
        return;
      }
      setState(() {
        _alertRules = rules.whereType<Map<String, dynamic>>().toList();
      });
    } catch (_) {
      // Keep existing list if backend call fails.
    } finally {
      if (mounted) {
        setState(() => _isLoadingAlerts = false);
      }
    }
  }

  Future<void> _toggleAlertRule(Map<String, dynamic> rule, bool enabled) async {
    final id = rule['id'] as int?;
    if (id == null) {
      return;
    }

    try {
      await _api.updateAlertRule(id, {'is_active': enabled});
      await _loadAlertRules();
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to update alert rule: $e'),
          backgroundColor: AppTheme.error,
        ),
      );
    }
  }

  Future<void> _deleteAlertRule(Map<String, dynamic> rule) async {
    final id = rule['id'] as int?;
    if (id == null) {
      return;
    }

    try {
      await _api.deleteAlertRule(id);
      await _loadAlertRules();
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to delete alert rule: $e'),
          backgroundColor: AppTheme.error,
        ),
      );
    }
  }

  Future<void> _openCreateAlertDialog() async {
    final nameController = TextEditingController();
    final descController = TextEditingController();
    final classesController = TextEditingController();
    final cooldownController = TextEditingController(text: '60');
    final confidenceController = TextEditingController(text: '0.5');
    final countController = TextEditingController();
    String selectedModel = 'yolo';
    String selectedType = 'object_detected';

    final created = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setLocalState) {
            return AlertDialog(
              title: const Text('Create Alert Rule'),
              content: SizedBox(
                width: 560,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: nameController,
                        decoration: const InputDecoration(
                          labelText: 'Rule Name',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: descController,
                        decoration: const InputDecoration(
                          labelText: 'Description (optional)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        initialValue: selectedModel,
                        decoration: const InputDecoration(
                          labelText: 'Model',
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'yolo', child: Text('yolo')),
                          DropdownMenuItem(value: 'pose', child: Text('pose')),
                          DropdownMenuItem(value: 'preprocess', child: Text('preprocess')),
                          DropdownMenuItem(value: 'custom_model_1', child: Text('custom_model_1')),
                          DropdownMenuItem(value: 'custom_model_2', child: Text('custom_model_2')),
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            setLocalState(() => selectedModel = value);
                          }
                        },
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        initialValue: selectedType,
                        decoration: const InputDecoration(
                          labelText: 'Trigger Type',
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'object_detected', child: Text('object_detected')),
                          DropdownMenuItem(value: 'confidence_above', child: Text('confidence_above')),
                          DropdownMenuItem(value: 'count_threshold', child: Text('count_threshold')),
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            setLocalState(() => selectedType = value);
                          }
                        },
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: classesController,
                        decoration: const InputDecoration(
                          labelText: 'Classes (comma-separated)',
                          hintText: 'person, car',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: confidenceController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(
                          labelText: 'Confidence Min (optional)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: countController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Count Threshold (optional)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: cooldownController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Cooldown (seconds)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () async {
                    final name = nameController.text.trim();
                    if (name.isEmpty) {
                      return;
                    }

                    final classes = classesController.text
                        .split(',')
                        .map((e) => e.trim())
                        .where((e) => e.isNotEmpty)
                        .toList();

                    final confidence = double.tryParse(confidenceController.text.trim());
                    final countThreshold = int.tryParse(countController.text.trim());
                    final cooldown = int.tryParse(cooldownController.text.trim()) ?? 60;

                    final triggerCondition = <String, dynamic>{
                      'type': selectedType,
                      if (classes.isNotEmpty) 'classes': classes,
                      if (confidence != null) 'confidence_min': confidence,
                      if (countThreshold != null) 'count_threshold': countThreshold,
                    };

                    final payload = {
                      'name': name,
                      'description': descController.text.trim().isEmpty
                          ? null
                          : descController.text.trim(),
                      'model_name': selectedModel,
                      'trigger_condition': triggerCondition,
                      'actions': {
                        'push_notification': false,
                        'webhook_ids': <int>[],
                        'log_event': true,
                      },
                      'cooldown_seconds': cooldown,
                    };

                    try {
                      await _api.createAlertRule(payload);
                      if (dialogContext.mounted) {
                        Navigator.pop(dialogContext, true);
                      }
                    } catch (e) {
                      if (dialogContext.mounted) {
                        ScaffoldMessenger.of(dialogContext).showSnackBar(
                          SnackBar(
                            content: Text('Failed to create alert rule: $e'),
                            backgroundColor: AppTheme.error,
                          ),
                        );
                      }
                    }
                  },
                  child: const Text('Create'),
                ),
              ],
            );
          },
        );
      },
    );

    nameController.dispose();
    descController.dispose();
    classesController.dispose();
    cooldownController.dispose();
    confidenceController.dispose();
    countController.dispose();

    if (created == true) {
      await _loadAlertRules();
    }
  }

  bool _isValidCameraSource(String source, String type) {
    if (source.isEmpty) return false;
    
    switch (type) {
      case 'usb':
        return int.tryParse(source) != null;
      case 'rtsp':
        return source.startsWith('rtsp://');
      case 'http':
        return source.startsWith('http://') || source.startsWith('https://');
      case 'video_file':
        return source.endsWith('.mp4') || source.endsWith('.avi') || source.endsWith('.mkv');
      default:
        return false;
    }
  }

  Future<void> _testConnection(StorageService storage) async {
    final source = _cameraSourceController.text.trim();
    if (source.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a source to test')),
      );
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    bool isAccessible = false;

    messenger.showSnackBar(
      const SnackBar(content: Text('Testing connection...')),
    );

    try {
      if (_selectedSourceType == 'http') {
        final uri = Uri.parse(source);
        // Timeout after 3 seconds
        final response = await http.get(uri).timeout(const Duration(seconds: 3));
        isAccessible = response.statusCode >= 200 && response.statusCode < 400; // Might be 200 stream
      } else if (_selectedSourceType == 'usb' || _selectedSourceType == 'rtsp' || _selectedSourceType == 'video_file') {
        // Without full backend checking, we will simply format check or assume it's valid format for now.
        // True robust check requires a backend endpoint.
        isAccessible = _isValidCameraSource(source, _selectedSourceType);
      }
      
      messenger.hideCurrentSnackBar();
      if (isAccessible) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('Source appears Online / Accessible!'),
            backgroundColor: AppTheme.success,
          ),
        );
        // Save to history since it's valid
        storage.setLastCameraSource(source);
      } else {
        messenger.showSnackBar(
          SnackBar(
            content: Text('Source is Offline or Unreachable.'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    } catch (e) {
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text('Failed to connect: ${e.toString()}'),
          backgroundColor: AppTheme.error,
        ),
      );
    }
  }

  Future<void> _startPipeline() async {
    final source = _cameraSourceController.text.trim();
    if (source.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a camera source')),
      );
      return;
    }

    if (!_isValidCameraSource(source, _selectedSourceType)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Invalid source format for type: $_selectedSourceType'),
          backgroundColor: AppTheme.error,
        ),
      );
      return;
    }

    setState(() => _isStarting = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      context.read<StorageService>().setLastCameraSource(source);
      await _api.startPipeline(source);
      if (mounted) {
        setState(() {
          _pipelineStatus = {
            ...?_pipelineStatus,
            'is_running': true,
          };
        });
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text('Pipeline started!'),
          backgroundColor: AppTheme.success,
        ),
      );
      await _syncPipelineStatus(expectedRunning: true, retries: 8);
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Failed to start: $e')),
      );
    }
    if (mounted) {
      setState(() => _isStarting = false);
    }
  }

  Widget _buildHeader(ThemeData theme) {
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.65),
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: Icon(
              Icons.admin_panel_settings_rounded,
              color: colorScheme.onPrimaryContainer,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Admin',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Configure camera, pipeline, schedules, and alerts',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurface.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _stopPipeline() async {
    setState(() => _isStopping = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _api.stopPipeline();
      if (mounted) {
        setState(() {
          _pipelineStatus = {
            ...?_pipelineStatus,
            'is_running': false,
          };
        });
      }
      messenger.showSnackBar(
        const SnackBar(content: Text('Pipeline stopped')),
      );
      await _syncPipelineStatus(expectedRunning: false, retries: 6);
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Failed to stop: $e')),
      );
    }
    if (mounted) {
      setState(() => _isStopping = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isRunning = _pipelineStatus?['is_running'] == true;

    return Scaffold(
      body: Column(
        children: [
          _buildHeader(theme),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Appearance
                  Card(
                    elevation: 0,
                    color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.palette_rounded, color: colorScheme.primary),
                              const SizedBox(width: 12),
                              Text(
                                'Appearance',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Consumer<StorageService>(
                            builder: (context, storage, child) {
                              return SizedBox(
                                width: double.infinity,
                                child: SegmentedButton<ThemeMode>(
                                  style: SegmentedButton.styleFrom(
                                    backgroundColor: colorScheme.surface,
                                    foregroundColor: colorScheme.onSurface,
                                    selectedBackgroundColor: colorScheme.primaryContainer,
                                    selectedForegroundColor: colorScheme.onPrimaryContainer,
                                  ),
                                  segments: const [
                                    ButtonSegment<ThemeMode>(
                                      value: ThemeMode.system,
                                      label: Text(
                                        'System',
                                        maxLines: 1,
                                        softWrap: false,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      icon: Icon(Icons.brightness_auto),
                                    ),
                                    ButtonSegment<ThemeMode>(
                                      value: ThemeMode.light,
                                      label: Text(
                                        'Light',
                                        maxLines: 1,
                                        softWrap: false,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      icon: Icon(Icons.light_mode_rounded),
                                    ),
                                    ButtonSegment<ThemeMode>(
                                      value: ThemeMode.dark,
                                      label: Text(
                                        'Dark',
                                        maxLines: 1,
                                        softWrap: false,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      icon: Icon(Icons.dark_mode_rounded),
                                    ),
                                  ],
                                  selected: {storage.themeMode},
                                  onSelectionChanged: (Set<ThemeMode> newSelection) {
                                    storage.setThemeMode(newSelection.first);
                                  },
                                  showSelectedIcon: false,
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

            // Camera Source Configuration
            Card(
              elevation: 0,
              color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.videocam_rounded, color: colorScheme.primary),
                        const SizedBox(width: 12),
                        Text(
                          'Camera Source',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Source type selector
                    DropdownButtonFormField<String>(
                      initialValue: _selectedSourceType,
                      decoration: const InputDecoration(
                        labelText: 'Source Type',
                        border: OutlineInputBorder(),
                      ),
                      items: _sourceTypes.map((type) {
                        return DropdownMenuItem(
                          value: type['type'],
                          child: Text(type['label']!),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setState(() {
                          _selectedSourceType = value!;
                          _cameraSourceController.text = '';
                        });
                      },
                    ),
                    const SizedBox(height: 16),

                    // Source URL/index input
                    Consumer<StorageService>(
                      builder: (context, storage, child) {
                        return LayoutBuilder(
                          builder: (context, constraints) {
                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Expanded(
                                  child: DropdownMenu<String>(
                                    controller: _cameraSourceController,
                                    width: constraints.maxWidth - 120,
                                    label: const Text('Source'),
                                    enableFilter: true,
                                    requestFocusOnTap: true,
                                    leadingIcon: const Icon(Icons.link_rounded),
                                    dropdownMenuEntries: storage.cameraHistory.map((String value) {
                                      return DropdownMenuEntry<String>(
                                        value: value,
                                        label: value,
                                        trailingIcon: IconButton(
                                          icon: const Icon(Icons.delete_outline, size: 18),
                                          onPressed: () {
                                            storage.removeCameraSourceFromHistory(value);
                                          },
                                        ),
                                      );
                                    }).toList(),
                                    onSelected: (String? value) {
                                      if (value != null) {
                                        _cameraSourceController.text = value;
                                      }
                                    },
                                  ),
                                ),
                                const SizedBox(width: 8),
                                FilledButton.tonalIcon(
                                  onPressed: () => _testConnection(storage),
                                  icon: const Icon(Icons.wifi_find_rounded),
                                  label: const Text('Test'),
                                ),
                              ],
                            );
                          }
                        );
                      }
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Pipeline Control
            Card(
              elevation: 0,
              color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.play_circle_rounded, color: colorScheme.primary),
                        const SizedBox(width: 12),
                        Text(
                          'Pipeline Control',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 4),
                          decoration: BoxDecoration(
                            color: (isRunning ? AppTheme.success : AppTheme.warning)
                                .withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            isRunning ? 'RUNNING' : 'STOPPED',
                            style: TextStyle(
                              color: isRunning ? AppTheme.success : AppTheme.warning,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        FilledButton.icon(
                          onPressed: isRunning || _isStarting
                              ? null
                              : _startPipeline,
                          icon: _isStarting
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.play_arrow_rounded),
                          label: const Text('Start'),
                        ),
                        const SizedBox(width: 12),
                        FilledButton.tonalIcon(
                          onPressed: !isRunning || _isStopping
                              ? null
                              : _stopPipeline,
                          icon: _isStopping
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.stop_rounded),
                          label: const Text('Stop'),
                          style: FilledButton.styleFrom(
                            backgroundColor: colorScheme.errorContainer,
                            foregroundColor: colorScheme.onErrorContainer,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Scheduled Jobs
            Card(
              elevation: 0,
              color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.schedule_rounded, color: colorScheme.primary),
                        const SizedBox(width: 12),
                        Text(
                          'Scheduled Jobs',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                        const Spacer(),
                        OutlinedButton.icon(
                          onPressed: _loadScheduledJobs,
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('Refresh'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Create cron-based pipeline schedules and trigger runs manually for verification.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurface.withValues(alpha: 0.7),
                          ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _scheduleNameController,
                      decoration: const InputDecoration(
                        labelText: 'Job Name',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<int>(
                      initialValue: _selectedScheduleCameraId,
                      decoration: const InputDecoration(
                        labelText: 'Camera Config',
                        border: OutlineInputBorder(),
                      ),
                      items: _cameraConfigs.map((cam) {
                        final id = cam['id'] as int?;
                        final name = cam['name']?.toString() ?? 'Camera';
                        return DropdownMenuItem<int>(
                          value: id,
                          child: Text('$name (#$id)'),
                        );
                      }).whereType<DropdownMenuItem<int>>().toList(),
                      onChanged: (value) => setState(() => _selectedScheduleCameraId = value),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _scheduleCronController,
                            decoration: const InputDecoration(
                              labelText: 'Cron Expression',
                              hintText: '0 9 * * 1-5',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _scheduleDurationController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Duration (min, optional)',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _scheduleModelsController,
                      decoration: const InputDecoration(
                        labelText: 'Enabled Models (comma-separated)',
                        hintText: 'yolo,pose',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton.icon(
                        onPressed: _createScheduledJob,
                        icon: const Icon(Icons.add_task_rounded),
                        label: const Text('Create Schedule'),
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (_isLoadingSchedules)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: 16),
                          child: CircularProgressIndicator(),
                        ),
                      )
                    else if (_scheduledJobs.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Text('No scheduled jobs yet.'),
                      )
                    else
                      Column(
                        children: _scheduledJobs.map((job) {
                          final name = (job['name'] as String?) ?? 'Unnamed Job';
                          final cron = (job['cron_expression'] as String?) ?? '';
                          final statusText = (job['last_run_status'] as String?) ?? 'never run';
                          final isActive = job['is_active'] == true;
                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            title: Text(name),
                            subtitle: Text('$cron • last: $statusText'),
                            trailing: Wrap(
                              spacing: 8,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.play_arrow_rounded),
                                  tooltip: 'Run now',
                                  onPressed: () => _runScheduledJobNow(job),
                                ),
                                Switch(
                                  value: isActive,
                                  onChanged: (value) => _toggleScheduledJob(job, value),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline_rounded),
                                  tooltip: 'Delete schedule',
                                  onPressed: () => _deleteScheduledJob(job),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // ROI Editor
            Card(
              elevation: 0,
              color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.polyline_rounded, color: colorScheme.primary),
                        const SizedBox(width: 12),
                        Text(
                          'ROI Editor',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                        const Spacer(),
                        OutlinedButton.icon(
                          onPressed: _loadROIZones,
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('Refresh'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Draw polygon points on the canvas to define normalized ROI zones per camera.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurface.withValues(alpha: 0.7),
                          ),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<int>(
                      initialValue: _selectedROICameraId,
                      decoration: const InputDecoration(
                        labelText: 'Camera Config',
                        border: OutlineInputBorder(),
                      ),
                      items: _cameraConfigs.map((cam) {
                        final id = cam['id'] as int?;
                        final name = cam['name']?.toString() ?? 'Camera';
                        return DropdownMenuItem<int>(
                          value: id,
                          child: Text('$name (#$id)'),
                        );
                      }).whereType<DropdownMenuItem<int>>().toList(),
                      onChanged: (value) {
                        setState(() => _selectedROICameraId = value);
                        _loadROIZones();
                      },
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _roiNameController,
                            decoration: const InputDecoration(
                              labelText: 'ROI Name',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        SizedBox(
                          width: 190,
                          child: DropdownButtonFormField<String>(
                            initialValue: _selectedROIColor,
                            decoration: const InputDecoration(
                              labelText: 'Color',
                              border: OutlineInputBorder(),
                            ),
                            items: const [
                              DropdownMenuItem(value: '#FF0000', child: Text('Red')),
                              DropdownMenuItem(value: '#00AEEF', child: Text('Blue')),
                              DropdownMenuItem(value: '#00C853', child: Text('Green')),
                              DropdownMenuItem(value: '#FFB300', child: Text('Amber')),
                            ],
                            onChanged: (value) {
                              if (value != null) {
                                setState(() => _selectedROIColor = value);
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _roiDescriptionController,
                      decoration: const InputDecoration(
                        labelText: 'Description (optional)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    AspectRatio(
                      aspectRatio: 16 / 9,
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          return GestureDetector(
                            onTapDown: (details) {
                              final width = constraints.maxWidth;
                              final height = constraints.maxHeight;
                              if (width <= 0 || height <= 0) {
                                return;
                              }
                              _addROIPoint(
                                Offset(
                                  details.localPosition.dx / width,
                                  details.localPosition.dy / height,
                                ),
                              );
                            },
                            child: Container(
                              decoration: BoxDecoration(
                                color: colorScheme.surface,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: colorScheme.outline.withValues(alpha: 0.5),
                                ),
                              ),
                              child: CustomPaint(
                                painter: _ROIPolygonPainter(
                                  points: _roiDraftPoints,
                                  polygonColor: _selectedROIColor,
                                  canvasColor: colorScheme.primary,
                                ),
                                child: Center(
                                  child: _roiDraftPoints.isEmpty
                                      ? Text(
                                          'Tap to add points',
                                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                                color: colorScheme.onSurface.withValues(alpha: 0.6),
                                              ),
                                        )
                                      : null,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        FilledButton.tonalIcon(
                          onPressed: _removeLastROIPoint,
                          icon: const Icon(Icons.undo_rounded),
                          label: const Text('Undo Point'),
                        ),
                        FilledButton.tonalIcon(
                          onPressed: () => _clearROIDraft(clearText: false),
                          icon: const Icon(Icons.clear_all_rounded),
                          label: const Text('Clear Points'),
                        ),
                        FilledButton.icon(
                          onPressed: _isSavingROIZone ? null : _saveROIZone,
                          icon: _isSavingROIZone
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : Icon(_editingROIZoneId == null
                                  ? Icons.add_location_alt_rounded
                                  : Icons.save_rounded),
                          label: Text(_editingROIZoneId == null ? 'Create ROI Zone' : 'Update ROI Zone'),
                        ),
                        if (_editingROIZoneId != null)
                          FilledButton.tonalIcon(
                            onPressed: () => _clearROIDraft(clearText: true),
                            icon: const Icon(Icons.close_rounded),
                            label: const Text('Cancel Edit'),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Draft points: ${_roiDraftPoints.length}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurface.withValues(alpha: 0.7),
                          ),
                    ),
                    const SizedBox(height: 16),
                    if (_isLoadingROIZones)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: 16),
                          child: CircularProgressIndicator(),
                        ),
                      )
                    else if (_roiZones.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Text('No ROI zones configured for this camera.'),
                      )
                    else
                      Column(
                        children: _roiZones.map((zone) {
                          final name = zone['name']?.toString() ?? 'Unnamed ROI';
                          final isActive = zone['is_active'] == true;
                          final pointCount = (zone['coordinates'] as List<dynamic>? ?? <dynamic>[]).length;
                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            leading: Icon(Icons.gesture_rounded, color: colorScheme.primary),
                            title: Text(name),
                            subtitle: Text('points: $pointCount • ${zone['zone_type'] ?? 'polygon'}'),
                            trailing: Wrap(
                              spacing: 8,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.edit_rounded),
                                  tooltip: 'Edit ROI',
                                  onPressed: () => _startEditROIZone(zone),
                                ),
                                Switch(
                                  value: isActive,
                                  onChanged: (value) => _toggleROIZone(zone, value),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline_rounded),
                                  tooltip: 'Delete ROI',
                                  onPressed: () => _deleteROIZone(zone),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Webhooks
            Card(
              elevation: 0,
              color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.hub_rounded, color: colorScheme.primary),
                        const SizedBox(width: 12),
                        Text(
                          'Webhooks',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                        const Spacer(),
                        OutlinedButton.icon(
                          onPressed: _loadWebhooks,
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('Refresh'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Configure outbound webhook endpoints for alert/integration events.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurface.withValues(alpha: 0.7),
                          ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _webhookNameController,
                      decoration: const InputDecoration(
                        labelText: 'Webhook Name',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _webhookUrlController,
                      decoration: const InputDecoration(
                        labelText: 'Webhook URL',
                        hintText: 'https://example.com/webhook',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _webhookSecretController,
                      decoration: const InputDecoration(
                        labelText: 'Secret Key (optional)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _webhookEventsController,
                      decoration: const InputDecoration(
                        labelText: 'Events (comma-separated)',
                        hintText: 'alert, detection, session_start',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton.icon(
                        onPressed: _createWebhook,
                        icon: const Icon(Icons.add_link_rounded),
                        label: const Text('Create Webhook'),
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (_isLoadingWebhooks)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: 16),
                          child: CircularProgressIndicator(),
                        ),
                      )
                    else if (_webhooks.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Text('No webhooks configured yet.'),
                      )
                    else
                      Column(
                        children: _webhooks.map((webhook) {
                          final name = (webhook['name'] as String?) ?? 'Unnamed Webhook';
                          final url = (webhook['url'] as String?) ?? '';
                          final statusCode = webhook['last_status_code'];
                          final isActive = webhook['is_active'] == true;
                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            title: Text(name),
                            subtitle: Text('$url${statusCode != null ? ' • last=$statusCode' : ''}'),
                            trailing: Wrap(
                              spacing: 8,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.play_circle_outline_rounded),
                                  tooltip: 'Test webhook',
                                  onPressed: () => _testWebhook(webhook),
                                ),
                                Switch(
                                  value: isActive,
                                  onChanged: (value) => _toggleWebhook(webhook, value),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline_rounded),
                                  tooltip: 'Delete webhook',
                                  onPressed: () => _deleteWebhook(webhook),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Push Notifications
            Card(
              elevation: 0,
              color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.notifications_rounded, color: colorScheme.primary),
                        const SizedBox(width: 12),
                        Text(
                          'Push Notifications',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                        const Spacer(),
                        OutlinedButton.icon(
                          onPressed: _loadDeviceTokens,
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('Refresh'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Register device tokens and send test push dispatches (simulation mode).',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurface.withValues(alpha: 0.7),
                          ),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: _selectedTokenPlatform,
                      decoration: const InputDecoration(
                        labelText: 'Platform',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'fcm', child: Text('fcm')),
                        DropdownMenuItem(value: 'apns', child: Text('apns')),
                        DropdownMenuItem(value: 'web', child: Text('web')),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setState(() => _selectedTokenPlatform = value);
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _deviceTokenController,
                      decoration: const InputDecoration(
                        labelText: 'Device Token',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _deviceNameController,
                            decoration: const InputDecoration(
                              labelText: 'Device Name (optional)',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _userIdController,
                            decoration: const InputDecoration(
                              labelText: 'User ID (optional)',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton.icon(
                        onPressed: _registerDeviceToken,
                        icon: const Icon(Icons.app_registration_rounded),
                        label: const Text('Register Token'),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _testTitleController,
                      decoration: const InputDecoration(
                        labelText: 'Test Title',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _testBodyController,
                      decoration: const InputDecoration(
                        labelText: 'Test Body',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton.tonalIcon(
                        onPressed: _isSendingTestPush ? null : _sendTestPush,
                        icon: _isSendingTestPush
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.send_rounded),
                        label: const Text('Send Test'),
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (_isLoadingDeviceTokens)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: 16),
                          child: CircularProgressIndicator(),
                        ),
                      )
                    else if (_deviceTokens.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Text('No device tokens registered yet.'),
                      )
                    else
                      Column(
                        children: _deviceTokens.map((token) {
                          final tokenValue = (token['device_token'] as String?) ?? '';
                          final isActive = token['is_active'] == true;
                          final platform = (token['platform'] as String?) ?? 'unknown';
                          final deviceName = (token['device_name'] as String?) ?? 'Unnamed Device';
                          final userId = (token['user_id'] as String?) ?? 'n/a';
                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            title: Text(deviceName),
                            subtitle: Text('${_maskToken(tokenValue)} • $platform • user: $userId'),
                            trailing: Wrap(
                              spacing: 8,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Switch(
                                  value: isActive,
                                  onChanged: (value) => _toggleDeviceToken(token, value),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline_rounded),
                                  tooltip: 'Delete token',
                                  onPressed: () => _deleteDeviceToken(token),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Alert Rules
            Card(
              elevation: 0,
              color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.notifications_active_rounded, color: colorScheme.primary),
                        const SizedBox(width: 12),
                        Text(
                          'Alert Rules',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                        const Spacer(),
                        OutlinedButton.icon(
                          onPressed: _loadAlertRules,
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('Refresh'),
                        ),
                        const SizedBox(width: 8),
                        FilledButton.icon(
                          onPressed: _openCreateAlertDialog,
                          icon: const Icon(Icons.add_alert_rounded),
                          label: const Text('Add Rule'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (_isLoadingAlerts)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: 16),
                          child: CircularProgressIndicator(),
                        ),
                      )
                    else if (_alertRules.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Text('No alert rules yet. Create one to start trigger-based automation.'),
                      )
                    else
                      Column(
                        children: _alertRules.map((rule) {
                          final trigger = Map<String, dynamic>.from(
                            rule['trigger_condition'] as Map? ?? <String, dynamic>{},
                          );
                          final ruleName = (rule['name'] as String?) ?? 'Unnamed Rule';
                          final modelName = (rule['model_name'] as String?) ?? 'unknown';
                          final isActive = rule['is_active'] == true;
                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            title: Text(ruleName),
                            subtitle: Text(
                              'Model: $modelName, Trigger: ${trigger['type'] ?? 'unknown'}',
                            ),
                            trailing: Wrap(
                              spacing: 8,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Switch(
                                  value: isActive,
                                  onChanged: (value) => _toggleAlertRule(rule, value),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline_rounded),
                                  tooltip: 'Delete rule',
                                  onPressed: () => _deleteAlertRule(rule),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Activity Logs Viewer
            Card(
              elevation: 0,
              color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.receipt_long_rounded, color: colorScheme.primary),
                        const SizedBox(width: 12),
                        Text(
                          'Activity Logs',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                        const Spacer(),
                        OutlinedButton.icon(
                          onPressed: _loadActivityLogs,
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('Refresh'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Filter and inspect pipeline/backend activity from the last 24 hours.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurface.withValues(alpha: 0.7),
                          ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        SizedBox(
                          width: 220,
                          child: DropdownButtonFormField<String>(
                            initialValue: _selectedLogSeverity,
                            decoration: const InputDecoration(
                              labelText: 'Severity Filter',
                              border: OutlineInputBorder(),
                            ),
                            items: const [
                              DropdownMenuItem(value: '', child: Text('All')),
                              DropdownMenuItem(value: 'debug', child: Text('debug')),
                              DropdownMenuItem(value: 'info', child: Text('info')),
                              DropdownMenuItem(value: 'warning', child: Text('warning')),
                              DropdownMenuItem(value: 'error', child: Text('error')),
                              DropdownMenuItem(value: 'critical', child: Text('critical')),
                            ],
                            onChanged: (value) {
                              setState(() => _selectedLogSeverity = value ?? '');
                              _loadActivityLogs();
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        SizedBox(
                          width: 180,
                          child: DropdownButtonFormField<int>(
                            initialValue: _logLimit,
                            decoration: const InputDecoration(
                              labelText: 'Limit',
                              border: OutlineInputBorder(),
                            ),
                            items: const [
                              DropdownMenuItem(value: 20, child: Text('20')),
                              DropdownMenuItem(value: 30, child: Text('30')),
                              DropdownMenuItem(value: 50, child: Text('50')),
                              DropdownMenuItem(value: 100, child: Text('100')),
                            ],
                            onChanged: (value) {
                              if (value != null) {
                                setState(() => _logLimit = value);
                                _loadActivityLogs();
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (_logStatistics != null)
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          Chip(label: Text('Total: ${_logStatistics?['total_logs'] ?? 0}')),
                          Chip(label: Text('Errors: ${(_logStatistics?['by_severity']?['error'] ?? 0)}')),
                          Chip(label: Text('Critical: ${(_logStatistics?['by_severity']?['critical'] ?? 0)}')),
                          Chip(label: Text('Warnings: ${(_logStatistics?['by_severity']?['warning'] ?? 0)}')),
                        ],
                      ),
                    const SizedBox(height: 12),
                    if (_isLoadingLogs)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: 16),
                          child: CircularProgressIndicator(),
                        ),
                      )
                    else if (_activityLogs.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Text('No logs found for current filter.'),
                      )
                    else
                      Column(
                        children: _activityLogs.map((log) {
                          final severity = (log['severity'] as String?) ?? 'info';
                          final severityColor = severity == 'critical' || severity == 'error'
                              ? AppTheme.error
                              : severity == 'warning'
                                ? AppTheme.warning
                                : AppTheme.success;
                          final eventType = (log['event_type'] as String?) ?? 'event';
                          final message = (log['message'] as String?) ?? '';
                          final createdAt = (log['created_at'] as String?) ?? '';

                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            leading: CircleAvatar(
                              radius: 14,
                              backgroundColor: severityColor.withValues(alpha: 0.15),
                              child: Icon(Icons.circle, color: severityColor, size: 10),
                            ),
                            title: Text(eventType),
                            subtitle: Text('$message\n$createdAt'),
                            isThreeLine: true,
                            trailing: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: severityColor.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                severity.toUpperCase(),
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: severityColor,
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                  ],
                ),
              ),
            ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ROIPolygonPainter extends CustomPainter {
  _ROIPolygonPainter({
    required this.points,
    required this.polygonColor,
    required this.canvasColor,
  });

  final List<Offset> points;
  final String polygonColor;
  final Color canvasColor;

  @override
  void paint(Canvas canvas, Size size) {
    final strokeColor = _parseHexColor(polygonColor) ?? canvasColor;

    final fillPaint = Paint()
      ..color = strokeColor.withValues(alpha: 0.18)
      ..style = PaintingStyle.fill;

    final linePaint = Paint()
      ..color = strokeColor
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    final pointPaint = Paint()
      ..color = strokeColor
      ..style = PaintingStyle.fill;

    final mapped = points
        .map((p) => Offset(p.dx * size.width, p.dy * size.height))
        .toList();

    if (mapped.length >= 2) {
      final path = Path()..moveTo(mapped.first.dx, mapped.first.dy);
      for (final point in mapped.skip(1)) {
        path.lineTo(point.dx, point.dy);
      }

      if (mapped.length >= 3) {
        path.close();
        canvas.drawPath(path, fillPaint);
      }
      canvas.drawPath(path, linePaint);
    }

    for (final point in mapped) {
      canvas.drawCircle(point, 4.5, pointPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _ROIPolygonPainter oldDelegate) {
    return oldDelegate.points != points || oldDelegate.polygonColor != polygonColor;
  }
}

Color? _parseHexColor(String hex) {
  final value = hex.trim().replaceAll('#', '');
  if (value.length != 6 && value.length != 8) {
    return null;
  }
  final normalized = value.length == 6 ? 'FF$value' : value;
  final intValue = int.tryParse(normalized, radix: 16);
  if (intValue == null) {
    return null;
  }
  return Color(intValue);
}






