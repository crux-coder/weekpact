import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'chat_backend.dart';

enum ChatDelivery { sending, sent, failed }

/// A message as the page shows it.
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.senderId,
    required this.createdAt,
    this.text,
    this.delivery = ChatDelivery.sent,
    this.deleted = false,
    this.reactions = const {},
  });

  final String id;
  final String senderId;
  final DateTime createdAt;

  /// The words. Null once the message is deleted.
  final String? text;
  final ChatDelivery delivery;
  final bool deleted;

  /// Each reacting member's emoji, by user id. Empty once deleted.
  final Map<String, String> reactions;

  ChatMessage copyWith({
    String? text,
    ChatDelivery? delivery,
    DateTime? createdAt,
    bool? deleted,
    Map<String, String>? reactions,
  }) => ChatMessage(
    id: id,
    senderId: senderId,
    createdAt: createdAt ?? this.createdAt,
    text: deleted == true ? null : text ?? this.text,
    delivery: delivery ?? this.delivery,
    deleted: deleted ?? this.deleted,
    reactions: deleted == true ? const {} : reactions ?? this.reactions,
  );
}

enum ChatStatus { loading, ready, failed }

/// The longest message, in characters: what the server's column allows.
const chatMessageMaxLength = 2000;

/// One crew's chat on this device: its messages, who is typing and who has
/// read what. The page reads this and nothing else.
class ChatSession extends ChangeNotifier {
  ChatSession({
    required this.backend,
    required this.crewId,
    required this.userId,
    this.pageSize = 40,
    this.typingTimeout = const Duration(seconds: 6),
    this.typingIdle = const Duration(seconds: 4),
  });

  final ChatBackend backend;
  final String crewId;
  final String userId;
  final int pageSize;

  /// How long somebody else counts as typing after their last signal.
  final Duration typingTimeout;

  /// How long after the last keystroke this device says it stopped.
  final Duration typingIdle;

  ChatStatus _status = ChatStatus.loading;
  ChatStatus get status => _status;

  /// Oldest first.
  List<ChatMessage> get messages => List.unmodifiable(_messages);
  final _messages = <ChatMessage>[];

  bool _hasMore = true;
  bool get hasMore => _hasMore;
  bool _loadingMore = false;
  bool get loadingMore => _loadingMore;

  Set<String> get typing => Set.unmodifiable(_typing.keys);
  final _typing = <String, Timer>{};

  Set<String> get online => Set.unmodifiable(_online);
  Set<String> _online = {};

  Map<String, DateTime> get reads => Map.unmodifiable(_reads);
  final _reads = <String, DateTime>{};

  ChatConnection? _connection;
  StreamSubscription<ChatEvent>? _subscription;
  Timer? _typingIdleTimer;
  DateTime? _typingSentAt;
  bool _disposed = false;
  DateTime? _readSent;

  Future<void> open() async {
    _status = ChatStatus.loading;
    _notify();
    try {
      _connection = backend.connect(crewId: crewId, userId: userId);
      _subscription = _connection!.events.listen(_onEvent);

      final page = await backend.fetchMessages(crewId, limit: pageSize);
      final reads = await backend.fetchReads(crewId);
      if (_disposed) return;
      _hasMore = page.length >= pageSize;
      _reads
        ..clear()
        ..addAll(reads);
      _merge(page);
      _status = ChatStatus.ready;
      _notify();
    } catch (error) {
      debugPrint('Chat failed to open: $error');
      if (_disposed) return;
      _status = ChatStatus.failed;
      _notify();
    }
  }

  Future<void> retry() async {
    await _teardownConnection();
    await open();
  }

  /// Reads further back. Does nothing once the start has been reached.
  Future<void> loadMore() async {
    if (!_hasMore || _loadingMore || _messages.isEmpty) return;
    _loadingMore = true;
    _notify();
    try {
      final oldest = _messages
          .where((m) => m.delivery == ChatDelivery.sent)
          .map((m) => m.createdAt)
          .fold<DateTime?>(null, (a, b) => a == null || b.isBefore(a) ? b : a);
      final page = await backend.fetchMessages(
        crewId,
        before: oldest,
        limit: pageSize,
      );
      if (_disposed) return;
      _hasMore = page.length >= pageSize;
      _merge(page);
    } catch (_) {
      // Scrolling up again tries again.
    } finally {
      _loadingMore = false;
      _notify();
    }
  }

