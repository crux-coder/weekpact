import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weekpact/src/auth/auth_backend.dart';
import 'package:weekpact/src/chat/chat_session.dart';
import 'package:weekpact/src/crew/crew_backend.dart';
import 'package:weekpact/src/home/home_page.dart';
import 'package:weekpact/src/theme/weekpact_theme.dart';
import 'package:weekpact/src/widgets/page_frame.dart';

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

  testWidgets('tapping outside the composer closes the keyboard', (
    tester,
  ) async {
    await pumpHome(tester, server);
    await tester.tap(find.byKey(const ValueKey('nav-chat')));
    await tester.pumpUi();

    final input = find.byKey(const ValueKey('chat-input'));
    bool focused() => tester
        .widget<EditableText>(
          find.descendant(of: input, matching: find.byType(EditableText)),
        )
        .focusNode
        .hasFocus;

    await tester.enterText(input, 'Hi');
    await tester.pump();
    expect(focused(), isTrue);

    // Sending keeps the keyboard up for the next message.
    await tester.tap(find.byKey(const ValueKey('chat-send')));
    await tester.pumpUi();
    expect(focused(), isTrue);

    await tester.tapAt(tester.getCenter(find.text('Hi')));
    await tester.pumpUi();
    expect(focused(), isFalse);
  });

  testWidgets('the skeleton draws its bubbles as tall as a message', (
    tester,
  ) async {
    final other = await crewmate(server);
    addTearDown(other.dispose);
    await other.send('Morning');
    await pumpHome(tester, server);
    await tester.tap(find.byKey(const ValueKey('nav-chat')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final skeleton = find.byWidgetPredicate(
      (w) => w is SkeletonBar && w.height > 30,
    );
    expect(skeleton, findsWidgets);
    final placeholder = tester.getSize(skeleton.first).height;
    await tester.pumpUi();
    final bubble = find
        .ancestor(of: find.text('Morning'), matching: find.byType(Container))
        .first;
    expect(tester.getSize(bubble).height, closeTo(placeholder, .5));
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
    expect(find.text('Seen by Crew member'), findsOneWidget);
  });

  testWidgets('a crewmate\'s message likes on tap and picks on hold', (
    tester,
  ) async {
    final other = await crewmate(server);
    addTearDown(other.dispose);
    await other.send('Ran 10k');
    await pumpHome(tester, server);
    await tester.tap(find.byKey(const ValueKey('nav-chat')));
    await tester.pumpUi();
    final id = other.messages.single.id;
    final button = find.byKey(ValueKey('chat-reaction-button-$id'));

    // Always there, and a tap is a like; another tap takes it back.
    expect(button, findsOneWidget);
    await tester.tap(button);
    await tester.pumpUi();
    expect(other.messages.single.reactions, {viewer: '👍'});
    await tester.tap(button);
    await tester.pumpUi();
    expect(other.messages.single.reactions, isEmpty);

    // Holding opens every reaction; the one picked replaces the like.
    await tester.longPress(button);
    await tester.pumpUi();
    expect(find.byKey(const ValueKey('chat-reaction-popup')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('chat-react-🔥')));
    await tester.pumpUi();
    expect(find.byKey(const ValueKey('chat-reaction-popup')), findsNothing);
    expect(other.messages.single.reactions, {viewer: '🔥'});

    // A tap now takes the fire back, and a double tap on the bubble likes.
    await tester.tap(button);
    await tester.pumpUi();
    expect(other.messages.single.reactions, isEmpty);
    await tester.tap(find.text('Ran 10k'));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.text('Ran 10k'));
    await tester.pumpUi();
    expect(other.messages.single.reactions, {viewer: '👍'});

    // Theirs sit beside yours with their count, and the sheet says who.
    final others = find.byKey(ValueKey('chat-reaction-others-$id'));
    expect(others, findsNothing);
    await other.react(id, '❤️');
    await tester.pumpUi();
    expect(
      find.descendant(of: others, matching: find.text('1')),
      findsOneWidget,
    );
    expect(
      tester.getCenter(others).dx,
      greaterThan(tester.getCenter(button).dx),
    );
    // Holding the message lists who reacted, with what, and no picker.
    await tester.longPress(find.text('Ran 10k'));
    await tester.pumpUi();
    final people = find.byKey(const ValueKey('chat-message-people'));
    expect(
      find.descendant(of: people, matching: find.text('You')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: people, matching: find.text('Crew member')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('chat-react-👍')), findsNothing);
    expect(find.text('Copy'), findsOneWidget);
    // Not yours to delete.
    expect(find.text('Delete'), findsNothing);
  });

  testWidgets('your own message shows a reaction only once given', (
    tester,
  ) async {
    final other = await crewmate(server);
    addTearDown(other.dispose);
    await pumpHome(tester, server);
    await tester.tap(find.byKey(const ValueKey('nav-chat')));
    await tester.pumpUi();
    await tester.enterText(find.byKey(const ValueKey('chat-input')), 'PB');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('chat-send')));
    await tester.pumpUi();
    final id = other.messages.single.id;
    final others = find.byKey(ValueKey('chat-reaction-others-$id'));
    expect(others, findsNothing);
    final people = find.byKey(const ValueKey('chat-message-people'));
    final crewmateRow = find.descendant(
      of: people,
      matching: find.text('Crew member'),
    );

    // Holding it says nobody has seen it, until they read it.
    await tester.longPress(find.text('PB'));
    await tester.pumpUi();
    expect(find.text('Nobody has seen this yet.'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpUi();
    await other.markRead();
    await tester.pumpUi();
    await tester.longPress(find.text('PB'));
    await tester.pumpUi();
    expect(crewmateRow, findsOneWidget);
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpUi();

    await other.react(id, '👏');
    await tester.pumpUi();
    expect(others, findsOneWidget);
    // There is no reaction of yours to give on your own message.
    expect(find.byKey(ValueKey('chat-reaction-button-$id')), findsNothing);
    // Tapping theirs opens the same list.
    await tester.tap(others);
    await tester.pumpUi();
    expect(crewmateRow, findsOneWidget);
    expect(other.messages.single.reactions, {'other': '👏'});
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
