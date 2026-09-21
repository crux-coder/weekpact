import '../theme/weekpact_theme.dart';
import '../widgets/avatar_shape.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:hugeicons/styles/stroke_rounded.dart';

import '../crew/crew_switcher.dart' show CrewHeaderSurface;
import '../widgets/app_components.dart';
import 'home_backend.dart';
import 'home_surface.dart';

class CrewMemberList extends StatefulWidget {
  const CrewMemberList({
    super.key,
    required this.members,
    required this.done,
    required this.userId,
    this.backend,
    this.crewId,
    this.checkedIn,
    this.onDark = false,
    this.head = 0,
    this.headLead = 0,
  });
  final List<WeekMember> members;
  final bool done;
  final String userId;
  final HomeBackend? backend;
  final String? crewId;

  /// Who is in today, where the list holds the whole crew rather than one
  /// side of it.
  ///
  /// The panels above Home each show one state and say so in their own title,
  /// so they leave this off and no row carries a mark. A list that mixes the
  /// two — the day's drawer — passes the ids that are in, and every row then
  /// wears what its day is: a tick, or the seat still waiting on it.
  final Set<String>? checkedIn;

  /// True when the list sits on a dark face rather than a pale tile. The
  /// rows then take the dark card's ink and the nudge button inverts: a pale
  /// face on the dark border, since graphite on a dark panel is a shadow.
  final bool onDark;

  /// The rows' margin from the list's own edges, which the hairline over them
  /// takes too so the two line up.
  static const inset = 12.0;

  /// Room over the first face, carrying a hairline at its top.
  ///
  /// A list opening straight out of the thing above it needs a line saying
  /// where one ends and the other begins, and air under that line so the
  /// first face is not pressed against it. Zero where the list is already
  /// inside a titled surface of its own.
  ///
  /// The caller sets it, because the caller is sizing the box: a drawer that
  /// runs exactly as far as its rows have to know this is in them, or it
  /// clips its last name.
  final double head;

  /// The air over the hairline inside [head].
  ///
  /// The caller sets it, because only the caller knows what the thing above
  /// already leaves under its own last line. The line wants the same space on
  /// each side of it, and the slack over it is half that space already.
  final double headLead;

  @override
  State<CrewMemberList> createState() => _CrewMemberListState();
}

