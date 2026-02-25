import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ─── Drezzy Brand Palette ──────────────────────────────────────────────────
// Obsidian Plum  → primary brand colour
// Champagne Gold → accent / highlight
// Near-black     → dark surface
// Ivory White    → light surface
// ──────────────────────────────────────────────────────────────────────────

abstract final class DrezzyColors {
  // Core brand
  static const Color obsidianPlum = Color(0xFF1C0B36);
  static const Color deepAubergine = Color(0xFF2E1254);
  static const Color champagneGold = Color(0xFFCDA96E);
  static const Color paleGold = Color(0xFFE8D5A8);

  // Neutrals
  static const Color nearBlack = Color(0xFF0A0A0F);
  static const Color charcoal = Color(0xFF1A1A24);
  static const Color slate = Color(0xFF3A3A4A);
  static const Color ivoryWhite = Color(0xFFF8F5EF);
  static const Color softWhite = Color(0xFFFAF9F7);

  // Status
  static const Color success = Color(0xFF4CAF7D);
  static const Color error = Color(0xFFE05252);
  static const Color warning = Color(0xFFE8A930);
}

// ─── Typography ────────────────────────────────────────────────────────────
// Headlines → Cormorant Garamond  (high-fashion editorial serif)
// Body/UI   → DM Sans             (clean, modern grotesque)
// ──────────────────────────────────────────────────────────────────────────

abstract final class DrezzyTextTheme {
  static TextTheme build(ColorScheme scheme) {
    final serif = GoogleFonts.cormorantGaramond;
    final sans = GoogleFonts.dmSans;

    return TextTheme(
      // Display — hero headings
      displayLarge: serif(
        fontSize: 57,
        fontWeight: FontWeight.w300,
        letterSpacing: -0.25,
        color: scheme.onSurface,
      ),
      displayMedium: serif(
        fontSize: 45,
        fontWeight: FontWeight.w300,
        color: scheme.onSurface,
      ),
      displaySmall: serif(
        fontSize: 36,
        fontWeight: FontWeight.w400,
        color: scheme.onSurface,
      ),

      // Headlines — section titles
      headlineLarge: serif(
        fontSize: 32,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.5,
        color: scheme.onSurface,
      ),
      headlineMedium: serif(
        fontSize: 28,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.25,
        color: scheme.onSurface,
      ),
      headlineSmall: serif(
        fontSize: 24,
        fontWeight: FontWeight.w500,
        color: scheme.onSurface,
      ),

      // Titles — card / list headers
      titleLarge: sans(
        fontSize: 22,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.15,
        color: scheme.onSurface,
      ),
      titleMedium: sans(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.15,
        color: scheme.onSurface,
      ),
      titleSmall: sans(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.1,
        color: scheme.onSurface,
      ),

      // Body — readable text
      bodyLarge: sans(
        fontSize: 16,
        fontWeight: FontWeight.w400,
        letterSpacing: 0.5,
        color: scheme.onSurface,
      ),
      bodyMedium: sans(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        letterSpacing: 0.25,
        color: scheme.onSurface,
      ),
      bodySmall: sans(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        letterSpacing: 0.4,
        color: scheme.onSurfaceVariant,
      ),

      // Labels — buttons, chips, captions
      labelLarge: sans(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.2,
        color: scheme.onSurface,
      ),
      labelMedium: sans(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.5,
        color: scheme.onSurface,
      ),
      labelSmall: sans(
        fontSize: 11,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.5,
        color: scheme.onSurfaceVariant,
      ),
    );
  }
}

// ─── Theme Builder ─────────────────────────────────────────────────────────

