import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class StorageService extends ChangeNotifier {
  static const String _themeModeKey = 'theme_mode';
  static const String _cameraSourceKey = 'camera_source';
  static const String _cameraHistoryKey = 'camera_history';
  static const String _authTokenKey = 'auth_token';
  static const String _authUserKey = 'auth_user';

  late SharedPreferences _prefs;

  ThemeMode _themeMode = ThemeMode.system;
  ThemeMode get themeMode => _themeMode;

  String _lastCameraSource = '0';
  String get lastCameraSource => _lastCameraSource;

  List<String> _cameraHistory = [];
  List<String> get cameraHistory => _cameraHistory;

  String? _authToken;
  Map<String, dynamic>? _authUser;
  String? get authToken => _authToken;
  Map<String, dynamic>? get authUser => _authUser;
  String get authRole => (_authUser?['role'] as String?) ?? '';
  String get authName => (_authUser?['full_name'] as String?) ?? '';
  String get authEmail => (_authUser?['email'] as String?) ?? '';
  bool get hasAuthSession => _authToken != null && _authToken!.isNotEmpty;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();

    final themeString = _prefs.getString(_themeModeKey);
    if (themeString != null) {
      if (themeString == 'light') _themeMode = ThemeMode.light;
      if (themeString == 'dark') _themeMode = ThemeMode.dark;
    }

    _lastCameraSource = _prefs.getString(_cameraSourceKey) ?? '0';
    _cameraHistory = _prefs.getStringList(_cameraHistoryKey) ?? [];

    _authToken = _prefs.getString(_authTokenKey);
    final rawUser = _prefs.getString(_authUserKey);
    if (rawUser != null && rawUser.isNotEmpty) {
      try {
        _authUser = jsonDecode(rawUser) as Map<String, dynamic>;
      } catch (_) {
        _authUser = null;
      }
    }
    
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    notifyListeners();

    const themeModeMap = {
      ThemeMode.light: 'light',
      ThemeMode.dark: 'dark',
      ThemeMode.system: 'system',
    };

    await _prefs.setString(_themeModeKey, themeModeMap[mode] ?? 'system');
  }

  Future<void> setLastCameraSource(String sourceUrl) async {
    _lastCameraSource = sourceUrl;
    
    if (!_cameraHistory.contains(sourceUrl) && sourceUrl.isNotEmpty) {
      _cameraHistory.insert(0, sourceUrl);
      if (_cameraHistory.length > 20) {
        _cameraHistory = _cameraHistory.sublist(0, 20);
      }
      await _prefs.setStringList(_cameraHistoryKey, _cameraHistory);
    } else if (_cameraHistory.contains(sourceUrl)) {
      _cameraHistory.remove(sourceUrl);
      _cameraHistory.insert(0, sourceUrl);
      await _prefs.setStringList(_cameraHistoryKey, _cameraHistory);
    }

    notifyListeners();
    await _prefs.setString(_cameraSourceKey, sourceUrl);
  }
  
  Future<void> removeCameraSourceFromHistory(String sourceUrl) async {
    _cameraHistory.remove(sourceUrl);
    notifyListeners();
    await _prefs.setStringList(_cameraHistoryKey, _cameraHistory);
  }

  Future<void> setAuthSession(String token, Map<String, dynamic> user) async {
    _authToken = token;
    _authUser = user;
    notifyListeners();
    await _prefs.setString(_authTokenKey, token);
    await _prefs.setString(_authUserKey, jsonEncode(user));
  }

  Future<void> clearAuthSession() async {
    _authToken = null;
    _authUser = null;
    notifyListeners();
    await _prefs.remove(_authTokenKey);
    await _prefs.remove(_authUserKey);
  }
}
