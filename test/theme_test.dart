import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weekpact/src/theme/weekpact_theme.dart';
import 'package:weekpact/src/widgets/app_components.dart';

double contrast(Color a, Color b) {
  final first = a.computeLuminance();
  final second = b.computeLuminance();
  return first > second
      ? (first + .05) / (second + .05)
      : (second + .05) / (first + .05);
}

/// How far apart two colours look, rather than how far apart their numbers
/// are: CIE76 in Lab, where 1 is about the smallest difference an eye can
/// find and anything past 30 is plainly another colour.
double difference(Color a, Color b) {
  List<double> lab(Color colour) {
    double linear(double channel) => channel <= .04045
        ? channel / 12.92
        : math.pow((channel + .055) / 1.055, 2.4) as double;
    final r = linear(colour.r);
    final g = linear(colour.g);
    final b = linear(colour.b);
    // D65, the white the screen is.
    double f(double t) =>
        t > .008856 ? math.pow(t, 1 / 3) as double : 7.787 * t + 16 / 116;
    final x = f((r * .4124 + g * .3576 + b * .1805) / .95047);
    final y = f(r * .2126 + g * .7152 + b * .0722);
    final z = f((r * .0193 + g * .1192 + b * .9505) / 1.08883);
    return [116 * y - 16, 500 * (x - y), 200 * (y - z)];
  }

  final first = lab(a);
  final second = lab(b);
  return math.sqrt(
    List.generate(
      3,
      (i) => (first[i] - second[i]) * (first[i] - second[i]),
    ).reduce((sum, term) => sum + term),
  );
}

void main() {
  test('a page dot is a colour, not a paler ink', () {
    // The five destinations' full stops, as the pages set them.
    const dots = {
      'Home': WeekPactColors.salmon,
      'Pacts': WeekPactColors.lavender,
      'Feed': WeekPactColors.lime,
      'Crews': WeekPactColors.sky,
      'Account': WeekPactColors.lantern,
    };
    // A dot is six pixels beside 32pt of cream. A card tint at that size is
    // just more cream — which is what the canvas ink already is — so each one
    // has to stand well clear of it.
    dots.forEach((page, dot) {
      expect(
        difference(dot, WeekPactColors.darkInk),
        greaterThan(30),
        reason: "$page's dot reads as the ink beside it",
      );
    });
    // And clear of each other: the dot is how a destination is known before
    // its title is read, which two dots of one colour cannot do.
    for (final one in dots.entries) {
      for (final other in dots.entries) {
        if (one.key == other.key) continue;
        expect(
          difference(one.value, other.value),
          greaterThan(30),
          reason: '${one.key} and ${other.key} wear the same dot',
        );
      }
    }
  });
  testWidgets('home palette cards retain contrast on the dark canvas', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    late BuildContext themed;
    await tester.pumpWidget(
      MaterialApp(
        theme: WeekPactTheme.dark,
        home: Scaffold(
          body: Builder(
            builder: (context) {
              themed = context;
              return AppSectionCard(
                title: 'Weekly pacts',
                builder: (context) => Column(
                  children: [
                    const Text('Small steps start here.'),
                    AppTextField(
                      label: 'PACT NAME',
                      hint: 'Read',
                      controller: controller,
                      validator: (_) => null,
                    ),
                    AppButton(
                      label: 'ADD PACT',
                      color: WeekPactColors.sand,
                      onPressed: () {},
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
    expect(contrast(themed.ink, themed.canvas), greaterThanOrEqualTo(4.5));
    final cardContext = tester.element(find.byType(TextFormField));
    expect(cardContext.surface, WeekPactColors.cream);
    expect(cardContext.ink, WeekPactColors.black);
    for (final fill in [
      cardContext.surface,
      cardContext.yellow,
      cardContext.mint,
    ]) {
      expect(contrast(cardContext.ink, fill), greaterThanOrEqualTo(4.5));
    }
    expect(
      contrast(cardContext.muted, cardContext.surface),
      greaterThanOrEqualTo(4.5),
    );
    final materials = tester.widgetList<Material>(find.byType(Material));
    expect(materials.any((m) => m.color == WeekPactColors.cream), isTrue);
    for (final legacy in [
      WeekPactColors.darkSurface,
      WeekPactColors.darkMint,
      WeekPactColors.darkCoral,
      WeekPactColors.darkYellow,
      WeekPactColors.darkPink,
    ]) {
      expect(materials.any((m) => m.color == legacy), isFalse);
    }
    expect(materials.every((m) => m.elevation == 0), isTrue);
    expect(
      tester.widget<TextFormField>(find.byType(TextFormField)).controller,
      controller,
    );
    expect(tester.takeException(), isNull);
  });
}
