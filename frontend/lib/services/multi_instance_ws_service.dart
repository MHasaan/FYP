import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../config/app_config.dart';

/// Multi-instance WebSocket service for managing multiple pipeline connections
/// Handles feed and results streams for multiple pipeline instances simultaneously
class MultiInstanceWsService {
  // Map of instance ID to WebSocket channels
  final Map<int, WebSocketChannel> _feedChannels = {};
  final Map<int, WebSocketChannel> _resultsChannels = {};

  // Map of instance ID to stream controllers
  final Map<int, StreamController<Map<String, dynamic>>> _feedControllers = {};
  final Map<int, StreamController<Map<String, dynamic>>> _resultsControllers = {};

  // Track connection states
  final Map<int, bool> _feedConnected = {};
  final Map<int, bool> _resultsConnected = {};
  final Map<int, bool> _intentionalDisconnect = {};
  final Map<int, DateTime> _lastFeedMessageAt = {};
  final Map<int, DateTime> _lastResultsMessageAt = {};
  final Map<int, int> _feedReconnectAttempts = {};
  final Map<int, int> _resultsReconnectAttempts = {};
  final Map<int, Timer> _feedReconnectTimers = {};
  final Map<int, Timer> _resultsReconnectTimers = {};

  /// Get feed stream for a specific instance
  Stream<Map<String, dynamic>> getFeedStream(int instanceId) {
    _feedControllers[instanceId] ??= StreamController<Map<String, dynamic>>.broadcast();
    return _feedControllers[instanceId]!.stream;
  }

  /// Get results stream for a specific instance
  Stream<Map<String, dynamic>> getResultsStream(int instanceId) {
    _resultsControllers[instanceId] ??= StreamController<Map<String, dynamic>>.broadcast();
    return _resultsControllers[instanceId]!.stream;
  }

  /// Connect to feed WebSocket for a specific instance
  void connectInstanceFeed(int instanceId) {
    if (_feedConnected[instanceId] == true) return;

    _intentionalDisconnect[instanceId] = false;
    _feedControllers[instanceId] ??= StreamController<Map<String, dynamic>>.broadcast();
    _feedReconnectTimers[instanceId]?.cancel();
    _feedReconnectTimers.remove(instanceId);

    try {
      final url = AppConfig.wsInstanceFeedUrl(instanceId);
      _feedChannels[instanceId]?.sink.close();
      _feedChannels[instanceId] = WebSocketChannel.connect(Uri.parse(url));
      _feedConnected[instanceId] = true;
      _feedReconnectAttempts[instanceId] = 0;

      _feedChannels[instanceId]!.stream.listen(
        (data) {
          try {
            final parsed = jsonDecode(data as String) as Map<String, dynamic>;
            _lastFeedMessageAt[instanceId] = DateTime.now();
            _feedControllers[instanceId]?.add(parsed);
          } catch (e) {
            debugPrint('Instance $instanceId feed parse error: $e');
          }
        },
        onError: (error) {
          debugPrint('Instance $instanceId feed WebSocket error: $error');
          _feedConnected[instanceId] = false;
          _reconnectInstanceFeed(instanceId);
        },
        onDone: () {
          debugPrint('Instance $instanceId feed WebSocket closed');
          _feedConnected[instanceId] = false;
          _reconnectInstanceFeed(instanceId);
        },
      );
    } catch (e) {
      debugPrint('Instance $instanceId feed connection error: $e');
      _feedConnected[instanceId] = false;
      _reconnectInstanceFeed(instanceId);
    }
  }

  /// Connect to results WebSocket for a specific instance
  void connectInstanceResults(int instanceId) {
    if (_resultsConnected[instanceId] == true) return;

    _intentionalDisconnect[instanceId] = false;
    _resultsControllers[instanceId] ??= StreamController<Map<String, dynamic>>.broadcast();
    _resultsReconnectTimers[instanceId]?.cancel();
    _resultsReconnectTimers.remove(instanceId);

    try {
      final url = AppConfig.wsInstanceResultsUrl(instanceId);
      _resultsChannels[instanceId]?.sink.close();
      _resultsChannels[instanceId] = WebSocketChannel.connect(Uri.parse(url));
      _resultsConnected[instanceId] = true;
      _resultsReconnectAttempts[instanceId] = 0;

      _resultsChannels[instanceId]!.stream.listen(
        (data) {
          try {
            final parsed = jsonDecode(data as String) as Map<String, dynamic>;
            _lastResultsMessageAt[instanceId] = DateTime.now();
            _resultsControllers[instanceId]?.add(parsed);
          } catch (e) {
            debugPrint('Instance $instanceId results parse error: $e');
          }
        },
        onError: (error) {
          debugPrint('Instance $instanceId results WebSocket error: $error');
          _resultsConnected[instanceId] = false;
          _reconnectInstanceResults(instanceId);
        },
        onDone: () {
          debugPrint('Instance $instanceId results WebSocket closed');
          _resultsConnected[instanceId] = false;
          _reconnectInstanceResults(instanceId);
        },
      );
    } catch (e) {
      debugPrint('Instance $instanceId results connection error: $e');
      _resultsConnected[instanceId] = false;
      _reconnectInstanceResults(instanceId);
    }
  }

