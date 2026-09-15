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
  });
  final AuthBackend backend;
  final double size;
  final String? initials;
  final Color? backgroundColor;
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
              fontWeight: FontWeight.w700,
            ),
          ),
        )
      : HugeIcon(
          icon: HugeIconsStrokeRounded.user,
          color: context.ink,
          size: widget.size / 2,
        );
  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List?>(
    future: _photo,
    builder: (context, snapshot) => Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: widget.backgroundColor ?? context.yellow,
        border: Border.all(
          color: context.border,
          width: WeekPactMetrics.border,
        ),
      ),
      child: ClipOval(
        child: snapshot.data != null
            ? Image.memory(
                snapshot.data!,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => _fallback(context),
              )
            : _fallback(context),
      ),
    ),
  );
}
