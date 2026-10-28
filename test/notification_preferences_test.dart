import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weekpact/src/auth/account_page.dart';
import 'package:weekpact/src/auth/auth_backend.dart';
import 'package:weekpact/src/notifications/notification_kind_controls.dart';
import 'package:weekpact/src/notifications/notification_preferences.dart';
import 'package:weekpact/src/notifications/notification_scope.dart';
import 'package:weekpact/src/notifications/notification_service.dart';
import 'package:weekpact/src/theme/weekpact_theme.dart';

import 'notifications_test.dart' show FakeMessaging;
import 'support/pump_ui.dart';
import 'widget_test.dart' show FakeAuthBackend;

class FakePreferences implements NotificationPreferencesBackend {
  FakePreferences([this.stored = const NotificationPreferences()]);
  NotificationPreferences stored;
  final saves = <(NotificationKind, bool)>[];
  bool failSaves = false;
  bool failFetch = false;

  @override
  Future<NotificationPreferences> fetchNotificationPreferences() async {
    if (failFetch) throw StateError('offline');
    return stored;
  }

  @override
  Future<NotificationPreferences> setNotificationPreference(
    NotificationKind kind,
    bool enabled,
  ) async {
    saves.add((kind, enabled));
    if (failSaves) throw StateError('offline');
    return stored = stored.withKind(kind, enabled);
  }
}

class PreferencesAuthBackend extends FakeAuthBackend
    implements NotificationPreferencesBackend {
  final preferences = FakePreferences();

  @override
  Future<NotificationPreferences> fetchNotificationPreferences() =>
      preferences.fetchNotificationPreferences();

  @override
  Future<NotificationPreferences> setNotificationPreference(
    NotificationKind kind,
    bool enabled,
  ) => preferences.setNotificationPreference(kind, enabled);
}

bool switchOn(WidgetTester tester, NotificationKind kind) => tester
    .widget<SwitchListTile>(
      find.byKey(ValueKey('notification-kind-${kind.key}')),
    )
    .value;

void main() {
  test('a kind the server leaves out is on', () {
    final preferences = NotificationPreferences.fromJson({'claps': false});
    expect(preferences.wants(NotificationKind.checkIns), isTrue);
    expect(preferences.wants(NotificationKind.claps), isFalse);
    expect(preferences.wants(NotificationKind.chat), isTrue);
  });

  group('the three switches', () {
    Future<void> show(WidgetTester tester, FakePreferences backend) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: WeekPactTheme.dark,
          home: Scaffold(body: NotificationKindControls(backend: backend)),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('show what the account has saved', (tester) async {
      await show(
        tester,
        FakePreferences(const NotificationPreferences(chat: false)),
      );
      expect(find.text('Pact check-ins'), findsOneWidget);
      expect(find.text('Claps'), findsOneWidget);
      expect(find.text('Chat'), findsOneWidget);
      expect(switchOn(tester, NotificationKind.checkIns), isTrue);
      expect(switchOn(tester, NotificationKind.claps), isTrue);
      expect(switchOn(tester, NotificationKind.chat), isFalse);
    });

    testWidgets('each turns off its own kind and no other', (tester) async {
      final backend = FakePreferences();
      await show(tester, backend);
      for (final kind in NotificationKind.values) {
        await tester.tap(find.byKey(ValueKey('notification-kind-${kind.key}')));
        await tester.pumpAndSettle();
        expect(backend.saves.last, (kind, false));
        for (final other in NotificationKind.values) {
          // Kinds already tapped stay off; the rest are untouched.
          final tapped = other.index <= kind.index;
          expect(switchOn(tester, other), !tapped);
          expect(backend.stored.wants(other), !tapped);
        }
      }
      expect(backend.saves, hasLength(3));
    });

    testWidgets('a save that fails puts that switch back', (tester) async {
      final backend = FakePreferences()..failSaves = true;
      await show(tester, backend);
      await tester.tap(find.text('Claps'));
      await tester.pumpAndSettle();
      expect(switchOn(tester, NotificationKind.claps), isTrue);
      expect(
        find.text('Could not update notifications. Please retry.'),
        findsOneWidget,
      );
    });

    testWidgets('a failed load offers a retry', (tester) async {
      final backend = FakePreferences()..failFetch = true;
      await show(tester, backend);
      expect(find.text('Claps'), findsNothing);
      backend.failFetch = false;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('Claps'), findsOneWidget);
    });
  });

  group('in Account settings', () {
    late FakeMessaging client;
    late NotificationService service;

    Future<void> openSettings(WidgetTester tester, AuthBackend backend) async {
      await service.initialize();
      await tester.pumpWidget(
        MaterialApp(
          theme: WeekPactTheme.dark,
          // Where the app puts it, so the settings sheet sees it too.
          builder: (context, child) =>
              NotificationScope(service: service, child: child!),
          home: Scaffold(
            body: AccountPage(
              user: const AuthUser(
                email: 'alex.morgan@example.com',
                firstName: 'Alex',
                lastName: 'Morgan',
              ),
              backend: backend,
              signingOut: false,
              onSignOut: () {},
            ),
          ),
        ),
      );
      await tester.pumpUi();
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpUi();
    }

    tearDown(() async {
      service.dispose();
      await client.dispose();
    });

    testWidgets('appear under Notifications while this phone has them on', (
      tester,
    ) async {
      client = FakeMessaging();
      service = NotificationService(
        createClient: () async => client,
        saveEnabled: (_) async {},
        enabled: true,
        delay: (_) async {},
      );
      final backend = PreferencesAuthBackend();
      await openSettings(tester, backend);
      await tester.ensureVisible(find.text('Chat'));
      await tester.tap(find.text('Chat'));
      await tester.pumpUi();
      expect(backend.preferences.saves, [(NotificationKind.chat, false)]);
      expect(tester.takeException(), isNull);
    });

    testWidgets('stay out of the way while the phone has them off', (
      tester,
    ) async {
      client = FakeMessaging();
      service = NotificationService(
        createClient: () async => client,
        saveEnabled: (_) async {},
        delay: (_) async {},
      );
      await openSettings(tester, PreferencesAuthBackend());
      expect(find.text('Notifications'), findsOneWidget);
      expect(find.text('Pact check-ins'), findsNothing);
    });
  });
}
