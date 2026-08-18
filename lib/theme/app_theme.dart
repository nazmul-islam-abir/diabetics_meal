/// আমার ডায়েট — Monochrome identity system (v3).
///
/// Design intent:
///   • Minimal, high-contrast, black & white. Built for older users first:
///     large type, generous tap targets, no blur/noise that hurts legibility.
///   • White/near-white canvas, ink-black text. Depth comes from soft
///     elevation shadows and thin hairline borders — not glass blur.
///   • Gradients are monochrome (black → charcoal) and used sparingly, on
///     primary buttons, headers, and progress states, so the app still feels
///     premium and "designed" instead of flat.
///   • Two restrained signal colors — a calm green for "done / on-track" and
///     a muted red for "missed / alert" — are kept because a diabetes app
///     must let an older user recognise a health warning at a glance. Every
///     other surface stays strictly grayscale.
library;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AppColors {
  AppColors._();

  // ── Canvas ──────────────────────────────────────────────────────────────
  static const Color void1 = Color(0xFFFFFFFF); // text/icons drawn on black
  static const Color void2 = Color(0xFFF8F9FA); // scaffold background
  static const Color void3 = Color(0xFFFFFFFF); // raised surface
  static const Color surface = Color(0xFFFFFFFF); // card / sheet
  static const Color surfaceHigh = Color(0xFFF1F3F5); // elevated / pressed card
  static const Color line = Color(0xFFE9ECEF); // hairline border
  static const Color lineStrong = Color(0xFFDEE2E6); // stronger border

  // ── Text ────────────────────────────────────────────────────────────────
  static const Color text = Color(0xFF212529); // ink-black, primary text
  static const Color textMuted = Color(0xFF495057); // secondary text
  static const Color textDim = Color(0xFFadb5bd); // tertiary / hint text

  // ── Brand accents ──────────────────────────────────────────────────────
  static const Color cyan = Color(0xFF059669); // Deep Emerald (v3)
  static const Color cyanDeep = Color(0xFF065F46);
  static const Color violet = Color(0xFF4A90E2); // Soft Blue accent
  static const Color violetDeep = Color(0xFF357ABD);
  static const Color mint = Color(0xFF10B981); // Rich Mint
  static const Color mintDeep = Color(0xFF047857);
  static const Color rose = Color(0xFFFF5252); // Alert Red
  static const Color amber = Color(0xFFFFB300); // Warning Orange

  // ── Functional mapping ──────────────────────────────────────────────────
  static const Color background = void2;
  static const Color border = line;
  static const Color accent = cyan;
  static const Color accentDeep = cyanDeep;
  static const Color accentSurface = Color(0x0D17171A);
  static const Color inverse = text;
  static const Color onInverse = void1;
  static const Color onAccent = void1;
  static const Color success = mint;
  static const Color warning = amber;
  static const Color danger = rose;

  // ── Legacy aliases (screens reference these names directly) ─────────────
  static const Color ink = text; // primary text
  static const Color paper = void2; // scaffold background
  static const Color graphite = line; // hairline border
  static const Color card = surface; // card fill
  static const Color moss = mint; // legacy green → success
  static const Color chalk = Color(0xFFFFFFFF); // Light background token
  static const Color smoke = textMuted; // muted secondary text
  static const Color ash = textDim; // dim tertiary text
}

/// Named gradients used across the app. Every gradient is monochrome —
/// black through charcoal — so buttons and headers read as premium without
/// breaking the black & white system.
class AppGradients {
  AppGradients._();

  // Backdrop — a whisper of grey top-to-bottom, never a distraction.
  static const LinearGradient cosmos = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFFFFFFF), Color(0xFFF8F9FA)],
    stops: [0.0, 1.0],
  );

  // Primary CTA gradient — used on the main action buttons.
  // Deeper, richer emerald that reads clearly on light surfaces.
  static const LinearGradient aurora = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF047857), Color(0xFF10B981), Color(0xFF34D399)],
    stops: [0.0, 0.55, 1.0],
  );

  static const LinearGradient nebula = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF065F46), Color(0xFF10B981)],
  );

  // Warning / borderline banners.
  static const LinearGradient sunrise = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFFFB300), Color(0xFFFF8F00)],
  );

  // "Done / on-track" states — meal taken, medicine taken, workout complete.
  static const LinearGradient mintGlow = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF10B981), Color(0xFF047857)],
  );

  // Secondary CTA.
  static const LinearGradient violetPop = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF4A90E2), Color(0xFF357ABD)],
  );

  // Section headers / titles.
  static const LinearGradient title = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF065F46), Color(0xFF10B981)],
  );

  // Legacy "blob" backdrop gradients.
  static const RadialGradient blobCyan = RadialGradient(
    center: Alignment.topLeft,
    radius: 0.9,
    colors: [Color(0x3310B981), Color(0x00000000)],
  );
  static const RadialGradient blobViolet = RadialGradient(
    center: Alignment.bottomRight,
    radius: 0.9,
    colors: [Color(0x1E4A90E2), Color(0x00000000)],
  );
  static const RadialGradient blobMint = RadialGradient(
    center: Alignment.center,
    radius: 0.8,
    colors: [Color(0x1400C897), Color(0x00000000)],
  );
}

