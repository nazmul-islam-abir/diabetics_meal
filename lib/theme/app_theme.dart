/// Pure black & white design system for আমার ডায়েট.
///
/// Why this exists:
///   • Premium editorial feel — high contrast, generous whitespace, oversized
///     typography tuned for elderly eyes (everything ≥ 16 sp, primary ≥ 18 sp).
///   • Zero brand colors by default. Every accent is grayscale so the UI feels
///     calm, professional, and unmistakably high-end.
///   • Motion is built into the system: durations, curves, and shared
///     decoration primitives live here so every screen reads as one product.
library;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AppColors {
  AppColors._();

  // The five canonical stops we use everywhere. No tints, no shades.
  static const Color ink = Color(0xFF0A0A0A); // primary text & fg
  static const Color paper = Color(0xFFFFFFFF); // canvas
  static const Color chalk = Color(0xFFF4F4F4); // surface
  static const Color graphite = Color(0xFFE5E5E5); // divider / outline
  static const Color smoke = Color(0xFF8A8A8A); // secondary text
  static const Color ash = Color(0xFFB8B8B8); // tertiary text

  // Functional mapping — same five colors, used with intent.
  static const Color text = ink;
  static const Color textMuted = smoke;
  static const Color textDim = ash;
  static const Color background = paper;
  static const Color surface = chalk;
  static const Color border = graphite;
  static const Color inverse = ink;
  static const Color onInverse = paper;
}

class AppMotion {
  AppMotion._();

  static const Duration micro = Duration(milliseconds: 140);
  static const Duration short = Duration(milliseconds: 220);
  static const Duration medium = Duration(milliseconds: 360);
  static const Duration long = Duration(milliseconds: 520);
  static const Duration epic = Duration(milliseconds: 820);

  static const Curve emphasized = Cubic(0.2, 0.0, 0.0, 1.0);
  static const Curve standard = Cubic(0.2, 0.0, 0.2, 1.0);
  static const Curve decelerate = Cubic(0.0, 0.0, 0.2, 1.0);
  static const Curve overshoot = Cubic(0.34, 1.56, 0.64, 1.0);
}

class AppRadius {
  AppRadius._();

  static const double xs = 8;
  static const double sm = 12;
  static const double md = 18;
  static const double lg = 24;
  static const double xl = 32;
  static const double pill = 999;
}

class AppSpacing {
  AppSpacing._();

  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 20;
  static const double xl = 28;
  static const double xxl = 40;
  static const double xxxl = 56;
}

class AppTheme {
  AppTheme._();

