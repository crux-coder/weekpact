import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../pacts/pact_icons.dart';
import '../theme/weekpact_theme.dart';
import '../widgets/app_components.dart';
import '../widgets/pact_icon_badge.dart';
import 'home_backend.dart';

/// What Home says the moment a check-in lands: where that puts you in the
/// crew's day, or for a crew of one, where the pact's week stands.
///
/// The reward for keeping a pact used to arrive later, as a clap, or not at
/// all; a habit is wired by what happens at the moment of the behaviour, so
/// this is said at once, before the week is refetched.
class CheckInMoment {
  const CheckInMoment({required this.headline});

  final String headline;

  /// Read off [week] as it stands with the check-in on [pactId] applied.
  static CheckInMoment read(
    CrewWeek week, {
    required String userId,
    required String pactId,
  }) {
    final pact = week.pacts.firstWhere((p) => p.id == pactId);
    final days = week.days(pactId, userId);
    final target = pact.daysPerWeek;
    final members = week.members.map((m) => m.id).toSet();
    final inToday = week.checkIns
        .where((i) => i.day == week.today && members.contains(i.userId))
        .map((i) => i.userId)
        .toSet()
        .length;
    return CheckInMoment(
      headline: switch (members.length) {
        <= 1 =>
          days >= target
              ? '${pact.title} done for the week.'
              : 'Day $days of $target for ${pact.title}.',
        _ when inToday <= 1 => 'First in the crew today.',
        final crew when inToday >= crew => 'The whole crew is in today.',
        _ =>
          'You and ${inToday - 1} ${inToday == 2 ? 'crewmate' : 'crewmates'} '
              'are in today.',
      },
    );
  }
}

/// The moment, put up as the app's own dialog: the pact's badge pops in over
/// a burst of the palette's confetti, with a flourish under the thumb, and
/// the headline under it. It stays until its button or a tap outside sends
/// it off.
///
/// The dialog itself arrives with the pop the pact card used to make on a
/// check-in: over four tenths of a second it swells a little past its
/// size and settles, fading in as it does, so the check-in still lands as
/// one movement rather than a cut.
Future<void> showCheckInMoment(
  BuildContext context, {
  required CheckInMoment moment,
  required int pactIndex,
  required String iconKey,
}) => showGeneralDialog<void>(
  context: context,
  barrierDismissible: true,
  barrierLabel: 'Dismiss',
  barrierColor: Colors.black54,
  transitionDuration: const Duration(milliseconds: 400),
  transitionBuilder: (context, animation, _, child) {
    final pop = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(
          begin: 0.86,
          end: 1.03,
        ).chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 60,
      ),
      TweenSequenceItem(
        tween: Tween(
          begin: 1.03,
          end: 1.0,
        ).chain(CurveTween(curve: Curves.easeInOut)),
        weight: 40,
      ),
    ]).animate(animation);
    return FadeTransition(
      opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
      child: ScaleTransition(scale: pop, child: child),
    );
  },
  pageBuilder: (context, _, _) => Dialog(
    key: const ValueKey('check-in-moment'),
    backgroundColor: Colors.transparent,
    elevation: 0,
    shape: const RoundedRectangleBorder(),
    insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
    child: AppSurface(
      fillColor: context.surface,
      builder: (context) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(22, 10, 22, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CheckInCelebration(
              key: const ValueKey('check-in-celebration'),
              pactIndex: pactIndex,
              iconKey: iconKey,
            ),
            const SizedBox(height: 6),
            Text(
              moment.headline,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: context.ink,
                fontSize: 27,
                height: 1.1,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 22),
            AppButton(label: 'NICE', onPressed: () => Navigator.pop(context)),
          ],
        ),
      ),
    ),
  ),
);

/// The pact's badge popping in at the centre of a stage, a ring rolling out
/// from under it, and confetti in the pact palette bursting up and falling
/// away. One run, when the dialog opens; the rest of the dialog stands still.
///
/// The flourish under the thumb runs off the same clock: a click as the
/// badge appears, two taps as it swells, and the heavy one as the confetti
/// goes, so the hand feels the burst the eye sees. With animations off the
/// badge simply stands there, and only the heavy tap is given.
class CheckInCelebration extends StatefulWidget {
  const CheckInCelebration({
    super.key,
    required this.pactIndex,
    required this.iconKey,
  });

  final int pactIndex;
  final String iconKey;

  static const height = 190.0;
  static const badge = 84.0;
  static const duration = Duration(milliseconds: 1900);

  /// When each tap lands, as a share of [duration], and which tap it is.
  static const taps = <(double, Future<void> Function())>[
    (0.0, HapticFeedback.selectionClick),
    (0.07, HapticFeedback.lightImpact),
    (0.13, HapticFeedback.mediumImpact),
    (0.19, HapticFeedback.heavyImpact),
  ];

  @override
  State<CheckInCelebration> createState() => _CheckInCelebrationState();
}

