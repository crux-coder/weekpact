import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../widgets/app_icon.dart';

import 'package:hugeicons/styles/stroke_rounded.dart';

import '../widgets/app_components.dart';
import '../widgets/open_app_settings.dart';
import '../theme/weekpact_theme.dart';
import 'check_in_camera.dart';
import 'check_in_camera_preview.dart';
import 'check_in_gallery.dart';
import 'home_backend.dart';

typedef CheckInPhotoCapture = Future<Uint8List?> Function();

/// The photo check-in, as two pages on the stack: the camera, then the
/// picture with "Check in" under it. Completes with whether the check-in was
/// saved.
Future<bool> showPhotoCheckIn({
  required BuildContext context,
  required HomeBackend backend,
  required String userId,
  required String crewId,
  required String pactId,
  required String pactTitle,
  required int daysKept,
  required int daysPerWeek,
  required String today,
  required Set<String> selectedPactIds,
  CheckInPhotoCapture? capturePhoto,
  CheckInPhotoCapture pickPhoto = pickCheckInPhoto,
  OpenAppSettings openSettings = openAppSettings,
}) async {
  return await presentPhotoCheckIn<bool>(
        context,
        (_) => PhotoCheckInPage(
          pactTitle: pactTitle,
          daysKept: daysKept,
          daysPerWeek: daysPerWeek,
          capturePhoto: capturePhoto,
          pickPhoto: pickPhoto,
          openSettings: openSettings,
          save: (bytes) => backend.saveCheckIns(
            crewId: crewId,
            today: today,
            pactIds: selectedPactIds,
            photos: {pactId: bytes},
          ),
        ),
      ) ??
      false;
}

/// Pushes the first page of a photo flow — the camera — as a page of its own,
/// rising from the bottom the way a task you can put away does. Each step
/// after it is pushed on top, so back is always the step before. Completes
/// with what the last step finished with, or null when the flow was put away.
Future<T?> presentPhotoCheckIn<T>(
  BuildContext context,
  WidgetBuilder builder,
) => Navigator.of(context)
    .push<T>(MaterialPageRoute<T>(fullscreenDialog: true, builder: builder));

/// A photo check-in's first page: the camera, with the week's progress on the
/// pact under it. A picture taken here opens [PhotoCheckInReviewPage] on top.
class PhotoCheckInPage extends StatelessWidget {
  const PhotoCheckInPage({
    super.key,
    required this.pactTitle,
    this.daysKept = 0,
    this.daysPerWeek = 0,
    this.capturePhoto,
    this.pickPhoto = pickCheckInPhoto,
    required this.save,
    this.openSettings = openAppSettings,
  });
  final String pactTitle;

  /// Days of this pact already kept this week, today not counted: the
  /// picture being taken is what adds today.
  final int daysKept;

  /// The pact's target for the week. Zero hides the progress readout.
  final int daysPerWeek;
  final CheckInPhotoCapture pickPhoto;
  final CheckInPhotoCapture? capturePhoto;
  final Future<void> Function(Uint8List) save;
  final OpenAppSettings openSettings;

  @override
  Widget build(BuildContext context) => CameraStep<bool>(
    title: pactTitle,
    closeTooltip: 'Close photo check-in',
    capturePhoto: capturePhoto,
    pickPhoto: pickPhoto,
    openSettings: openSettings,
    footer: _WeekProgress(kept: daysKept, target: daysPerWeek),
    next: (context, photo) => Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => PhotoCheckInReviewPage(
          pactTitle: pactTitle,
          photo: photo,
          save: save,
        ),
      ),
    ),
  );
}

/// The camera as a page: the feed fills a rounded card, a round shutter sits
/// in it with the gallery to its left and the lens switch to its right, and
/// whatever the flow wants said about the picture sits under it.
///
/// A picture taken or chosen here is handed to [next], which pushes the step
/// after this one. When that step finishes, this page closes with its result;
/// when it is backed out of, this page is the camera again — going back is
/// how a picture is retaken. The camera is let go while another step stands
/// over it, and opened again on the way back.
class CameraStep<T> extends StatefulWidget {
  const CameraStep({
    super.key,
    required this.title,
    required this.next,
    this.closeTooltip = 'Close camera',
    this.footer,
    this.capturePhoto,
    this.pickPhoto = pickCheckInPhoto,
    this.openSettings = openAppSettings,
  });

