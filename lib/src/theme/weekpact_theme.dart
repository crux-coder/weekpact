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
    borderRadius: BorderRadius.all(Radius.circular(cardCurve)),
  );
  static const raisedOffset = Offset(0, controlDepth);

  // Corners. There are four, and only four.
  //
  // A control, a cell or a flat panel is a rounded rect of `controlRadius`.
  // A card is a continuous squircle: `cardCorner` is that corner as a plain
  // radius and `cardCurve` is the same corner drawn as a squircle, which needs
  // a larger number to read at the same size — `curveFor` converts between
  // them, so a surface can switch shape without a caller restating both. A
  // smaller raised panel, header or tile steps down to `panelCurve`, keeping
  // the curve proportional to the box instead of swallowing it. Buttons use
  // `buttonShape`. Reach for one of these rather than a new number.
  static const controlRadius = 8.0;
  static const cardCorner = 18.0;
  static const cardCurve = 40.0;
  static const panelCurve = 24.0;
  static const buttonShape = SquircleButtonBorder();

  /// The squircle curve that draws `radius` at the size it reads as a card.
  static double curveFor(double radius) => radius * (cardCurve / cardCorner);

  /// A bar, pip or progress track: rounded to its own half-height, so it reads
  /// as a pill at whatever size it happens to be rather than at a guessed
  /// radius. Oversized on purpose — the paint clamps it to the box.
  static const pill = BorderRadius.all(Radius.circular(999));

  /// Modal sheets meet the screen edge, so they round only along the top.
  static const sheetRadius = 16.0;
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
  // Plain grey, with none of the palette's blue-green in it: the whole card set
  // is marine now, so waiting has to read as absence of colour, not a paler sea.
  static const pendingCheckIns = Color(0xFFC6CACB);
  static const success = Color(0xFF4C8C5D);
  static const warning = Color(0xFFC48A42);
  static const outlineInk = Color(0xFF161C23);
  static const sky = Color(0xFF87CFFA);
  static const lavender = Color(0xFFBEA8F5);
  static const lime = Color(0xFFBBDC99);
  static const salmon = Color(0xFFFF836F);
  static const black = Color(0xFF191B19);
  static const cream = Color(0xFFF0F5F4);
  static const lightCanvas = Color(0xFFE4EBEA);
  static const darkCanvas = Color(0xFF222A2B);
  static const darkSurface = Color(0xFF202829);
  static const darkInk = Color(0xFFEDF3F2);
  static const darkBorder = Color(0xFF67797C);
  static const darkShadow = darkBorder;
  static const darkMuted = Color(0xFFAAB8B9);
  static const darkYellow = Color(0xFF49412B);
  static const darkMint = Color(0xFF304531);
  static const darkCoral = Color(0xFF523732);
  static const darkPink = Color(0xFF483743);
  static const darkAccent = coolGrey;
  static const darkError = Color(0xFFFFA8AE);
  static const mintGreen = Color(0xFFA8D2CC);
  static const bubblegumPink = Color(0xFFEAC7D4);
  static const pinkInk = Color(0xFF475556);

  /// The palette's two warm notes, and the only ones: the sand on the quay and
  /// the brass on the boats. They carry the roles a marine tint cannot — a
  /// subscription that is ending, a clap the viewer gave — so those read as
  /// themselves rather than as one more card colour.
  static const sand = Color(0xFFE0D9C0);
  static const brass = Color(0xFFE6D7A6);

  /// The five destinations' full stops: `salmon` Home, `lavender` Pacts,
  /// `lime` Feed, `sky` Crews and `lantern` Account.
  ///
  /// A page's dot is a 32pt full stop — six pixels of colour against cream
  /// ink, on a canvas the app never leaves. The card tints and the quay's warm
  /// notes are chosen to sit *under* ink, so at that size every one of them
  /// goes white; the dot is the one place the palette has to be loud. These
  /// five are the hues held at full chroma for it, one per destination, spaced
  /// far enough apart in hue to be told apart before the title is read.
  ///
  /// `lantern` is the warm one, and the Account dot: a light on the quay
  /// rather than the sun on it, so it reads as gold beside cream where `sand`
  /// and `brass` read as more cream. Keep it clear of `streak`'s orange —
  /// that one answers to nothing else in the palette, and a dot wearing it
  /// would say a streak is running.
  static const lantern = Color(0xFFF0B858);

  static const stone = Color(0xFFCDE0DC);
  static const coolGrey = Color(0xFF9FCBD9);
  static const neutralInset = Color(0xFFD7E0DF);
  static const activitySurface = Color(0xFF1F2627);
  // Card tints: warm, and held to the depth where a card still reads as
  // tinted paper but the tint reads as a colour rather than as a smudge — the
  // pale versions washed out against cream and the fill lost its edge. The
  // quay rather than the water — clay, straw and sage, with the two greens
  // kept warm so they sit in the same light as the rest. They are ordered so
  // neighbours in the list sit far apart in hue: most crews run two or three
  // pacts, so the first few entries are the ones that have to look least
  // alike. Every one clears 7:1 against card ink.
  static const pactPalette = <Color>[
    Color(0xFFD0B2A4), // Clay.
    Color(0xFFB4C8A2), // Sage.
    Color(0xFFD6B2B6), // Blush.
    Color(0xFFBEC596), // Olive.
    Color(0xFFD6CCAE), // Straw.
    Color(0xFFC6A39F), // Rosewood.
    Color(0xFFB5CCAE), // Moss.
    Color(0xFFD4C0AA), // Apricot.
    Color(0xFFBFACA1), // Mushroom.
    Color(0xFFD8D4BA), // Wheat.
  ];

  /// The same ten, with the chroma the card gives up.
  ///
  /// A card this quiet cannot also be the thing that tells two pacts apart at
  /// a glance, so the pact's icon badge carries that: the card's own hue held
  /// deep enough to read as an object sitting on the card rather than as a
  /// patch of it. Paired by index with [pactPalette] — a new tint needs a new
  /// badge on the same line, in the same hue.
  static const pactBadgePalette = <Color>[
    Color(0xFFCBA08B), // Clay.
    Color(0xFFA4C289), // Sage.
    Color(0xFFD1999F), // Blush.
    Color(0xFFB8C17B), // Olive.
    Color(0xFFD0C295), // Straw.
    Color(0xFFC18C86), // Rosewood.
    Color(0xFFA2C497), // Moss.
    Color(0xFFCEB092), // Apricot.
    Color(0xFFB79B8A), // Mushroom.
    Color(0xFFD2CBA3), // Wheat.
  ];

  /// A pact's card colour, by its position in the crew's pact list. Home, the
  /// crew week and the pacts page all read it, so one pact looks the same
  /// wherever it appears.
  static Color pactTint(int index) => pactPalette[index % pactPalette.length];

  /// The badge colour that goes with [pactTint] at the same index.
  static Color pactBadge(int index) =>
      pactBadgePalette[index % pactBadgePalette.length];

  static const mutedLight = Color(0xFF46535A);
  static const error = Color(0xFFC94F59);

  // Edges and outlines for the two crew check-in tile states. One value per
  // state, shared by the tile's outline, its raised edge, the faces and the
  // overflow chip, so a tile reads as a single object.
  static const mintEdge = Color(0xFF6D9188);
  static const pendingEdge = Color(0xFFA3A9AA);

  /// The week in progress: the crew progress card on Home and on the crew week
  /// page, while the week is still being kept. Pale citron — the one hue the
  /// harbour does not carry — so a week underway is told apart from a week
  /// finished at a glance rather than by reading the number.
  static const crewProgress = Color(0xFFF2F3AE);

  /// A day kept, on the crew week's calendar. Sea glass sat on the old marine
  /// card set; on a warm card it read as the one cool thing on the page, so
  /// the kept day is a warm green off the same quay. It clears 10:1 with card
  /// ink and stands clear of all ten tints, olive — the nearest — included.
  static const keptDay = Color(0xFFB8CC8E);

  /// The one green for a completed check-in, on cards and on the nudge button.
  /// Deeper and bluer than the sea glass tint, so done reads as a mark rather
  /// than as another card colour.
  static const doneMark = Color(0xFF3F7A6B);

  /// Graphite: the small dark action sitting on a light surface — the nudge
  /// button's face, with its own lifted edge underneath.
  static const graphite = Color(0xFF363F40);
  static const graphiteEdge = Color(0xFF66716F);

  /// The streak flame, once the streak has started. The one warm signal that
  /// answers to nothing else in the palette.
  static const streak = Color(0xFFE08A45);

  /// The dark check-in button's outline and raised edge: black lifted just
  /// enough to separate the face from its own shadow.
  static const inkEdge = Color(0xFF484848);

  /// The selected navigation tile on a dark canvas: muted off-white, cooled
  /// toward the canvas rather than bright white.
  static const navSelected = Color(0xFFCCD8D6);

  /// A cast shadow on the canvas, where no card colour is available to mix from.
  static const castShadow = Color(0x40000000);

  /// The wash over the page behind a sheet or a dialog. Deep enough that the
  /// surface in front reads as lifted off the page rather than laid on it, and
  /// that the page underneath stops competing for the eye.
  static const barrier = Color(0xB3191B19);
}

