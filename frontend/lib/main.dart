import 'package:flutter/material.dart';
import 'package:animations/animations.dart';
import 'package:provider/provider.dart';
import 'theme/app_theme.dart';
import 'widgets/sidebar.dart';
import 'services/storage_service.dart';
import 'services/api_service.dart';
import 'screens/dashboard.dart';
import 'screens/live_feed.dart';
import 'screens/settings.dart';
import 'screens/history.dart';
import 'screens/multi_camera_grid.dart';
import 'utils/browser_location.dart';
import 'security/role_access.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final storageService = StorageService();
  await storageService.init();
  ApiService.setAuthToken(storageService.authToken);

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: storageService),
      ],
      child: const FYPApp(),
    ),
  );
}

class FYPApp extends StatelessWidget {
  const FYPApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<StorageService>(
      builder: (context, storage, child) {
        final platformBrightness = MediaQuery.platformBrightnessOf(context);
        AppTheme.isLightMode = storage.themeMode == ThemeMode.light || (storage.themeMode == ThemeMode.system && platformBrightness == Brightness.light);

        return MaterialApp(
          title: 'FYP ML Pipeline',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: storage.themeMode,
          home: const MainApp(),
        );
      },
    );
  }
}
class MainApp extends StatefulWidget {
  const MainApp({super.key});

  @override
  State<MainApp> createState() => MainAppState();
}

class MainAppState extends State<MainApp> {
  int _selectedIndex = 0;

  Uri _resolveLaunchUri() {
    final href = browserLocationHref();
    if (href != null && href.trim().isNotEmpty) {
      final parsed = Uri.tryParse(href.trim());
      if (parsed != null) {
        return parsed;
      }
    }
    return Uri.base;
  }

  int _resolveInitialIndexFromUrl() {
    final launchUri = _resolveLaunchUri();
    final rawTab = (launchUri.queryParameters['tab'] ?? '').trim().toLowerCase();
    if (rawTab.isEmpty) {
      return 0;
    }

    final numeric = int.tryParse(rawTab);
    if (numeric != null && numeric >= 0 && numeric <= 4) {
      return numeric;
    }

    const namedMap = <String, int>{
      // New IA names
      'overview': 0,
      'dashboard': 0,
      'monitor': 1,
      'multi-cam': 1,
      'multicam': 1,
      'multi': 1,
      'live': 2,
      'live-feed': 2,
      'admin': 3,
      'settings': 3,
      'insights': 4,
      'history': 4,
    };

    return namedMap[rawTab] ?? 0;
  }

  @override
  void initState() {
    super.initState();
    _selectedIndex = _resolveInitialIndexFromUrl();
  }

  final List<NavigationDestination> _destinations = const [
    NavigationDestination(
      icon: Icon(Icons.space_dashboard_outlined),
      selectedIcon: Icon(Icons.space_dashboard_rounded),
      label: 'Overview',
    ),
    NavigationDestination(
      icon: Icon(Icons.view_module_outlined),
      selectedIcon: Icon(Icons.view_module_rounded),
      label: 'Monitor',
    ),
    NavigationDestination(
      icon: Icon(Icons.videocam_outlined),
      selectedIcon: Icon(Icons.videocam_rounded),
      label: 'Live',
    ),
    NavigationDestination(
      icon: Icon(Icons.tune_outlined),
      selectedIcon: Icon(Icons.tune_rounded),
      label: 'Admin',
    ),
    NavigationDestination(
      icon: Icon(Icons.insights_outlined),
      selectedIcon: Icon(Icons.insights_rounded),
      label: 'Insights',
    ),
  ];

  void _onItemTapped(int index) {
    setState(() => _selectedIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    final storage = context.watch<StorageService>();
    final role = storage.authRole;
    final isAuthenticated = storage.hasAuthSession;
    final screens = <Widget>[
      DashboardScreen(onNavigate: _onItemTapped),
      RoleAccess.canViewMonitor(isAuthenticated: isAuthenticated, role: role)
          ? MultiCameraGridScreen(onNavigateToTab: _onItemTapped)
          : const _RestrictedScreen(
              title: 'Monitor access is restricted',
              message: 'Only admin and caregiver accounts can access multi-camera control.',
            ),
      RoleAccess.canViewLive(isAuthenticated: isAuthenticated)
          ? const LiveFeedScreen()
          : const _RestrictedScreen(
              title: 'Live view requires sign-in',
              message: 'Sign in with an assigned Eldercare account to view live streams.',
            ),
      const SettingsScreen(),
      RoleAccess.canViewInsights(isAuthenticated: isAuthenticated)
          ? const HistoryScreen()
          : const _RestrictedScreen(
              title: 'Insights require sign-in',
              message: 'Sign in to review incidents, sessions, and recordings.',
            ),
    ];

    final safeIndex = _selectedIndex.clamp(0, screens.length - 1) as int;

    final isWide = MediaQuery.of(context).size.width > 800;

    return Scaffold(
      body: isWide
          ? Row(
              children: [
                SideNavigation(
                  selectedIndex: safeIndex,
                  onItemSelected: _onItemTapped,
                  destinations: _destinations,
                  footerTitle: RoleAccess.footerTitle(
                    isAuthenticated: isAuthenticated,
                    role: role,
                  ),
                  footerSubtitle: RoleAccess.footerSubtitle(
                    isAuthenticated: isAuthenticated,
                    role: role,
                  ),
                ),
                Expanded(
                  child: SafeArea(
                        child: PageTransitionSwitcher(
                          duration: const Duration(milliseconds: 300),
                          transitionBuilder: (child, primaryAnimation, secondaryAnimation) {
                            return FadeThroughTransition(
                              animation: primaryAnimation,
                              secondaryAnimation: secondaryAnimation,
                              fillColor: Theme.of(context).scaffoldBackgroundColor,
                              child: child,
                            );
                          },
                          child: KeyedSubtree(
                            key: ValueKey<int>(safeIndex),
                            child: screens[safeIndex],
                          ),
                        ),
                  ),
                ),
              ],
            )
          : SafeArea(child: screens[safeIndex]),
      bottomNavigationBar: isWide
          ? null
          : NavigationBar(
              selectedIndex: safeIndex,
              onDestinationSelected: _onItemTapped,
              destinations: _destinations,
            ),
    );
  }
}

class _RestrictedScreen extends StatelessWidget {
  final String title;
  final String message;

  const _RestrictedScreen({
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: Card(
          margin: const EdgeInsets.all(24),
          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock_outline_rounded, size: 40, color: colorScheme.primary),
                const SizedBox(height: 12),
                Text(
                  title,
                  style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  message,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurface.withValues(alpha: 0.75),
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
