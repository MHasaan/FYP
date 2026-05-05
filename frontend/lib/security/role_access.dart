class RoleAccess {
  static bool isAdmin(String role) => role == 'admin';
  static bool isCaregiver(String role) => role == 'caregiver';
  static bool isPatientRelative(String role) => role == 'patient_relative';

  static bool isCareTeam(String role) => isAdmin(role) || isCaregiver(role);

  static bool canViewMonitor({required bool isAuthenticated, required String role}) =>
      isAuthenticated && isCareTeam(role);

  static bool canViewLive({required bool isAuthenticated}) => isAuthenticated;

  static bool canViewInsights({required bool isAuthenticated}) => isAuthenticated;

  static bool canUseAdminConsole({required bool isAuthenticated, required String role}) =>
      isAuthenticated && isCareTeam(role);

  static String footerTitle({required bool isAuthenticated, required String role}) {
    if (!isAuthenticated) return 'Guest';
    if (isAdmin(role)) return 'Admin';
    if (isCaregiver(role)) return 'Caregiver';
    if (isPatientRelative(role)) return 'Family';
    return 'User';
  }

  static String footerSubtitle({required bool isAuthenticated, required String role}) {
    if (!isAuthenticated) return 'Sign in required';
    if (isAdmin(role)) return 'Full access';
    if (isCaregiver(role)) return 'Care operations';
    if (isPatientRelative(role)) return 'Read-only care view';
    return 'Restricted';
  }
}
