import 'package:flutter/material.dart';

import '../widgets/app_icon.dart';

import 'package:hugeicons/styles/stroke_rounded.dart';

import '../theme/weekpact_theme.dart';
import 'telemetry.dart';

class DiagnosticsControl extends StatefulWidget {
  const DiagnosticsControl({super.key, this.enabled = true});
  final bool enabled;
  @override
  State<DiagnosticsControl> createState() => _DiagnosticsControlState();
}

class _DiagnosticsControlState extends State<DiagnosticsControl> {
  bool _saving = false;
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: CrashReporting.instance,
    builder: (context, enabled, _) => Tooltip(
      message:
          'Optional device diagnostics, without your name or pact content.',
      child: SwitchListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        secondary: const AppIcon(icon: HugeIconsStrokeRounded.file02, size: 26),
        title: const Text(
          'Share crash reports',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
        ),
        subtitle: Text(
          'Optional diagnostics',
          style: TextStyle(fontSize: 13, color: context.muted),
        ),
        activeTrackColor: WeekPactColors.coolGrey,
        activeThumbColor: WeekPactColors.black,
        value: enabled,
        onChanged:
            !widget.enabled || _saving || !CrashReporting.instance.available
            ? null
            : (value) async {
                setState(() => _saving = true);
                try {
                  await CrashReporting.instance.setEnabled(value);
                } catch (_) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Could not update diagnostics. Please retry.',
                        ),
                      ),
                    );
                  }
                } finally {
                  if (mounted) setState(() => _saving = false);
                }
              },
      ),
    ),
  );
}
