import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:hugeicons/styles/stroke_rounded.dart';

import '../crew/crew_page_layout.dart';
import '../crew/crew_switcher.dart';
import '../home/home_backend.dart';
import '../notifications/notifications_page.dart';
import '../pacts/pacts_backend.dart';
import '../theme/weekpact_theme.dart';
import '../widgets/app_components.dart';
import '../widgets/squircle_button_border.dart';
import '../widgets/app_icon.dart';
import '../widgets/app_sheet.dart';
import '../widgets/avatar_shape.dart';
import '../widgets/page_frame.dart';
import 'chat_backend.dart';
import 'chat_session.dart';

/// The Chat tab: the crew Home is showing, talking.
///
/// It follows the same crew as Home — switching here switches there — and
/// opens its connection the first time the tab is shown rather than on
/// launch, so an app opened only to check in never holds a socket for it.
class ChatPage extends StatefulWidget {
  const ChatPage({
    super.key,
    required this.backend,
    required this.pactsBackend,
    required this.homeBackend,
    required this.userId,
    required this.active,
    this.selectedCrewId,
    this.onCrewSelected,
    this.onRead,
  });

  final ChatBackend backend;

  /// Where the list of crews comes from, for the switcher.
  final PactsBackend pactsBackend;

  /// Where names and faces come from: the crew's week already carries them.
  final HomeBackend homeBackend;
  final String userId;

  /// Whether the tab is the one showing.
  final bool active;
  final String? selectedCrewId;
  final ValueChanged<String>? onCrewSelected;

  /// Told after this device marks the chat read, so the unread dot can go.
  final VoidCallback? onRead;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> with WidgetsBindingObserver {
  List<PactCrew>? _crews;
  bool _crewsFailed = false;
  ChatSession? _session;
  Map<String, WeekMember> _members = const {};
  int _request = 0;

  final _composer = TextEditingController();
  final _focus = FocusNode();
  final _scroll = ScrollController();
  bool _showJump = false;
  bool _resumed = true;

  PactCrew? get _crew {
    final crews = _crews;
    if (crews == null || crews.isEmpty) return null;
    return crews.where((c) => c.id == widget.selectedCrewId).firstOrNull ??
        crews.first;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scroll.addListener(_onScroll);
    _composer.addListener(() => setState(() {}));
    if (widget.active) _loadCrews();
  }

  @override
  void didUpdateWidget(covariant ChatPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) {
      if (_crews == null || _crewsFailed) {
        _loadCrews();
      } else {
        _openSelected();
        _markRead();
      }
    } else if (widget.selectedCrewId != oldWidget.selectedCrewId &&
        _crews != null) {
      _openSelected();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _resumed = state == AppLifecycleState.resumed;
    if (_resumed && widget.active) {
      unawaited(_session?.retryIfFailed());
      _markRead();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _session?.removeListener(_onSession);
    _session?.dispose();
    _composer.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _loadCrews() async {
    final request = ++_request;
    setState(() => _crewsFailed = false);
    try {
      final crews = await widget.pactsBackend.fetchCrews();
      if (!mounted || request != _request) return;
      setState(() => _crews = crews);
      _openSelected();
    } catch (_) {
      if (mounted && request == _request) setState(() => _crewsFailed = true);
    }
  }

  void _openSelected() {
    final crew = _crew;
    if (crew == null) {
      _closeSession();
      return;
    }
    if (crew.id != widget.selectedCrewId) {
      // After the frame: this can run while the parent is mid-build.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _crew?.id == crew.id) {
          widget.onCrewSelected?.call(crew.id);
        }
      });
    }
    if (_session?.crewId == crew.id) return;
    _closeSession();
    final session = ChatSession(
      backend: widget.backend,
      crewId: crew.id,
      userId: widget.userId,
    )..addListener(_onSession);
    setState(() {
      _session = session;
      _members = const {};
      _showJump = false;
    });
    _composer.clear();
    unawaited(session.open());
    unawaited(_loadMembers(crew.id));
  }

  void _closeSession() {
    final session = _session;
    if (session == null) return;
    session.removeListener(_onSession);
    session.dispose();
    setState(() => _session = null);
  }

  Future<void> _loadMembers(String crewId) async {
    try {
      final week = await widget.homeBackend.fetchWeek(crewId);
      if (!mounted || _session?.crewId != crewId) return;
      setState(() => _members = {for (final m in week.members) m.id: m});
    } catch (_) {
      // Messages still read without names; they say "Crew member".
    }
  }

  int _seenCount = 0;