  final String title;
  final String closeTooltip;

  /// Pushes the next step with the picture, and completes with what the flow
  /// finished with — null when that step was backed out of.
  final Future<T?> Function(BuildContext context, CapturedPhoto photo) next;

  /// Under the card while the camera is live: a check-in's week, say.
  final Widget? footer;

  /// The gallery, for a picture already taken. Null bytes mean the person
  /// backed out of the picker.
  final CheckInPhotoCapture pickPhoto;

  /// A capture of the page's own, in place of the live preview. Tests hand
  /// one in so the flow runs without a camera.
  final CheckInPhotoCapture? capturePhoto;

  /// The way into the system Settings, injected so a test can assert the door
  /// was opened. A refused camera is the one error here that trying again
  /// cannot answer.
  final OpenAppSettings openSettings;

  @override
  State<CameraStep<T>> createState() => _CameraStepState<T>();
}

class _CameraStepState<T> extends State<CameraStep<T>> {
  VoidCallback? _cameraAction;
  VoidCallback? _switchCamera;
  bool _capturing = false;
  bool _denied = false;

  /// A later step is standing over this one, so the camera is let go.
  bool _away = false;
  String? _error;

  Future<void> _capture() async {
    if (_capturing || _away) return;
    setState(() {
      _capturing = true;
      _error = null;
      _denied = false;
    });
    try {
      final photo = await widget.capturePhoto!();
      if (mounted && photo != null && photo.isNotEmpty) {
        setState(() => _capturing = false);
        await _advance(
          CapturedPhoto(preview: photo, prepare: () async => photo),
        );
      }
    } on PlatformException catch (e) {
      if (mounted) {
        final refused =
            e.code.toLowerCase().contains('access') ||
            e.code.toLowerCase().contains('permission');
        setState(() {
          _denied = refused;
          _error = refused
              ? 'Allow camera access in Settings, then try again.'
              : 'Could not open the camera. Please try again.';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Could not take a photo. Please try again on a device with a camera.',
        );
      }
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  /// A picture from the gallery goes on exactly as a shot does, and is
  /// prepared for upload the same way.
  Future<void> _pick() async {
    if (_capturing || _away) return;
    setState(() {
      _capturing = true;
      _error = null;
    });
    CapturedPhoto? picked;
    try {
      final bytes = await widget.pickPhoto();
      if (bytes != null && bytes.isNotEmpty) {
        picked = CapturedPhoto(
          preview: bytes,
          prepare: () => CheckInCamera.prepare(bytes),
        )..warm();
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not open that photo. Try another one.');
      }
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
    if (mounted && picked != null) await _advance(picked);
  }

  /// On to the next step with [photo]. Its result closes this page with it;
  /// coming back without one is a retake, and the camera opens again.
  Future<void> _advance(CapturedPhoto photo) async {
    setState(() {
      _away = true;
      _cameraAction = null;
      _switchCamera = null;
      _error = null;
    });
    final result = await widget.next(context, photo);
    if (!mounted) return;
    if (result != null) {
      Navigator.of(context).pop(result);
      return;
    }
    setState(() => _away = false);
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_capturing,
    child: Scaffold(
      backgroundColor: WeekPactColors.black,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // The feed sits in its own rounded card, inset from the edges,
            // the way a phone camera app frames it: the shutter lives inside
            // the card and whatever the flow says sits beneath it.
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(_stageRadius),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _stage(),
                      // Soft shade behind the controls, so a bright feed
                      // never swallows the pale close button, title and
                      // shutter.
                      const IgnorePointer(child: _Shade()),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _PhotoTopBar(
                            title: widget.title,
                            tooltip: widget.closeTooltip,
                            icon: HugeIconsStrokeRounded.cancel01,
                            onPressed: _capturing
                                ? null
                                : () => Navigator.of(context).maybePop(),
                          ),
                          const Spacer(),
                          if (!_denied)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                              child: _captureControls(),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            _bottomStrip(),
          ],
        ),
      ),
    ),
  );

  /// The feed, filling the card. Let go of while a later step stands over
  /// this one, so the camera is not running behind a page nobody can see.
  Widget _stage() {
    if (_away) return const ColoredBox(color: WeekPactColors.black);
    if (widget.capturePhoto == null) {
      return CheckInCameraPreview(
        onActionChanged: (action) => setState(() => _cameraAction = action),
        onSwitchChanged: (action) => setState(() => _switchCamera = action),
        onDeniedChanged: (denied) => setState(() => _denied = denied),
        onCaptured: _advance,
        onBusyChanged: (busy) => setState(() => _capturing = busy),
      );
    }
    return ColoredBox(
      color: WeekPactColors.darkCanvas,
      child: Center(
        child: _capturing
            ? const CircularProgressIndicator(color: WeekPactColors.cream)
            : const AppIcon(
                icon: HugeIconsStrokeRounded.camera01,
                size: 40,
                color: WeekPactColors.darkMuted,
              ),
      ),
    );
  }

  /// What sits under the card: the flow's own footer while the camera is
  /// live, and Settings when the camera was refused. Errors read here too,
  /// above whichever action answers them.
  Widget _bottomStrip() => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_error != null) ...[
          _PhotoError(_error!),
          const SizedBox(height: 12),
        ],
        if (_denied)
          _deniedControls()
        else
          widget.footer ?? const SizedBox(height: 8),
      ],
    ),
  );

  /// The shutter in the middle, the gallery to its left and the lens switch
  /// to its right.
  Widget _captureControls() {
    final onShutter = _capturing || _away
        ? null
        : widget.capturePhoto != null
        ? _capture
        : _cameraAction;
    return SizedBox(
      height: _ShutterButton.size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          _ShutterButton(
            key: const ValueKey('take-picture'),
            isLoading: _capturing,
            onPressed: onShutter,
          ),
          Positioned(
            left: 0,
            child: _RoundControl(
              key: const ValueKey('pick-photo'),
              tooltip: 'Choose from gallery',
              icon: HugeIconsStrokeRounded.image02,
              onPressed: _capturing ? null : _pick,
            ),
          ),
          if (_switchCamera != null)
            Positioned(
              right: 0,
              child: _RoundControl(
                tooltip: 'Switch camera',
                icon: HugeIconsStrokeRounded.cameraRotated01,
                onPressed: _capturing ? null : _switchCamera,
              ),
            ),
        ],
      ),
    );
  }

  /// A refused camera is the one failure here that the shutter cannot answer:
  /// the OS will not ask again, so a shutter that quietly reopens the camera
  /// can only fail the same way. Settings is offered as the action, with the
  /// retry kept underneath for someone who has just granted it.
  Widget _deniedControls() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      AppButton(
        key: const ValueKey('open-camera-settings'),
        label: 'OPEN SETTINGS',
        color: WeekPactColors.cream,
        foregroundColor: WeekPactColors.black,
        onPressed: _capturing ? null : () => unawaited(widget.openSettings()),
      ),
      const SizedBox(height: 8),
      AppButton(
        key: const ValueKey('retry-camera'),
        label: 'TRY AGAIN',
        color: WeekPactColors.darkSurface,
        foregroundColor: WeekPactColors.darkInk,
        onPressed: _capturing
            ? null
            : widget.capturePhoto != null
            ? _capture
            : _cameraAction,
      ),
      // A refused camera does not refuse the flow: a picture already taken
      // can still stand in for it.
      TextButton(
        key: const ValueKey('pick-photo'),
        onPressed: _capturing ? null : _pick,
        style: TextButton.styleFrom(
          foregroundColor: WeekPactColors.cream,
          disabledForegroundColor: WeekPactColors.darkMuted,
        ),
        child: const Text('CHOOSE FROM GALLERY'),
      ),
    ],
  );
}

