import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Bitconnect brand theme (dark, mesh-green).
///
/// Central design tokens so every screen shares a consistent visual language.
class AppTheme {
  // ---- Brand palette ----
  static const brandGreen = Color(0xFF2BD9A5);
  static const brandGreenSoft = Color(0xFF12B886);
  static const brandDeep = Color(0xFF0B6E4F);
  static const accentBlue = Color(0xFF4DABF7);
  static const accentAmber = Color(0xFFFFC94D);

  // ---- Neutrals ----
  static const surface = Color(0xFF0B100F);
  static const surfaceHigh = Color(0xFF101816);
  static const card = Color(0xFF16201D);
  static const elevated = Color(0xFF1E2B27);

  // ---- Surfaces ----
  static const surfaceGradientTop = Color(0xFF0E1614);
  static const surfaceGradientBottom = surface;

  // ---- Spacing scale ----
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;

  // ---- Radius ----
  static const double radiusSm = 8;
  static const double radiusMd = 12;
  static const double radiusLg = 16;
  static const double radiusXl = 22;

  /// A soft vertical gradient used behind screens.
  static LinearGradient backgroundGradient() => const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [surfaceGradientTop, surfaceGradientBottom],
      );

  /// Returns a deterministic color derived from a string seed (for avatars).
  static Color colorForSeed(String seed) {
    var hash = 0;
    for (final c in seed.codeUnits) {
      hash = (hash * 31 + c) & 0xffffffff;
    }
    const palette = <Color>[
      Color(0xFF12B886),
      Color(0xFF4DABF7),
      Color(0xFFFFC94D),
      Color(0xFFF071B5),
      Color(0xFFA78BFA),
      Color(0xFFF27C6D),
      Color(0xFF4DD0E1),
    ];
    return palette[hash.abs() % palette.length];
  }

  static ThemeData dark() {
    final base = ColorScheme.fromSeed(
      seedColor: brandGreen,
      brightness: Brightness.dark,
      primary: brandGreen,
      surface: surface,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: base,
      scaffoldBackgroundColor: surface,
      visualDensity: VisualDensity.standard,
      textTheme: Typography.whiteMountainView.apply(
        bodyColor: Colors.white.withValues(alpha: 0.9),
        displayColor: Colors.white,
      ),
      // AppBar
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        titleTextStyle: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w800,
          color: Colors.white,
          letterSpacing: 0.2,
        ),
      ),
      // Cards
      cardTheme: CardThemeData(
        color: card,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusLg),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.07)),
        ),
        margin: EdgeInsets.zero,
      ),
      // Inputs
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: elevated.withValues(alpha: 0.6),
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.10)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.10)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: const BorderSide(color: brandGreen, width: 1.6),
        ),
        labelStyle: TextStyle(
          color: Colors.white.withValues(alpha: 0.72),
          fontWeight: FontWeight.w500,
        ),
        hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.40)),
        helperStyle: TextStyle(color: Colors.white.withValues(alpha: 0.48)),
      ),
      // Buttons
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: brandGreen,
          foregroundColor: const Color(0xFF06251B),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusMd),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white.withValues(alpha: 0.9),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.16)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusMd),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: Colors.white.withValues(alpha: 0.85),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusMd),
          ),
        ),
      ),
      // Navigation
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: const Color(0xFF0F1715),
        indicatorColor: brandGreen.withValues(alpha: 0.20),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        labelTextStyle: WidgetStateProperty.resolveWith((s) {
          final selected = s.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
            color: selected ? brandGreen : Colors.white60,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((s) {
          final selected = s.contains(WidgetState.selected);
          return IconThemeData(
            color: selected ? brandGreen : Colors.white60,
            size: 24,
          );
        }),
        height: 68,
      ),
      // Snackbars
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: elevated,
        elevation: 6,
        contentTextStyle: const TextStyle(color: Colors.white),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMd),
        ),
      ),
      // Chips
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusSm),
        ),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
        labelStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
      // Dialogs
      dialogTheme: DialogThemeData(
        backgroundColor: card,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusLg),
        ),
      ),
      // List tiles
      listTileTheme: const ListTileThemeData(
        textColor: Colors.white,
        iconColor: Colors.white70,
      ),
      dividerTheme: DividerThemeData(
        color: Colors.white.withValues(alpha: 0.08),
        thickness: 1,
        space: 1,
      ),
      // Segmented buttons
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((s) {
            if (s.contains(WidgetState.selected)) {
              return brandGreen.withValues(alpha: 0.18);
            }
            return elevated.withValues(alpha: 0.5);
          }),
          foregroundColor: WidgetStateProperty.resolveWith((s) {
            return s.contains(WidgetState.selected)
                ? brandGreen
                : Colors.white60;
          }),
          side: WidgetStateProperty.all(
            BorderSide(color: Colors.white.withValues(alpha: 0.10)),
          ),
        ),
      ),
    );
  }
}