  void _onSession() {
    if (!mounted) return;
    setState(() {});
    final count = _session?.messages.length ?? 0;
    if (count != _seenCount) {
      _seenCount = count;
      _markRead();
      // A page that lands without filling the list, or while the reader is
      // still at its far end, reads on rather than waiting for a scroll.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _loadMoreIfNearStart();
      });
    }
  }

  void _markRead() {
    final session = _session;
    if (session == null ||
        !widget.active ||
        !_resumed ||
        session.status != ChatStatus.ready) {
      return;
    }
    unawaited(session.markRead().then((_) => widget.onRead?.call()));
  }

  void _onScroll() {
    final position = _scroll.position;
    final jump = position.pixels > 320;
    if (jump != _showJump) setState(() => _showJump = jump);
    _loadMoreIfNearStart();
  }

  void _loadMoreIfNearStart() {
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    // The list runs bottom-up, so its far end is the oldest message.
    if (position.pixels > position.maxScrollExtent - 400) {
      unawaited(_session?.loadMore());
    }
  }

  void _jumpToNewest() {
    if (!_scroll.hasClients) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _scroll.jumpTo(0);
      return;
    }
    _scroll.animateTo(
      0,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _send() async {
    final session = _session;
    final text = _composer.text;
    if (session == null || session.status != ChatStatus.ready) return;
    if (text.trim().isEmpty) return;
    final sent = session.send(text);
    _composer.clear();
    unawaited(HapticFeedback.lightImpact().catchError((Object _) {}));
    _jumpToNewest();
    if (!await sent && mounted) {
      // Only too long gets here: empty never leaves the button.
      _composer.text = text;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('That message is too long to send.')),
      );
    }
  }

  String _name(String userId) {
    if (userId == widget.userId) return 'You';
    final name = _members[userId]?.displayName.trim() ?? '';
    return name.isEmpty ? 'Crew member' : name.split(RegExp(r'\s+')).first;
  }

  /// Holding a message: what can be done with it, then everybody who has
  /// seen it, with the reaction each gave beside their name.
  Future<void> _messageActions(ChatMessage message) async {
    final session = _session;
    if (session == null || message.deleted) return;
    final mine = message.senderId == widget.userId;
    final sent = message.delivery == ChatDelivery.sent;
    // Reacting counts as having seen it, whatever the read marker says.
    final people = sent
        ? _peopleBy(message.reactions, session.readBy(message))
        : const <String>[];
    unawaited(HapticFeedback.selectionClick().catchError((Object _) {}));
    final action = await showAppSheet<_MessageAction>(
      context: context,
      builder: (context) => AppSheet(
        builder: (context) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 4),
            Row(
              children: [
                for (final (i, button) in [
                  if (message.delivery == ChatDelivery.failed) ...[
                    _SheetButton(
                      icon: HugeIconsStrokeRounded.sent,
                      label: 'Try again',
                      onTap: () => Navigator.pop(context, _MessageAction.retry),
                    ),
                    _SheetButton(
                      icon: HugeIconsStrokeRounded.delete02,
                      label: 'Discard',
                      destructive: true,
                      onTap: () =>
                          Navigator.pop(context, _MessageAction.discard),
                    ),
                  ],
                  if (message.text != null)
                    _SheetButton(
                      icon: HugeIconsStrokeRounded.copy01,
                      label: 'Copy',
                      onTap: () => Navigator.pop(context, _MessageAction.copy),
                    ),
                  if (mine && sent)
                    _SheetButton(
                      icon: HugeIconsStrokeRounded.delete02,
                      label: 'Delete',
                      destructive: true,
                      onTap: () =>
                          Navigator.pop(context, _MessageAction.delete),
                    ),
                ].indexed) ...[
                  if (i > 0) const SizedBox(width: 8),
                  Expanded(child: button),
                ],
              ],
            ),
            if (sent) ...[
              const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  people.isEmpty ? 'Nobody has seen this yet.' : 'Seen by',
                  style: TextStyle(
                    color: context.muted,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Column(
                key: const ValueKey('chat-message-people'),
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final who in people)
                    _PersonRow(
                      member: _members[who],
                      name: _name(who),
                      reaction: message.reactions[who],
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case _MessageAction.copy:
        await Clipboard.setData(ClipboardData(text: message.text ?? ''));
        if (!mounted) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Copied.')));
      case _MessageAction.retry:
        await session.resend(message.id);
      case _MessageAction.discard:
        session.discard(message.id);
      case _MessageAction.delete:
        try {
          await session.delete(message.id);
        } catch (_) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Could not delete. Please try again.'),
            ),
          );
        }
    }
  }

  Future<void> _react(ChatMessage message, String emoji) async {
    final session = _session;
    if (session == null) return;
    unawaited(HapticFeedback.lightImpact().catchError((Object _) {}));
    try {
      await session.react(message.id, emoji);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not react. Please try again.')),
      );
    }
  }

  /// A tap on a crewmate's message's reaction: a like, or taking back
  /// whatever this account gave.
  Future<void> _toggleReaction(ChatMessage message) =>
      _react(message, message.reactions[widget.userId] ?? chatReactions.first);

  /// Holding the reaction: every reaction, over the button, to pick from.
  Future<void> _pickReaction(ChatMessage message, Rect anchor) async {
    unawaited(HapticFeedback.selectionClick().catchError((Object _) {}));
    final mine = message.reactions[widget.userId];
    final emoji = await showGeneralDialog<String>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close reactions',
      barrierColor: Colors.black26,
      transitionDuration: const Duration(milliseconds: 140),
      pageBuilder: (context, _, _) =>
          _ReactionPopup(anchor: anchor, selected: mine),
      transitionBuilder: (context, animation, _, child) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween(
            begin: .9,
            end: 1.0,
          ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOut)),
          child: child,
        ),
      ),
    );
    if (!mounted || emoji == null || emoji == mine) return;
    await _react(message, emoji);
  }

  /// Who reacted, in the picker's order, then who has only seen it.
  List<String> _peopleBy(Map<String, String> reactions, Set<String> seen) {
    int byName(String a, String b) => _name(a).compareTo(_name(b));
    final reacted = reactions.keys.toList()
      ..sort((a, b) {
        final byEmoji = chatReactions
            .indexOf(reactions[a]!)
            .compareTo(chatReactions.indexOf(reactions[b]!));
        return byEmoji != 0 ? byEmoji : byName(a, b);
      });
    final onlySeen = seen.where((id) => !reactions.containsKey(id)).toList()
      ..sort(byName);
    return [...reacted, ...onlySeen];
  }

  @override
  Widget build(BuildContext context) {
    final crews = _crews;
    final crew = _crew;
    final session = _session;
    return SafeArea(
      bottom: false,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: CrewPageHeading(
                  // The same bell Home hangs in its corner, so the crew's
                  // notices are a tap away from the chat as well.
                  actions: [
                    NotificationsBell(
                      key: const ValueKey('chat-notifications'),
                      backend: widget.homeBackend,
                      viewerId: widget.userId,
                      active: widget.active,
                    ),
                  ],
                  switcher: crews == null || crews.isEmpty
                      ? null
                      : CrewSwitcher(
                          key: const ValueKey('chat-crew-switcher'),
                          crews: crews,
                          selectedId: crew?.id,
                          onSelected: widget.onCrewSelected,
                        ),
                ),
              ),
              if (session != null) _StatusLine(session: session, name: _name),
              Expanded(child: _body(context, crews, session)),
              if (session != null)
                _Composer(
                  controller: _composer,
                  focusNode: _focus,
                  enabled: session.status == ChatStatus.ready,
                  onChanged: (text) {
                    if (text.trim().isNotEmpty) session.typed();
                  },
                  onSend: _send,
                ),
              // Above the navigation floating over the page's foot.
              SizedBox(height: MediaQuery.paddingOf(context).bottom),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body(
    BuildContext context,
    List<PactCrew>? crews,
    ChatSession? session,
  ) {
    if (_crewsFailed) {
      return _Notice(
        title: 'Could not load your crews.',
        action: TextButton(
          onPressed: _loadCrews,
          child: const Text('TRY AGAIN'),
        ),
      );
    }
    if (crews == null) return const _ChatSkeleton();
    if (crews.isEmpty) {
      return const _Notice(
        icon: HugeIconsStrokeRounded.bubbleChat,
        title: 'Chat starts with a crew.',
        message: 'Start or join a crew, and talk to them here.',
      );
    }
    if (session == null || session.status == ChatStatus.loading) {
      return const _ChatSkeleton();
    }
    if (session.status == ChatStatus.failed) {
      return _Notice(
        title: 'Could not open the chat.',
        message: 'Check your connection and try again.',
        action: TextButton(
          key: const ValueKey('chat-retry'),
          onPressed: session.retry,
          child: const Text('TRY AGAIN'),
        ),
      );
    }
    final messages = session.messages;
    final typing = session.typing;
    if (messages.isEmpty && typing.isEmpty) {
      return _Notice(
        key: const ValueKey('chat-empty'),
        icon: HugeIconsStrokeRounded.bubbleChat,
        title: 'Say hi to ${_crew?.name ?? 'your crew'}.',
        message: 'Only your crew can see what is said here.',
      );
    }
    final items = _items(messages, session);
    return Stack(
      children: [
        ListView.builder(
          key: const ValueKey('chat-messages'),
          controller: _scroll,
          reverse: true,
          // Springs back past either end, even with only a few messages.
          physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          itemCount: items.length + (typing.isEmpty ? 0 : 1) + 1,
          itemBuilder: (context, index) {
            if (typing.isNotEmpty) {
              if (index == 0) {
                return _TypingRow(
                  key: const ValueKey('chat-typing'),
                  members: [for (final id in typing) _members[id]],
                  names: [for (final id in typing) _name(id)],
                );
              }
              index -= 1;
            }
            if (index == items.length) {
              return _ListEnd(
                loading: session.loadingMore,
                start: !session.hasMore,
              );
            }
            return items[index];
          },
        ),
        Positioned(
          right: 16,
          bottom: 12,
          child: IgnorePointer(
            ignoring: !_showJump,
            child: AnimatedOpacity(
              opacity: _showJump ? 1 : 0,
              duration: const Duration(milliseconds: 160),
              child: _RoundButton(
                key: const ValueKey('chat-jump'),
                tooltip: 'Newest messages',
                icon: HugeIconsStrokeRounded.arrowDown01,
                onPressed: _jumpToNewest,
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// The list's rows, newest first, as the reversed list draws them: each
  /// message with its neighbours deciding whether it opens or closes a run,
  /// and a day line wherever the date turns over.
  List<Widget> _items(List<ChatMessage> messages, ChatSession session) {
    final items = <Widget>[];
    // Seen is said once, under the newest of your own messages somebody has
    // read — every bubble saying it would be a column of the same word.
    String? seenOn;
    Set<String> seenBy = const {};
    for (final message in messages.reversed) {
      if (message.senderId != widget.userId ||
          message.delivery != ChatDelivery.sent) {
        continue;
      }
      final readers = session.readBy(message);
      if (readers.isNotEmpty) {
        seenOn = message.id;
        seenBy = readers;
      }
      break;
    }
    for (var i = messages.length - 1; i >= 0; i--) {
      final message = messages[i];
      final older = i > 0 ? messages[i - 1] : null;
      final newer = i < messages.length - 1 ? messages[i + 1] : null;
      final opensRun = !_sameRun(older, message);
      final reactable =
          message.senderId != widget.userId &&
          message.delivery == ChatDelivery.sent &&
          !message.deleted;
      final closesRun = !_sameRun(message, newer);
      items.add(
        _MessageRow(
          key: ValueKey('chat-message-${message.id}'),
          message: message,
          mine: message.senderId == widget.userId,
          member: _members[message.senderId],
          senderName: _name(message.senderId),
          opensRun: opensRun,
          closesRun: closesRun,
          seenBy: message.id == seenOn
              ? [for (final id in seenBy) _name(id)]
              : const [],
          onLongPress: () => _messageActions(message),
          viewerId: widget.userId,
          onDoubleTap: reactable ? () => _toggleReaction(message) : null,
          onReact: reactable ? () => _toggleReaction(message) : null,
          onPickReaction: reactable
              ? (anchor) => _pickReaction(message, anchor)
              : null,
          onShowReactions: () => _messageActions(message),
          onRetry: message.delivery == ChatDelivery.failed
              ? () => _messageActions(message)
              : null,
        ),
      );
      if (older == null || !_sameDay(older.createdAt, message.createdAt)) {
        items.add(_DayLine(day: message.createdAt));
      }
    }
    return items;
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// Whether [b] follows [a] in one run of bubbles: same person, same day,
  /// however long between them. A day line always starts a new run, so the
  /// name and face are never left on the other side of it.
  static bool _sameRun(ChatMessage? a, ChatMessage? b) =>
      a != null &&
      b != null &&
      a.senderId == b.senderId &&
      _sameDay(a.createdAt, b.createdAt);
}

extension on ChatSession {
  Future<void> retryIfFailed() async {
    if (status == ChatStatus.failed) await retry();
  }
}

enum _MessageAction { copy, delete, retry, discard }

/// [reactions] (user id to emoji) as each emoji's reactors, in the order the
/// picker offers them.
Map<String, List<String>> _groupReactions(Map<String, String> reactions) => {
  for (final emoji in chatReactions)
    if (reactions.containsValue(emoji))
      emoji: [
        for (final entry in reactions.entries)
          if (entry.value == emoji) entry.key,
      ],
};

/// How each reaction is drawn, and read aloud. The emoji is only what the
/// server stores; the app draws its own glyph for it.
const _reactionIcons = <String, List<List<dynamic>>>{
  '👍': HugeIconsStrokeRounded.thumbsUp,
  '\u2764\uFE0F': HugeIconsStrokeRounded.favourite,
  '😂': HugeIconsStrokeRounded.laughing,
  '🔥': HugeIconsStrokeRounded.fire,
  '👏': HugeIconsStrokeRounded.handsClapping,
  '😮': HugeIconsStrokeRounded.surprise,
};

/// The colour a reaction you gave is drawn in, on the dark canvas.
const _reactionColors = <String, Color>{
  '👍': WeekPactColors.sky,
  '\u2764\uFE0F': WeekPactColors.salmon,
  '😂': WeekPactColors.gold,
  '🔥': WeekPactColors.lantern,
  '👏': WeekPactColors.brass,
  '😮': WeekPactColors.lavender,
};
const _reactionNames = <String, String>{
  '👍': 'Like',
  '\u2764\uFE0F': 'Love',
  '😂': 'Haha',
  '🔥': 'Fire',
  '👏': 'Clap',
  '😮': 'Wow',
};

/// The reaction glyphs filled in: Hugeicons' free set is outlines only, so
/// each outline's main shape is filled here. The faces' outlines are open,
/// so they get a disc of their own to fill.
final _filledReactionIcons = <String, List<List<dynamic>>>{
  '👍': _filledShapes(HugeIconsStrokeRounded.thumbsUp, {0, 1}),
  '\u2764\uFE0F': _filledShapes(HugeIconsStrokeRounded.favourite, {0}),
  '😂': [
    _faceDisc,
    ..._filledShapes(HugeIconsStrokeRounded.laughing, {3, 4}),
  ],
  '🔥': _filledShapes(HugeIconsStrokeRounded.fire, {0}),
  '👏': _filledShapes(HugeIconsStrokeRounded.handsClapping, {0}),
  '😮': _filledShapes(HugeIconsStrokeRounded.surprise, {0}),
};

const _faceDisc = [
  'circle',
  {'key': 'disc', 'cx': '12', 'cy': '12', 'r': '10', 'fill': 'currentColor'},
];

List<List<dynamic>> _filledShapes(List<List<dynamic>> icon, Set<int> shapes) =>
    [
      for (final (i, element) in icon.indexed)
        shapes.contains(i)
            ? [
                element[0],
                {...element[1] as Map<String, dynamic>, 'fill': 'currentColor'},
              ]
            : element,
    ];

/// A reaction's glyph: filled in its own colour, with the details in a
/// darker shade of it, unless [color] asks for a plain outline.
class _ReactionIcon extends StatelessWidget {
  const _ReactionIcon({required this.emoji, required this.size, this.color});
  final String emoji;
  final double size;

  /// The outline's colour, for a reaction not given.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final outline = color;
    final fill = _reactionColors[emoji] ?? context.ink;
    return Semantics(
      label: _reactionNames[emoji],
      child: HugeIcon(
        icon: outline == null
            ? _filledReactionIcons[emoji] ?? HugeIconsStrokeRounded.smile
            : _reactionIcons[emoji] ?? HugeIconsStrokeRounded.smile,
        size: size,
        color: outline ?? Color.lerp(fill, WeekPactColors.black, .6),
        secondaryColor: outline == null ? fill : null,
        strokeWidth: outline == null ? 1.6 : 1.8,
      ),
    );
  }
}

/// The row of reactions at the top of a message's sheet.
class _ReactionPicker extends StatelessWidget {
  const _ReactionPicker({required this.selected, required this.onPick});
  final String? selected;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
    children: [
      for (final emoji in chatReactions)
        Semantics(
          button: true,
          selected: emoji == selected,
          child: InkResponse(
            key: ValueKey('chat-react-$emoji'),
            onTap: () => onPick(emoji),
            radius: 26,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: 48,
              height: 48,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: emoji == selected
                    ? WeekPactColors.black.withValues(alpha: .1)
                    : Colors.transparent,
              ),
              child: _ReactionIcon(emoji: emoji, size: 26),
            ),
          ),
        ),
    ],
  );
}

/// The reactions beside a bubble, in the bubble's own colour. On a
/// crewmate's message the main squircle is yours: a muted like until you
/// react, then your reaction, filled. A smaller one next to it, outward,
/// holds everybody else's, each with how many gave it.
class _Reactions extends StatelessWidget {
  const _Reactions({
    required this.messageId,
    required this.reactions,
    required this.viewerId,
    required this.fill,
    required this.onShowReactions,
    this.onReact,
    this.onPickReaction,
  });

  final String messageId;
  final Map<String, String> reactions;
  final String viewerId;
  final Color fill;
  final VoidCallback onShowReactions;

  /// Null on your own message: there is no reaction of yours to give.
  final VoidCallback? onReact;

  /// Given where your reaction is on screen, so a picker can open over it.
  final ValueChanged<Rect>? onPickReaction;

  @override
  Widget build(BuildContext context) {
    final mine = reactions[viewerId];
    final others = _groupReactions({
      for (final entry in reactions.entries)
        if (entry.key != viewerId) entry.key: entry.value,
    });
    final edge = Color.lerp(fill, WeekPactColors.black, .22)!;
    final react = onReact;
    final pick = onPickReaction;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (react != null && pick != null)
          Semantics(
            button: true,
            label: mine == null ? 'React' : 'Reacted ${_reactionNames[mine]}',
            child: _SpringPress(
              key: ValueKey('chat-reaction-button-$messageId'),
              onTap: react,
              onLongPress: pick,
              child: _Lipped(
                fill: fill,
                edge: edge,
                child: SizedBox.square(
                  dimension: 30,
                  child: Center(
                    child: _ReactionIcon(
                      emoji: mine ?? chatReactions.first,
                      size: mine == null ? 16 : 19,
                      // Faint until you react, so a given reaction stands out.
                      color: mine == null
                          ? WeekPactColors.mutedLight.withValues(alpha: .35)
                          : null,
                    ),
                  ),
                ),
              ),
            ),
          ),
        if (others.isNotEmpty) ...[
          if (react != null) const SizedBox(width: 3),
          Semantics(
            button: true,
            label: 'See reactions',
            child: _SpringPress(
              key: ValueKey('chat-reaction-others-$messageId'),
              onTap: onShowReactions,
              onLongPress: (_) => onShowReactions(),
              child: _Lipped(
                fill: fill,
                edge: edge,
                child: Container(
                  height: 22,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final (i, entry) in others.entries.indexed) ...[
                        if (i > 0) const SizedBox(width: 5),
                        _ReactionIcon(emoji: entry.key, size: 13),
                        const SizedBox(width: 2),
                        Text(
                          '${entry.value.length}',
                          style: const TextStyle(
                            color: WeekPactColors.black,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// A squircle in [fill] with the same lip along its foot as the bubbles.
class _Lipped extends StatelessWidget {
  const _Lipped({required this.fill, required this.edge, required this.child});
  final Color fill;
  final Color edge;
  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: ShapeDecoration(
      color: edge,
      shape: const SquircleButtonBorder(),
    ),
    child: Padding(
      padding: const EdgeInsets.only(bottom: WeekPactMetrics.controlDepth),
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: fill,
          shape: const SquircleButtonBorder(),
        ),
        child: child,
      ),
    ),
  );
}

/// Squeezes [child] while a finger is on it and springs it back on release.
class _SpringPress extends StatefulWidget {
  const _SpringPress({
    super.key,
    required this.child,
    required this.onTap,
    required this.onLongPress,
  });

  final Widget child;
  final VoidCallback onTap;

  /// Given where the child is on screen.
  final ValueChanged<Rect> onLongPress;

  @override
  State<_SpringPress> createState() => _SpringPressState();
}

class _SpringPressState extends State<_SpringPress>
    with SingleTickerProviderStateMixin {
  late final _scale = AnimationController.unbounded(vsync: this, value: 1);

  static const _pressed = .82;
  static final _spring = SpringDescription.withDampingRatio(
    mass: 1,
    stiffness: 420,
    ratio: .45,
  );

  bool get _still => MediaQuery.disableAnimationsOf(context);

  void _down() {
    if (_still) return;
    _scale.animateTo(
      _pressed,
      duration: const Duration(milliseconds: 90),
      curve: Curves.easeOut,
    );
  }

  void _release() {
    if (_still) return;
    _scale.animateWith(
      SpringSimulation(_spring, _scale.value, 1, _scale.velocity),
    );
  }

  @override
  void dispose() {
    _scale.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTapDown: (_) => _down(),
    onTapUp: (_) => _release(),
    onTapCancel: _release,
    onTap: widget.onTap,
    onLongPress: () {
      final box = context.findRenderObject()! as RenderBox;
      widget.onLongPress(box.localToGlobal(Offset.zero) & box.size);
    },
    child: ScaleTransition(scale: _scale, child: widget.child),
  );
}

/// Every reaction in a strip over [anchor], or under it when there is no
/// room above. Closes with the one picked.
class _ReactionPopup extends StatelessWidget {
  const _ReactionPopup({required this.anchor, required this.selected});
  final Rect anchor;
  final String? selected;

  static const _height = 64.0;

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final padding = MediaQuery.paddingOf(context);
    final width = math.min(304.0, screen.width - 16);
    final left = (anchor.center.dx - width / 2).clamp(
      8.0,
      screen.width - width - 8,
    );
    final above = anchor.top - _height - 8;
    final top = above >= padding.top + 8 ? above : anchor.bottom + 8;
    return Stack(
      children: [
        Positioned(
          left: left,
          top: top,
          width: width,
          height: _height,
          child: Material(
            type: MaterialType.transparency,
            child: DecoratedBox(
              key: const ValueKey('chat-reaction-popup'),
              decoration: const ShapeDecoration(
                color: WeekPactColors.cream,
                shape: SquircleButtonBorder(),
                shadows: [
                  BoxShadow(
                    color: Color(0x33000000),
                    blurRadius: 16,
                    offset: Offset(0, 6),
                  ),
                ],
              ),
              child: _ReactionPicker(
                selected: selected,
                onPick: (emoji) => Navigator.pop(context, emoji),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The line under the crew's name: who is in the chat now. Nothing while
/// nobody else is.
class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.session, required this.name});
  final ChatSession session;
  final String Function(String) name;

  @override
  Widget build(BuildContext context) {
    final others = session.online.where((id) => id != session.userId).toList();
    final online = switch (others.length) {
      0 => null,
      1 => '${name(others.first)} is here',
      2 => '${name(others[0])} and ${name(others[1])} are here',
      _ => '${others.length} crewmates are here',
    };
    if (online == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Flexible(
            child: Text(
              online,
              key: const ValueKey('chat-status'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: context.muted, fontSize: 13),
            ),
          ),
          const SizedBox(width: 6),
          const _Dot(color: WeekPactColors.success, size: 7),
        ],
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color, this.size = 8});
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}

class _DayLine extends StatelessWidget {
  const _DayLine({required this.day});
  final DateTime day;

  static const _weekdays = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  String _label() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final that = DateTime(day.year, day.month, day.day);
    final days = today.difference(that).inDays;
    if (days == 0) return 'Today';
    if (days == 1) return 'Yesterday';
    if (days < 7) return _weekdays[that.weekday - 1];
    final date = '${that.day} ${_months[that.month - 1]}';
    return that.year == now.year ? date : '$date ${that.year}';
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Center(
      child: Text(
        _label().toUpperCase(),
        style: TextStyle(
          color: context.muted,
          fontSize: 11,
          fontWeight: FontWeight.w500,
          letterSpacing: .6,
        ),
      ),
    ),
  );
}

class _ChatAvatar extends StatelessWidget {
  const _ChatAvatar({required this.member, this.size = 28});
  final WeekMember? member;
  final double size;

  @override
  Widget build(BuildContext context) {
    final initials = Text(
      member?.initials ?? '?',
      style: TextStyle(
        color: context.ink,
        fontSize: size * .4,
        fontWeight: FontWeight.w600,
      ),
    );
    final url = member?.avatarUrl;
    return FlatAvatar(
      radius: size / 2,
      backgroundColor: context.ink.withValues(alpha: .14),
      child: url == null || url.trim().isEmpty
          ? initials
          : Image.network(
              url,
              width: size,
              height: size,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              errorBuilder: (_, _, _) => initials,
            ),
    );
  }
}

class _MessageRow extends StatelessWidget {
  const _MessageRow({
    super.key,
    required this.message,
    required this.mine,
    required this.member,
    required this.senderName,
    required this.opensRun,
    required this.closesRun,
    required this.seenBy,
    required this.onLongPress,
    required this.viewerId,
    required this.onShowReactions,
    this.onReact,
    this.onPickReaction,
    this.onDoubleTap,
    this.onRetry,
  });

  final ChatMessage message;
  final bool mine;
  final WeekMember? member;
  final String senderName;
  final bool opensRun;
  final bool closesRun;
  final List<String> seenBy;
  final VoidCallback onLongPress;
  final String viewerId;
  final VoidCallback onShowReactions;

  /// Null on your own messages, which are reacted to rather than on.
  final VoidCallback? onReact;
  final ValueChanged<Rect>? onPickReaction;
  final VoidCallback? onDoubleTap;
  final VoidCallback? onRetry;

  static const _avatar = 28.0;
  static const _round = Radius.circular(18);
  static const _tight = Radius.circular(6);

  /// A crewmate's message always offers your reaction; your own shows the
  /// others' once somebody has reacted.
  bool get _hasReaction =>
      !message.deleted &&
      message.delivery == ChatDelivery.sent &&
      (onReact != null || message.reactions.isNotEmpty);

  Color get _fill => mine ? WeekPactColors.coolGrey : WeekPactColors.cream;

  BorderRadius get _corners => mine
      ? BorderRadius.only(
          topLeft: _round,
          bottomLeft: _round,
          topRight: opensRun ? _round : _tight,
          bottomRight: closesRun ? _round : _tight,
        )
      : BorderRadius.only(
          topRight: _round,
          bottomRight: _round,
          topLeft: opensRun ? _round : _tight,
          bottomLeft: closesRun ? _round : _tight,
        );

  String _time(BuildContext context) =>
      MaterialLocalizations.of(context).formatTimeOfDay(
        TimeOfDay.fromDateTime(message.createdAt),
        alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
      );

  String _seen() => switch (seenBy.length) {
    0 => '',
    1 => 'Seen by ${seenBy.first}',
    2 => 'Seen by ${seenBy[0]} and ${seenBy[1]}',
    _ => 'Seen by ${seenBy.length}',
  };

  static final _metaStyle = TextStyle(
    color: WeekPactColors.black.withValues(alpha: .55),
    fontSize: 11,
    height: 1.3,
  );
  static const _tick = 12.0;

  /// The time, and for your own messages whether it got there.
  Widget _meta(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(_time(context), style: _metaStyle),
      if (mine) ...[
        const SizedBox(width: 4),
        _Dot(color: _metaStyle.color!, size: 2.5),
        const SizedBox(width: 4),
        AppIcon(
          icon: message.delivery == ChatDelivery.sending
              ? HugeIconsStrokeRounded.clock01
              : message.delivery == ChatDelivery.failed
              ? HugeIconsStrokeRounded.alertCircle
              : seenBy.isEmpty
              ? HugeIconsStrokeRounded.tick02
              : HugeIconsStrokeRounded.tickDouble02,
          size: _tick,
          color: _metaStyle.color,
        ),
      ],
    ],
  );

  Widget _bubble(BuildContext context) {
    final fill = _fill;
    final edge = Color.lerp(fill, WeekPactColors.black, .22)!;
    final faded = message.deleted;
    final Widget content;
    if (message.deleted) {
      content = _Quiet(
        icon: HugeIconsStrokeRounded.delete02,
        text: 'Message deleted',
      );
    } else {
      // The time, and for your own whether it got there, on a line of
      // their own under the text, at the bubble's right edge.
      content = IntrinsicWidth(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              message.text!,
              style: const TextStyle(
                color: WeekPactColors.black,
                fontSize: 16,
                height: 1.3,
              ),
            ),
            const SizedBox(height: 2),
            Align(alignment: Alignment.centerRight, child: _meta(context)),
          ],
        ),
      );
    }
    return Opacity(
      opacity: message.delivery == ChatDelivery.sending ? .7 : 1,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: faded ? fill.withValues(alpha: .55) : fill,
          borderRadius: _corners,
          border: Border(
            bottom: BorderSide(
              color: faded ? Colors.transparent : edge,
              width: WeekPactMetrics.controlDepth,
            ),
          ),
        ),
        child: content,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final maxBubble = math.min(width * .74, 460.0);
    final footer = _footer(context);
    final Widget body = GestureDetector(
      onLongPress: onLongPress,
      onDoubleTap: onDoubleTap,
      onTap: onRetry,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxBubble),
        child: _bubble(context),
      ),
    );
    // The reaction floats beside the bubble's outer side, halfway down.
    final bubble = !_hasReaction
        ? body
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (mine) ...[_reactions(), const SizedBox(width: 6)],
              Flexible(child: body),
              if (!mine) ...[const SizedBox(width: 6), _reactions()],
            ],
          );
    return Semantics(
      label: '$senderName, ${_time(context)}',
      child: Padding(
        padding: EdgeInsets.only(top: opensRun ? 10 : 2),
        child: Column(
          crossAxisAlignment: mine
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            if (mine)
              bubble
            else
              // The face sits with the name at the top of a run; the rest of
              // the run lines up under the first bubble.
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: _avatar,
                    child: opensRun
                        ? _ChatAvatar(member: member, size: _avatar)
                        : null,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (opensRun)
                          Padding(
                            padding: const EdgeInsets.only(left: 2, bottom: 3),
                            child: Text(
                              senderName,
                              style: TextStyle(
                                color: context.muted,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        bubble,
                      ],
                    ),
                  ),
                ],
              ),
            if (footer != null)
              Padding(
                padding: EdgeInsets.only(
                  top: 4,
                  left: mine ? 0 : _avatar + 12,
                  right: mine ? 4 : 0,
                ),
                child: footer,
              ),
          ],
        ),
      ),
    );
  }

  Widget _reactions() => _Reactions(
    messageId: message.id,
    reactions: message.reactions,
    viewerId: viewerId,
    fill: _fill,
    onReact: onReact,
    onPickReaction: onPickReaction,
    onShowReactions: onShowReactions,
  );

  /// Under a bubble: that it did not send, or who has seen it.
  Widget? _footer(BuildContext context) {
    if (message.delivery == ChatDelivery.failed) {
      return GestureDetector(
        onTap: onRetry,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppIcon(
              icon: HugeIconsStrokeRounded.alertCircle,
              size: 13,
              color: context.errorInk,
            ),
            Text(
              'Not sent · Tap to retry',
              key: const ValueKey('chat-not-sent'),
              style: TextStyle(color: context.errorInk, fontSize: 12),
            ),
          ],
        ),
      );
    }
    if (seenBy.isEmpty) return null;
    return Text(
      _seen(),
      key: const ValueKey('chat-seen'),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(color: context.muted, fontSize: 11),
    );
  }
}

