import 'package:flutter/material.dart';
import 'package:hugeicons/styles/stroke_rounded.dart';

import '../auth/account_actions.dart';
import '../auth/auth_backend.dart';
import '../auth/auth_page.dart';
import '../crew/crew_backend.dart';
import '../home/home_surface.dart';
import '../invites/invite_code_entry.dart';
import '../invites/invite_links.dart';
import '../pacts/pact_icons.dart';
import '../theme/weekpact_theme.dart';
import '../widgets/app_components.dart';
import '../widgets/app_icon.dart';
import '../widgets/pact_icon_badge.dart';
import 'onboarding_draft.dart';
import 'onboarding_widgets.dart';

/// A habit offered on the first-pact screen: what the tile says, the pact it
/// becomes, and its icon from the pact catalogue.
class StarterHabit {
  const StarterHabit(this.label, this.title, this.iconKey);

  final String label;
  final String title;
  final String iconKey;

  static const all = [
    StarterHabit('Run', 'Go for a run', 'run'),
    StarterHabit('Read', 'Read', 'book'),
    StarterHabit('Stretch', 'Stretch or yoga', 'yoga'),
    StarterHabit('Work out', 'Work out', 'strength'),
    StarterHabit('Sleep early', 'In bed on time', 'sleep'),
    StarterHabit('Walk', 'Go for a walk', 'walk'),
    StarterHabit('Get outside', 'Get outside', 'plant'),
    StarterHabit('Eat well', 'Eat well', 'food'),
  ];
}

enum _Screen { welcome, crewName, pact, save, code, invite, join, logIn }

/// Everything before there is an account, for a new phone: a new crew
/// (name → first pact → Apple/Google), an invite (code or link → the crew →
/// join with Apple/Google), and Log in for anybody who already has an account.
///
/// Answers go into [draftStore] after every screen; signing in hands over to
/// whoever shows the signed-in pages, which turns the draft into a crew.
class OnboardingFlow extends StatefulWidget {
  const OnboardingFlow({
    super.key,
    required this.authBackend,
    required this.draftStore,
    required this.onInvite,
    required this.onClearInvite,
    required this.onJoinIntent,
    this.invite,
    this.invitePreview,
    this.previewMissing = false,
    this.previewLoading = false,
    this.returning = false,
    this.initialError,
  });

  final AuthBackend authBackend;
  final OnboardingDraftStore draftStore;

  /// The invite this phone was handed, by link or by typing.
  final InviteRef? invite;
  final CrewInvitePreview? invitePreview;

  /// The preview came back empty: the code is unknown or was reset.
  final bool previewMissing;

  /// The preview is still on its way.
  final bool previewLoading;
  final ValueChanged<InviteRef> onInvite;
  final VoidCallback onClearInvite;

  /// Sign-in is about to happen for an invite; [notify] is the switch on the
  /// join screen. Called before the provider sheet opens.
  final ValueChanged<bool> onJoinIntent;

  /// Somebody who was signed in on this phone a moment ago: Log in first.
  final bool returning;
  final String? initialError;

  @override
  State<OnboardingFlow> createState() => _OnboardingFlowState();
}

class _OnboardingFlowState extends State<OnboardingFlow> {
  late OnboardingDraft _draft =
      widget.draftStore.read() ?? const OnboardingDraft();

  /// The screens on the flow's navigator, bottom to top. The navigator's
  /// pages are built from it, so pushing, popping and the iOS edge swipe all
  /// go through this one list.
  late final List<_Screen> _history = _initialHistory();
  SignInProvider? _signingIn;
  String? _error;
  bool _notify = true;

  _Screen get _screen => _history.last;

  /// Where the flow opens, with the screens that would have come before it
  /// underneath, so back (and the swipe) from there goes somewhere sensible.
  List<_Screen> _initialHistory() {
    const welcome = _Screen.welcome;
    if (widget.invite != null) return [welcome, _Screen.invite];
    if (widget.initialError != null || widget.returning) {
      return [welcome, _Screen.logIn];
    }
    // Somebody who closed the app halfway comes back where they were.
    if (_draft.complete) {
      return [welcome, _Screen.crewName, _Screen.pact, _Screen.save];
    }
    if (_draft.crewName?.trim().isNotEmpty ?? false) {
      return [welcome, _Screen.crewName, _Screen.pact];
    }
    return [welcome];
  }

