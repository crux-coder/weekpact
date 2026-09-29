import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../widgets/raised_icon.dart';

import 'package:hugeicons/styles/stroke_rounded.dart';

import '../theme/weekpact_theme.dart';
import '../widgets/app_sheet.dart';
import 'home_backend.dart';

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
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            IconButton(
              tooltip: 'Close check-in photo',
              onPressed: () => Navigator.pop(context),
              icon: const RaisedIcon(icon: HugeIconsStrokeRounded.cancel01),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // The photo at its own shape: check-ins are the whole camera frame,
        // so a fixed square would cut most of it away.
        Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * .6,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(WeekPactMetrics.cardCorner),
              child: FutureBuilder<Uint8List>(
                future: _photo,
                builder: (context, snapshot) {
                  if (snapshot.hasData) {
                    return Image.memory(
                      snapshot.data!,
                      fit: BoxFit.contain,
                      semanticLabel: 'Crew check-in photo',
                    );
                  }
                  return SizedBox(
                    width: 240,
                    height: 240,
                    child: ColoredBox(
                      color: WeekPactColors.neutralInset,
                      child: snapshot.hasError
                          ? Center(
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
                            )
                          : const Center(
                              child: CircularProgressIndicator(
                                semanticsLabel: 'Loading check-in photo',
                              ),
                            ),
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
