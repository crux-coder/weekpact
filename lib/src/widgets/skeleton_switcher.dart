import 'package:flutter/material.dart';

import '../theme/weekpact_theme.dart';

/// Swaps a page between its [skeleton] and its content without flashing
/// either one.
///
/// Every load shows the skeleton, and for at least [minimum], so a quick one
/// reads as the page arriving rather than as a blink. However the skeleton
/// is drawn, it shows as one flat tone: see [SkeletonSilhouette].
///
/// Nothing crossfades: what leaves is gone at once, and what arrives fades in
/// while growing from [zoom] to full size, so it comes into focus where it
/// stands rather than showing through the skeleton.
///
/// It sizes itself to whatever stands in it, so it works both in a page of
/// fixed height and inside a scroll view.
class SkeletonSwitcher extends StatefulWidget {
  const SkeletonSwitcher({
    super.key,
    required this.skeleton,
    required this.child,
    this.minimum = const Duration(milliseconds: 400),
    this.fade = const Duration(milliseconds: 450),
    this.zoom = .98,
    this.onShown,
  });

  final Widget skeleton;

  /// The page itself, or null while it is still loading.
  final Widget? child;
  final Duration minimum;
  final Duration fade;

  /// The scale the arriving page starts from.
  final double zoom;

  /// Called each time the skeleton gives way to the page, once the page is
  /// laid out — for a page that measures itself, such as a list that loads
  /// more once it is short of the screen, which a skeleton is not a fair
  /// measure of.
  final VoidCallback? onShown;

  @override
  State<SkeletonSwitcher> createState() => _SkeletonSwitcherState();
}

class _SkeletonSwitcherState extends State<SkeletonSwitcher>
    with SingleTickerProviderStateMixin {
  static const _skeletonKey = ValueKey('skeleton-switcher-skeleton');

  bool _showingSkeleton = false;

  /// Runs for the skeleton's [SkeletonSwitcher.minimum]. A ticker rather
  /// than a timer: the skeleton is on screen and drawing through it, so the
  /// frames run on to the moment it may go.
  late final _minimum =
      AnimationController(vsync: this, duration: widget.minimum)
        ..addStatusListener((status) {
          if (status == AnimationStatus.completed &&
              _showingSkeleton &&
              widget.child != null) {
            setState(() => _showingSkeleton = false);
            _announceShown();
          }
        });

  @override
  void initState() {
    super.initState();
    if (widget.child == null) _showSkeleton();
  }

  @override
  void didUpdateWidget(covariant SkeletonSwitcher oldWidget) {
    super.didUpdateWidget(oldWidget);
    final loading = widget.child == null;
    if (loading == (oldWidget.child == null)) return;
    if (loading) {
      if (!_showingSkeleton) _showSkeleton();
    } else if (_showingSkeleton && _minimum.isCompleted) {
      // Otherwise the page waits for the minimum to run out.
      _showingSkeleton = false;
      _announceShown();
    }
  }

  void _showSkeleton() {
    _showingSkeleton = true;
    _minimum.forward(from: 0);
  }

  void _announceShown() {
    if (widget.onShown == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onShown?.call();
    });
  }

  @override
  void dispose() {
    _minimum.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final child = widget.child;
    final shown = _showingSkeleton || child == null ? widget.skeleton : child;
    // The content's own key, wrapped so a finder for it finds the content
    // alone: content with a new key is a new page, and fades in over the old.
    final key = identical(shown, widget.skeleton)
        ? _skeletonKey
        : ValueKey<Key?>(shown.key);
    return AnimatedSwitcher(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : widget.fade,
      switchInCurve: Curves.easeOutCubic,
      // Only the arrival is drawn: what it replaces leaves at once rather
      // than fading under it.
      layoutBuilder: (current, previous) => current ?? const SizedBox.shrink(),
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween(begin: widget.zoom, end: 1.0).animate(animation),
          child: child,
        ),
      ),
      child: KeyedSubtree(
        key: key,
        child: identical(shown, widget.skeleton)
            ? SkeletonSilhouette(child: shown)
            : shown,
      ),
    );
  }
}

/// Draws [child] as a silhouette in the skeleton's one tone — the faint ink
/// a [SkeletonBar] is drawn in — whatever colours it was built with.
///
/// Skeletons stand cards, bands and badges in at their real size, and drawn
/// in their real fills they read as a half-loaded page in the wrong colours.
/// As one tone they read as what they are: the page's shape, waiting.
class SkeletonSilhouette extends StatelessWidget {
  const SkeletonSilhouette({super.key, required this.child});

  final Widget child;

  /// How strongly the tone shows, as on a [SkeletonBar].
  static const strength = .14;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: strength,
      // Then that shape takes the ink's colour.
      child: ColorFiltered(
        colorFilter: ColorFilter.mode(context.ink, BlendMode.srcIn),
        // First, anything drawn at all is drawn solid, so a bar on a card
        // and the card are one shape rather than two shades.
        child: ColorFiltered(
          colorFilter: const ColorFilter.matrix([
            0, 0, 0, 0, 0, //
            0, 0, 0, 0, 0, //
            0, 0, 0, 0, 0, //
            0, 0, 0, 40, 0, //
          ]),
          child: child,
        ),
      ),
    );
  }
}
