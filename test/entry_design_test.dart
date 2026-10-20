import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weekpact/src/auth/auth_page.dart';
import 'package:weekpact/src/crew/crew_backend.dart';
import 'package:weekpact/src/invites/invite_links.dart';
import 'package:weekpact/src/onboarding/onboarding_draft.dart';
import 'package:weekpact/src/onboarding/onboarding_flow.dart';
import 'package:weekpact/src/theme/weekpact_theme.dart';

import 'support/fonts.dart';
import 'support/pump_ui.dart';
import 'widget_test.dart' show FakeAuthBackend;

void main() {
  for (final dark in [false, true]) {
    testWidgets('entry screens fit ${dark ? 'dark' : 'light'} theme', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final backend = FakeAuthBackend();
      addTearDown(backend.dispose);
      const boundaryKey = ValueKey('entry-capture');
      if (const bool.fromEnvironment('CAPTURE_DESIGN')) {
        await tester.runAsync(loadAppFont);
        final icons = FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
        await tester.runAsync(() => icons.load());
      }
      Future<void> capture(String name) async {
        await tester.pumpUi();
        expect(tester.takeException(), isNull);
        if (const bool.fromEnvironment('CAPTURE_DESIGN')) {
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(boundaryKey),
          );
          await tester.runAsync(() async {
            final image = await boundary.toImage();
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await File('/tmp/entry-${dark ? 'dark' : 'light'}-$name.png')
                .writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
      }

      Widget app(Widget child) => MaterialApp(
        theme: dark ? WeekPactTheme.dark : WeekPactTheme.light,
        home: RepaintBoundary(key: boundaryKey, child: child),
      );
      final drafts = OnboardingDraftStore.memory();
      Widget flow({InviteRef? invite, CrewInvitePreview? preview}) =>
          OnboardingFlow(
            authBackend: backend,
            draftStore: drafts,
            invite: invite,
            invitePreview: preview,
            onInvite: (_) {},
            onClearInvite: () {},
            onJoinIntent: (_) {},
          );
      Future<void> tap(Finder finder) async {
        await tester.ensureVisible(finder);
        await tester.tap(finder);
      }

      await tester.pumpWidget(app(flow()));
      await capture('welcome');
      await tap(find.byKey(const ValueKey('get-started')));
      await capture('crew-name');
      await tap(find.byKey(const ValueKey('crew-name-continue')));
      await capture('pact');
      await tap(find.text('Something else'));
      await capture('pact-custom');
      await tap(find.text('Run'));
      await tester.pumpUi();
      await tap(find.byKey(const ValueKey('pact-continue')));
      await capture('save');
      await tap(find.text('Log in'));
      await capture('log-in');
      await tester.pumpWidget(app(EmailLogInPage(authBackend: backend)));
      await capture('email-log-in');
      await tester.pumpWidget(
        app(
          flow(
            invite: const InviteRef('7K2QXM'),
            preview: const CrewInvitePreview(
              crewName: 'Early Birds',
              memberCount: 4,
              ownerName: 'Amra',
              inviterName: 'Edin',
              memberInitials: ['AM', 'EK', 'LS', 'NH'],
              pacts: [
                InvitePact(
                  title: 'Go for a run',
                  iconKey: 'run',
                  daysPerWeek: 3,
                ),
                InvitePact(
                  title: 'Read before bed',
                  iconKey: 'book',
                  daysPerWeek: 5,
                ),
              ],
            ),
          ),
        ),
      );
      await capture('invite');
      await tap(find.byKey(const ValueKey('join-crew')));
      await capture('join');
    });
  }
}
