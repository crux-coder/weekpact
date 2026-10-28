import 'package:flutter/material.dart';

import '../crew/crew_backend.dart';
import '../crew/crew_profile.dart';
import '../crew/crew_roster.dart';
import '../home/home_backend.dart';
import '../pacts/pact_icons.dart';
import '../pacts/pacts_backend.dart';
import '../theme/weekpact_theme.dart';
import '../widgets/avatar_shape.dart';
import '../widgets/pact_icon_badge.dart';
import 'profile_history.dart';

/// One figure in the profile header: a count over what it counts.
class ProfileFigure extends StatelessWidget {
  const ProfileFigure({super.key, required this.value, required this.label});

  /// Null while the summary is loading, which keeps the figure's height.
  final int? value;
  final String label;

  @override
  Widget build(BuildContext context) => Semantics(
    label: value == null ? null : '$value $label',
    excludeSemantics: value != null,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value?.toString() ?? '–',
          style: TextStyle(
            color: context.ink,
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: context.muted, fontSize: 13),
        ),
      ],
    ),
  );
}

/// A crew in the profile's strip: a dark pill with a few of its faces and its
/// name, small enough that several fit across the page.
class ProfileCrewPill extends StatelessWidget {
  const ProfileCrewPill({
    super.key,
    required this.crew,
    required this.onTap,
    this.members,
  });

  static const height = 44.0;
  static const _faces = 3;
  static const _face = 26.0;

  final PactCrew crew;

  /// The crew's members, once its week has loaded. Until then the pill wears
  /// the crew's own picture.
  final List<WeekMember>? members;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final members = this.members;
    return Semantics(
      button: true,
      label: 'Open ${crew.name}',
      excludeSemantics: true,
      child: Material(
        color: WeekPactDarkCard.fill,
        shape: WeekPactMetrics.buttonShape.copyWith(
          side: const BorderSide(color: WeekPactDarkCard.outline),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            height: height,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(9, 0, 14, 0),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (members == null || members.isEmpty)
                    CrewAvatar(
                      name: crew.name,
                      url: crew.avatarUrl,
                      size: _face,
                    )
                  else
                    for (final (i, member) in members.take(_faces).indexed)
                      Align(
                        widthFactor: i == 0 ? 1 : .72,
                        child: _Face(member: member),
                      ),
                  const SizedBox(width: 9),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 160),
                    child: Text(
                      crew.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: WeekPactDarkCard.ink,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One face in a pill's stack: cream under the initial, ringed in the pill's
/// own fill so overlapping faces stay apart.
class _Face extends StatelessWidget {
  const _Face({required this.member});

  final WeekMember member;

  @override
  Widget build(BuildContext context) => Container(
    width: ProfileCrewPill._face + 4,
    height: ProfileCrewPill._face + 4,
    padding: const EdgeInsets.all(2),
    decoration: const ShapeDecoration(
      color: WeekPactDarkCard.fill,
      shape: AvatarShape(),
    ),
    child: AvatarClip(
      child: ColoredBox(
        color: WeekPactColors.cream,
        child: CrewFace(
          fontSize: 11,
          member: CrewMember(
            userId: member.id,
            email: member.email,
            role: 'member',
            joinedAt: DateTime(2000),
            displayName: member.displayName,
            avatarUrl: member.avatarUrl,
          ),
        ),
      ),
    ),
  );
}

/// A filter over the wall: All, or one pact with its badge.
class ProfileFilterChip extends StatelessWidget {
  const ProfileFilterChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.pact,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final ProfilePact? pact;

  @override
  Widget build(BuildContext context) {
    final pact = this.pact;
    final fill = selected
        ? WeekPactColors.cream
        : context.ink.withValues(alpha: .08);
    final ink = selected ? WeekPactColors.black : context.ink;
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: fill,
        shape: WeekPactMetrics.buttonShape,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.fromLTRB(pact == null ? 14 : 5, 5, 12, 5),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (pact != null) ...[
                  PactIconBadge(
                    icon: PactIcon.find(pact.iconKey).data,
                    tint: WeekPactColors.pactBadge(pact.pactIndex),
                    size: 22,
                    depth: 1,
                  ),
                  const SizedBox(width: 7),
                ],
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 140),
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: ink,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One check-in on the wall: its photo, or the pact's tint when it kept none,
/// with the pact's badge in the corner and the day it was kept.
class ProfileWallTile extends StatelessWidget {
  const ProfileWallTile({super.key, required this.checkIn, this.onTap});

  final ProfileCheckIn checkIn;
  final VoidCallback? onTap;

  /// A tile's outline: a story's own squircle, stepped down to a tile's curve.
  static const shape = ContinuousRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(WeekPactMetrics.panelCurve)),
  );

  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  /// `yyyy-MM-dd` as `26 Oct`.
  static String shortDay(String day) {
    final date = DateTime.tryParse(day);
    if (date == null) return day;
    return '${date.day} ${_months[date.month - 1]}';
  }

  @override
  Widget build(BuildContext context) {
    final url = checkIn.photoUrl;
    final tint = WeekPactColors.pactTint(checkIn.pactIndex);
    final icon = PactIcon.find(checkIn.iconKey).data;
    final badge = WeekPactColors.pactBadge(checkIn.pactIndex);
    final day = shortDay(checkIn.day);
    final bare = PactIconBadge(icon: icon, tint: badge, size: 36);
    return Semantics(
      button: onTap != null,
      label: '${checkIn.pactTitle}, ${checkIn.crewName}, $day',
      excludeSemantics: true,
      child: Material(
        color: tint,
        shape: shape,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (url == null)
                Center(child: bare)
              else
                Image.network(
                  url,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Center(child: bare),
                ),
              if (url != null)
                Positioned(
                  left: 6,
                  bottom: 6,
                  child: PactIconBadge(
                    icon: icon,
                    tint: badge,
                    size: 22,
                    depth: 1,
                  ),
                ),
              Positioned(
                top: 5,
                right: 7,
                child: Text(
                  day,
                  style: TextStyle(
                    color: url == null
                        ? WeekPactColors.black.withValues(alpha: .74)
                        : Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    shadows: url == null
                        ? null
                        : const [
                            Shadow(color: Color(0x99000000), blurRadius: 3),
                          ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The wall's three-wide grid, laid out in the page's own scroll rather than
/// scrolling on its own. Each tile is a story's shape, tall rather than square,
/// so a check-in reads on the wall the way it was seen in the rail.
class ProfileWallGrid extends StatelessWidget {
  const ProfileWallGrid({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
  });

  static const columns = 3;
  static const gap = 4.0;

  /// Width over height: a story's 9:16 frame.
  static const aspectRatio = 9 / 16;

  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final side = (constraints.maxWidth - gap * (columns - 1)) / columns;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [
          for (var i = 0; i < itemCount; i++)
            SizedBox(
              width: side,
              height: side / aspectRatio,
              child: itemBuilder(context, i),
            ),
        ],
      );
    },
  );
}
