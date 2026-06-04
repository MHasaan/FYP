// Generated from android/app/google-services.json — Android-only setup.
// Re-generate by running `flutterfire configure` (which also handles iOS/web)
// when you need more platforms.

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  /// Returns the options for the current platform, or `null` for platforms
  /// we haven't configured (web, iOS, desktop). PushService gracefully skips
  /// Firebase initialization when this is null.
  static FirebaseOptions? get currentPlatform {
    if (kIsWeb) return null;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      default:
        return null;
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyA7or-8NvLWO9elzh5d2yqHJq7m3mhlwnk',
    appId: '1:177437345281:android:09e36fc66019f29457a200',
    messagingSenderId: '177437345281',
    projectId: 'eldercarefyp-c5407',
    storageBucket: 'eldercarefyp-c5407.firebasestorage.app',
  );
}
