import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:hugeicons/styles/stroke_rounded.dart';

import '../auth/profile_scope.dart';
import '../theme/weekpact_theme.dart';
import '../widgets/app_icon.dart';
import '../widgets/app_sheet.dart';
import '../widgets/avatar_shape.dart';
import 'clap_control.dart';
import 'home_backend.dart';

/// What sits where the clap would on your own story: the claps it has, and
/// beside them, on the page itself, the faces of whoever gave them.
///
/// You do not clap your own story, so the pill is a tally rather than a
/// button that claps. It and the faces both open the list of who saw it, the
/// way holding a chat message shows who read it.
class StoryAudienceBar extends StatelessWidget {
  const StoryAudienceBar({
    super.key,
    required this.clapCount,
    required this.audience,
    required this.onPressed,
  });

  /// The claps the story carries. Shown before the audience has loaded, and
  /// from then on the audience's own count.
  final int clapCount;

  /// Null while it is loading, or if it could not be.
  final List<StoryAudienceMember>? audience;
  final VoidCallback onPressed;

  /// How many faces the bar shows before the rest become a number.
  static const _faces = 3;

  @override
  Widget build(BuildContext context) {
    final audience = this.audience;
    final clappers = [
      for (final who in audience ?? const <StoryAudienceMember>[])
        if (who.clapped) who.member,
    ];
    final claps = audience == null ? clapCount : clappers.length;
    const ink = WeekPactDarkCard.ink;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          button: true,
          label: switch (claps) {
            0 => 'No claps yet',
            1 => '1 clap',
            _ => '$claps claps',
          },
          hint: 'Show who saw it',
          excludeSemantics: true,
          child: Material(
            key: const ValueKey('story-clap-tally'),
            color: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: WeekPactMetrics.pill,
              side: BorderSide(color: ink.withValues(alpha: .32)),
            ),
            child: InkWell(
              onTap: onPressed,
              borderRadius: WeekPactMetrics.pill,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 9,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    HugeIcon(
                      icon: clapIcon,
                      color: claps > 0 ? clapInk : WeekPactDarkCard.muted,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '$claps',
                      style: const TextStyle(
                        color: ink,
                        fontSize: 13.5,
                        height: 1.2,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (clappers.isNotEmpty) ...[
          const SizedBox(width: 10),
          Semantics(
            button: true,
            label:
                'Clapped by ${clappers.map((m) => m.displayName).join(', ')}',
            hint: 'Show who saw it',
            excludeSemantics: true,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onPressed,
              child: _FaceStack(
                key: const ValueKey('story-clappers'),
                members: clappers.take(_faces).toList(),
                more: clappers.length - _faces,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// The clappers' faces, overlapping left to right, each ringed in the page's
/// black so the edges read as separate faces rather than one blot.
class _FaceStack extends StatelessWidget {
  const _FaceStack({super.key, required this.members, required this.more});

  final List<WeekMember> members;

  /// How many clappers are left out, shown as `+n` after the last face.
  final int more;

  static const _size = 32.0;
  static const _step = 22.0;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      SizedBox(
        width: _size + _step * (members.length - 1),
        height: _size,
        child: Stack(
          children: [
            for (final (i, member) in members.indexed)
              Positioned(
                left: _step * i,
                child: Container(
                  width: _size,
                  height: _size,
                  padding: const EdgeInsets.all(2),
                  decoration: const ShapeDecoration(
                    color: WeekPactColors.black,
                    shape: AvatarShape(),
                  ),
                  child: _Face(
                    member: member,
                    size: _size - 4,
                    ink: WeekPactDarkCard.ink,
                    background: WeekPactColors.activitySurface,
                  ),
                ),
              ),
          ],
        ),
      ),
      if (more > 0) ...[
        const SizedBox(width: 6),
        Text(
          '+$more',
          style: const TextStyle(
            color: WeekPactDarkCard.muted,
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ],
  );
}

/// A crewmate's face, or their initials where they have no photo.
class _Face extends StatelessWidget {
  const _Face({
    required this.member,
    required this.size,
    required this.ink,
    required this.background,
  });

  final WeekMember member;
  final double size;
  final Color ink;
  final Color background;

  @override
  Widget build(BuildContext context) {
    final initials = Text(
      member.initials,
      style: TextStyle(
        color: ink,
        fontSize: size * .4,
        fontWeight: FontWeight.w600,
      ),
    );
    final url = member.avatarUrl;
    return FlatAvatar(
      radius: size / 2,
      backgroundColor: background,
      child: url == null || url.trim().isEmpty
          ? initials
          : Image.network(
              url,
              cacheWidth: avatarDecodeWidth,
              width: size,
              height: size,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              errorBuilder: (_, _, _) => initials,
            ),
    );
  }
}

/// Everybody who saw one of your stories, the ones who clapped first with the
/// clap beside their name — the story's counterpart of a chat message's
/// "Seen by".
Future<void> showStoryAudience(
  BuildContext context, {
  required List<StoryAudienceMember> audience,
}) => showAppSheet<void>(
  context: context,
  builder: (context) => AppSheet(
    // Dark, like the story it opens over.
    dark: true,
    builder: (context) => Column(
      key: const ValueKey('story-audience'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            audience.isEmpty ? 'Nobody has seen this yet.' : 'Seen by',
            style: TextStyle(
              color: context.muted,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            children: [
              for (final who in audience)
                _AudienceRow(
                  key: ValueKey('audience-${who.member.id}'),
                  who: who,
                ),
            ],
          ),
        ),
      ],
    ),
  ),
);

class _AudienceRow extends StatelessWidget {
  const _AudienceRow({super.key, required this.who});

  final StoryAudienceMember who;

  @override
  Widget build(BuildContext context) {
    final name = who.member.displayName.trim();
    final openProfile = ProfileScope.opener(context, who.member);
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      child: Row(
        children: [
          _Face(
            member: who.member,
            size: 32,
            ink: context.ink,
            background: context.ink.withValues(alpha: .14),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              name.isEmpty ? 'Crew member' : name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: context.ink,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          if (who.clapped)
            const HugeIcon(
              key: ValueKey('audience-clapped'),
              icon: clapIcon,
              color: clapInk,
              size: 22,
            )
          else
            AppIcon(
              icon: HugeIconsStrokeRounded.view,
              size: 18,
              color: context.muted,
            ),
        ],
      ),
    );
    return openProfile == null ? row : InkWell(onTap: openProfile, child: row);
  }
}
