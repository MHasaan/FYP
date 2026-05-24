import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';

/// Friendly empty state with a glowing icon halo + soft entrance animation.
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;
  final IconData? actionIcon;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
    this.actionIcon,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Glowing halo behind icon
            Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        AppTheme.brandTeal.withValues(alpha: 0.20),
                        AppTheme.brandTeal.withValues(alpha: 0.0),
                      ],
                    ),
                  ),
                ),
                Container(
                  width: 76,
                  height: 76,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        AppTheme.brandTeal.withValues(alpha: 0.18),
                        AppTheme.brandSage.withValues(alpha: 0.14),
                      ],
                    ),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppTheme.brandTeal.withValues(alpha: 0.25),
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Icon(icon, color: AppTheme.brandTeal, size: 32),
                )
                    .animate(onPlay: (c) => c.repeat(reverse: true))
                    .scaleXY(begin: 1.0, end: 1.06, duration: 1800.ms, curve: Curves.easeInOut),
              ],
            ),
            const SizedBox(height: 24),
            Text(
              title,
              style: GoogleFonts.outfit(
                fontSize: 19,
                fontWeight: FontWeight.w700,
                color: cs.onSurface,
                letterSpacing: -0.2,
              ),
              textAlign: TextAlign.center,
            ).animate().fadeIn(duration: 300.ms).slideY(begin: 0.1, duration: 400.ms),
            if (subtitle != null) ...[
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: Text(
                  subtitle!,
                  style: GoogleFonts.dmSans(
                    fontSize: 14,
                    color: cs.onSurfaceVariant,
                    height: 1.55,
                  ),
                  textAlign: TextAlign.center,
                ),
              ).animate(delay: 100.ms).fadeIn(duration: 300.ms).slideY(begin: 0.1, duration: 400.ms),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: onAction,
                icon: Icon(actionIcon ?? Icons.add_rounded, size: 18),
                label: Text(actionLabel!),
              ).animate(delay: 200.ms).fadeIn(duration: 300.ms).slideY(begin: 0.1, duration: 400.ms),
            ],
          ],
        ),
      ),
    );
  }
}
