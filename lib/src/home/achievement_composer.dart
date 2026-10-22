import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:hugeicons/styles/stroke_rounded.dart';

import '../theme/weekpact_theme.dart';
import '../widgets/app_components.dart';
import '../widgets/app_sheet.dart';
import 'check_in_gallery.dart';
import 'home_backend.dart';
import 'photo_check_in_page.dart';
import 'stories.dart';

/// Posts an achievement to [crewId]: a win outside any pact, for the crew's
/// rail today. Completes with what was posted, or null when it was put away.
///
/// The camera comes first, as a story's does: the same drawer a photo
/// check-in opens. Every achievement carries a picture, so there is no way
/// past it; the words follow, under the picture just taken. Put the camera
/// away and nothing is started.
Future<Achievement?> composeAchievement({
  required BuildContext context,
  required HomeBackend backend,
  required String crewId,
  required String crewName,
  required String today,
  CheckInPhotoCapture? capturePhoto,
  CheckInPhotoCapture pickPhoto = pickCheckInPhoto,
}) async {
  final photo = await takeAchievementPhoto(
    context,
    capturePhoto: capturePhoto,
    pickPhoto: pickPhoto,
  );
  if (photo == null || !context.mounted) return null;
  return showAchievementComposer(
    context: context,
    backend: backend,
    crewId: crewId,
    crewName: crewName,
    today: today,
    photo: photo,
    capturePhoto: capturePhoto,
    pickPhoto: pickPhoto,
  );
}

/// The camera drawer, for an achievement. Null when it was put away.
Future<Uint8List?> takeAchievementPhoto(
  BuildContext context, {
  CheckInPhotoCapture? capturePhoto,
  CheckInPhotoCapture pickPhoto = pickCheckInPhoto,
}) async {
  Uint8List? taken;
  final done = await presentPhotoCheckIn(
    context,
    (_) => PhotoCheckInPage(
      pactTitle: 'Post a story',
      submitLabel: 'NEXT',
      capturePhoto: capturePhoto,
      pickPhoto: pickPhoto,
      save: (bytes) async => taken = bytes,
    ),
  );
  return done == true ? taken : null;
}

/// The words step: what the achievement says, under the picture it carries.
/// The picture can still be retaken here, never taken off.
Future<Achievement?> showAchievementComposer({
  required BuildContext context,
  required HomeBackend backend,
  required String crewId,
  required String crewName,
  required String today,
  required Uint8List photo,
  CheckInPhotoCapture? capturePhoto,
  CheckInPhotoCapture pickPhoto = pickCheckInPhoto,
}) => showAppSheet<Achievement>(
  context: context,
  builder: (context) => AppSheet(
    builder: (context) => _AchievementComposer(
      backend: backend,
      crewId: crewId,
      crewName: crewName,
      today: today,
      photo: photo,
      capturePhoto: capturePhoto,
      pickPhoto: pickPhoto,
    ),
  ),
);

class _AchievementComposer extends StatefulWidget {
  const _AchievementComposer({
    required this.backend,
    required this.crewId,
    required this.crewName,
    required this.today,
    required this.photo,
    this.capturePhoto,
    this.pickPhoto = pickCheckInPhoto,
  });

  final HomeBackend backend;
  final String crewId;
  final String crewName;
  final String today;

  /// The picture the camera step took.
  final Uint8List photo;
  final CheckInPhotoCapture? capturePhoto;
  final CheckInPhotoCapture pickPhoto;

  @override
  State<_AchievementComposer> createState() => _AchievementComposerState();
}

class _AchievementComposerState extends State<_AchievementComposer> {
  final _form = GlobalKey<FormState>();
  final _text = TextEditingController();
  bool _posting = false;
  String? _error;

  /// What the post is: a win, or a plain story. Picked on the toggle above
  /// the words, and an achievement until it is.
  PostKind _kind = PostKind.achievement;

