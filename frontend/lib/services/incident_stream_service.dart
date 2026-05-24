import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../config/app_config.dart';
import 'api_service.dart';
import 'auth_controller.dart';

/// Streams new incidents to the UI in real time.
///
/// Connects to /ws/incidents (token via query string). Falls back to polling
/// /api/incidents?status=new every 15s if the WebSocket fails three times.
class IncidentStreamService extends ChangeNotifier {
  IncidentStreamService(this._auth) {
    _auth.addListener(_authChanged);
    _authChanged();
  }

  final AuthController _auth;
  final ApiService _api = ApiService();

  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  Timer? _pollTimer;
  Timer? _reconnectTimer;
  int _wsAttempts = 0;
  bool _running = false;

  final List<Map<String, dynamic>> _recent = [];
  int _unresolvedCount = 0;

  /// Latest unresolved (status='new') count.
  int get unresolvedCount => _unresolvedCount;

  /// Most recent (up to 20) incident events in reverse-chronological order.
  List<Map<String, dynamic>> get recent => List.unmodifiable(_recent);

  /// True when the WebSocket is connected; false when polling-only.
  bool get isLive => _channel != null;

  /// Stream of new incidents — used by snackbar listeners.
  final StreamController<Map<String, dynamic>> _eventController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get newIncidentStream => _eventController.stream;

  void _authChanged() {
    if (_auth.state == AuthState.authenticated && !_running) {
      _start();
    } else if (_auth.state != AuthState.authenticated && _running) {
      _stop();
    }
  }

  Future<void> _start() async {
    if (_running) return;
    _running = true;
    await _seedInitialCount();
    _connectWs();
  }

  void _stop() {
    _running = false;
    _channel?.sink.close();
    _channel = null;
    _sub?.cancel();
    _sub = null;
    _pollTimer?.cancel();
    _pollTimer = null;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _wsAttempts = 0;
    _recent.clear();
    _unresolvedCount = 0;
    notifyListeners();
  }

  Future<void> _seedInitialCount() async {
    try {
      final resp = await _api.getIncidents(status: 'new', limit: 20);
      final items = (resp['items'] as List?) ?? const [];
      _recent
        ..clear()
        ..addAll(items.cast<Map<String, dynamic>>());
      _unresolvedCount = (resp['total'] as num?)?.toInt() ?? items.length;
      notifyListeners();
    } catch (_) {
      // ignored — connection may not be ready yet
    }
  }

  void _connectWs() {
    final token = ApiService.authToken;
    if (token == null || token.isEmpty) return;
    final url = '${AppConfig.wsBaseUrl}/ws/incidents?token=$token';
    try {
      _channel = WebSocketChannel.connect(Uri.parse(url));
      _sub = _channel!.stream.listen(
        _onWsMessage,
        onError: (_) => _onWsClose(),
        onDone: _onWsClose,
        cancelOnError: true,
      );
      _wsAttempts = 0;
      notifyListeners();
    } catch (_) {
      _onWsClose();
    }
  }

  void _onWsMessage(dynamic raw) {
    try {
      final data = (raw is String) ? jsonDecode(raw) : raw;
      if (data is! Map) return;
      final type = data['type'];
      if (type == 'ping') return;
      // Treat as incident event
      _addEvent(Map<String, dynamic>.from(data));
    } catch (_) {}
  }

  void _onWsClose() {
    _channel?.sink.close();
    _channel = null;
    _sub?.cancel();
    _sub = null;
    if (!_running) return;
    _wsAttempts += 1;
    if (_wsAttempts >= 3) {
      _startPolling();
      return;
    }
    final backoff = Duration(seconds: 2 * (1 << (_wsAttempts - 1))); // 2,4,8
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(backoff, _connectWs);
    notifyListeners();
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 15), (_) async {
      try {
        final resp = await _api.getIncidents(status: 'new', limit: 20);
        final items = ((resp['items'] as List?) ?? const []).cast<Map<String, dynamic>>();
        final knownIds = _recent.map((e) => e['id']).toSet();
        for (final item in items.reversed) {
          if (!knownIds.contains(item['id'])) {
            _addEvent(item);
          }
        }
        _unresolvedCount = (resp['total'] as num?)?.toInt() ?? items.length;
        notifyListeners();
      } catch (_) {}
    });
    notifyListeners();
  }

  void _addEvent(Map<String, dynamic> evt) {
    final id = evt['id'];
    // Capture the prior version's status (if any) BEFORE we replace it, so we
    // can adjust the unresolved count correctly on re-emits (reconnect,
    // polling-then-WS, etc) without double-counting.
    final priorIdx = _recent.indexWhere((e) => e['id'] == id);
    final priorStatus = priorIdx >= 0 ? (_recent[priorIdx]['status'] as String?) : null;

    if (priorIdx >= 0) _recent.removeAt(priorIdx);
    _recent.insert(0, evt);
    if (_recent.length > 20) _recent.removeRange(20, _recent.length);

    final newStatus = (evt['status'] as String?) ?? 'new';
    final wasNew = priorStatus == 'new';
    final isNew = newStatus == 'new';
    if (!wasNew && isNew) {
      _unresolvedCount += 1;
    } else if (wasNew && !isNew && _unresolvedCount > 0) {
      _unresolvedCount -= 1;
    }
    // wasNew == isNew == true → no change (the more important fix)
    // priorStatus == null && isNew → first time we see this, +1 (handled above)

    _eventController.add(evt);
    notifyListeners();
  }

  /// Inject an event from another transport (e.g. an FCM foreground message
  /// on mobile). De-duplicates against the WebSocket feed by `incident_id`.
  void injectIncidentEvent(Map<String, dynamic> evt) {
    if (evt['id'] == null) return;
    _addEvent(Map<String, dynamic>.from(evt));
  }

  /// Local-only update used by the Incidents screen so badges decrement
  /// immediately when the user acknowledges/resolves.
  void markStatusLocally(int incidentId, String newStatus) {
    final idx = _recent.indexWhere((e) => e['id'] == incidentId);
    if (idx >= 0) {
      final wasNew = (_recent[idx]['status'] as String?) == 'new';
      _recent[idx] = {..._recent[idx], 'status': newStatus};
      if (wasNew && newStatus != 'new' && _unresolvedCount > 0) {
        _unresolvedCount -= 1;
      } else if (!wasNew && newStatus == 'new') {
        _unresolvedCount += 1;
      }
      notifyListeners();
    } else {
      // Item not in cache — refresh initial count.
      _seedInitialCount();
    }
  }

  /// Force a refresh of the unresolved count + cached recent incidents.
  Future<void> refresh() async {
    await _seedInitialCount();
  }

  @override
  void dispose() {
    _auth.removeListener(_authChanged);
    _stop();
    _eventController.close();
    super.dispose();
  }
}
