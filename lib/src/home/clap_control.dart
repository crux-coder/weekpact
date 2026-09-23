import 'package:flutter/material.dart';
import 'package:hugeicons/styles/stroke_rounded.dart';

import '../theme/weekpact_theme.dart';

/// The one glyph a clap is drawn with, wherever it appears.
const clapIcon = HugeIconsStrokeRounded.handsClapping;

/// The colour a clap the viewer gave is drawn in. Unclapped claps stay muted,
/// so a check-in the viewer applauded reads at a glance.
const clapInk = WeekPactColors.brass;

/// A one-shot squeeze when a clap lands. A story opened on a clap the
/// viewer already gave stays still, the same way a restored check-in does.
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
