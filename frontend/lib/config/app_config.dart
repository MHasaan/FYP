/// App configuration — API endpoints and WebSocket URLs
class AppConfig {
  // Change these when deploying
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:8000',
  );

  static const String wsBaseUrl = String.fromEnvironment(
    'WS_BASE_URL',
    defaultValue: 'ws://localhost:8000',
  );

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

  // WebSocket endpoints
  static String get wsFeedUrl => '$wsBaseUrl/ws/feed';
  static String get wsResultsUrl => '$wsBaseUrl/ws/results';
  static String wsInstanceFeedUrl(int instanceId) => '$wsBaseUrl/ws/feed/$instanceId';
  static String wsInstanceResultsUrl(int instanceId) => '$wsBaseUrl/ws/results/$instanceId';
}
