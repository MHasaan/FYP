import 'dart:async';
import 'dart:convert';
import 'dart:io';
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
  static String? _authToken;

  static void setAuthToken(String? token) {
    _authToken = token?.trim().isEmpty == true ? null : token?.trim();
    // ignore: avoid_print
    print('[ApiService] setAuthToken -> set=${_authToken != null} '
        'len=${_authToken?.length ?? 0}');
  }

  /// Public read-only access to the current bearer token.
  static String? get authToken => _authToken;

  /// Optional 401 callback (e.g. AuthController logs out on unauthorized).
  /// Pass `null` to clear. Kept as a stub so wiring doesn't break — actual
  /// invocation is handled in `_handleJsonResponse` if/when we route 401s.
  static void Function()? _on401;
  static void registerOn401(void Function()? cb) {
    _on401 = cb;
  }

  Map<String, String> _buildHeaders({bool json = true}) {
    final headers = <String, String>{};
    if (json) {
      headers['Content-Type'] = 'application/json';
    }
    final token = _authToken;
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    // Bypass ngrok's browser-warning interstitial for programmatic requests.
    headers['ngrok-skip-browser-warning'] = 'true';
    // Temporary diagnostic — visible via `adb logcat | grep flutter` so we can
    // confirm in the field whether the bearer is actually being attached.
    // Remove once the install + auth flow is verified stable.
    // ignore: avoid_print
    print('[ApiService] _buildHeaders -> hasAuth=${token != null && token.isNotEmpty} '
        'tokenLen=${token?.length ?? 0}');
    return headers;
  }

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

  // ============ Video Upload ============

  /// Upload a video file to the backend. The backend stores it at
  /// /videos/uploads/<uuid>.<ext> and returns that server path. Use the
  /// returned path as the `source_url` of a CameraConfig with
  /// source_type='video_file' to make the ML manager process it.
  ///
  /// On Flutter web (where `dart:io File` isn't available), pass `bytes` +
  /// `filename` instead of `filePath`. `onProgress` is called with
  /// (sentBytes, totalBytes) as the upload streams.
  Future<Map<String, dynamic>> uploadVideo({
    String? filePath,
    List<int>? bytes,
    String? filename,
    void Function(int sent, int total)? onProgress,
  }) async {
    final uri = Uri.parse('${AppConfig.apiBaseUrl}/api/videos/upload');
    final request = http.MultipartRequest('POST', uri);

    // Auth header (token, if any) — multipart sets its own Content-Type.
    final tok = _authToken;
    if (tok != null && tok.isNotEmpty) {
      request.headers['Authorization'] = 'Bearer $tok';
    }

    // Attach the file
    if (filePath != null) {
      final file = File(filePath);
      final length = await file.length();
      final stream = http.ByteStream(_progressStream(file.openRead(), length, onProgress));
      request.files.add(http.MultipartFile(
        'file',
        stream,
        length,
        filename: filename ?? file.uri.pathSegments.last,
      ));
    } else if (bytes != null && filename != null) {
      // Web path — wrap in a controllable stream to report progress
      final total = bytes.length;
      final stream = http.ByteStream(_progressStream(
        Stream.fromIterable([bytes]),
        total,
        onProgress,
      ));
      request.files.add(http.MultipartFile(
        'file',
        stream,
        total,
        filename: filename,
      ));
    } else {
      throw ArgumentError('Provide either filePath or (bytes + filename).');
    }

    final streamed = await request.send();
    final response = await http.Response.fromStream(streamed);
    return _handleJsonResponse(response);
  }

  /// Wraps a byte stream so we can report `(sent, total)` to a progress
  /// callback as data flows through it.
  Stream<List<int>> _progressStream(
    Stream<List<int>> source,
    int total,
    void Function(int sent, int total)? onProgress,
  ) async* {
    int sent = 0;
    await for (final chunk in source) {
      sent += chunk.length;
      if (onProgress != null) onProgress(sent, total);
      yield chunk;
    }
  }

  // ============ Health ============

  Future<Map<String, dynamic>> checkHealth() async {
    final response = await _client.get(Uri.parse(AppConfig.healthUrl));
    return _handleJsonResponse(response);
  }

  // ============ Camera ============

  Future<List<dynamic>> getCameraConfigs() async {
    final response = await _client.get(Uri.parse(AppConfig.camerasUrl), headers: _buildHeaders(json: false));
    return _handleJsonListResponse(response);
  }

  Future<Map<String, dynamic>> createCameraConfig(
      Map<String, dynamic> config) async {
    final response = await _client.post(
      Uri.parse(AppConfig.camerasUrl),
      headers: _buildHeaders(),
      body: jsonEncode(config),
    );
    return _handleJsonResponse(response);
  }

  Future<void> deleteCameraConfig(int id) async {
    final response = await _client.delete(Uri.parse('${AppConfig.camerasUrl}/$id'), headers: _buildHeaders(json: false));
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
      headers: _buildHeaders(),
      body: jsonEncode(config),
    );
    return _handleJsonResponse(response);
  }

  Future<Map<String, dynamic>> getCameraSources() async {
    final response = await _client.get(Uri.parse(AppConfig.cameraSourcesUrl), headers: _buildHeaders(json: false));
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
    final response = await _client.get(uri, headers: _buildHeaders(json: false));
    return _handleJsonListResponse(response);
  }

  Future<Map<String, dynamic>> createROIZone(Map<String, dynamic> payload) async {
    final response = await _client.post(
      Uri.parse('${AppConfig.apiBaseUrl}/api/roi/zones'),
      headers: _buildHeaders(),
      body: jsonEncode(payload),
    );
    return _handleJsonResponse(response);
  }

  Future<Map<String, dynamic>> updateROIZone(int zoneId, Map<String, dynamic> payload) async {
    final response = await _client.patch(
      Uri.parse('${AppConfig.apiBaseUrl}/api/roi/zones/$zoneId'),
      headers: _buildHeaders(),
      body: jsonEncode(payload),
    );
    return _handleJsonResponse(response);
  }

  Future<void> deleteROIZone(int zoneId) async {
    final response = await _client.delete(Uri.parse('${AppConfig.apiBaseUrl}/api/roi/zones/$zoneId'), headers: _buildHeaders(json: false));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(response.statusCode, response.body);
    }
  }

  // ============ Pipeline ============

  Future<Map<String, dynamic>> getPipelineStatus() async {
    final response =
        await _client.get(Uri.parse(AppConfig.pipelineStatusUrl), headers: _buildHeaders(json: false));
    return _handleJsonResponse(response);
  }

  Future<Map<String, dynamic>> controlPipeline(
      Map<String, dynamic> command) async {
    final response = await _client.post(
      Uri.parse(AppConfig.pipelineControlUrl),
      headers: _buildHeaders(),
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
        Uri.parse('${AppConfig.sessionsUrl}?limit=$limit&offset=$offset'), headers: _buildHeaders(json: false));
    return _handleJsonListResponse(response);
  }

  Future<Map<String, dynamic>> getSessionStats(int sessionId) async {
    final response =
        await _client.get(Uri.parse(AppConfig.sessionStatsUrl(sessionId)), headers: _buildHeaders(json: false));
    return _handleJsonResponse(response);
  }

  // ============ Pipeline Instances ============

  Future<List<dynamic>> getInstances({String? statusFilter}) async {
    // Trailing slash matters: see AppConfig.patientsUrl comment.
    var url = '${AppConfig.instancesUrl}/';
    if (statusFilter != null) url += '?status_filter=$statusFilter';
    final response = await _client.get(Uri.parse(url), headers: _buildHeaders(json: false));
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
    final response = await _client.get(uri, headers: _buildHeaders(json: false));
    return _handleJsonResponse(response);
  }

  Future<Map<String, dynamic>> getInstance(int instanceId) async {
    final response = await _client.get(Uri.parse('${AppConfig.instancesUrl}/$instanceId'), headers: _buildHeaders(json: false));
    return _handleJsonResponse(response);
  }

  Future<Map<String, dynamic>> updateInstance(
    int instanceId,
    Map<String, dynamic> updateData,
  ) async {
    final response = await _client.patch(
      Uri.parse('${AppConfig.instancesUrl}/$instanceId'),
      headers: _buildHeaders(),
      body: jsonEncode(updateData),
    );
    return _handleJsonResponse(response);
  }

  Future<Map<String, dynamic>> createInstance(Map<String, dynamic> instanceData) async {
    final response = await _client.post(
      Uri.parse('${AppConfig.instancesUrl}/'),
      headers: _buildHeaders(),
      body: jsonEncode(instanceData),
    );
    return _handleJsonResponse(response);
  }

  Future<Map<String, dynamic>> controlInstance(int instanceId, String action) async {
    final response = await _client.post(
      Uri.parse('${AppConfig.instancesUrl}/$instanceId/control'),
      headers: _buildHeaders(),
      body: jsonEncode({'action': action}),
    );
    return _handleJsonResponse(response);
  }

  Future<Map<String, dynamic>> updateInstanceModels(int instanceId, List<String> enabledModels) async {
    final response = await _client.patch(
      Uri.parse('${AppConfig.instancesUrl}/$instanceId/models'),
      headers: _buildHeaders(),
      body: jsonEncode({'enabled_models': enabledModels}),
    );
    return _handleJsonResponse(response);
  }

  Future<Map<String, dynamic>> updateInstanceConfig(int instanceId, Map<String, dynamic> modelConfigs) async {
    final response = await _client.patch(
      Uri.parse('${AppConfig.instancesUrl}/$instanceId/config'),
      headers: _buildHeaders(),
      body: jsonEncode({'model_configs': modelConfigs}),
    );
    return _handleJsonResponse(response);
  }

  Future<void> deleteInstance(int instanceId) async {
    final response = await _client.delete(Uri.parse('${AppConfig.instancesUrl}/$instanceId'), headers: _buildHeaders(json: false));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(response.statusCode, response.body);
    }
  }

  Future<Map<String, dynamic>> getInstanceStatus(int instanceId) async {
    final response = await _client.get(Uri.parse('${AppConfig.instancesUrl}/$instanceId/status'), headers: _buildHeaders(json: false));
    return _handleJsonResponse(response);
  }

  Future<Map<String, dynamic>> importInstancesBatch(
    Map<String, dynamic> importPayload,
  ) async {
    final response = await _client.post(
      Uri.parse('${AppConfig.instancesUrl}/import-batch'),
      headers: _buildHeaders(),
      body: jsonEncode(importPayload),
    );
    return _handleJsonResponse(response);
  }

  // ============ Alert Rules ============

  Future<List<dynamic>> getAlertRules() async {
    final response = await _client.get(Uri.parse('${AppConfig.apiBaseUrl}/api/alerts/'), headers: _buildHeaders(json: false));
    return _handleJsonListResponse(response);
  }

  Future<Map<String, dynamic>> createAlertRule(
    Map<String, dynamic> payload,
  ) async {
    final response = await _client.post(
      Uri.parse('${AppConfig.apiBaseUrl}/api/alerts/'),
      headers: _buildHeaders(),
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
      headers: _buildHeaders(),
      body: jsonEncode(payload),
    );
    return _handleJsonResponse(response);
  }

  Future<void> deleteAlertRule(int ruleId) async {
    final response = await _client.delete(Uri.parse('${AppConfig.apiBaseUrl}/api/alerts/$ruleId'), headers: _buildHeaders(json: false));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(response.statusCode, response.body);
    }
  }

  // ============ Push Notifications ============

  Future<List<dynamic>> getDeviceTokens() async {
    final response = await _client.get(Uri.parse('${AppConfig.apiBaseUrl}/api/notifications/devices'), headers: _buildHeaders(json: false));
    return _handleJsonListResponse(response);
  }

  Future<Map<String, dynamic>> registerDeviceToken(Map<String, dynamic> payload) async {
    final response = await _client.post(
      Uri.parse('${AppConfig.apiBaseUrl}/api/notifications/devices'),
      headers: _buildHeaders(),
      body: jsonEncode(payload),
    );
    return _handleJsonResponse(response);
  }

  Future<Map<String, dynamic>> updateDeviceToken(int deviceId, Map<String, dynamic> payload) async {
    final response = await _client.patch(
      Uri.parse('${AppConfig.apiBaseUrl}/api/notifications/devices/$deviceId'),
      headers: _buildHeaders(),
      body: jsonEncode(payload),
    );
    return _handleJsonResponse(response);
  }

  Future<void> deleteDeviceToken(int deviceId) async {
    final response = await _client.delete(Uri.parse('${AppConfig.apiBaseUrl}/api/notifications/devices/$deviceId'), headers: _buildHeaders(json: false));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(response.statusCode, response.body);
    }
  }

  Future<Map<String, dynamic>> sendTestNotification(Map<String, dynamic> payload) async {
    final response = await _client.post(
      Uri.parse('${AppConfig.apiBaseUrl}/api/notifications/test'),
      headers: _buildHeaders(),
      body: jsonEncode(payload),
    );
    return _handleJsonResponse(response);
  }

  // ============ Webhooks ============

  Future<List<dynamic>> getWebhooks() async {
    final response = await _client.get(Uri.parse('${AppConfig.apiBaseUrl}/api/webhooks/'), headers: _buildHeaders(json: false));
    return _handleJsonListResponse(response);
  }

  Future<Map<String, dynamic>> createWebhook(Map<String, dynamic> payload) async {
    final response = await _client.post(
      Uri.parse('${AppConfig.apiBaseUrl}/api/webhooks/'),
      headers: _buildHeaders(),
      body: jsonEncode(payload),
    );
    return _handleJsonResponse(response);
  }

  Future<Map<String, dynamic>> updateWebhook(int webhookId, Map<String, dynamic> payload) async {
    final response = await _client.patch(
      Uri.parse('${AppConfig.apiBaseUrl}/api/webhooks/$webhookId'),
      headers: _buildHeaders(),
      body: jsonEncode(payload),
    );
    return _handleJsonResponse(response);
  }

  Future<void> deleteWebhook(int webhookId) async {
    final response = await _client.delete(Uri.parse('${AppConfig.apiBaseUrl}/api/webhooks/$webhookId'), headers: _buildHeaders(json: false));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(response.statusCode, response.body);
    }
  }

  Future<Map<String, dynamic>> testWebhook(int webhookId) async {
    final response = await _client.post(
      Uri.parse('${AppConfig.apiBaseUrl}/api/webhooks/test'),
      headers: _buildHeaders(),
      body: jsonEncode({'webhook_id': webhookId}),
    );
    return _handleJsonResponse(response);
  }

  // ============ Scheduled Jobs ============

  Future<List<dynamic>> getScheduledJobs() async {
    final response = await _client.get(Uri.parse('${AppConfig.apiBaseUrl}/api/schedules/'), headers: _buildHeaders(json: false));
    return _handleJsonListResponse(response);
  }

  Future<Map<String, dynamic>> createScheduledJob(Map<String, dynamic> payload) async {
    final response = await _client.post(
      Uri.parse('${AppConfig.apiBaseUrl}/api/schedules/'),
      headers: _buildHeaders(),
      body: jsonEncode(payload),
    );
    return _handleJsonResponse(response);
  }

  Future<Map<String, dynamic>> updateScheduledJob(int jobId, Map<String, dynamic> payload) async {
    final response = await _client.patch(
      Uri.parse('${AppConfig.apiBaseUrl}/api/schedules/$jobId'),
      headers: _buildHeaders(),
      body: jsonEncode(payload),
    );
    return _handleJsonResponse(response);
  }

  Future<void> deleteScheduledJob(int jobId) async {
    final response = await _client.delete(Uri.parse('${AppConfig.apiBaseUrl}/api/schedules/$jobId'), headers: _buildHeaders(json: false));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(response.statusCode, response.body);
    }
  }

  Future<Map<String, dynamic>> runScheduledJobNow(int jobId) async {
    final response = await _client.post(
      Uri.parse('${AppConfig.apiBaseUrl}/api/schedules/$jobId/run'),
      headers: _buildHeaders(),
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
    final response = await _client.get(uri, headers: _buildHeaders(json: false));
    return _handleJsonResponse(response);
  }

  Future<List<dynamic>> getRecentErrors({int hours = 24, int limit = 50}) async {
    final uri = Uri.parse('${AppConfig.apiBaseUrl}/api/logs/recent-errors')
        .replace(queryParameters: {'hours': '$hours', 'limit': '$limit'});
    final response = await _client.get(uri, headers: _buildHeaders(json: false));
    return _handleJsonListResponse(response);
  }

  Future<Map<String, dynamic>> getLogStatistics({int hours = 24}) async {
    final uri = Uri.parse('${AppConfig.apiBaseUrl}/api/logs/statistics')
        .replace(queryParameters: {'hours': '$hours'});
    final response = await _client.get(uri, headers: _buildHeaders(json: false));
    return _handleJsonResponse(response);
  }

  // ============ Recordings ============

  Future<List<dynamic>> getRecordings() async {
    final response = await _client.get(Uri.parse('${AppConfig.apiBaseUrl}/api/recordings/'), headers: _buildHeaders(json: false));
    return _handleJsonListResponse(response);
  }

  Future<Map<String, dynamic>> startRecording(Map<String, dynamic> payload) async {
    final response = await _client.post(
      Uri.parse('${AppConfig.apiBaseUrl}/api/recordings/'),
      headers: _buildHeaders(),
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
      headers: _buildHeaders(),
      body: jsonEncode(payload),
    );
    return _handleJsonResponse(response);
  }

  Future<void> deleteRecording(int recordingId) async {
    final response = await _client.delete(Uri.parse('${AppConfig.apiBaseUrl}/api/recordings/$recordingId'), headers: _buildHeaders(json: false));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(response.statusCode, response.body);
    }
  }

  // ============ Results ============

  Future<List<dynamic>> getSessionResults(int sessionId,
      {String? modelName, int limit = 100}) async {
    var url = '${AppConfig.resultsUrl(sessionId)}?limit=$limit';
    if (modelName != null) url += '&model_name=$modelName';
    final response = await _client.get(Uri.parse(url), headers: _buildHeaders(json: false));
    return _handleJsonListResponse(response);
  }

  // ============ Auth & Users ============

  Future<Map<String, dynamic>> login(String email, String password) async {
    final response = await _client.post(
      Uri.parse(AppConfig.authLoginUrl),
      headers: _buildHeaders(),
      body: jsonEncode({'email': email, 'password': password}),
    );
    return _handleJsonResponse(response);
  }

  Future<Map<String, dynamic>> registerUser(Map<String, dynamic> payload) async {
    final response = await _client.post(
      Uri.parse(AppConfig.authRegisterUrl),
      headers: _buildHeaders(),
      body: jsonEncode(payload),
    );
    return _handleJsonResponse(response);
  }

  Future<Map<String, dynamic>> logout(String accessToken) async {
    final response = await _client.post(
      Uri.parse(AppConfig.authLogoutUrl),
      headers: _buildHeaders(),
      body: jsonEncode({'access_token': accessToken}),
    );
    return _handleJsonResponse(response);
  }

  Future<Map<String, dynamic>> getCurrentUser() async {
    final response = await _client.get(
      Uri.parse(AppConfig.authMeUrl),
      headers: _buildHeaders(json: false),
    );
    return _handleJsonResponse(response);
  }

  /// Update the current user's own profile (full_name, phone). Works for any
  /// signed-in user; doesn't require admin.
  Future<Map<String, dynamic>> updateMe(Map<String, dynamic> payload) async {
    final response = await _client.patch(
      Uri.parse(AppConfig.authMeUrl),
      headers: _buildHeaders(),
      body: jsonEncode(payload),
    );
    return _handleJsonResponse(response);
  }

  Future<List<dynamic>> listUsers() async {
    final response = await _client.get(
      Uri.parse(AppConfig.authUsersUrl),
      headers: _buildHeaders(json: false),
    );
    return _handleJsonListResponse(response);
  }

  Future<Map<String, dynamic>> createUser(Map<String, dynamic> payload) async {
    final response = await _client.post(
      Uri.parse(AppConfig.authUsersUrl),
      headers: _buildHeaders(),
      body: jsonEncode(payload),
    );
    return _handleJsonResponse(response);
  }

  Future<Map<String, dynamic>> updateUser(int userId, Map<String, dynamic> payload) async {
    final response = await _client.patch(
      Uri.parse('${AppConfig.authUsersUrl}/$userId'),
      headers: _buildHeaders(),
      body: jsonEncode(payload),
    );
    return _handleJsonResponse(response);
  }

  Future<void> deleteUser(int userId) async {
    final response = await _client.delete(
      Uri.parse('${AppConfig.authUsersUrl}/$userId'),
      headers: _buildHeaders(json: false),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(response.statusCode, response.body);
    }
  }

  /// Returns the total number of users. Used by the login screen to detect
  /// the first-admin bootstrap case.
  Future<int> getUsersCount() async {
    final users = await listUsers();
    return users.length;
  }

  /// List users optionally filtered by role.
  Future<List<dynamic>> listUsersFiltered({String? role}) async {
    final uri = Uri.parse(AppConfig.authUsersUrl).replace(queryParameters: {
      if (role != null && role.isNotEmpty) 'role': role,
    });
    final response = await _client.get(uri, headers: _buildHeaders(json: false));
    return _handleJsonListResponse(response);
  }

  /// Change the currently-authenticated user's password.
  Future<Map<String, dynamic>> changeMyPassword(String currentPassword, String newPassword) async {
    final response = await _client.post(
      Uri.parse('${AppConfig.authMeUrl}/password'),
      headers: _buildHeaders(),
      body: jsonEncode({
        'current_password': currentPassword,
        'new_password': newPassword,
      }),
    );
    return _handleJsonResponse(response);
  }

  // ============ Patients ============

  Future<List<dynamic>> getPatients({String? search}) async {
    final queryParams = <String, String>{
      if (search != null && search.trim().isNotEmpty) 'search': search.trim(),
    };
    // Trailing slash matters: see AppConfig.patientsUrl comment.
    final uri = Uri.parse('${AppConfig.patientsUrl}/').replace(queryParameters: queryParams);
    final response = await _client.get(uri, headers: _buildHeaders(json: false));
    return _handleJsonListResponse(response);
  }

  Future<Map<String, dynamic>> createPatient(Map<String, dynamic> payload) async {
    final response = await _client.post(
      Uri.parse('${AppConfig.patientsUrl}/'),
      headers: _buildHeaders(),
      body: jsonEncode(payload),
    );
    return _handleJsonResponse(response);
  }

  Future<Map<String, dynamic>> updatePatient(int patientId, Map<String, dynamic> payload) async {
    final response = await _client.patch(
      Uri.parse('${AppConfig.patientsUrl}/$patientId'),
      headers: _buildHeaders(),
      body: jsonEncode(payload),
    );
    return _handleJsonResponse(response);
  }

  Future<void> deletePatient(int patientId) async {
    final response = await _client.delete(
      Uri.parse('${AppConfig.patientsUrl}/$patientId'),
      headers: _buildHeaders(json: false),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(response.statusCode, response.body);
    }
  }

  // ============ Incidents ============

  Future<Map<String, dynamic>> getIncidents({
    int limit = 50,
    int offset = 0,
    int? patientId,
    int? cameraConfigId,
    String? status,
    String? eventType,
    DateTime? startTime,
    DateTime? endTime,
  }) async {
    final queryParams = <String, String>{
      'limit': '$limit',
      'offset': '$offset',
      if (patientId != null) 'patient_id': '$patientId',
      if (cameraConfigId != null) 'camera_config_id': '$cameraConfigId',
      if (status != null && status.isNotEmpty) 'status': status,
      if (eventType != null && eventType.isNotEmpty) 'event_type': eventType,
      if (startTime != null) 'start_time': startTime.toUtc().toIso8601String(),
      if (endTime != null) 'end_time': endTime.toUtc().toIso8601String(),
    };
    // Trailing slash matters: see AppConfig.patientsUrl comment.
    final uri = Uri.parse('${AppConfig.incidentsUrl}/').replace(queryParameters: queryParams);
    final response = await _client.get(uri, headers: _buildHeaders(json: false));
    return _handleJsonResponse(response);
  }

  Future<Map<String, dynamic>> createIncident(Map<String, dynamic> payload) async {
    final response = await _client.post(
      Uri.parse('${AppConfig.incidentsUrl}/'),
      headers: _buildHeaders(),
      body: jsonEncode(payload),
    );
    return _handleJsonResponse(response);
  }

  Future<Map<String, dynamic>> updateIncident(int incidentId, Map<String, dynamic> payload) async {
    final response = await _client.patch(
      Uri.parse('${AppConfig.incidentsUrl}/$incidentId'),
      headers: _buildHeaders(),
      body: jsonEncode(payload),
    );
    return _handleJsonResponse(response);
  }

  Future<Map<String, dynamic>> acknowledgeIncident(int incidentId) async {
    final response = await _client.post(
      Uri.parse('${AppConfig.incidentsUrl}/$incidentId/acknowledge'),
      headers: _buildHeaders(),
      body: jsonEncode({}),
    );
    return _handleJsonResponse(response);
  }

  Future<Map<String, dynamic>> resolveIncident(int incidentId) async {
    final response = await _client.post(
      Uri.parse('${AppConfig.incidentsUrl}/$incidentId/resolve'),
      headers: _buildHeaders(),
      body: jsonEncode({}),
    );
    return _handleJsonResponse(response);
  }

  // ============ Detection Settings ============

  Future<List<dynamic>> getDetectionSettings({
    int? cameraConfigId,
    int? patientId,
  }) async {
    final queryParams = <String, String>{
      if (cameraConfigId != null) 'camera_config_id': '$cameraConfigId',
      if (patientId != null) 'patient_id': '$patientId',
    };
    // Trailing slash matters: see AppConfig.patientsUrl comment.
    final uri = Uri.parse('${AppConfig.detectionSettingsUrl}/').replace(queryParameters: queryParams);
    final response = await _client.get(uri, headers: _buildHeaders(json: false));
    return _handleJsonListResponse(response);
  }

  Future<Map<String, dynamic>> createDetectionSetting(Map<String, dynamic> payload) async {
    final response = await _client.post(
      Uri.parse('${AppConfig.detectionSettingsUrl}/'),
      headers: _buildHeaders(),
      body: jsonEncode(payload),
    );
    return _handleJsonResponse(response);
  }

  Future<Map<String, dynamic>> updateDetectionSetting(int settingId, Map<String, dynamic> payload) async {
    final response = await _client.patch(
      Uri.parse('${AppConfig.detectionSettingsUrl}/$settingId'),
      headers: _buildHeaders(),
      body: jsonEncode(payload),
    );
    return _handleJsonResponse(response);
  }

  Future<void> deleteDetectionSetting(int settingId) async {
    final response = await _client.delete(
      Uri.parse('${AppConfig.detectionSettingsUrl}/$settingId'),
      headers: _buildHeaders(json: false),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(response.statusCode, response.body);
    }
  }

  // ============ Reports & System ============

  Future<Map<String, dynamic>> getIncidentReport({
    int? patientId,
    int? cameraConfigId,
    DateTime? startTime,
    DateTime? endTime,
  }) async {
    final queryParams = <String, String>{
      if (patientId != null) 'patient_id': '$patientId',
      if (cameraConfigId != null) 'camera_config_id': '$cameraConfigId',
      if (startTime != null) 'start_time': startTime.toUtc().toIso8601String(),
      if (endTime != null) 'end_time': endTime.toUtc().toIso8601String(),
    };
    final uri = Uri.parse(AppConfig.incidentReportsUrl).replace(queryParameters: queryParams);
    final response = await _client.get(uri, headers: _buildHeaders(json: false));
    return _handleJsonResponse(response);
  }

  Future<Map<String, dynamic>> getSystemCapabilities() async {
    final response = await _client.get(
      Uri.parse(AppConfig.systemCapabilitiesUrl),
      headers: _buildHeaders(json: false),
    );
    return _handleJsonResponse(response);
  }

  // ============ Visual Search (GroundingDINO) ============

  /// Upload an image OR video to the Visual Search endpoint.
  /// [inputType] is 'image' or 'video' — picks the matching backend route.
  /// Server stores the file, queues a job, and returns the new job row
  /// (status='queued'). Poll [getGroundingDinoJob] until status is
  /// 'completed' or 'failed'.
  Future<Map<String, dynamic>> submitGroundingDinoJob({
    required String inputType, // 'image' | 'video'
    required String prompt,
    String? name,
    double boxThreshold = 0.35,
    double textThreshold = 0.25,
    String? filePath,
    List<int>? bytes,
    String? filename,
    void Function(int sent, int total)? onProgress,
  }) async {
    assert(inputType == 'image' || inputType == 'video',
        "inputType must be 'image' or 'video'");

    final endpoint = '${AppConfig.groundingDinoBaseUrl}/detect/$inputType';
    final uri = Uri.parse(endpoint);
    final request = http.MultipartRequest('POST', uri);

    final tok = _authToken;
    if (tok != null && tok.isNotEmpty) {
      request.headers['Authorization'] = 'Bearer $tok';
    }

    request.fields['prompt'] = prompt;
    request.fields['box_threshold'] = boxThreshold.toString();
    request.fields['text_threshold'] = textThreshold.toString();
    if (name != null && name.trim().isNotEmpty) {
      request.fields['name'] = name.trim();
    }

    if (filePath != null) {
      final file = File(filePath);
      final length = await file.length();
      final stream = http.ByteStream(
          _progressStream(file.openRead(), length, onProgress));
      request.files.add(http.MultipartFile(
        'file', stream, length,
        filename: filename ?? file.uri.pathSegments.last,
      ));
    } else if (bytes != null && filename != null) {
      final total = bytes.length;
      final stream = http.ByteStream(_progressStream(
        Stream.fromIterable([bytes]),
        total,
        onProgress,
      ));
      request.files.add(http.MultipartFile(
        'file', stream, total, filename: filename,
      ));
    } else {
      throw ArgumentError('Provide either filePath or (bytes + filename).');
    }

    final streamed = await request.send();
    final response = await http.Response.fromStream(streamed);
    return _handleJsonResponse(response);
  }

  /// Submit a Visual Search job that captures a live frame from a configured
  /// camera. The ML manager opens the camera, grabs one frame, and runs
  /// GroundingDINO on it. Returns the new job row (status='queued').
  Future<Map<String, dynamic>> submitGroundingDinoLiveFrameJob({
    required int cameraConfigId,
    required String prompt,
    String? name,
    double boxThreshold = 0.35,
    double textThreshold = 0.25,
  }) async {
    final uri = Uri.parse('${AppConfig.groundingDinoBaseUrl}/detect/live-frame/');
    final response = await _client.post(
      uri,
      headers: _buildHeaders(json: true),
      body: jsonEncode({
        'camera_config_id': cameraConfigId,
        'prompt': prompt,
        if (name != null && name.trim().isNotEmpty) 'name': name.trim(),
        'box_threshold': boxThreshold,
        'text_threshold': textThreshold,
      }),
    );
    return _handleJsonResponse(response);
  }

  /// List the current user's Visual Search jobs (most recent first).
  Future<Map<String, dynamic>> listGroundingDinoJobs({
    int limit = 50,
    int offset = 0,
    String? statusFilter,
  }) async {
    final qp = <String, String>{
      'limit': '$limit',
      'offset': '$offset',
      if (statusFilter != null && statusFilter.isNotEmpty)
        'status_filter': statusFilter,
    };
    final uri = Uri.parse('${AppConfig.groundingDinoBaseUrl}/jobs')
        .replace(queryParameters: qp);
    final response =
        await _client.get(uri, headers: _buildHeaders(json: false));
    return _handleJsonResponse(response);
  }

  Future<Map<String, dynamic>> getGroundingDinoJob(int jobId) async {
    final response = await _client.get(
      Uri.parse('${AppConfig.groundingDinoBaseUrl}/jobs/$jobId'),
      headers: _buildHeaders(json: false),
    );
    return _handleJsonResponse(response);
  }

  Future<void> deleteGroundingDinoJob(int jobId) async {
    final response = await _client.delete(
      Uri.parse('${AppConfig.groundingDinoBaseUrl}/jobs/$jobId'),
      headers: _buildHeaders(json: false),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(response.statusCode, response.body);
    }
  }

  /// URL the frontend can hand to Image.network / VideoPlayer for an
  /// annotated job output. The browser still needs the bearer token, so
  /// callers should fetch the bytes via [downloadGroundingDinoOutput] if
  /// the endpoint is behind auth.
  String groundingDinoOutputUrl(int jobId) =>
      '${AppConfig.groundingDinoBaseUrl}/jobs/$jobId/output';

  /// Fetches the annotated output as raw bytes (carries the bearer token).
  /// Returns null if the output isn't ready yet (HTTP 404).
  Future<List<int>?> downloadGroundingDinoOutput(int jobId) async {
    final response = await _client.get(
      Uri.parse(groundingDinoOutputUrl(jobId)),
      headers: _buildHeaders(json: false),
    );
    if (response.statusCode == 404) return null;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(response.statusCode, response.body);
    }
    return response.bodyBytes;
  }

  void dispose() {
    _client.close();
  }
}
