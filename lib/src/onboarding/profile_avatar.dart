import 'package:hugeicons/styles/stroke_rounded.dart';
import 'package:hugeicons/hugeicons.dart';

import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../auth/auth_backend.dart';
import '../theme/weekpact_theme.dart';

class ProfileAvatar extends StatefulWidget {
  const ProfileAvatar({super.key, required this.backend});
  final AuthBackend backend;
  @override
  State<ProfileAvatar> createState() => _ProfileAvatarState();
}

class _ProfileAvatarState extends State<ProfileAvatar> {
  late final Future<Uint8List?> _photo = widget.backend.loadAvatar();
  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List?>(
    future: _photo,
    builder: (context, snapshot) => Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: context.yellow,
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
                errorBuilder: (_, _, _) => HugeIcon(
                  icon: HugeIconsStrokeRounded.user,
                  color: context.ink,
                  size: 36,
                ),
              )
            : HugeIcon(
                icon: HugeIconsStrokeRounded.user,
                color: context.ink,
                size: 36,
              ),
      ),
    ),
  );
}
