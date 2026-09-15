import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:hugeicons/styles/stroke_rounded.dart';

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

  static const height = 60.0;
  final CrewWeek week;
  final String userId;
  final DateTime? now;
  final VoidCallback? onOpen;
  final double expansion;
  final double expandedHeight;
  final Widget? history;

  @override
  Widget build(BuildContext context) {
    const background = WeekPactColors.activitySurface;
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
              color: background,
              child: Ink(
                child: InkWell(
                  onTap: open,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    child: LayoutBuilder(
                      builder: (context, space) => Row(
                        children: [
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: homeInk.withValues(alpha: .12),
                                  blurRadius: 8,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: ClipOval(
                              key: const ValueKey('activity-avatar'),
                              child: !hasActivity
                                  ? const ColoredBox(
                                      color: Color(0xFF3B3D3B),
                                      child: Padding(
                                        padding: EdgeInsets.all(6),
                                        child: HugeIcon(
                                          icon: HugeIconsStrokeRounded.zap,
                                          color: WeekPactColors.darkInk,
                                          size: 20,
                                        ),
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
                                      const Text(
                                        'LATEST ACTIVITY',
                                        style: TextStyle(
                                          color: WeekPactColors.darkMuted,
                                          fontFamily: 'Roboto',
                                          fontSize: 9,
                                          height: 1.1,
                                          letterSpacing: 1.2,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        message,
                                        maxLines: hasActivity ? 1 : 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: WeekPactColors.darkInk,
                                          fontFamily: 'Roboto',
                                          fontFamilyFallback: ['Arial'],
                                          fontSize: 14,
                                          height: 1.2,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      if (detail != null) ...[
                                        const SizedBox(height: 2),
                                        Text(
                                          detail,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: WeekPactColors.darkMuted,
                                            fontFamily: 'Roboto',
                                            fontFamilyFallback: ['Arial'],
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
                          if (open != null) ...[
                            const SizedBox(width: 8),
                            Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: .06),
                                shape: BoxShape.circle,
                              ),
                              child: Transform.rotate(
                                angle: -math.pi / 2 * expansion,
                                child: const HugeIcon(
                                  icon: HugeIconsStrokeRounded.arrowRight01,
                                  color: WeekPactColors.darkInk,
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
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(WeekPactMetrics.cardRadius),
        child: ColoredBox(
          color: background,
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
    color: const Color(0xFF3B3D3B),
    child: Center(
      child: Text(
        member?.initials ?? '?',
        textScaler: TextScaler.noScaling,
        style: const TextStyle(
          color: WeekPactColors.darkInk,
          fontFamily: 'Roboto',
          fontFamilyFallback: ['Arial'],
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
