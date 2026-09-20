import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:hugeicons/styles/stroke_rounded.dart';

import '../theme/weekpact_theme.dart';
import '../widgets/app_components.dart';

/// The one glyph a clap is drawn with, wherever it appears.
const clapIcon = HugeIconsStrokeRounded.handsClapping;

/// The colour a clap the viewer gave is drawn in. Unclapped claps stay muted,
/// so a post the viewer applauded reads at a glance.
const clapInk = WeekPactColors.softYellow;

/// The clap tally on a feed post, and the way to take a clap back.
///
/// Tapping it claps, and tapping it again unclaps — the deliberate, reversible
/// half of the gesture. Double-tapping the post is the quick half; both end in
/// the same one clap per member.
class ClapButton extends StatelessWidget {
  const ClapButton({
    super.key,
    required this.count,
    required this.clapped,
    this.onPressed,
  });

  final int count;
  final bool clapped;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final color = clapped ? clapInk : WeekPactDarkCard.muted;
    return Semantics(
      button: true,
      enabled: onPressed != null,
      checked: clapped,
      label: switch (count) {
        0 => 'Clap',
        1 => '1 clap',
        _ => '$count claps',
      },
      hint: clapped ? 'Take your clap back' : 'Clap for this check-in',
      excludeSemantics: true,
      child: InkWell(
        onTap: onPressed,
        borderRadius: WeekPactMetrics.pill,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClapPop(
                clapped: clapped,
                child: HugeIcon(icon: clapIcon, color: color, size: 20),
              ),
              if (count > 0) ...[
                const SizedBox(width: 6),
                Text(
                  '$count',
                  style: TextStyle(
                    fontFamily: WeekPactType.secondary,
                    fontFamilyFallback: WeekPactType.secondaryFallback,
                    color: color,
                    fontSize: 13,
                    height: 1.2,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A one-shot squeeze when a clap lands. Posts that arrive already clapped
/// stay still, the same way a restored check-in does.
class ClapPop extends StatefulWidget {
  const ClapPop({super.key, required this.clapped, required this.child});

  final bool clapped;
  final Widget child;

  @override
  State<ClapPop> createState() => _ClapPopState();
}

class _ClapPopState extends State<ClapPop> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  );
  late final _scale = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween(
        begin: 1.0,
        end: 1.3,
      ).chain(CurveTween(curve: Curves.easeOut)),
      weight: 40,
    ),
    TweenSequenceItem(
      tween: Tween(
        begin: 1.3,
        end: 1.0,
      ).chain(CurveTween(curve: Curves.easeInOut)),
      weight: 60,
    ),
  ]).animate(_controller);

  @override
  void didUpdateWidget(covariant ClapPop oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.clapped &&
        widget.clapped &&
        !MediaQuery.disableAnimationsOf(context)) {
      _controller.forward(from: 0);
    } else if (!widget.clapped) {
      _controller.reset();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      ScaleTransition(scale: _scale, child: widget.child);
}

/// The big clap that swells over a photo on a double tap, then fades. It is
/// feedback only — the tally underneath is what the clap actually changed.
class ClapBurst extends StatelessWidget {
  const ClapBurst({super.key, required this.animation});

  final Animation<double> animation;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final progress = animation.value;
        if (progress <= 0 || progress >= 1) return const SizedBox.shrink();
        // Swells past its size, holds, then lifts away as it fades.
        final scale =
            .6 + Curves.easeOutBack.transform(math.min(1, progress * 3)) * .5;
        final fade = progress < .6 ? 1.0 : 1 - (progress - .6) / .4;
        return Center(
          child: Opacity(
            opacity: fade.clamp(0, 1),
            child: Transform.translate(
              offset: Offset(0, -18 * math.max(0, progress - .6) / .4),
              child: Transform.scale(
                scale: scale,
                // The glyph rides on a card of its own: the same fill,
                // outline and lifted edge the post underneath is drawn with.
                child: AppSurface(
                  borderRadius: 16,
                  fillColor: WeekPactDarkCard.fill,
                  resolveTone: false,
                  builder: (context) => const Padding(
                    padding: EdgeInsets.all(12),
                    child: HugeIcon(
                      icon: clapIcon,
                      color: clapInk,
                      size: 60,
                      strokeWidth: 2,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    ),
  );
}
