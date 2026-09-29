import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../widgets/app_icon.dart';

import 'package:hugeicons/styles/stroke_rounded.dart';

import '../theme/weekpact_theme.dart';
import 'check_in_camera.dart';

/// The live camera, filling whatever box it is given edge to edge.
///
/// Owns the camera only while the capture step is visible and foregrounded.
/// It draws nothing but the feed: the shutter, the lens switch and the way
/// out are the page's, published here as actions so the page can decide what
/// to offer when the camera fails.
class CheckInCameraPreview extends StatefulWidget {
  const CheckInCameraPreview({
    super.key,
    required this.onCaptured,
    required this.onBusyChanged,
    required this.onActionChanged,
    this.onSwitchChanged,
    this.onDeniedChanged,
    this.listCameras = availableCameras,
    this.createController = _createController,
    this.preparePhoto = CheckInCamera.prepare,
  });

  /// The shutter while the feed is live, a retry once it has failed, and
  /// nothing at all while the camera is starting or taking a picture.
  final ValueChanged<VoidCallback?> onActionChanged;

  /// The switch to the other lens, or null when there is no other lens or the
  /// feed is not ready to swap.
  final ValueChanged<VoidCallback?>? onSwitchChanged;

  /// True once the camera has been refused rather than merely failed. The
  /// page owns the call to action, so it is the only thing that can offer the
  /// way into Settings; the preview here can only say which kind of failure
  /// this is. Every other error is answered by trying again, which the
  /// published action already is.
  final ValueChanged<bool>? onDeniedChanged;
  final Future<Uint8List> Function(Uint8List) preparePhoto;
  final ValueChanged<CapturedPhoto> onCaptured;
  final ValueChanged<bool> onBusyChanged;
  final Future<List<CameraDescription>> Function() listCameras;
  final CameraController Function(CameraDescription) createController;

  static CameraController _createController(CameraDescription camera) =>
      CameraController(camera, ResolutionPreset.high, enableAudio: false);

  @override
  State<CheckInCameraPreview> createState() => _CheckInCameraPreviewState();
}

