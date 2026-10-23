import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

/// A message as the server holds it.
class ChatMessageRecord {
  const ChatMessageRecord({
    required this.id,
    required this.crewId,
    required this.senderId,
    required this.body,
    required this.createdAt,
    this.deletedAt,
    this.reactions,
  });

  final String id;
  final String crewId;
  final String senderId;

  /// Empty once the message is deleted.
  final String body;
  final DateTime createdAt;
  final DateTime? deletedAt;

  /// Each reacting member's emoji, by user id. Null when the row came without
  /// them, as a live update does: whatever is already known still stands.
  final Map<String, String>? reactions;

  bool get deleted => deletedAt != null;

  factory ChatMessageRecord.fromJson(Map<String, dynamic> row) =>
      ChatMessageRecord(
        id: row['id'] as String,
        crewId: row['crew_id'] as String,
        senderId: row['sender_id'] as String,
        body: row['body'] as String? ?? '',
        createdAt: DateTime.parse(row['created_at'] as String),
        deletedAt: row['deleted_at'] == null
            ? null
            : DateTime.parse(row['deleted_at'] as String),
        reactions: row['chat_reactions'] is List
            ? {
                for (final r
                    in (row['chat_reactions'] as List)
                        .cast<Map<String, dynamic>>())
                  if (r['emoji'] is String)
                    r['user_id'] as String: r['emoji'] as String,
              }
            : null,
      );
}

/// The emoji a message can be reacted with: what the server's column allows.
const chatReactions = ['👍', '\u2764\uFE0F', '😂', '🔥', '👏', '😮'];

/// One member's reaction to one message.
class ChatReactionRecord {
  const ChatReactionRecord({
    required this.messageId,
    required this.crewId,
    required this.userId,
    this.emoji,
  });

  final String messageId;
  final String crewId;
  final String userId;

  /// Null once it is taken back.
  final String? emoji;

  factory ChatReactionRecord.fromJson(Map<String, dynamic> row) =>
      ChatReactionRecord(
        messageId: row['message_id'] as String,
        crewId: row['crew_id'] as String,
        userId: row['user_id'] as String,
        emoji: row['emoji'] as String?,
      );
}

/// Something that happened in a crew's chat while it was open.
sealed class ChatEvent {
  const ChatEvent();
}

/// The live connection came up, or came back. Anything could have been
/// missed while it was down.
class ChatConnected extends ChatEvent {
  const ChatConnected();
}

class ChatMessageChanged extends ChatEvent {
  const ChatMessageChanged(this.message);
  final ChatMessageRecord message;
}

class ChatReactionChanged extends ChatEvent {
  const ChatReactionChanged(this.reaction);
  final ChatReactionRecord reaction;
}

class ChatReadChanged extends ChatEvent {
  const ChatReadChanged(this.userId, this.lastReadAt);
  final String userId;
  final DateTime lastReadAt;
}

class ChatTypingChanged extends ChatEvent {
  const ChatTypingChanged(this.userId, this.typing);
  final String userId;
  final bool typing;
}

/// Who has the chat open right now.
class ChatPresenceChanged extends ChatEvent {
  const ChatPresenceChanged(this.userIds);
  final Set<String> userIds;
}

/// One crew's chat, live.
abstract interface class ChatConnection {
  Stream<ChatEvent> get events;
  Future<void> sendTyping(bool typing);
  Future<void> close();
}

abstract interface class ChatBackend {
  /// Newest first, up to [limit], older than [before] when it is given.
  Future<List<ChatMessageRecord>> fetchMessages(
    String crewId, {
    DateTime? before,
    int limit = 40,
  });
  Future<ChatMessageRecord> sendMessage({
    required String id,
    required String crewId,
    required String body,
  });
  Future<void> deleteMessage(String messageId);

  /// Sets this account's reaction to a message, or takes it back with null.
  Future<void> react(String messageId, String? emoji);

  Future<void> markRead(String crewId, DateTime at);
  Future<Map<String, DateTime>> fetchReads(String crewId);

  /// Unread messages from others, by crew.
  Future<Map<String, int>> fetchUnreadCounts();

  /// Fires when a message lands in any of the account's crews, for the
  /// unread dot. Carries nothing: the counts are reread.
  Stream<void> watchActivity(String userId);

  ChatConnection connect({required String crewId, required String userId});
}

class SupabaseChatBackend implements ChatBackend {
  const SupabaseChatBackend(this._client);
  final SupabaseClient _client;

  @override
  Future<List<ChatMessageRecord>> fetchMessages(
    String crewId, {
    DateTime? before,
    int limit = 40,
  }) async {
    var query = _client
        .from('chat_messages')
        .select('*, chat_reactions(user_id, emoji)')
        .eq('crew_id', crewId);
    if (before != null) {
      query = query.lt('created_at', before.toUtc().toIso8601String());
    }
    final rows = await query
        .order('created_at', ascending: false)
        .order('id', ascending: false)
        .limit(limit);
    return rows.map(ChatMessageRecord.fromJson).toList(growable: false);
  }

  @override
  Future<ChatMessageRecord> sendMessage({
    required String id,
    required String crewId,
    required String body,
  }) async {
    final row = await _client
        .from('chat_messages')
        .insert({'id': id, 'crew_id': crewId, 'body': body})
        .select()
        .single();
    return ChatMessageRecord.fromJson(row);
  }

  @override
  Future<void> deleteMessage(String messageId) => _client.rpc<void>(
    'delete_chat_message',
    params: {'target_message_id': messageId},
  );

  @override
  Future<void> react(String messageId, String? emoji) => _client.rpc<void>(
    'react_to_chat_message',
    params: {'target_message_id': messageId, 'reaction': emoji},
  );

