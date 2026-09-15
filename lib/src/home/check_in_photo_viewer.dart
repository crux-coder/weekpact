import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:hugeicons/styles/stroke_rounded.dart';

import '../widgets/app_sheet.dart';
import 'home_backend.dart';
import 'check_in_photo_frame.dart';

class CheckInPhotoViewer extends StatefulWidget {
  const CheckInPhotoViewer({
    super.key,
    required this.backend,
    required this.path,
    required this.title,
  });
  final HomeBackend backend;
  final String path;
  final String title;
  @override
  State<CheckInPhotoViewer> createState() => _CheckInPhotoViewerState();
}

class _CheckInPhotoViewerState extends State<CheckInPhotoViewer> {
  late Future<Uint8List> _photo = widget.backend.fetchCheckInPhoto(widget.path);
  @override
  Widget build(BuildContext context) => AppSheet(
    builder: (context) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                widget.title,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            IconButton(
              tooltip: 'Close check-in photo',
              onPressed: () => Navigator.pop(context),
              icon: const HugeIcon(icon: HugeIconsStrokeRounded.cancel01),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Center(
          child: SizedBox(
            width: (MediaQuery.sizeOf(context).height * .65).clamp(
              120.0,
              360.0,
            ),
            child: CheckInPhotoFrame(
              child: FutureBuilder<Uint8List>(
                future: _photo,
                builder: (context, snapshot) {
                  if (snapshot.hasData) {
                    return Image.memory(
                      snapshot.data!,
                      fit: BoxFit.cover,
                      semanticLabel: 'Crew check-in photo',
                    );
                  }
                  if (snapshot.hasError) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'Photo unavailable',
                            textAlign: TextAlign.center,
                          ),
                          TextButton(
                            onPressed: () => setState(() {
                              _photo = widget.backend.fetchCheckInPhoto(
                                widget.path,
                              );
                            }),
                            child: const Text('RETRY'),
                          ),
                        ],
                      ),
                    );
                  }
                  return const Center(
                    child: CircularProgressIndicator(
                      semanticsLabel: 'Loading check-in photo',
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
