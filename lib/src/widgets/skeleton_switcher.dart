import 'dart:async';

import 'package:flutter/material.dart';

/// Swaps a page between its [skeleton] and its content without flashing
/// either one.
///
/// A load that lands within [delay] never shows the skeleton: the page holds
/// what it last showed, untouchable, and goes straight to the new content.
/// A skeleton that does appear stays up for at least [minimum], so a load
/// finishing just past the delay does not blink it. Every swap crossfades.
class SkeletonSwitcher extends StatefulWidget {
  const SkeletonSwitcher({
    super.key,
    required this.skeleton,
    required this.child,
    this.delay = const Duration(milliseconds: 200),
    this.minimum = const Duration(milliseconds: 400),
    this.fade = const Duration(milliseconds: 200),
  });

  final Widget skeleton;

  /// The page itself, or null while it is still loading.
  final Widget? child;
  final Duration delay;
  final Duration minimum;
  final Duration fade;

  @override
  State<SkeletonSwitcher> createState() => _SkeletonSwitcherState();
}

class _SkeletonSwitcherState extends State<SkeletonSwitcher> {
  static const _skeletonKey = ValueKey('skeleton-switcher-skeleton');
  static const _contentKey = ValueKey('skeleton-switcher-content');

  /// The content last on screen, held while a short load runs.
  Widget? _held;
  bool _showingSkeleton = false;
  final _shown = Stopwatch();
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (widget.child == null) _waitForSkeleton();
  }

  @override
  void didUpdateWidget(covariant SkeletonSwitcher oldWidget) {
    super.didUpdateWidget(oldWidget);
    final loading = widget.child == null;
    if (loading == (oldWidget.child == null)) return;
    _timer?.cancel();
    if (loading) {
      if (!_showingSkeleton) _waitForSkeleton();
    } else if (_showingSkeleton) {
      final left = widget.minimum - _shown.elapsed;
      if (left > Duration.zero) {
        _timer = Timer(left, _hideSkeleton);
      } else {
        _showingSkeleton = false;
      }
    }
  }

  void _waitForSkeleton() {
    _timer = Timer(widget.delay, () {
      if (!mounted) return;
      setState(() => _showingSkeleton = true);
      _shown
        ..reset()
        ..start();
    });
  }

  void _hideSkeleton() {
    if (mounted) setState(() => _showingSkeleton = false);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final child = widget.child;
    if (child != null && !_showingSkeleton) _held = child;
    final shown = _showingSkeleton ? widget.skeleton : _held;
    return AnimatedSwitcher(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : widget.fade,
      layoutBuilder: (current, previous) =>
          Stack(fit: StackFit.expand, children: [...previous, ?current]),
      child: KeyedSubtree(
        key: _showingSkeleton ? _skeletonKey : shown?.key ?? _contentKey,
        child: IgnorePointer(
          // Held content belongs to the load being replaced: it is looked
          // at, not pressed.
          ignoring: child == null,
          child: shown ?? const SizedBox.shrink(),
        ),
      ),
    );
  }
}