  /// One key per place in the history, so a screen keeps its state while
  /// others are pushed over it, and a screen replaced at the same depth is a
  /// new page.
  ValueKey<String> _pageKey(int depth) =>
      ValueKey('$depth-${_history[depth].name}');

  @override
  void didUpdateWidget(covariant OnboardingFlow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.invite != null && widget.invite != oldWidget.invite) {
      setState(() {
        _error = null;
        if (_screen != _Screen.invite) _history.add(_Screen.invite);
      });
    }
    if (widget.initialError != null && oldWidget.initialError == null) {
      setState(() => _history.add(_Screen.logIn));
    }
  }

  void _go(_Screen screen) => setState(() {
    _error = null;
    _history.add(screen);
  });

  void _back() {
    if (_history.length <= 1) return;
    setState(_popScreen);
  }

  void _popScreen() {
    _error = null;
    final left = _history.removeLast();
    if (left == _Screen.invite) widget.onClearInvite();
  }

  Future<void> _saveDraft(OnboardingDraft draft) async {
    setState(() => _draft = draft);
    await widget.draftStore.save(draft);
  }

  Future<void> _signIn(SignInProvider provider, {bool join = false}) async {
    if (_signingIn != null) return;
    if (join) widget.onJoinIntent(_notify);
    setState(() {
      _signingIn = provider;
      _error = null;
    });
    try {
      // On success the auth stream replaces this whole flow; nothing more to
      // do here.
      await widget.authBackend.signInWith(provider);
    } catch (error) {
      if (mounted) setState(() => _error = signInErrorMessage(error));
    } finally {
      if (mounted) setState(() => _signingIn = null);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    // Android's back reaches the outer route first; hand it to the flow.
    canPop: _history.length <= 1,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _back();
    },
    child: Navigator(
      pages: [
        for (var depth = 0; depth < _history.length; depth++)
          MaterialPage<void>(
            key: _pageKey(depth),
            child: _screenFor(context, _history[depth]),
          ),
      ],
      // A page the navigator took off itself (the iOS edge swipe) leaves the
      // history too. Pages this state removed are already gone from it.
      onDidRemovePage: (page) {
        if (page.key == _pageKey(_history.length - 1) && _history.length > 1) {
          setState(_popScreen);
        }
      },
    ),
  );

  Widget _screenFor(BuildContext context, _Screen screen) => switch (screen) {
    _Screen.welcome => _welcome(context),
    _Screen.crewName => _CrewNameScreen(
      initial: _draft.crewName,
      onBack: _back,
      onLogIn: () => _go(_Screen.logIn),
      onCode: () => _go(_Screen.code),
      onNext: (name) async {
        await _saveDraft(_draft.copyWith(crewName: name));
        _go(_Screen.pact);
      },
    ),
    _Screen.pact => _FirstPactScreen(
      crewName: _draft.crewName ?? 'your crew',
      draft: _draft,
      onBack: _back,
      onLogIn: () => _go(_Screen.logIn),
      onNext: (title, icon, days) async {
        await _saveDraft(
          _draft.copyWith(pactTitle: title, pactIcon: icon, pactDays: days),
        );
        _go(_Screen.save);
      },
    ),
    _Screen.save => _save(context),
    _Screen.code => OnboardingScaffold(
      onBack: _back,
      onLogIn: () => _go(_Screen.logIn),
      eyebrow: 'JOIN A CREW',
      title: 'Enter your invite code.',
      subtitle: 'Six letters and numbers, from the invite message or page.',
      body: [InviteCodeEntry(showTip: true, onInvite: widget.onInvite)],
    ),
    _Screen.invite => _invite(context),
    _Screen.join => _join(context),
    _Screen.logIn => _logIn(context),
  };

  Widget _welcome(BuildContext context) => OnboardingScaffold(
    title: 'Good habits.\nGreat company.',
    subtitle:
        'Pick one small thing, keep it a few days a week, and do it alongside '
        'your friends.',
    centerBody: true,
    body: const [_WelcomeArt()],
    footer: [
      AppButton(
        key: const ValueKey('get-started'),
        label: 'GET STARTED',
        color: WeekPactColors.mintGreen,
        height: 56,
        onPressed: () => _go(_Screen.crewName),
      ),
      const SizedBox(height: 10),
      AppButton(
        key: const ValueKey('have-code'),
        label: 'I HAVE AN INVITE CODE',
        icon: HugeIconsStrokeRounded.link01,
        color: WeekPactColors.graphite,
        foregroundColor: WeekPactColors.darkInk,
        height: 56,
        onPressed: () => _go(_Screen.code),
      ),
      const SizedBox(height: 4),
      TextButton(
        key: const ValueKey('welcome-log-in'),
        onPressed: () => _go(_Screen.logIn),
        style: TextButton.styleFrom(foregroundColor: context.muted),
        child: const Text('Already have an account? Log in'),
      ),
    ],
  );

  Widget _save(BuildContext context) {
    final icon = PactIcon.find(_draft.pactIcon ?? 'target');
    final days = _draft.pactDays ?? 3;
    return OnboardingScaffold(
      onBack: _back,
      step: 3,
      steps: 3,
      onLogIn: () => _go(_Screen.logIn),
      eyebrow: '3 OF 3 · LAST STEP',
      title: 'Save your week.',
      subtitle:
          'Your name and photo come from your account. Nothing to fill in.',
      body: [
        _SummaryCard(
          tint: WeekPactColors.pactTint(0),
          badge: WeekPactColors.pactBadge(0),
          icon: icon.data,
          title: '${_draft.pactTitle ?? 'Your pact'} · ${_daysLabel(days)}',
          caption:
              '${(_draft.crewName ?? 'Your crew').toUpperCase()} · STARTS TODAY',
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: TextStyle(color: context.errorInk)),
        ],
      ],
      footer: [
        ProviderButtons(
          providers: widget.authBackend.signInProviders,
          busy: _signingIn,
          onPressed: (provider) => _signIn(provider),
        ),
        const SizedBox(height: 12),
        const TermsLine(),
      ],
    );
  }

  Widget _invite(BuildContext context) {
    final preview = widget.invitePreview;
    if (widget.previewMissing) {
      return InviteProblemView(
        problem: InviteProblem.invalid,
        onBack: _back,
        onPrimary: () {
          widget.onClearInvite();
          setState(
            () => _history
              ..clear()
              ..addAll([_Screen.welcome, _Screen.code]),
          );
        },
        onSecondary: () {
          widget.onClearInvite();
          setState(
            () => _history
              ..clear()
              ..addAll([_Screen.welcome, _Screen.crewName]),
          );
        },
      );
    }
    return OnboardingScaffold(
      onBack: _back,
      onLogIn: () => _go(_Screen.logIn),
      title: preview == null
          ? 'Your crew is waiting.'
          : '${preview.inviterName} invited you.',
      subtitle: 'To keep each other honest, one small pact at a time.',
      body: [
        if (preview != null)
          InvitePreviewCard(preview: preview)
        else if (widget.previewLoading)
          const Center(child: CircularProgressIndicator()),
      ],
      footer: [
        AppButton(
          key: const ValueKey('join-crew'),
          label: preview == null
              ? 'JOIN THE CREW'
              : 'JOIN ${preview.crewName.toUpperCase()}',
          color: WeekPactColors.mintGreen,
          height: 56,
          onPressed: widget.previewLoading ? null : () => _go(_Screen.join),
        ),
        const SizedBox(height: 4),
        TextButton(
          onPressed: () {
            widget.onClearInvite();
            setState(
              () => _history
                ..clear()
                ..addAll([_Screen.welcome, _Screen.crewName]),
            );
          },
          style: TextButton.styleFrom(foregroundColor: context.muted),
          child: const Text('Not for you? Start your own crew'),
        ),
      ],
    );
  }

  Widget _join(BuildContext context) {
    final preview = widget.invitePreview;
    final name = preview?.crewName ?? 'the crew';
    return OnboardingScaffold(
      onBack: _back,
      onLogIn: () => _go(_Screen.logIn),
      eyebrow: 'ONE TAP AND YOU’RE IN',
      title: 'Join $name.',
      subtitle: 'No password to remember. Your name comes from your account.',
      body: [
        if (preview != null)
          _SummaryCard(
            tint: WeekPactColors.mintGreen,
            badge: WeekPactColors.cream,
            icon: HugeIconsStrokeRounded.userGroup,
            title:
                '${preview.crewName} · ${preview.memberCount} '
                '${preview.memberCount == 1 ? 'member' : 'members'}',
            caption: '${preview.inviterName.toUpperCase()} INVITED YOU',
          ),
        const SizedBox(height: 10),
        NotifySwitchCard(
          title: 'Tell me when they check in',
          value: _notify,
          onChanged: (value) => setState(() => _notify = value),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: TextStyle(color: context.errorInk)),
        ],
      ],
      footer: [
        ProviderButtons(
          providers: widget.authBackend.signInProviders,
          busy: _signingIn,
          verb: 'Join',
          onPressed: (provider) => _signIn(provider, join: true),
        ),
        const SizedBox(height: 12),
        const TermsLine(),
      ],
    );
  }

  Widget _logIn(BuildContext context) => OnboardingScaffold(
    onBack: _back,
    title: 'Welcome back.',
    subtitle: 'Use the same Apple or Google account you joined with.',
    body: [
      if (widget.initialError != null || _error != null) ...[
        Text(
          _error ?? widget.initialError!,
          style: TextStyle(color: context.errorInk),
        ),
        const SizedBox(height: 12),
      ],
    ],
    footer: [
      ProviderButtons(
        providers: widget.authBackend.signInProviders,
        busy: _signingIn,
        onPressed: (provider) => _signIn(provider, join: widget.invite != null),
      ),
      const SizedBox(height: 4),
      TextButton(
        key: const ValueKey('email-log-in'),
        onPressed: () => Navigator.of(context, rootNavigator: true).push(
          MaterialPageRoute<void>(
            builder: (_) => EmailLogInPage(authBackend: widget.authBackend),
          ),
        ),
        style: TextButton.styleFrom(foregroundColor: context.muted),
        child: const Text('Joined with email before? Log in with email'),
      ),
      const SizedBox(height: 8),
      const PublicAccountLinks(),
    ],
  );
}

