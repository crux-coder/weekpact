import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../widgets/app_icon.dart';

import 'package:hugeicons/styles/stroke_rounded.dart';

import '../widgets/app_components.dart';
import '../widgets/app_sheet.dart';
import '../theme/weekpact_theme.dart';
import 'inline_check_in_camera.dart';
import 'check_in_photo_frame.dart';
import 'home_backend.dart';

typedef CheckInPhotoCapture = Future<Uint8List?> Function();

Future<bool> showPhotoCheckIn({
  required BuildContext context,
  required HomeBackend backend,
  required String userId,
  required String crewId,
  required String pactId,
  required String pactTitle,
  required String today,
  required Set<String> selectedPactIds,
  CheckInPhotoCapture? capturePhoto,
}) async {
  return await showAppSheet<bool>(
        context: context,
        builder: (_) => PhotoCheckInSheet(
          pactTitle: pactTitle,
          capturePhoto: capturePhoto,
          // Debug builds check in without a picture so the flow is testable on
          // simulators, which have no camera.
          saveWithoutPhoto: () => backend.saveCheckIns(
            crewId: crewId,
            today: today,
            pactIds: selectedPactIds,
          ),
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

class PhotoCheckInSheet extends StatefulWidget {
  const PhotoCheckInSheet({
    super.key,
    required this.pactTitle,
    this.capturePhoto,
    required this.save,
    this.saveWithoutPhoto,
  });
  final String pactTitle;
  final CheckInPhotoCapture? capturePhoto;
  final Future<void> Function(Uint8List) save;

  /// Debug-only escape hatch: check in with no picture at all.
  final Future<void> Function()? saveWithoutPhoto;
  @override
  State<PhotoCheckInSheet> createState() => _PhotoCheckInSheetState();
}

class _PhotoCheckInSheetState extends State<PhotoCheckInSheet> {
  VoidCallback? _cameraAction;
  Uint8List? _photo;
  bool _capturing = false;
  bool _saving = false;
  String? _error;

  Future<void> _capture() async {
    if (_capturing || _saving || _photo != null) return;
    setState(() {
      _capturing = true;
      _error = null;
    });
    try {
      final photo = await widget.capturePhoto!();
      if (mounted && photo != null && photo.isNotEmpty) {
        setState(() => _photo = photo);
      }
    } on PlatformException catch (e) {
      if (mounted) {
        setState(
          () => _error =
              e.code.toLowerCase().contains('access') ||
                  e.code.toLowerCase().contains('permission')
              ? 'Allow camera access in Settings, then try again.'
              : 'Could not open the camera. Please try again.',
        );
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

  Future<void> _skipPhoto() async {
    final skip = widget.saveWithoutPhoto;
    if (skip == null || _saving || _capturing) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await skip();
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not save the check-in. Try again.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _save() async {
    final photo = _photo;
    if (photo == null || _saving || _capturing) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.save(photo);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = e.toString().contains('day changed')
              ? 'The day changed. Close this drawer and check in again.'
              : 'Could not save your photo check-in. Your picture is still here—try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving && !_capturing,
    child: AppSheet(
      builder: (context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.pactTitle,
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Close photo check-in',
                onPressed: _saving || _capturing
                    ? null
                    : () => Navigator.pop(context, false),
                icon: const AppIcon(icon: HugeIconsStrokeRounded.cancel01),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'A quick photo for your crew.',
            style: TextStyle(
              fontFamily: WeekPactType.secondary,
              fontFamilyFallback: WeekPactType.secondaryFallback,
              fontSize: 14,
              fontWeight: FontWeight.w400,
              color: context.muted,
            ),
          ),
          const SizedBox(height: 16),
          if (widget.capturePhoto == null && _photo == null)
            InlineCheckInCamera(
              onActionChanged: (action) =>
                  setState(() => _cameraAction = action),
              onCaptured: (photo) => setState(() => _photo = photo),
              onBusyChanged: (busy) => setState(() => _capturing = busy),
            )
          else ...[
            Center(
              child: SizedBox(
                width: (MediaQuery.sizeOf(context).height * .4).clamp(
                  120.0,
                  320.0,
                ),
                child: CheckInPhotoFrame(
                  child: ColoredBox(
                    color: WeekPactColors.neutralInset,
                    child: _photo == null
                        ? Center(
                            child: _capturing
                                ? const CircularProgressIndicator()
                                : const AppIcon(
                                    icon: HugeIconsStrokeRounded.camera01,
                                    size: 40,
                                    color: WeekPactColors.mutedLight,
                                  ),
                          )
                        : Image.memory(
                            _photo!,
                            fit: BoxFit.cover,
                            semanticLabel: 'Your check-in photo',
                          ),
                  ),
                ),
              ),
            ),
          ],
          if (_photo != null) ...[
            const SizedBox(height: 12),
            TextButton(
              onPressed: _saving
                  ? null
                  : () => setState(() {
                      _photo = null;
                      _cameraAction = null;
                      _error = null;
                    }),
              child: const Text('RETAKE PHOTO'),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 8),
            Semantics(
              liveRegion: true,
              child: Text(
                _error!,
                style: TextStyle(
                  fontFamily: WeekPactType.secondary,
                  fontFamilyFallback: WeekPactType.secondaryFallback,
                  fontSize: 13,
                  color: context.errorInk,
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          _RotatingCheckInAction(
            hasPhoto: _photo != null,
            isLoading: _capturing || _saving,
            onPressed: _capturing || _saving
                ? null
                : _photo != null
                ? _save
                : widget.capturePhoto != null
                ? _capture
                : _cameraAction,
          ),
          if (kDebugMode && widget.saveWithoutPhoto != null && _photo == null)
            TextButton(
              key: const ValueKey('skip-photo-check-in'),
              onPressed: _saving || _capturing ? null : _skipPhoto,
              child: const Text('SKIP PHOTO (DEBUG)'),
            ),
        ],
      ),
    ),
  );
}

/// One CTA flips from the shutter action to confirmation without accepting taps
/// on the new action until its label has finished turning into view.
class _RotatingCheckInAction extends StatefulWidget {
  const _RotatingCheckInAction({
    required this.hasPhoto,
    required this.isLoading,
    required this.onPressed,
  });
  final bool hasPhoto;
  final bool isLoading;
  final VoidCallback? onPressed;
  @override
  State<_RotatingCheckInAction> createState() => _RotatingCheckInActionState();
}

class _RotatingCheckInActionState extends State<_RotatingCheckInAction>
    with SingleTickerProviderStateMixin {
  late final _rotation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
    value: 1,
  );
  bool _previousHasPhoto = false;
  @override
  void didUpdateWidget(covariant _RotatingCheckInAction oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.hasPhoto != widget.hasPhoto) {
      _previousHasPhoto = oldWidget.hasPhoto;
      if (MediaQuery.disableAnimationsOf(context)) {
        _rotation.value = 1;
      } else {
        _rotation.forward(from: 0);
      }
    }
  }

  @override
  void dispose() {
    _rotation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _rotation,
    builder: (context, _) {
      final progress = Curves.easeInOut.transform(_rotation.value);
      final hasPhoto = progress < .5 ? _previousHasPhoto : widget.hasPhoto;
      final angle = progress < .5
          ? -math.pi * progress
          : math.pi * (1 - progress);
      return Transform(
        alignment: Alignment.center,
        transform: Matrix4.identity()
          ..setEntry(3, 2, .001)
          ..rotateX(angle),
        child: AppButton(
          key: ValueKey(hasPhoto ? 'submit-photo-check-in' : 'take-picture'),
          label: hasPhoto ? 'CHECK IN' : 'TAKE PICTURE',
          isLoading: widget.isLoading,
          onPressed: _rotation.isCompleted ? widget.onPressed : null,
        ),
      );
    },
  );
}
