import 'package:flutter/foundation.dart';

/// App configuration — API endpoints and WebSocket URLs.
///
/// On Flutter web the app is always served from the same host as the API
/// (nginx proxies /api/ and /ws/ to the backend). Using relative paths means
/// the app works identically whether accessed via localhost, ngrok, or any
/// future domain — no rebuild needed when the URL changes.
///
/// On mobile (Android/iOS) a full absolute URL must be baked in at build time
/// via --dart-define=API_BASE_URL=https://... .
class AppConfig {
  static const String _envApiBase = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: '',
  );
  static const String _envWsBase = String.fromEnvironment(
    'WS_BASE_URL',
    defaultValue: '',
  );

  /// Base URL for HTTP REST calls.
  /// Web: empty string → relative URLs (same-origin via nginx proxy).
  /// Mobile: absolute URL from --dart-define.
  static String get apiBaseUrl {
    if (kIsWeb) return '';
    return _envApiBase.isEmpty ? 'http://localhost:8000' : _envApiBase;
  }

  /// Base URL for WebSocket connections.
  /// Web: derived from current page origin (http→ws, https→wss).
  /// Mobile: absolute URL from --dart-define.
  static String get wsBaseUrl {
    if (kIsWeb) {
      // Derive ws:// or wss:// from the page the app is loaded from.
      final uri = Uri.base;
      final scheme = uri.scheme == 'https' ? 'wss' : 'ws';
      return '$scheme://${uri.host}${uri.port != 0 && uri.port != 80 && uri.port != 443 ? ':${uri.port}' : ''}';
    }
    return _envWsBase.isEmpty ? 'ws://localhost:8000' : _envWsBase;
  }

  // API endpoints
  static String get healthUrl => '$apiBaseUrl/health';
  static String get camerasUrl => '$apiBaseUrl/api/camera/configs';
  static String get cameraSourcesUrl => '$apiBaseUrl/api/camera/sources';
  static String get pipelineStatusUrl => '$apiBaseUrl/api/pipeline/status';
  static String get pipelineControlUrl => '$apiBaseUrl/api/pipeline/control';
  static String get sessionsUrl => '$apiBaseUrl/api/pipeline/sessions';
  static String get instancesUrl => '$apiBaseUrl/api/instances';
  static String resultsUrl(int sessionId) =>
      '$apiBaseUrl/api/results/session/$sessionId';
  static String sessionStatsUrl(int sessionId) =>
      '$apiBaseUrl/api/results/session/$sessionId/stats';
  static String get authLoginUrl => '$apiBaseUrl/api/auth/login';
  static String get authRegisterUrl => '$apiBaseUrl/api/auth/register';
  static String get authLogoutUrl => '$apiBaseUrl/api/auth/logout';
  static String get authMeUrl => '$apiBaseUrl/api/auth/me';
  static String get authUsersUrl => '$apiBaseUrl/api/auth/users';
  static String get patientsUrl => '$apiBaseUrl/api/patients';
  static String get incidentsUrl => '$apiBaseUrl/api/incidents';
  static String get detectionSettingsUrl => '$apiBaseUrl/api/detection-settings';
  static String get incidentReportsUrl => '$apiBaseUrl/api/reports/incidents';
  static String get systemCapabilitiesUrl => '$apiBaseUrl/api/system/capabilities';
  static String get groundingDinoBaseUrl => '$apiBaseUrl/api/grounding-dino';

  // WebSocket endpoints
  static String get wsFeedUrl => '$wsBaseUrl/ws/feed';
  static String get wsResultsUrl => '$wsBaseUrl/ws/results';
  static String wsInstanceFeedUrl(int instanceId) => '$wsBaseUrl/ws/feed/$instanceId';
  static String wsInstanceResultsUrl(int instanceId) => '$wsBaseUrl/ws/results/$instanceId';
}
