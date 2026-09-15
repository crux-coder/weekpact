import 'package:hugeicons/hugeicons.dart';
import 'package:hugeicons/styles/stroke_rounded.dart';
import 'package:flutter/material.dart';

/// Shared stroke and depth values for the app's outlined surfaces.
abstract final class WeekPactMetrics {
  static const border = 1.0;
  static const cardRadius = 8.0;
  static const controlRadius = 8.0;
  static const pageInset = 12.0;
  static const sectionGap = 20.0;
  static const fineBorder = 1.0;
  static const selectedBorder = 2.0;
  static const shadow = Offset.zero;
  static const smallShadow = Offset.zero;
  static const pressDepth = 0.0;
  static const buttonHeight = 48.0;
  static const buttonPadding = EdgeInsets.symmetric(
    horizontal: 12,
    vertical: 6,
  );
}

abstract final class WeekPactColors {
  static const success = Color(0xFF4C8C5D);
  static const warning = Color(0xFFC48A42);
  static const outlineInk = Color(0xFF161C23);
  static const sky = Color(0xFF87CFFA);
  static const lavender = Color(0xFFBEA8F5);
  static const lime = Color(0xFFBBDC99);
  static const salmon = Color(0xFFFF836F);
  static const black = Color(0xFF191B19);
  static const cream = Color(0xFFF5F6F5);
  static const lightCanvas = Color(0xFFF7F3E9);
  static const darkCanvas = Color(0xFF191B19);
  static const darkSurface = Color(0xFF282D28);
  static const darkInk = Color(0xFFF3F5F2);
  static const darkBorder = Color(0xFF747E70);
  static const darkShadow = darkBorder;
  static const darkMuted = Color(0xFFB8BEB5);
  static const darkYellow = Color(0xFF49412B);
  static const darkMint = Color(0xFF304531);
  static const darkCoral = Color(0xFF523732);
  static const darkPink = Color(0xFF483743);
  static const darkAccent = Color(0xFFD0E5BA);
  static const darkError = Color(0xFFFFA8AE);
  static const softYellow = Color(0xFFF4D88F);
  static const mintGreen = Color(0xFFD0E5BA);
  static const bubblegumPink = Color(0xFFEAC7D4);
  static const pinkInk = Color(0xFF47623B);
  static const softCoral = Color(0xFFF0C6B6);
  static const activitySurface = Color(0xFF292A29);
  static const pactPalette = <Color>[
    Color(0xFFE4E1DA), // Stone.
    Color(0xFFCDD2D3), // Cool grey.
    Color(0xFFD8D3CF), // Warm grey.
    Color(0xFFD2D5D0), // Silver sage.
    Color(0xFFD5D1D9), // Ash.
    Color(0xFFDDD8CC), // Oat.
    Color(0xFFCFD5D5), // Mist.
    Color(0xFFD9D6D1), // Pebble.
    Color(0xFFD0D2D8), // Slate.
    Color(0xFFDCD9D3), // Linen.
  ];
  static const mutedLight = Color(0xFF686D63);
  static const error = Color(0xFFC94F59);
}

abstract final class WeekPactTheme {
  static ThemeData get light => _build(
    brightness: Brightness.light,
    background: WeekPactColors.lightCanvas,
    foreground: WeekPactColors.black,
    primary: WeekPactColors.softYellow,
  );

  static ThemeData get dark => _build(
    brightness: Brightness.dark,
    background: WeekPactColors.darkCanvas,
    foreground: WeekPactColors.darkInk,
    primary: WeekPactColors.softYellow,
  );

