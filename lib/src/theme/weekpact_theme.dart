import 'package:flutter/material.dart';

/// Shared stroke and depth values for the app's outlined surfaces.
abstract final class WeekPactMetrics {
  static const border = 2.0;
  static const fineBorder = 1.0;
  static const selectedBorder = 2.0;
  static const shadow = Offset.zero;
  static const smallShadow = Offset.zero;
  static const pressDepth = 0.0;
  static const buttonHeight = 40.0;
  static const buttonPadding = EdgeInsets.symmetric(
    horizontal: 12,
    vertical: 6,
  );
}

abstract final class WeekPactColors {
  static const outlineInk = Color(0xFF161C23);
  static const sky = Color(0xFF87CFFA);
  static const lavender = Color(0xFFBEA8F5);
  static const lime = Color(0xFFBBDC99);
  static const salmon = Color(0xFFFF836F);
  static const black = Color(0xFF090909);
  static const cream = Color(0xFFFFFCF3);
  static const lightCanvas = Color(0xFFF8F5EC);
  static const darkCanvas = Color(0xFF303642);
  static const darkSurface = Color(0xFF3D4553);
  static const darkInk = Color(0xFFF6F1E5);
  static const darkBorder = Color(0xFFB0BCC4);
  static const darkShadow = darkBorder;
  static const darkMuted = Color(0xFFB6BEC7);
  static const darkYellow = Color(0xFF51452B);
  static const darkMint = Color(0xFF294B3E);
  static const darkCoral = Color(0xFF633B46);
  static const darkPink = Color(0xFF60354F);
  static const darkAccent = Color(0xFFFFB4CE);
  static const darkError = Color(0xFFFFA8AE);
  static const softYellow = Color(0xFFFFEFAE);
  static const mintGreen = Color(0xFFBFE3B2);
  static const bubblegumPink = Color(0xFFF45B91);
  static const pinkInk = Color(0xFFB83363);
  static const softCoral = Color(0xFFFF999B);
  static const mutedLight = Color(0xFF74716A);
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
    final surface = dark ? WeekPactColors.darkSurface : WeekPactColors.cream;
    final outline = dark ? WeekPactColors.darkBorder : WeekPactColors.black;
    final inputBorder = OutlineInputBorder(
      borderSide: BorderSide(color: outline, width: WeekPactMetrics.border),
      borderRadius: BorderRadius.circular(8),
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
      scaffoldBackgroundColor: Colors.transparent,
      colorScheme:
          ColorScheme.fromSeed(
            seedColor: primary,
            brightness: brightness,
            surface: surface,
          ).copyWith(
            onSurface: foreground,
            onSurfaceVariant: dark
                ? WeekPactColors.darkMuted
                : WeekPactColors.mutedLight,
            primary: dark ? const Color(0xFFF1D68A) : WeekPactColors.pinkInk,
            onPrimary: WeekPactColors.black,
            outline: outline,
            error: dark ? WeekPactColors.darkError : WeekPactColors.error,
            surfaceTint: Colors.transparent,
          ),
    );

    return base.copyWith(
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
        shape: Border.all(color: background, width: WeekPactMetrics.border),
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
  Color get surface =>
      isDark ? WeekPactColors.darkSurface : WeekPactColors.cream;
  Color get border => isDark ? WeekPactColors.darkBorder : WeekPactColors.black;
  Color get shadow => isDark ? WeekPactColors.darkShadow : WeekPactColors.black;
  Color get yellow =>
      isDark ? WeekPactColors.darkYellow : WeekPactColors.softYellow;
  Color get mint => isDark ? WeekPactColors.darkMint : WeekPactColors.mintGreen;
  Color get coral =>
      isDark ? WeekPactColors.darkCoral : WeekPactColors.softCoral;
  Color get pink =>
      isDark ? WeekPactColors.darkPink : WeekPactColors.bubblegumPink;
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
    if (!isDark) return color;
    if (color == WeekPactColors.softYellow) return yellow;
    if (color == WeekPactColors.mintGreen) return mint;
    if (color == WeekPactColors.softCoral) return coral;
    if (color == WeekPactColors.bubblegumPink) return pink;
    if (color == WeekPactColors.cream) return surface;
    return color;
  }
}
