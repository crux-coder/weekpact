import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weekpact/src/theme/weekpact_theme.dart';
import 'package:weekpact/src/widgets/app_components.dart';

void main() {
  // On iOS the focusing tap lands the cursor on the nearer edge of the word
  // under it, so a filled field tapped on its left opened with the cursor
  // before the first letter, which read as that letter being cut off.
  testWidgets('a filled field opens with the cursor at the end, wherever '
      'it was tapped', (tester) async {
    final controller = TextEditingController(text: 'hello');
    await tester.pumpWidget(
      MaterialApp(
        theme: WeekPactTheme.light,
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: AppTextField(
              hint: 'Description',
              controller: controller,
              validator: (_) => null,
              minLines: 2,
              maxLines: 4,
            ),
          ),
        ),
      ),
    );
    final text = tester.getRect(find.byType(EditableText));
    for (final dx in [-10.0, 1.0, 200.0]) {
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tapAt(Offset(text.left + dx, text.top + 10));
      await tester.pump(const Duration(milliseconds: 500));
      expect(
        controller.selection,
        const TextSelection.collapsed(offset: 5),
        reason: 'tapped at $dx',
      );
    }
    // Once in, a tap still puts the cursor where it lands.
    await tester.tapAt(Offset(text.left + 1, text.top + 10));
    await tester.pump(const Duration(milliseconds: 500));
    expect(controller.selection.baseOffset, 0);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  // Fields are cream in both themes, but the cursor is set at the app's root
  // from the app's own theme: in the dark one it came out near-white on
  // cream, and no one could see it.
  for (final dark in [false, true]) {
    testWidgets('the cursor is ink on a cream field in the '
        '${dark ? 'dark' : 'light'} theme', (tester) async {
      final controller = TextEditingController(text: 'testing');
      await tester.pumpWidget(
        MaterialApp(
          theme: dark ? WeekPactTheme.dark : WeekPactTheme.light,
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: AppTextField(
                hint: 'Description',
                controller: controller,
                validator: (_) => null,
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byType(EditableText));
      await tester.pump(const Duration(milliseconds: 100));
      final field = tester.widget<EditableText>(find.byType(EditableText));
      expect(field.focusNode.hasFocus, isTrue);
      expect(field.cursorColor, WeekPactColors.black);
    }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
  }
}
