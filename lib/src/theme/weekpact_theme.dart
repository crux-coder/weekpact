import 'package:flutter/material.dart';

/// Shared stroke and depth values for the app's outlined surfaces.
abstract final class WeekPactMetrics {
  static const border = 1.5;
  static const fineBorder = 1.0;
  static const selectedBorder = 2.0;
  static const shadow = Offset(2, 3);
  static const smallShadow = Offset(1, 2);
  static const pressDepth = 3.0;
  static const buttonHeight = 40.0;
  static const buttonPadding = EdgeInsets.symmetric(
    horizontal: 12,
    vertical: 6,
  );
}

abstract final class WeekPactColors {
  static const black = Color(0xFF090909);
  static const cream = Color(0xFFFFFCF3);
  static const lightCanvas = Color(0xFFF8F5EC);
  static const darkCanvas = Color(0xFF191E25);
  static const darkSurface = Color(0xFF292F38);
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
    final gridColor = context.isDark
        ? const Color(0x14F8F5EC)
        : const Color(0x10090909);

    return ColoredBox(
      color: context.canvas,
      child: CustomPaint(
        painter: _GridPaperPainter(color: gridColor),
        child: child,
      ),
    );
  }
}

class _GridPaperPainter extends CustomPainter {
  const _GridPaperPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    const spacing = 24.0;

    for (var x = 0.0; x <= size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (var y = 0.0; y <= size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _GridPaperPainter oldDelegate) {
    return oldDelegate.color != color;
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
