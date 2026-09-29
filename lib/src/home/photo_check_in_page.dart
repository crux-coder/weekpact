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

/// Opens the camera as a full-height drawer and completes with whether the
/// check-in was saved.
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
  return await presentPhotoCheckIn(
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

/// The drawer the camera comes up in: the full height under the status bar,
/// pulled down to dismiss like any other sheet. Completes once the drawer is
/// gone, not merely popped, so what follows it does not play behind it.
Future<bool?> presentPhotoCheckIn(
  BuildContext context,
  WidgetBuilder builder,
) async {
  ModalRoute<bool>? route;
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: WeekPactColors.black,
    barrierColor: WeekPactColors.barrier,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(WeekPactMetrics.sheetRadius),
      ),
    ),
    clipBehavior: Clip.antiAlias,
    constraints: BoxConstraints.tightFor(
      width: MediaQuery.sizeOf(context).width,
    ),
    builder: (context) {
      route ??= ModalRoute.of<bool>(context);
      return FractionallySizedBox(heightFactor: 1, child: builder(context));
    },
  );
  await route?.completed;
  return result;
}

/// The photo check-in as a camera, not a form: the feed fills the screen, a
/// round shutter sits under it with the lens switch to its right, and the
/// picture then takes the feed's place, full size, with "Check in" under it.
class PhotoCheckInPage extends StatefulWidget {
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

  /// The gallery, for a picture already taken. Null bytes mean the person
  /// backed out of the picker.
  final CheckInPhotoCapture pickPhoto;

  /// A capture of the page's own, in place of the live preview. Tests hand
  /// one in so the flow runs without a camera.
  final CheckInPhotoCapture? capturePhoto;
  final Future<void> Function(Uint8List) save;

  /// The way into the system Settings, injected so a test can assert the door
  /// was opened. A refused camera is the one error here that trying again
  /// cannot answer.
  final OpenAppSettings openSettings;
  @override
  State<PhotoCheckInPage> createState() => _PhotoCheckInPageState();
}

class _PhotoCheckInPageState extends State<PhotoCheckInPage> {
  VoidCallback? _cameraAction;
  VoidCallback? _switchCamera;
  CapturedPhoto? _photo;
  bool _capturing = false;
  bool _saving = false;
  bool _denied = false;
  String? _error;

  bool get _busy => _capturing || _saving;

