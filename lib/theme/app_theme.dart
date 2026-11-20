import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// מערכת העיצוב של האפליקציה: טורקיז עמוק + ענבר חם, פונט Heebo, פינות מעוגלות.
class AppTheme {
  static const seed = Color(0xFF0E7C6B);
  static const amber = Color(0xFFF2A541);

  /// לבדיקות אוטומטיות: פונט מקומי במקום הורדה מ-Google Fonts
  static String? fontOverride;

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static LinearGradient heroGradient(ColorScheme c) => LinearGradient(
        begin: Alignment.topRight,
        end: Alignment.bottomLeft,
        colors: [c.primary, Color.lerp(c.primary, const Color(0xFF0B3550), .55)!],
      );

  static ThemeData _build(Brightness b) {
    final isLight = b == Brightness.light;
    final c = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: b,
      tertiary: isLight ? const Color(0xFFB86E00) : amber,
    );
    final base = ThemeData(useMaterial3: true, colorScheme: c, brightness: b);
    final text = (fontOverride != null
            ? base.textTheme.apply(fontFamily: fontOverride, fontFamilyFallback: const ['AppFallback'])
            : GoogleFonts.heeboTextTheme(base.textTheme))
        .apply(bodyColor: c.onSurface, displayColor: c.onSurface);
    final radius = BorderRadius.circular(16);

    return base.copyWith(
      textTheme: text,
      scaffoldBackgroundColor: isLight ? const Color(0xFFF5F7F6) : const Color(0xFF0F1513),
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        foregroundColor: c.onSurface,
        titleTextStyle: text.titleLarge?.copyWith(fontWeight: FontWeight.w800, color: c.onSurface),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: isLight ? Colors.white : c.surfaceContainer,
        surfaceTintColor: Colors.transparent,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: c.outlineVariant.withValues(alpha: isLight ? .5 : .25)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isLight ? Colors.white : c.surfaceContainerHigh,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: c.outlineVariant)),
        enabledBorder: OutlineInputBorder(
            borderRadius: radius, borderSide: BorderSide(color: c.outlineVariant.withValues(alpha: .6))),
        focusedBorder: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: c.primary, width: 1.6)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 52),
          shape: RoundedRectangleBorder(borderRadius: radius),
          textStyle: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 52),
          shape: RoundedRectangleBorder(borderRadius: radius),
          side: BorderSide(color: c.outlineVariant),
          textStyle: text.titleSmall?.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(textStyle: text.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: c.primary,
        foregroundColor: c.onPrimary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 70,
        elevation: 0,
        backgroundColor: isLight ? Colors.white : c.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        indicatorColor: c.primaryContainer,
        labelTextStyle: WidgetStatePropertyAll(text.labelMedium?.copyWith(fontWeight: FontWeight.w600)),
      ),
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(borderRadius: radius),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
        titleTextStyle: text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        subtitleTextStyle: text.bodySmall?.copyWith(color: c.onSurfaceVariant),
      ),
      chipTheme: ChipThemeData(
        shape: const StadiumBorder(),
        side: BorderSide(color: c.outlineVariant.withValues(alpha: .6)),
        labelStyle: text.labelLarge,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      dialogTheme: DialogThemeData(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24))),
      bottomSheetTheme: const BottomSheetThemeData(
        showDragHandle: true,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      ),
      dividerTheme: DividerThemeData(color: c.outlineVariant.withValues(alpha: .4), space: 1),
      sliderTheme: SliderThemeData(
        trackHeight: 4,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
        inactiveTrackColor: c.primary.withValues(alpha: .15),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: c.primary, linearTrackColor: c.primary.withValues(alpha: .12)),
    );
  }
}
