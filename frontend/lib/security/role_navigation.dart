import 'package:flutter/material.dart';
import '../theme/app_icons.dart';
import 'role_access.dart';

/// Single navigation item.
class NavItem {
  final String key;
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final WidgetBuilder builder;

  const NavItem({
    required this.key,
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.builder,
  });
}

typedef NavBuilder = WidgetBuilder;

/// Returns the navigation set appropriate for the user's role.
class RoleNavigation {
  /// Resolve the navigation list for the given role. Each entry maps to a
  /// builder that the AppShell will render when selected.
  static List<NavItem> itemsForRole({
    required String role,
    required NavBuilder dashboardBuilder,
    required NavBuilder liveMonitorBuilder,
    required NavBuilder incidentsBuilder,
    required NavBuilder patientsBuilder,
    required NavBuilder camerasBuilder,
    required NavBuilder detectionRulesBuilder,
    required NavBuilder reportsBuilder,
    required NavBuilder usersBuilder,
    required NavBuilder systemBuilder,
    required NavBuilder accountBuilder,
    required NavBuilder relativeHomeBuilder,
  }) {
    if (RoleAccess.isAdmin(role)) {
      return [
        NavItem(key: 'dashboard',  label: 'Dashboard',       icon: AppIcons.dashboard,      selectedIcon: AppIcons.dashboard,      builder: dashboardBuilder),
        NavItem(key: 'live',       label: 'Live Monitor',    icon: AppIcons.live,           selectedIcon: AppIcons.live,           builder: liveMonitorBuilder),
        NavItem(key: 'incidents',  label: 'Incidents',       icon: AppIcons.incidents,      selectedIcon: AppIcons.incidents,      builder: incidentsBuilder),
        NavItem(key: 'patients',   label: 'Patients',        icon: AppIcons.patients,       selectedIcon: AppIcons.patients,       builder: patientsBuilder),
        NavItem(key: 'cameras',    label: 'Cameras',         icon: AppIcons.cameras,        selectedIcon: AppIcons.cameras,        builder: camerasBuilder),
        NavItem(key: 'detection',  label: 'Detection rules', icon: AppIcons.detectionRules, selectedIcon: AppIcons.detectionRules, builder: detectionRulesBuilder),
        NavItem(key: 'reports',    label: 'Reports',         icon: AppIcons.reports,        selectedIcon: AppIcons.reports,        builder: reportsBuilder),
        NavItem(key: 'users',      label: 'Users',           icon: AppIcons.users,          selectedIcon: AppIcons.users,          builder: usersBuilder),
        NavItem(key: 'system',     label: 'System',          icon: AppIcons.system,         selectedIcon: AppIcons.system,         builder: systemBuilder),
        NavItem(key: 'account',    label: 'Account',         icon: AppIcons.account,        selectedIcon: AppIcons.account,        builder: accountBuilder),
      ];
    }
    if (RoleAccess.isCaregiver(role)) {
      return [
        NavItem(key: 'dashboard',  label: 'Dashboard',       icon: AppIcons.dashboard,      selectedIcon: AppIcons.dashboard,      builder: dashboardBuilder),
        NavItem(key: 'live',       label: 'Live Monitor',    icon: AppIcons.live,           selectedIcon: AppIcons.live,           builder: liveMonitorBuilder),
        NavItem(key: 'incidents',  label: 'Incidents',       icon: AppIcons.incidents,      selectedIcon: AppIcons.incidents,      builder: incidentsBuilder),
        NavItem(key: 'patients',   label: 'Patients',        icon: AppIcons.patients,       selectedIcon: AppIcons.patients,       builder: patientsBuilder),
        NavItem(key: 'detection',  label: 'Detection rules', icon: AppIcons.detectionRules, selectedIcon: AppIcons.detectionRules, builder: detectionRulesBuilder),
        NavItem(key: 'reports',    label: 'Reports',         icon: AppIcons.reports,        selectedIcon: AppIcons.reports,        builder: reportsBuilder),
        NavItem(key: 'account',    label: 'Account',         icon: AppIcons.account,        selectedIcon: AppIcons.account,        builder: accountBuilder),
      ];
    }
    // patient_relative
    return [
      NavItem(key: 'home',      label: 'Home',      icon: AppIcons.home,      selectedIcon: AppIcons.home,      builder: relativeHomeBuilder),
      NavItem(key: 'incidents', label: 'Incidents', icon: AppIcons.incidents, selectedIcon: AppIcons.incidents, builder: incidentsBuilder),
      NavItem(key: 'account',   label: 'Account',   icon: AppIcons.account,   selectedIcon: AppIcons.account,   builder: accountBuilder),
    ];
  }

  /// Default landing tab key for a role.
  static String defaultKeyForRole(String role) {
    if (RoleAccess.isAdmin(role)) return 'dashboard';
    if (RoleAccess.isCaregiver(role)) return 'incidents';
    return 'home';
  }

  /// Resolve initial index from a `?tab=` URL param against a list of items.
  static int resolveInitialIndex(List<NavItem> items, String? rawTab, String role) {
    final fallback = items.indexWhere((i) => i.key == defaultKeyForRole(role));
    if (rawTab == null || rawTab.trim().isEmpty) return fallback >= 0 ? fallback : 0;
    final lower = rawTab.trim().toLowerCase();
    final match = items.indexWhere((i) => i.key == lower);
    if (match >= 0) return match;
    return fallback >= 0 ? fallback : 0;
  }
}
