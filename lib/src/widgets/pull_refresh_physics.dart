import 'package:flutter/widgets.dart';

/// The scroll physics of a page that refreshes on a pull: the page itself
/// comes down under the finger, as an iOS list does, rather than standing
/// still while only the indicator moves. It springs back a little firmer
/// than the default bounce, so a refresh lets go of the page briskly.
///
/// With animations turned off the page stands still and only the indicator
/// shows, which is [refreshPhysics]'s other answer.
class PullRefreshPhysics extends BouncingScrollPhysics {
  const PullRefreshPhysics({super.parent});

  @override
  PullRefreshPhysics applyTo(ScrollPhysics? ancestor) =>
      PullRefreshPhysics(parent: buildParent(ancestor));

  @override
  SpringDescription get spring =>
      SpringDescription.withDampingRatio(mass: 1, stiffness: 220, ratio: .75);
}

/// The physics for a pull-to-refresh page in [context]: [PullRefreshPhysics],
/// or a page that does not move when the system asks for less motion.
ScrollPhysics refreshPhysics(BuildContext context) =>
    MediaQuery.disableAnimationsOf(context)
    ? const AlwaysScrollableScrollPhysics(parent: ClampingScrollPhysics())
    : const PullRefreshPhysics(parent: AlwaysScrollableScrollPhysics());
