import 'package:flutter/foundation.dart';
import 'api_service.dart';
import 'push_service.dart';
import 'storage_service.dart';

enum AuthState { unknown, unauthenticated, authenticated }

/// Single source of truth for authentication.
///
/// Wraps `StorageService` (persistence) and `ApiService` (network) to:
/// - boot the app deciding whether to show LoginScreen or AppShell;
/// - log in / register / log out;
/// - propagate 401s back to a clean unauthenticated state.
class AuthController extends ChangeNotifier {
  AuthController(this._api, this._storage, {PushService? pushService})
      : _push = pushService {
    ApiService.registerOn401(_handle401);
  }

  final ApiService _api;
  final StorageService _storage;
  final PushService? _push;

  AuthState _state = AuthState.unknown;
  Map<String, dynamic>? _user;
  String? _error;
  bool _busy = false;

  AuthState get state => _state;
  Map<String, dynamic>? get user => _user;
  String? get error => _error;
  bool get busy => _busy;

  String get role => (_user?['role'] as String?) ?? '';
  String get fullName => (_user?['full_name'] as String?) ?? '';
  String get email => (_user?['email'] as String?) ?? '';
  int? get userId => (_user?['id'] as num?)?.toInt();

  bool get isAdmin     => role == 'admin';
  bool get isCaregiver => role == 'caregiver';
  bool get isRelative  => role == 'patient_relative';
  bool get isCareTeam  => isAdmin || isCaregiver;

  bool hasRole(String r) => role == r;

  /// Called once on app start. Decides initial state.
  Future<void> bootstrap() async {
    final token = _storage.authToken;
    if (token == null || token.isEmpty) {
      _setState(AuthState.unauthenticated);
      return;
    }

    ApiService.setAuthToken(token);
    try {
      final me = await _api.getCurrentUser();
      _user = me;
      await _storage.setAuthSession(token, me);
      _setState(AuthState.authenticated);
    } catch (_) {
      // Stale or revoked token.
      await _storage.clearAuthSession();
      ApiService.setAuthToken(null);
      _setState(AuthState.unauthenticated);
    }
  }

  Future<bool> login(String email, String password) async {
    _setBusy(true);
    _error = null;
    try {
      final res = await _api.login(email.trim(), password);
      final token = res['access_token'] as String?;
      final user = res['user'] as Map<String, dynamic>?;
      if (token == null || user == null) {
        _error = 'Unexpected response from server';
        return false;
      }
      ApiService.setAuthToken(token);
      _user = user;
      await _storage.setAuthSession(token, user);
      _setState(AuthState.authenticated);
      // Fire-and-forget push registration so the sign-in flow stays snappy.
      // ignore: discarded_futures
      _push?.ensurePermissionAndRegister();
      return true;
    } catch (e) {
      _error = _friendlyError(e, defaultMsg: 'Sign-in failed');
      notifyListeners();
      return false;
    } finally {
      _setBusy(false);
    }
  }

  Future<bool> register({
    required String fullName,
    required String email,
    required String password,
    required String role,
    String? phone,
  }) async {
    _setBusy(true);
    _error = null;
    try {
      final payload = <String, dynamic>{
        'full_name': fullName.trim(),
        'email': email.trim(),
        'password': password,
        'role': role,
        if (phone != null && phone.trim().isNotEmpty) 'phone': phone.trim(),
      };
      final res = await _api.registerUser(payload);
      final token = res['access_token'] as String?;
      final user = res['user'] as Map<String, dynamic>?;
      if (token == null || user == null) {
        _error = 'Unexpected response from server';
        return false;
      }
      ApiService.setAuthToken(token);
      _user = user;
      await _storage.setAuthSession(token, user);
      _setState(AuthState.authenticated);
      // ignore: discarded_futures
      _push?.ensurePermissionAndRegister();
      return true;
    } catch (e) {
      _error = _friendlyError(e, defaultMsg: 'Account creation failed');
      notifyListeners();
      return false;
    } finally {
      _setBusy(false);
    }
  }

  Future<void> logout() async {
    // Deactivate push BEFORE clearing the token so the API call still has auth.
    try {
      await _push?.deactivateOnLogout();
    } catch (_) {}
    final token = _storage.authToken;
    if (token != null && token.isNotEmpty) {
      try {
        await _api.logout(token);
      } catch (_) {}
    }
    await _storage.clearAuthSession();
    ApiService.setAuthToken(null);
    _user = null;
    _error = null;
    _setState(AuthState.unauthenticated);
  }

  Future<void> refreshMe() async {
    try {
      final me = await _api.getCurrentUser();
      _user = me;
      final token = _storage.authToken;
      if (token != null) await _storage.setAuthSession(token, me);
      notifyListeners();
    } catch (_) {
      await _handle401();
    }
  }

  /// Called once after `bootstrap()` resolves to authenticated, so an existing
  /// session that started before PushService initialized still gets a token
  /// registered with the backend.
  Future<void> bootstrapPushIfAuthenticated() async {
    if (_state == AuthState.authenticated) {
      // ignore: discarded_futures
      _push?.ensurePermissionAndRegister();
    }
  }

  Future<int> usersCount() => _api.getUsersCount();

  void clearError() {
    if (_error != null) {
      _error = null;
      notifyListeners();
    }
  }

  Future<void> _handle401() async {
    if (_state == AuthState.unauthenticated) return;
    await _storage.clearAuthSession();
    ApiService.setAuthToken(null);
    _user = null;
    _setState(AuthState.unauthenticated);
  }

  String _friendlyError(Object e, {required String defaultMsg}) {
    if (e is ApiException) {
      if (e.statusCode == 401) return 'Invalid email or password';
      if (e.statusCode == 403) {
        return 'You don\'t have permission to perform this action';
      }
      if (e.statusCode == 409) return 'An account with this email already exists';
      if (e.statusCode == 422) return 'Please check the details you entered';
      if (e.message.isNotEmpty) return e.message;
    }
    return '$defaultMsg. Please check your connection and try again.';
  }

  void _setState(AuthState s) {
    _state = s;
    notifyListeners();
  }

  void _setBusy(bool v) {
    _busy = v;
    notifyListeners();
  }

  @override
  void dispose() {
    ApiService.registerOn401(null);
    super.dispose();
  }
}