  /// Sends [text]. Returns false when there is nothing to send or it is too
  /// long; a failed network write stays in the list marked failed instead.
  Future<bool> send(String text) async {
    final words = text.trim();
    if (words.isEmpty || words.runes.length > chatMessageMaxLength) {
      return false;
    }
    final id = _newId();
    _messages.add(
      ChatMessage(
        id: id,
        senderId: userId,
        createdAt: DateTime.now(),
        text: words,
        delivery: ChatDelivery.sending,
      ),
    );
    _notify();
    unawaited(_stopTyping());
    await _deliver(id, words);
    return true;
  }

  Future<void> resend(String messageId) async {
    final index = _messages.indexWhere((m) => m.id == messageId);
    if (index < 0) return;
    final message = _messages[index];
    if (message.delivery != ChatDelivery.failed || message.text == null) return;
    _messages[index] = message.copyWith(delivery: ChatDelivery.sending);
    _notify();
    await _deliver(messageId, message.text!);
  }

  /// Drops a message that never left the device.
  void discard(String messageId) {
    _messages.removeWhere(
      (m) => m.id == messageId && m.delivery == ChatDelivery.failed,
    );
    _notify();
  }

  Future<void> _deliver(String id, String text) async {
    try {
      final saved = await backend.sendMessage(
        id: id,
        crewId: crewId,
        body: text,
      );
      _replace(
        id,
        (m) => m.copyWith(
          delivery: ChatDelivery.sent,
          createdAt: saved.createdAt.toLocal(),
        ),
      );
      _sort();
      unawaited(markRead());
    } catch (error) {
      debugPrint('Chat message failed to send: $error');
      // The insert may have landed before the answer was lost; the realtime
      // echo or the next refresh settles it either way.
      _replace(id, (m) => m.copyWith(delivery: ChatDelivery.failed));
    }
    _notify();
  }

  /// Unsends one of this account's own messages, for everyone.
  Future<void> delete(String messageId) async {
    final index = _messages.indexWhere((m) => m.id == messageId);
    if (index < 0 || _messages[index].senderId != userId) return;
    final before = _messages[index];
    _messages[index] = before.copyWith(deleted: true);
    _notify();
    try {
      await backend.deleteMessage(messageId);
    } catch (_) {
      final now = _messages.indexWhere((m) => m.id == messageId);
      if (now >= 0) _messages[now] = before;
      _notify();
      rethrow;
    }
  }

  /// Reacts to a message with [emoji], or takes the reaction back when it is
  /// the one already given.
  Future<void> react(String messageId, String emoji) async {
    final index = _messages.indexWhere((m) => m.id == messageId);
    if (index < 0) return;
    final before = _messages[index];
    if (before.deleted || before.delivery != ChatDelivery.sent) return;
    final next = before.reactions[userId] == emoji ? null : emoji;
    _setReaction(messageId, userId, next);
    _notify();
    try {
      await backend.react(messageId, next);
    } catch (_) {
      _setReaction(messageId, userId, before.reactions[userId]);
      _notify();
      rethrow;
    }
  }

  void _setReaction(String messageId, String who, String? emoji) =>
      _replace(messageId, (m) {
        if (m.deleted) return m;
        final reactions = {...m.reactions};
        if (emoji == null) {
          reactions.remove(who);
        } else {
          reactions[who] = emoji;
        }
        return m.copyWith(reactions: reactions);
      });

  /// Tells the crew this device is typing. Throttled, and followed by a stop
  /// once the keyboard has been quiet for [typingIdle].
  void typed() {
    final connection = _connection;
    if (connection == null) return;
    final now = DateTime.now();
    if (_typingSentAt == null ||
        now.difference(_typingSentAt!) > const Duration(seconds: 3)) {
      _typingSentAt = now;
      unawaited(connection.sendTyping(true).catchError((Object _) {}));
    }
    _typingIdleTimer?.cancel();
    _typingIdleTimer = Timer(typingIdle, () => unawaited(_stopTyping()));
  }

  Future<void> _stopTyping() async {
    _typingIdleTimer?.cancel();
    _typingIdleTimer = null;
    if (_typingSentAt == null) return;
    _typingSentAt = null;
    await _connection?.sendTyping(false).catchError((Object _) {});
  }

