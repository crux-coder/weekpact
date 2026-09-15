import 'package:hugeicons/styles/stroke_rounded.dart';

import 'app_icon.dart';

import 'package:flutter/material.dart';

class SettingsRow extends StatelessWidget {
  const SettingsRow({
    super.key,
    required this.icon,
    required this.label,
    this.onTap,
  });
  final List<List<dynamic>> icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: AppIcon(icon: icon, size: 23),
    title: Text(
      label,
      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
    ),
    trailing: const AppIcon(
      icon: HugeIconsStrokeRounded.arrowRight01,
      size: 21,
    ),
    onTap: onTap,
  );
}
