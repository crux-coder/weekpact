import '../widgets/avatar_shape.dart';

import 'package:hugeicons/styles/stroke_rounded.dart';
import 'package:hugeicons/hugeicons.dart';

import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../auth/auth_backend.dart';
import '../theme/weekpact_theme.dart';

class ProfileAvatar extends StatefulWidget {
  const ProfileAvatar({
    super.key,
    required this.backend,
    this.size = 72,
    this.initials,
    this.backgroundColor,
    this.photo,
  });
  final AuthBackend backend;
  final double size;
  final String? initials;
  final Color? backgroundColor;

  /// A photo the caller already has — the one just chosen in the editor,
  /// which storage has not been asked for again.
  final Uint8List? photo;
  @override
  State<ProfileAvatar> createState() => _ProfileAvatarState();
}

class _ProfileAvatarState extends State<ProfileAvatar> {
  late final Future<Uint8List?> _photo = widget.backend.loadAvatar();

  Widget _fallback(BuildContext context) => widget.initials?.isNotEmpty == true
      ? Center(
          child: Text(
            widget.initials!,
            style: TextStyle(
              color: context.ink,
              fontSize: widget.size * .35,
              fontWeight: FontWeight.w500,
            ),
          ),
        )
      : Center(
          child: HugeIcon(
            icon: HugeIconsStrokeRounded.user,
            color: context.ink,
            size: widget.size / 2,
          ),
        );
  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List?>(
    future: _photo,
    builder: (context, snapshot) {
      final bytes = widget.photo ?? snapshot.data;
      return Container(
        width: widget.size,
        height: widget.size,
        // No outline: an outlined shape insets its child by the stroke, and
        // that gap let the fill ring a photo that should reach the edge.
        decoration: ShapeDecoration(
          shape: const AvatarShape(),
          color: widget.backgroundColor ?? context.yellow,
        ),
        child: AvatarClip(
          child: bytes != null
              ? Image.memory(
                  bytes,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => _fallback(context),
                )
              : _fallback(context),
        ),
      );
    },
  );
}
