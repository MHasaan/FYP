import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/multi_instance_ws_service.dart';
import '../services/download_service.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';

/// Multi-Camera Grid Screen
/// Shows multiple pipeline instances in a grid layout with live feeds
class MultiCameraGridScreen extends StatefulWidget {
  final ValueChanged<int>? onNavigateToTab;

  const MultiCameraGridScreen({
    super.key,
    this.onNavigateToTab,
  });

  @override
  State<MultiCameraGridScreen> createState() => _MultiCameraGridScreenState();
}

class _MultiCameraGridScreenState extends State<MultiCameraGridScreen> {
  final MultiInstanceWsService _multiWs = MultiInstanceWsService();
  final ApiService _api = ApiService();
  final TextEditingController _searchController = TextEditingController();
  static const List<String> _availableModels = [
    'pose',
    'fall_detection',
    'test',
  ];

  List<Map<String, dynamic>> _instances = [];
  bool _isLoading = true;
  String? _error;
  static const int _instancesPageSize = 100;
  static const int _groupRenderChunkSize = 24;
  int _instancesTotal = 0;
  int _instancesOffset = 0;
  bool _hasMoreInstances = false;
  bool _isLoadingMoreInstances = false;

  // Stream subscriptions for cleanup
  final Map<int, StreamSubscription> _feedSubscriptions = {};
  final Map<int, StreamSubscription> _resultsSubscriptions = {};

  // UI state for each instance
  final Map<int, Uint8List?> _instanceFrames = {};
  final Map<int, Map<String, dynamic>?> _instanceResults = {};
  final Map<int, DateTime> _lastFrameAt = {};
  final Map<int, DateTime> _lastFeedReconnectAt = {};
  final Map<int, bool> _instanceShowOverlay = {};
  final Map<int, String> _cameraGroups = {};
  final Map<int, Map<String, dynamic>> _cameraConfigsById = {};
  String _selectedGroupFilter = 'All';
  bool _groupedView = false;
  String _searchQuery = '';
  String _sortBy = 'created_at';
  String _sortOrder = 'desc';
  final Map<String, bool> _expandedGroups = {};
  final Map<String, int> _groupRenderLimits = {};
  Map<String, dynamic>? _lastImportReport;
  Timer? _feedHealthTimer;
  Timer? _searchDebounceTimer;

