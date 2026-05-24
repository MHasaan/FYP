import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ── Brand palette ─────────────────────────────────────────────────────────────
// #3D8D7A  sage forest green
// #FFFACD  lemon chiffon cream
// #01949A  deep teal (primary)
// #FCB5AC  soft blush rose
// #DC9750  warm amber gold

// ── Severity colours ──────────────────────────────────────────────────────────
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
    high:     Color(0xFFDC9750),
    medium:   Color(0xFFB45309),
    low:      Color(0xFF3D8D7A),
    resolved: Color(0xFF57534E),
  );

  static const IncidentSeverityColors dark = IncidentSeverityColors(
    critical: Color(0xFFEF4444),
    high:     Color(0xFFDC9750),
    medium:   Color(0xFFF59E0B),
    low:      Color(0xFF3D8D7A),
    resolved: Color(0xFF78716C),
  );

  Color forSeverity(String? severity) {
    switch (severity?.toLowerCase()) {
      case 'critical': return critical;
      case 'high':     return high;
      case 'medium':   return medium;
      case 'low':      return low;
      default:         return resolved;
    }
  }

  @override
  IncidentSeverityColors copyWith({Color? critical, Color? high, Color? medium, Color? low, Color? resolved}) =>
      IncidentSeverityColors(
        critical: critical ?? this.critical,
        high:     high     ?? this.high,
        medium:   medium   ?? this.medium,
        low:      low      ?? this.low,
        resolved: resolved ?? this.resolved,
      );

  @override
  IncidentSeverityColors lerp(ThemeExtension<IncidentSeverityColors>? other, double t) {
    if (other is! IncidentSeverityColors) return this;
    return IncidentSeverityColors(
      critical: Color.lerp(critical, other.critical, t) ?? critical,
      high:     Color.lerp(high,     other.high,     t) ?? high,
      medium:   Color.lerp(medium,   other.medium,   t) ?? medium,
      low:      Color.lerp(low,      other.low,      t) ?? low,
      resolved: Color.lerp(resolved, other.resolved, t) ?? resolved,
    );
  }
}

// ── Status colours ─────────────────────────────────────────────────────────────
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
    success: Color(0xFF3D8D7A),
    warning: Color(0xFFDC9750),
    info:    Color(0xFF01949A),
    danger:  Color(0xFFB91C1C),
  );

  static const AppStatusColors dark = AppStatusColors(
    success: Color(0xFF3D8D7A),
    warning: Color(0xFFDC9750),
    info:    Color(0xFF01949A),
    danger:  Color(0xFFEF4444),
  );

  static const AppStatusColors fallback = light;

  @override
  AppStatusColors copyWith({Color? success, Color? warning, Color? info, Color? danger}) =>
      AppStatusColors(
        success: success ?? this.success,
        warning: warning ?? this.warning,
        info:    info    ?? this.info,
        danger:  danger  ?? this.danger,
      );

  @override
  AppStatusColors lerp(ThemeExtension<AppStatusColors>? other, double t) {
    if (other is! AppStatusColors) return this;
    return AppStatusColors(
      success: Color.lerp(success, other.success, t) ?? success,
      warning: Color.lerp(warning, other.warning, t) ?? warning,
      info:    Color.lerp(info,    other.info,    t) ?? info,
      danger:  Color.lerp(danger,  other.danger,  t) ?? danger,
    );
  }
}

// ── Theme ──────────────────────────────────────────────────────────────────────
class AppTheme {
  static bool isLightMode = false;

  // Brand constants
  static const Color brandTeal  = Color(0xFF01949A);
  static const Color brandSage  = Color(0xFF3D8D7A);
  static const Color brandCream = Color(0xFFFFFACD);
  static const Color brandBlush = Color(0xFFFCB5AC);
  static const Color brandAmber = Color(0xFFDC9750);

  // Legacy surface getters
  static Color get background        => isLightMode ? const Color(0xFFFAF9F0) : const Color(0xFF0A1310);
  static Color get surface           => isLightMode ? const Color(0xFFFFFFFF) : const Color(0xFF111E1C);
  static Color get surfaceHighlight  => isLightMode ? const Color(0xFFF0F7F5) : const Color(0xFF182820);
  static Color get primary           => isLightMode ? brandTeal : brandSage;
  static Color get textPrimary       => isLightMode ? const Color(0xFF0F1C1A) : const Color(0xFFF2F7F5);
  static Color get textSecondary     => isLightMode ? const Color(0xFF4A6860) : const Color(0xFF8AADA6);
  static Color get error             => const Color(0xFFB91C1C);
  static Color get success           => brandSage;
  static Color get warning           => brandAmber;

