import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:hugeicons/styles/stroke_rounded.dart';

import '../auth/avatar_picker.dart';
import '../home/home_backend.dart';
import '../invites/invite_code_entry.dart';
import '../invites/invite_links.dart';
import '../pacts/pacts_backend.dart';
import '../subscriptions/pro_upgrade.dart';
import '../subscriptions/subscription_scope.dart';
import '../theme/weekpact_theme.dart';
import '../widgets/app_components.dart';
import '../widgets/app_icon.dart';
import '../widgets/app_sheet.dart';
import '../widgets/page_frame.dart';
import 'crew_backend.dart';
import 'crew_page.dart';
import 'crew_page_layout.dart';
import 'crew_profile.dart';
import 'crew_roster.dart';
import 'device_timezone.dart';

/// The Crews tab: every crew you are in, one card each, and the way into each
/// one's own page, where its pacts and its people are managed together.
///
/// There used to be a Pacts tab beside this one, each with its own switcher
/// over the same selected crew. A pact only ever belongs to one crew, so the
/// crew is where it is kept; the list is where a crew is chosen.
class CrewsPage extends StatefulWidget {
  const CrewsPage({
    super.key,
    required this.backend,
    required this.currentUserEmail,
    this.userId = '',
    this.weekBackend,
    this.pactsBackend,
    this.active = true,
    this.onCrewSelected,
    this.onInviteCode,
    this.onCrewLeft,
    this.onCrewCreated,
    this.pickCrewAvatar,
  });

  final CrewBackend backend;
  final String currentUserEmail;
  final String userId;

  /// Where each card's week comes from. Null draws the cards with their names
  /// alone.
  final HomeBackend? weekBackend;
  final PactsBackend? pactsBackend;
  final bool active;

  /// Told which crew was opened, so Home follows the crew last looked at.
  final ValueChanged<String>? onCrewSelected;

  /// Handed a code typed into "Join with a code"; null hides the button.
  final ValueChanged<InviteRef>? onInviteCode;
  final VoidCallback? onCrewLeft;
  final ValueChanged<CrewDetails>? onCrewCreated;

  /// Injected by tests, which have no gallery for the native picker to open.
  final AvatarPicker? pickCrewAvatar;

  @override
  State<CrewsPage> createState() => _CrewsPageState();
}

class _CrewsPageState extends State<CrewsPage> with WidgetsBindingObserver {
  final _crewNameController = TextEditingController();
  final _crewDescriptionController = TextEditingController();
  final _createFormKey = GlobalKey<FormState>();

