import '../widgets/avatar_shape.dart';

import 'package:hugeicons/styles/stroke_rounded.dart';

import '../widgets/app_icon.dart';

import 'package:hugeicons/hugeicons.dart';
import 'package:flutter/material.dart';

import '../theme/weekpact_theme.dart';
import '../widgets/app_components.dart';
import 'crew_backend.dart';

/// The track every crew row is drawn as: the same squircle, outline and raised
/// edge a pact bar uses, so the two lists read as one family.
class CrewBand extends StatelessWidget {
  const CrewBand({
    super.key,
    required this.builder,
    this.fillColor,
    this.resolveTone = true,
  });

  /// Built inside the surface, so `context.ink` and `context.muted` resolve
  /// against the pale card rather than the page's canvas theme.
  final WidgetBuilder builder;
  final Color? fillColor;
  final bool resolveTone;

  @override
  Widget build(BuildContext context) => AppSurface(
    fillColor: fillColor,
    resolveTone: resolveTone,
    borderRadius: WeekPactMetrics.cardCorner,
    builder: (context) => ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 56),
      child: builder(context),
    ),
  );
}

/// The crew as a stack of name bands: one pill per person, read top to bottom,
/// rather than a grid of square portraits.
class CrewRoster extends StatelessWidget {
  const CrewRoster({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final (index, child) in children.indexed) ...[
        if (index > 0) const SizedBox(height: 8),
        child,
      ],
    ],
  );
}

/// The overlapping faces above the roster: who is here, before the names.
class CrewAvatarStack extends StatelessWidget {
  const CrewAvatarStack({super.key, required this.members, this.limit = 5});
  final List<CrewMember> members;
  final int limit;

  @override
  Widget build(BuildContext context) {
    final shown = members.take(limit).toList();
    final hidden = members.length - shown.length;
    final faces = shown.length + (hidden > 0 ? 1 : 0);
    if (faces == 0) return const SizedBox.shrink();
    return SizedBox(
      height: 34,
      // Faces overlap by a third, so the stack is as wide as the last one's
      // offset plus a whole face. A Row leaves its width unbounded.
      width: (faces - 1) * 24 + 34,
      child: Stack(
        children: [
          for (final (index, member) in shown.indexed)
            Positioned(
              left: index * 24,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: context.canvas,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: SizedBox.square(
                  dimension: 30,
                  child: CrewFace(member: member),
                ),
              ),
            ),
          if (hidden > 0)
            Positioned(
              left: shown.length * 24,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: context.canvas,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: SizedBox.square(
                  dimension: 30,
                  child: AvatarClip(
                    child: ColoredBox(
                      color: WeekPactColors.stone,
                      child: Center(
                        child: Text(
                          '+$hidden',
                          style: const TextStyle(
                            color: WeekPactColors.black,
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A member's photo, or the first letter of their name when there is none.
class CrewFace extends StatelessWidget {
  const CrewFace({super.key, required this.member, this.fontSize = 16});
  final CrewMember member;
  final double fontSize;

  String get _name => member.displayName?.trim().isNotEmpty == true
      ? member.displayName!.trim()
      : 'Crew member';

  Widget _initial(BuildContext context) => ColoredBox(
    color: WeekPactColors.black.withValues(alpha: .10),
    child: Center(
      child: Text(
        _name == 'Crew member' ? '?' : _name.characters.first.toUpperCase(),
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.w800,
          color: WeekPactColors.black,
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => AvatarClip(
    child: member.avatarUrl?.trim().isNotEmpty != true
        ? _initial(context)
        : Image.network(
            member.avatarUrl!,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            frameBuilder: (context, child, frame, synchronous) =>
                synchronous || frame != null ? child : _initial(context),
            errorBuilder: (context, error, stack) => _initial(context),
          ),
  );
}

class CrewPersonBand extends StatelessWidget {
  const CrewPersonBand({
    super.key,
    required this.member,
    required this.isCurrentUser,
    required this.color,
    this.onRemove,
  });
  final CrewMember member;
  final bool isCurrentUser;
  final Color color;
  final VoidCallback? onRemove;

  String get _name => member.displayName?.trim().isNotEmpty == true
      ? member.displayName!.trim()
      : 'Crew member';

  String get _role => member.isOwner ? 'OWNER' : 'MEMBER';

  Widget _roleLabel(BuildContext context) => Text(
    _role,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    // Colour is the only thing marking your own band, which a screen reader
    // cannot read out.
    semanticsLabel: isCurrentUser ? 'You, ${_role.toLowerCase()}' : _role,
    style: TextStyle(
      color: context.muted,
      fontSize: 11,
      letterSpacing: .8,
      fontWeight: FontWeight.w800,
    ),
  );

  @override
  Widget build(BuildContext context) {
    // Past a large text scale the name and the role cannot share a line
    // without one of them losing most of its characters, so the role drops
    // under the name instead of squeezing it.
    final stacked = MediaQuery.textScalerOf(context).scale(1) > 1.3;
    return CrewBand(
      fillColor: color,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
        child: Row(
          children: [
            SizedBox.square(dimension: 40, child: CrewFace(member: member)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Tooltip(
                    message: _name,
                    child: Text(
                      _name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (stacked) _roleLabel(context),
                ],
              ),
            ),
            if (!stacked) ...[const SizedBox(width: 10), _roleLabel(context)],
            // The slot and its gap are held whether or not the row has a
            // button, so every role label lines up down the roster and none of
            // them runs under the button.
            const SizedBox(width: 12),
            SizedBox.square(
              dimension: 30,
              child: onRemove == null
                  ? null
                  // A raised disc with a person-minus glyph: the one control on
                  // the band says what it does, where three dots said only
                  // that something was hidden behind them. It carries the same
                  // outline and edge as every other surface, so it reads as a
                  // button sitting on the band.
                  : AppSurface(
                      fillColor: context.ink,
                      resolveTone: false,
                      shape: const CircleBorder(),
                      builder: (_) => IconButton(
                        tooltip: 'Remove $_name',
                        onPressed: onRemove,
                        padding: EdgeInsets.zero,
                        icon: AppIcon(
                          icon: HugeIconsStrokeRounded.userMinus01,
                          color: color,
                          size: 15,
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The one band that is not a person: ink-filled, so adding someone reads as
/// the end of the stack rather than another member of it.
class CrewInviteBand extends StatelessWidget {
  const CrewInviteBand({super.key, this.onPressed});
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => CrewBand(
    fillColor: WeekPactColors.black,
    resolveTone: false,
    builder: (context) => InkWell(
      onTap: onPressed,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 16, 8),
        child: Row(
          children: [
            Container(
              decoration: const BoxDecoration(
                color: WeekPactColors.cream,
                shape: BoxShape.circle,
              ),
              child: const Padding(
                padding: EdgeInsets.all(9),
                child: HugeIcon(
                  icon: HugeIconsStrokeRounded.add01,
                  size: 22,
                  color: WeekPactColors.black,
                ),
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'INVITE SOMEONE',
                style: TextStyle(
                  color: WeekPactColors.cream,
                  fontSize: 17,
                  letterSpacing: .4,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
