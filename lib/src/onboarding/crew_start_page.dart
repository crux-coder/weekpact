import 'package:flutter/material.dart';
import 'package:hugeicons/styles/stroke_rounded.dart';

import '../crew/crew_backend.dart';
import '../home/home_backend.dart';
import '../home/photo_check_in_page.dart';
import '../invites/invite_link_entry.dart';
import '../pacts/pacts_backend.dart';
import '../theme/weekpact_theme.dart';
import '../widgets/app_components.dart';
import '../widgets/app_icon.dart';
import '../widgets/app_sheet.dart';
import '../widgets/page_frame.dart';
import 'crew_setup_page.dart';

/// The one fork in onboarding, asked as a question rather than offered as a
/// setting: a link somebody sent, people to invite, or nobody yet.
///
/// The link comes first because it is how most people arrive. "Just me" is
/// a real answer that makes a one-person crew, not a way of skipping: the
/// week still needs a crew to run in, and friends can fill the seats later.
class CrewStartPage extends StatelessWidget {
  const CrewStartPage({
    super.key,
    required this.crewBackend,
    required this.pactsBackend,
    required this.homeBackend,
    required this.userId,
    required this.onDone,
    this.onInviteToken,
    this.firstName = '',
    this.captureCheckInPhoto,
  });

  final CrewBackend crewBackend;
  final PactsBackend pactsBackend;
  final HomeBackend homeBackend;
  final String userId;
  final String firstName;
  final CheckInPhotoCapture? captureCheckInPhoto;

  /// Called once the person has chosen and finished (or walked away from)
  /// setup, so whoever shows this page can show Home instead.
  final VoidCallback onDone;

  /// Handed a pasted invite's token. Null where nobody upstream can act on
  /// one, in which case the link option is not offered.
  final ValueChanged<String>? onInviteToken;

  Future<void> _pasteLink(BuildContext context) async {
    final token = await showAppSheet<String>(
      context: context,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          20,
          20,
          20 + MediaQuery.viewInsetsOf(sheetContext).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Got a link?',
              style: TextStyle(
                color: context.ink,
                fontSize: 24,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 16),
            InviteLinkEntry(
              buttonLabel: 'FIND MY CREW',
              onToken: (token) => Navigator.pop(sheetContext, token),
            ),
          ],
        ),
      ),
    );
    if (token != null) onInviteToken!(token);
  }

  Future<void> _setUp(BuildContext context, {required bool solo}) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CrewSetupPage(
          crewBackend: crewBackend,
          pactsBackend: pactsBackend,
          homeBackend: homeBackend,
          userId: userId,
          captureCheckInPhoto: captureCheckInPhoto,
          solo: solo,
        ),
      ),
    );
    onDone();
  }

  @override
  Widget build(BuildContext context) {
    final name = firstName.trim();
    return Scaffold(
      body: PageFrame(
        header: Text(
          'WeekPact.',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w700,
            color: context.ink,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              name.isEmpty
                  ? 'Who are you doing this with?'
                  : 'Who are you doing this with, $name?',
              style: TextStyle(
                color: context.ink,
                fontSize: 34,
                height: 1.05,
                fontWeight: FontWeight.w700,
                letterSpacing: -.5,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Pacts are kept in a crew. Pick how yours starts.',
              style: TextStyle(color: context.muted, fontSize: 16),
            ),
            const SizedBox(height: 24),
            if (onInviteToken != null) ...[
              _StartOption(
                key: const ValueKey('start-link'),
                icon: HugeIconsStrokeRounded.link01,
                color: WeekPactColors.mintGreen,
                title: 'I’ve got a link',
                subtitle: 'Someone invited me to their crew.',
                onTap: () => _pasteLink(context),
              ),
              const SizedBox(height: 10),
            ],
            _StartOption(
              key: const ValueKey('start-people'),
              icon: HugeIconsStrokeRounded.userGroup,
              color: WeekPactColors.stone,
              title: 'I’ve got people',
              subtitle: 'Start a crew, then send them the link.',
              onTap: () => _setUp(context, solo: false),
            ),
            const SizedBox(height: 10),
            _StartOption(
              key: const ValueKey('start-solo'),
              icon: HugeIconsStrokeRounded.user,
              color: WeekPactColors.lavender,
              title: 'Just me, for now',
              subtitle: 'Friends can join any time.',
              onTap: () => _setUp(context, solo: true),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: onDone,
              style: TextButton.styleFrom(foregroundColor: context.muted),
              child: const Text('Skip for now'),
            ),
          ],
        ),
      ),
    );
  }
}

class _StartOption extends StatelessWidget {
  const _StartOption({
    super.key,
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final List<List<dynamic>> icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => AppSurface(
    builder: (context) => InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(
                  WeekPactMetrics.controlRadius,
                ),
                border: Border.all(color: WeekPactColors.black),
              ),
              child: Center(
                child: AppIcon(
                  icon: icon,
                  size: 24,
                  color: WeekPactColors.black,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: context.ink,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(color: context.muted, fontSize: 14),
                  ),
                ],
              ),
            ),
            AppIcon(
              icon: HugeIconsStrokeRounded.arrowRight01,
              size: 20,
              color: context.muted,
            ),
          ],
        ),
      ),
    ),
  );
}