/// A bubble with nothing in it to read: the message was deleted.
class _Quiet extends StatelessWidget {
  const _Quiet({required this.icon, required this.text});
  final List<List<dynamic>> icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      AppIcon(icon: icon, size: 14, color: WeekPactColors.mutedLight),
      Flexible(
        child: Text(
          text,
          style: const TextStyle(
            color: WeekPactColors.mutedLight,
            fontSize: 14,
            fontStyle: FontStyle.italic,
          ),
        ),
      ),
    ],
  );
}

/// Who is typing, kept small: their faces, and a mini pill of dots beside
/// them. Several typers share the one row as overlapping faces.
class _TypingRow extends StatelessWidget {
  const _TypingRow({super.key, required this.members, required this.names});
  final List<WeekMember?> members;
  final List<String> names;

  String get _label => switch (names.length) {
    1 => '${names.first} is typing',
    2 => '${names[0]} and ${names[1]} are typing',
    _ => '${names.length} people are typing',
  };

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    label: _label,
    child: ExcludeSemantics(
      child: Padding(
        // The first face sits under the avatars of the messages above.
        padding: const EdgeInsets.only(top: 10, left: 5),
        child: Row(
          children: [
            _TypingFaces(members: members),
            const SizedBox(width: 6),
            Container(
              key: const ValueKey('chat-typing-bubble'),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: context.ink.withValues(alpha: .14),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const _TypingDots(),
            ),
          ],
        ),
      ),
    ),
  );
}

