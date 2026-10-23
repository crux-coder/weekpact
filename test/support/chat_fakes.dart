import 'dart:async';

import 'package:weekpact/src/chat/chat_backend.dart';

/// One chat server that several fake devices talk to.
class FakeChatServer {
  FakeChatServer({Map<String, Set<String>>? crews})
    : members =
          crews ??
          {
            'crew-1': {'alice', 'bob'},
          };

  /// Crew id to the user ids in it.
  final Map<String, Set<String>> members;
  final messages = <String, ChatMessageRecord>{};
  final reads = <String, Map<String, DateTime>>{};

  /// Message id to each reacting user's emoji.
  final reactions = <String, Map<String, String>>{};
  final connections = <FakeChatConnection>[];

  var _clock = DateTime.utc(2026, 10, 21, 9);
  DateTime tick() => _clock = _clock.add(const Duration(seconds: 1));

  bool failSends = false;
  bool failReactions = false;

  void _emit(String crewId, ChatEvent event) {
    for (final connection in [...connections]) {
      if (connection.crewId == crewId) connection.emit(event);
    }
  }

  /// Everyone connected to [crewId], as presence would report it.
  void syncPresence(String crewId) => _emit(
    crewId,
    ChatPresenceChanged({
      for (final c in connections)
        if (c.crewId == crewId) c.userId,
    }),
  );
}

class FakeChatConnection implements ChatConnection {
  FakeChatConnection(this.server, this.crewId, this.userId);
  final FakeChatServer server;
  final String crewId;
  final String userId;
  final _events = StreamController<ChatEvent>.broadcast();
  final typingSent = <bool>[];

  void emit(ChatEvent event) {
    if (!_events.isClosed) _events.add(event);
  }

  @override
  Stream<ChatEvent> get events => _events.stream;

  @override
  Future<void> sendTyping(bool typing) async {
    typingSent.add(typing);
    for (final other in server.connections) {
      if (other.crewId == crewId && other != this) {
        other.emit(ChatTypingChanged(userId, typing));
      }
    }
  }

  @override
  Future<void> close() async {
    server.connections.remove(this);
    await _events.close();
  }
}

/// One signed-in account's view of [server].
class FakeChatBackend implements ChatBackend {
  FakeChatBackend(this.server, this.userId);
  final FakeChatServer server;
  final String userId;

  void _member(String crewId) {
    if (!(server.members[crewId]?.contains(userId) ?? false)) {
      throw StateError('Crew membership required');
    }
  }

  @override
  Future<List<ChatMessageRecord>> fetchMessages(
    String crewId, {
    DateTime? before,
    int limit = 40,
  }) async {
    _member(crewId);
    final rows =
        server.messages.values
            .where(
              (m) =>
                  m.crewId == crewId &&
                  (before == null || m.createdAt.isBefore(before)),
            )
            .toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return [
      for (final m in rows.take(limit))
        ChatMessageRecord(
          id: m.id,
          crewId: m.crewId,
          senderId: m.senderId,
          body: m.body,
          createdAt: m.createdAt,
          deletedAt: m.deletedAt,
          reactions: {...?server.reactions[m.id]},
        ),
    ];
  }

  @override
  Future<ChatMessageRecord> sendMessage({
    required String id,
    required String crewId,
    required String body,
  }) async {
    _member(crewId);
    if (server.failSends) throw StateError('offline');
    final row = ChatMessageRecord(
      id: id,
      crewId: crewId,
      senderId: userId,
      body: body,
      createdAt: server.tick(),
    );
    server.messages[id] = row;
    server._emit(crewId, ChatMessageChanged(row));
    return row;
  }

  @override
  Future<void> deleteMessage(String messageId) async {
    final row = server.messages[messageId]!;
    if (row.senderId != userId) throw StateError('Only the sender');
    final deleted = ChatMessageRecord(
      id: row.id,
      crewId: row.crewId,
      senderId: row.senderId,
      body: '',
      createdAt: row.createdAt,
      deletedAt: server.tick(),
    );
    server.messages[messageId] = deleted;
    server._emit(row.crewId, ChatMessageChanged(deleted));
    for (final who in [...?server.reactions.remove(messageId)?.keys]) {
      server._emit(
        row.crewId,
        ChatReactionChanged(
          ChatReactionRecord(
            messageId: messageId,
            crewId: row.crewId,
            userId: who,
          ),
        ),
      );
    }
  }

  @override
  Future<void> react(String messageId, String? emoji) async {
    final row = server.messages[messageId];
    if (row == null || row.deleted) throw StateError('No such message');
    _member(row.crewId);
    if (server.failReactions) throw StateError('offline');
    final reactions = server.reactions.putIfAbsent(messageId, () => {});
    if (emoji == null) {
      reactions.remove(userId);
    } else {
      reactions[userId] = emoji;
    }
    server._emit(
      row.crewId,
      ChatReactionChanged(
        ChatReactionRecord(
          messageId: messageId,
          crewId: row.crewId,
          userId: userId,
          emoji: emoji,
        ),
      ),
    );
  }

  @override
  Future<void> markRead(String crewId, DateTime at) async {
    final crew = server.reads.putIfAbsent(crewId, () => {});
    final known = crew[userId];
    if (known == null || at.isAfter(known)) crew[userId] = at;
    server._emit(crewId, ChatReadChanged(userId, crew[userId]!));
  }

  @override
  Future<Map<String, DateTime>> fetchReads(String crewId) async => {
    ...?server.reads[crewId],
  };

  @override
  Future<Map<String, int>> fetchUnreadCounts() async => {
    for (final crew in server.members.entries)
      if (crew.value.contains(userId))
        crew.key: server.messages.values
            .where(
              (m) =>
                  m.crewId == crew.key &&
                  m.senderId != userId &&
                  !m.deleted &&
                  (server.reads[crew.key]?[userId] == null ||
                      m.createdAt.isAfter(server.reads[crew.key]![userId]!)),
            )
            .length,
  };

  final activity = StreamController<void>.broadcast();

  @override
  Stream<void> watchActivity(String userId) => activity.stream;

  final opened = <FakeChatConnection>[];

  @override
  ChatConnection connect({required String crewId, required String userId}) {
    final connection = FakeChatConnection(server, crewId, userId);
    server.connections.add(connection);
    opened.add(connection);
    return connection;
  }
}