class _CrewMemberListState extends State<CrewMemberList>
    with WidgetsBindingObserver {
  Color get _ink => widget.onDark ? WeekPactDarkCard.ink : homeInk;
  Color get _muted =>
      widget.onDark ? WeekPactDarkCard.muted : WeekPactColors.mutedLight;

  Map<String, CrewNudgeState> _states = {};
  final _sending = <String>{};
  final _failed = <String>{};
  bool _loading = false;
  bool _loadFailed = false;
  int _request = 0;
  Timer? _cooldownTimer;
  bool get _canNudge =>
      !widget.done && widget.backend != null && widget.crewId != null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (_canNudge) _loadStates();
  }

  @override
  void didUpdateWidget(covariant CrewMemberList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_canNudge &&
        (widget.crewId != oldWidget.crewId ||
            widget.members.map((m) => m.id).join(',') !=
                oldWidget.members.map((m) => m.id).join(','))) {
      _loadStates();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _canNudge) _loadStates();
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _loadStates() async {
    final request = ++_request;
    setState(() {
      _loading = true;
      _loadFailed = false;
    });
    try {
      final states = await widget.backend!.fetchNudgeStates(widget.crewId!);
      if (!mounted || request != _request) return;
      setState(() {
        _states = states;
        _loading = false;
      });
      _scheduleRefresh();
    } catch (_) {
      if (!mounted || request != _request) return;
      setState(() {
        _loading = false;
        _loadFailed = true;
      });
    }
  }

  void _scheduleRefresh() {
    _cooldownTimer?.cancel();
    final now = DateTime.now();
    final deadlines =
        _states.values
            .map((s) => s.nextAllowedAt)
            .whereType<DateTime>()
            .where((date) => date.isAfter(now))
            .toList()
          ..sort();
    if (deadlines.isNotEmpty) {
      _cooldownTimer = Timer(
        deadlines.first.difference(now) + const Duration(seconds: 1),
        _loadStates,
      );
    }
  }

  Future<void> _send(String recipientId) async {
    if (_sending.contains(recipientId) || _loading) return;
    ++_request; // A stale status read cannot overwrite this send's result.
    setState(() {
      _sending.add(recipientId);
      _failed.remove(recipientId);
    });
    try {
      final result = await widget.backend!.sendNudge(
        crewId: widget.crewId!,
        recipientId: recipientId,
      );
      if (!mounted) return;
      ++_request;
      setState(() {
        _loading = false;
        _states[recipientId] = result;
        _sending.remove(recipientId);
      });
      _scheduleRefresh();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _sending.remove(recipientId);
        _failed.add(recipientId);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.members.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            widget.done
                ? 'No one has checked in today yet.'
                : 'Everyone has checked in today.',
            textAlign: TextAlign.center,
            style: TextStyle(color: _ink, fontSize: 14),
          ),
        ),
      );
    }
    return Column(
      children: [
        if (_loadFailed)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Could not load nudges.',
                    style: TextStyle(color: _ink, fontSize: 12),
                  ),
                ),
                TextButton(onPressed: _loadStates, child: const Text('Retry')),
              ],
            ),
          ),
        if (widget.head > 0)
          SizedBox(
            height: widget.head,
            child: Align(
              alignment: Alignment.topCenter,
              child: Padding(
                // Inset to the rows' own margin, so the line starts where the
                // faces start and stops where the nudge buttons stop. A rule
                // running the full width would cut the drawer in two instead
                // of grouping what is under it.
                padding: EdgeInsets.fromLTRB(
                  CrewMemberList.inset,
                  widget.headLead,
                  CrewMemberList.inset,
                  0,
                ),
                child: Container(
                  key: const ValueKey('crew-member-list-rule'),
                  height: 1,
                  color: _ink.withValues(alpha: .12),
                ),
              ),
            ),
          ),
        Expanded(
          child: ListView.builder(
            key: ValueKey(
              widget.done ? 'checked-members-list' : 'pending-members-list',
            ),
            padding: const EdgeInsets.fromLTRB(
              CrewMemberList.inset,
              0,
              CrewMemberList.inset,
              8,
            ),
            itemCount: widget.members.length,
            itemBuilder: (context, index) =>
                _member(context, widget.members[index]),
          ),
        ),
      ],
    );
  }

  Widget _member(BuildContext context, WeekMember member) {
    final full = member.displayName.trim();
    // A crew is small and on first-name terms, and the row has a nudge button
    // to leave space for. The whole name stays in the tooltip and in what a
    // screen reader reads.
    final name = full.isEmpty
        ? 'Crew member'
        : full.split(RegExp(r'\s+')).first;
    final initials = Center(
      child: Text(
        member.initials,
        style: const TextStyle(
          color: WeekPactColors.black,
          fontFamily: WeekPactType.secondary,
          fontFamilyFallback: WeekPactType.secondaryFallback,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
    final action = member.id == widget.userId
        ? Text('You', style: TextStyle(color: _muted, fontSize: 12))
        : _canNudge
        ? _nudgeButton(context, member)
        : null;
    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Tooltip(
          message: full.isEmpty ? name : full,
          child: Semantics(
            label: full.isEmpty ? name : full,
            excludeSemantics: true,
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: _ink,
                fontFamily: WeekPactType.secondary,
                fontFamilyFallback: WeekPactType.secondaryFallback,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
        if (_failed.contains(member.id))
          Text(
            'Could not send. Try again.',
            style: TextStyle(
              color: widget.onDark
                  ? WeekPactColors.darkError
                  : WeekPactColors.error,
              fontSize: 11,
            ),
          ),
      ],
    );
    return Padding(
      key: ValueKey('crew-check-in-person-${member.id}'),
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        // The name and its action read against the face beside them, so the
        // row centres on the avatar rather than hanging from its top edge.
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _face(context, member, initials),
          const SizedBox(width: 10),
          Expanded(
            child: LayoutBuilder(
              builder: (context, space) {
                // Keep full names readable at large text sizes and on narrow phones.
                if (action != null &&
                    (space.maxWidth < 200 ||
                        MediaQuery.textScalerOf(context).scale(1) > 1.3)) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [details, action],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: details),
                    if (action != null) ...[const SizedBox(width: 8), action],
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// One person's face, with what their day is on it where the list is
  /// holding the whole crew.
  ///
  /// The mark rides the corner of the face rather than taking a column of its
  /// own: the row already spends its width on a name and a nudge, and a state
  /// belongs to the person it is about.
  Widget _face(BuildContext context, WeekMember member, Widget initials) {
    final checkedIn = widget.checkedIn;
    final avatar = AvatarClip(
      child: SizedBox.square(
        dimension: 36,
        child: ColoredBox(
          color: homePaper,
          child: member.avatarUrl == null
              ? initials
              : Image.network(
                  member.avatarUrl!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => initials,
                ),
        ),
      ),
    );
    if (checkedIn == null) return avatar;
    final done = checkedIn.contains(member.id);
    return Stack(
      // The mark sits a little proud of the face, in the row's own padding.
      clipBehavior: Clip.none,
      children: [
        avatar,
        Positioned(
          right: -3,
          bottom: -3,
          child: _CheckMark(done: done, onDark: widget.onDark),
        ),
      ],
    );
  }

  Widget _nudgeButton(BuildContext context, WeekMember member) {
    final state = _states[member.id];
    final busy = _sending.contains(member.id);
    final ready = state?.status == CrewNudgeStatus.ready;
    final nudged =
        state?.status == CrewNudgeStatus.sent ||
        state?.status == CrewNudgeStatus.cooldown;
    final text = busy
        ? 'Sending…'
        : _loading
        ? 'Loading…'
        : _failed.contains(member.id)
        ? 'Try again'
        : nudged
        ? 'Nudged'
        : state?.status == CrewNudgeStatus.checkedIn
        ? 'Checked in'
        : ready
        ? 'Nudge'
        : 'Unavailable';
    final deadline = state?.nextAllowedAt?.toLocal();
    final localizations = MaterialLocalizations.of(context);
    final hint = nudged && deadline != null
        ? 'You can nudge again ${localizations.formatMediumDate(deadline)} at ${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(deadline), alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context))}.'
        : ready
        ? 'Send a little encouragement. One nudge per person every 24 hours.'
        : state?.status == CrewNudgeStatus.checkedIn
        ? 'They have already checked in today.'
        : 'This person cannot receive a nudge right now.';
    // Only a nudge you can actually send is an object. The other states are
    // what the row has to say about that person, so they stay flat words.
    final solid = ready || busy;
    // On a dark face graphite is a shadow, so the button inverts to the pale
    // one. Either way it is the app's raised button: `AppSurface` on
    // `buttonShape`, which mixes its own outline and lifted edge from the
    // face rather than spelling a second pair here.
    final face = widget.onDark ? WeekPactColors.cream : WeekPactColors.graphite;
    final label = widget.onDark ? WeekPactColors.black : homePaper;
    final button = TextButton(
      key: ValueKey('nudge-${member.id}'),
      onPressed: ready && !_loading && !_loadFailed && !busy
          ? () => _send(member.id)
          : null,
      style: TextButton.styleFrom(
        foregroundColor: solid ? label : _muted,
        disabledForegroundColor: solid ? label.withValues(alpha: .7) : _muted,
        backgroundColor: Colors.transparent,
        disabledBackgroundColor: Colors.transparent,
        minimumSize: const Size(64, 32),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        textStyle: const TextStyle(
          fontFamily: WeekPactType.secondary,
          fontFamilyFallback: WeekPactType.secondaryFallback,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
        shape: WeekPactMetrics.buttonShape,
      ),
      child: Text(text),
    );
    return Tooltip(
      message: hint,
      child: Semantics(
        liveRegion: true,
        child: solid
            ? AppSurface(
                fillColor: face,
                resolveTone: false,
                shape: WeekPactMetrics.buttonShape,
                borderRadius: WeekPactMetrics.controlRadius,
                builder: (context) => button,
              )
            : button,
      ),
    );
  }
}

/// What the day is for one person, as a badge on their face: the crew tile's
/// mint tick for a check-in that is in, and the empty seat for one the day is
/// still waiting on.
///
/// It is the same pair the strip's seats and the check-in tiles use, held at
/// badge size — a kept day is mint with a tick, an owed one is bare
/// `pendingCheckIns`. Read together down the column they sort the roster
/// without a word, which is what the drawer has no room for.
class _CheckMark extends StatelessWidget {
  const _CheckMark({required this.done, required this.onDark});
  final bool done;
  final bool onDark;

  /// The badge's own box, inside the ring that knocks it out of the face.
  static const _size = 13.0;

  /// The seat's own colour. The empty one is the crew tile's
  /// `pendingCheckIns` on a pale list, and the dark face's border on a dark
  /// one: a pale grey dot repeated down a dark column reads as louder than
  /// the tick it is supposed to be quieter than.
  Color get _fill => done
      ? WeekPactColors.mintGreen
      : onDark
      ? WeekPactColors.darkBorder
      : WeekPactColors.pendingCheckIns;

  Color get _edge => done
      ? WeekPactColors.mintEdge
      : onDark
      ? Color.lerp(WeekPactColors.darkBorder, WeekPactColors.black, .35)!
      : WeekPactColors.pendingEdge;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: done ? 'Checked in today' : 'Not checked in yet',
    child: Semantics(
      label: done ? 'Checked in today' : 'Not checked in yet',
      child: Container(
        // The list's own face, so the badge reads as an object on the photo
        // rather than a hole punched in it.
        padding: const EdgeInsets.all(1.5),
        decoration: BoxDecoration(
          color: onDark ? CrewHeaderSurface.faceColor(context) : homePaper,
          shape: BoxShape.circle,
        ),
        child: SizedBox.square(
          dimension: _size,
          child: DecoratedBox(
            decoration: ShapeDecoration(
              color: _fill,
              shape: CircleBorder(side: BorderSide(color: _edge)),
            ),
            child: done
                ? const Center(
                    child: HugeIcon(
                      icon: HugeIconsStrokeRounded.tick03,
                      color: WeekPactColors.black,
                      size: 9,
                      strokeWidth: 3,
                    ),
                  )
                : null,
          ),
        ),
      ),
    ),
  );
}