  @override
  void initState() {
    super.initState();
    _feedHealthTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _checkFeedHealth();
    });
    _loadInstances();
  }

  @override
  void dispose() {
    // Cancel all subscriptions
    for (final sub in _feedSubscriptions.values) {
      sub.cancel();
    }
    for (final sub in _resultsSubscriptions.values) {
      sub.cancel();
    }
    _searchController.dispose();
    _feedHealthTimer?.cancel();
    _searchDebounceTimer?.cancel();
    _multiWs.disconnectAll();
    _api.dispose();
    super.dispose();
  }

  String? get _activeGroupFilter {
    if (_selectedGroupFilter == 'All') {
      return null;
    }
    return _selectedGroupFilter;
  }

  void _scheduleSearchReload() {
    _searchDebounceTimer?.cancel();
    _searchDebounceTimer = Timer(const Duration(milliseconds: 350), () {
      _loadInstances();
    });
  }

  Future<void> _loadInstances() async {
    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });

      // Reset active subscriptions before rebuilding instance connections.
      for (final sub in _feedSubscriptions.values) {
        sub.cancel();
      }
      for (final sub in _resultsSubscriptions.values) {
        sub.cancel();
      }
      _feedSubscriptions.clear();
      _resultsSubscriptions.clear();
      _multiWs.disconnectAll();
      _instanceFrames.clear();
      _instanceResults.clear();
      _lastFrameAt.clear();
      _lastFeedReconnectAt.clear();
      _cameraGroups.clear();
      _cameraConfigsById.clear();

      final instancesPage = await _api.getInstancesPaged(
        groupName: _activeGroupFilter,
        searchQuery: _searchQuery.trim().isEmpty ? null : _searchQuery.trim(),
        sortBy: _sortBy,
        sortOrder: _sortOrder,
        limit: _instancesPageSize,
        offset: 0,
      );
      final cameraConfigs = await _api.getCameraConfigs();

      final pagedItems = (instancesPage['items'] as List<dynamic>? ?? <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .toList();
      final total = (instancesPage['total'] as num?)?.toInt() ?? pagedItems.length;

      for (final config in cameraConfigs) {
        if (config is Map<String, dynamic>) {
          final id = config['id'];
          if (id is int) {
            _cameraConfigsById[id] = config;
            _cameraGroups[id] = (config['group_name'] as String?)?.trim() ?? '';
          }
        }
      }

      setState(() {
        _instances = pagedItems;
        _instancesTotal = total;
        _instancesOffset = pagedItems.length;
        _hasMoreInstances = _instancesOffset < _instancesTotal;
        final availableGroups = _getAvailableGroups();
        if (!availableGroups.contains(_selectedGroupFilter)) {
          _selectedGroupFilter = 'All';
        }

        final filteredForGroupMap = _getFilteredInstances();
        final currentGroups = _groupInstances(filteredForGroupMap).keys.toSet();
        _expandedGroups.removeWhere((key, _) => !currentGroups.contains(key));
        _groupRenderLimits.removeWhere((key, _) => !currentGroups.contains(key));
        for (final group in currentGroups) {
          _expandedGroups.putIfAbsent(group, () => false);
          _groupRenderLimits.putIfAbsent(group, () => _groupRenderChunkSize);
        }
        _isLoading = false;
      });

      // Connect to running instances
      for (final instance in _instances) {
        final instanceId = instance['id'] as int;
        final status = instance['status'] as String?;

        if (status == 'running') {
          _connectToInstance(instanceId);
        }

        // Initialize UI state
        _instanceShowOverlay[instanceId] = true;
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _loadMoreInstances() async {
    if (_isLoadingMoreInstances || !_hasMoreInstances) {
      return;
    }

    setState(() => _isLoadingMoreInstances = true);
    try {
      final page = await _api.getInstancesPaged(
        groupName: _activeGroupFilter,
        searchQuery: _searchQuery.trim().isEmpty ? null : _searchQuery.trim(),
        sortBy: _sortBy,
        sortOrder: _sortOrder,
        limit: _instancesPageSize,
        offset: _instancesOffset,
      );
      final items = (page['items'] as List<dynamic>? ?? <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .toList();
      final total = (page['total'] as num?)?.toInt() ?? _instancesTotal;

      if (!mounted) {
        return;
      }

      setState(() {
        _instances.addAll(items);
        _instancesTotal = total;
        _instancesOffset = _instances.length;
        _hasMoreInstances = _instancesOffset < _instancesTotal;

        for (final instance in items) {
          final instanceId = instance['id'] as int?;
          if (instanceId == null) {
            continue;
          }
          final status = instance['status'] as String?;
          _instanceShowOverlay[instanceId] ??= true;
          if (status == 'running') {
            _connectToInstance(instanceId);
          }
        }
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to load more instances: $e'),
          backgroundColor: AppTheme.error,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoadingMoreInstances = false);
      }
    }
  }

  void _connectToInstance(int instanceId) {
    _feedSubscriptions[instanceId]?.cancel();
    _resultsSubscriptions[instanceId]?.cancel();
    _multiWs.connectInstance(instanceId);

    // Subscribe to feed stream
    _feedSubscriptions[instanceId] = _multiWs.getFeedStream(instanceId).listen((data) {
      if (mounted && data['image'] != null) {
        setState(() {
          _instanceFrames[instanceId] = base64Decode(data['image'] as String);
          _lastFrameAt[instanceId] = DateTime.now();
        });
      }
    });

    // Subscribe to results stream
    _resultsSubscriptions[instanceId] = _multiWs.getResultsStream(instanceId).listen((data) {
      if (mounted) {
        setState(() {
          _instanceResults[instanceId] = data;
        });
      }
    });
  }

  void _disconnectFromInstance(int instanceId) {
    _feedSubscriptions[instanceId]?.cancel();
    _resultsSubscriptions[instanceId]?.cancel();
    _feedSubscriptions.remove(instanceId);
    _resultsSubscriptions.remove(instanceId);
    _multiWs.disconnectInstance(instanceId);

    setState(() {
      _instanceFrames.remove(instanceId);
      _instanceResults.remove(instanceId);
      _lastFrameAt.remove(instanceId);
      _lastFeedReconnectAt.remove(instanceId);
    });
  }

  void _checkFeedHealth() {
    if (!mounted) {
      return;
    }

    final now = DateTime.now();
    for (final instance in _instances) {
      final instanceId = instance['id'] as int?;
      final status = (instance['status'] as String?) ?? '';
      if (instanceId == null || status != 'running') {
        continue;
      }

      final lastFrame = _lastFrameAt[instanceId];
      final secondsSinceFrame = lastFrame == null ? 999 : now.difference(lastFrame).inSeconds;
      if (secondsSinceFrame < 12) {
        continue;
      }

      final lastReconnect = _lastFeedReconnectAt[instanceId];
      if (lastReconnect != null && now.difference(lastReconnect).inSeconds < 10) {
        continue;
      }

      _lastFeedReconnectAt[instanceId] = now;
      _multiWs.forceReconnectFeed(instanceId);
    }
  }

  Future<void> _controlInstance(int instanceId, String action) async {
    final instanceIndex = _instances.indexWhere((inst) => inst['id'] == instanceId);
    final instance = instanceIndex >= 0 ? _instances[instanceIndex] : null;
    final cameraConfigId = instance?['camera_config_id'] as int?;
    final requiresCameraConfig = action == 'start' || action == 'resume';

    if (requiresCameraConfig && cameraConfigId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Cannot start/resume this camera: missing camera configuration.'),
            backgroundColor: AppTheme.warning,
          ),
        );
      }
      return;
    }

    try {
      await _api.controlInstance(instanceId, action);

      // Update local state optimistically
      if (instanceIndex >= 0) {
        setState(() {
          switch (action) {
            case 'start':
              _instances[instanceIndex]['status'] = 'running';
              _connectToInstance(instanceId);
              break;
            case 'stop':
              _instances[instanceIndex]['status'] = 'stopped';
              _disconnectFromInstance(instanceId);
              break;
            case 'pause':
              _instances[instanceIndex]['status'] = 'paused';
              break;
            case 'resume':
              _instances[instanceIndex]['status'] = 'running';
              break;
          }
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to $action instance: ${e.toString()}'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    }
  }

  Future<void> _openAddCameraDialog() async {
    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController();
    final sourceController = TextEditingController();
    final groupController = TextEditingController();
    String sourceType = 'usb';
    final selectedModels = <String>{'pose'};
    bool isSubmitting = false;

    final created = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setLocalState) {
            return AlertDialog(
              title: Text('Add Camera Instance'),
              content: SizedBox(
                width: 480,
                child: Form(
                  key: formKey,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextFormField(
                          controller: nameController,
                          decoration: const InputDecoration(
                            labelText: 'Camera Name',
                            hintText: 'Entrance Camera',
                          ),
                          validator: (value) => (value == null || value.trim().isEmpty)
                              ? 'Camera name is required'
                              : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: groupController,
                          decoration: const InputDecoration(
                            labelText: 'Group (optional)',
                            hintText: 'Floor 1',
                          ),
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          initialValue: sourceType,
                          decoration: const InputDecoration(labelText: 'Source Type'),
                          items: const [
                            DropdownMenuItem(value: 'usb', child: Text('USB Camera')),
                            DropdownMenuItem(value: 'rtsp', child: Text('RTSP Stream')),
                            DropdownMenuItem(value: 'http', child: Text('HTTP Stream')),
                            DropdownMenuItem(value: 'video_file', child: Text('Video File')),
                          ],
                          onChanged: (value) {
                            if (value != null) {
                              setLocalState(() => sourceType = value);
                            }
                          },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: sourceController,
                          decoration: const InputDecoration(
                            labelText: 'Source URL / Index',
                            hintText: '0 or rtsp://... or http://.../video',
                          ),
                          validator: (value) => (value == null || value.trim().isEmpty)
                              ? 'Camera source is required'
                              : null,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Models/Pipeline',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _availableModels.map((model) {
                            return FilterChip(
                              label: Text(model),
                              selected: selectedModels.contains(model),
                              onSelected: (selected) {
                                setLocalState(() {
                                  if (selected) {
                                    selectedModels.add(model);
                                  } else {
                                    selectedModels.remove(model);
                                  }
                                });
                              },
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSubmitting ? null : () => Navigator.pop(context, false),
                  child: Text('Cancel'),
                ),
                FilledButton(
                  onPressed: isSubmitting
                      ? null
                      : () async {
                          if (!(formKey.currentState?.validate() ?? false)) {
                            return;
                          }
                          if (selectedModels.isEmpty) {
                            ScaffoldMessenger.of(this.context).showSnackBar(
                              SnackBar(
                                content: Text('Select at least one model'),
                                backgroundColor: AppTheme.error,
                              ),
                            );
                            return;
                          }

                          setLocalState(() => isSubmitting = true);
                          try {
                            final camera = await _api.createCameraConfig({
                              'name': nameController.text.trim(),
                              'source_type': sourceType,
                              'source_url': sourceController.text.trim(),
                              'group_name': groupController.text.trim().isEmpty
                                  ? null
                                  : groupController.text.trim(),
                              'enabled_models': selectedModels.toList(),
                              'model_configs': {},
                            });

                            await _api.createInstance({
                              'name': nameController.text.trim(),
                              'camera_config_id': camera['id'],
                              'enabled_models': selectedModels.toList(),
                              'model_configs': {},
                            });

                            if (mounted) {
                              Navigator.pop(context, true);
                            }
                          } catch (e) {
                            if (mounted) {
                              ScaffoldMessenger.of(this.context).showSnackBar(
                                SnackBar(
                                  content: Text('Failed to add camera: $e'),
                                  backgroundColor: AppTheme.error,
                                ),
                              );
                            }
                            setLocalState(() => isSubmitting = false);
                          }
                        },
                  child: Text('Create'),
                ),
              ],
            );
          },
        );
      },
    );

    nameController.dispose();
    sourceController.dispose();
    groupController.dispose();

    if (created == true) {
      await _loadInstances();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Camera and instance created successfully'),
            backgroundColor: AppTheme.success,
          ),
        );
      }
    }
  }

  Future<void> _openModelAssignmentDialog(Map<String, dynamic> instance) async {
    final instanceId = instance['id'] as int;
    final currentModels = List<String>.from(instance['enabled_models'] as List? ?? <String>[]);
    final selectedModels = <String>{...currentModels};
    bool isSubmitting = false;

    final updated = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setLocalState) {
            return AlertDialog(
              title: Text('Assign Models: ${instance['name']}'),
              content: SizedBox(
                width: 420,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _availableModels.map((model) {
                    return FilterChip(
                      label: Text(model),
                      selected: selectedModels.contains(model),
                      onSelected: (selected) {
                        setLocalState(() {
                          if (selected) {
                            selectedModels.add(model);
                          } else {
                            selectedModels.remove(model);
                          }
                        });
                      },
                    );
                  }).toList(),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSubmitting ? null : () => Navigator.pop(context, false),
                  child: Text('Cancel'),
                ),
                FilledButton(
                  onPressed: isSubmitting
                      ? null
                      : () async {
                          if (selectedModels.isEmpty) {
                            ScaffoldMessenger.of(this.context).showSnackBar(
                              SnackBar(
                                content: Text('Select at least one model'),
                                backgroundColor: AppTheme.error,
                              ),
                            );
                            return;
                          }

                          setLocalState(() => isSubmitting = true);
                          try {
                            await _api.updateInstanceModels(instanceId, selectedModels.toList());
                            if (mounted) {
                              Navigator.pop(context, true);
                            }
                          } catch (e) {
                            if (mounted) {
                              ScaffoldMessenger.of(this.context).showSnackBar(
                                SnackBar(
                                  content: Text('Failed to update models: $e'),
                                  backgroundColor: AppTheme.error,
                                ),
                              );
                            }
                            setLocalState(() => isSubmitting = false);
                          }
                        },
                  child: Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );

    if (updated == true) {
      await _loadInstances();
    }
  }

  Future<void> _openModelConfigDialog(Map<String, dynamic> instance) async {
    final instanceId = instance['id'] as int;
    final cameraConfigId = instance['camera_config_id'] as int?;
    final enabledModels = List<String>.from(instance['enabled_models'] as List? ?? <String>[]);
    final existingConfigs = Map<String, dynamic>.from(
      instance['model_configs'] as Map? ?? <String, dynamic>{},
    );

    if (enabledModels.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Assign at least one model before configuring parameters'),
            backgroundColor: AppTheme.warning,
          ),
        );
      }
      return;
    }

    final confidenceByModel = <String, double>{};
    final nmsByModel = <String, double>{};
    final classesControllerByModel = <String, TextEditingController>{};

    for (final model in enabledModels) {
      final cfg = Map<String, dynamic>.from(
        existingConfigs[model] as Map? ?? <String, dynamic>{},
      );
      confidenceByModel[model] = ((cfg['confidence'] as num?)?.toDouble() ?? 0.5).clamp(0.0, 1.0);
      nmsByModel[model] = ((cfg['nms_threshold'] as num?)?.toDouble() ?? 0.45).clamp(0.0, 1.0);

      final classes = cfg['classes'];
      final classesText = classes is List
          ? classes.map((e) => e.toString()).join(', ')
          : (classes as String? ?? '');
      classesControllerByModel[model] = TextEditingController(text: classesText);
    }

    bool isSubmitting = false;
    final updated = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setLocalState) {
            return AlertDialog(
              title: Text('Configure Models: ${instance['name']}'),
              content: SizedBox(
                width: 620,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: enabledModels.map((model) {
                      final confidence = confidenceByModel[model] ?? 0.5;
                      final nms = nmsByModel[model] ?? 0.45;
                      final classesController = classesControllerByModel[model]!;

                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: Theme.of(context).colorScheme.outlineVariant,
                          ),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              model,
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text('Confidence: ${confidence.toStringAsFixed(2)}'),
                            Slider(
                              value: confidence,
                              min: 0,
                              max: 1,
                              divisions: 20,
                              label: confidence.toStringAsFixed(2),
                              onChanged: (value) {
                                setLocalState(() => confidenceByModel[model] = value);
                              },
                            ),
                            Text('NMS Threshold: ${nms.toStringAsFixed(2)}'),
                            Slider(
                              value: nms,
                              min: 0,
                              max: 1,
                              divisions: 20,
                              label: nms.toStringAsFixed(2),
                              onChanged: (value) {
                                setLocalState(() => nmsByModel[model] = value);
                              },
                            ),
                            TextField(
                              controller: classesController,
                              decoration: const InputDecoration(
                                labelText: 'Target Classes (comma-separated)',
                                hintText: 'person, car, bicycle',
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSubmitting ? null : () => Navigator.pop(context, false),
                  child: Text('Cancel'),
                ),
                FilledButton(
                  onPressed: isSubmitting
                      ? null
                      : () async {
                          setLocalState(() => isSubmitting = true);
                          try {
                            final updatedConfigs = Map<String, dynamic>.from(existingConfigs);
                            for (final model in enabledModels) {
                              final classesText = classesControllerByModel[model]!.text.trim();
                              final classes = classesText.isEmpty
                                  ? <String>[]
                                  : classesText
                                        .split(',')
                                        .map((e) => e.trim())
                                        .where((e) => e.isNotEmpty)
                                        .toList();

                              updatedConfigs[model] = {
                                ...Map<String, dynamic>.from(
                                  updatedConfigs[model] as Map? ?? <String, dynamic>{},
                                ),
                                'confidence': confidenceByModel[model] ?? 0.5,
                                'nms_threshold': nmsByModel[model] ?? 0.45,
                                'classes': classes,
                              };
                            }

                            await _api.updateInstanceConfig(instanceId, updatedConfigs);
                            if (cameraConfigId != null) {
                              await _api.updateCameraConfig(cameraConfigId, {
                                'enabled_models': enabledModels,
                                'model_configs': updatedConfigs,
                              });
                            }

                            if (mounted) {
                              Navigator.pop(context, true);
                            }
                          } catch (e) {
                            if (mounted) {
                              ScaffoldMessenger.of(this.context).showSnackBar(
                                SnackBar(
                                  content: Text('Failed to update model parameters: $e'),
                                  backgroundColor: AppTheme.error,
                                ),
                              );
                            }
                            setLocalState(() => isSubmitting = false);
                          }
                        },
                  child: Text('Save Parameters'),
                ),
              ],
            );
          },
        );
      },
    );

    for (final controller in classesControllerByModel.values) {
      controller.dispose();
    }

    if (updated == true) {
      await _loadInstances();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Model parameters updated successfully'),
            backgroundColor: AppTheme.success,
          ),
        );
      }
    }
  }

  Future<void> _openEditCameraDialog(Map<String, dynamic> instance) async {
    final cameraConfigId = instance['camera_config_id'] as int?;
    if (cameraConfigId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No camera config linked to this instance'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
      return;
    }

    final cameraConfig = _cameraConfigsById[cameraConfigId];
    if (cameraConfig == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Camera configuration not found'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
      return;
    }

    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController(text: (instance['name'] as String?) ?? '');
    final sourceController = TextEditingController(text: (cameraConfig['source_url'] as String?) ?? '');
    final groupController = TextEditingController(text: (cameraConfig['group_name'] as String?) ?? '');
    String sourceType = (cameraConfig['source_type'] as String?) ?? 'usb';
    bool isSubmitting = false;

    final updated = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setLocalState) {
            return AlertDialog(
              title: Text('Edit Camera Metadata'),
              content: SizedBox(
                width: 480,
                child: Form(
                  key: formKey,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextFormField(
                          controller: nameController,
                          decoration: const InputDecoration(labelText: 'Camera Name'),
                          validator: (value) => (value == null || value.trim().isEmpty)
                              ? 'Camera name is required'
                              : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: groupController,
                          decoration: const InputDecoration(
                            labelText: 'Group (optional)',
                            hintText: 'Floor 1 / Zone A',
                          ),
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          initialValue: sourceType,
                          decoration: const InputDecoration(labelText: 'Source Type'),
                          items: const [
                            DropdownMenuItem(value: 'usb', child: Text('USB Camera')),
                            DropdownMenuItem(value: 'rtsp', child: Text('RTSP Stream')),
                            DropdownMenuItem(value: 'http', child: Text('HTTP Stream')),
                            DropdownMenuItem(value: 'video_file', child: Text('Video File')),
                          ],
                          onChanged: (value) {
                            if (value != null) {
                              setLocalState(() => sourceType = value);
                            }
                          },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: sourceController,
                          decoration: const InputDecoration(labelText: 'Source URL / Index'),
                          validator: (value) => (value == null || value.trim().isEmpty)
                              ? 'Source is required'
                              : null,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSubmitting ? null : () => Navigator.pop(context, false),
                  child: Text('Cancel'),
                ),
                FilledButton(
                  onPressed: isSubmitting
                      ? null
                      : () async {
                          if (!(formKey.currentState?.validate() ?? false)) {
                            return;
                          }

                          setLocalState(() => isSubmitting = true);
                          try {
                            await _api.updateCameraConfig(cameraConfigId, {
                              'name': nameController.text.trim(),
                              'group_name': groupController.text.trim().isEmpty
                                  ? null
                                  : groupController.text.trim(),
                              'source_type': sourceType,
                              'source_url': sourceController.text.trim(),
                            });

                            await _api.updateInstance(
                              instance['id'] as int,
                              {'name': nameController.text.trim()},
                            );

                            if (mounted) {
                              Navigator.pop(context, true);
                            }
                          } catch (e) {
                            if (mounted) {
                              ScaffoldMessenger.of(this.context).showSnackBar(
                                SnackBar(
                                  content: Text('Failed to update camera: $e'),
                                  backgroundColor: AppTheme.error,
                                ),
                              );
                            }
                            setLocalState(() => isSubmitting = false);
                          }
                        },
                  child: Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );

    nameController.dispose();
    sourceController.dispose();
    groupController.dispose();

    if (updated == true) {
      await _loadInstances();
    }
  }

  List<String> _getAvailableGroups() {
    final groups = <String>{'All'};
    for (final group in _cameraGroups.values) {
      if (group.isNotEmpty) {
        groups.add(group);
      }
    }
    final sorted = groups.toList()..sort();
    sorted.remove('All');
    return ['All', ...sorted];
  }

  List<Map<String, dynamic>> _getFilteredInstances() {
    return _instances;
  }

  Map<String, List<Map<String, dynamic>>> _groupInstances(
    List<Map<String, dynamic>> instances,
  ) {
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final instance in instances) {
      final cameraConfigId = instance['camera_config_id'] as int?;
      final group = (_cameraGroups[cameraConfigId] ?? '').trim();
      final key = group.isEmpty ? 'Ungrouped' : group;
      grouped.putIfAbsent(key, () => <Map<String, dynamic>>[]).add(instance);
    }
    return grouped;
  }

  Map<String, int> _buildStatusCounts(List<Map<String, dynamic>> instances) {
    final counts = <String, int>{
      'running': 0,
      'paused': 0,
      'stopped': 0,
      'idle': 0,
      'other': 0,
    };
    for (final instance in instances) {
      final status = (instance['status'] as String? ?? 'other').toLowerCase();
      if (counts.containsKey(status)) {
        counts[status] = (counts[status] ?? 0) + 1;
      } else {
        counts['other'] = (counts['other'] ?? 0) + 1;
      }
    }
    return counts;
  }

  Future<void> _controlGroup(String action, List<Map<String, dynamic>> targets) async {
    if (targets.isEmpty) {
      return;
    }

    final requiresCameraConfig = action == 'start' || action == 'resume';
    final runnable = <Map<String, dynamic>>[];
    var skippedMissingConfig = 0;

    for (final instance in targets) {
      final cameraConfigId = instance['camera_config_id'] as int?;
      if (requiresCameraConfig && cameraConfigId == null) {
        skippedMissingConfig++;
      } else {
        runnable.add(instance);
      }
    }

    if (runnable.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'No cameras can "$action": $skippedMissingConfig missing camera configuration.',
            ),
            backgroundColor: AppTheme.warning,
          ),
        );
      }
      return;
    }

    var successCount = 0;
    var failureCount = 0;

    for (final instance in runnable) {
      final instanceId = instance['id'] as int;
      try {
        await _api.controlInstance(instanceId, action);
        successCount++;
      } catch (_) {
        failureCount++;
      }
    }

    await _loadInstances();

    if (mounted) {
      final message =
          '"$action" results: $successCount ok, $failureCount failed, $skippedMissingConfig skipped';
      final backgroundColor = failureCount > 0
          ? AppTheme.error
          : (skippedMissingConfig > 0 ? AppTheme.warning : AppTheme.success);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: backgroundColor,
        ),
      );
    }
  }

  Future<void> _deleteCameraInstance(Map<String, dynamic> instance) async {
    final instanceId = instance['id'] as int;
    final instanceName = instance['name'] as String? ?? 'Camera';
    final cameraConfigId = instance['camera_config_id'] as int?;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Delete Camera Instance'),
          content: Text(
            'Delete "$instanceName" and its saved camera configuration? This cannot be undone.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.errorContainer,
                foregroundColor: Theme.of(context).colorScheme.onErrorContainer,
              ),
              child: Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    try {
      await _api.deleteInstance(instanceId);
      if (cameraConfigId != null) {
        await _api.deleteCameraConfig(cameraConfigId);
      }

      await _loadInstances();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Deleted "$instanceName" successfully'),
            backgroundColor: AppTheme.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete "$instanceName": $e'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    }
  }

  Future<void> _exportCameraConfigs() async {
    final payload = {
      'version': 1,
      'exported_at': DateTime.now().toIso8601String(),
      'cameras': _instances.map((instance) {
        final cameraConfigId = instance['camera_config_id'] as int?;
        final cameraConfig = cameraConfigId == null ? null : _cameraConfigsById[cameraConfigId];
        return {
          'name': instance['name'],
          'group_name': cameraConfig?['group_name'],
          'source_type': cameraConfig?['source_type'],
          'source_url': cameraConfig?['source_url'],
          'enabled_models': instance['enabled_models'] ?? <String>[],
          'model_configs': instance['model_configs'] ?? <String, dynamic>{},
        };
      }).toList(),
    };

    final jsonText = const JsonEncoder.withIndent('  ').convert(payload);
    await Clipboard.setData(ClipboardData(text: jsonText));

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Camera configuration JSON copied to clipboard'),
          backgroundColor: AppTheme.success,
        ),
      );
    }
  }

  Future<void> _downloadCameraConfigs() async {
    final payload = {
      'version': 1,
      'exported_at': DateTime.now().toIso8601String(),
      'cameras': _instances.map((instance) {
        final cameraConfigId = instance['camera_config_id'] as int?;
        final cameraConfig = cameraConfigId == null ? null : _cameraConfigsById[cameraConfigId];
        return {
          'name': instance['name'],
          'group_name': cameraConfig?['group_name'],
          'source_type': cameraConfig?['source_type'],
          'source_url': cameraConfig?['source_url'],
          'enabled_models': instance['enabled_models'] ?? <String>[],
          'model_configs': instance['model_configs'] ?? <String, dynamic>{},
        };
      }).toList(),
    };

    final jsonText = const JsonEncoder.withIndent('  ').convert(payload);
    final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    await downloadJsonFile('camera-configs-$timestamp.json', jsonText);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Camera configuration JSON download started'),
          backgroundColor: AppTheme.success,
        ),
      );
    }
  }

  String _csvEscape(String value) {
    final escaped = value.replaceAll('"', '""');
    return '"$escaped"';
  }

  String _truncateErrorMessage(String input, {int maxChars = 180}) {
    if (input.length <= maxChars) {
      return input;
    }
    return '${input.substring(0, maxChars)}...';
  }

  String _formatBatchImportError(Object error) {
    if (error is ApiException) {
      if (error.statusCode == 404) {
        return 'Batch import endpoint is unavailable (404). Rebuild/restart backend and try again.';
      }
      if (error.statusCode >= 500) {
        return 'Backend batch import failed (server error ${error.statusCode}). Please retry.';
      }
      final message = _truncateErrorMessage(error.message.replaceAll('\n', ' '));
      return 'Batch import failed (${error.statusCode}): $message';
    }

    final message = error.toString().toLowerCase();
    if (message.contains('connection') || message.contains('network') || message.contains('timeout')) {
      return 'Cannot reach backend batch import endpoint. Check backend container and network, then retry.';
    }

    return 'Batch import failed: ${_truncateErrorMessage(error.toString())}';
  }

  Future<void> _downloadLastImportReportJson() async {
    if (_lastImportReport == null) {
      return;
    }
    final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    final text = const JsonEncoder.withIndent('  ').convert(_lastImportReport);
    await downloadTextFile(
      'import-report-$timestamp.json',
      text,
      mimeType: 'application/json;charset=utf-8',
    );
  }

  Future<void> _downloadLastImportReportCsv() async {
    if (_lastImportReport == null) {
      return;
    }

    final rows = (_lastImportReport!['rows'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList();

    final buffer = StringBuffer();
    buffer.writeln('index,name,action,attempts,reason');
    for (final row in rows) {
      final index = '${row['index'] ?? ''}';
      final name = _csvEscape('${row['name'] ?? ''}');
      final action = _csvEscape('${row['action'] ?? ''}');
      final attempts = '${row['attempts'] ?? ''}';
      final reason = _csvEscape('${row['reason'] ?? ''}');
      buffer.writeln('$index,$name,$action,$attempts,$reason');
    }

    final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    await downloadTextFile(
      'import-report-$timestamp.csv',
      buffer.toString(),
      mimeType: 'text/csv;charset=utf-8',
    );
  }

  void _openLastImportReportDialog() {
    final report = _lastImportReport;
    if (report == null) {
      return;
    }

    final summary = Map<String, dynamic>.from(report['summary'] as Map? ?? <String, dynamic>{});
    final rows = (report['rows'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList();
    final mode = (report['mode'] as String?) ?? 'tolerant';
    final strategy = (report['conflict_strategy'] as String?) ?? 'skip';

    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Last Import Report'),
          content: SizedBox(
            width: 720,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Summary: total ${summary['total'] ?? 0}, processed ${summary['processed'] ?? 0}, '
                  'created ${summary['created'] ?? 0}, renamed ${summary['renamed'] ?? 0}, '
                  'merged ${summary['merged'] ?? 0}, skipped ${summary['skipped'] ?? 0}',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text('Mode: $mode, conflict strategy: $strategy'),
                const SizedBox(height: 10),
                SizedBox(
                  height: 280,
                  child: ListView.builder(
                    itemCount: rows.length,
                    itemBuilder: (context, index) {
                      final row = rows[index];
                      return ListTile(
                        dense: true,
                        title: Text('#${row['index'] ?? ''} ${row['name'] ?? '-'}'),
                        subtitle: Text(
                          '${row['action'] ?? '-'} (attempts ${row['attempts'] ?? 0}): ${row['reason'] ?? '-'}',
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Close'),
            ),
          ],
        );
      },
    );
  }

  List<dynamic> _parseImportCameras(String rawInput) {
    final decoded = jsonDecode(rawInput);
    if (decoded is Map<String, dynamic> && decoded['cameras'] is List<dynamic>) {
      return decoded['cameras'] as List<dynamic>;
    }
    if (decoded is List<dynamic>) {
      return decoded;
    }
    throw const FormatException('Invalid JSON shape for camera import');
  }

  Map<String, dynamic>? _normalizeImportCamera(dynamic camera) {
    if (camera is! Map<String, dynamic>) {
      return null;
    }

    final name = (camera['name'] as String?)?.trim();
    final sourceType = (camera['source_type'] as String?)?.trim();
    final sourceUrl = (camera['source_url'] as String?)?.trim();
    if (name == null || sourceType == null || sourceUrl == null) {
      return null;
    }

    return {
      'name': name,
      'group_name': (camera['group_name'] as String?)?.trim(),
      'source_type': sourceType,
      'source_url': sourceUrl,
      'enabled_models': List<String>.from(camera['enabled_models'] as List? ?? <String>[]),
      'model_configs': Map<String, dynamic>.from(
        camera['model_configs'] as Map? ?? <String, dynamic>{},
      ),
    };
  }

  String _generateUniqueCameraName(String baseName, Set<String> usedLowerNames) {
    var candidate = baseName;
    var suffix = 1;
    while (usedLowerNames.contains(candidate.toLowerCase())) {
      candidate = '$baseName ($suffix)';
      suffix++;
    }
    return candidate;
  }

  Map<String, dynamic> _buildImportPreview(
    List<dynamic> cameras, {
    required String conflictStrategy,
  }) {
    final usedNames = _cameraConfigsById.values
        .map((cfg) => ((cfg['name'] as String?) ?? '').toLowerCase())
        .toSet();
    final previewRows = <Map<String, String>>[];
    var creatable = 0;
    var renamed = 0;
    var merged = 0;
    var skipped = 0;

    for (var i = 0; i < cameras.length; i++) {
      final normalized = _normalizeImportCamera(cameras[i]);
      if (normalized == null) {
        skipped++;
        previewRows.add({
          'name': 'Row ${i + 1}',
          'status': 'skip',
          'reason': 'Missing required fields',
        });
        continue;
      }

      final name = normalized['name'] as String;
      final lowerName = name.toLowerCase();
      if (usedNames.contains(lowerName)) {
        if (conflictStrategy == 'skip') {
          skipped++;
          previewRows.add({
            'name': name,
            'status': 'skip',
            'reason': 'Already exists or duplicate',
          });
          continue;
        }

        if (conflictStrategy == 'merge') {
          merged++;
          previewRows.add({
            'name': name,
            'status': 'merge',
            'reason': 'Will merge into existing camera',
          });
          continue;
        }

        final renamedName = _generateUniqueCameraName(name, usedNames);
        usedNames.add(renamedName.toLowerCase());
        creatable++;
        renamed++;
        previewRows.add({
          'name': '$name -> $renamedName',
          'status': 'rename',
          'reason': 'Will auto-rename on conflict',
        });
        continue;
      }

      usedNames.add(lowerName);
      creatable++;
      previewRows.add({
        'name': name,
        'status': 'create',
        'reason': 'Valid',
      });
    }

    return {
      'creatable': creatable,
      'renamed': renamed,
      'merged': merged,
      'skipped': skipped,
      'rows': previewRows,
    };
  }

  Future<void> _openImportConfigsDialog() async {
    final controller = TextEditingController();
    bool isSubmitting = false;
    String conflictStrategy = 'skip';
    bool strictMode = false;
    String? previewSummary;
    List<Map<String, String>> previewRows = const [];

    final shouldImport = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setLocalState) {
            return AlertDialog(
              title: Text('Import Camera Configurations'),
              content: SizedBox(
                width: 640,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Paste JSON with shape {"cameras": [...]} or a raw array [...].',
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: controller,
                      minLines: 10,
                      maxLines: 20,
                      decoration: const InputDecoration(
                        hintText: '{"cameras": [{"name":"Cam 1", ...}]}',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Text('On name conflict:'),
                        const SizedBox(width: 8),
                        SegmentedButton<String>(
                          segments: const [
                            ButtonSegment<String>(value: 'skip', label: Text('Skip')),
                            ButtonSegment<String>(value: 'rename', label: Text('Rename')),
                            ButtonSegment<String>(value: 'merge', label: Text('Merge')),
                          ],
                          selected: {conflictStrategy},
                          onSelectionChanged: (selection) {
                            setLocalState(() => conflictStrategy = selection.first);
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: Text('Strict mode (fail-fast on first row error)'),
                      subtitle: Text('Stops remaining import rows when one row fails or is skipped due to an error.'),
                      value: strictMode,
                      onChanged: (value) {
                        setLocalState(() => strictMode = value);
                      },
                    ),
                    if (previewSummary != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          previewSummary!,
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 160,
                        child: ListView.builder(
                          itemCount: previewRows.length,
                          itemBuilder: (context, index) {
                            final row = previewRows[index];
                            final status = row['status'] ?? '';
                            final scheme = Theme.of(context).colorScheme;
                            final color = status == 'create'
                                ? AppTheme.success
                                : status == 'rename'
                                    ? scheme.primary
                                    : status == 'merge'
                                        ? scheme.tertiary
                                        : AppTheme.warning;
                            return ListTile(
                              dense: true,
                              leading: Icon(
                                status == 'create'
                                    ? Icons.check_circle_outline_rounded
                                    : status == 'rename'
                                        ? Icons.drive_file_rename_outline_rounded
                                : status == 'merge'
                                  ? Icons.merge_type_rounded
                                    : Icons.info_outline_rounded,
                                size: 18,
                                color: color,
                              ),
                              title: Text(row['name'] ?? '-'),
                              subtitle: Text(row['reason'] ?? '-'),
                            );
                          },
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSubmitting ? null : () => Navigator.pop(context, false),
                  child: Text('Cancel'),
                ),
                OutlinedButton(
                  onPressed: isSubmitting
                      ? null
                      : () {
                          final raw = controller.text.trim();
                          if (raw.isEmpty) {
                            return;
                          }
                          try {
                            final cameras = _parseImportCameras(raw);
                            final preview = _buildImportPreview(
                              cameras,
                              conflictStrategy: conflictStrategy,
                            );
                            setLocalState(() {
                              previewSummary =
                                  'Preview: ${preview['creatable']} create, ${preview['renamed']} rename, ${preview['merged']} merge, ${preview['skipped']} skip, ${cameras.length} total (${strictMode ? 'strict' : 'tolerant'} mode)';
                              previewRows = List<Map<String, String>>.from(
                                preview['rows'] as List<dynamic>,
                              );
                            });
                          } catch (e) {
                            setLocalState(() {
                              previewSummary = 'Preview failed: $e';
                              previewRows = const [];
                            });
                          }
                        },
                  child: Text('Preview'),
                ),
                FilledButton(
                  onPressed: isSubmitting
                      ? null
                      : () async {
                          if (controller.text.trim().isEmpty) {
                            return;
                          }
                          setLocalState(() => isSubmitting = true);
                          Navigator.pop(context, true);
                        },
                  child: Text('Import'),
                ),
              ],
            );
          },
        );
      },
    );

    if (shouldImport != true) {
      controller.dispose();
      return;
    }

    final rawInput = controller.text.trim();
    controller.dispose();

    final progressValue = ValueNotifier<double>(0);
    final progressText = ValueNotifier<String>('Preparing import...');
    final importCancelled = ValueNotifier<bool>(false);

    try {
      final cameras = _parseImportCameras(rawInput);
      final total = cameras.length;

      if (mounted) {
        showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) {
            return AlertDialog(
              title: Text('Importing Cameras'),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ValueListenableBuilder<String>(
                      valueListenable: progressText,
                      builder: (context, value, _) => Text(value),
                    ),
                    const SizedBox(height: 12),
                    ValueListenableBuilder<double>(
                      valueListenable: progressValue,
                      builder: (context, value, _) => LinearProgressIndicator(value: value),
                    ),
                    const SizedBox(height: 12),
                    ValueListenableBuilder<bool>(
                      valueListenable: importCancelled,
                      builder: (context, cancelled, _) => TextButton.icon(
                        onPressed: cancelled
                            ? null
                            : () {
                                importCancelled.value = true;
                              },
                        icon: const Icon(Icons.cancel_rounded),
                        label: Text(cancelled ? 'Cancelling...' : 'Cancel Import'),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      }

      if (importCancelled.value) {
        if (mounted) {
          Navigator.of(context, rootNavigator: true).pop();
        }
        progressValue.dispose();
        progressText.dispose();
        importCancelled.dispose();
        return;
      }

      progressText.value = 'Submitting batch import to backend...';
      progressValue.value = total == 0 ? 1 : 0.2;

      final batchResult = await _api.importInstancesBatch({
        'cameras': cameras,
        'conflict_strategy': conflictStrategy,
        'mode': strictMode ? 'strict' : 'tolerant',
      });

      progressText.value = 'Applying import results...';
      progressValue.value = 0.85;

      final summary = Map<String, dynamic>.from(
        batchResult['summary'] as Map? ?? <String, dynamic>{},
      );
      final createdCount = int.tryParse('${summary['created'] ?? 0}') ?? 0;
      final renamedCount = int.tryParse('${summary['renamed'] ?? 0}') ?? 0;
      final mergedCount = int.tryParse('${summary['merged'] ?? 0}') ?? 0;
      final skippedCount = int.tryParse('${summary['skipped'] ?? 0}') ?? 0;
      final processedCount = int.tryParse('${summary['processed'] ?? 0}') ?? 0;
      final backendRows = (batchResult['rows'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .toList();

      progressText.value = 'Finalizing import...';
      progressValue.value = 1;

      await _loadInstances();
      _lastImportReport = {
        'timestamp': batchResult['timestamp'] ?? DateTime.now().toIso8601String(),
        'conflict_strategy': batchResult['conflict_strategy'] ?? conflictStrategy,
        'mode': batchResult['mode'] ?? (strictMode ? 'strict' : 'tolerant'),
        'summary': {
          'total': int.tryParse('${summary['total'] ?? cameras.length}') ?? cameras.length,
          'processed': processedCount,
          'created': createdCount,
          'renamed': renamedCount,
          'merged': mergedCount,
          'skipped': skippedCount,
          'cancelled': summary['cancelled'] == true,
          'committed': summary['committed'] == true,
          'rolled_back': summary['rolled_back'] == true,
        },
        'rows': backendRows,
      };
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      progressValue.dispose();
      progressText.dispose();
      importCancelled.dispose();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Import complete: processed $processedCount/${cameras.length}, created $createdCount, renamed $renamedCount, merged $mergedCount, skipped $skippedCount',
            ),
            backgroundColor: AppTheme.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      progressValue.dispose();
      progressText.dispose();
      importCancelled.dispose();
      if (mounted) {
        final userMessage = _formatBatchImportError(e);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(userMessage),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final filteredInstances = _getFilteredInstances();

    if (_isLoading) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: colorScheme.primary),
              const SizedBox(height: 16),
              Text('Loading pipeline instances...'),
            ],
          ),
        ),
      );
    }

    if (_error != null) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 64, color: colorScheme.error),
              const SizedBox(height: 16),
              Text('Error: $_error'),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _loadInstances,
                child: Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      body: Column(
        children: [
          _buildHeader(colorScheme),
          Expanded(
            child: filteredInstances.isEmpty
                ? ((_selectedGroupFilter != 'All' || _searchQuery.trim().isNotEmpty)
                    ? _buildNoResultsForGroup()
                    : _buildEmptyState())
              : _groupedView
                ? _buildGroupedView(filteredInstances)
                : _buildGrid(),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(ColorScheme colorScheme) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final groups = _getAvailableGroups();
    final filteredInstances = _getFilteredInstances();
    final groupLabel = _selectedGroupFilter == 'All' ? 'all groups' : _selectedGroupFilter;
    final statusCounts = _buildStatusCounts(filteredInstances);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(bottom: BorderSide(color: colorScheme.outlineVariant)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.grid_view_rounded,
                  color: colorScheme.onPrimaryContainer,
                  size: 20,
                ),
              ),
              Text(
                'Monitor',
                style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  border: Border.all(color: colorScheme.primaryContainer),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${filteredInstances.length} / ${_instances.length} loaded (total $_instancesTotal)',
                  style: TextStyle(
                    color: colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ),
              _buildStatusChip('Run', statusCounts['running'] ?? 0, AppTheme.success),
              _buildStatusChip('Pause', statusCounts['paused'] ?? 0, AppTheme.warning),
              _buildStatusChip('Stop', statusCounts['stopped'] ?? 0, AppTheme.error),
              _buildStatusChip('Idle', statusCounts['idle'] ?? 0, colorScheme.primary),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilledButton.icon(
                onPressed: _openAddCameraDialog,
                icon: const Icon(Icons.add_rounded),
                label: Text('Add Camera'),
              ),
              OutlinedButton.icon(
                onPressed: _openImportConfigsDialog,
                icon: const Icon(Icons.upload_file_rounded, size: 16),
                label: Text('Import JSON'),
              ),
              OutlinedButton.icon(
                onPressed: _lastImportReport == null ? null : _openLastImportReportDialog,
                icon: const Icon(Icons.visibility_outlined, size: 16),
                label: Text('View Report'),
              ),
              PopupMenuButton<String>(
                tooltip: 'Download latest import report',
                enabled: _lastImportReport != null,
                onSelected: (value) async {
                  if (value == 'json') {
                    await _downloadLastImportReportJson();
                  } else if (value == 'csv') {
                    await _downloadLastImportReportCsv();
                  }
                },
                itemBuilder: (context) => const [
                  PopupMenuItem<String>(
                    value: 'json',
                    child: Text('Download Import Report JSON'),
                  ),
                  PopupMenuItem<String>(
                    value: 'csv',
                    child: Text('Download Import Report CSV'),
                  ),
                ],
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.summarize_outlined, size: 18),
                      SizedBox(width: 6),
                      Text('Import Report'),
                    ],
                  ),
                ),
              ),
              OutlinedButton.icon(
                onPressed: _instances.isEmpty ? null : _downloadCameraConfigs,
                icon: const Icon(Icons.file_download_rounded, size: 16),
                label: Text('Download JSON'),
              ),
              OutlinedButton.icon(
                onPressed: _instances.isEmpty ? null : _exportCameraConfigs,
                icon: const Icon(Icons.download_rounded, size: 16),
                label: Text('Copy JSON'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 180,
                child: DropdownButtonFormField<String>(
                  initialValue: groups.contains(_selectedGroupFilter) ? _selectedGroupFilter : 'All',
                  isDense: true,
                  decoration: const InputDecoration(
                    isDense: true,
                    labelText: 'Group',
                    border: OutlineInputBorder(),
                  ),
                  items: groups
                      .map(
                        (group) => DropdownMenuItem<String>(
                          value: group,
                          child: Text(group == 'All' ? 'All Groups' : group),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => _selectedGroupFilter = value);
                      _loadInstances();
                    }
                  },
                ),
              ),
              SizedBox(
                width: 180,
                child: DropdownButtonFormField<String>(
                  initialValue: _sortBy,
                  isDense: true,
                  decoration: const InputDecoration(
                    isDense: true,
                    labelText: 'Sort By',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'created_at', child: Text('Created Time')),
                    DropdownMenuItem(value: 'name', child: Text('Instance Name')),
                    DropdownMenuItem(value: 'status', child: Text('Status')),
                    DropdownMenuItem(value: 'camera_name', child: Text('Camera Name')),
                    DropdownMenuItem(value: 'group_name', child: Text('Group Name')),
                  ],
                  onChanged: (value) {
                    if (value == null) {
                      return;
                    }
                    setState(() => _sortBy = value);
                    _loadInstances();
                  },
                ),
              ),
              SizedBox(
                width: 120,
                child: DropdownButtonFormField<String>(
                  initialValue: _sortOrder,
                  isDense: true,
                  decoration: const InputDecoration(
                    isDense: true,
                    labelText: 'Order',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'desc', child: Text('Desc')),
                    DropdownMenuItem(value: 'asc', child: Text('Asc')),
                  ],
                  onChanged: (value) {
                    if (value == null) {
                      return;
                    }
                    setState(() => _sortOrder = value);
                    _loadInstances();
                  },
                ),
              ),
              SizedBox(
                width: 240,
                child: TextField(
                  controller: _searchController,
                  onChanged: (value) {
                    setState(() => _searchQuery = value);
                    _scheduleSearchReload();
                  },
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Search name/group',
                    prefixIcon: const Icon(Icons.search_rounded, size: 18),
                    suffixIcon: _searchQuery.isEmpty
                        ? null
                        : IconButton(
                            onPressed: () {
                              setState(() {
                                _searchQuery = '';
                                _searchController.clear();
                              });
                              _loadInstances();
                            },
                            icon: const Icon(Icons.close_rounded, size: 16),
                          ),
                  ),
                ),
              ),
              SizedBox(
                width: 220,
                child: SegmentedButton<bool>(
                  style: SegmentedButton.styleFrom(
                    backgroundColor: colorScheme.surface,
                    foregroundColor: colorScheme.onSurface,
                    selectedBackgroundColor: colorScheme.primaryContainer,
                    selectedForegroundColor: colorScheme.onPrimaryContainer,
                  ),
                  segments: const [
                    ButtonSegment<bool>(
                      value: false,
                      label: Text(
                        'Grid',
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    ButtonSegment<bool>(
                      value: true,
                      label: Text(
                        'Grouped',
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                  selected: {_groupedView},
                  onSelectionChanged: (selection) {
                    setState(() => _groupedView = selection.first);
                  },
                  showSelectedIcon: false,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh_rounded),
                onPressed: _loadInstances,
                tooltip: 'Refresh instances',
              ),
              OutlinedButton.icon(
                onPressed: (!_hasMoreInstances || _isLoadingMoreInstances) ? null : _loadMoreInstances,
                icon: _isLoadingMoreInstances
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.unfold_more_rounded, size: 16),
                label: Text(_hasMoreInstances ? 'Load More' : 'All Loaded'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (_groupedView)
                OutlinedButton.icon(
                  onPressed: () {
                    final grouped = _groupInstances(filteredInstances);
                    setState(() {
                      for (final key in grouped.keys) {
                        _expandedGroups[key] = true;
                        _groupRenderLimits[key] = _groupRenderChunkSize;
                      }
                    });
                  },
                  icon: const Icon(Icons.unfold_more_rounded, size: 16),
                  label: Text('Expand All'),
                ),
              if (_groupedView)
                OutlinedButton.icon(
                  onPressed: () {
                    final grouped = _groupInstances(filteredInstances);
                    setState(() {
                      for (final key in grouped.keys) {
                        _expandedGroups[key] = false;
                      }
                    });
                  },
                  icon: const Icon(Icons.unfold_less_rounded, size: 16),
                  label: Text('Collapse All'),
                ),
              OutlinedButton.icon(
                onPressed: filteredInstances.isEmpty
                    ? null
                    : () => _controlGroup('start', filteredInstances),
                icon: const Icon(Icons.play_arrow_rounded, size: 16),
                label: Text('Start $groupLabel'),
              ),
              OutlinedButton.icon(
                onPressed: filteredInstances.isEmpty
                    ? null
                    : () => _controlGroup('stop', filteredInstances),
                icon: const Icon(Icons.stop_rounded, size: 16),
                label: Text('Stop $groupLabel'),
              ),
              OutlinedButton.icon(
                onPressed: filteredInstances.isEmpty
                    ? null
                    : () => _controlGroup('pause', filteredInstances),
                icon: const Icon(Icons.pause_rounded, size: 16),
                label: Text('Pause $groupLabel'),
              ),
              OutlinedButton.icon(
                onPressed: filteredInstances.isEmpty
                    ? null
                    : () => _controlGroup('resume', filteredInstances),
                icon: const Icon(Icons.play_circle_outline_rounded, size: 16),
                label: Text('Resume $groupLabel'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.videocam_off_rounded,
              size: 48,
              color: colorScheme.primary.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'No pipeline instances',
            style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            'Add a camera or import configs to start live monitoring',
            style: textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _openAddCameraDialog,
            icon: const Icon(Icons.add_rounded),
            label: const Text('Add Camera'),
          ),
        ],
      ),
    );
  }

  Widget _buildGrid() {
    final filteredInstances = _getFilteredInstances();
    final runningInstances = filteredInstances
        .where((instance) => (instance['status'] as String?)?.toLowerCase() == 'running')
        .toList();
    final inactiveInstances = filteredInstances
        .where((instance) => (instance['status'] as String?)?.toLowerCase() != 'running')
        .toList();

    return ListView(
      padding: const EdgeInsets.all(8),
      children: [
        if (runningInstances.length == 1) ...[
          Text(
            'Active Camera',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          AspectRatio(
            aspectRatio: 16 / 9,
            child: _buildInstanceTile(runningInstances.first),
          ),
          const SizedBox(height: 12),
        ] else if (runningInstances.length > 1) ...[
          Text(
            'Active Cameras (${runningInstances.length})',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          _buildInstanceGridSection(runningInstances),
          const SizedBox(height: 12),
        ],
        if (inactiveInstances.isNotEmpty) ...[
          Text(
            runningInstances.isEmpty
                ? 'Cameras (${inactiveInstances.length})'
                : 'Inactive Cameras (${inactiveInstances.length})',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          _buildInstanceGridSection(inactiveInstances),
        ],
      ],
    );
  }

  Widget _buildInstanceGridSection(List<Map<String, dynamic>> instances) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 8.0;
        const minTileWidth = 360.0;
        final possibleColumns = (constraints.maxWidth / minTileWidth).floor();
        final dynamicColumns = possibleColumns < 1 ? 1 : possibleColumns;
        final crossAxisCount = instances.length < dynamicColumns ? instances.length : dynamicColumns;

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: spacing,
            mainAxisSpacing: spacing,
            childAspectRatio: 16 / 10,
          ),
          itemCount: instances.length,
          itemBuilder: (context, index) {
            final instance = instances[index];
            return _buildInstanceTile(instance);
          },
        );
      },
    );
  }

  Widget _buildNoResultsForGroup() {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.filter_alt_off_rounded,
            size: 56,
            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 12),
          Text(
            _searchQuery.trim().isEmpty
                ? 'No cameras in "$_selectedGroupFilter"'
                : 'No cameras match "${_searchQuery.trim()}"',
            style: TextStyle(
              fontSize: 16,
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => setState(() => _selectedGroupFilter = 'All'),
            child: Text('Show all groups'),
          ),
        ],
      ),
    );
  }

  Widget _buildGroupedView(List<Map<String, dynamic>> filteredInstances) {
    final grouped = _groupInstances(filteredInstances);
    final groupKeys = grouped.keys.toList()..sort();

    return ListView.builder(
      padding: const EdgeInsets.all(8.0),
      itemCount: groupKeys.length,
      itemBuilder: (context, index) {
        final groupName = groupKeys[index];
        final groupInstances = grouped[groupName] ?? <Map<String, dynamic>>[];
        final isExpanded = _expandedGroups[groupName] ?? false;
        final groupStatus = _buildStatusCounts(groupInstances);

        return LayoutBuilder(
          builder: (context, constraints) {
            const spacing = 8.0;
            const minTileWidth = 360.0;
            final possibleColumns = (constraints.maxWidth / minTileWidth).floor();
            final dynamicColumns = possibleColumns < 1 ? 1 : possibleColumns;
            final crossAxisCount = groupInstances.length < dynamicColumns
                ? groupInstances.length
                : dynamicColumns;

            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          groupName,
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '${groupInstances.length} camera(s)',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.primary,
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        _buildStatusChip('Run', groupStatus['running'] ?? 0, AppTheme.success),
                        const SizedBox(width: 6),
                        _buildStatusChip('Pause', groupStatus['paused'] ?? 0, AppTheme.warning),
                        const SizedBox(width: 6),
                        _buildStatusChip('Stop', groupStatus['stopped'] ?? 0, AppTheme.error),
                        const Spacer(),
                        TextButton.icon(
                          onPressed: () => _controlGroup('start', groupInstances),
                          icon: const Icon(Icons.play_arrow_rounded, size: 16),
                          label: Text('Start Group'),
                        ),
                        TextButton.icon(
                          onPressed: () => _controlGroup('stop', groupInstances),
                          icon: const Icon(Icons.stop_rounded, size: 16),
                          label: Text('Stop Group'),
                        ),
                        TextButton.icon(
                          onPressed: () => _controlGroup('pause', groupInstances),
                          icon: const Icon(Icons.pause_rounded, size: 16),
                          label: Text('Pause Group'),
                        ),
                        TextButton.icon(
                          onPressed: () => _controlGroup('resume', groupInstances),
                          icon: const Icon(Icons.play_circle_outline_rounded, size: 16),
                          label: Text('Resume Group'),
                        ),
                        IconButton(
                          onPressed: () {
                            setState(() {
                              final nextExpanded = !isExpanded;
                              _expandedGroups[groupName] = nextExpanded;
                              if (nextExpanded) {
                                _groupRenderLimits[groupName] = _groupRenderChunkSize;
                              }
                            });
                          },
                          icon: Icon(
                            isExpanded
                                ? Icons.expand_less_rounded
                                : Icons.expand_more_rounded,
                          ),
                          tooltip: isExpanded ? 'Collapse group' : 'Expand group',
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (isExpanded)
                      Builder(
                        builder: (context) {
                          final currentLimit = _groupRenderLimits[groupName] ?? _groupRenderChunkSize;
                          final visibleCount = currentLimit < groupInstances.length
                              ? currentLimit
                              : groupInstances.length;
                          final visibleInstances = groupInstances.take(visibleCount).toList();

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              GridView.builder(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: crossAxisCount,
                                  crossAxisSpacing: spacing,
                                  mainAxisSpacing: spacing,
                                  childAspectRatio: 16 / 10,
                                ),
                                itemCount: visibleInstances.length,
                                itemBuilder: (context, tileIndex) {
                                  return _buildInstanceTile(visibleInstances[tileIndex]);
                                },
                              ),
                              if (visibleCount < groupInstances.length)
                                Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Row(
                                    children: [
                                      Text(
                                        'Showing $visibleCount of ${groupInstances.length}',
                                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      OutlinedButton.icon(
                                        onPressed: () {
                                          setState(() {
                                            final next = (_groupRenderLimits[groupName] ?? _groupRenderChunkSize) +
                                                _groupRenderChunkSize;
                                            _groupRenderLimits[groupName] = next;
                                          });
                                        },
                                        icon: const Icon(Icons.expand_more_rounded, size: 16),
                                        label: Text('Load More Tiles'),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          );
                        },
                      )
                    else
                      Text(
                        'Group collapsed. Expand to render ${groupInstances.length} camera tiles.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildInstanceTile(Map<String, dynamic> instance) {
    final instanceId = instance['id'] as int;
    final name = instance['name'] as String;
    final status = instance['status'] as String;
    final frame = _instanceFrames[instanceId];
    final results = _instanceResults[instanceId];
    final showOverlay = _instanceShowOverlay[instanceId] ?? true;
    final lastFrame = _lastFrameAt[instanceId];
    final staleSeconds = lastFrame == null ? null : DateTime.now().difference(lastFrame).inSeconds;
    final isFeedStale = status == 'running' && staleSeconds != null && staleSeconds >= 12;
    final reconnectAttempts = _multiWs.feedReconnectAttempts(instanceId);
    final feedConnected = _multiWs.isFeedConnected(instanceId);
    final groupName = _cameraGroups[instance['camera_config_id'] as int? ?? -1] ?? '';
    final colorScheme = Theme.of(context).colorScheme;
    final statusColor = _getStatusColor(status);

    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: statusColor.withValues(alpha: status == 'running' ? 0.55 : 0.25),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              border: Border(bottom: BorderSide(color: colorScheme.outlineVariant)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: colorScheme.onSurface,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (groupName.isNotEmpty)
                        Text(
                          groupName,
                          style: TextStyle(
                            fontSize: 10,
                            color: colorScheme.onSurfaceVariant,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: statusColor,
                    shape: BoxShape.circle,
                    boxShadow: status == 'running'
                        ? [
                            BoxShadow(
                              color: statusColor.withValues(alpha: 0.5),
                              blurRadius: 6,
                            ),
                          ]
                        : null,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  status.toUpperCase(),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: statusColor,
                  ),
                ),
              ],
            ),
          ),
          // Video area
          Expanded(
            child: Container(
              color: colorScheme.surfaceContainerHighest,
              child: frame != null
                  ? Stack(
                      children: [
                        Center(
                          child: Image.memory(
                            frame,
                            fit: BoxFit.contain,
                            gaplessPlayback: true,
                          ),
                        ),
                        if (showOverlay && results != null)
                          _buildResultsOverlay(results),
                      ],
                    )
                  : Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            status == 'running'
                                ? Icons.hourglass_empty
                                : Icons.videocam_off,
                            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.55),
                            size: 36,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            status == 'running'
                                ? (isFeedStale
                                    ? 'Feed stale (${staleSeconds}s)'
                                    : (feedConnected ? 'Waiting for frames...' : 'Reconnecting feed...'))
                                : 'Not running',
                            style: TextStyle(
                              color: colorScheme.onSurfaceVariant,
                              fontSize: 11,
                            ),
                          ),
                          if (status == 'running' && reconnectAttempts > 0)
                            Text(
                              'retry $reconnectAttempts',
                              style: TextStyle(
                                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.75),
                                fontSize: 10,
                              ),
                            ),
                        ],
                      ),
                    ),
            ),
          ),
          // Controls
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              border: Border(top: BorderSide(color: colorScheme.outlineVariant)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildControlButton(
                  Icons.play_arrow,
                  'Start',
                  status != 'running',
                  () => _controlInstance(instanceId, 'start'),
                ),
                _buildControlButton(
                  Icons.stop,
                  'Stop',
                  status == 'running' || status == 'paused',
                  () => _controlInstance(instanceId, 'stop'),
                ),
                _buildControlButton(
                  status == 'paused' ? Icons.play_circle_fill : Icons.pause_circle_filled,
                  status == 'paused' ? 'Resume' : 'Pause',
                  status == 'running' || status == 'paused',
                  () => _controlInstance(instanceId, status == 'paused' ? 'resume' : 'pause'),
                ),
                _buildControlButton(
                  Icons.tune_rounded,
                  'Assign Models',
                  true,
                  () => _openModelAssignmentDialog(instance),
                ),
                _buildControlButton(
                  Icons.settings_input_component_rounded,
                  'Configure Models',
                  true,
                  () => _openModelConfigDialog(instance),
                ),
                _buildControlButton(
                  Icons.edit_rounded,
                  'Edit Camera',
                  true,
                  () => _openEditCameraDialog(instance),
                ),
                _buildControlButton(
                  Icons.delete_forever_rounded,
                  'Delete',
                  true,
                  () => _deleteCameraInstance(instance),
                ),
                _buildControlButton(
                  showOverlay ? Icons.layers : Icons.layers_clear,
                  'Overlay',
                  true,
                  () => setState(() => _instanceShowOverlay[instanceId] = !showOverlay),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControlButton(IconData icon, String tooltip, bool enabled, VoidCallback onPressed) {
    final colorScheme = Theme.of(context).colorScheme;

    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: enabled ? onPressed : null,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(
            icon,
            size: 18,
            color: enabled
                ? colorScheme.primary
                : colorScheme.onSurfaceVariant.withValues(alpha: 0.35),
          ),
        ),
      ),
    );
  }

  Widget _buildResultsOverlay(Map<String, dynamic> results) {
    final colorScheme = Theme.of(context).colorScheme;
    final timing = results['timing'] as Map<String, dynamic>? ?? {};
    final detectionResults = results['results'] as Map<String, dynamic>? ?? {};

    return Positioned(
      top: 8,
      left: 8,
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: colorScheme.inverseSurface.withValues(alpha: 0.78),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Frame #${results['frame_id'] ?? '-'}',
              style: TextStyle(
                color: colorScheme.onInverseSurface,
                fontSize: 8,
                fontWeight: FontWeight.bold,
              ),
            ),
            ...detectionResults.entries.map(
              (entry) => Text(
                '${entry.key}: ${_formatCompactResult(entry.value)} (${timing[entry.key] ?? '-'}ms)',
                style: TextStyle(
                  color: colorScheme.onInverseSurface,
                  fontSize: 8,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatCompactResult(dynamic result) {
    if (result is Map) {
      return '${result.length} items';
    }
    if (result is List) {
      return '${result.length} det';
    }
    return result.toString();
  }

  Widget _buildStatusChip(String label, int value, Color color) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$label: $value',
        style: textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ) ??
            TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'running':
        return AppTheme.success;
      case 'stopped':
        return AppTheme.error;
      case 'paused':
        return AppTheme.warning;
      case 'idle':
        return Theme.of(context).colorScheme.primary;
      default:
        return Theme.of(context).colorScheme.outline;
    }
  }
}




