import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../firebase_options.dart';
import 'api_service.dart';
import 'incident_stream_service.dart';
import 'storage_service.dart';

/// Top-level background-message handler. Required to be a `@pragma` annotated
/// top-level function because FCM spawns a separate isolate for background
/// delivery on Android.
@pragma('vm:entry-point')
Future<void> _firebaseBackgroundMessageHandler(RemoteMessage message) async {
  // Re-init Firebase in the isolate; safe to call repeatedly.
  if (!kIsWeb) {
    final opts = DefaultFirebaseOptions.currentPlatform;
    if (opts != null) {
      try {
        await Firebase.initializeApp(options: opts);
      } catch (_) {
        // already initialized
      }
    }
  }
  // FCM auto-renders the system tray notification when `notification` is set
  // in the payload, so there is nothing to do here unless we want to do
  // background work (e.g. cache the incident). The foreground handler does
  // the in-app surfacing.
}

/// Singleton for FCM lifecycle: init, permission, token registration with
/// the backend, foreground display, and tap-to-deep-link.
class PushService {
  PushService._internal();
  static final PushService _instance = PushService._internal();
  factory PushService() => _instance;

  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;
  bool _firebaseAvailable = false;
  String? _currentToken;
  StreamSubscription<RemoteMessage>? _foregroundSub;
  StreamSubscription<RemoteMessage>? _tapSub;
  StreamSubscription<String>? _tokenRefreshSub;
  IncidentStreamService? _incidentStream;
  ApiService? _api;
  StorageService? _storage;

  /// Stream of `incident_id` values emitted whenever the user taps an alert
  /// notification. The shell listens and navigates to that incident.
  final StreamController<int> _tapIncidentController =
      StreamController<int>.broadcast();
  Stream<int> get onTapIncident => _tapIncidentController.stream;

  /// Cold-start payload (the notification that launched the app).
  Map<String, dynamic>? _initialMessageData;
  Map<String, dynamic>? consumeInitialMessageData() {
    final data = _initialMessageData;
    _initialMessageData = null;
    return data;
  }

  bool get isFirebaseAvailable => _firebaseAvailable;

  /// One-time setup. Safe to call on web (no-op).
  Future<void> initialize({
    required ApiService api,
    required StorageService storage,
    required IncidentStreamService incidentStream,
  }) async {
    _api = api;
    _storage = storage;
    _incidentStream = incidentStream;

    if (_initialized) return;
    _initialized = true;

    if (kIsWeb) return; // FCM web requires a VAPID key + service worker — skip for now.

    // Only Android / iOS proceed.
    if (!(Platform.isAndroid || Platform.isIOS)) return;

    final options = DefaultFirebaseOptions.currentPlatform;
    if (options == null) {
      debugPrint('PushService: Firebase options not configured. '
          'Run `flutterfire configure` to enable real push notifications.');
      return;
    }

    try {
      await Firebase.initializeApp(options: options);
      _firebaseAvailable = true;
    } catch (e) {
      debugPrint('PushService: Firebase.initializeApp failed: $e');
      return;
    }

    // System background isolate handler must be registered before any await.
    FirebaseMessaging.onBackgroundMessage(_firebaseBackgroundMessageHandler);

    // Local notifications channel for Android 8+. Channel id matches the value
    // sent by the backend in AndroidNotification.channel_id.
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await _localNotifications.initialize(
      const InitializationSettings(android: androidInit, iOS: iosInit),
      onDidReceiveNotificationResponse: (resp) {
        final payload = resp.payload;
        if (payload != null) _handleTapPayload(payload);
      },
    );

    if (Platform.isAndroid) {
      final androidPlugin = _localNotifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      await androidPlugin?.createNotificationChannel(
        const AndroidNotificationChannel(
          'eldercare_alerts',
          'Eldercare alerts',
          description: 'Real-time fall and seizure alerts',
          importance: Importance.high,
        ),
      );
    }

    // Capture cold-start tap.
    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null) {
      _initialMessageData = Map<String, dynamic>.from(initial.data);
      // Defer until something is listening on the stream.
      Future.microtask(() => _emitTapFromData(_initialMessageData!));
    }

    // Foreground messages → render local notification + inject into stream.
    _foregroundSub = FirebaseMessaging.onMessage.listen(_onForegroundMessage);

