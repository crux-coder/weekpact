import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:hugeicons/styles/stroke_rounded.dart';

import '../widgets/app_components.dart';
import '../widgets/app_sheet.dart';
import '../theme/weekpact_theme.dart';
import 'check_in_camera.dart';
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
          capturePhoto:
              capturePhoto ??
              () => CheckInCamera.capture(
                userId: userId,
                crewId: crewId,
                pactId: pactId,
                today: today,
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
    required this.capturePhoto,
    required this.save,
  });
  final String pactTitle;
  final CheckInPhotoCapture capturePhoto;
  final Future<void> Function(Uint8List) save;
  @override
  State<PhotoCheckInSheet> createState() => _PhotoCheckInSheetState();
}

class _PhotoCheckInSheetState extends State<PhotoCheckInSheet> {
  Uint8List? _photo;
  bool _capturing = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _capture();
    });
  }

  Future<void> _capture() async {
    if (_capturing || _saving) return;
    setState(() {
      _capturing = true;
      _error = null;
    });
    try {
      final photo = await widget.capturePhoto();
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
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Close photo check-in',
                onPressed: _saving || _capturing
                    ? null
                    : () => Navigator.pop(context, false),
                icon: const HugeIcon(icon: HugeIconsStrokeRounded.cancel01),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'A quick photo for your crew.',
            style: TextStyle(
              fontFamily: 'Roboto',
              fontSize: 14,
              fontWeight: FontWeight.w400,
              color: context.muted,
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: SizedBox(
              width: (MediaQuery.sizeOf(context).height * .4).clamp(
                120.0,
                320.0,
              ),
              child: CheckInPhotoFrame(
                child: ColoredBox(
                  color: const Color(0xFFE5E9E2),
                  child: _photo == null
                      ? Center(
                          child: _capturing
                              ? const CircularProgressIndicator()
                              : const HugeIcon(
                                  icon: HugeIconsStrokeRounded.camera01,
                                  size: 40,
                                  color: Color(0xFF687262),
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
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: _capturing || _saving ? null : _capture,
            icon: const HugeIcon(
              icon: HugeIconsStrokeRounded.camera01,
              size: 20,
            ),
            label: Text(_photo == null ? 'OPEN CAMERA' : 'RETAKE PHOTO'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Semantics(
              liveRegion: true,
              child: Text(
                _error!,
                style: TextStyle(
                  fontFamily: 'Roboto',
                  fontSize: 13,
                  color: context.errorInk,
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          AppButton(
            key: const ValueKey('submit-photo-check-in'),
            label: 'CHECK IN',
            color: _photo == null ? const Color(0xFFE0E3DE) : null,
            foregroundColor: _photo == null ? const Color(0xFF73796F) : null,
            isLoading: _saving,
            onPressed: _photo == null || _capturing ? null : _save,
          ),
        ],
      ),
    ),
  );
}
