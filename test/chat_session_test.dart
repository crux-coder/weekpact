import 'package:flutter_test/flutter_test.dart';
import 'package:weekpact/src/chat/chat_session.dart';

import 'support/chat_fakes.dart';

const crew = 'crew-1';

void main() {
  late FakeChatServer server;
  final sessions = <ChatSession>[];

  setUp(() => server = FakeChatServer());
  tearDown(() {
    for (final session in sessions) {
      session.dispose();
    }
    sessions.clear();
  });

  Future<ChatSession> open(
    String userId, {
    Duration typingTimeout = const Duration(seconds: 6),
  }) async {
    final session = ChatSession(
      backend: FakeChatBackend(server, userId),
      crewId: crew,
      userId: userId,
      typingTimeout: typingTimeout,
    );
    sessions.add(session);
    await session.open();
    return session;
  }

  /// Lets the events the fake server queued run, and what they start.
  Future<void> settle() async {
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  test('a message reaches every crewmate as it is sent', () async {
    final alice = await open('alice');
    final bob = await open('bob');
    expect(alice.status, ChatStatus.ready);

    expect(await alice.send('  Morning run at 7?  '), isTrue);
    await settle();

    expect(server.messages.values.single.body, 'Morning run at 7?');
    expect(alice.messages.single.text, 'Morning run at 7?');
    expect(alice.messages.single.delivery, ChatDelivery.sent);
    expect(bob.messages.single.text, 'Morning run at 7?');
  });

  test('a crewmate who opens later reads the whole history', () async {
    final alice = await open('alice');
    await alice.send('Before Bob had the app');
    await settle();
    alice.dispose();
    sessions.remove(alice);

    final bob = await open('bob');
    expect(bob.messages.single.text, 'Before Bob had the app');
  });

  test('presence says who has the chat open', () async {
    final alice = await open('alice');
    await open('bob');
    server.syncPresence(crew);
    await settle();
    expect(alice.online, {'alice', 'bob'});
  });

  test('typing is announced, throttled and expires', () async {
    final alice = await open(
      'alice',
      typingTimeout: const Duration(milliseconds: 50),
    );
    final bob = await open('bob');
    bob.typed();
    bob.typed();
    await settle();
    expect(alice.typing, {'bob'});
    final bobConnection = server.connections.firstWhere(
      (c) => c.userId == 'bob',
    );
    expect(bobConnection.typingSent, [true]);

    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(alice.typing, isEmpty);

    // Sending says it stopped.
    bob.typed();
    await bob.send('Done typing');
    await settle();
    expect(bobConnection.typingSent.last, isFalse);
  });

  test('a message arriving clears its sender from typing', () async {
    final alice = await open('alice');
    final bob = await open('bob');
    bob.typed();
    await settle();
    expect(alice.typing, {'bob'});
    await bob.send('Here');
    await settle();
    expect(alice.typing, isEmpty);
  });

  test('reads are shared and say who has seen a message', () async {
    final alice = await open('alice');
    final bob = await open('bob');
    await alice.send('Seen?');
    await settle();
    final message = alice.messages.single;
    expect(alice.readBy(message), isEmpty);

    await bob.markRead();
    await settle();
    expect(alice.readBy(message), {'bob'});
  });

  test('a failed send stays, marked, and can be sent again', () async {
    final alice = await open('alice');
    server.failSends = true;
    await alice.send('Lost in a tunnel');
    expect(alice.messages.single.delivery, ChatDelivery.failed);
    expect(server.messages, isEmpty);

    server.failSends = false;
    await alice.resend(alice.messages.single.id);
    await settle();
    expect(alice.messages.single.delivery, ChatDelivery.sent);
    expect(server.messages, hasLength(1));
  });

  test('deleting unsends for everyone', () async {
    final alice = await open('alice');
    final bob = await open('bob');
    await alice.send('Oops');
    await settle();
    await alice.delete(alice.messages.single.id);
    await settle();
    expect(alice.messages.single.deleted, isTrue);
    expect(bob.messages.single.deleted, isTrue);
    expect(bob.messages.single.text, isNull);
    expect(server.messages.values.single.body, isEmpty);
  });

  test('reactions reach the crew, toggle and replace each other', () async {
    final alice = await open('alice');
    final bob = await open('bob');
    await alice.send('PB today');
    await settle();
    final id = alice.messages.single.id;

    await bob.react(id, '🔥');
    await settle();
    expect(alice.messages.single.reactions, {'bob': '🔥'});
    expect(bob.messages.single.reactions, {'bob': '🔥'});

    // Another emoji replaces it; the same one again takes it back.
    await bob.react(id, '👏');
    await alice.react(id, '👏');
    await settle();
    expect(alice.messages.single.reactions, {'bob': '👏', 'alice': '👏'});
    await bob.react(id, '👏');
    await settle();
    expect(alice.messages.single.reactions, {'alice': '👏'});

    // Somebody opening later reads them with the history.
    final fresh = await open('bob');
    expect(fresh.messages.single.reactions, {'alice': '👏'});
  });

  test('a failed reaction is put back', () async {
    final alice = await open('alice');
    await alice.send('Hi');
    await settle();
    server.failReactions = true;
    await expectLater(
      alice.react(alice.messages.single.id, '😂'),
      throwsStateError,
    );
    expect(alice.messages.single.reactions, isEmpty);
  });

  test('unsending a message clears its reactions', () async {
    final alice = await open('alice');
    final bob = await open('bob');
    await alice.send('Oops');
    await settle();
    final id = alice.messages.single.id;
    await bob.react(id, '😂');
    await settle();
    await alice.delete(id);
    await settle();
    expect(bob.messages.single.reactions, isEmpty);
    expect(server.reactions[id], isNull);
  });

  test('empty and oversized messages are refused', () async {
    final alice = await open('alice');
    expect(await alice.send('   '), isFalse);
    expect(await alice.send('x' * (chatMessageMaxLength + 1)), isFalse);
    // Counted in characters, as the server counts them, not bytes.
    expect(await alice.send('é' * chatMessageMaxLength), isTrue);
    expect(alice.messages, hasLength(1));
  });

  test('older messages page in', () async {
    final alice = await open('alice');
    for (var i = 0; i < 45; i++) {
      await alice.send('m$i');
    }
    final fresh = ChatSession(
      backend: FakeChatBackend(server, 'alice'),
      crewId: crew,
      userId: 'alice',
    );
    sessions.add(fresh);
    await fresh.open();
    expect(fresh.messages, hasLength(40));
    expect(fresh.hasMore, isTrue);
    await fresh.loadMore();
    expect(fresh.messages, hasLength(45));
    expect(fresh.messages.first.text, 'm0');
    expect(fresh.hasMore, isFalse);
  });

  test('a stranger to the crew cannot open it', () async {
    final eve = await open('eve');
    expect(eve.status, ChatStatus.failed);
  });
}