  /// Records that everything up to the newest message has been read.
  Future<void> markRead() async {
    final newest = _messages
        .where((m) => m.delivery == ChatDelivery.sent)
        .map((m) => m.createdAt)
        .fold<DateTime?>(null, (a, b) => a == null || b.isAfter(a) ? b : a);
    if (newest == null) return;
    if (_readSent != null && !newest.isAfter(_readSent!)) return;
    _readSent = newest;
    try {
      await backend.markRead(crewId, newest);
      _reads[userId] = newest;
    } catch (_) {
      _readSent = null;
    }
  }

  /// The crewmates, other than this account, who have read [message].
  Set<String> readBy(ChatMessage message) => {
    for (final entry in _reads.entries)
      if (entry.key != userId &&
          entry.key != message.senderId &&
          !entry.value.isBefore(message.createdAt))
        entry.key,
  };

  void _onEvent(ChatEvent event) {
    switch (event) {
      case ChatConnected():
        _notify();
        unawaited(_catchUp());
      case ChatMessageChanged(:final message):
        _typingStopped(message.senderId);
        _merge([message]);
        _notify();
      case ChatReactionChanged(:final reaction):
        if (reaction.crewId != crewId) return;
        _setReaction(reaction.messageId, reaction.userId, reaction.emoji);
        _notify();
      case ChatReadChanged(:final userId, :final lastReadAt):
        final known = _reads[userId];
        if (known == null || lastReadAt.isAfter(known)) {
          _reads[userId] = lastReadAt;
          _notify();
        }
      case ChatTypingChanged(:final userId, :final typing):
        if (typing) {
          _typing[userId]?.cancel();
          _typing[userId] = Timer(typingTimeout, () => _typingStopped(userId));
          _notify();
        } else {
          _typingStopped(userId);
        }
      case ChatPresenceChanged(:final userIds):
        _online = userIds;
        _notify();
    }
  }

  void _typingStopped(String who) {
    final timer = _typing.remove(who);
    if (timer == null) return;
    timer.cancel();
    _notify();
  }

  /// After a (re)connect: anything that arrived while the connection was down.
  Future<void> _catchUp() async {
    if (_status != ChatStatus.ready) return;
    try {
      final page = await backend.fetchMessages(crewId, limit: pageSize);
      final reads = await backend.fetchReads(crewId);
      if (_disposed) return;
      _reads.addAll(reads);
      _merge(page);
      _notify();
    } catch (_) {
      // The next reconnect or open tries again.
    }
  }

  void _merge(List<ChatMessageRecord> rows) {
    for (final row in rows) {
      if (row.crewId != crewId) continue;
      final index = _messages.indexWhere((m) => m.id == row.id);
      final message = ChatMessage(
        id: row.id,
        senderId: row.senderId,
        createdAt: row.createdAt.toLocal(),
        text: row.deleted ? null : row.body,
        deleted: row.deleted,
        reactions: row.deleted
            ? const {}
            : row.reactions ??
                  (index >= 0 ? _messages[index].reactions : const {}),
      );
      if (index >= 0) {
        _messages[index] = message;
      } else {
        _messages.add(message);
      }
    }
    _sort();
  }

  void _replace(String id, ChatMessage Function(ChatMessage) update) {
    final index = _messages.indexWhere((m) => m.id == id);
    if (index >= 0) _messages[index] = update(_messages[index]);
  }

  void _sort() {
    // Unsent messages stay at the bottom, where they were typed.
    _messages.sort((a, b) {
      final aPending = a.delivery != ChatDelivery.sent;
      final bPending = b.delivery != ChatDelivery.sent;
      if (aPending != bPending) return aPending ? 1 : -1;
      final byTime = a.createdAt.compareTo(b.createdAt);
      return byTime != 0 ? byTime : a.id.compareTo(b.id);
    });
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> _teardownConnection() async {
    await _subscription?.cancel();
    _subscription = null;
    final connection = _connection;
    _connection = null;
    await connection?.close();
  }

  @override
  void dispose() {
    _disposed = true;
    for (final timer in _typing.values) {
      timer.cancel();
    }
    _typing.clear();
    final connection = _connection;
    if (_typingSentAt != null && connection != null) {
      unawaited(connection.sendTyping(false).catchError((Object _) {}));
    }
    _typingIdleTimer?.cancel();
    unawaited(_teardownConnection());
    super.dispose();
  }
}

final _random = Random.secure();

/// A random (version 4) UUID, made here so a message has its id before the
/// server has seen it.
String _newId() {
  final b = List<int>.generate(16, (_) => _random.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  final hex = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}
