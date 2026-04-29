import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../config/app_config.dart';

/// WebSocket service for real-time feed and results streaming
class WsService {
  WebSocketChannel? _feedChannel;
  WebSocketChannel? _resultsChannel;

  StreamController<Map<String, dynamic>>? _feedController;
  StreamController<Map<String, dynamic>>? _resultsController;

  // Flag to prevent reconnection after intentional disconnect
  bool _intentionalDisconnect = false;

  /// Stream of live video frames
  /// Each event: {"frame_id": int, "image": "base64_jpeg"}
  Stream<Map<String, dynamic>> get feedStream {
    _feedController ??= StreamController<Map<String, dynamic>>.broadcast();
    return _feedController!.stream;
  }

  /// Stream of real-time ML results
  /// Each event: {"frame_id": int, "results": {...}, "timing": {...}}
  Stream<Map<String, dynamic>> get resultsStream {
    _resultsController ??= StreamController<Map<String, dynamic>>.broadcast();
    return _resultsController!.stream;
  }

  /// Connect to the live feed WebSocket
  void connectFeed() {
    _intentionalDisconnect = false;
    _feedController ??= StreamController<Map<String, dynamic>>.broadcast();
    try {
      _feedChannel = WebSocketChannel.connect(Uri.parse(AppConfig.wsFeedUrl));
      _feedChannel!.stream.listen(
        (data) {
          try {
            final parsed = jsonDecode(data as String) as Map<String, dynamic>;
            _feedController?.add(parsed);
          } catch (e) {
            print('Feed parse error: $e');
          }
        },
        onError: (error) {
          print('Feed WebSocket error: $error');
          _reconnectFeed();
        },
        onDone: () {
          print('Feed WebSocket closed');
          _reconnectFeed();
        },
      );
    } catch (e) {
      print('Feed connection error: $e');
      _reconnectFeed();
    }
  }

  /// Connect to the results WebSocket
  void connectResults() {
    _intentionalDisconnect = false;
    _resultsController ??= StreamController<Map<String, dynamic>>.broadcast();
    try {
      _resultsChannel =
          WebSocketChannel.connect(Uri.parse(AppConfig.wsResultsUrl));
      _resultsChannel!.stream.listen(
        (data) {
          try {
            final parsed = jsonDecode(data as String) as Map<String, dynamic>;
            _resultsController?.add(parsed);
          } catch (e) {
            print('Results parse error: $e');
          }
        },
        onError: (error) {
          print('Results WebSocket error: $error');
          _reconnectResults();
        },
        onDone: () {
          print('Results WebSocket closed');
          _reconnectResults();
        },
      );
    } catch (e) {
      print('Results connection error: $e');
      _reconnectResults();
    }
  }

  void _reconnectFeed() {
    // Don't reconnect if disconnect was intentional
    if (_intentionalDisconnect) return;

    Future.delayed(const Duration(seconds: 3), () {
      if (!_intentionalDisconnect) {
        connectFeed();
      }
    });
  }

  void _reconnectResults() {
    // Don't reconnect if disconnect was intentional
    if (_intentionalDisconnect) return;

    Future.delayed(const Duration(seconds: 3), () {
      if (!_intentionalDisconnect) {
        connectResults();
      }
    });
  }

  /// Disconnect all WebSocket connections
  void disconnect() {
    _intentionalDisconnect = true;
    _feedChannel?.sink.close();
    _resultsChannel?.sink.close();
    _feedController?.close();
    _resultsController?.close();
    _feedController = null;
    _resultsController = null;
  }
}
