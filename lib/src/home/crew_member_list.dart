import '../theme/weekpact_theme.dart';
import '../widgets/avatar_shape.dart';

import 'dart:async';

import 'package:flutter/material.dart';

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
    this.onDark = false,
    this.head = 0,
  });
  final List<WeekMember> members;
  final bool done;
  final String userId;
  final HomeBackend? backend;
  final String? crewId;

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
                padding: const EdgeInsets.symmetric(
                  horizontal: CrewMemberList.inset,
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
          AvatarClip(
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
          ),
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
