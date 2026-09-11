import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weekpact/src/auth/account_page.dart';
import 'package:weekpact/src/theme/weekpact_theme.dart';

import 'support/pump_ui.dart';

import 'package:weekpact/src/theme/theme_preference.dart';

import 'widget_test.dart' show FakeAuthBackend;

void main() {
  testWidgets('profile editor validates and updates the account header', (
    tester,
  ) async {
    final backend = FakeAuthBackend();
    addTearDown(backend.dispose);
    await backend.signIn(email: 'jasmin@example.com', password: 'password');
    await tester.pumpWidget(
      ThemePreference(
        mode: ThemeMode.light,
        onChanged: (_) {},
        child: MaterialApp(
          theme: WeekPactTheme.light,
          home: Scaffold(
            body: AccountPage(
              user: backend.currentUser!,
              backend: backend,
              signingOut: false,
              onSignOut: () {},
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip('Edit profile'));
    await tester.pumpUi();
    await tester.tap(find.text('SAVE'));
    await tester.pump();
    expect(find.text('Enter your first name'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).first, 'Jasmin');
    await tester.enterText(find.byType(TextFormField).last, 'Test');
    await tester.tap(find.text('SAVE'));
    await tester.pumpUi();
    expect(find.text('Jasmin Test'), findsOneWidget);
    expect(find.text('Edit profile'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
