import 'package:flutter/material.dart';
import 'package:hugeicons/styles/stroke_rounded.dart';

import '../theme/weekpact_theme.dart';
import '../widgets/app_icon.dart';
import 'notification_preferences.dart';

/// A switch for each kind of push, under the device's own Notifications
/// switch. Each one only turns off its own kind; they are saved to the
/// account, so they hold on every phone it signs in on.
class NotificationKindControls extends StatefulWidget {
  const NotificationKindControls({
    super.key,
    required this.backend,
    this.enabled = true,
  });

  final NotificationPreferencesBackend backend;
  final bool enabled;

  @override
  State<NotificationKindControls> createState() =>
      _NotificationKindControlsState();
}

class _NotificationKindControlsState extends State<NotificationKindControls> {
  NotificationPreferences? _preferences;
  bool _failed = false;
  final Set<NotificationKind> _saving = {};

  static const _labels = {
    NotificationKind.checkIns: 'Pact check-ins',
    NotificationKind.claps: 'Claps',
    NotificationKind.chat: 'Chat',
  };
  static const _hints = {
    NotificationKind.checkIns: 'When your crew checks in on a pact',
    NotificationKind.claps: 'When someone claps your check-in or story',
    NotificationKind.chat: 'New messages in your crew chats',
  };
  static const Map<NotificationKind, List<List<dynamic>>> _icons = {
    NotificationKind.checkIns: HugeIconsStrokeRounded.checkmarkCircle02,
    NotificationKind.claps: HugeIconsStrokeRounded.handsClapping,
    NotificationKind.chat: HugeIconsStrokeRounded.bubbleChat,
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _failed = false);
    try {
      final preferences = await widget.backend.fetchNotificationPreferences();
      if (mounted) setState(() => _preferences = preferences);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  Future<void> _set(NotificationKind kind, bool value) async {
    final before = _preferences!;
    setState(() {
      _saving.add(kind);
      _preferences = before.withKind(kind, value);
    });
    try {
      final saved = await widget.backend.setNotificationPreference(kind, value);
      if (mounted) setState(() => _preferences = saved);
    } catch (_) {
      if (!mounted) return;
      // Only this kind goes back; another switch may have saved meanwhile.
      setState(
        () => _preferences = _preferences!.withKind(kind, before.wants(kind)),
      );
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not update notifications. Please retry.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving.remove(kind));
    }
  }

  @override
  Widget build(BuildContext context) {
    final preferences = _preferences;
    if (_failed) {
      return ListTile(
        contentPadding: const EdgeInsets.only(left: 58, right: 16),
        title: Text(
          'Couldn’t load which notifications you get.',
          style: TextStyle(fontSize: 14, color: context.muted),
        ),
        trailing: TextButton(onPressed: _load, child: const Text('Retry')),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final kind in NotificationKind.values)
          SwitchListTile(
            key: ValueKey('notification-kind-${kind.key}'),
            contentPadding: const EdgeInsets.only(left: 32, right: 16),
            secondary: AppIcon(icon: _icons[kind]!, size: 22),
            title: Text(
              _labels[kind]!,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            ),
            subtitle: Text(
              _hints[kind]!,
              style: TextStyle(fontSize: 13, color: context.muted),
            ),
            activeTrackColor: WeekPactColors.coolGrey,
            activeThumbColor: WeekPactColors.black,
            // Everything is on until the account says otherwise, the way
            // the server treats an account that never chose.
            value: preferences?.wants(kind) ?? true,
            onChanged:
                !widget.enabled || preferences == null || _saving.contains(kind)
                ? null
                : (value) => _set(kind, value),
          ),
      ],
    );
  }
}
