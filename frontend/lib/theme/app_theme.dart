import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ── Severity colours for incident chips/stripes ─────────────────────────────
@immutable
class IncidentSeverityColors extends ThemeExtension<IncidentSeverityColors> {
  final Color critical;
  final Color high;
  final Color medium;
  final Color low;
  final Color resolved;

  const IncidentSeverityColors({
    required this.critical,
    required this.high,
    required this.medium,
    required this.low,
    required this.resolved,
  });

  static const IncidentSeverityColors light = IncidentSeverityColors(
    critical: Color(0xFFB91C1C),
    high: Color(0xFFC2410C),
    medium: Color(0xFFB45309),
    low: Color(0xFF4D7C0F),
    resolved: Color(0xFF57534E),
  );

  static const IncidentSeverityColors dark = IncidentSeverityColors(
    critical: Color(0xFFEF4444),
    high: Color(0xFFF97316),
    medium: Color(0xFFF59E0B),
    low: Color(0xFF84CC16),
    resolved: Color(0xFF78716C),
  );

  Color forSeverity(String? severity) {
    switch (severity?.toLowerCase()) {
      case 'critical': return critical;
      case 'high': return high;
      case 'medium': return medium;
      case 'low': return low;
      default: return resolved;
    }
  }

  @override
  IncidentSeverityColors copyWith({Color? critical, Color? high, Color? medium, Color? low, Color? resolved}) {
    return IncidentSeverityColors(
      critical: critical ?? this.critical,
      high: high ?? this.high,
      medium: medium ?? this.medium,
      low: low ?? this.low,
      resolved: resolved ?? this.resolved,
    );
  }

  @override
  IncidentSeverityColors lerp(ThemeExtension<IncidentSeverityColors>? other, double t) {
    if (other is! IncidentSeverityColors) return this;
    return IncidentSeverityColors(
      critical: Color.lerp(critical, other.critical, t) ?? critical,
      high: Color.lerp(high, other.high, t) ?? high,
      medium: Color.lerp(medium, other.medium, t) ?? medium,
      low: Color.lerp(low, other.low, t) ?? low,
      resolved: Color.lerp(resolved, other.resolved, t) ?? resolved,
    );
  }
}

// ── Status colours ───────────────────────────────────────────────────────────
@immutable
class AppStatusColors extends ThemeExtension<AppStatusColors> {
  final Color success;
  final Color warning;
  final Color info;
  final Color danger;

  const AppStatusColors({
    required this.success,
    required this.warning,
    required this.info,
    required this.danger,
  });

  static const AppStatusColors light = AppStatusColors(
    success: Color(0xFF15803D),
    warning: Color(0xFFB45309),
    info: Color(0xFF0369A1),
    danger: Color(0xFFB91C1C),
  );

  static const AppStatusColors dark = AppStatusColors(
    success: Color(0xFF22C55E),
    warning: Color(0xFFF59E0B),
    info: Color(0xFF38BDF8),
    danger: Color(0xFFEF4444),
  );

  static const AppStatusColors fallback = light;

  @override
  AppStatusColors copyWith({Color? success, Color? warning, Color? info, Color? danger}) {
    return AppStatusColors(
      success: success ?? this.success,
      warning: warning ?? this.warning,
      info: info ?? this.info,
      danger: danger ?? this.danger,
    );
  }

  @override
  AppStatusColors lerp(ThemeExtension<AppStatusColors>? other, double t) {
    if (other is! AppStatusColors) return this;
    return AppStatusColors(
      success: Color.lerp(success, other.success, t) ?? success,
      warning: Color.lerp(warning, other.warning, t) ?? warning,
      info: Color.lerp(info, other.info, t) ?? info,
      danger: Color.lerp(danger, other.danger, t) ?? danger,
    );
  }
}

// ── Theme ────────────────────────────────────────────────────────────────────
class AppTheme {
  static bool isLightMode = false;

  // Primary brand: calm teal (medical)
  static const Color _primaryLight = Color(0xFF0F766E);
  static const Color _primaryDark  = Color(0xFF2DD4BF);

  // Legacy surface getters still referenced in older screens
  static Color get background => isLightMode ? const Color(0xFFFAFAF7) : const Color(0xFF0F1419);
  static Color get surface     => isLightMode ? const Color(0xFFFFFFFF) : const Color(0xFF151E27);
  static Color get surfaceHighlight => isLightMode ? const Color(0xFFF1F0EA) : const Color(0xFF1A2129);
  static Color get primary     => isLightMode ? _primaryLight : _primaryDark;
  static Color get textPrimary => isLightMode ? const Color(0xFF1C1917) : const Color(0xFFF5F5F4);
  static Color get textSecondary => isLightMode ? const Color(0xFF57534E) : const Color(0xFFA8A29E);
  static Color get error       => const Color(0xFFB91C1C);
  static Color get success     => const Color(0xFF15803D);
  static Color get warning     => const Color(0xFFB45309);

