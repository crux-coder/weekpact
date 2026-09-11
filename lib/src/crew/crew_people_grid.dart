import 'package:flutter/material.dart';

import '../theme/weekpact_theme.dart';
import '../widgets/app_components.dart';
import '../widgets/dashed_border.dart';
import 'crew_backend.dart';

/// A responsive people grid shared by the crew's populated and loading states.
class CrewPeopleGrid extends StatelessWidget {
  const CrewPeopleGrid({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns =
          constraints.maxWidth >= 340 &&
              MediaQuery.textScalerOf(context).scale(1) <= 1.3
          ? 2
          : 1;
      final side = (constraints.maxWidth - (columns - 1) * 12) / columns;
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          for (final child in children)
            SizedBox.square(dimension: side, child: child),
        ],
      );
    },
  );
}

class CrewPersonCard extends StatelessWidget {
  const CrewPersonCard({
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

  Widget _initial(BuildContext context) => Container(
    alignment: Alignment.center,
    color: context.ink.withValues(alpha: .08),
    child: Text(
      _name == 'Crew member' ? '?' : _name.characters.first.toUpperCase(),
      style: TextStyle(
        fontSize: 40,
        fontWeight: FontWeight.w700,
        color: context.ink,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => AppSurface(
    fillColor: color,
    builder: (context) => Stack(
      children: [
        Positioned.fill(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 20, 12, 12),
            child: Column(
              children: [
                Expanded(
                  child: Center(
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: ClipOval(
                        child: member.avatarUrl?.trim().isNotEmpty != true
                            ? _initial(context)
                            : Image.network(
                                member.avatarUrl!,
                                fit: BoxFit.cover,
                                gaplessPlayback: true,
                                frameBuilder:
                                    (context, child, frame, synchronous) =>
                                        synchronous || frame != null
                                        ? child
                                        : _initial(context),
                                errorBuilder: (context, error, stack) =>
                                    _initial(context),
                              ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Tooltip(
                  message: _name,
                  child: Text(
                    _name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${isCurrentUser ? 'You · ' : ''}${member.isOwner ? 'Owner' : 'Member'}',
                  style: TextStyle(fontSize: 14, color: context.muted),
                ),
              ],
            ),
          ),
        ),
        if (onRemove != null)
          Positioned(
            top: 0,
            right: 0,
            child: IconButton(
              tooltip: 'Remove $_name',
              onPressed: onRemove,
              icon: const Icon(Icons.more_horiz, size: 22),
            ),
          ),
      ],
    ),
  );
}

class CrewInviteTile extends StatelessWidget {
  const CrewInviteTile({super.key, this.onPressed});
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => DashedBorder(
    color: WeekPactColors.cream.withValues(alpha: .8),
    radius: WeekPactMetrics.cardRadius,
    child: Material(
      color: WeekPactColors.black,
      borderRadius: BorderRadius.circular(WeekPactMetrics.cardRadius),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: const BoxDecoration(
                  color: WeekPactColors.cream,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.add,
                  size: 32,
                  color: WeekPactColors.black,
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'INVITE SOMEONE',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: WeekPactColors.cream,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
