import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weekpact/src/auth/account_page.dart';
import 'package:weekpact/src/auth/auth_backend.dart';
import 'package:weekpact/src/onboarding/profile_avatar.dart';
import 'package:weekpact/src/theme/weekpact_theme.dart';

import 'support/pump_ui.dart';

void main() {
  for (final size in [
    const Size(390, 844),
    const Size(320, 568),
    const Size(844, 390),
  ]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'account actions remain accessible at $size and text scale $scale',
        (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          var signedOut = false;
          await tester.pumpWidget(
            MaterialApp(
              theme: WeekPactTheme.dark,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: Scaffold(
                body: AccountPage(
                  user: const AuthUser(
                    email: 'alex.morgan@example.com',
                    firstName: 'Alex',
                    lastName: 'Morgan',
                  ),
                  backend: const MissingConfigurationAuthBackend(),
                  signingOut: false,
                  onSignOut: () => signedOut = true,
                ),
              ),
            ),
          );
          await tester.pumpUi();
          expect(tester.takeException(), isNull);
          expect(find.text('AM'), findsOneWidget);
          expect(find.text('Reset password'), findsNothing);
          final profile = tester.getRect(
            find.byKey(const ValueKey('account-profile')),
          );
          expect(
            tester.getCenter(find.byType(ProfileAvatar)).dx,
            closeTo(profile.center.dx, 1),
          );
          for (final title in [
            'Notifications',
            'Share crash reports',
            'Support',
            'Privacy policy',
          ]) {
            await tester.ensureVisible(find.text(title));
            await tester.pumpUi();
            expect(find.text(title).hitTestable(), findsOneWidget);
            expect(tester.takeException(), isNull);
          }
          await tester.ensureVisible(find.text('Delete account'));
          await tester.tap(find.text('Delete account'));
          await tester.pumpUi();
          expect(find.text('Delete your account?'), findsOneWidget);
          await tester.tap(find.text('Cancel'));
          await tester.pumpUi();
          await tester.ensureVisible(find.text('Log out'));
          await tester.tap(find.text('Log out'));
          expect(signedOut, isTrue);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
