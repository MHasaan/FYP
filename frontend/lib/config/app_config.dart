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

  // WebSocket endpoints
  static String get wsFeedUrl => '$wsBaseUrl/ws/feed';
  static String get wsResultsUrl => '$wsBaseUrl/ws/results';
  static String wsInstanceFeedUrl(int instanceId) => '$wsBaseUrl/ws/feed/$instanceId';
  static String wsInstanceResultsUrl(int instanceId) => '$wsBaseUrl/ws/results/$instanceId';
}
