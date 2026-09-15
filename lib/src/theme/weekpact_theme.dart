import '../widgets/squircle_button_border.dart';

import 'package:hugeicons/hugeicons.dart';

import 'package:hugeicons/styles/stroke_rounded.dart';
import 'package:flutter/material.dart';

/// Shared stroke and depth values for the app's outlined surfaces.
abstract final class WeekPactMetrics {
  static const border = 1.0;
  static const controlDepth = 2.0;
  static const cardDepth = 3.0;
  static const pactCardShape = ContinuousRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(40)),
  );
  static const raisedOffset = Offset(0, controlDepth);
  static const cardRadius = 8.0;
  static const controlRadius = 8.0;
  static const buttonShape = SquircleButtonBorder();
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
  static const pendingCheckIns = Color(0xFFC6C9C3);
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
  static const darkAccent = coolGrey;
  static const darkError = Color(0xFFFFA8AE);
  static const softYellow = Color(0xFFF4D88F);
  static const mintGreen = Color(0xFFC2D8AC);
  static const bubblegumPink = Color(0xFFEAC7D4);
  static const pinkInk = Color(0xFF505550);
  static const softCoral = Color(0xFFF0C6B6);
  static const stone = Color(0xFFDCD0BB);
  static const coolGrey = Color(0xFFB9CBD0);
  static const neutralInset = Color(0xFFDDDFD7);
  static const activitySurface = Color(0xFF292A29);
  static const pactPalette = <Color>[
    stone,
    coolGrey,
    Color(0xFFD3C3B9), // Warm grey.
    Color(0xFFC4CEBF), // Silver sage.
    Color(0xFFCCC2D4), // Ash.
    Color(0xFFD8CBAF), // Oat.
    Color(0xFFBFCFCA), // Mist.
    Color(0xFFD0C6BA), // Pebble.
    Color(0xFFC0C8D5), // Slate.
    Color(0xFFD8CDBF), // Linen.
  ];
  static const mutedLight = Color(0xFF51564F);
  static const error = Color(0xFFC94F59);
}

abstract final class WeekPactTheme {
  static ThemeData get light => _build(
    brightness: Brightness.light,
    background: WeekPactColors.lightCanvas,
    foreground: WeekPactColors.black,
    primary: WeekPactColors.coolGrey,
  );

  static ThemeData get dark => _build(
    brightness: Brightness.dark,
    background: WeekPactColors.darkCanvas,
    foreground: WeekPactColors.darkInk,
    primary: WeekPactColors.coolGrey,
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
            primary: dark ? WeekPactColors.darkInk : WeekPactColors.black,
            onPrimary: dark ? WeekPactColors.black : WeekPactColors.cream,
            secondary: dark ? WeekPactColors.coolGrey : WeekPactColors.pinkInk,
            secondaryContainer: WeekPactColors.coolGrey,
            onSecondaryContainer: WeekPactColors.black,
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
          shape: WeekPactMetrics.buttonShape,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(shape: WeekPactMetrics.buttonShape),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(shape: WeekPactMetrics.buttonShape),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(shape: WeekPactMetrics.buttonShape),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: dark ? WeekPactColors.coolGrey : WeekPactColors.pinkInk,
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
  Color get yellow => WeekPactColors.stone;
  Color get mint => WeekPactColors.mintGreen;
  Color get coral => WeekPactColors.coolGrey;
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
    if (color == WeekPactColors.softYellow ||
        color == WeekPactColors.softCoral) {
      return WeekPactColors.stone;
    }
    if (color == WeekPactColors.bubblegumPink ||
        color == WeekPactColors.lavender ||
        color == WeekPactColors.sky) {
      return WeekPactColors.coolGrey;
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
