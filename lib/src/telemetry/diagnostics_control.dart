import 'package:flutter/material.dart';

import '../widgets/app_components.dart';
import 'telemetry.dart';

class DiagnosticsControl extends StatefulWidget {
  const DiagnosticsControl({super.key});
  @override
  State<DiagnosticsControl> createState() => _DiagnosticsControlState();
}

class _DiagnosticsControlState extends State<DiagnosticsControl> {
  bool _saving = false;
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: CrashReporting.instance,
    builder: (context, enabled, _) => AppSurface(
      builder: (context) => SwitchListTile(
        title: const Text('Share crash reports'),
        subtitle: const Text(
          'Help improve reliability. Optional device diagnostics, without your name or pact content.',
        ),
        value: enabled,
        onChanged: _saving || !CrashReporting.instance.available
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