/// "Glass" tokens — kept for API compatibility with [GlassCard], but on the
/// light monochrome canvas these now describe a solid card + hairline
/// border + soft shadow instead of frosted blur (blur reduces legibility,
/// which matters for an elder-friendly app).
class AppGlass {
  AppGlass._();

  static const Color tint = Color(0xFFFFFFFF);
  static const Color tintHigh = Color(0xFFFFFFFF);
  static const Color tintLow = Color(0xFFFAFAFB);

  static const Color border = Color(0xFFE2E2E6);
  static const Color borderHigh = Color(0xFF141416);

  // Blur is dialled to near-zero by default now; see [GlassCard].
  static const double blurLow = 0;
  static const double blurMed = 0;
  static const double blurHigh = 0;

  // Soft elevation shadow used behind cards.
  static List<BoxShadow> shadow(
          {double opacity = 0.08, double blur = 20, double y = 8}) =>
      [
        BoxShadow(
            color: Color.fromRGBO(0, 0, 0, opacity),
            blurRadius: blur,
            offset: Offset(0, y)),
      ];
}

class AppMotion {
  AppMotion._();

  static const Duration micro = Duration(milliseconds: 140);
  static const Duration short = Duration(milliseconds: 220);
  static const Duration medium = Duration(milliseconds: 360);
  static const Duration long = Duration(milliseconds: 520);
  static const Duration epic = Duration(milliseconds: 820);
  static const Duration gradientDrift = Duration(seconds: 14);

  static const Curve emphasized = Cubic(0.2, 0.0, 0.0, 1.0);
  static const Curve standard = Cubic(0.2, 0.0, 0.2, 1.0);
  static const Curve decelerate = Cubic(0.0, 0.0, 0.2, 1.0);
  static const Curve overshoot = Cubic(0.34, 1.56, 0.64, 1.0);
  static const Curve springy = Cubic(0.5, 1.6, 0.5, 1.0);
}

class AppRadius {
  AppRadius._();

  static const double xs = 10;
  static const double sm = 14;
  static const double md = 18;
  static const double lg = 22;
  static const double xl = 30;
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

class AppThemeData {
  final ThemeData theme;
  AppThemeData(this.theme);

  AppColorsData get colors => AppColorsData();
  AppTextData get text => AppTextData(theme.textTheme);
}

class AppColorsData {
  Color get ink => AppColors.ink;
  Color get paper => AppColors.paper;
  Color get graphite => AppColors.graphite;
  Color get cyan => AppColors.cyan;
  Color get violet => AppColors.violet;
  Color get mint => AppColors.mint;
}

class AppTextData {
  final TextTheme theme;
  AppTextData(this.theme);

  TextStyle get display => theme.displayMedium!;
  TextStyle get body => theme.bodyMedium!;
  TextStyle get bodyEmphasis => theme.titleSmall!;
  TextStyle get micro => theme.labelSmall!;
}

class AppTheme {
  AppTheme._();

  static AppThemeData of(BuildContext context) {
    return AppThemeData(Theme.of(context));
  }

