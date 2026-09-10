import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:weekpact/src/theme/theme_preference.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weekpact/src/theme/weekpact_theme.dart';
import 'package:weekpact/src/widgets/brutal_widgets.dart';

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

  testWidgets(
    'dark cards, tabs, inputs and shadows use contrasting theme colors',
    (tester) async {
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
                return BrutalTabbedCard(
                  title: 'WEEKLY GOALS',
                  tabColor: WeekPactColors.mintGreen,
                  child: Column(
                    children: [
                      const Text('Small steps start here.'),
                      BrutalTextField(
                        label: 'GOAL NAME',
                        hint: 'Read',
                        controller: controller,
                        validator: (_) => null,
                      ),
                      BrutalButton(
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
      expect(themed.surface, WeekPactColors.darkSurface);
      expect(themed.fieldInk, themed.ink);
      for (final background in [
        themed.canvas,
        themed.surface,
        themed.yellow,
        themed.mint,
        themed.coral,
        themed.pink,
      ]) {
        expect(contrast(themed.ink, background), greaterThanOrEqualTo(4.5));
      }
      expect(contrast(themed.muted, themed.surface), greaterThanOrEqualTo(4.5));
      expect(contrast(themed.shadow, themed.canvas), greaterThanOrEqualTo(3));
      final decorations = tester
          .widgetList<Container>(find.byType(Container))
          .map((widget) => widget.decoration)
          .whereType<BoxDecoration>();
      expect(
        decorations.any((decoration) => decoration.color == WeekPactColors.cream),
        isFalse,
      );
      expect(
        decorations.any(
          (decoration) => decoration.color == WeekPactColors.darkMint,
        ),
        isTrue,
      );
      expect(
        decorations.any(
          (decoration) => decoration.color == WeekPactColors.darkCoral,
        ),
        isTrue,
      );
      expect(
        decorations.any(
          (decoration) =>
              decoration.boxShadow?.any(
                (shadow) => shadow.color == WeekPactColors.darkShadow,
              ) ??
              false,
        ),
        isTrue,
      );
      expect(
        tester.widget<TextFormField>(find.byType(TextFormField)).controller,
        controller,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
