import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';

/// Custom exception for API errors
class ApiException implements Exception {
  final int statusCode;
  final String message;

  ApiException(this.statusCode, this.message);

  @override
  String toString() => 'ApiException($statusCode): $message';
}

/// REST API service for communicating with the backend
class ApiService {
  final http.Client _client = http.Client();

  /// Validates HTTP response and returns decoded JSON
  Map<String, dynamic> _handleJsonResponse(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (response.body.isEmpty) {
        return {};
      }
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw ApiException(response.statusCode, response.body);
  }

  /// Validates HTTP response and returns decoded JSON list
  List<dynamic> _handleJsonListResponse(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (response.body.isEmpty) {
        return [];
      }
      return jsonDecode(response.body) as List<dynamic>;
    }
    throw ApiException(response.statusCode, response.body);
  }

  // ============ Health ============

  Future<Map<String, dynamic>> checkHealth() async {
    final response = await _client.get(Uri.parse(AppConfig.healthUrl));
    return _handleJsonResponse(response);
  }

  // ============ Camera ============

  Future<List<dynamic>> getCameraConfigs() async {
    final response = await _client.get(Uri.parse(AppConfig.camerasUrl));
    return _handleJsonListResponse(response);
  }

  Future<Map<String, dynamic>> createCameraConfig(
      Map<String, dynamic> config) async {
    final response = await _client.post(
      Uri.parse(AppConfig.camerasUrl),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(config),
    );
    return _handleJsonResponse(response);
  }

  Future<void> deleteCameraConfig(int id) async {
    final response = await _client.delete(Uri.parse('${AppConfig.camerasUrl}/$id'));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(response.statusCode, response.body);
    }
  }

  Future<Map<String, dynamic>> updateCameraConfig(
    int id,
    Map<String, dynamic> config,
  ) async {
    final response = await _client.patch(
      Uri.parse('${AppConfig.camerasUrl}/$id'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(config),
    );
    return _handleJsonResponse(response);
  }

  Future<Map<String, dynamic>> getCameraSources() async {
    final response = await _client.get(Uri.parse(AppConfig.cameraSourcesUrl));
    return _handleJsonResponse(response);
  }

  // ============ ROI Zones ============

  Future<List<dynamic>> getROIZones({
    int? cameraConfigId,
    bool includeInactive = true,
  }) async {
    final queryParams = <String, String>{
      'include_inactive': '$includeInactive',
      if (cameraConfigId != null) 'camera_config_id': '$cameraConfigId',
    };
    final uri = Uri.parse('${AppConfig.apiBaseUrl}/api/roi/zones').replace(queryParameters: queryParams);
    final response = await _client.get(uri);
    return _handleJsonListResponse(response);
  }

  Future<Map<String, dynamic>> createROIZone(Map<String, dynamic> payload) async {
    final response = await _client.post(
      Uri.parse('${AppConfig.apiBaseUrl}/api/roi/zones'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    );
    return _handleJsonResponse(response);
  }

  Future<Map<String, dynamic>> updateROIZone(int zoneId, Map<String, dynamic> payload) async {
    final response = await _client.patch(
      Uri.parse('${AppConfig.apiBaseUrl}/api/roi/zones/$zoneId'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    );
    return _handleJsonResponse(response);
  }

  Future<void> deleteROIZone(int zoneId) async {
    final response = await _client.delete(Uri.parse('${AppConfig.apiBaseUrl}/api/roi/zones/$zoneId'));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(response.statusCode, response.body);
    }
  }

  // ============ Pipeline ============

  Future<Map<String, dynamic>> getPipelineStatus() async {
    final response =
        await _client.get(Uri.parse(AppConfig.pipelineStatusUrl));
    return _handleJsonResponse(response);
  }

  Future<Map<String, dynamic>> controlPipeline(
      Map<String, dynamic> command) async {
    final response = await _client.post(
      Uri.parse(AppConfig.pipelineControlUrl),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(command),
    );
    return _handleJsonResponse(response);
  }

  Future<Map<String, dynamic>> startPipeline(String cameraSource,
      {Map<String, dynamic>? config}) async {
    return controlPipeline({
      'action': 'start',
      'camera_source': cameraSource,
      'config': config ?? {},
    });
  }

  Future<Map<String, dynamic>> stopPipeline() async {
    return controlPipeline({'action': 'stop'});
  }

  // ============ Sessions ============

  Future<List<dynamic>> getSessions({int limit = 20, int offset = 0}) async {
    final response = await _client.get(
        Uri.parse('${AppConfig.sessionsUrl}?limit=$limit&offset=$offset'));
    return _handleJsonListResponse(response);
  }

  Future<Map<String, dynamic>> getSessionStats(int sessionId) async {
    final response =
        await _client.get(Uri.parse(AppConfig.sessionStatsUrl(sessionId)));
    return _handleJsonResponse(response);
  }

  // ============ Pipeline Instances ============

  Future<List<dynamic>> getInstances({String? statusFilter}) async {
    var url = AppConfig.instancesUrl;
    if (statusFilter != null) url += '?status_filter=$statusFilter';
    final response = await _client.get(Uri.parse(url));
    return _handleJsonListResponse(response);
  }

  Future<Map<String, dynamic>> getInstancesPaged({
    String? statusFilter,
    String? groupName,
    String? searchQuery,
    String sortBy = 'created_at',
    String sortOrder = 'desc',
    int limit = 100,
    int offset = 0,
  }) async {
    final queryParams = <String, String>{
      'limit': '$limit',
      'offset': '$offset',
      'sort_by': sortBy,
      'sort_order': sortOrder,
      if (statusFilter != null && statusFilter.isNotEmpty) 'status_filter': statusFilter,
      if (groupName != null && groupName.isNotEmpty) 'group_name': groupName,
      if (searchQuery != null && searchQuery.isNotEmpty) 'search_query': searchQuery,
    };
    final uri = Uri.parse('${AppConfig.instancesUrl}/paged').replace(queryParameters: queryParams);
    final response = await _client.get(uri);
    return _handleJsonResponse(response);
  }

  Future<Map<String, dynamic>> getInstance(int instanceId) async {
    final response = await _client.get(Uri.parse('${AppConfig.instancesUrl}/$instanceId'));
    return _handleJsonResponse(response);
  }

  Future<Map<String, dynamic>> updateInstance(
    int instanceId,
    Map<String, dynamic> updateData,
  ) async {
    final response = await _client.patch(
      Uri.parse('${AppConfig.instancesUrl}/$instanceId'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(updateData),
    );
    return _handleJsonResponse(response);
  }

  Future<Map<String, dynamic>> createInstance(Map<String, dynamic> instanceData) async {
    final response = await _client.post(
      Uri.parse(AppConfig.instancesUrl),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(instanceData),
    );
    return _handleJsonResponse(response);
  }

  Future<Map<String, dynamic>> controlInstance(int instanceId, String action) async {
    final response = await _client.post(
      Uri.parse('${AppConfig.instancesUrl}/$instanceId/control'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'action': action}),
    );
    return _handleJsonResponse(response);
  }

  Future<Map<String, dynamic>> updateInstanceModels(int instanceId, List<String> enabledModels) async {
    final response = await _client.patch(
      Uri.parse('${AppConfig.instancesUrl}/$instanceId/models'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'enabled_models': enabledModels}),
    );
    return _handleJsonResponse(response);
  }

  Future<Map<String, dynamic>> updateInstanceConfig(int instanceId, Map<String, dynamic> modelConfigs) async {
    final response = await _client.patch(
      Uri.parse('${AppConfig.instancesUrl}/$instanceId/config'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'model_configs': modelConfigs}),
    );
    return _handleJsonResponse(response);
  }

  Future<void> deleteInstance(int instanceId) async {
    final response = await _client.delete(Uri.parse('${AppConfig.instancesUrl}/$instanceId'));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(response.statusCode, response.body);
    }
  }

  Future<Map<String, dynamic>> getInstanceStatus(int instanceId) async {
    final response = await _client.get(Uri.parse('${AppConfig.instancesUrl}/$instanceId/status'));
    return _handleJsonResponse(response);
  }

  Future<Map<String, dynamic>> importInstancesBatch(
    Map<String, dynamic> importPayload,
  ) async {
    final response = await _client.post(
      Uri.parse('${AppConfig.instancesUrl}/import-batch'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(importPayload),
    );
    return _handleJsonResponse(response);
  }

  // ============ Alert Rules ============

  Future<List<dynamic>> getAlertRules() async {
    final response = await _client.get(Uri.parse('${AppConfig.apiBaseUrl}/api/alerts/'));
    return _handleJsonListResponse(response);
  }

  Future<Map<String, dynamic>> createAlertRule(
    Map<String, dynamic> payload,
  ) async {
    final response = await _client.post(
      Uri.parse('${AppConfig.apiBaseUrl}/api/alerts/'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    );
    return _handleJsonResponse(response);
  }

  Future<Map<String, dynamic>> updateAlertRule(
    int ruleId,
    Map<String, dynamic> payload,
  ) async {
    final response = await _client.patch(
      Uri.parse('${AppConfig.apiBaseUrl}/api/alerts/$ruleId'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    );
    return _handleJsonResponse(response);
  }

  Future<void> deleteAlertRule(int ruleId) async {
    final response = await _client.delete(Uri.parse('${AppConfig.apiBaseUrl}/api/alerts/$ruleId'));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(response.statusCode, response.body);
    }
  }

  // ============ Push Notifications ============

  Future<List<dynamic>> getDeviceTokens() async {
    final response = await _client.get(Uri.parse('${AppConfig.apiBaseUrl}/api/notifications/devices'));
    return _handleJsonListResponse(response);
  }

  Future<Map<String, dynamic>> registerDeviceToken(Map<String, dynamic> payload) async {
    final response = await _client.post(
      Uri.parse('${AppConfig.apiBaseUrl}/api/notifications/devices'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    );
    return _handleJsonResponse(response);
  }

  Future<Map<String, dynamic>> updateDeviceToken(int deviceId, Map<String, dynamic> payload) async {
    final response = await _client.patch(
      Uri.parse('${AppConfig.apiBaseUrl}/api/notifications/devices/$deviceId'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    );
    return _handleJsonResponse(response);
  }

  Future<void> deleteDeviceToken(int deviceId) async {
    final response = await _client.delete(Uri.parse('${AppConfig.apiBaseUrl}/api/notifications/devices/$deviceId'));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(response.statusCode, response.body);
    }
  }

  Future<Map<String, dynamic>> sendTestNotification(Map<String, dynamic> payload) async {
    final response = await _client.post(
      Uri.parse('${AppConfig.apiBaseUrl}/api/notifications/test'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    );
    return _handleJsonResponse(response);
  }

  // ============ Webhooks ============

  Future<List<dynamic>> getWebhooks() async {
    final response = await _client.get(Uri.parse('${AppConfig.apiBaseUrl}/api/webhooks/'));
    return _handleJsonListResponse(response);
  }

  Future<Map<String, dynamic>> createWebhook(Map<String, dynamic> payload) async {
    final response = await _client.post(
      Uri.parse('${AppConfig.apiBaseUrl}/api/webhooks/'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    );
    return _handleJsonResponse(response);
  }

  Future<Map<String, dynamic>> updateWebhook(int webhookId, Map<String, dynamic> payload) async {
    final response = await _client.patch(
      Uri.parse('${AppConfig.apiBaseUrl}/api/webhooks/$webhookId'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    );
    return _handleJsonResponse(response);
  }

  Future<void> deleteWebhook(int webhookId) async {
    final response = await _client.delete(Uri.parse('${AppConfig.apiBaseUrl}/api/webhooks/$webhookId'));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(response.statusCode, response.body);
    }
  }

  Future<Map<String, dynamic>> testWebhook(int webhookId) async {
    final response = await _client.post(
      Uri.parse('${AppConfig.apiBaseUrl}/api/webhooks/test'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'webhook_id': webhookId}),
    );
    return _handleJsonResponse(response);
  }

  // ============ Scheduled Jobs ============

  Future<List<dynamic>> getScheduledJobs() async {
    final response = await _client.get(Uri.parse('${AppConfig.apiBaseUrl}/api/schedules/'));
    return _handleJsonListResponse(response);
  }

  Future<Map<String, dynamic>> createScheduledJob(Map<String, dynamic> payload) async {
    final response = await _client.post(
      Uri.parse('${AppConfig.apiBaseUrl}/api/schedules/'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    );
    return _handleJsonResponse(response);
  }

  Future<Map<String, dynamic>> updateScheduledJob(int jobId, Map<String, dynamic> payload) async {
    final response = await _client.patch(
      Uri.parse('${AppConfig.apiBaseUrl}/api/schedules/$jobId'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    );
    return _handleJsonResponse(response);
  }

  Future<void> deleteScheduledJob(int jobId) async {
    final response = await _client.delete(Uri.parse('${AppConfig.apiBaseUrl}/api/schedules/$jobId'));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(response.statusCode, response.body);
    }
  }

  Future<Map<String, dynamic>> runScheduledJobNow(int jobId) async {
    final response = await _client.post(
      Uri.parse('${AppConfig.apiBaseUrl}/api/schedules/$jobId/run'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({}),
    );
    return _handleJsonResponse(response);
  }

  // ============ Activity Logs ============

  Future<Map<String, dynamic>> getActivityLogs({
    String? eventType,
    String? severity,
    int? pipelineInstanceId,
    int? sessionId,
    int limit = 50,
    int offset = 0,
  }) async {
    final queryParams = <String, String>{
      'limit': '$limit',
      'offset': '$offset',
      if (eventType != null && eventType.isNotEmpty) 'event_type': eventType,
      if (severity != null && severity.isNotEmpty) 'severity': severity,
      if (pipelineInstanceId != null) 'pipeline_instance_id': '$pipelineInstanceId',
      if (sessionId != null) 'session_id': '$sessionId',
    };

    final uri = Uri.parse('${AppConfig.apiBaseUrl}/api/logs/').replace(queryParameters: queryParams);
    final response = await _client.get(uri);
    return _handleJsonResponse(response);
  }

  Future<List<dynamic>> getRecentErrors({int hours = 24, int limit = 50}) async {
    final uri = Uri.parse('${AppConfig.apiBaseUrl}/api/logs/recent-errors')
        .replace(queryParameters: {'hours': '$hours', 'limit': '$limit'});
    final response = await _client.get(uri);
    return _handleJsonListResponse(response);
  }

  Future<Map<String, dynamic>> getLogStatistics({int hours = 24}) async {
    final uri = Uri.parse('${AppConfig.apiBaseUrl}/api/logs/statistics')
        .replace(queryParameters: {'hours': '$hours'});
    final response = await _client.get(uri);
    return _handleJsonResponse(response);
  }

  // ============ Recordings ============

  Future<List<dynamic>> getRecordings() async {
    final response = await _client.get(Uri.parse('${AppConfig.apiBaseUrl}/api/recordings/'));
    return _handleJsonListResponse(response);
  }

  Future<Map<String, dynamic>> startRecording(Map<String, dynamic> payload) async {
    final response = await _client.post(
      Uri.parse('${AppConfig.apiBaseUrl}/api/recordings/'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    );
    return _handleJsonResponse(response);
  }

  Future<Map<String, dynamic>> stopRecording(
    int recordingId,
    Map<String, dynamic> payload,
  ) async {
    final response = await _client.post(
      Uri.parse('${AppConfig.apiBaseUrl}/api/recordings/$recordingId/stop'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    );
    return _handleJsonResponse(response);
  }

  Future<void> deleteRecording(int recordingId) async {
    final response = await _client.delete(Uri.parse('${AppConfig.apiBaseUrl}/api/recordings/$recordingId'));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(response.statusCode, response.body);
    }
  }

  // ============ Results ============

  Future<List<dynamic>> getSessionResults(int sessionId,
      {String? modelName, int limit = 100}) async {
    var url = '${AppConfig.resultsUrl(sessionId)}?limit=$limit';
    if (modelName != null) url += '&model_name=$modelName';
    final response = await _client.get(Uri.parse(url));
    return _handleJsonListResponse(response);
  }

  void dispose() {
    _client.close();
  }
}
