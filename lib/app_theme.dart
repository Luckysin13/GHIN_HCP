/// The app's theme.
///
/// [legacy] reproduces the previous look — a bare Material 3 scheme from a
/// green seed with none of the component styling below. It is selected with
///
///     flutter build apk --release --dart-define=GHIN_LEGACY_UI=true
///
/// so the new look can be compared against, or abandoned, without editing
/// code or reinstalling anything.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'design_tokens.dart';

/// True when the build was asked for the previous appearance.
const bool legacyUi = bool.fromEnvironment('GHIN_LEGACY_UI');

abstract final class AppTheme {
  static ThemeData get light => _build(Brightness.light);
  static ThemeData get dark => _build(Brightness.dark);

  /// What the app actually runs with, honouring [legacyUi].
  static ThemeData active(Brightness brightness) =>
      legacyUi ? _legacy(brightness) : _build(brightness);

  static ThemeData _legacy(Brightness b) => ThemeData(
    colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
    useMaterial3: true,
    brightness: b,
  );

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final scheme =
        ColorScheme.fromSeed(
          seedColor: Brand.green,
          brightness: brightness,
        ).copyWith(
          // Brass is an accent, not another shade of the primary green.
          tertiary: isDark ? const Color(0xFFE0C27A) : Brand.brass,
          surface: isDark ? Brand.canvasDark : Brand.canvas,
          surfaceContainerLowest: isDark
              ? const Color(0xFF111A16)
              : const Color(0xFFFFFFFF),
          surfaceContainerLow: isDark
              ? const Color(0xFF19231E)
              : const Color(0xFFFFFFFF),
          surfaceContainer: isDark
              ? const Color(0xFF1D2A23)
              : const Color(0xFFEEF3EF),
          surfaceContainerHigh: isDark
              ? const Color(0xFF24332B)
              : const Color(0xFFE8EFEB),
          surfaceContainerHighest: isDark
              ? const Color(0xFF2B3B32)
              : const Color(0xFFE4ECE6),
          onSurface: isDark ? const Color(0xFFEAF1EC) : const Color(0xFF1A2821),
          onSurfaceVariant: isDark
              ? const Color(0xFFBAC9C0)
              : const Color(0xFF58685F),
          outlineVariant: isDark
              ? const Color(0xFF405148)
              : const Color(0xFFD8E2DB),
          primary: isDark ? const Color(0xFF91D0AE) : Brand.green,
          onPrimary: isDark ? const Color(0xFF103B29) : Colors.white,
          primaryContainer: isDark
              ? const Color(0xFF244F3B)
              : const Color(0xFFDDEFE4),
          onPrimaryContainer: isDark
              ? const Color(0xFFD9F2E2)
              : const Color(0xFF183D2D),
        );

    final base = ThemeData(colorScheme: scheme, useMaterial3: true);

    // Slightly denser than M3's defaults: this app is a list of numbers on a
    // phone held at arm's length, and the default rhythm wastes vertical
    // space that a scorecard needs.
    final text = base.textTheme
        .apply(bodyColor: scheme.onSurface, displayColor: scheme.onSurface)
        .copyWith(
          headlineSmall: AppType.headline.copyWith(color: scheme.onSurface),
          titleMedium: AppType.title.copyWith(color: scheme.onSurface),
          titleSmall: AppType.label.copyWith(color: scheme.onSurface),
          bodyMedium: AppType.body.copyWith(color: scheme.onSurface),
          bodySmall: AppType.meta.copyWith(color: scheme.onSurfaceVariant),
          labelLarge: AppType.label.copyWith(color: scheme.onSurface),
        );

    return base.copyWith(
      scaffoldBackgroundColor: scheme.surface,
      textTheme: text,
      splashFactory: InkSparkle.splashFactory,

      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        // A hairline instead of a shadow: the bar is already a different
        // tone from the content scrolling under it, and a shadow on top of
        // that reads as dirt on a mostly-white screen.
        scrolledUnderElevation: 0,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: AppType.headline.copyWith(
          color: scheme.onSurface,
          fontSize: 20,
        ),
        systemOverlayStyle: isDark
            ? SystemUiOverlayStyle.light.copyWith(
                statusBarColor: Colors.transparent,
              )
            : SystemUiOverlayStyle.dark.copyWith(
                statusBarColor: Colors.transparent,
              ),
      ),

      cardTheme: CardThemeData(
        // Flat with an outline, not a floating shadow. A card in this app is a
        // panel of related numbers sitting flush on the page; elevation would
        // imply it floats above the screen rather than belongs to it.
        elevation: 0,
        color: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.card),
          side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6)),
        ),
      ),

      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant.withValues(alpha: 0.5),
        thickness: 1,
        space: 1,
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(horizontal: Insets.xl),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Radii.control),
          ),
          textStyle: AppType.label.copyWith(fontSize: 15),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(horizontal: Insets.xl),
          side: BorderSide(color: scheme.outline),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Radii.control),
          ),
          textStyle: AppType.label.copyWith(fontSize: 15),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(0, 44),
          textStyle: AppType.label.copyWith(fontSize: 15),
        ),
      ),

      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          // Keep icon actions comfortably tappable without inflating row height.
          minimumSize: const Size(44, 44),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Radii.control),
          ),
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: Insets.lg,
          vertical: Insets.md,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.control),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.control),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.control),
          borderSide: BorderSide(color: scheme.primary, width: 1.6),
        ),
      ),

      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.control),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: Insets.lg,
          vertical: Insets.xs,
        ),
        minVerticalPadding: Insets.md,
        titleTextStyle: AppType.title.copyWith(color: scheme.onSurface),
        subtitleTextStyle: AppType.meta.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      ),

      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Brand.forest,
        surfaceTintColor: Colors.transparent,
        indicatorColor: Colors.white.withValues(alpha: 0.16),
        elevation: 0,
        height: 76,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => AppType.meta.copyWith(
            fontSize: 11,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
            color: states.contains(WidgetState.selected)
                ? Colors.white
                : Colors.white.withValues(alpha: 0.7),
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: Colors.white.withValues(
              alpha: states.contains(WidgetState.selected) ? 1 : 0.72,
            ),
          ),
        ),
      ),

      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: AppType.body.copyWith(color: scheme.onInverseSurface),
        actionTextColor: scheme.inversePrimary,
        elevation: 2,
        insetPadding: const EdgeInsets.all(Insets.lg),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.control),
        ),
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.dialog),
        ),
        titleTextStyle: AppType.headline.copyWith(fontSize: 20),
        contentTextStyle: AppType.body.copyWith(color: scheme.onSurfaceVariant),
      ),

      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(Radii.sheet),
          ),
        ),
        showDragHandle: true,
      ),

      chipTheme: ChipThemeData(
        side: BorderSide(color: scheme.outlineVariant),
        labelStyle: AppType.label.copyWith(fontSize: 13),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.pill),
        ),
      ),

      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Radii.control),
          ),
        ),
      ),

      // The app's own containers, so nothing inherits the M3 default of 4dp
      // and reads as a chip in a screen full of panels.
      drawerTheme: const DrawerThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.horizontal(
            right: Radius.circular(Radii.sheet),
          ),
        ),
      ),
    );
  }
}
