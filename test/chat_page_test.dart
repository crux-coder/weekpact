import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weekpact/src/auth/auth_backend.dart';
import 'package:weekpact/src/chat/chat_session.dart';
import 'package:weekpact/src/crew/crew_backend.dart';
import 'package:weekpact/src/home/home_page.dart';
import 'package:weekpact/src/theme/weekpact_theme.dart';

import 'support/chat_fakes.dart';
import 'support/home_fakes.dart';
import 'support/pump_ui.dart';

const viewer = 'user-id';

Future<void> pumpHome(WidgetTester tester, FakeChatServer server) async {
  final home = DashboardBackend(viewerId: viewer);
  await tester.pumpWidget(
    MaterialApp(
      theme: WeekPactTheme.dark,
      home: HomePage(
        user: const AuthUser(email: 'person@example.com', id: viewer),
        authBackend: const MissingConfigurationAuthBackend(),
        crewBackend: const MissingCrewBackend(),
        pactsBackend: home.pacts,
        homeBackend: home,
        chatBackend: FakeChatBackend(server, viewer),
      ),
    ),
  );
  await tester.pumpUi();
}

/// The crewmate on the other end, on a device of their own.
Future<ChatSession> crewmate(FakeChatServer server) async {
  final session = ChatSession(
    backend: FakeChatBackend(server, 'other'),
    crewId: 'crew',
    userId: 'other',
  );
  await session.open();
  return session;
}

void main() {
  late FakeChatServer server;
  setUp(
    () => server = FakeChatServer(
      crews: {
        'crew': {viewer, 'other'},
      },
    ),
  );

  testWidgets('Chat sits between Home and Crews', (tester) async {
    await pumpHome(tester, server);
    final home = tester.getCenter(find.byKey(const ValueKey('nav-home'))).dx;
    final chat = tester.getCenter(find.byKey(const ValueKey('nav-chat'))).dx;
    final crews = tester.getCenter(find.byKey(const ValueKey('nav-crews'))).dx;
    expect(home, lessThan(chat));
    expect(chat, lessThan(crews));
  });

  testWidgets('sends and receives messages, with typing', (tester) async {
    final other = await crewmate(server);
    addTearDown(other.dispose);
    await pumpHome(tester, server);

    await tester.tap(find.byKey(const ValueKey('nav-chat')));
    await tester.pumpUi();
    expect(find.text('Say hi to Early Birds.'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('chat-input')),
      'Who is in for a run?',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('chat-send')));
    await tester.pumpUi();

    expect(find.text('Who is in for a run?'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('chat-input')))
          .controller!
          .text,
      isEmpty,
    );
    expect(other.messages.single.text, 'Who is in for a run?');

    other.typed();
    await tester.pumpUi();
    expect(find.byKey(const ValueKey('chat-typing')), findsOneWidget);

    await other.send('Me! 6:30 at the park');
    await tester.pumpUi();
    expect(find.text('Me! 6:30 at the park'), findsOneWidget);
    expect(find.byKey(const ValueKey('chat-typing')), findsNothing);

    // Reading on this device shows up as seen on theirs, and theirs here.
    expect(other.reads[viewer], isNotNull);
    await other.markRead();
    await tester.pumpUi();
    expect(find.text(' · Seen by Crew member'), findsOneWidget);
  });

  testWidgets('a failed message says so and sends on retry', (tester) async {
    await pumpHome(tester, server);
    await tester.tap(find.byKey(const ValueKey('nav-chat')));
    await tester.pumpUi();

    server.failSends = true;
    await tester.enterText(find.byKey(const ValueKey('chat-input')), 'Hi');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('chat-send')));
    await tester.pumpUi();
    expect(find.byKey(const ValueKey('chat-not-sent')), findsOneWidget);

    server.failSends = false;
    await tester.tap(find.byKey(const ValueKey('chat-not-sent')));
    await tester.pumpUi();
    await tester.tap(find.text('Try again'));
    await tester.pumpUi();
    expect(find.byKey(const ValueKey('chat-not-sent')), findsNothing);
    expect(server.messages, hasLength(1));
  });

  testWidgets('unread messages put a dot on Chat until they are read', (
    tester,
  ) async {
    final other = await crewmate(server);
    addTearDown(other.dispose);
    await other.send('Anyone up?');

    await pumpHome(tester, server);
    expect(find.byKey(const ValueKey('nav-badge-chat')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('nav-chat')));
    await tester.pumpUi();
    expect(find.byKey(const ValueKey('nav-badge-chat')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('nav-home')));
    await tester.pumpUi();
    expect(find.byKey(const ValueKey('nav-badge-chat')), findsNothing);
  });
}
