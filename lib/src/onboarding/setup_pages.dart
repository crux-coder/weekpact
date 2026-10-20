import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hugeicons/styles/stroke_rounded.dart';

import '../auth/auth_backend.dart';
import '../crew/crew_backend.dart';
import '../crew/crew_sharing.dart';
import '../home/home_backend.dart';
import '../invites/invite_links.dart';
import '../notifications/notification_primer_page.dart';
import '../notifications/notification_scope.dart';
import '../pacts/pact_icons.dart';
import '../pacts/pacts_backend.dart';
import '../sharing/app_share.dart';
import '../theme/weekpact_theme.dart';
import '../widgets/app_components.dart';
import '../widgets/app_icon.dart';
import '../widgets/pact_icon_badge.dart';
import 'onboarding_flow.dart';
import 'onboarding_widgets.dart';

/// Turns the notification switch into the system's ask, when there is still
/// an ask to make. A refusal is the system's to remember, not ours.
Future<void> askForNotifications(BuildContext context) async {
  final service = NotificationScope.maybeOf(context);
  if (!NotificationPrimerPage.wanted(service)) return;
  try {
    await service!.enable();
  } catch (_) {}
}

/// Asked only when Apple withheld the name, which Apple lets people do.
class NamePage extends StatefulWidget {
  const NamePage({
    super.key,
    required this.backend,
    required this.user,
    required this.onSaved,
    this.crewName,
  });

  final AuthBackend backend;
  final AuthUser user;
  final ValueChanged<AuthUser> onSaved;

  /// The crew this name is for, when there is one already.
  final String? crewName;

  @override
  State<NamePage> createState() => _NamePageState();
}

class _NamePageState extends State<NamePage> {
  final _form = GlobalKey<FormState>();
  late final _first = TextEditingController(text: widget.user.firstName);
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _first.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !(_form.currentState?.validate() ?? false)) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final user = await widget.backend.completeOnboarding(
        firstName: _first.text.trim(),
        lastName: widget.user.lastName,
      );
      TextInput.finishAutofillContext();
      if (mounted) widget.onSaved(user);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is ArgumentError
              ? error.message.toString()
              : 'Could not save your name. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Form(
    key: _form,
    child: OnboardingScaffold(
      eyebrow: widget.crewName == null
          ? 'ACCOUNT SAVED'
          : 'YOU’RE IN ${widget.crewName!.toUpperCase()}',
      title: 'What should the crew call you?',
      subtitle: 'Apple kept your name private, so we just need a first name.',
      body: [
        AppTextField(
          label: 'FIRST NAME',
          hint: 'Your first name',
          controller: _first,
          textInputAction: TextInputAction.done,
          autofillHints: const [AutofillHints.givenName],
          validator: (value) {
            final name = value?.trim() ?? '';
            if (name.isEmpty) return 'Enter your first name';
            if (name.length > 60) return 'Keep it under 60 characters';
            return null;
          },
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: TextStyle(color: context.errorInk)),
        ],
      ],
      footer: [
        AppButton(
          key: const ValueKey('name-continue'),
          label: 'CONTINUE',
          color: WeekPactColors.mintGreen,
          height: 56,
          isLoading: _saving,
          onPressed: _save,
        ),
      ],
    ),
  );
}

/// While the draft becomes a crew, or when that failed and can be retried.
class SetupStatusPage extends StatelessWidget {
  const SetupStatusPage({super.key, this.error, this.onRetry, this.onSkip});

  final String? error;
  final VoidCallback? onRetry;
  final VoidCallback? onSkip;

  @override
  Widget build(BuildContext context) => error == null
      ? const Scaffold(body: Center(child: CircularProgressIndicator()))
      : OnboardingScaffold(
          centered: true,
          title: 'Your crew didn’t save.',
          subtitle: error,
          body: const [],
          footer: [
            AppButton(
              label: 'TRY AGAIN',
              color: WeekPactColors.mintGreen,
              height: 56,
              onPressed: onRetry,
            ),
            if (onSkip != null)
              TextButton(
                onPressed: onSkip,
                style: TextButton.styleFrom(foregroundColor: context.muted),
                child: const Text('Skip for now'),
              ),
          ],
        );
}

/// Right after the account: the crew's link and code, and the one ask for
/// notifications, made while there is somebody to hear from.
class BringPeoplePage extends StatefulWidget {
  const BringPeoplePage({
    super.key,
    required this.crew,
    required this.sharing,
    required this.onDone,
    this.inviterId,
    this.share = const NativeAppShare(),
  });

  final CrewDetails crew;
  final CrewSharingBackend? sharing;
  final String? inviterId;
  final AppShare share;
  final VoidCallback onDone;

  @override
  State<BringPeoplePage> createState() => _BringPeoplePageState();
}