  List<PactCrew>? _crews;
  final Map<String, CrewWeek> _weeks = {};
  final Set<String> _failedWeeks = {};
  bool _loading = false;
  bool _showCreate = false;
  bool _creating = false;
  bool _pickingPhoto = false;
  Uint8List? _crewPhoto;
  String? _error;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // The photo placeholder shows the name's first letter as it is typed.
    _crewNameController.addListener(_onCrewNameChanged);
    _refresh();
  }

  void _onCrewNameChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _crewNameController.dispose();
    _crewDescriptionController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant CrewsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) _refresh();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && widget.active) _refresh();
  }

  Future<void> _refresh() async {
    final request = ++_request;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final crews = await widget.backend.fetchCrews();
      if (!mounted || request != _request) return;
      setState(() {
        _crews = crews;
        _weeks.removeWhere((id, _) => !crews.any((c) => c.id == id));
      });
      final weeks = widget.weekBackend;
      if (weeks == null) return;
      // Each card fills in on its own: one crew's week failing leaves that
      // card with its name and nothing else, not the whole list waiting.
      await Future.wait([
        for (final crew in crews)
          weeks
              .fetchWeekBrief(crew.id)
              .then((week) {
                if (!mounted || request != _request) return;
                setState(() {
                  _weeks[crew.id] = week;
                  _failedWeeks.remove(crew.id);
                });
              })
              .catchError((Object _) {
                if (!mounted || request != _request) return;
                setState(() => _failedWeeks.add(crew.id));
              }),
      ]);
    } catch (error) {
      if (mounted && request == _request) {
        setState(() => _error = crewErrorMessage(error));
      }
    } finally {
      if (mounted && request == _request) setState(() => _loading = false);
    }
  }

  Future<void> _openCrew(PactCrew crew) async {
    widget.onCrewSelected?.call(crew.id);
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CrewPage(
          crewId: crew.id,
          backend: widget.backend,
          profileBackend: widget.weekBackend,
          pactsBackend: widget.pactsBackend,
          currentUserEmail: widget.currentUserEmail,
          onCrewLeft: widget.onCrewLeft,
        ),
      ),
    );
    // Back from the crew: its pacts, its people or the crew itself may have
    // changed while it was open.
    if (mounted) await _refresh();
  }

  /// Opens the new-crew form, or explains why it cannot be opened. Someone who
  /// upgrades from the dialog lands straight in the form.
  Future<void> _toggleCreate() async {
    if (_showCreate) {
      setState(() => _showCreate = false);
      return;
    }
    if ((_crews ?? const []).isNotEmpty && !context.isPro) {
      final upgraded = await showCrewLimitUpgrade(
        context,
        reason: CrewLimitReason.creating,
      );
      if (!upgraded || !mounted) return;
    }
    setState(() => _showCreate = true);
  }

  Future<void> _createCrew() async {
    if (!(_createFormKey.currentState?.validate() ?? false)) return;
    setState(() {
      _creating = true;
      _error = null;
    });
    try {
      final crew = await widget.backend.createCrew(
        name: _crewNameController.text,
        timezone: await deviceTimezone(),
        description: _crewDescriptionController.text,
        avatar: _crewPhoto,
      );
      if (!mounted) return;
      setState(() {
        _showCreate = false;
        _crewPhoto = null;
      });
      _crewNameController.clear();
      _crewDescriptionController.clear();
      widget.onCrewSelected?.call(crew.id);
      await _refresh();
      if (!mounted) return;
      widget.onCrewCreated?.call(crew);
    } catch (error) {
      if (!mounted) return;
      // Postgres has the final say: entitlements can lapse between opening the
      // form and submitting it, and the SDK's view can be stale.
      if (isCrewLimitError(error)) {
        if (await showCrewLimitUpgrade(
              context,
              reason: CrewLimitReason.creating,
            ) &&
            mounted) {
          await _createCrew();
          return;
        }
        if (mounted) setState(() => _showCreate = false);
      } else {
        setState(() => _error = crewErrorMessage(error));
      }
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  Future<void> _openJoinWithCode() async {
    final onCode = widget.onInviteCode;
    if (onCode == null) return;
    final invite = await showAppSheet<InviteRef>(
      context: context,
      builder: (sheetContext) => AppSheet(
        builder: (context) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Join with a code',
                    style: TextStyle(fontSize: 26, fontWeight: FontWeight.w600),
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.pop(context),
                  icon: const AppIcon(icon: HugeIconsStrokeRounded.cancel01),
                ),
              ],
            ),
            const SizedBox(height: 12),
            InviteCodeEntry(
              onInvite: (invite) => Navigator.pop(context, invite),
            ),
          ],
        ),
      ),
    );
    if (invite != null && mounted) onCode(invite);
  }

  Future<void> _chooseCrewPhoto() async {
    if (_creating || _pickingPhoto) return;
    setState(() {
      _pickingPhoto = true;
      _error = null;
    });
    final picked = await pickCrewPhoto(widget.pickCrewAvatar);
    if (!mounted) return;
    setState(() {
      _pickingPhoto = false;
      _crewPhoto = picked.photo ?? _crewPhoto;
      _error = picked.error;
    });
  }

  @override
  Widget build(BuildContext context) {
    final crews = _crews;
    final hasCrews = crews != null && crews.isNotEmpty;
    return PageFrame(
      header: CrewPageHeading(
        // Making another crew leads the row; the invites that other people
        // sent you close it. They are not a pair, so they do not sit as one.
        leading: [
          if (hasCrews)
            IconButton(
              tooltip: _showCreate ? 'Cancel new crew' : 'Create another crew',
              onPressed: _creating ? null : _toggleCreate,
              icon: AppIcon(
                icon: _showCreate
                    ? HugeIconsStrokeRounded.cancel01
                    : HugeIconsStrokeRounded.add01,
              ),
            ),
        ],
        actions: [
          if (widget.onInviteCode != null)
            IconButton(
              tooltip: 'Join with a code',
              onPressed: _openJoinWithCode,
              icon: const AppIcon(icon: HugeIconsStrokeRounded.userAdd01),
            ),
        ],
      ),
      loading: crews == null && _loading,
      skeleton: const CrewsListSkeleton(),
      onRefresh: _refresh,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (crews != null && (!hasCrews || _showCreate))
            AppSurfaceTheme(builder: _buildCreateState)
          else if (hasCrews)
            for (final (index, crew) in crews.indexed) ...[
              if (index > 0) const SizedBox(height: 12),
              CrewListCard(
                key: ValueKey('crew-card-${crew.id}'),
                crew: crew,
                week: _weeks[crew.id],
                weekFailed: _failedWeeks.contains(crew.id),
                userId: widget.userId,
                tint: _cardTints[index % _cardTints.length],
                onTap: () => _openCrew(crew),
              ),
            ],
          if (_error != null) ...[
            const SizedBox(height: 18),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: context.errorInk,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (crews == null) ...[
              const SizedBox(height: 12),
              Text(
                'Pull down to try again.',
                textAlign: TextAlign.center,
                style: TextStyle(color: context.muted),
              ),
            ],
          ],
        ],
      ),
    );
  }

  static const _cardTints = [
    WeekPactColors.stone,
    WeekPactColors.cream,
    WeekPactColors.mintGreen,
  ];

  Widget _buildCreateState(BuildContext context) {
    return Form(
      key: _createFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppSectionCard(
            title: 'Your crew',
            builder: (_) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Start your crew',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 20),
                  CrewPhotoField(
                    name: _crewNameController.text,
                    photo: _crewPhoto,
                    picking: _pickingPhoto,
                    onPick: _creating ? null : _chooseCrewPhoto,
                  ),
                  const SizedBox(height: 12),
                  AppTextField(
                    label: 'CREW NAME',
                    hint: 'Early Birds',
                    controller: _crewNameController,
                    validator: validateCrewName,
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 12),
                  AppTextField(
                    label: 'DESCRIPTION',
                    hint: 'What this crew is about (optional)',
                    controller: _crewDescriptionController,
                    validator: validateCrewDescription,
                    keyboardType: TextInputType.multiline,
                    minLines: 2,
                    maxLines: 4,
                  ),
                  const SizedBox(height: 22),
                  // The crew's week runs on the zone this device is in, taken
                  // from the device when the crew is made, so there is nothing
                  // to choose here and nothing to show.
                  Text(
                    'Your week runs Monday to Sunday.',
                    style: TextStyle(
                      color: context.muted,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 25),
                  AppButton(
                    label: 'CREATE CREW',
                    icon: HugeIconsStrokeRounded.userGroup02,
                    isLoading: _creating,
                    onPressed: _createCrew,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One crew in the list: its name and streak, who is in it and how many pacts
/// it keeps, then this week — yours and the crew's — so you can tell which
/// crew needs you without opening it.
class CrewListCard extends StatelessWidget {
  const CrewListCard({
    super.key,
    required this.crew,
    required this.userId,
    required this.onTap,
    this.week,
    this.weekFailed = false,
    this.tint = WeekPactColors.stone,
  });

  final PactCrew crew;
  final CrewWeek? week;
  final bool weekFailed;
  final String userId;
  final Color tint;
  final VoidCallback onTap;

  static const _faces = 4;

  @override
  Widget build(BuildContext context) {
    final week = this.week;
    return Semantics(
      button: true,
      label: 'Open ${crew.name}',
      child: AppSurface(
        fillColor: tint,
        resolveTone: false,
        borderRadius: WeekPactMetrics.cardCorner,
        builder: (context) => InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
            child: Row(
              children: [
                CrewAvatar(
                  key: ValueKey('crew-card-avatar-${crew.id}'),
                  name: crew.name,
                  url: crew.avatarUrl,
                  size: 48,
                  color: WeekPactColors.black.withValues(alpha: .10),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              crew.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: context.ink,
                                fontSize: 21,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          if (week != null && week.streakWeeks > 0) ...[
                            const SizedBox(width: 8),
                            _StreakPill(weeks: week.streakWeeks),
                          ],
                        ],
                      ),
                      const SizedBox(height: 10),
                      if (week != null)
                        ..._weekLines(context, week)
                      else if (weekFailed)
                        Text(
                          'This week could not load.',
                          style: TextStyle(color: context.muted, fontSize: 13),
                        )
                      else ...[
                        const SkeletonBar(height: 26, width: 120),
                        const SizedBox(height: 10),
                        const SkeletonBar(height: 8, radius: 999),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                AppIcon(
                  icon: HugeIconsStrokeRounded.arrowRight01,
                  color: context.ink.withValues(alpha: .6),
                  size: 22,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _weekLines(BuildContext context, CrewWeek week) {
    final caption = TextStyle(
      color: context.ink.withValues(alpha: .74),
      fontSize: 13,
      fontWeight: FontWeight.w500,
    );
    final pacts = week.pacts.length;
    return [
      Row(
        children: [
          for (final (i, member) in week.members.take(_faces).indexed)
            Align(
              widthFactor: i == 0 ? 1 : .72,
              child: SizedBox.square(
                dimension: 26,
                child: CrewFace(
                  fontSize: 11,
                  member: CrewMember(
                    userId: member.id,
                    email: member.email,
                    role: 'member',
                    joinedAt: DateTime(2000),
                    displayName: member.displayName,
                    avatarUrl: member.avatarUrl,
                  ),
                ),
              ),
            ),
          if (week.members.length > _faces) ...[
            const SizedBox(width: 6),
            Text('+${week.members.length - _faces}', style: caption),
          ],
          const Spacer(),
          Text(
            pacts == 0
                ? 'No pacts yet'
                : '$pacts ${pacts == 1 ? 'pact' : 'pacts'}',
            style: caption,
          ),
        ],
      ),
      if (week.target > 0) ...[
        const SizedBox(height: 12),
        LinearProgressIndicator(
          value: week.completed(userId) / week.target,
          minHeight: 8,
          borderRadius: WeekPactMetrics.pill,
          color: context.ink,
          backgroundColor: context.ink.withValues(alpha: .12),
          semanticsLabel:
              'Your week in ${crew.name}: ${week.completed(userId)} of '
              '${week.target} check-ins',
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Text(
                'You: ${week.completed(userId)} of ${week.target} this week',
                key: ValueKey('crew-card-progress-${crew.id}'),
                style: caption,
              ),
            ),
            Text('Crew ${week.percentCrew}%', style: caption),
          ],
        ),
      ] else ...[
        const SizedBox(height: 8),
        Text(
          crew.isOwner
              ? 'Add a pact to start the week.'
              : 'Waiting on the first pact.',
          style: caption,
        ),
      ],
    ];
  }
}

class _StreakPill extends StatelessWidget {
  const _StreakPill({required this.weeks});
  final int weeks;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: context.ink.withValues(alpha: .1),
      borderRadius: WeekPactMetrics.pill,
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const AppIcon(
            icon: HugeIconsStrokeRounded.fire,
            color: WeekPactColors.streak,
            size: 14,
          ),
          const SizedBox(width: 4),
          Text(
            '$weeks wk',
            semanticsLabel: '$weeks week streak',
            style: TextStyle(
              color: context.ink,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    ),
  );
}

/// The list's loading shapes: three cards at the height a loaded one stands.
class CrewsListSkeleton extends StatelessWidget {
  const CrewsListSkeleton({super.key});

  @override
  Widget build(BuildContext context) => CrewPageSkeleton(
    body: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < 3; i++) ...[
          if (i > 0) const SizedBox(height: 12),
          AppSurface(
            borderRadius: WeekPactMetrics.cardCorner,
            builder: (context) => const Padding(
              padding: EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SkeletonBar(width: 150, height: 22),
                  SizedBox(height: 12),
                  SkeletonBar(width: 120, height: 26),
                  SizedBox(height: 12),
                  SkeletonBar(height: 8, radius: 999),
                  SizedBox(height: 8),
                  SkeletonBar(width: 170, height: 12),
                ],
              ),
            ),
          ),
        ],
      ],
    ),
  );
}