  Future<void> _capture() async {
    if (_busy || _photo != null) return;
    setState(() {
      _capturing = true;
      _error = null;
      _denied = false;
    });
    try {
      final photo = await widget.capturePhoto!();
      if (mounted && photo != null && photo.isNotEmpty) {
        setState(
          () => _photo = CapturedPhoto(
            preview: photo,
            prepare: () async => photo,
          ),
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

  /// A picture from the gallery takes the feed's place exactly as a shot
  /// does, and is prepared for upload the same way.
  Future<void> _pick() async {
    if (_busy || _photo != null) return;
    setState(() {
      _capturing = true;
      _error = null;
    });
    try {
      final bytes = await widget.pickPhoto();
      if (mounted && bytes != null && bytes.isNotEmpty) {
        setState(
          () => _photo = CapturedPhoto(
            preview: bytes,
            prepare: () => CheckInCamera.prepare(bytes),
          )..warm(),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not open that photo. Try another one.');
      }
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  Future<void> _save() async {
    final photo = _photo;
    if (photo == null || _busy) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    Uint8List bytes;
    try {
      bytes = await photo.prepared;
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

  void _retake() => setState(() {
    _photo = null;
    _cameraAction = null;
    _switchCamera = null;
    _error = null;
  });

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    // Pulling the drawer down pops it outright, past the guard above. While
    // a picture is being taken or saved the pull is claimed here instead, so
    // the drawer stays put until the work is done.
    child: GestureDetector(
      onVerticalDragStart: _busy ? (_) {} : null,
      onVerticalDragUpdate: _busy ? (_) {} : null,
      onVerticalDragEnd: _busy ? (_) {} : null,
      child: Material(
        color: WeekPactColors.black,
        child: SafeArea(
          top: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 5,
                  margin: const EdgeInsets.only(top: 8),
                  decoration: const BoxDecoration(
                    color: WeekPactColors.darkBorder,
                    borderRadius: WeekPactMetrics.pill,
                  ),
                ),
              ),
              // The feed sits in its own rounded card, inset from the edges,
              // the way a phone camera app frames it: the shutter lives inside
              // the card and the check-in actions in the strip beneath it.
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(_stageRadius),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        _stage(),
                        // Soft shade behind the controls, so a bright picture
                        // or feed never swallows the pale close button, title
                        // and shutter.
                        const IgnorePointer(
                          child: DecoratedBox(
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
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _topBar(),
                            const Spacer(),
                            if (_photo == null && !_denied)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  20,
                                  0,
                                  20,
                                  20,
                                ),
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
    ),
  );

  static const _stageRadius = 28.0;

  /// The feed, or the picture that replaced it, filling the card.
  Widget _stage() {
    final photo = _photo;
    if (photo != null) {
      return Image.memory(
        photo.preview,
        gaplessPlayback: true,
        fit: BoxFit.cover,
        semanticLabel: 'Your check-in photo',
      );
    }
    if (widget.capturePhoto == null) {
      return CheckInCameraPreview(
        onActionChanged: (action) => setState(() => _cameraAction = action),
        onSwitchChanged: (action) => setState(() => _switchCamera = action),
        onDeniedChanged: (denied) => setState(() => _denied = denied),
        onCaptured: (photo) => setState(() => _photo = photo),
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

  Widget _topBar() => Padding(
    padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
    child: Row(
      children: [
        IconButton(
          tooltip: 'Close photo check-in',
          onPressed: _busy ? null : () => Navigator.pop(context, false),
          color: WeekPactColors.cream,
          disabledColor: WeekPactColors.darkMuted,
          icon: const AppIcon(icon: HugeIconsStrokeRounded.cancel01),
        ),
        Expanded(
          child: Text(
            widget.pactTitle,
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
        // Balances the close button so the title sits in the middle.
        const SizedBox(width: 48),
      ],
    ),
  );

  /// What sits under the card: the pact while the camera is live, the
  /// check-in once there is a picture, and Settings when the camera was
  /// refused. Errors read here too, above whichever action answers them.
  Widget _bottomStrip() => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_error != null) ...[
          Semantics(
            liveRegion: true,
            child: Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: WeekPactType.secondary,
                fontFamilyFallback: WeekPactType.secondaryFallback,
                fontSize: 13,
                color: WeekPactColors.darkError,
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (_photo != null)
          _reviewControls()
        else if (_denied)
          _deniedControls()
        else
          _WeekProgress(kept: widget.daysKept, target: widget.daysPerWeek),
      ],
    ),
  );

  /// The shutter in the middle, the gallery to its left and the lens switch
  /// to its right.
  Widget _captureControls() {
    final onShutter = _busy
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
              onPressed: _busy ? null : _pick,
            ),
          ),
          if (_switchCamera != null)
            Positioned(
              right: 0,
              child: _RoundControl(
                tooltip: 'Switch camera',
                icon: HugeIconsStrokeRounded.cameraRotated01,
                onPressed: _busy ? null : _switchCamera,
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
        onPressed: _busy ? null : () => unawaited(widget.openSettings()),
      ),
      const SizedBox(height: 8),
      AppButton(
        key: const ValueKey('retry-camera'),
        label: 'TRY AGAIN',
        color: WeekPactColors.darkSurface,
        foregroundColor: WeekPactColors.darkInk,
        onPressed: _busy
            ? null
            : widget.capturePhoto != null
            ? _capture
            : _cameraAction,
      ),
      // A refused camera does not refuse the check-in: a picture already
      // taken can still stand in for it.
      TextButton(
        key: const ValueKey('pick-photo'),
        onPressed: _busy ? null : _pick,
        style: TextButton.styleFrom(
          foregroundColor: WeekPactColors.cream,
          disabledForegroundColor: WeekPactColors.darkMuted,
        ),
        child: const Text('CHOOSE FROM GALLERY'),
      ),
    ],
  );

  Widget _reviewControls() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
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
        onPressed: _saving ? null : _retake,
        style: TextButton.styleFrom(
          foregroundColor: WeekPactColors.cream,
          disabledForegroundColor: WeekPactColors.darkMuted,
        ),
        child: const Text('RETAKE PHOTO'),
      ),
    ],
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
