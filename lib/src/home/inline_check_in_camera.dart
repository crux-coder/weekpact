import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:hugeicons/styles/stroke_rounded.dart';

import '../theme/weekpact_theme.dart';
import 'check_in_camera.dart';
import 'check_in_photo_frame.dart';

/// Owns the camera only while the live capture step is visible and foregrounded.
class InlineCheckInCamera extends StatefulWidget {
  const InlineCheckInCamera({
    super.key,
    required this.onCaptured,
    required this.onBusyChanged,
    required this.onActionChanged,
    this.listCameras = availableCameras,
    this.createController = _createController,
    this.preparePhoto = CheckInCamera.prepare,
  });

  final ValueChanged<VoidCallback?> onActionChanged;
  final Future<Uint8List> Function(Uint8List) preparePhoto;
  final ValueChanged<Uint8List> onCaptured;
  final ValueChanged<bool> onBusyChanged;
  final Future<List<CameraDescription>> Function() listCameras;
  final CameraController Function(CameraDescription) createController;

  static CameraController _createController(CameraDescription camera) =>
      CameraController(camera, ResolutionPreset.high, enableAudio: false);

  @override
  State<InlineCheckInCamera> createState() => _InlineCheckInCameraState();
}

class _InlineCheckInCameraState extends State<InlineCheckInCamera>
    with WidgetsBindingObserver {
  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  CameraDescription? _selected;
  Future<void> _operations = Future.value();
  int _generation = 0;
  bool _active = true;
  bool _initializing = true;
  bool _takingPhoto = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _open();
  }

  bool _current(int generation) =>
      mounted && _active && generation == _generation;

  Future<void> _release() async {
    final controller = _controller;
    _controller = null;
    controller?.removeListener(_cameraChanged);
    try {
      await controller?.dispose();
    } catch (_) {
      // A disconnected camera must not prevent reopening or closing the drawer.
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
    });
  }

  void _cameraChanged() {
    if (mounted && _controller?.value.hasError == true) {
      setState(() => _error = 'Camera interrupted. Please try again.');
      _publishAction();
    }
  }

  void _open([CameraDescription? camera]) {
    final generation = ++_generation;
    setState(() {
      _initializing = true;
      _error = null;
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
          });
          _publishAction();
        }
      }
    });
  }

  String _message(Object error) {
    final code = error is CameraException ? error.code.toLowerCase() : '';
    if (code.contains('restricted')) {
      return 'Camera access is restricted on this device.';
    }
    if (code.contains('access') || code.contains('permission')) {
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
      try {
        if (!_current(generation)) return;
        final file = await controller.takePicture();
        if (await file.length() > 20 * 1024 * 1024) {
          throw StateError('Photo too large');
        }
        final photo = await widget.preparePhoto(await file.readAsBytes());
        if (_current(generation)) widget.onCaptured(photo);
      } catch (_) {
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
    return Column(
      children: [
        SizedBox(
          width: (MediaQuery.sizeOf(context).height * .4).clamp(120.0, 320.0),
          child: CheckInPhotoFrame(
            child: ColoredBox(
              color: WeekPactColors.neutralInset,
              child: ready && _error == null
                  ? ValueListenableBuilder<CameraValue>(
                      valueListenable: controller!,
                      builder: (context, value, _) {
                        final orientation =
                            value.lockedCaptureOrientation ??
                            value.deviceOrientation;
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
                              semanticsLabel: 'Starting camera',
                            )
                          : const HugeIcon(
                              icon: HugeIconsStrokeRounded.camera01,
                              size: 40,
                              color: WeekPactColors.mutedLight,
                            ),
                    ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (_error != null) ...[
          Semantics(
            liveRegion: true,
            child: Text(
              _error!,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Roboto',
                fontSize: 13,
                color: context.errorInk,
              ),
            ),
          ),
        ],
      ],
    );
  }
}