  void _reconnectInstanceFeed(int instanceId) {
    if (_intentionalDisconnect[instanceId] == true) return;
    if (_feedReconnectTimers[instanceId]?.isActive == true) return;

    final attempts = (_feedReconnectAttempts[instanceId] ?? 0) + 1;
    _feedReconnectAttempts[instanceId] = attempts;
    final delaySeconds = attempts <= 1 ? 2 : (attempts <= 3 ? 4 : 8);
    _feedReconnectTimers[instanceId] = Timer(Duration(seconds: delaySeconds), () {
      if (_intentionalDisconnect[instanceId] != true) {
        connectInstanceFeed(instanceId);
      }
    });
  }

  void _reconnectInstanceResults(int instanceId) {
    if (_intentionalDisconnect[instanceId] == true) return;
    if (_resultsReconnectTimers[instanceId]?.isActive == true) return;

    final attempts = (_resultsReconnectAttempts[instanceId] ?? 0) + 1;
    _resultsReconnectAttempts[instanceId] = attempts;
    final delaySeconds = attempts <= 1 ? 2 : (attempts <= 3 ? 4 : 8);
    _resultsReconnectTimers[instanceId] = Timer(Duration(seconds: delaySeconds), () {
      if (_intentionalDisconnect[instanceId] != true) {
        connectInstanceResults(instanceId);
      }
    });
  }

  bool isFeedConnected(int instanceId) => _feedConnected[instanceId] == true;

  DateTime? lastFeedMessageAt(int instanceId) => _lastFeedMessageAt[instanceId];

  int feedReconnectAttempts(int instanceId) => _feedReconnectAttempts[instanceId] ?? 0;

  void forceReconnectFeed(int instanceId) {
    if (_intentionalDisconnect[instanceId] == true) {
      return;
    }
    _feedChannels[instanceId]?.sink.close();
    _feedConnected[instanceId] = false;
    _reconnectInstanceFeed(instanceId);
  }

  /// Connect both feed and results for an instance
  void connectInstance(int instanceId) {
    connectInstanceFeed(instanceId);
    connectInstanceResults(instanceId);
  }

  /// Disconnect a specific instance
  void disconnectInstance(int instanceId) {
    _intentionalDisconnect[instanceId] = true;
    _feedReconnectTimers[instanceId]?.cancel();
    _resultsReconnectTimers[instanceId]?.cancel();
    _feedChannels[instanceId]?.sink.close();
    _resultsChannels[instanceId]?.sink.close();
    _feedControllers[instanceId]?.close();
    _resultsControllers[instanceId]?.close();

    _feedChannels.remove(instanceId);
    _resultsChannels.remove(instanceId);
    _feedControllers.remove(instanceId);
    _resultsControllers.remove(instanceId);
    _feedConnected.remove(instanceId);
    _resultsConnected.remove(instanceId);
    _lastFeedMessageAt.remove(instanceId);
    _lastResultsMessageAt.remove(instanceId);
    _feedReconnectAttempts.remove(instanceId);
    _resultsReconnectAttempts.remove(instanceId);
    _feedReconnectTimers.remove(instanceId);
    _resultsReconnectTimers.remove(instanceId);
  }

  /// Disconnect all instances
  void disconnectAll() {
    final instanceIds = List<int>.from(_feedChannels.keys);
    for (final instanceId in instanceIds) {
      disconnectInstance(instanceId);
    }
  }

  /// Get list of connected instance IDs
  List<int> get connectedInstances => _feedChannels.keys.toList();

  /// Check if instance is connected (either feed or results)
  bool isInstanceConnected(int instanceId) {
    return _feedConnected[instanceId] == true || _resultsConnected[instanceId] == true;
  }
}