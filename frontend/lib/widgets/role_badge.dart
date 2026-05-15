import 'package:flutter/material.dart';
import '../theme/app_icons.dart';

/// Pill showing a user role with appropriate icon and colour.
class RoleBadge extends StatelessWidget {
  final String role;
  final bool dense;

  const RoleBadge({super.key, required this.role, this.dense = false});

  ({String label, Color color, IconData icon}) _meta(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    switch (role) {
      case 'admin':
        return (label: 'Admin', color: cs.primary, icon: AppIcons.admin);
      case 'caregiver':
        return (label: 'Caregiver', color: cs.tertiary, icon: AppIcons.caregiver);
      case 'patient_relative':
        return (label: 'Family', color: cs.secondary, icon: AppIcons.relative);
      default:
        return (label: 'User', color: cs.onSurfaceVariant, icon: AppIcons.account);
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = _meta(context);
    final hPad = dense ? 8.0 : 10.0;
    final vPad = dense ? 3.0 : 5.0;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: hPad, vertical: vPad),
      decoration: BoxDecoration(
        color: m.color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: m.color.withValues(alpha: 0.30)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(m.icon, color: m.color, size: dense ? 12 : 14),
          SizedBox(width: dense ? 4 : 6),
          Text(
            m.label,
            style: TextStyle(
              color: m.color,
              fontWeight: FontWeight.w700,
              fontSize: dense ? 11 : 12,
            ),
          ),
        ],
      ),
    );
  }
}