class _CheckInCameraPreviewState extends State<CheckInCameraPreview>
    with WidgetsBindingObserver {
  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  CameraDescription? _selected;
  Future<void> _operations = Future.value();
  int _generation = 0;
  bool _active = true;
  bool _initializing = true;
  bool _takingPhoto = false;
  bool _denied = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _open();
  }

  bool _current(int generation) =>
      mounted && _active && generation == _generation;

  bool get _ready =>
      _active &&
      !_initializing &&
      !_takingPhoto &&
      _error == null &&
      _controller?.value.isInitialized == true;

  Future<void> _release() async {
    final controller = _controller;
    _controller = null;
    controller?.removeListener(_cameraChanged);
    try {
      await controller?.dispose();
    } catch (_) {
      // A disconnected camera must not prevent reopening or closing the page.
    }
  }

  void _publishAction() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.onActionChanged(
        !_active || _initializing || _takingPhoto
            ? null
            : _error != null
            ? _open
            : _takePhoto,
      );
      widget.onSwitchChanged?.call(
        _ready && _cameras.length > 1 ? _switchCamera : null,
      );
      widget.onDeniedChanged?.call(_denied);
    });
  }

  void _cameraChanged() {
    if (mounted && _controller?.value.hasError == true) {
      setState(() {
        _error = 'Camera interrupted. Please try again.';
        _denied = false;
      });
      _publishAction();
    }
  }

  void _open([CameraDescription? camera]) {
    final generation = ++_generation;
    setState(() {
      _initializing = true;
      _error = null;
      _denied = false;
    });
    _publishAction();
    // Initialize, capture and dispose in order, including quick app switches.
    _operations = _operations.then((_) async {
      await _release();
      if (!_current(generation)) return;
      try {
        _cameras = await widget.listCameras();
        if (!_current(generation)) return;
        if (_cameras.isEmpty) {
          throw CameraException('NoCamera', 'No camera available');
        }
        _selected =
            camera ??
            _selected ??
            _cameras
                .where((c) => c.lensDirection == CameraLensDirection.back)
                .firstOrNull ??
            _cameras.first;
        final controller = widget.createController(_selected!);
        _controller = controller;
        controller.addListener(_cameraChanged);
        await controller.initialize();
        if (!_current(generation)) {
          await _release();
          return;
        }
        setState(() => _initializing = false);
        _publishAction();
      } catch (error) {
        await _release();
        if (_current(generation)) {
          setState(() {
            _initializing = false;
            _error = _message(error);
            _denied = _refused(error);
          });
          _publishAction();
        }
      }
    });
  }

  /// Swaps to the lens facing the other way, or failing that the next one
  /// the device lists.
  void _switchCamera() {
    if (!_ready || _cameras.length < 2) return;
    final current = _selected;
    final other = _cameras
        .where((c) => c.lensDirection != current?.lensDirection)
        .firstOrNull;
    if (other != null) {
      _open(other);
      return;
    }
    final index = _cameras.indexOf(current!);
    _open(_cameras[(index + 1) % _cameras.length]);
  }

  /// Whether the camera was refused rather than broken. The OS will not ask a
  /// second time once someone has said no, so trying again on its own can
  /// only fail again; Settings is the only door left. A camera restricted by
  /// device policy is not this — Settings cannot lift a restriction either,
  /// so it stays a plain failure.
  static bool _refused(Object error) {
    if (error is! CameraException) return false;
    final code = error.code.toLowerCase();
    if (code.contains('restricted')) return false;
    return code.contains('denied') ||
        code.contains('permission') ||
        code.contains('access');
  }

  static String _message(Object error) {
    final code = error is CameraException ? error.code.toLowerCase() : '';
    if (code.contains('restricted')) {
      return 'Camera access is restricted on this device.';
    }
    if (_refused(error)) {
      return 'Allow camera access in Settings, then try again.';
    }
    if (code == 'nocamera') {
      return 'No camera found. Use a device with a camera.';
    }
    return 'Could not start the camera. Please try again.';
  }

  void _takePhoto() {
    final controller = _controller;
    if (_takingPhoto ||
        _initializing ||
        !_active ||
        controller == null ||
        !controller.value.isInitialized ||
        _error != null) {
      return;
    }
    final generation = _generation;
    setState(() => _takingPhoto = true);
    widget.onBusyChanged(true);
    _publishAction();
    _operations = _operations.then((_) async {
      var frozen = false;
      try {
        if (!_current(generation)) return;
        // The shutter asks for the picture, then holds the feed on its last
        // frame. The capture itself still takes the camera a moment, and a
        // feed that keeps moving through it makes the tap feel ignored; a
        // frozen frame is what every phone camera shows in that gap.
        final taking = controller.takePicture();
        frozen = await _freeze(controller);
        final file = await taking;
        if (await file.length() > 20 * 1024 * 1024) {
          throw StateError('Photo too large');
        }
        final bytes = await file.readAsBytes();
        if (!_current(generation)) return;
        // Hand the picture over the moment it exists. Scaling and re-encoding
        // it for upload takes a good second, and nobody should wait on that
        // to see what they just took.
        final photo = CapturedPhoto(
          preview: bytes,
          prepare: () => widget.preparePhoto(bytes),
        )..warm();
        widget.onCaptured(photo);
      } catch (_) {
        // The picture did not come, so the feed has to move again.
        if (frozen) await _thaw(controller);
        if (_current(generation)) {
          setState(
            () => _error = 'Could not take the photo. Please try again.',
          );
        }
      } finally {
        if (mounted) {
          setState(() => _takingPhoto = false);
          widget.onBusyChanged(false);
          _publishAction();
        }
      }
    });
  }

  /// Holds the preview on its current frame. A camera that cannot pause is
  /// left running rather than failing the capture over it.
  static Future<bool> _freeze(CameraController controller) async {
    try {
      await controller.pausePreview();
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<void> _thaw(CameraController controller) async {
    try {
      await controller.resumePreview();
    } catch (_) {
      // Retrying reopens the camera anyway.
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _active = true;
      _open();
    } else {
      _active = false;
      ++_generation;
      setState(() => _initializing = true);
      _publishAction();
      _operations = _operations.then((_) => _release());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    ++_generation;
    _active = false;
    _operations = _operations.then((_) => _release());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final ready =
        !_initializing && _active && controller?.value.isInitialized == true;
    // A shade above the page's black, so the card reads as a card before
    // the feed arrives and when there is no feed to show.
    return ColoredBox(
      color: WeekPactColors.darkCanvas,
      child: SizedBox.expand(
        child: ready && _error == null
            ? ValueListenableBuilder<CameraValue>(
                valueListenable: controller!,
                builder: (context, value, _) {
                  final orientation =
                      value.lockedCaptureOrientation ?? value.deviceOrientation;
                  final landscape =
                      orientation == DeviceOrientation.landscapeLeft ||
                      orientation == DeviceOrientation.landscapeRight;
                  final aspect = landscape
                      ? value.aspectRatio
                      : 1 / value.aspectRatio;
                  return ClipRect(
                    child: FittedBox(
                      fit: BoxFit.cover,
                      child: SizedBox(
                        width: aspect * 100,
                        height: 100,
                        child: CameraPreview(controller),
                      ),
                    ),
                  );
                },
              )
            : Center(
                child: _initializing
                    ? const CircularProgressIndicator(
                        color: WeekPactColors.cream,
                        semanticsLabel: 'Starting camera',
                      )
                    : Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const AppIcon(
                              icon: HugeIconsStrokeRounded.camera01,
                              size: 40,
                              color: WeekPactColors.darkMuted,
                            ),
                            if (_error != null) ...[
                              const SizedBox(height: 12),
                              Semantics(
                                liveRegion: true,
                                child: Text(
                                  _error!,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontFamily: WeekPactType.secondary,
                                    fontFamilyFallback:
                                        WeekPactType.secondaryFallback,
                                    fontSize: 14,
                                    color: WeekPactColors.cream,
                                  ),
                                ),
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
