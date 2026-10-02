import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:hugeicons/styles/stroke_rounded.dart';

import '../theme/weekpact_theme.dart';
import '../widgets/app_components.dart';
import '../widgets/app_icon.dart';
import '../widgets/page_frame.dart';
import 'notification_scope.dart';
import 'notification_service.dart';

/// Why the page is asking: what has just happened that is worth hearing about.
enum NotificationPrimerReason {
  /// The person has joined somebody else's crew, whose members will check in.
  joined,

  /// The person has just sent an invitation, and will want to hear it land.
  invited,
}

/// The one ask for notifications, in the app's own words, before the system's
/// dialog. The system asks exactly once, so the reason comes first.
///
/// Shown only at the two moments there is something to be notified about: on
/// joining a crew, and on inviting people to one. A solo crew is never asked;
/// nobody else is in it yet. "Not now" leaves Account → Notifications as the
/// way back in, and the system's own choice is left to the button.
class NotificationPrimerPage extends StatelessWidget {
  const NotificationPrimerPage({
    super.key,
    required this.crewName,
    required this.reason,
    required this.onDone,
  });

  final String crewName;
  final NotificationPrimerReason reason;
  final VoidCallback onDone;

  /// Whether the ask is worth making on this phone: notifications exist in
  /// this build, and the person has neither turned them on nor refused them.
  static bool wanted(NotificationService? service) =>
      service != null &&
      service.available &&
      !service.enabled &&
      service.permission == AuthorizationStatus.notDetermined;

  /// Puts the page over whatever is showing, when it is [wanted], and returns
  /// once it has been answered. Answers nothing, straight away, otherwise.
  static Future<void> show(
    BuildContext context, {
    required String crewName,
    required NotificationPrimerReason reason,
  }) async {
    final service = NotificationScope.maybeOf(context);
    if (!wanted(service)) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (routeContext) => NotificationPrimerPage(
          crewName: crewName,
          reason: reason,
          onDone: () => Navigator.of(routeContext).pop(),
        ),
      ),
    );
  }

  Future<void> _enable(NotificationService service) async {
    await service.enable();
    onDone();
  }

  @override
  Widget build(BuildContext context) {
    final service = NotificationScope.maybeOf(context);
    final busy = service?.busy ?? false;
    return PopScope(
      canPop: !busy,
      child: Scaffold(
        body: PageFrame(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'STAY IN THE LOOP',
                style: TextStyle(
                  color: context.muted,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 12),
              AppSurface(
                fillColor: WeekPactColors.stone,
                builder: (context) => Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 56,
                        height: 56,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: WeekPactColors.lantern,
                          borderRadius: BorderRadius.circular(
                            WeekPactMetrics.controlRadius,
                          ),
                          border: Border.all(color: WeekPactColors.black),
                        ),
                        child: AppIcon(
                          icon: HugeIconsStrokeRounded.notification02,
                          size: 32,
                          color: WeekPactColors.black,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        _title,
                        style: TextStyle(
                          color: context.ink,
                          fontSize: 34,
                          height: 1.05,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -.5,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _body,
                        style: TextStyle(
                          color: context.muted,
                          fontSize: 16,
                          height: 1.45,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              AppSurface(
                builder: (context) => Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final line in const [
                        'A crewmate checks in',
                        'Somebody claps your check-in',
                        'A friend joins the crew',
                      ]) ...[
                        Row(
                          children: [
                            AppIcon(
                              icon: HugeIconsStrokeRounded.checkmarkCircle02,
                              size: 20,
                              color: WeekPactColors.doneMark,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                line,
                                style: TextStyle(
                                  color: context.ink,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                      ],
                      Text(
                        'Nothing else. No streak alarms, no marketing.',
                        style: TextStyle(color: context.muted, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ),
              if (service?.error != null) ...[
                const SizedBox(height: 12),
                Text(
                  service!.error!,
                  style: TextStyle(color: context.errorInk),
                ),
              ],
              const SizedBox(height: 20),
              AppButton(
                label: 'TURN ON NOTIFICATIONS',
                icon: HugeIconsStrokeRounded.notification02,
                isLoading: busy,
                onPressed: service == null || busy
                    ? null
                    : () => _enable(service),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: busy ? null : onDone,
                style: TextButton.styleFrom(foregroundColor: context.muted),
                child: const Text('NOT NOW'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String get _title => switch (reason) {
    NotificationPrimerReason.joined => 'Hear it when $crewName shows up.',
    NotificationPrimerReason.invited => 'Hear it when they join.',
  };

  String get _body => switch (reason) {
    NotificationPrimerReason.joined =>
      'The crew checks in through the day. A small nudge when they do is '
          'most of what keeps a pact going.',
    NotificationPrimerReason.invited =>
      'Your link is out. Know the moment somebody joins $crewName and when '
          'they check in, without opening the app to look.',
  };
}