  static ThemeData _buildTheme(Brightness brightness) {
    final isLight = brightness == Brightness.light;
    final primaryColor = isLight ? brandTeal : brandSage;

    final baseScheme = ColorScheme.fromSeed(
      seedColor: primaryColor,
      brightness: brightness,
    );

    final scheme = baseScheme.copyWith(
      primary:              primaryColor,
      primaryContainer:     isLight ? const Color(0xFFB2EDE9) : const Color(0xFF0D3330),
      onPrimaryContainer:   isLight ? const Color(0xFF003836) : const Color(0xFFB2EDE9),
      secondary:            isLight ? brandSage : brandTeal,
      secondaryContainer:   isLight ? const Color(0xFFC8E8E2) : const Color(0xFF0D2922),
      onSecondaryContainer: isLight ? const Color(0xFF0D2922) : const Color(0xFFC8E8E2),
      tertiary:             brandAmber,
      tertiaryContainer:    isLight ? const Color(0xFFFDE8C8) : const Color(0xFF3D2207),
      onTertiaryContainer:  isLight ? const Color(0xFF3D2207) : const Color(0xFFFDE8C8),
      error:                const Color(0xFFB91C1C),
      errorContainer:       isLight ? const Color(0xFFFFDAD6) : const Color(0xFF7F1D1D),
      surface:              isLight ? const Color(0xFFFFFFFF) : const Color(0xFF111E1C),
      surfaceContainerHighest: isLight ? const Color(0xFFF0F7F5) : const Color(0xFF1A2F2B),
      surfaceContainerHigh:    isLight ? const Color(0xFFF5FAF8) : const Color(0xFF162824),
      surfaceContainer:        isLight ? const Color(0xFFFAFDF9) : const Color(0xFF0F1E1B),
      surfaceContainerLow:     isLight ? const Color(0xFFFCFEFC) : const Color(0xFF0D1A18),
      onSurface:            isLight ? const Color(0xFF0F1C1A) : const Color(0xFFF2F7F5),
      onSurfaceVariant:     isLight ? const Color(0xFF3D6059) : const Color(0xFF8AADA6),
      outline:              isLight ? const Color(0xFFB2CDC8) : const Color(0xFF2A4440),
      outlineVariant:       isLight ? const Color(0xFFD9EDEA) : const Color(0xFF1E3532),
    );

    // Typography: Cormorant Garamond for display, Outfit for UI, DM Sans for body
    final textTheme = GoogleFonts.dmSansTextTheme(
      (isLight ? ThemeData.light() : ThemeData.dark()).textTheme,
    ).copyWith(
      displayLarge:  GoogleFonts.cormorantGaramond(fontWeight: FontWeight.w700, fontSize: 57, letterSpacing: -1.0),
      displayMedium: GoogleFonts.cormorantGaramond(fontWeight: FontWeight.w700, fontSize: 45, letterSpacing: -0.5),
      displaySmall:  GoogleFonts.cormorantGaramond(fontWeight: FontWeight.w600, fontSize: 36, letterSpacing: -0.5),
      headlineLarge: GoogleFonts.outfit(fontWeight: FontWeight.w700, fontSize: 32, letterSpacing: -0.5),
      headlineMedium:GoogleFonts.outfit(fontWeight: FontWeight.w700, fontSize: 28, letterSpacing: -0.5),
      headlineSmall: GoogleFonts.outfit(fontWeight: FontWeight.w600, fontSize: 24, letterSpacing: -0.3),
      titleLarge:    GoogleFonts.outfit(fontWeight: FontWeight.w600, fontSize: 22, letterSpacing: -0.2),
      titleMedium:   GoogleFonts.outfit(fontWeight: FontWeight.w600, fontSize: 16),
      titleSmall:    GoogleFonts.outfit(fontWeight: FontWeight.w600, fontSize: 14),
      bodyLarge:     GoogleFonts.dmSans(fontWeight: FontWeight.w400, fontSize: 16),
      bodyMedium:    GoogleFonts.dmSans(fontWeight: FontWeight.w400, fontSize: 14),
      bodySmall:     GoogleFonts.dmSans(fontWeight: FontWeight.w400, fontSize: 12),
      labelLarge:    GoogleFonts.dmSans(fontWeight: FontWeight.w600, fontSize: 14),
      labelMedium:   GoogleFonts.dmSans(fontWeight: FontWeight.w600, fontSize: 12),
      labelSmall:    GoogleFonts.dmSans(fontWeight: FontWeight.w600, fontSize: 11),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      brightness: brightness,
      extensions: <ThemeExtension<dynamic>>[
        isLight ? AppStatusColors.light : AppStatusColors.dark,
        isLight ? IncidentSeverityColors.light : IncidentSeverityColors.dark,
      ],
      scaffoldBackgroundColor: isLight ? const Color(0xFFFAF9F0) : const Color(0xFF0A1310),
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0.5,
        backgroundColor: isLight ? const Color(0xFFFAF9F0) : const Color(0xFF0A1310),
        surfaceTintColor: Colors.transparent,
        foregroundColor: scheme.onSurface,
        centerTitle: false,
        titleTextStyle: GoogleFonts.outfit(
          fontWeight: FontWeight.w700,
          fontSize: 20,
          letterSpacing: -0.2,
          color: scheme.onSurface,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: isLight
                ? const Color(0xFFD9EDEA)
                : const Color(0xFF1E3532),
          ),
        ),
        shadowColor: isLight
            ? const Color(0xFF01949A).withValues(alpha: 0.08)
            : Colors.black.withValues(alpha: 0.4),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        thickness: 1,
        space: 1,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isLight ? const Color(0xFFF4FAF8) : scheme.surfaceContainerHighest,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFB91C1C)),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFB91C1C), width: 2),
        ),
        hintStyle: TextStyle(color: scheme.onSurfaceVariant.withValues(alpha: 0.6)),
        labelStyle: TextStyle(color: scheme.onSurfaceVariant),
        prefixIconColor: scheme.primary.withValues(alpha: 0.7),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: GoogleFonts.outfit(fontWeight: FontWeight.w600, fontSize: 15, letterSpacing: 0.2),
          elevation: 0,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: GoogleFonts.outfit(fontWeight: FontWeight.w600, fontSize: 15),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: GoogleFonts.outfit(fontWeight: FontWeight.w600, fontSize: 15),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: scheme.surfaceContainerHighest,
        side: BorderSide(color: scheme.outlineVariant),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        labelStyle: GoogleFonts.dmSans(color: scheme.onSurfaceVariant, fontWeight: FontWeight.w600, fontSize: 12),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: scheme.surface,
        indicatorColor: scheme.primary.withValues(alpha: 0.14),
        selectedIconTheme: IconThemeData(color: scheme.primary),
        selectedLabelTextStyle: GoogleFonts.outfit(color: scheme.primary, fontWeight: FontWeight.w700, fontSize: 12),
        unselectedIconTheme: IconThemeData(color: scheme.onSurfaceVariant),
        unselectedLabelTextStyle: GoogleFonts.outfit(color: scheme.onSurfaceVariant, fontWeight: FontWeight.w500, fontSize: 12),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: isLight ? const Color(0xFFFFFFFF) : const Color(0xFF111E1C),
        surfaceTintColor: Colors.transparent,
        shadowColor: isLight
            ? Colors.black.withValues(alpha: 0.08)
            : Colors.black.withValues(alpha: 0.5),
        elevation: 8,
        indicatorColor: scheme.primary.withValues(alpha: 0.14),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return GoogleFonts.outfit(
            color: selected ? scheme.primary : scheme.onSurfaceVariant,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            fontSize: 11,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: selected ? scheme.primary : scheme.onSurfaceVariant,
            size: 22,
          );
        }),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        height: 68,
      ),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      badgeTheme: const BadgeThemeData(
        backgroundColor: Color(0xFFB91C1C),
        textColor: Colors.white,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        backgroundColor: isLight ? const Color(0xFF0F1C1A) : const Color(0xFFF2F7F5),
        contentTextStyle: GoogleFonts.dmSans(
          color: isLight ? Colors.white : const Color(0xFF0F1C1A),
          fontSize: 14,
        ),
      ),
    );
  }

  static ThemeData get lightTheme => _buildTheme(Brightness.light);
  static ThemeData get darkTheme  => _buildTheme(Brightness.dark);
}