/// The typers' faces, overlapping: up to three, or two and a count of the
/// rest.
class _TypingFaces extends StatelessWidget {
  const _TypingFaces({required this.members});
  final List<WeekMember?> members;

  static const _size = 18.0;
  static const _ring = 1.5;
  static const _overlap = 6.0;

  @override
  Widget build(BuildContext context) {
    final ring = Theme.of(context).scaffoldBackgroundColor;
    final shown = members.length > 3 ? members.take(2).toList() : members;
    final faces = <Widget>[
      for (final member in shown) _ChatAvatar(member: member, size: _size),
      if (members.length > 3)
        FlatAvatar(
          radius: _size / 2,
          backgroundColor: context.ink.withValues(alpha: .14),
          child: Text(
            '+${members.length - 2}',
            style: TextStyle(
              color: context.ink,
              fontSize: 8,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
    ];
    const face = _size + _ring * 2;
    return SizedBox(
      width: face + (faces.length - 1) * (face - _overlap),
      height: face,
      child: Stack(
        children: [
          for (var i = 0; i < faces.length; i++)
            Positioned(
              left: i * (face - _overlap),
              // A ring of page colour keeps overlapping faces apart.
              child: AvatarClip(
                child: ColoredBox(
                  color: ring,
                  child: Padding(
                    padding: const EdgeInsets.all(_ring),
                    child: faces[i],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _TypingDots extends StatefulWidget {
  const _TypingDots();

  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots>
    with SingleTickerProviderStateMixin {
  late final _wave = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _wave.stop();
      _wave.value = .5;
    } else if (!_wave.isAnimating) {
      _wave.repeat();
    }
  }

  @override
  void dispose() {
    _wave.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _wave,
    builder: (context, _) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < 3; i++) ...[
          if (i > 0) const SizedBox(width: 3),
          Transform.translate(
            offset: Offset(
              0,
              -2.5 *
                  math.max(
                    0.0,
                    math.sin((_wave.value - i * .18) * 2 * math.pi),
                  ),
            ),
            child: _Dot(color: context.muted, size: 5),
          ),
        ],
      ],
    ),
  );
}

class _ListEnd extends StatelessWidget {
  const _ListEnd({required this.loading, required this.start});
  final bool loading;
  final bool start;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(
          child: SizedBox.square(
            dimension: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    if (!start) return const SizedBox(height: 16);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
      child: Text(
        'This is the start of your crew’s chat.',
        textAlign: TextAlign.center,
        style: TextStyle(color: context.muted, fontSize: 13),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.focusNode,
    required this.enabled,
    required this.onChanged,
    required this.onSend,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool enabled;
  final ValueChanged<String> onChanged;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final canSend = enabled && controller.text.trim().isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: AppSurface(
              raised: false,
              // The squircle the app's controls are cut to, as the send
              // button beside it is, rather than a pill.
              shape: WeekPactMetrics.buttonShape,
              builder: (context) => CaretAtEndOnFocus(
                controller: controller,
                child: TextField(
                  key: const ValueKey('chat-input'),
                  controller: controller,
                  focusNode: focusNode,
                  enabled: enabled,
                  minLines: 1,
                  maxLines: 5,
                  maxLength: 2000,
                  textCapitalization: TextCapitalization.sentences,
                  keyboardType: TextInputType.multiline,
                  onChanged: onChanged,
                  // Touch taps elsewhere close the keyboard; the send button
                  // is in the field's tap region so sending keeps it open.
                  onTapOutside: (_) => focusNode.unfocus(),
                  style: TextStyle(color: context.ink, fontSize: 16),
                  decoration: InputDecoration(
                    hintText: 'Message your crew',
                    hintStyle: TextStyle(color: context.muted),
                    counterText: '',
                    filled: false,
                    isDense: true,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 13,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          TextFieldTapRegion(
            child: _RoundButton(
              key: const ValueKey('chat-send'),
              tooltip: 'Send',
              icon: HugeIconsStrokeRounded.sent,
              onPressed: canSend ? onSend : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final List<List<dynamic>> icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final fill = enabled ? WeekPactColors.coolGrey : WeekPactColors.graphite;
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        enabled: enabled,
        label: tooltip,
        child: Material(
          color: fill,
          shape: SquircleButtonBorder(
            side: BorderSide(
              color: Color.lerp(fill, WeekPactColors.black, .2)!,
            ),
          ),
          child: InkWell(
            customBorder: const SquircleButtonBorder(),
            onTap: onPressed,
            child: SizedBox.square(
              // The height of a one-line field beside it, so the two
              // squircles stand level.
              dimension: 50,
              child: AppIcon(
                icon: icon,
                size: 20,
                strokeWidth: 2,
                color: enabled
                    ? WeekPactColors.black
                    : WeekPactColors.darkMuted,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One of a message's actions, side by side with the others at the top of
/// its sheet.
class _SheetButton extends StatelessWidget {
  const _SheetButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
  });
  final List<List<dynamic>> icon;
  final String label;
  final VoidCallback onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final color = destructive ? context.errorInk : context.ink;
    return Material(
      color: WeekPactColors.neutralInset,
      shape: const SquircleButtonBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppIcon(icon: icon, color: color, size: 20),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Somebody in a message's sheet: who they are, and the reaction they gave,
/// or a quiet tick for having seen it.
class _PersonRow extends StatelessWidget {
  const _PersonRow({required this.member, required this.name, this.reaction});
  final WeekMember? member;
  final String name;
  final String? reaction;

  @override
  Widget build(BuildContext context) {
    final reaction = this.reaction;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      child: Row(
        children: [
          _ChatAvatar(member: member, size: 32),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: context.ink,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          if (reaction != null)
            _ReactionIcon(emoji: reaction, size: 22)
          else
            AppIcon(
              icon: HugeIconsStrokeRounded.tickDouble02,
              size: 16,
              color: context.muted,
            ),
        ],
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({
    super.key,
    required this.title,
    this.message,
    this.icon,
    this.action,
  });
  final String title;
  final String? message;
  final List<List<dynamic>>? icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            AppIcon(icon: icon!, size: 36, color: context.muted),
            const SizedBox(height: 10),
          ],
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: context.ink,
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (message != null) ...[
            const SizedBox(height: 8),
            Text(
              message!,
              textAlign: TextAlign.center,
              style: TextStyle(color: context.muted, fontSize: 15),
            ),
          ],
          if (action != null) ...[const SizedBox(height: 8), action!],
        ],
      ),
    ),
  );
}

class _ChatSkeleton extends StatelessWidget {
  const _ChatSkeleton();

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Loading chat',
    liveRegion: true,
    child: ExcludeSemantics(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final (mine, width) in const [
                (false, 180.0),
                (false, 120.0),
                (true, 200.0),
                (false, 150.0),
                (true, 110.0),
              ])
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Align(
                    alignment: mine
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    child: SkeletonBar(width: width, height: 38, radius: 18),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}
