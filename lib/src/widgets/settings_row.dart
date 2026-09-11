import 'package:flutter/material.dart';

class SettingsRow extends StatelessWidget {
  const SettingsRow({
    super.key,
    required this.icon,
    required this.label,
    this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: Icon(icon, size: 23),
    title: Text(
      label,
      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
    ),
    trailing: const Icon(Icons.chevron_right, size: 21),
    onTap: onTap,
  );
}