abstract final class DrezzyTheme {
  // ── Dark theme (default — premium editorial feel) ──
  static ThemeData get dark {
    final scheme = ColorScheme.fromSeed(
      seedColor: DrezzyColors.obsidianPlum,
      brightness: Brightness.dark,
      primary: DrezzyColors.obsidianPlum,
      secondary: DrezzyColors.champagneGold,
      tertiary: DrezzyColors.deepAubergine,
      surface: DrezzyColors.charcoal,
      onSurface: DrezzyColors.ivoryWhite,
      onPrimary: DrezzyColors.ivoryWhite,
      onSecondary: DrezzyColors.nearBlack,
      error: DrezzyColors.error,
    );

    return _build(scheme);
  }

  // ── Light theme (clean minimalist ivory) ──
  static ThemeData get light {
    final scheme = ColorScheme.fromSeed(
      seedColor: DrezzyColors.obsidianPlum,
      brightness: Brightness.light,
      primary: DrezzyColors.obsidianPlum,
      secondary: DrezzyColors.champagneGold,
      tertiary: DrezzyColors.deepAubergine,
      surface: DrezzyColors.softWhite,
      onSurface: DrezzyColors.nearBlack,
      onPrimary: DrezzyColors.ivoryWhite,
      onSecondary: DrezzyColors.nearBlack,
      error: DrezzyColors.error,
    );

    return _build(scheme);
  }

  static ThemeData _build(ColorScheme scheme) {
    final textTheme = DrezzyTextTheme.build(scheme);

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      textTheme: textTheme,
      scaffoldBackgroundColor: scheme.surface,

      // AppBar — flush, no elevation
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: true,
        titleTextStyle: textTheme.titleLarge?.copyWith(
          letterSpacing: 2,
          fontWeight: FontWeight.w700,
        ),
      ),

      // Elevated Buttons — gold accent CTA
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: scheme.secondary,
          foregroundColor: scheme.onSecondary,
          minimumSize: const Size(double.infinity, 52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(4),
          ),
          textStyle: textTheme.labelLarge,
          elevation: 0,
        ),
      ),

      // Outlined Buttons — ghost style
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: scheme.onSurface,
          minimumSize: const Size(double.infinity, 52),
          side: BorderSide(color: scheme.outline, width: 1),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(4),
          ),
          textStyle: textTheme.labelLarge,
        ),
      ),

      // TextButton — minimal, uppercase tracking
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.secondary,
          textStyle: textTheme.labelLarge,
        ),
      ),

      // Input fields — clean underline-free style
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: BorderSide(color: scheme.outline.withValues(alpha: 0.5)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: BorderSide(color: scheme.outline.withValues(alpha: 0.4)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: BorderSide(color: scheme.secondary, width: 1.5),
        ),
        labelStyle: textTheme.bodyMedium?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
        hintStyle: textTheme.bodyMedium?.copyWith(
          color: scheme.onSurfaceVariant.withValues(alpha: 0.6),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
      ),

      // Cards — subtle elevation
      cardTheme: CardThemeData(
        color: scheme.surfaceContainer,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
        margin: EdgeInsets.zero,
      ),

      // Chips — refined tag style
      chipTheme: ChipThemeData(
        backgroundColor: scheme.surfaceContainerHighest,
        selectedColor: scheme.secondary.withValues(alpha: 0.2),
        labelStyle: textTheme.labelMedium,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(2),
          side: BorderSide(color: scheme.outlineVariant),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      ),

      // Bottom nav — minimal icon bar
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surface,
        indicatorColor: scheme.secondary.withValues(alpha: 0.2),
        labelTextStyle: WidgetStateProperty.all(textTheme.labelSmall),
        iconTheme: WidgetStateProperty.all(
          IconThemeData(color: scheme.onSurfaceVariant),
        ),
        elevation: 0,
      ),

      // Dividers
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant.withValues(alpha: 0.4),
        thickness: 0.5,
        space: 0,
      ),

      // FAB — gold accent
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.secondary,
        foregroundColor: scheme.onSecondary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
        ),
        elevation: 2,
      ),

      // Snackbars
      snackBarTheme: SnackBarThemeData(
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: scheme.onInverseSurface,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