const _stageRadius = 28.0;

/// A photo check-in's second page: the picture, full size, with "Check in"
/// under it. Back, or "Retake photo", is the camera again.
class PhotoCheckInReviewPage extends StatefulWidget {
  const PhotoCheckInReviewPage({
    super.key,
    required this.pactTitle,
    required this.photo,
    required this.save,
  });

  final String pactTitle;
  final CapturedPhoto photo;
  final Future<void> Function(Uint8List) save;

  @override
  State<PhotoCheckInReviewPage> createState() => _PhotoCheckInReviewPageState();
}

class _PhotoCheckInReviewPageState extends State<PhotoCheckInReviewPage> {
  bool _saving = false;
  String? _error;

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    Uint8List bytes;
    try {
      bytes = await widget.photo.prepared;
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Could not process the photo. Please retake it.';
        });
      }
      return;
    }
    try {
      await widget.save(bytes);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = e.toString().contains('day changed')
              ? 'The day changed. Close the camera and check in again.'
              : 'Could not save your photo check-in. Your picture is still here—try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: Scaffold(
      backgroundColor: WeekPactColors.black,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(_stageRadius),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.memory(
                        widget.photo.preview,
                        gaplessPlayback: true,
                        fit: BoxFit.cover,
                        semanticLabel: 'Your check-in photo',
                      ),
                      const IgnorePointer(child: _Shade()),
                      Align(
                        alignment: Alignment.topCenter,
                        child: _PhotoTopBar(
                          title: widget.pactTitle,
                          tooltip: 'Retake photo',
                          icon: HugeIconsStrokeRounded.arrowLeft01,
                          onPressed: _saving
                              ? null
                              : () => Navigator.of(context).maybePop(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_error != null) ...[
                    _PhotoError(_error!),
                    const SizedBox(height: 12),
                  ],
                  AppButton(
                    key: const ValueKey('submit-photo-check-in'),
                    label: 'CHECK IN',
                    color: WeekPactColors.cream,
                    foregroundColor: WeekPactColors.black,
                    isLoading: _saving,
                    onPressed: _saving ? null : _save,
                  ),
                  const SizedBox(height: 4),
                  TextButton(
                    onPressed: _saving
                        ? null
                        : () => Navigator.of(context).maybePop(),
                    style: TextButton.styleFrom(
                      foregroundColor: WeekPactColors.cream,
                      disabledForegroundColor: WeekPactColors.darkMuted,
                    ),
                    child: const Text('RETAKE PHOTO'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// The way out of a photo page, and what the page is for, across the top of
/// the card.
class _PhotoTopBar extends StatelessWidget {
  const _PhotoTopBar({
    required this.title,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String title;
  final String tooltip;
  final List<List<dynamic>> icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
    child: Row(
      children: [
        IconButton(
          tooltip: tooltip,
          onPressed: onPressed,
          color: WeekPactColors.cream,
          disabledColor: WeekPactColors.darkMuted,
          icon: AppIcon(icon: icon),
        ),
        Expanded(
          child: Text(
            title,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: WeekPactColors.cream,
            ),
          ),
        ),
        // Balances the button so the title sits in the middle.
        const SizedBox(width: 48),
      ],
    ),
  );
}

/// Shade at the card's top and foot, so a bright picture or feed never
/// swallows the pale controls laid over it.
class _Shade extends StatelessWidget {
  const _Shade();

  @override
  Widget build(BuildContext context) => const DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        stops: [0, .18, .72, 1],
        colors: [
          Color(0x99191B19),
          Color(0x00191B19),
          Color(0x00191B19),
          Color(0xB3191B19),
        ],
      ),
    ),
  );
}

class _PhotoError extends StatelessWidget {
  const _PhotoError(this.message);

  final String message;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Text(
      message,
      textAlign: TextAlign.center,
      style: const TextStyle(
        fontFamily: WeekPactType.secondary,
        fontFamilyFallback: WeekPactType.secondaryFallback,
        fontSize: 13,
        color: WeekPactColors.darkError,
      ),
    ),
  );
}

/// Where this week stands on the pact, and what today's picture does to it:
/// one segment per target day, the kept ones filled, today's lit, the rest
/// waiting. A photo check-in is the pact's own moment, so this is the one
/// place the person sees the week move under it.
class _WeekProgress extends StatelessWidget {
  const _WeekProgress({required this.kept, required this.target});

  final int kept;
  final int target;

  String get _line {
    final next = kept + 1;
    if (next < target) {
      final left = target - next;
      return 'Today makes it $next. '
          '${left == 1 ? 'One more' : '$left more'} after this.';
    }
    if (next == target) return 'Today makes it $target. That’s the week.';
    return 'Your week is already kept. This one’s a bonus.';
  }

  @override
  Widget build(BuildContext context) {
    if (target <= 0) return const SizedBox(height: 8);
    final shown = kept.clamp(0, target);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        key: const ValueKey('week-progress'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'This week',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: WeekPactColors.cream,
                ),
              ),
              Text(
                '$shown of $target ${target == 1 ? 'day' : 'days'}',
                style: const TextStyle(
                  fontFamily: WeekPactType.secondary,
                  fontFamilyFallback: WeekPactType.secondaryFallback,
                  fontSize: 13,
                  color: WeekPactColors.darkMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Semantics(
            label: '$shown of $target days kept this week',
            child: Row(
              children: [
                for (var i = 0; i < target; i++) ...[
                  if (i > 0) const SizedBox(width: 6),
                  Expanded(
                    child: Container(
                      height: 6,
                      decoration: BoxDecoration(
                        borderRadius: WeekPactMetrics.pill,
                        color: i < shown
                            ? WeekPactColors.keptDay
                            : i == shown
                            ? WeekPactColors.crewProgress
                            : WeekPactColors.darkBorder.withValues(alpha: .45),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _line,
            style: const TextStyle(
              fontFamily: WeekPactType.secondary,
              fontFamilyFallback: WeekPactType.secondaryFallback,
              fontSize: 13,
              color: WeekPactColors.darkMuted,
            ),
          ),
        ],
      ),
    );
  }
}

/// The round shutter: a pale ring around a pale disc, the way every phone
/// camera draws it, so nobody has to read a label to find it. The disc is
/// a plain circle of a fixed size, never a progress ring; the picture
/// arriving is the feedback.
class _ShutterButton extends StatelessWidget {
  const _ShutterButton({
    super.key,
    required this.onPressed,
    this.isLoading = false,
  });

  static const size = 76.0;

  final VoidCallback? onPressed;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !isLoading;
    // While the camera works the disc dims rather than turning into a
    // spinner: the shutter was pressed, and the picture is on its way.
    final color = enabled ? WeekPactColors.cream : WeekPactColors.darkMuted;
    return Semantics(
      button: true,
      enabled: enabled,
      label: 'Take picture',
      child: SizedBox.square(
        dimension: size,
        child: Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: enabled ? onPressed : null,
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: color, width: 4),
              ),
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: color,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A small dark disc with a pale glyph, for the controls beside the shutter.
class _RoundControl extends StatelessWidget {
  const _RoundControl({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final List<List<dynamic>> icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tooltip,
    onPressed: onPressed,
    style: IconButton.styleFrom(
      backgroundColor: WeekPactColors.darkSurface.withValues(alpha: .8),
      foregroundColor: WeekPactColors.cream,
      disabledForegroundColor: WeekPactColors.darkMuted,
      fixedSize: const Size.square(52),
      shape: const CircleBorder(),
    ),
    icon: AppIcon(
      icon: icon,
      color: onPressed == null
          ? WeekPactColors.darkMuted
          : WeekPactColors.cream,
    ),
  );
}