String _daysLabel(int days) => days >= 7 ? 'every day' : '$days× a week';

/// The front door's picture: three of a crew's pacts, mid-week, fanned like
/// a hand of cards and drawn the way Home draws them.
class _WelcomeArt extends StatelessWidget {
  const _WelcomeArt();

  // Back to front; the last is the one on top.
  static const _hand = [
    (index: 2, icon: 'book', title: 'Read before bed', done: 4, days: 5),
    (index: 4, icon: 'yoga', title: 'Stretch for 10 minutes', done: 3, days: 4),
    (index: 1, icon: 'run', title: 'Morning run', done: 2, days: 3),
  ];
  // Turned about the bottom of the hand, the way cards held in one hand
  // spread: the back two lean out far enough to show their names and badges.
  static const _angles = [-.13, .13, 0.0];
  static const _offsets = [Offset(-40, 0), Offset(40, 0), Offset(0, 64)];

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox(
      height: 316,
      child: Stack(
        alignment: Alignment.topCenter,
        clipBehavior: Clip.none,
        children: [
          for (var i = 0; i < _hand.length; i++)
            Transform.translate(
              offset: _offsets[i],
              child: Transform.rotate(
                angle: _angles[i],
                alignment: const Alignment(0, 1.6),
                child: _FanCard(
                  tint: WeekPactColors.pactTint(_hand[i].index),
                  badge: WeekPactColors.pactBadge(_hand[i].index),
                  icon: PactIcon.find(_hand[i].icon).data,
                  title: _hand[i].title,
                  done: _hand[i].done,
                  days: _hand[i].days,
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

/// Home's pact card at a glance: name, badge, the week's count and its bar.
class _FanCard extends StatelessWidget {
  const _FanCard({
    required this.tint,
    required this.badge,
    required this.icon,
    required this.title,
    required this.done,
    required this.days,
  });

  final Color tint;
  final Color badge;
  final List<List<dynamic>> icon;
  final String title;
  final int done;
  final int days;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 236,
    height: 236,
    child: HomeSurface(
      tint: tint,
      radius: WeekPactMetrics.cardCorner,
      raised: true,
      depth: WeekPactMetrics.cardDepth,
      shape: WeekPactMetrics.pactCardShape,
      outlineColor: Color.lerp(tint, Colors.black, .28),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  title,
                  maxLines: 2,
                  style: const TextStyle(
                    color: homeInk,
                    fontSize: 21,
                    height: 1.15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              PactIconBadge(icon: icon, tint: badge, size: 44),
            ],
          ),
          const Spacer(),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '$done',
                style: const TextStyle(
                  color: homeInk,
                  fontSize: 52,
                  height: 1,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                '/ $days',
                style: TextStyle(
                  color: homeMutedInk,
                  fontSize: 26,
                  height: 1,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'days',
                  maxLines: 1,
                  style: TextStyle(
                    color: homeMutedInk,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              for (var day = 0; day < days; day++)
                Expanded(
                  child: Container(
                    height: 12,
                    margin: EdgeInsets.only(right: day == days - 1 ? 0 : 4),
                    decoration: ShapeDecoration(
                      color: day < done
                          ? homeInk
                          : homeInk.withValues(alpha: .32),
                      shape: ContinuousRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          WeekPactMetrics.curveFor(6),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    ),
  );
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.tint,
    required this.badge,
    required this.icon,
    required this.title,
    required this.caption,
  });

  final Color tint;
  final Color badge;
  final List<List<dynamic>> icon;
  final String title;
  final String caption;

  @override
  Widget build(BuildContext context) => AppSurface(
    fillColor: tint,
    resolveTone: false,
    builder: (context) => Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          PactIconBadge(icon: icon, tint: badge, size: 40),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: WeekPactColors.black,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  caption,
                  style: const TextStyle(
                    color: WeekPactColors.mutedLight,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _CrewNameScreen extends StatefulWidget {
  const _CrewNameScreen({
    required this.initial,
    required this.onBack,
    required this.onLogIn,
    required this.onCode,
    required this.onNext,
  });

  final String? initial;
  final VoidCallback onBack;
  final VoidCallback onLogIn;
  final VoidCallback onCode;
  final Future<void> Function(String name) onNext;

  @override
  State<_CrewNameScreen> createState() => _CrewNameScreenState();
}

class _CrewNameScreenState extends State<_CrewNameScreen> {
  static const _suggestions = ['Morning Runners', 'Early Birds', 'The Pact'];

  // Prefilled, so Continue works without typing a thing.
  late final _controller = TextEditingController(
    text: widget.initial ?? _suggestions.first,
  );
  final _form = GlobalKey<FormState>();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (!(_form.currentState?.validate() ?? false)) return;
    widget.onNext(_controller.text.trim());
  }

  @override
  Widget build(BuildContext context) => OnboardingScaffold(
    onBack: widget.onBack,
    step: 1,
    steps: 3,
    onLogIn: widget.onLogIn,
    eyebrow: '1 OF 3 · YOUR CREW',
    title: 'Name your crew.',
    subtitle:
        'Your crew is you plus anyone you invite. Friends can join now or any '
        'time later.',
    body: [
      Form(
        key: _form,
        child: AppTextField(
          label: 'CREW NAME',
          hint: 'Morning Runners',
          controller: _controller,
          textInputAction: TextInputAction.done,
          validator: (value) {
            final name = value?.trim() ?? '';
            if (name.length < 2) return 'Give your crew a name';
            if (name.length > 60) return 'Keep it under 60 characters';
            return null;
          },
        ),
      ),
      const SizedBox(height: 10),
      Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final suggestion in _suggestions)
            TextButton(
              onPressed: () => setState(() => _controller.text = suggestion),
              style: TextButton.styleFrom(
                backgroundColor: WeekPactColors.graphite,
                foregroundColor: WeekPactColors.darkInk,
                minimumSize: const Size(0, 40),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                shape: WeekPactMetrics.buttonShape,
                side: const BorderSide(color: WeekPactColors.graphiteEdge),
              ),
              child: Text(
                suggestion,
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
            ),
        ],
      ),
    ],
    footer: [
      AppButton(
        key: const ValueKey('crew-name-continue'),
        label: 'CONTINUE',
        color: WeekPactColors.mintGreen,
        height: 56,
        onPressed: _submit,
      ),
      const SizedBox(height: 4),
      TextButton(
        onPressed: widget.onCode,
        style: TextButton.styleFrom(foregroundColor: context.muted),
        child: const Text('Got an invite code instead?'),
      ),
    ],
  );
}

class _FirstPactScreen extends StatefulWidget {
  const _FirstPactScreen({
    required this.crewName,
    required this.draft,
    required this.onBack,
    required this.onLogIn,
    required this.onNext,
  });

  final String crewName;
  final OnboardingDraft draft;
  final VoidCallback onBack;
  final VoidCallback onLogIn;
  final Future<void> Function(String title, String icon, int days) onNext;

  @override
  State<_FirstPactScreen> createState() => _FirstPactScreenState();
}

class _FirstPactScreenState extends State<_FirstPactScreen> {
  late int _picked = _initialPick();
  late int _days = widget.draft.pactDays ?? 3;
  late final _custom = TextEditingController(
    text: _initialPick() == -1 ? widget.draft.pactTitle : '',
  );
  String? _error;

  int _initialPick() {
    final title = widget.draft.pactTitle;
    if (title == null) return 0;
    final index = StarterHabit.all.indexWhere((habit) => habit.title == title);
    return index;
  }

  @override
  void dispose() {
    _custom.dispose();
    super.dispose();
  }

  void _submit() {
    if (_picked == -1) {
      final title = _custom.text.trim();
      if (title.length < 2) {
        setState(() => _error = 'Name your pact, like “Practise guitar”.');
        return;
      }
      widget.onNext(title, 'target', _days);
      return;
    }
    final habit = StarterHabit.all[_picked];
    widget.onNext(habit.title, habit.iconKey, _days);
  }

  @override
  Widget build(BuildContext context) => OnboardingScaffold(
    onBack: widget.onBack,
    step: 2,
    steps: 3,
    onLogIn: widget.onLogIn,
    eyebrow: '2 OF 3 · YOUR PACT',
    title: 'What will ${widget.crewName} keep up first?',
    body: [
      GridView.count(
        crossAxisCount: 3,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 1.25,
        children: [
          for (final (index, habit) in StarterHabit.all.indexed)
            _HabitTile(
              label: habit.label,
              icon: PactIcon.find(habit.iconKey).data,
              tint: WeekPactColors.pactTint(index),
              badge: WeekPactColors.pactBadge(index),
              selected: _picked == index,
              onTap: () => setState(() {
                _picked = index;
                _error = null;
              }),
            ),
          _HabitTile(
            label: 'Something else',
            icon: HugeIconsStrokeRounded.pencilEdit02,
            tint: WeekPactColors.stone,
            badge: WeekPactColors.neutralInset,
            selected: _picked == -1,
            onTap: () => setState(() => _picked = -1),
          ),
        ],
      ),
      if (_picked == -1) ...[
        const SizedBox(height: 12),
        AppTextField(
          label: 'YOUR PACT',
          hint: 'Practise guitar',
          controller: _custom,
          textInputAction: TextInputAction.done,
          validator: (_) => null,
        ),
      ],
      const SizedBox(height: 12),
      AppSurface(
        builder: (context) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'HOW OFTEN',
                          style: TextStyle(
                            color: context.muted,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            letterSpacing: 1,
                          ),
                        ),
                        Text(
                          _days >= 7
                              ? 'Every day'
                              : _days == 1
                              ? 'Once a week'
                              : '$_days days a week',
                          style: TextStyle(
                            color: context.ink,
                            fontSize: 19,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton.filledTonal(
                    tooltip: 'Fewer days',
                    onPressed: _days > 1 ? () => setState(() => _days--) : null,
                    icon: const AppIcon(icon: HugeIconsStrokeRounded.minusSign),
                  ),
                  const SizedBox(width: 6),
                  IconButton.filledTonal(
                    tooltip: 'More days',
                    onPressed: _days < 7 ? () => setState(() => _days++) : null,
                    icon: const AppIcon(icon: HugeIconsStrokeRounded.add01),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  for (var i = 0; i < 7; i++) ...[
                    if (i > 0) const SizedBox(width: 4),
                    Expanded(
                      child: Container(
                        height: 10,
                        decoration: BoxDecoration(
                          color: i < _days
                              ? WeekPactColors.pactBadge(
                                  _picked < 0 ? 0 : _picked,
                                )
                              : WeekPactColors.neutralInset,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Small enough for a busy week. Most people start with 3.',
                style: TextStyle(color: context.muted, fontSize: 13),
              ),
            ],
          ),
        ),
      ),
      if (_error != null) ...[
        const SizedBox(height: 10),
        Text(_error!, style: TextStyle(color: context.errorInk)),
      ],
    ],
    footer: [
      AppButton(
        key: const ValueKey('pact-continue'),
        label: 'CONTINUE',
        color: WeekPactColors.mintGreen,
        height: 56,
        onPressed: _submit,
      ),
    ],
  );
}

class _HabitTile extends StatelessWidget {
  const _HabitTile({
    required this.label,
    required this.icon,
    required this.tint,
    required this.badge,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final List<List<dynamic>> icon;
  final Color tint;
  final Color badge;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    child: AppSurface(
      fillColor: selected ? tint : WeekPactColors.cream,
      resolveTone: false,
      outlineColor: selected ? WeekPactColors.black : null,
      borderWidth: selected ? 2 : WeekPactMetrics.border,
      builder: (context) => InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              PactIconBadge(icon: icon, tint: badge, size: 32),
              const SizedBox(height: 6),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: WeekPactColors.black,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// A crew behind an invite, before anyone joins: who sent it, the crew, who
/// is in it, and the pacts they keep.
class InvitePreviewCard extends StatelessWidget {
  const InvitePreviewCard({super.key, required this.preview});

  final CrewInvitePreview preview;

  @override
  Widget build(BuildContext context) => AppSurface(
    fillColor: WeekPactColors.mintGreen,
    resolveTone: false,
    builder: (context) => Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _Initials(
                text: preview.inviterInitials.isEmpty
                    ? _initialsOf(preview.inviterName)
                    : preview.inviterInitials,
                size: 56,
                color: WeekPactColors.pactBadge(2),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '${preview.inviterName} invited you to',
                  style: const TextStyle(
                    color: WeekPactColors.black,
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            preview.crewName,
            style: const TextStyle(
              color: WeekPactColors.black,
              fontSize: 34,
              height: 1.05,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              for (final (index, initials)
                  in preview.memberInitials.take(5).indexed)
                Transform.translate(
                  offset: Offset(-8.0 * index, 0),
                  child: _Initials(
                    text: initials,
                    size: 32,
                    color: WeekPactColors.pactBadge(index),
                  ),
                ),
              Expanded(
                child: Text(
                  '${preview.memberCount} '
                  '${preview.memberCount == 1 ? 'member' : 'members'}'
                  ' · started by ${preview.ownerName}',
                  style: const TextStyle(
                    color: WeekPactColors.mutedLight,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
          if (preview.pacts.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              preview.pacts.length == 1
                  ? 'YOU’LL KEEP THIS PACT WITH THEM'
                  : 'YOU’LL KEEP THESE PACTS WITH THEM',
              style: const TextStyle(
                color: WeekPactColors.mutedLight,
                fontSize: 12,
                fontWeight: FontWeight.w500,
                letterSpacing: 1,
              ),
            ),
            for (final (index, pact) in preview.pacts.indexed) ...[
              const SizedBox(height: 6),
              AppSurface(
                fillColor: WeekPactColors.pactTint(index),
                resolveTone: false,
                raised: false,
                borderRadius: WeekPactMetrics.controlRadius,
                builder: (context) => Padding(
                  padding: const EdgeInsets.all(8),
                  child: Row(
                    children: [
                      PactIconBadge(
                        icon: PactIcon.find(pact.iconKey).data,
                        tint: WeekPactColors.pactBadge(index),
                        size: 28,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          pact.title,
                          style: const TextStyle(
                            color: WeekPactColors.black,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Text(
                        _daysLabel(pact.daysPerWeek).toUpperCase(),
                        style: const TextStyle(
                          color: WeekPactColors.mutedLight,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ],
      ),
    ),
  );
}

String _initialsOf(String name) => name
    .trim()
    .split(RegExp(r'\s+'))
    .where((part) => part.isNotEmpty)
    .take(2)
    .map((part) => part[0].toUpperCase())
    .join();

class _Initials extends StatelessWidget {
  const _Initials({
    required this.text,
    required this.size,
    required this.color,
  });

  final String text;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(size * .32),
      border: Border.all(color: WeekPactColors.black, width: 1.5),
    ),
    child: Text(
      text,
      style: TextStyle(
        color: WeekPactColors.black,
        fontSize: size * .36,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

/// A card with one switch: the notification ask, made where the reason for it
/// is on screen instead of on a page of its own.
class NotifySwitchCard extends StatelessWidget {
  const NotifySwitchCard({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => AppSurface(
    builder: (context) => Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      child: Row(
        children: [
          PactIconBadge(
            icon: HugeIconsStrokeRounded.notification02,
            tint: WeekPactColors.lantern,
            size: 36,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: context.ink,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: TextStyle(color: context.muted, fontSize: 13),
                  ),
              ],
            ),
          ),
          Switch(
            key: const ValueKey('notify-switch'),
            value: value,
            onChanged: onChanged,
          ),
        ],
      ),
    ),
  );
}

enum InviteProblem { invalid, member }

/// An invite that cannot be used as it stands, with the way forward from it.
class InviteProblemView extends StatelessWidget {
  const InviteProblemView({
    super.key,
    required this.problem,
    required this.onPrimary,
    this.onSecondary,
    this.onBack,
    this.crewName,
  });

  final InviteProblem problem;
  final VoidCallback onPrimary;
  final VoidCallback? onSecondary;
  final VoidCallback? onBack;
  final String? crewName;

  @override
  Widget build(BuildContext context) => OnboardingScaffold(
    onBack: onBack,
    centered: true,
    title: switch (problem) {
      InviteProblem.invalid => 'This invite doesn’t work anymore.',
      InviteProblem.member => 'You’re already in.',
    },
    subtitle: switch (problem) {
      InviteProblem.invalid =>
        'The code may have been mistyped, or the crew reset it. Ask whoever '
            'invited you for the current one.',
      InviteProblem.member =>
        'You’re already a member of ${crewName ?? 'this crew'}. Nothing to do '
            'here — your crew is one tap away.',
    },
    body: [
      Center(
        child: PactIconBadge(
          icon: switch (problem) {
            InviteProblem.invalid => HugeIconsStrokeRounded.clock01,
            InviteProblem.member => HugeIconsStrokeRounded.checkmarkCircle02,
          },
          tint: switch (problem) {
            InviteProblem.invalid => WeekPactColors.lantern,
            InviteProblem.member => WeekPactColors.mintGreen,
          },
          size: 88,
        ),
      ),
    ],
    footer: [
      AppButton(
        label: switch (problem) {
          InviteProblem.invalid => 'ENTER A DIFFERENT CODE',
          InviteProblem.member =>
            'GO TO ${(crewName ?? 'your crew').toUpperCase()}',
        },
        color: WeekPactColors.mintGreen,
        height: 56,
        onPressed: onPrimary,
      ),
      if (onSecondary != null) ...[
        const SizedBox(height: 10),
        AppButton(
          label: 'START MY OWN CREW',
          color: WeekPactColors.graphite,
          foregroundColor: WeekPactColors.darkInk,
          height: 56,
          onPressed: onSecondary,
        ),
      ],
    ],
  );
}