/// The app's face. Rubik is the whole of it — display, body copy, captions and
/// numerals alike — and it is the theme's default, so a call site only names a
/// family when it is spelling out the one it already has.
///
/// [secondary] is kept because the small-caps labels, captions and numerals
/// name it, and what they are asking for is the face the caption sets in. It
/// is the same family as the display face now; it stays a name of its own so
/// those call sites keep saying which role they are, and so a second face can
/// come back without rewriting all of them.
abstract final class WeekPactType {
  static const primary = 'Rubik';
  static const secondary = primary;
  static const secondaryFallback = <String>['Arial'];
}

/// The charcoal card.
///
/// Most of the app is pale cards with dark ink. Three content-heavy surfaces —
/// the Feed, the paywall and the subscription page — invert that: the photos
/// and the pricing carry the colour there, and a pale card would compete with
/// them. Crew week's streak panel and Home's activity panel use it too.
///
/// It is a closed set. Take fill, outline, ink and muted from here together;
/// never put pale-card ink (`WeekPactColors.black`, `mutedLight`) on this fill,
/// and never put these on a pact tint.
abstract final class WeekPactDarkCard {
  static const fill = WeekPactColors.activitySurface;
  static const outline = WeekPactColors.darkBorder;
  static const ink = WeekPactColors.cream;
  static const muted = WeekPactColors.darkMuted;
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
    final outline = const Color(0xFFD5DDDC);
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
      fontFamily: WeekPactType.primary,
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
          borderRadius: BorderRadius.circular(WeekPactMetrics.controlRadius),
          side: BorderSide(color: outline),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(WeekPactMetrics.sheetRadius),
          ),
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
        labelStyle: TextStyle(color: foreground, fontWeight: FontWeight.w500),
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
          fontWeight: FontWeight.w500,
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
    if (color == WeekPactColors.brass || color == WeekPactColors.sand) {
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