  static ThemeData _build({
    required Brightness brightness,
    required Color background,
    required Color foreground,
    required Color primary,
  }) {
    final dark = brightness == Brightness.dark;
    final surface = WeekPactColors.cream;
    final outline = const Color(0xFFD9DDD5);
    final inputBorder = OutlineInputBorder(
      borderSide: BorderSide(color: outline, width: WeekPactMetrics.border),
      borderRadius: BorderRadius.circular(WeekPactMetrics.controlRadius),
    );
    final inputErrorBorder = inputBorder.copyWith(
      borderSide: BorderSide(
        color: dark ? WeekPactColors.darkError : WeekPactColors.error,
        width: WeekPactMetrics.border,
      ),
    );
    final base = ThemeData(
      useMaterial3: true,
      fontFamily: 'RobotoCondensed',
      brightness: brightness,
      scaffoldBackgroundColor: background,
      colorScheme:
          ColorScheme.fromSeed(
            seedColor: primary,
            brightness: brightness,
            surface: surface,
          ).copyWith(
            onSurface: WeekPactColors.black,
            onSurfaceVariant: WeekPactColors.mutedLight,
            primary: dark ? const Color(0xFFF1D68A) : WeekPactColors.pinkInk,
            onPrimary: WeekPactColors.black,
            outline: outline,
            error: dark ? WeekPactColors.darkError : WeekPactColors.error,
            surfaceTint: Colors.transparent,
          ),
    );

    return base.copyWith(
      actionIconTheme: ActionIconThemeData(
        backButtonIconBuilder: (context) =>
            const HugeIcon(icon: HugeIconsStrokeRounded.arrowLeft02),
        closeButtonIconBuilder: (context) =>
            const HugeIcon(icon: HugeIconsStrokeRounded.cancel01),
        drawerButtonIconBuilder: (context) =>
            const HugeIcon(icon: HugeIconsStrokeRounded.menu01),
        endDrawerButtonIconBuilder: (context) =>
            const HugeIcon(icon: HugeIconsStrokeRounded.menu01),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        foregroundColor: foreground,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(WeekPactMetrics.cardRadius),
          side: BorderSide(color: outline),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 48),
          backgroundColor: foreground,
          foregroundColor: background,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(WeekPactMetrics.controlRadius),
          ),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: dark ? WeekPactColors.mintGreen : WeekPactColors.pinkInk,
      ),
      iconTheme: IconThemeData(color: foreground),
      dividerColor: outline,
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        labelStyle: TextStyle(color: foreground),
        floatingLabelStyle: TextStyle(color: foreground),
        hintStyle: TextStyle(
          color: dark ? WeekPactColors.darkMuted : WeekPactColors.mutedLight,
        ),
        border: inputBorder,
        enabledBorder: inputBorder,
        focusedBorder: inputBorder,
        disabledBorder: inputBorder,
        errorBorder: inputErrorBorder,
        focusedErrorBorder: inputErrorBorder,
      ),
      chipTheme: base.chipTheme.copyWith(
        labelStyle: TextStyle(color: foreground, fontWeight: FontWeight.w700),
        checkmarkColor: foreground,
        backgroundColor: surface,
        side: BorderSide(color: outline, width: WeekPactMetrics.fineBorder),
      ),
      textTheme: base.textTheme.apply(
        bodyColor: foreground,
        displayColor: foreground,
        decorationColor: foreground,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: foreground,
        contentTextStyle: TextStyle(
          color: background,
          fontWeight: FontWeight.w700,
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(WeekPactMetrics.controlRadius),
        ),
      ),
    );
  }
}

class WeekPactBackground extends StatelessWidget {
  const WeekPactBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(color: context.canvas, child: child);
  }
}

extension WeekPactThemeX on BuildContext {
  bool get isDark => Theme.of(this).brightness == Brightness.dark;
  Color get ink => isDark ? WeekPactColors.darkInk : WeekPactColors.black;
  Color get canvas =>
      isDark ? WeekPactColors.darkCanvas : WeekPactColors.lightCanvas;
  Color get surface => WeekPactColors.cream;
  Color get border => WeekPactColors.black.withValues(alpha: .10);
  Color get shadow => border;
  Color get yellow => WeekPactColors.softYellow;
  Color get mint => WeekPactColors.mintGreen;
  Color get coral => WeekPactColors.mintGreen;
  Color get pink => WeekPactColors.cream;
  Color get primary => yellow;
  Color get accent =>
      isDark ? WeekPactColors.darkAccent : WeekPactColors.pinkInk;
  Color get fieldInk => ink;
  Color get muted =>
      isDark ? WeekPactColors.darkMuted : WeekPactColors.mutedLight;
  Color get errorInk =>
      isDark ? WeekPactColors.darkError : WeekPactColors.error;

  /// Resolve fixed accent colors carried by navigation and other view models.
  Color tone(Color color) {
    if (color == WeekPactColors.softCoral ||
        color == WeekPactColors.bubblegumPink) {
      return WeekPactColors.mintGreen;
    }
    return color;
  }
}

/// Home's pale surfaces retain dark content in either canvas theme.
/// Build content within this scope so explicit context colors also match.
class AppSurfaceTheme extends StatelessWidget {
  const AppSurfaceTheme({super.key, required this.builder});
  final WidgetBuilder builder;
  @override
  Widget build(BuildContext context) => Theme(
    data: WeekPactTheme.light,
    child: Builder(
      builder: (context) => DefaultTextStyle(
        style: Theme.of(context).textTheme.bodyMedium!,
        child: IconTheme(
          data: const IconThemeData(color: WeekPactColors.black),
          child: builder(context),
        ),
      ),
    ),
  );
}