  static ThemeData light() {
    const scheme = ColorScheme(
      brightness: Brightness.light,
      primary: AppColors.cyan,
      onPrimary: AppColors.void1,
      secondary: AppColors.violet,
      onSecondary: AppColors.void1,
      tertiary: AppColors.mint,
      onTertiary: AppColors.void1,
      error: AppColors.rose,
      onError: AppColors.void1,
      surface: AppColors.surface,
      onSurface: AppColors.text,
      surfaceContainerHighest: AppColors.surfaceHigh,
      outline: AppColors.line,
      outlineVariant: AppColors.line,
    );

    final textTheme = _buildTextTheme(AppColors.text);

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.void2,
      canvasColor: AppColors.void2,
      dividerColor: AppColors.line,
      splashColor: AppColors.cyan.withValues(alpha: 0.06),
      highlightColor: AppColors.cyan.withValues(alpha: 0.04),
      hoverColor: Colors.black.withValues(alpha: 0.03),
      textTheme: textTheme,
      iconTheme: const IconThemeData(color: AppColors.text, size: 24),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: AppColors.text,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleSpacing: AppSpacing.lg,
        toolbarHeight: 64,
        systemOverlayStyle: SystemUiOverlayStyle.dark,
        titleTextStyle: textTheme.titleLarge,
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: AppColors.surface,
        elevation: 0,
        modalElevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: AppColors.line),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.cyan,
        contentTextStyle: const TextStyle(
          color: AppColors.void1,
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
          backgroundColor: AppColors.cyan,
          foregroundColor: AppColors.void1,
          disabledBackgroundColor: AppColors.surfaceHigh,
          disabledForegroundColor: AppColors.textDim,
          minimumSize: const Size(64, 60),
          padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 18),
          textStyle: const TextStyle(
              fontSize: 18, fontWeight: FontWeight.w700, letterSpacing: 0.2),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.md)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.text,
          minimumSize: const Size(64, 60),
          padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 18),
          side: const BorderSide(color: AppColors.lineStrong, width: 1.4),
          textStyle: const TextStyle(
              fontSize: 18, fontWeight: FontWeight.w600, letterSpacing: 0.2),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.md)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.cyan,
          minimumSize: const Size(64, 52),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceHigh,
        hintStyle: const TextStyle(color: AppColors.textDim, fontSize: 17),
        labelStyle: const TextStyle(color: AppColors.textMuted, fontSize: 16),
        floatingLabelStyle: const TextStyle(
            color: AppColors.cyan, fontSize: 16, fontWeight: FontWeight.w700),
        prefixIconColor: AppColors.textMuted,
        suffixIconColor: AppColors.textMuted,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.line, width: 1.4),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.line, width: 1.4),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.cyan, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.rose, width: 1.6),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.rose, width: 2),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) => AppColors.void1),
        trackColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected)
                ? AppColors.cyan
                : AppColors.lineStrong),
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.cyan,
        linearTrackColor: AppColors.surfaceHigh,
        circularTrackColor: AppColors.surfaceHigh,
      ),
      sliderTheme: const SliderThemeData(
        activeTrackColor: AppColors.cyan,
        inactiveTrackColor: AppColors.surfaceHigh,
        thumbColor: AppColors.cyan,
        overlayColor: Color(0x1417171A),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: AppColors.cyan,
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        textStyle: const TextStyle(color: AppColors.void1, fontSize: 14),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.line,
        thickness: 1,
        space: 1,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.surfaceHigh,
        selectedColor: AppColors.cyan,
        labelStyle: const TextStyle(
            color: AppColors.text, fontSize: 14, fontWeight: FontWeight.w600),
        secondaryLabelStyle: const TextStyle(
            color: AppColors.void1, fontSize: 14, fontWeight: FontWeight.w700),
        side: const BorderSide(color: AppColors.line),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.pill)),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          side: const BorderSide(color: AppColors.line, width: 1),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        height: 84,
        indicatorColor: AppColors.cyan,
        labelTextStyle: WidgetStateProperty.resolveWith((s) {
          final selected = s.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 13,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? AppColors.text : AppColors.textMuted,
            letterSpacing: 0.2,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((s) {
          final selected = s.contains(WidgetState.selected);
          return IconThemeData(
            color: selected ? AppColors.void1 : AppColors.textMuted,
            size: 26,
          );
        }),
      ),
      listTileTheme: const ListTileThemeData(
        iconColor: AppColors.text,
        textColor: AppColors.text,
        minVerticalPadding: 16,
        contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      ),
      visualDensity: VisualDensity.standard,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: <TargetPlatform, PageTransitionsBuilder>{
          TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
    );
  }

  static TextTheme _buildTextTheme(Color color) {
    return TextTheme(
      displayLarge: TextStyle(
          color: color,
          fontSize: 56,
          fontWeight: FontWeight.w800,
          height: 1.05,
          letterSpacing: -1.0),
      displayMedium: TextStyle(
          color: color,
          fontSize: 44,
          fontWeight: FontWeight.w800,
          height: 1.05,
          letterSpacing: -0.6),
      displaySmall: TextStyle(
          color: color,
          fontSize: 36,
          fontWeight: FontWeight.w800,
          height: 1.08,
          letterSpacing: -0.4),
      headlineLarge: TextStyle(
          color: color,
          fontSize: 32,
          fontWeight: FontWeight.w800,
          height: 1.1,
          letterSpacing: -0.2),
      headlineMedium: TextStyle(
          color: color,
          fontSize: 28,
          fontWeight: FontWeight.w800,
          height: 1.12),
      headlineSmall: TextStyle(
          color: color,
          fontSize: 24,
          fontWeight: FontWeight.w700,
          height: 1.15),
      titleLarge: TextStyle(
          color: color, fontSize: 22, fontWeight: FontWeight.w700, height: 1.2),
      titleMedium: TextStyle(
          color: color,
          fontSize: 19,
          fontWeight: FontWeight.w700,
          height: 1.25),
      titleSmall: TextStyle(
          color: color, fontSize: 17, fontWeight: FontWeight.w700, height: 1.3),
      bodyLarge: TextStyle(
          color: color,
          fontSize: 19,
          height: 1.45,
          fontWeight: FontWeight.w500),
      bodyMedium: TextStyle(
          color: color,
          fontSize: 17,
          height: 1.45,
          fontWeight: FontWeight.w500),
      bodySmall: TextStyle(
          color: color, fontSize: 15, height: 1.4, fontWeight: FontWeight.w500),
      labelLarge: TextStyle(
          color: color,
          fontSize: 17,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2),
      labelMedium: TextStyle(
          color: color,
          fontSize: 15,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3),
      labelSmall: TextStyle(
          color: color.withValues(alpha: 0.85),
          fontSize: 13,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.0),
    );
  }
}
