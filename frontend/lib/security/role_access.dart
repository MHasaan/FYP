/// Role-based access helpers used everywhere.
class RoleAccess {
  static const String admin    = 'admin';
  static const String caregiver = 'caregiver';
  static const String relative  = 'patient_relative';

  static bool isAdmin(String role)     => role == admin;
  static bool isCaregiver(String role) => role == caregiver;
  static bool isPatientRelative(String role) => role == relative;
  static bool isRelative(String role)  => role == relative;

  /// Care team: admin + caregiver.
  static bool isCareTeam(String role) => isAdmin(role) || isCaregiver(role);

  static bool canViewMonitor({required bool isAuthenticated, required String role}) =>
      isAuthenticated && isCareTeam(role);

  static bool canViewLive({required bool isAuthenticated, String role = ''}) =>
      isAuthenticated && (role.isEmpty || isCareTeam(role));

  static bool canViewInsights({required bool isAuthenticated}) => isAuthenticated;

  static bool canUseAdminConsole({required bool isAuthenticated, required String role}) =>
      isAuthenticated && isAdmin(role);

  static bool canControlPipeline({required String role}) => isCareTeam(role);
  static bool canManageCameras({required String role})   => isCareTeam(role);
  static bool canManagePatients({required String role})  => isCareTeam(role);
  static bool canManageDetectionRules({required String role}) => isCareTeam(role);
  static bool canManageUsers({required String role}) => isAdmin(role);
  static bool canViewSystem({required String role}) => isAdmin(role);

  /// Display label for a given role.
  static String labelFor(String role) {
    switch (role) {
      case admin: return 'Admin';
      case caregiver: return 'Caregiver';
      case relative: return 'Family';
      default: return 'User';
    }
  }

  static String footerTitle({required bool isAuthenticated, required String role}) {
    if (!isAuthenticated) return 'Guest';
    return labelFor(role);
  }

  static String footerSubtitle({required bool isAuthenticated, required String role}) {
    if (!isAuthenticated) return 'Sign in required';
    if (isAdmin(role))     return 'Full access';
    if (isCaregiver(role)) return 'Care operations';
    if (isRelative(role))  return 'Family view';
    return 'Restricted';
  }
}
