import '../widgets/avatar_shape.dart';

import 'package:hugeicons/styles/stroke_rounded.dart';

import '../widgets/app_icon.dart';

import 'package:flutter/material.dart';

import '../theme/weekpact_theme.dart';
import '../widgets/app_components.dart';
import '../widgets/page_frame.dart';
import 'crew_backend.dart';
import '../subscriptions/pro_upgrade.dart';

class CrewInvitesPane extends StatefulWidget {
  const CrewInvitesPane({
    super.key,
    required this.backend,
    required this.onAccepted,
    this.showEmptyState = true,
  });
  final bool showEmptyState;
  final CrewBackend backend;
  final Future<void> Function(String crewId) onAccepted;

  @override
  State<CrewInvitesPane> createState() => CrewInvitesPaneState();
}

class CrewInvitesPaneState extends State<CrewInvitesPane> {
  List<ReceivedCrewInvite> _invites = [];
  ReceivedCrewInvite? _selected;
  bool _loading = true;
  bool _responding = false;
  bool _accepting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> refresh() async {
    if (_loading || _responding) return;
    await _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final invites = await widget.backend.fetchReceivedInvites();
      if (!mounted) return;
      setState(() {
        _invites = invites;
        final selectedId = _selected?.id;
        _selected = null;
        for (final invite in invites) {
          if (invite.id == selectedId) _selected = invite;
        }
      });
    } catch (error) {
      if (mounted) setState(() => _error = _inviteError(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _openPreview(ReceivedCrewInvite invite) {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _selected = invite;
      _error = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Scrollable.maybeOf(context)?.position.jumpTo(0);
    });
  }

  Future<void> _respond(bool accept) async {
    final invite = _selected;
    if (_responding || _loading || invite == null) return;
    setState(() {
      _responding = true;
      _accepting = accept;
      _error = null;
    });
    try {
      await widget.backend.respondToInvite(inviteId: invite.id, accept: accept);
      if (accept) {
        await widget.onAccepted(invite.crewId);
      } else if (mounted) {
        setState(() {
          _invites = _invites.where((item) => item.id != invite.id).toList();
          _selected = null;
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Invitation declined.')));
      }
    } catch (error) {
      if (!mounted) return;
      // Joining a second crew is a Pro feature, so the refusal is an offer
      // rather than an error. Upgrading accepts the invitation straight away.
      if (isCrewLimitError(error)) {
        if (await showCrewLimitUpgrade(
              context,
              reason: CrewLimitReason.joining,
            ) &&
            mounted) {
          setState(() => _responding = false);
          await _respond(accept);
          return;
        }
      } else {
        setState(() => _error = _inviteError(error));
      }
    } finally {
      if (mounted) setState(() => _responding = false);
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 18, 20, 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_loading) ...[
          Semantics(
            label: 'Loading invitations',
            child: const SkeletonBar(height: 24),
          ),
          const SizedBox(height: 18),
          const SkeletonBar(height: 70),
          const SizedBox(height: 14),
          const SkeletonBar(height: 70),
        ] else if (_selected != null)
          ..._preview(_selected!)
        else
          ..._inbox(),
        if (_error != null) ...[
          const SizedBox(height: 18),
          Text(
            _error!,
            style: TextStyle(
              color: context.errorInk,
              fontWeight: FontWeight.w500,
            ),
          ),
          TextButton(
            onPressed: _responding ? null : refresh,
            child: const Text('RETRY'),
          ),
        ],
      ],
    ),
  );

  List<Widget> _inbox() => [
    if (_invites.isNotEmpty) ...[
      const Text(
        'RECEIVED',
        style: TextStyle(
          fontFamily: WeekPactType.secondary,
          fontFamilyFallback: WeekPactType.secondaryFallback,
          fontSize: 10,
          letterSpacing: 2,
          fontWeight: FontWeight.w500,
        ),
      ),
      const SizedBox(height: 12),
    ],
    if (_invites.isEmpty && _error == null && widget.showEmptyState) ...[
      const SizedBox(height: 12),
      AppIcon(
        icon: HugeIconsStrokeRounded.mail01,
        size: 32,
        color: context.muted,
      ),
      const SizedBox(height: 12),
      const Text(
        'No invites yet',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w500),
      ),
      const SizedBox(height: 12),
    ],
    for (final invite in _invites) ...[
      Material(
        color: WeekPactColors.stone,
        shape: const ContinuousRectangleBorder(
          borderRadius: BorderRadius.all(
            Radius.circular(WeekPactMetrics.panelCurve),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _openPreview(invite),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        invite.name,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${invite.members.length} ${invite.members.length == 1 ? 'member' : 'members'} · ${invite.pacts.length} ${invite.pacts.length == 1 ? 'pact' : 'pacts'}',
                        style: const TextStyle(
                          fontFamily: WeekPactType.secondary,
                          fontFamilyFallback: WeekPactType.secondaryFallback,
                          fontSize: 13,
                          fontWeight: FontWeight.w400,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'VIEW CREW',
                        style: TextStyle(fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ),
                const AppIcon(icon: HugeIconsStrokeRounded.arrowRight01),
              ],
            ),
          ),
        ),
      ),
      const SizedBox(height: 16),
    ],
  ];

  List<Widget> _preview(ReceivedCrewInvite invite) {
    final expired = !invite.expiresAt.isAfter(DateTime.now());
    return [
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: _responding
              ? null
              : () => setState(() {
                  _selected = null;
                  _error = null;
                }),
          icon: const AppIcon(icon: HugeIconsStrokeRounded.arrowLeft02),
          label: const Text('ALL INVITES'),
        ),
      ),
      const SizedBox(height: 10),
      Text(
        invite.name,
        style: TextStyle(
          color: context.ink,
          fontSize: 30,
          fontWeight: FontWeight.w600,
        ),
      ),
      const SizedBox(height: 8),
      Text(
        'Week starts Monday · ${invite.timezone}',
        style: TextStyle(
          color: context.muted,
          fontFamily: WeekPactType.secondary,
          fontFamilyFallback: WeekPactType.secondaryFallback,
          fontWeight: FontWeight.w400,
          fontSize: 13,
          height: 1.5,
        ),
      ),
      const SizedBox(height: 24),
      const Text(
        'MEMBERS',
        style: TextStyle(
          fontFamily: WeekPactType.secondary,
          fontFamilyFallback: WeekPactType.secondaryFallback,
          fontSize: 10,
          fontWeight: FontWeight.w500,
          letterSpacing: 2,
        ),
      ),
      const SizedBox(height: 10),
      for (final member in invite.members)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              FlatAvatar(
                backgroundColor: WeekPactColors.coolGrey,
                foregroundColor: context.ink,
                child: Text(
                  member.email.isEmpty
                      ? '?'
                      : member.email.substring(0, 1).toUpperCase(),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  member.email,
                  style: const TextStyle(
                    fontFamily: WeekPactType.secondary,
                    fontFamilyFallback: WeekPactType.secondaryFallback,
                    fontSize: 14,
                    height: 1.4,
                  ),
                ),
              ),
              if (member.isOwner) ...[
                const SizedBox(width: 8),
                const Text(
                  'OWNER',
                  style: TextStyle(
                    fontFamily: WeekPactType.secondary,
                    fontFamilyFallback: WeekPactType.secondaryFallback,
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ],
          ),
        ),
      const SizedBox(height: 20),
      const Text(
        'PACTS',
        style: TextStyle(
          fontFamily: WeekPactType.secondary,
          fontFamilyFallback: WeekPactType.secondaryFallback,
          fontSize: 10,
          fontWeight: FontWeight.w500,
          letterSpacing: 2,
        ),
      ),
      const SizedBox(height: 10),
      if (invite.pacts.isEmpty)
        const Text('This crew hasn’t added any pacts yet.'),
      for (final pact in invite.pacts)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                pact.title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                pact.schedule,
                style: TextStyle(
                  color: context.muted,
                  fontFamily: WeekPactType.secondary,
                  fontFamilyFallback: WeekPactType.secondaryFallback,
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      const SizedBox(height: 22),
      Text(
        'Invite expires ${MaterialLocalizations.of(context).formatMediumDate(invite.expiresAt.toLocal())}.',
        style: TextStyle(
          color: context.muted,
          fontFamily: WeekPactType.secondary,
          fontFamilyFallback: WeekPactType.secondaryFallback,
          fontSize: 12,
          height: 1.5,
        ),
      ),
      if (expired) ...[
        const SizedBox(height: 14),
        Text(
          'This invitation has expired. Ask the owner for a new one.',
          style: TextStyle(
            color: context.errorInk,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
      const SizedBox(height: 20),
      AppButton(
        label: 'ACCEPT INVITE',
        icon: HugeIconsStrokeRounded.arrowRight01,

        isLoading: _responding && _accepting,
        onPressed: _responding || expired ? null : () => _respond(true),
      ),
      const SizedBox(height: 16),
      TextButton(
        onPressed: _responding || expired ? null : () => _respond(false),
        child: _responding && !_accepting
            ? const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Text('DECLINE INVITE'),
      ),
    ];
  }
}

String _inviteError(Object error) {
  final message = error.toString();
  if (message.contains('Confirm your email')) {
    return 'Confirm your email before viewing invitations.';
  }
  if (message.contains('no longer available')) {
    return 'This invitation has expired, was revoked, or was already answered. Refresh your invites.';
  }

  return 'Could not update your invitations. Please try again.';
}
