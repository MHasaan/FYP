import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'theme/app_theme.dart';
import 'security/role_navigation.dart';
import 'services/api_service.dart';
import 'services/auth_controller.dart';
import 'services/incident_stream_service.dart';
import 'services/push_service.dart';
import 'services/storage_service.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/splash_screen.dart';
import 'screens/account/account_screen.dart';
import 'screens/cameras/cameras_screen.dart';
import 'screens/dashboard.dart';
import 'screens/detection_rules/detection_rules_screen.dart';
import 'screens/home/relative_home_screen.dart';
import 'screens/incidents/incidents_screen.dart';
import 'screens/live/live_monitor_screen.dart';
import 'screens/patients/patients_screen.dart';
import 'screens/reports/reports_screen.dart';
import 'screens/system/system_screen.dart';
import 'screens/users/users_screen.dart';
import 'screens/visual_search/visual_search_screen.dart';
import 'utils/browser_location.dart';
import 'widgets/app_shell.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final storage = StorageService();
  await storage.init();

  final api = ApiService();
  final push = PushService();
  final auth = AuthController(api, storage, pushService: push);
  final incidents = IncidentStreamService(auth);

  // Initialize FCM (no-op on web / when firebase_options is unconfigured).
  // ignore: discarded_futures
  push.initialize(api: api, storage: storage, incidentStream: incidents);

  // Hydrate token before AuthController.bootstrap() so /api/auth/me works.
  ApiService.setAuthToken(storage.authToken);

  // Kick off boot in the background; UI shows splash until done. After it
  // resolves, register push token if the session is already authenticated.
  // ignore: discarded_futures
  auth.bootstrap().then((_) => auth.bootstrapPushIfAuthenticated());

  runApp(EldercareApp(
    storage: storage,
    auth: auth,
    incidents: incidents,
    push: push,
  ));
}

class EldercareApp extends StatelessWidget {
  final StorageService storage;
  final AuthController auth;
  final IncidentStreamService incidents;
  final PushService push;

  const EldercareApp({
    super.key,
    required this.storage,
    required this.auth,
    required this.incidents,
    required this.push,
  });

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<StorageService>.value(value: storage),
        ChangeNotifierProvider<AuthController>.value(value: auth),
        ChangeNotifierProvider<IncidentStreamService>.value(value: incidents),
        Provider<PushService>.value(value: push),
      ],
      child: Consumer<StorageService>(
        builder: (context, store, __) {
          final brightness = MediaQuery.platformBrightnessOf(context);
          AppTheme.isLightMode = store.themeMode == ThemeMode.light ||
              (store.themeMode == ThemeMode.system && brightness == Brightness.light);
          return MaterialApp(
            title: 'Eldercare',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: store.themeMode,
            home: const _AuthGate(),
          );
        },
      ),
    );
  }
}

// ── Auth gate ───────────────────────────────────────────────────────────────
class _AuthGate extends StatelessWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthController>(
      builder: (_, auth, __) {
        switch (auth.state) {
          case AuthState.unknown:
            return const SplashScreen();
          case AuthState.unauthenticated:
            return const LoginScreen();
          case AuthState.authenticated:
            return _RoleShell(role: auth.role);
        }
      },
    );
  }
}

// ── Role-aware shell ────────────────────────────────────────────────────────
class _RoleShell extends StatefulWidget {
  final String role;
  const _RoleShell({required this.role});

  @override
  State<_RoleShell> createState() => _RoleShellState();
}

class _RoleShellState extends State<_RoleShell> {
  String? _initialTabKey;

  @override
  void initState() {
    super.initState();
    _initialTabKey = _resolveTabFromUrl();
  }

  String? _resolveTabFromUrl() {
    final href = browserLocationHref();
    if (href == null || href.trim().isEmpty) return null;
    final uri = Uri.tryParse(href.trim());
    if (uri == null) return null;
    final raw = (uri.queryParameters['tab'] ?? '').trim().toLowerCase();
    return raw.isEmpty ? null : raw;
  }

  @override
  Widget build(BuildContext context) {
    final items = RoleNavigation.itemsForRole(
      role: widget.role,
      dashboardBuilder:      (_) => const DashboardScreen(),
      liveMonitorBuilder:    (_) => const LiveMonitorScreen(),
      incidentsBuilder:      (_) => const IncidentsScreen(),
      patientsBuilder:       (_) => const PatientsScreen(),
      camerasBuilder:        (_) => const CamerasScreen(),
      detectionRulesBuilder: (_) => const DetectionRulesScreen(),
      reportsBuilder:        (_) => const ReportsScreen(),
      usersBuilder:          (_) => const UsersScreen(),
      systemBuilder:         (_) => const SystemScreen(),
      accountBuilder:        (_) => const AccountScreen(),
      relativeHomeBuilder:   (_) => const RelativeHomeScreen(),
      visualSearchBuilder:   (_) => const VisualSearchScreen(),
    );

    final initialIndex = RoleNavigation.resolveInitialIndex(items, _initialTabKey, widget.role);

    return AppShell(items: items, initialIndex: initialIndex);
  }
}
