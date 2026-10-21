import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hugeicons/styles/stroke_rounded.dart';

import '../crew/crew_page_layout.dart';
import '../crew/crew_switcher.dart';
import '../home/home_backend.dart';
import '../pacts/pacts_backend.dart';
import '../theme/weekpact_theme.dart';
import '../widgets/app_components.dart';
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

  Future<void> _messageActions(ChatMessage message) async {
    final session = _session;
    if (session == null || message.deleted) return;
    final mine = message.senderId == widget.userId;
    unawaited(HapticFeedback.selectionClick().catchError((Object _) {}));
    final action = await showAppSheet<_MessageAction>(
      context: context,
      builder: (context) => AppSheet(
        builder: (context) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (message.delivery == ChatDelivery.failed) ...[
              _SheetAction(
                icon: HugeIconsStrokeRounded.sent,
                label: 'Try again',
                onTap: () => Navigator.pop(context, _MessageAction.retry),
              ),
              _SheetAction(
                icon: HugeIconsStrokeRounded.delete02,
                label: 'Discard',
                destructive: true,
                onTap: () => Navigator.pop(context, _MessageAction.discard),
              ),
            ],
            if (message.text != null)
              _SheetAction(
                icon: HugeIconsStrokeRounded.copy01,
                label: 'Copy',
                onTap: () => Navigator.pop(context, _MessageAction.copy),
              ),
            if (mine && message.delivery == ChatDelivery.sent)
              _SheetAction(
                icon: HugeIconsStrokeRounded.delete02,
                label: 'Delete for everyone',
                destructive: true,
                onTap: () => Navigator.pop(context, _MessageAction.delete),
              ),
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
  /// within a few minutes.
  static bool _sameRun(ChatMessage? a, ChatMessage? b) =>
      a != null &&
      b != null &&
      a.senderId == b.senderId &&
      _sameDay(a.createdAt, b.createdAt) &&
      b.createdAt.difference(a.createdAt).abs() < const Duration(minutes: 5);
}

extension on ChatSession {
  Future<void> retryIfFailed() async {
    if (status == ChatStatus.failed) await retry();
  }
}

enum _MessageAction { copy, delete, retry, discard }

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
  final VoidCallback? onRetry;

  static const _avatar = 28.0;
  static const _round = Radius.circular(18);
  static const _tight = Radius.circular(6);

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

  Widget _bubble(BuildContext context) {
    final fill = mine ? WeekPactColors.coolGrey : WeekPactColors.cream;
    final edge = Color.lerp(fill, WeekPactColors.black, .22)!;
    final faded = message.deleted;
    final Widget content;
    if (message.deleted) {
      content = _Quiet(
        icon: HugeIconsStrokeRounded.delete02,
        text: 'Message deleted',
      );
    } else {
      content = Text(
        message.text!,
        style: const TextStyle(
          color: WeekPactColors.black,
          fontSize: 16,
          height: 1.3,
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
    final bubble = GestureDetector(
      onLongPress: onLongPress,
      onTap: onRetry,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxBubble),
        child: _bubble(context),
      ),
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
            if (!mine && opensRun)
              Padding(
                padding: const EdgeInsets.only(left: _avatar + 18, bottom: 3),
                child: Text(
                  senderName,
                  style: TextStyle(
                    color: context.muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            if (mine)
              bubble
            else
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  SizedBox(
                    width: _avatar,
                    child: closesRun
                        ? _ChatAvatar(member: member, size: _avatar)
                        : null,
                  ),
                  const SizedBox(width: 8),
                  Flexible(child: bubble),
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

  /// Under the last bubble of a run: when, and for your own, whether it got
  /// there.
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
    if (!closesRun && seenBy.isEmpty) return null;
    final style = TextStyle(color: context.muted, fontSize: 11);
    final seen = _seen();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(_time(context), style: style),
        if (mine) ...[
          const SizedBox(width: 2),
          AppIcon(
            icon: message.delivery == ChatDelivery.sending
                ? HugeIconsStrokeRounded.clock01
                : seenBy.isEmpty
                ? HugeIconsStrokeRounded.tick02
                : HugeIconsStrokeRounded.tickDouble02,
            size: 12,
            color: context.muted,
          ),
        ],
        if (seen.isNotEmpty)
          Flexible(
            child: Text(
              ' · $seen',
              key: const ValueKey('chat-seen'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style,
            ),
          ),
      ],
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
        padding: const EdgeInsets.only(top: 10),
        child: Row(
          children: [
            _ChatAvatar(member: members.first, size: _MessageRow._avatar),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
              decoration: const BoxDecoration(
                color: WeekPactColors.cream,
                borderRadius: BorderRadius.all(_MessageRow._round),
              ),
              child: const _TypingDots(),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                _label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: context.muted, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    ),
  );
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
          if (i > 0) const SizedBox(width: 4),
          Transform.translate(
            offset: Offset(
              0,
              -3 *
                  math.max(
                    0.0,
                    math.sin((_wave.value - i * .18) * 2 * math.pi),
                  ),
            ),
            child: const _Dot(color: WeekPactColors.mutedLight, size: 7),
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
              borderRadius: 22,
              builder: (context) => TextField(
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
          const SizedBox(width: 8),
          _RoundButton(
            key: const ValueKey('chat-send'),
            tooltip: 'Send',
            icon: HugeIconsStrokeRounded.sent,
            onPressed: canSend ? onSend : null,
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
          shape: CircleBorder(
            side: BorderSide(
              color: Color.lerp(fill, WeekPactColors.black, .2)!,
            ),
          ),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onPressed,
            child: SizedBox.square(
              dimension: 46,
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

class _SheetAction extends StatelessWidget {
  const _SheetAction({
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
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(WeekPactMetrics.controlRadius),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
        child: Row(
          children: [
            AppIcon(icon: icon, color: color, size: 20),
            const SizedBox(width: 12),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
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
