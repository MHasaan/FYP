import 'package:flutter/material.dart';

/// Centralised icon map so every domain concept always renders the same icon.
class AppIcons {
  AppIcons._();

  // Navigation
  static const IconData dashboard   = Icons.space_dashboard_rounded;
  static const IconData monitor     = Icons.view_module_rounded;
  static const IconData live        = Icons.videocam_rounded;
  static const IconData incidents   = Icons.warning_amber_rounded;
  static const IconData patients    = Icons.person_rounded;
  static const IconData cameras     = Icons.camera_alt_rounded;
  static const IconData detectionRules = Icons.tune_rounded;
  static const IconData reports     = Icons.summarize_rounded;
  static const IconData users       = Icons.group_rounded;
  static const IconData system      = Icons.settings_rounded;
  static const IconData account     = Icons.manage_accounts_rounded;
  static const IconData home        = Icons.home_rounded;

  // Roles
  static const IconData admin       = Icons.shield_rounded;
  static const IconData caregiver   = Icons.health_and_safety_rounded;
  static const IconData relative    = Icons.family_restroom_rounded;

  // Incidents
  static const IconData fall        = Icons.warning_amber_rounded;
  static const IconData seizure     = Icons.bolt_rounded;
  static const IconData manual      = Icons.flag_rounded;

  // Actions
  static const IconData acknowledge = Icons.check_circle_outline_rounded;
  static const IconData resolve     = Icons.task_alt_rounded;
  static const IconData reopen      = Icons.refresh_rounded;
  static const IconData signOut     = Icons.logout_rounded;
  static const IconData add         = Icons.add_rounded;
  static const IconData edit        = Icons.edit_rounded;
  static const IconData delete      = Icons.delete_outline_rounded;
  static const IconData refresh     = Icons.refresh_rounded;
  static const IconData filter      = Icons.filter_list_rounded;
  static const IconData search      = Icons.search_rounded;
  static const IconData export      = Icons.download_rounded;
  static const IconData more        = Icons.more_vert_rounded;
  static const IconData close       = Icons.close_rounded;
  static const IconData check       = Icons.check_rounded;
  static const IconData info        = Icons.info_outline_rounded;
  static const IconData alert       = Icons.notifications_rounded;
  static const IconData alertOff    = Icons.notifications_off_outlined;
  static const IconData start       = Icons.play_arrow_rounded;
  static const IconData stop        = Icons.stop_rounded;
  static const IconData pause       = Icons.pause_rounded;
  static const IconData resume      = Icons.play_circle_outline_rounded;
  static const IconData password    = Icons.lock_outline_rounded;
  static const IconData eye         = Icons.visibility_rounded;
  static const IconData eyeOff      = Icons.visibility_off_rounded;
  static const IconData calendar    = Icons.calendar_today_rounded;
  static const IconData phone       = Icons.phone_rounded;
  static const IconData email       = Icons.email_rounded;
  static const IconData location    = Icons.location_on_rounded;
  static const IconData risk        = Icons.priority_high_rounded;
  static const IconData patient     = Icons.person_rounded;
  static const IconData chart       = Icons.bar_chart_rounded;
  static const IconData trend       = Icons.trending_up_rounded;
  static const IconData overlay     = Icons.layers_rounded;
  static const IconData overlayOff  = Icons.layers_clear_rounded;
  static const IconData visualSearch = Icons.image_search_rounded;

  /// Returns the icon for a given incident event_type string.
  static IconData forEventType(String? eventType) {
    switch (eventType?.toLowerCase()) {
      case 'fall':    return fall;
      case 'seizure': return seizure;
      default:        return manual;
    }
  }

  /// Returns the icon for a given user role string.
  static IconData forRole(String? role) {
    switch (role) {
      case 'admin':            return admin;
      case 'caregiver':        return caregiver;
      case 'patient_relative': return relative;
      default:                 return account;
    }
  }
}
