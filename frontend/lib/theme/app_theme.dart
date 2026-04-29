import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

@immutable
class AppStatusColors extends ThemeExtension<AppStatusColors> {
  final Color success;
  final Color warning;

  const AppStatusColors({
    required this.success,
    required this.warning,
  });

  static const AppStatusColors light = AppStatusColors(
    success: Color(0xFF16A34A),
    warning: Color(0xFFD97706),
  );

  static const AppStatusColors dark = AppStatusColors(
    success: Color(0xFF16A34A),
    warning: Color(0xFFD97706),
  );

  static const AppStatusColors fallback = light;

  @override
  AppStatusColors copyWith({Color? success, Color? warning}) {
    return AppStatusColors(
      success: success ?? this.success,
      warning: warning ?? this.warning,
    );
  }

  @override
  AppStatusColors lerp(ThemeExtension<AppStatusColors>? other, double t) {
    if (other is! AppStatusColors) {
      return this;
    }
    return AppStatusColors(
      success: Color.lerp(success, other.success, t) ?? success,
      warning: Color.lerp(warning, other.warning, t) ?? warning,
    );
  }
}

class AppTheme {
  static bool isLightMode = false;

  // Brand seed (controls the generated ColorScheme).
  static const Color seed = Color(0xFF2563EB);

  // Legacy getters (still used across screens/widgets). We'll phase these out
  // by moving usage to Theme.of(context).colorScheme + ThemeExtensions.
  static Color get background => isLightMode ? const Color(0xFFF6F7FB) : const Color(0xFF0B1220);
  static Color get surface => isLightMode ? const Color(0xFFFFFFFF) : const Color(0xFF0F1B2E);
  static Color get surfaceHighlight => isLightMode ? const Color(0xFFF1F3F7) : const Color(0xFF17233A);
  static Color get primary => seed;
  static Color get accent => isLightMode ? const Color(0xFF0EA5E9) : const Color(0xFF38BDF8);
  static Color get textPrimary => isLightMode ? const Color(0xFF0F172A) : const Color(0xFFEAF0FF);
  static Color get textSecondary => isLightMode ? const Color(0xFF475569) : const Color(0xFFA7B4CF);
  static Color get error => const Color(0xFFDC2626);
  static Color get success => const Color(0xFF16A34A);
  static Color get warning => const Color(0xFFD97706);

  static ThemeData _buildTheme(Brightness brightness) {
    final baseScheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
    );

    final isLight = brightness == Brightness.light;

    // Enterprise-light surfaces: neutral background + crisp white cards.
    final scheme = baseScheme.copyWith(
      surface: isLight ? const Color(0xFFFFFFFF) : const Color(0xFF0F1B2E),
      surfaceContainerHighest: isLight ? const Color(0xFFF1F3F7) : const Color(0xFF17233A),
      surfaceContainerHigh: isLight ? const Color(0xFFF6F7FB) : const Color(0xFF121F35),
      surfaceContainer: isLight ? const Color(0xFFF8F9FC) : const Color(0xFF0D192B),
      onSurface: isLight ? const Color(0xFF0F172A) : const Color(0xFFEAF0FF),
      onSurfaceVariant: isLight ? const Color(0xFF475569) : const Color(0xFFA7B4CF),
      outline: isLight ? const Color(0xFFE2E8F0) : const Color(0xFF263450),
      error: error,
      secondary: isLight ? const Color(0xFF0EA5E9) : const Color(0xFF38BDF8),
    );

    final textTheme = GoogleFonts.interTextTheme(
      (brightness == Brightness.light ? ThemeData.light() : ThemeData.dark()).textTheme,
    ).copyWith(
      displaySmall: GoogleFonts.inter(fontWeight: FontWeight.w700),
      headlineMedium: GoogleFonts.inter(fontWeight: FontWeight.w700),
      titleLarge: GoogleFonts.inter(fontWeight: FontWeight.w700),
      titleMedium: GoogleFonts.inter(fontWeight: FontWeight.w600),
      bodyLarge: GoogleFonts.inter(fontWeight: FontWeight.w400),
      bodyMedium: GoogleFonts.inter(fontWeight: FontWeight.w400),
      labelLarge: GoogleFonts.inter(fontWeight: FontWeight.w600),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      brightness: brightness,
      extensions: <ThemeExtension<dynamic>>[
        isLight ? AppStatusColors.light : AppStatusColors.dark,
      ],
      scaffoldBackgroundColor: isLight ? const Color(0xFFF6F7FB) : const Color(0xFF0B1220),
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: isLight ? const Color(0xFFF6F7FB) : const Color(0xFF0B1220),
        foregroundColor: scheme.onSurface,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surface,
        surfaceTintColor: const Color(0x00000000),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: scheme.outlineVariant.withValues(alpha: isLight ? 1 : 0.45)),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant.withValues(alpha: isLight ? 1 : 0.35),
        thickness: 1,
        space: 1,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
        hintStyle: TextStyle(color: scheme.onSurfaceVariant),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: scheme.surfaceContainerHighest,
        side: BorderSide(color: scheme.outlineVariant),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        labelStyle: TextStyle(color: scheme.onSurfaceVariant, fontWeight: FontWeight.w600),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: scheme.surface,
        indicatorColor: scheme.primary.withValues(alpha: 0.10),
        selectedIconTheme: IconThemeData(color: scheme.primary),
        selectedLabelTextStyle: TextStyle(color: scheme.primary, fontWeight: FontWeight.w700),
        unselectedIconTheme: IconThemeData(color: scheme.onSurfaceVariant),
        unselectedLabelTextStyle: TextStyle(color: scheme.onSurfaceVariant),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surface,
        indicatorColor: scheme.primary.withValues(alpha: 0.12),
        labelTextStyle: WidgetStateProperty.all(
          TextStyle(color: scheme.onSurfaceVariant, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  static ThemeData get lightTheme {
    return _buildTheme(Brightness.light);
  }

  static ThemeData get darkTheme {
    return _buildTheme(Brightness.dark);
  }
}