class _CheckInCelebrationState extends State<CheckInCelebration>
    with SingleTickerProviderStateMixin {
  late final _run = AnimationController(
    vsync: this,
    duration: CheckInCelebration.duration,
  )..addListener(_onTick);

  /// The pieces, cut once per dialog from a fixed seed, so the burst is the
  /// same shape every time rather than a different mess each check-in.
  late final List<_Piece> _pieces = _Piece.cut(
    math.Random(widget.pactIndex * 7 + 3),
  );

  int _tapped = 0;
  bool _still = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _still = MediaQuery.disableAnimationsOf(context);
    if (_still) {
      if (_run.value == 0) {
        // Marked given before the jump, or the jump's tick gives them all.
        _tapped = CheckInCelebration.taps.length;
        _run.value = 1;
        unawaited(HapticFeedback.heavyImpact().catchError((Object _) {}));
      }
    } else if (!_run.isAnimating && _run.value == 0) {
      _run.forward();
    }
  }

  void _onTick() {
    final taps = CheckInCelebration.taps;
    while (_tapped < taps.length && _run.value >= taps[_tapped].$1) {
      unawaited(taps[_tapped].$2().catchError((Object _) {}));
      _tapped++;
    }
  }

  @override
  void dispose() {
    _run.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final badge = WeekPactColors.pactBadge(widget.pactIndex);
    return SizedBox(
      height: CheckInCelebration.height,
      child: AnimatedBuilder(
        animation: _run,
        builder: (context, _) {
          final t = _run.value;
          // The badge swells past full size and settles, as the card's own
          // completion pop does, over the first third of a second.
          final pop = Curves.elasticOut.transform((t / .22).clamp(0.0, 1.0));
          return Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _BurstPainter(t: t, pieces: _pieces, ring: badge),
                ),
              ),
              Transform.scale(
                scale: 0.4 + 0.6 * pop,
                child: Opacity(
                  opacity: (t / .06).clamp(0.0, 1.0),
                  child: PactIconBadge(
                    icon: PactIcon.find(widget.iconKey).data,
                    tint: badge,
                    size: CheckInCelebration.badge,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// One piece of confetti: where it sets off, how fast and which way, what
/// colour and shape, and how it spins.
class _Piece {
  const _Piece({
    required this.angle,
    required this.speed,
    required this.color,
    required this.size,
    required this.spin,
    required this.round,
    required this.delay,
  });

  final double angle;
  final double speed;
  final Color color;
  final double size;
  final double spin;
  final bool round;

  /// A share of the run before this piece sets off, so the burst has a
  /// front and a tail rather than going as one ring.
  final double delay;

  static List<_Piece> cut(math.Random random) {
    final palette = [
      ...WeekPactColors.pactPalette,
      ...WeekPactColors.pactBadgePalette,
      WeekPactColors.gold,
    ];
    return [
      for (var i = 0; i < 44; i++)
        _Piece(
          // Up and out: everything leaves through the top half, give or
          // take, and gravity brings it back through the bottom.
          angle: -math.pi / 2 + (random.nextDouble() - .5) * math.pi * 1.5,
          speed: 160 + random.nextDouble() * 220,
          color: palette[random.nextInt(palette.length)],
          size: 6 + random.nextDouble() * 6,
          spin: (random.nextDouble() - .5) * 14,
          round: random.nextInt(3) == 0,
          delay: random.nextDouble() * .08,
        ),
    ];
  }
}

/// The ring and the confetti, drawn from the stage's centre.
class _BurstPainter extends CustomPainter {
  _BurstPainter({required this.t, required this.pieces, required this.ring});

  final double t;
  final List<_Piece> pieces;
  final Color ring;

  /// How far down the pieces fall per unit of time squared, in the stage's
  /// points; the burst is quick and the fall slower, which is what makes it
  /// read as thrown rather than sprayed.
  static const _gravity = 520.0;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = size.center(Offset.zero);
    // The ring: out from under the badge over the first half second, thinning
    // and fading as it goes.
    final ringAt = ((t - .08) / .4).clamp(0.0, 1.0);
    if (ringAt > 0 && ringAt < 1) {
      final eased = Curves.easeOutCubic.transform(ringAt);
      canvas.drawCircle(
        centre,
        CheckInCelebration.badge * .55 + eased * 70,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5 * (1 - eased) + 1
          ..color = ring.withValues(alpha: .6 * (1 - eased)),
      );
    }
    // The confetti: off at the heavy tap, over about a second and a quarter.
    const start = .19;
    const flight = .62;
    for (final piece in pieces) {
      final at = ((t - start - piece.delay) / flight).clamp(0.0, 1.0);
      if (at <= 0 || at >= 1) continue;
      final seconds = at * 1.25;
      final dx = math.cos(piece.angle) * piece.speed * seconds;
      final dy =
          math.sin(piece.angle) * piece.speed * seconds +
          _gravity * seconds * seconds / 2;
      final fade = at < .6 ? 1.0 : 1 - (at - .6) / .4;
      final paint = Paint()..color = piece.color.withValues(alpha: fade);
      canvas.save();
      canvas.translate(centre.dx + dx, centre.dy + dy);
      canvas.rotate(piece.spin * at);
      if (piece.round) {
        canvas.drawCircle(Offset.zero, piece.size / 2, paint);
      } else {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
              center: Offset.zero,
              width: piece.size,
              height: piece.size * .6,
            ),
            const Radius.circular(1.5),
          ),
          paint,
        );
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_BurstPainter old) =>
      old.t != t || old.pieces != pieces || old.ring != ring;
}