  static ThemeData light() {
    const scheme = ColorScheme(
      brightness: Brightness.light,
      primary: AppColors.ink,
      onPrimary: AppColors.paper,
      secondary: AppColors.ink,
      onSecondary: AppColors.paper,
      error: AppColors.ink,
      onError: AppColors.paper,
      surface: AppColors.paper,
      onSurface: AppColors.ink,
      surfaceContainerHighest: AppColors.chalk,
      outline: AppColors.graphite,
      outlineVariant: AppColors.graphite,
    );

    final textTheme = _buildTextTheme(AppColors.ink);

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.paper,
      canvasColor: AppColors.paper,
      dividerColor: AppColors.graphite,
      splashColor: AppColors.ink.withValues(alpha: 0.04),
      highlightColor: AppColors.ink.withValues(alpha: 0.02),
      hoverColor: AppColors.ink.withValues(alpha: 0.03),
      textTheme: textTheme,
      iconTheme: const IconThemeData(color: AppColors.ink, size: 24),
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.paper,
        foregroundColor: AppColors.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleSpacing: AppSpacing.lg,
        toolbarHeight: 64,
        systemOverlayStyle: SystemUiOverlayStyle.dark,
        titleTextStyle: textTheme.titleLarge,
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.paper,
        surfaceTintColor: AppColors.paper,
        modalBackgroundColor: AppColors.paper,
        elevation: 0,
        modalElevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.paper,
        surfaceTintColor: AppColors.paper,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.ink,
        contentTextStyle: const TextStyle(
          color: AppColors.paper,
          fontSize: 17,
          fontWeight: FontWeight.w500,
          height: 1.3,
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.ink,
          foregroundColor: AppColors.paper,
          disabledBackgroundColor: AppColors.ash,
          disabledForegroundColor: AppColors.paper,
          minimumSize: const Size(64, 60),
          padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 18),
          textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, letterSpacing: 0.2),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.ink,
          minimumSize: const Size(64, 60),
          padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 18),
          side: const BorderSide(color: AppColors.ink, width: 1.4),
          textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, letterSpacing: 0.2),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.ink,
          minimumSize: const Size(64, 52),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.chalk,
        hintStyle: const TextStyle(color: AppColors.ash, fontSize: 17),
        labelStyle: const TextStyle(color: AppColors.smoke, fontSize: 16),
        floatingLabelStyle: const TextStyle(color: AppColors.ink, fontSize: 16, fontWeight: FontWeight.w600),
        prefixIconColor: AppColors.ink,
        suffixIconColor: AppColors.ink,
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.graphite, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.ink, width: 1.8),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.ink, width: 1.6),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.ink, width: 1.8),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? AppColors.paper : AppColors.paper),
        trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? AppColors.ink : AppColors.ash),
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.ink,
        linearTrackColor: AppColors.graphite,
        circularTrackColor: AppColors.graphite,
      ),
      sliderTheme: const SliderThemeData(
        activeTrackColor: AppColors.ink,
        inactiveTrackColor: AppColors.graphite,
        thumbColor: AppColors.ink,
        overlayColor: Color(0x14000000),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: AppColors.ink,
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        textStyle: const TextStyle(color: AppColors.paper, fontSize: 14),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.graphite,
        thickness: 1,
        space: 1,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.chalk,
        selectedColor: AppColors.ink,
        labelStyle: const TextStyle(color: AppColors.ink, fontSize: 14, fontWeight: FontWeight.w600),
        secondaryLabelStyle: const TextStyle(color: AppColors.paper, fontSize: 14, fontWeight: FontWeight.w600),
        side: const BorderSide(color: AppColors.graphite),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.pill)),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      ),
      cardTheme: CardThemeData(
        color: AppColors.paper,
        surfaceTintColor: AppColors.paper,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          side: const BorderSide(color: AppColors.graphite, width: 1),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.paper,
        surfaceTintColor: AppColors.paper,
        elevation: 0,
        height: 84,
        indicatorColor: AppColors.ink,
        labelTextStyle: WidgetStateProperty.resolveWith((s) {
          final selected = s.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 13,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? AppColors.ink : AppColors.smoke,
            letterSpacing: 0.2,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((s) {
          final selected = s.contains(WidgetState.selected);
          return IconThemeData(
            color: selected ? AppColors.paper : AppColors.ink,
            size: 26,
          );
        }),
      ),
      listTileTheme: const ListTileThemeData(
        iconColor: AppColors.ink,
        textColor: AppColors.ink,
        minVerticalPadding: 16,
        contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      ),
      visualDensity: VisualDensity.standard,
      pageTransitionsTheme: PageTransitionsTheme(
        builders: <TargetPlatform, PageTransitionsBuilder>{
          TargetPlatform.android: const FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: const CupertinoPageTransitionsBuilder(),
        },
      ),
    );
  }

  static TextTheme _buildTextTheme(Color color) {
    return TextTheme(
      displayLarge: TextStyle(color: color, fontSize: 56, fontWeight: FontWeight.w800, height: 1.05, letterSpacing: -1.4),
      displayMedium: TextStyle(color: color, fontSize: 44, fontWeight: FontWeight.w800, height: 1.05, letterSpacing: -1.0),
      displaySmall: TextStyle(color: color, fontSize: 36, fontWeight: FontWeight.w800, height: 1.08, letterSpacing: -0.6),
      headlineLarge: TextStyle(color: color, fontSize: 32, fontWeight: FontWeight.w800, height: 1.1, letterSpacing: -0.4),
      headlineMedium: TextStyle(color: color, fontSize: 28, fontWeight: FontWeight.w800, height: 1.12, letterSpacing: -0.2),
      headlineSmall: TextStyle(color: color, fontSize: 24, fontWeight: FontWeight.w800, height: 1.15),
      titleLarge: TextStyle(color: color, fontSize: 22, fontWeight: FontWeight.w700, height: 1.2),
      titleMedium: TextStyle(color: color, fontSize: 19, fontWeight: FontWeight.w700, height: 1.25),
      titleSmall: TextStyle(color: color, fontSize: 17, fontWeight: FontWeight.w700, height: 1.3),
      bodyLarge: TextStyle(color: color, fontSize: 18, height: 1.4, fontWeight: FontWeight.w500),
      bodyMedium: TextStyle(color: color, fontSize: 17, height: 1.4, fontWeight: FontWeight.w500),
      bodySmall: TextStyle(color: color, fontSize: 15, height: 1.4, fontWeight: FontWeight.w500),
      labelLarge: TextStyle(color: color, fontSize: 17, fontWeight: FontWeight.w700, letterSpacing: 0.3),
      labelMedium: TextStyle(color: color, fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: 0.4),
      labelSmall: TextStyle(color: AppColors.smoke, fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 1.2),
    );
  }
}