    // Background-tap → app brought to foreground.
    _tapSub = FirebaseMessaging.onMessageOpenedApp.listen((m) {
      _emitTapFromData(Map<String, dynamic>.from(m.data));
    });

    // Token refresh.
    _tokenRefreshSub = FirebaseMessaging.instance.onTokenRefresh.listen((t) {
      _currentToken = t;
      _registerTokenWithBackend(t);
    });
  }

  /// Request notification permission and register the FCM token with the
  /// backend so this device starts receiving pushes for the signed-in user.
  Future<bool> ensurePermissionAndRegister() async {
    if (!_firebaseAvailable) return false;
    if (_storage?.authToken == null) return false;

    final settings = await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    final granted =
        settings.authorizationStatus == AuthorizationStatus.authorized ||
            settings.authorizationStatus == AuthorizationStatus.provisional;
    if (!granted) return false;

    final token = await FirebaseMessaging.instance.getToken();
    if (token == null) return false;
    _currentToken = token;
    await _registerTokenWithBackend(token);
    return true;
  }

  Future<void> _registerTokenWithBackend(String token) async {
    final api = _api;
    final storage = _storage;
    if (api == null || storage == null) return;
    if (storage.authToken == null) return;
    final uid = (storage.authUser?['id'] as num?)?.toInt();
    try {
      final res = await api.registerDeviceToken({
        'device_token': token,
        'platform': 'fcm',
        if (uid != null) 'user_id': uid.toString(),
        'device_name': _deviceLabel(),
      });
      final id = (res['id'] as num?)?.toInt();
      if (id != null) await storage.setDeviceTokenId(id);
    } catch (e) {
      debugPrint('PushService: token registration failed: $e');
    }
  }

  /// Called from AuthController when the user signs out so the backend stops
  /// pushing to this device.
  Future<void> deactivateOnLogout() async {
    final api = _api;
    final storage = _storage;
    if (api == null || storage == null) return;
    final id = storage.deviceTokenId;
    if (id != null) {
      try {
        await api.deleteDeviceToken(id);
      } catch (_) {}
      await storage.setDeviceTokenId(null);
    }
    if (_firebaseAvailable) {
      try {
        await FirebaseMessaging.instance.deleteToken();
      } catch (_) {}
    }
    _currentToken = null;
  }

  Future<void> _onForegroundMessage(RemoteMessage message) async {
    final data = Map<String, dynamic>.from(message.data);
    final notification = message.notification;

    // 1. Render an in-system notification (FCM doesn't auto-render in foreground).
    if (notification != null && Platform.isAndroid) {
      await _localNotifications.show(
        notification.hashCode,
        notification.title,
        notification.body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'eldercare_alerts',
            'Eldercare alerts',
            channelDescription: 'Real-time fall and seizure alerts',
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
        payload: _encodeTapPayload(data),
      );
    }

    // 2. Echo into IncidentStreamService so the in-app badge/toast/list update.
    if (data['type'] == 'incident' && data['incident_id'] != null) {
      _incidentStream?.injectIncidentEvent({
        'id': int.tryParse(data['incident_id']?.toString() ?? '') ?? -1,
        'event_type': data['event_type'],
        'severity': data['severity'],
        'status': 'new',
        'patient_id': int.tryParse(data['patient_id']?.toString() ?? ''),
        'detected_at': DateTime.now().toUtc().toIso8601String(),
      });
    }
  }

  String _encodeTapPayload(Map<String, dynamic> data) {
    final id = data['incident_id']?.toString();
    return id == null ? '' : 'incident:$id';
  }

  void _handleTapPayload(String payload) {
    if (payload.startsWith('incident:')) {
      final id = int.tryParse(payload.substring(9));
      if (id != null) _tapIncidentController.add(id);
    }
  }

  void _emitTapFromData(Map<String, dynamic> data) {
    final id = int.tryParse(data['incident_id']?.toString() ?? '');
    if (id != null) _tapIncidentController.add(id);
  }

  String _deviceLabel() {
    if (kIsWeb) return 'Web browser';
    try {
      if (Platform.isAndroid) return 'Android device';
      if (Platform.isIOS) return 'iOS device';
    } catch (_) {}
    return 'Device';
  }

  Future<void> dispose() async {
    await _foregroundSub?.cancel();
    await _tapSub?.cancel();
    await _tokenRefreshSub?.cancel();
    await _tapIncidentController.close();
  }
}