  static ThemeData _buildTheme(Brightness brightness) {
    final isLight = brightness == Brightness.light;
    final primaryColor = isLight ? _primaryLight : _primaryDark;

    final baseScheme = ColorScheme.fromSeed(
      seedColor: primaryColor,
      brightness: brightness,
    );

    final scheme = baseScheme.copyWith(
      primary: primaryColor,
      primaryContainer: isLight ? const Color(0xFFCCFBF1) : const Color(0xFF134E4A),
      onPrimaryContainer: isLight ? const Color(0xFF134E4A) : const Color(0xFFCCFBF1),
      secondary: isLight ? const Color(0xFFB45309) : const Color(0xFFF59E0B),
      secondaryContainer: isLight ? const Color(0xFFFEF3C7) : const Color(0xFF78350F),
      onSecondaryContainer: isLight ? const Color(0xFF78350F) : const Color(0xFFFEF3C7),
      tertiary: isLight ? const Color(0xFF6366F1) : const Color(0xFF818CF8),
      surface: isLight ? const Color(0xFFFFFFFF) : const Color(0xFF151E27),
      surfaceContainerHighest: isLight ? const Color(0xFFF1F0EA) : const Color(0xFF1A2129),
      surfaceContainerHigh: isLight ? const Color(0xFFF5F4EF) : const Color(0xFF1D2630),
      surfaceContainer: isLight ? const Color(0xFFFAFAF7) : const Color(0xFF131C24),
      surfaceContainerLow: isLight ? const Color(0xFFFDFCF8) : const Color(0xFF111921),
      onSurface: isLight ? const Color(0xFF1C1917) : const Color(0xFFF5F5F4),
      onSurfaceVariant: isLight ? const Color(0xFF57534E) : const Color(0xFFA8A29E),
      outline: isLight ? const Color(0xFFD6D3D1) : const Color(0xFF3F4954),
      outlineVariant: isLight ? const Color(0xFFE7E5E4) : const Color(0xFF2A3441),
      error: const Color(0xFFB91C1C),
      errorContainer: isLight ? const Color(0xFFFEE2E2) : const Color(0xFF7F1D1D),
    );

    // Typography: Plus Jakarta Sans for display/headlines, Inter for body
    final textTheme = GoogleFonts.interTextTheme(
      (isLight ? ThemeData.light() : ThemeData.dark()).textTheme,
    ).copyWith(
      displayLarge:  GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700, fontSize: 57),
      displayMedium: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700, fontSize: 45),
      displaySmall:  GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700, fontSize: 36),
      headlineLarge: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700, fontSize: 32),
      headlineMedium:GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700, fontSize: 28),
      headlineSmall: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600, fontSize: 24),
      titleLarge:    GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600, fontSize: 22),
      titleMedium:   GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600, fontSize: 16),
      titleSmall:    GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600, fontSize: 14),
      bodyLarge:     GoogleFonts.inter(fontWeight: FontWeight.w400, fontSize: 16),
      bodyMedium:    GoogleFonts.inter(fontWeight: FontWeight.w400, fontSize: 14),
      bodySmall:     GoogleFonts.inter(fontWeight: FontWeight.w400, fontSize: 12),
      labelLarge:    GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 14),
      labelMedium:   GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 12),
      labelSmall:    GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 11),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      brightness: brightness,
      extensions: <ThemeExtension<dynamic>>[
        isLight ? AppStatusColors.light : AppStatusColors.dark,
        isLight ? IncidentSeverityColors.light : IncidentSeverityColors.dark,
      ],
      scaffoldBackgroundColor: isLight ? const Color(0xFFFAFAF7) : const Color(0xFF0F1419),
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: isLight ? const Color(0xFFFAFAF7) : const Color(0xFF0F1419),
        foregroundColor: scheme.onSurface,
        centerTitle: false,
        titleTextStyle: GoogleFonts.plusJakartaSans(
          fontWeight: FontWeight.w700,
          fontSize: 20,
          color: scheme.onSurface,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: isLight ? 1.0 : 0.6),
          ),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant.withValues(alpha: isLight ? 1.0 : 0.4),
        thickness: 1,
        space: 1,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isLight ? const Color(0xFFFAFAF7) : scheme.surfaceContainerHighest,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFB91C1C)),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFB91C1C), width: 1.5),
        ),
        hintStyle: TextStyle(color: scheme.onSurfaceVariant.withValues(alpha: 0.7)),
        labelStyle: TextStyle(color: scheme.onSurfaceVariant),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 14),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 14),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 14),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: scheme.surfaceContainerHighest,
        side: BorderSide(color: scheme.outlineVariant),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        labelStyle: GoogleFonts.inter(color: scheme.onSurfaceVariant, fontWeight: FontWeight.w600, fontSize: 12),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: scheme.surface,
        indicatorColor: scheme.primary.withValues(alpha: 0.12),
        selectedIconTheme: IconThemeData(color: scheme.primary),
        selectedLabelTextStyle: GoogleFonts.inter(color: scheme.primary, fontWeight: FontWeight.w600, fontSize: 12),
        unselectedIconTheme: IconThemeData(color: scheme.onSurfaceVariant),
        unselectedLabelTextStyle: GoogleFonts.inter(color: scheme.onSurfaceVariant, fontWeight: FontWeight.w500, fontSize: 12),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surface,
        indicatorColor: scheme.primary.withValues(alpha: 0.12),
        labelTextStyle: WidgetStateProperty.all(
          GoogleFonts.inter(color: scheme.onSurfaceVariant, fontWeight: FontWeight.w600, fontSize: 12),
        ),
      ),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      badgeTheme: const BadgeThemeData(
        backgroundColor: Color(0xFFB91C1C),
        textColor: Colors.white,
      ),
    );
  }

  static ThemeData get lightTheme => _buildTheme(Brightness.light);
  static ThemeData get darkTheme  => _buildTheme(Brightness.dark);
}