class _BringPeoplePageState extends State<BringPeoplePage> {
  String? _code;
  bool _notify = true;
  bool _busy = false;
  bool _copied = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final sharing = widget.sharing;
    if (sharing == null) return;
    try {
      final code = await sharing.inviteCode(widget.crew.id);
      if (mounted) setState(() => _code = code);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not load the invite code.');
    }
  }

  Future<void> _share(BuildContext anchor) async {
    final code = _code;
    if (code == null || _busy) return;
    final origin = shareOrigin(anchor);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.share.text(
        inviteMessage(widget.crew.name, code, from: widget.inviterId),
        origin,
      );
      if (!mounted) return;
      if (_notify) await askForNotifications(context);
      if (mounted) widget.onDone();
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not share. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _copy() async {
    final code = _code;
    if (code == null) return;
    await Clipboard.setData(
      ClipboardData(text: inviteUrl(code, from: widget.inviterId).toString()),
    );
    if (mounted) setState(() => _copied = true);
  }

  @override
  Widget build(BuildContext context) {
    final code = _code;
    final open = widget.crew.members.length;
    return OnboardingScaffold(
      eyebrow: 'ACCOUNT SAVED',
      title: 'Bring your people.',
      subtitle: 'Send the link to whoever should keep you honest.',
      body: [
        AppSurface(
          builder: (context) => Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.crew.name,
                        style: TextStyle(
                          color: context.ink,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Text(
                      open == 1 ? 'JUST YOU SO FAR' : '$open MEMBERS',
                      style: TextStyle(
                        color: context.muted,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                if (code == null)
                  const SizedBox(height: 40)
                else ...[
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          inviteUrl(code)
                              .toString()
                              .replaceFirst('https://', ''),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: context.ink, fontSize: 15),
                        ),
                      ),
                      IconButton(
                        tooltip: _copied ? 'Link copied' : 'Copy link',
                        onPressed: _copy,
                        icon: AppIcon(
                          icon: _copied
                              ? HugeIconsStrokeRounded.tick02
                              : HugeIconsStrokeRounded.copy01,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'OR THE CODE',
                          style: TextStyle(
                            color: context.muted,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            letterSpacing: 1,
                          ),
                        ),
                      ),
                      InviteCodeBoxes(code: code, size: 38),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        NotifySwitchCard(
          title: 'Tell me when they join',
          subtitle: 'And when they check in',
          value: _notify,
          onChanged: (value) => setState(() => _notify = value),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: TextStyle(color: context.errorInk)),
        ],
      ],
      footer: [
        Builder(
          builder: (anchor) => AppButton(
            key: const ValueKey('share-invite'),
            label: 'SHARE INVITE LINK',
            icon: HugeIconsStrokeRounded.share08,
            color: WeekPactColors.mintGreen,
            height: 56,
            isLoading: _busy,
            onPressed: code == null ? null : () => _share(anchor),
          ),
        ),
        const SizedBox(height: 4),
        TextButton(
          key: const ValueKey('invite-later'),
          onPressed: _busy ? null : widget.onDone,
          style: TextButton.styleFrom(foregroundColor: context.muted),
          child: const Text('I’ll do it later'),
        ),
      ],
    );
  }
}

/// The end of the setup: the pact, and the first check-in one tap away.
class FirstCheckInPage extends StatefulWidget {
  const FirstCheckInPage({
    super.key,
    required this.crew,
    required this.pact,
    required this.homeBackend,
    required this.userId,
    required this.firstName,
    required this.onDone,
  });

  final CrewDetails crew;
  final CrewPact pact;
  final HomeBackend homeBackend;
  final String userId;
  final String firstName;
  final VoidCallback onDone;

  @override
  State<FirstCheckInPage> createState() => _FirstCheckInPageState();
}

class _FirstCheckInPageState extends State<FirstCheckInPage> {
  bool _busy = false;
  String? _error;

  Future<void> _checkIn() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final week = await widget.homeBackend.fetchWeek(widget.crew.id);
      final checked = week.checkedToday(widget.userId)..add(widget.pact.id);
      await widget.homeBackend.saveCheckIns(
        crewId: widget.crew.id,
        today: week.today,
        pactIds: checked,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('First step, done. Here’s to a good week!'),
        ),
      );
      widget.onDone();
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not check in. Please retry.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pact = widget.pact;
    final name = widget.firstName.trim();
    return OnboardingScaffold(
      eyebrow: 'WEEK 1 · DAY 1',
      title: name.isEmpty ? 'You’re in.' : 'You’re in, $name.',
      subtitle: 'Your first week starts today. Done it already?',
      body: [
        AppSurface(
          fillColor: WeekPactColors.pactTint(0),
          resolveTone: false,
          builder: (context) => Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    PactIconBadge(
                      icon: PactIcon.find(pact.iconKey).data,
                      tint: WeekPactColors.pactBadge(0),
                      size: 48,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            pact.title,
                            style: const TextStyle(
                              color: WeekPactColors.black,
                              fontSize: 20,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            '${widget.crew.name.toUpperCase()} · '
                            '${pact.daysPerWeek >= 7 ? 'EVERY DAY' : '${pact.daysPerWeek}× A WEEK'}',
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
                const SizedBox(height: 18),
                AppButton(
                  key: const ValueKey('first-check-in'),
                  label: 'I DID IT TODAY',
                  icon: HugeIconsStrokeRounded.tick02,
                  height: 56,
                  isLoading: _busy,
                  onPressed: _checkIn,
                ),
              ],
            ),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: TextStyle(color: context.errorInk)),
        ],
      ],
      footer: [
        TextButton(
          key: const ValueKey('check-in-later'),
          onPressed: _busy ? null : widget.onDone,
          style: TextButton.styleFrom(foregroundColor: context.muted),
          child: const Text('Not yet — take me to my week'),
        ),
      ],
    );
  }
}
