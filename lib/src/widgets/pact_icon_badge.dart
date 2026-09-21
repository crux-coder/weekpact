import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

import '../theme/weekpact_theme.dart';

/// A pact's icon, on a raised squircle of the pact's own colour.
///
/// The card under it is tinted paper — deliberately too quiet to be what tells
/// two pacts apart at a glance. This is what does that: the card's own hue from
/// `WeekPactColors.pactBadge`, held deep enough to read as an object sitting on
/// the card rather than as a patch of it.
///
/// Its outline and its raised edge are mixed from [tint], the way every other
/// raised surface in the app builds its own, so the badge stays one object
/// across all ten rather than needing a second colour chosen per pact.
class PactIconBadge extends StatelessWidget {
  const PactIconBadge({
    super.key,
    required this.icon,
    required this.tint,
    this.size = 56,
    this.depth = WeekPactMetrics.controlDepth,
  });

  final List<List<dynamic>> icon;

  /// The pact's badge colour, from `WeekPactColors.pactBadge(index)`.
  final Color tint;

  /// The badge's box, its raised edge excluded. The glyph and the corner are
  /// both fixed shares of it, so one number scales the whole badge.
  final double size;
  final double depth;

  /// The glyph's share of the box: small enough that the colour reads as a
  /// face the icon sits on rather than as a ring around it.
  static const _glyphShare = .5;

  /// The badge's corner, as a share of its box. A card's corner is a share of
  /// a much larger box; holding the same ratio here keeps the badge in the
  /// card's family instead of reading as a pill.
  static const _cornerShare = .28;

  @override
  Widget build(BuildContext context) {
    final shape = ContinuousRectangleBorder(
      borderRadius: BorderRadius.circular(
        WeekPactMetrics.curveFor(size * _cornerShare),
      ),
    );
    return SizedBox.square(
      dimension: size,
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: tint,
          shape: shape.copyWith(
            side: BorderSide(color: Color.lerp(tint, Colors.black, .30)!),
          ),
          shadows: [
            BoxShadow(
              color: Color.lerp(tint, Colors.black, .24)!,
              offset: Offset(0, depth),
            ),
          ],
        ),
        child: Center(
          child: HugeIcon(
            icon: icon,
            size: size * _glyphShare,
            // Every badge clears 6:1 against card ink, so the glyph is card
            // ink on all ten — the badge never has to pick between two inks.
            color: WeekPactColors.black,
          ),
        ),
      ),
    );
  }
}
