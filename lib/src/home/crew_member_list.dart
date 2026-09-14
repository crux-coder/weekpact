import 'dart:async';

import 'package:flutter/material.dart';

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
  });
  final List<WeekMember> members;
  final bool done;
  final String userId;
  final HomeBackend? backend;
  final String? crewId;

  @override
  State<CrewMemberList> createState() => _CrewMemberListState();
}

class _CrewMemberListState extends State<CrewMemberList>
    with WidgetsBindingObserver {
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
            style: const TextStyle(color: homeInk, fontSize: 14),
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
                const Expanded(
                  child: Text(
                    'Could not load nudges.',
                    style: TextStyle(color: homeInk, fontSize: 12),
                  ),
                ),
                TextButton(onPressed: _loadStates, child: const Text('Retry')),
              ],
            ),
          ),
        Expanded(
          child: ListView.builder(
            key: ValueKey(
              widget.done ? 'checked-members-list' : 'pending-members-list',
            ),
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            itemCount: widget.members.length,
            itemBuilder: (context, index) =>
                _member(context, widget.members[index]),
          ),
        ),
      ],
    );
  }

  Widget _member(BuildContext context, WeekMember member) {
    final name = member.displayName.trim().isEmpty
        ? 'Crew member'
        : member.displayName.trim();
    final initials = Center(
      child: Text(
        member.initials,
        style: const TextStyle(
          color: homeInk,
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
    final action = member.id == widget.userId
        ? const Text(
            'You',
            style: TextStyle(color: Color(0xFF646B60), fontSize: 12),
          )
        : _canNudge
        ? _nudgeButton(context, member)
        : null;
    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          name,
          style: const TextStyle(
            color: homeInk,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (_failed.contains(member.id))
          const Text(
            'Could not send. Try again.',
            style: TextStyle(color: Color(0xFF8A3831), fontSize: 11),
          ),
      ],
    );
    return Padding(
      key: ValueKey('crew-check-in-person-${member.id}'),
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipOval(
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
    final label = busy
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
    return Tooltip(
      message: hint,
      child: Semantics(
        liveRegion: true,
        child: TextButton(
          key: ValueKey('nudge-${member.id}'),
          onPressed: ready && !_loading && !_loadFailed && !busy
              ? () => _send(member.id)
              : null,
          style: TextButton.styleFrom(
            foregroundColor: const Color(0xFF36552C),
            disabledForegroundColor: const Color(0xFF687361),
            backgroundColor: ready && !busy
                ? const Color(0xFFD0E5BA)
                : Colors.transparent,
            minimumSize: const Size(64, 36),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            textStyle: const TextStyle(
              fontFamily: 'RobotoCondensed',
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
            shape: const StadiumBorder(),
          ),
          child: Text(label),
        ),
      ),
    );
  }
}