  @override
  Future<void> markRead(String crewId, DateTime at) => _client.rpc<void>(
    'mark_chat_read',
    params: {'target_crew_id': crewId, 'read_at': at.toUtc().toIso8601String()},
  );

  @override
  Future<Map<String, DateTime>> fetchReads(String crewId) async {
    final rows = await _client
        .from('chat_reads')
        .select('user_id,last_read_at')
        .eq('crew_id', crewId);
    return {
      for (final row in rows)
        row['user_id'] as String: DateTime.parse(row['last_read_at'] as String),
    };
  }

  @override
  Future<Map<String, int>> fetchUnreadCounts() async {
    final rows = await _client.rpc<List<dynamic>>('chat_unread_counts');
    return {
      for (final row in rows.cast<Map<String, dynamic>>())
        row['crew_id'] as String: row['unread'] as int,
    };
  }

  @override
  Stream<void> watchActivity(String userId) {
    late final RealtimeChannel channel;
    final controller = StreamController<void>.broadcast(
      onCancel: () => _client.removeChannel(channel),
    );
    // Unfiltered: the table's read policy already narrows the feed to the
    // crews this account is in.
    channel = _client
        .channel('chat-activity:$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'chat_messages',
          callback: (payload) {
            if (payload.newRecord['sender_id'] != userId) controller.add(null);
          },
        )
        .subscribe();
    return controller.stream;
  }

  @override
  ChatConnection connect({required String crewId, required String userId}) =>
      _SupabaseChatConnection(_client, crewId: crewId, userId: userId);
}

class _SupabaseChatConnection implements ChatConnection {
  _SupabaseChatConnection(
    this._client, {
    required String crewId,
    required this.userId,
  }) {
    final filter = PostgresChangeFilter(
      type: PostgresChangeFilterType.eq,
      column: 'crew_id',
      value: crewId,
    );
    _channel = _client
        .channel(
          'chat:$crewId',
          // One presence entry per account, however many phones it has open.
          opts: RealtimeChannelConfig(private: true, key: userId),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'chat_messages',
          filter: filter,
          callback: _message,
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'chat_messages',
          filter: filter,
          callback: _message,
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'chat_reactions',
          filter: filter,
          callback: _reaction,
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'chat_reactions',
          filter: filter,
          callback: _reaction,
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'chat_reads',
          filter: filter,
          callback: (payload) {
            final row = payload.newRecord;
            final at = row['last_read_at'];
            if (row['user_id'] is String && at is String) {
              _add(
                ChatReadChanged(row['user_id'] as String, DateTime.parse(at)),
              );
            }
          },
        )
        .onBroadcast(
          event: 'typing',
          callback: (payload) {
            final body = payload['payload'];
            final map = body is Map ? body : payload;
            final who = map['user_id'];
            if (who is String && who != userId) {
              _add(ChatTypingChanged(who, map['typing'] == true));
            }
          },
        )
        .onPresenceSync((_) => _presence())
        .subscribe((status, error) async {
          if (status != RealtimeSubscribeStatus.subscribed) return;
          _add(const ChatConnected());
          try {
            await _channel.track({'user_id': userId});
          } catch (_) {
            // Presence is a nicety; the chat works without it.
          }
        });
  }

  final SupabaseClient _client;
  final String userId;
  late final RealtimeChannel _channel;
  final _events = StreamController<ChatEvent>.broadcast();

  void _add(ChatEvent event) {
    if (!_events.isClosed) _events.add(event);
  }

  void _message(PostgresChangePayload payload) {
    try {
      _add(ChatMessageChanged(ChatMessageRecord.fromJson(payload.newRecord)));
    } catch (_) {
      // A row the app cannot read is dropped; the next refresh has it.
    }
  }

  void _reaction(PostgresChangePayload payload) {
    try {
      _add(ChatReactionChanged(ChatReactionRecord.fromJson(payload.newRecord)));
    } catch (_) {
      // As with messages: the next refresh has it.
    }
  }

  void _presence() {
    final users = <String>{};
    for (final state in _channel.presenceState()) {
      for (final presence in state.presences) {
        final user = presence.payload['user_id'];
        if (user is String) users.add(user);
      }
    }
    _add(ChatPresenceChanged(users));
  }

  @override
  Stream<ChatEvent> get events => _events.stream;

  @override
  Future<void> sendTyping(bool typing) async {
    await _channel.sendBroadcastMessage(
      event: 'typing',
      payload: {'user_id': userId, 'typing': typing},
    );
  }

  @override
  Future<void> close() async {
    await _events.close();
    await _client.removeChannel(_channel);
  }
}

/// For builds without Supabase: the chat says it cannot connect.
class MissingChatBackend implements ChatBackend {
  const MissingChatBackend();

  Never _missing() => throw StateError('Supabase is not configured.');

  @override
  Future<List<ChatMessageRecord>> fetchMessages(
    String crewId, {
    DateTime? before,
    int limit = 40,
  }) async => _missing();
  @override
  Future<ChatMessageRecord> sendMessage({
    required String id,
    required String crewId,
    required String body,
  }) async => _missing();
  @override
  Future<void> deleteMessage(String messageId) async => _missing();
  @override
  Future<void> react(String messageId, String? emoji) async => _missing();
  @override
  Future<void> markRead(String crewId, DateTime at) async => _missing();
  @override
  Future<Map<String, DateTime>> fetchReads(String crewId) async => _missing();
  @override
  Future<Map<String, int>> fetchUnreadCounts() async => const {};
  @override
  Stream<void> watchActivity(String userId) => const Stream.empty();
  @override
  ChatConnection connect({required String crewId, required String userId}) =>
      _missing();
}
