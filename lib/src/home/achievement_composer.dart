import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:hugeicons/styles/stroke_rounded.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show StorageException;

import '../theme/weekpact_theme.dart';
import '../widgets/app_components.dart';
import '../widgets/app_icon.dart';
import '../widgets/page_frame.dart';
import '../widgets/squircle_button_border.dart';
import 'check_in_camera.dart';
import 'check_in_gallery.dart';
import 'home_backend.dart';
import 'photo_check_in_page.dart';
import 'stories.dart';

/// Posts a story — or an achievement — to [crewId], for the crew's rail
/// today. Completes with what was posted, or null when it was put away.
///
/// Two pages on the stack, the way a photo check-in is: the camera first, the
/// same one a check-in opens, then [StoryComposerPage] with the picture just
/// taken. Every post carries a picture, so there is no way past the camera;
/// backing out of the words is a retake, and closing the camera starts
/// nothing.
Future<Achievement?> composeAchievement({
  required BuildContext context,
  required HomeBackend backend,
  required String crewId,
  required String crewName,
  required String today,
  CheckInPhotoCapture? capturePhoto,
  CheckInPhotoCapture pickPhoto = pickCheckInPhoto,
}) => presentPhotoCheckIn<Achievement>(
  context,
  (_) => CameraStep<Achievement>(
    title: 'Post a story',
    capturePhoto: capturePhoto,
    pickPhoto: pickPhoto,
    next: (context, photo) => Navigator.of(context).push<Achievement>(
      MaterialPageRoute<Achievement>(
        builder: (_) => StoryComposerPage(
          backend: backend,
          crewId: crewId,
          crewName: crewName,
          today: today,
          photo: photo,
        ),
      ),
    ),
  ),
);

/// The second page of a post: the picture, the toggle between a plain story
/// and an achievement, and the words. Back is the camera again.
class StoryComposerPage extends StatefulWidget {
  const StoryComposerPage({
    super.key,
    required this.backend,
    required this.crewId,
    required this.crewName,
    required this.today,
    required this.photo,
  });

  final HomeBackend backend;
  final String crewId;
  final String crewName;
  final String today;

  /// The picture the camera step took, prepared for upload the way a
  /// check-in's is.
  final CapturedPhoto photo;

  @override
  State<StoryComposerPage> createState() => _StoryComposerPageState();
}

class _StoryComposerPageState extends State<StoryComposerPage> {
  final _form = GlobalKey<FormState>();
  final _text = TextEditingController();
  bool _posting = false;
  String? _error;

  /// What the post is: a win, or a plain story. Picked on the toggle above
  /// the words, and a plain story until it is.
  PostKind _kind = PostKind.story;

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

  void _retake() {
    if (!_posting) Navigator.of(context).maybePop();
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
        photo: await widget.photo.prepared,
        kind: _kind,
      );
      if (!mounted) return;
      unawaited(HapticFeedback.mediumImpact().catchError((Object _) {}));
      Navigator.pop(context, posted);
    } catch (error) {
      // What went wrong is kept for the console: "could not post" alone left
      // a refused photo and a refused post looking the same.
      debugPrint('Posting a story failed: $error');
      if (!mounted) return;
      setState(() {
        _posting = false;
        // The server caps a member's day, and says so in its own words.
        _error = switch (error.toString()) {
          final e when e.contains('five achievements') =>
            'That’s five posts today. Save the next one for tomorrow.',
          final e when e.contains('unavailable') =>
            'That photo didn’t go up. Retake it and post again.',
          _ when error is StorageException =>
            'Could not upload the photo. Try again.',
          _ => 'Could not post. Try again.',
        };
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final over = _length > Achievement.maxLength;
    return PopScope(
      canPop: !_posting,
      child: Scaffold(
        body: Form(
          key: _form,
          child: PageFrame(
            header: Row(
              children: [
                IconButton(
                  tooltip: 'Back to camera',
                  onPressed: _posting ? null : _retake,
                  icon: const AppIcon(icon: HugeIconsStrokeRounded.arrowLeft01),
                ),
                Expanded(
                  child: Text(
                    'New story',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: context.ink,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                // Balances the button so the title sits in the middle.
                const SizedBox(width: 48),
              ],
            ),
            footer: AppButton(
              key: const ValueKey('post-achievement'),
              label: _posting ? 'POSTING…' : 'POST',
              isLoading: _posting,
              onPressed: _length == 0 || over || _posting ? null : _post,
            ),
            child: Column(
              key: const ValueKey('achievement-composer'),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _PhotoPreview(
                  key: const ValueKey('achievement-photo'),
                  bytes: widget.photo.preview,
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
                            HapticFeedback.selectionClick().catchError(
                              (Object _) {},
                            ),
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
                  style: TextStyle(
                    color: context.muted,
                    fontSize: 14,
                    height: 1.35,
                  ),
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
              ],
            ),
          ),
        ),
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

/// Story or achievement, as one switch with a side for each, cut to the
/// squircle every compact control in the app wears: the chosen side slides
/// under a thumb in its own colour, carrying its own glyph, so which
/// one is on reads before the words do. The same gold and trophy, lavender
/// and camera, that the post will wear in the rail and the viewer.
class PostKindToggle extends StatelessWidget {
  const PostKindToggle({super.key, required this.value, this.onChanged});

  final PostKind value;
  final ValueChanged<PostKind>? onChanged;

  /// Story first: it is what most posts are, so it sits on the left, where
  /// the switch starts.
  static const _order = [PostKind.story, PostKind.achievement];

  static const _height = 48.0;
  static const _inset = 4.0;

  @override
  Widget build(BuildContext context) {
    final motion = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 200);
    return Container(
      height: _height,
      padding: const EdgeInsets.all(_inset),
      decoration: ShapeDecoration(
        color: context.canvas,
        shape: SquircleButtonBorder(side: BorderSide(color: context.border)),
      ),
      child: LayoutBuilder(
        builder: (context, space) {
          final half = space.maxWidth / 2;
          return Stack(
            fit: StackFit.expand,
            children: [
              // The thumb is exactly one side's box, so the side it sits
              // under is centred in it by construction rather than by eye.
              AnimatedPositioned(
                duration: motion,
                curve: Curves.easeOutCubic,
                left: value == _order.first ? 0 : half,
                top: 0,
                bottom: 0,
                width: half,
                child: AnimatedContainer(
                  duration: motion,
                  decoration: ShapeDecoration(
                    color: value.tint,
                    shape: const SquircleButtonBorder(),
                  ),
                ),
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final kind in _order)
                    Expanded(child: _side(context, kind)),
                ],
              ),
            ],
          );
        },
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
        customBorder: const SquircleButtonBorder(),
        onTap: onChanged == null || on ? null : () => onChanged!(kind),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
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
