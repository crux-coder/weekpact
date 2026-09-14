import 'package:flutter/material.dart';

import 'dart:math' as math;

import '../theme/weekpact_theme.dart';
import 'home_backend.dart';
import 'home_surface.dart';

/// Compact activity summary with a borderless member photo. The tooltip and
/// semantics retain the full copy when a long name or pact is truncated.
class LatestActivityRow extends StatelessWidget {
  const LatestActivityRow({
    super.key,
    required this.week,
    required this.userId,
    this.now,
    this.onOpen,
    this.expansion = 0,
    this.expandedHeight = height,
    this.history,
  });

  static const height = 64.0;
  final CrewWeek week;
  final String userId;
  final DateTime? now;
  final VoidCallback? onOpen;
  final double expansion;
  final double expandedHeight;
  final Widget? history;

  @override
  Widget build(BuildContext context) {
    final activity = week.latestActivity;
    final member = week.members
        .where((m) => m.id == activity?.userId)
        .firstOrNull;
    final pact = week.pacts.where((g) => g.id == activity?.pactId).firstOrNull;
    final hasActivity = activity != null && member != null && pact != null;
    final name = member == null || member.displayName.trim().isEmpty
        ? activity?.userId == userId
              ? 'You'
              : 'A crew member'
        : member.displayName.trim().split(RegExp(r'\s+')).first;
    final message = hasActivity
        ? '$name checked in'
        : 'Be the first to check in today';
    final age = hasActivity
        ? _age(activity.createdAt, now ?? DateTime.now())
        : null;
    final detail = hasActivity ? '${pact.title} · $age' : null;
    final fullMessage =
        'Latest activity: $message${detail == null ? '' : ' · $detail'}';
    final open = onOpen;
    final header = SizedBox(
      key: const ValueKey('latest-activity'),
      height: height,
      child: Semantics(
        label: fullMessage,
        hint: open == null
            ? null
            : expansion > 0
            ? 'Collapse activity history'
            : 'Expand activity history',
        button: open != null,
        onTap: open,
        child: Tooltip(
          message: fullMessage,
          child: ExcludeSemantics(
            child: Material(
              color: WeekPactColors.softYellow,
              child: Ink(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFFFFEBAF), WeekPactColors.softYellow],
                  ),
                ),
                child: InkWell(
                  onTap: open,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    child: LayoutBuilder(
                      builder: (context, space) => Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF6E4B12)
                                      .withValues(alpha: .24),
                                  blurRadius: 8,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: ClipOval(
                              key: const ValueKey('activity-avatar'),
                              child: !hasActivity
                                  ? const ColoredBox(
                                      color: Color(0xFFFFF3CF),
                                      child: Icon(
                                        Icons.wb_sunny_rounded,
                                        color: Color(0xFFB67B25),
                                        size: 24,
                                      ),
                                    )
                                  : member.avatarUrl == null
                                  ? _initials(member)
                                  : Image.network(
                                      member.avatarUrl!,
                                      fit: BoxFit.cover,
                                      gaplessPlayback: true,
                                      errorBuilder: (_, _, _) =>
                                          _initials(member),
                                    ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: LayoutBuilder(
                              builder: (context, space) => FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: SizedBox(
                                  width: space.maxWidth,
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        message,
                                        maxLines: hasActivity ? 1 : 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: homeInk,
                                          fontSize: 14,
                                          height: 1.2,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      if (detail != null) ...[
                                        const SizedBox(height: 4),
                                        Text(
                                          detail,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: Color(0xFF665633),
                                            fontSize: 12,
                                            height: 1.2,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                          if (hasActivity &&
                              space.maxWidth >= 340 &&
                              MediaQuery.textScalerOf(context).scale(1) <=
                                  1.3) ...[
                            const SizedBox(width: 8),
                            const SizedBox(
                              width: 48,
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.local_fire_department_rounded,
                                    size: 24,
                                    color: Color(0xFFE67D45),
                                    shadows: [
                                      Shadow(
                                        color: Color(0xFF82502B),
                                        offset: Offset(0, 1),
                                      ),
                                    ],
                                  ),
                                  SizedBox(height: 3),
                                  FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Text(
                                      'Keep it up!',
                                      textScaler: TextScaler.noScaling,
                                      style: TextStyle(
                                        color: homeInk,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                        fontStyle: FontStyle.italic,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          if (open != null) ...[
                            const SizedBox(width: 8),
                            Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: .28),
                                shape: BoxShape.circle,
                              ),
                              child: Transform.rotate(
                                angle: -math.pi / 2 * expansion,
                                child: const Icon(
                                  Icons.chevron_right_rounded,
                                  color: homeInk,
                                  size: 22,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    return Container(
      key: const ValueKey('activity-container'),
      height: height + (expandedHeight - height) * expansion,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(WeekPactMetrics.cardRadius),
        boxShadow: [
          BoxShadow(
            color: homeInk.withValues(alpha: .12),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(WeekPactMetrics.cardRadius),
        child: ColoredBox(
          color: WeekPactColors.softYellow,
          child: Column(
            children: [
              header,
              if (history != null)
                Expanded(
                  child: ClipRect(
                    child: OverflowBox(
                      alignment: Alignment.topCenter,
                      minHeight: expandedHeight - height,
                      maxHeight: expandedHeight - height,
                      child: Opacity(opacity: expansion, child: history),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _initials(WeekMember? member) => ColoredBox(
    color: const Color(0xFFE1E5DC),
    child: Center(
      child: Text(
        member?.initials ?? '?',
        textScaler: TextScaler.noScaling,
        style: const TextStyle(
          color: homeInk,
          fontSize: 16,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
  );

  String _age(DateTime createdAt, DateTime now) {
    final elapsed = now.difference(createdAt);
    if (elapsed.inMinutes < 1) return 'Just now';
    if (elapsed.inHours < 1) return '${elapsed.inMinutes}m ago';
    if (elapsed.inDays < 1) return '${elapsed.inHours}h ago';
    return '${elapsed.inDays}d ago';
  }
}