  /// The picture taken for this achievement, ready for upload. The camera
  /// prepares it exactly as it prepares a check-in's.
  late Uint8List _photo = widget.photo;

  @override
  void initState() {
    super.initState();
    _text.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  int get _length => _text.text.trim().characters.length;

  /// Back to the camera for a retake. Putting it away keeps the picture
  /// that was here.
  Future<void> _retake() async {
    if (_posting) return;
    final photo = await takeAchievementPhoto(
      context,
      capturePhoto: widget.capturePhoto,
      pickPhoto: widget.pickPhoto,
    );
    if (mounted && photo != null) setState(() => _photo = photo);
  }

  Future<void> _post() async {
    if (_posting || !(_form.currentState?.validate() ?? false)) return;
    setState(() {
      _posting = true;
      _error = null;
    });
    try {
      final posted = await widget.backend.postAchievement(
        crewId: widget.crewId,
        text: _text.text.trim(),
        today: widget.today,
        photo: _photo,
        kind: _kind,
      );
      if (!mounted) return;
      unawaited(HapticFeedback.mediumImpact().catchError((Object _) {}));
      Navigator.pop(context, posted);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _posting = false;
        // The server caps a member's day, and says so in its own words.
        _error = error.toString().contains('five achievements')
            ? 'That’s five posts today. Save the next one for tomorrow.'
            : 'Could not post. Try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final over = _length > Achievement.maxLength;
    return Form(
      key: _form,
      child: Column(
        key: const ValueKey('achievement-composer'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PhotoPreview(
            key: const ValueKey('achievement-photo'),
            bytes: _photo,
            kind: _kind,
            onRetake: _posting ? null : _retake,
          ),
          const SizedBox(height: 14),
          PostKindToggle(
            key: const ValueKey('post-kind'),
            value: _kind,
            onChanged: _posting
                ? null
                : (kind) {
                    unawaited(
                      HapticFeedback.selectionClick().catchError((Object _) {}),
                    );
                    setState(() => _kind = kind);
                  },
          ),
          const SizedBox(height: 16),
          Text(
            switch (_kind) {
              PostKind.achievement => 'What did you achieve?',
              PostKind.story => 'What’s the story?',
            },
            style: TextStyle(
              color: context.ink,
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${switch (_kind) {
              PostKind.achievement => 'A win outside your pacts.',
              PostKind.story => 'A moment from your day.',
            }} ${widget.crewName.trim().isEmpty ? 'Your crew' : widget.crewName.trim()} '
            'sees it in today’s stories, and can clap for it.',
            style: TextStyle(color: context.muted, fontSize: 14, height: 1.35),
          ),
          const SizedBox(height: 16),
          AppTextField(
            key: const ValueKey('achievement-text'),
            hint: switch (_kind) {
              PostKind.achievement => 'Climbed my first 6c',
              PostKind.story => 'Sunrise on the morning run',
            },
            controller: _text,
            minLines: 3,
            maxLines: 5,
            keyboardType: TextInputType.multiline,
            textInputAction: TextInputAction.newline,
            validator: (value) {
              final text = value?.trim() ?? '';
              if (text.isEmpty) return 'Say a few words about it.';
              if (text.characters.length > Achievement.maxLength) {
                return 'Keep it to ${Achievement.maxLength} characters.';
              }
              return null;
            },
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              '$_length / ${Achievement.maxLength}',
              style: TextStyle(
                fontFamily: WeekPactType.secondary,
                fontFamilyFallback: WeekPactType.secondaryFallback,
                fontSize: 12,
                color: over ? context.errorInk : context.muted,
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: TextStyle(color: context.errorInk, fontSize: 13),
            ),
          ],
          const SizedBox(height: 16),
          AppButton(
            key: const ValueKey('post-achievement'),
            label: _posting ? 'POSTING…' : 'POST',
            isLoading: _posting,
            onPressed: _length == 0 || over || _posting ? null : _post,
          ),
        ],
      ),
    );
  }
}

/// The picture going up with the post, large, as the story will show it,
/// with the chip its kind will wear and a way back to the camera.
class _PhotoPreview extends StatelessWidget {
  const _PhotoPreview({
    super.key,
    required this.bytes,
    required this.kind,
    this.onRetake,
  });

  final Uint8List bytes;
  final PostKind kind;
  final VoidCallback? onRetake;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 260,
    child: ClipPath(
      clipper: const ShapeBorderClipper(
        shape: ContinuousRectangleBorder(
          borderRadius: BorderRadius.all(
            Radius.circular(WeekPactMetrics.cardCurve),
          ),
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.memory(
            bytes,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            semanticLabel: 'Your achievement photo',
          ),
          Positioned(
            left: 10,
            bottom: 10,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.fromLTRB(8, 6, 12, 6),
              decoration: ShapeDecoration(
                color: kind.tint,
                shape: WeekPactMetrics.buttonShape,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  HugeIcon(
                    icon: kind.icon,
                    color: WeekPactColors.black,
                    size: 18,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    kind.label,
                    style: const TextStyle(
                      color: WeekPactColors.black,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            right: 8,
            top: 8,
            child: IconButton(
              key: const ValueKey('retake-achievement-photo'),
              tooltip: 'Retake photo',
              onPressed: onRetake,
              style: IconButton.styleFrom(
                backgroundColor: WeekPactColors.black.withValues(alpha: .6),
              ),
              icon: const HugeIcon(
                icon: HugeIconsStrokeRounded.camera01,
                color: WeekPactColors.cream,
                size: 20,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

/// Achievement or story, as one switch with a side for each: the chosen side
/// slides under a thumb in its own colour, carrying its own glyph, so which
/// one is on reads before the words do. The same gold and trophy, lavender
/// and camera, that the post will wear in the rail and the viewer.
class PostKindToggle extends StatelessWidget {
  const PostKindToggle({super.key, required this.value, this.onChanged});

  final PostKind value;
  final ValueChanged<PostKind>? onChanged;

  static const _height = 48.0;
  static const _inset = 4.0;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Container(
      height: _height,
      padding: const EdgeInsets.all(_inset),
      decoration: ShapeDecoration(
        color: context.canvas,
        shape: StadiumBorder(side: BorderSide(color: context.border)),
      ),
      child: Stack(
        children: [
          AnimatedAlign(
            duration: reduceMotion
                ? Duration.zero
                : const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            alignment: value == PostKind.achievement
                ? Alignment.centerLeft
                : Alignment.centerRight,
            child: FractionallySizedBox(
              widthFactor: .5,
              heightFactor: 1,
              child: AnimatedContainer(
                duration: reduceMotion
                    ? Duration.zero
                    : const Duration(milliseconds: 200),
                decoration: ShapeDecoration(
                  color: value.tint,
                  shape: const StadiumBorder(),
                  shadows: [
                    BoxShadow(
                      color: Color.lerp(value.tint, Colors.black, .24)!,
                      offset: const Offset(0, 1.5),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Row(
            children: [
              for (final kind in PostKind.values)
                Expanded(child: _side(context, kind)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _side(BuildContext context, PostKind kind) {
    final on = kind == value;
    final ink = on ? WeekPactColors.black : context.muted;
    return Semantics(
      button: true,
      selected: on,
      inMutuallyExclusiveGroup: true,
      label: kind.label,
      excludeSemantics: true,
      child: InkWell(
        key: ValueKey('post-kind-${kind.name}'),
        customBorder: const StadiumBorder(),
        onTap: onChanged == null || on ? null : () => onChanged!(kind),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // The unchosen side keeps its colour in its glyph, so both
            // options are colour coded before either is picked.
            HugeIcon(icon: kind.icon, color: on ? ink : kind.badge, size: 20),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                kind.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: ink,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
