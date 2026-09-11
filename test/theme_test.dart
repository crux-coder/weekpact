import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:weekpact/src/theme/theme_preference.dart';
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

void main() {
  test(
    'theme preference defaults to device and restores saved choices',
    () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      expect(ThemePreferenceStore(preferences).mode, ThemeMode.system);
      for (final mode in ThemeMode.values) {
        await ThemePreferenceStore(preferences).save(mode);
        expect(ThemePreferenceStore(preferences).mode, mode);
      }
      await preferences.setString(ThemePreferenceStore.key, 'invalid');
      expect(ThemePreferenceStore(preferences).mode, ThemeMode.system);
    },
  );

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
                title: 'Weekly goals',
                builder: (context) => Column(
                  children: [
                    const Text('Small steps start here.'),
                    AppTextField(
                      label: 'GOAL NAME',
                      hint: 'Read',
                      controller: controller,
                      validator: (_) => null,
                    ),
                    AppButton(
                      label: 'ADD GOAL',
                      color: WeekPactColors.softCoral,
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
