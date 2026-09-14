import '../telemetry/diagnostics_control.dart';
import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:hugeicons/styles/stroke_rounded.dart';

import 'auth_backend.dart';
import 'profile_editor.dart';
import 'account_actions.dart';
import '../onboarding/profile_avatar.dart';
import '../notifications/notification_scope.dart';
import '../notifications/notification_settings_card.dart';
import '../theme/theme_preference.dart';
import '../theme/weekpact_theme.dart';
import '../widgets/app_components.dart';
import '../widgets/app_sheet.dart';
import '../widgets/page_frame.dart';

class AccountPage extends StatefulWidget {
  const AccountPage({
    super.key,
    required this.user,
    required this.backend,
    required this.signingOut,
    required this.onSignOut,
  });
  final AuthUser user;
  final AuthBackend backend;
  final bool signingOut;
  final VoidCallback onSignOut;
  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  AuthUser? _edited;

  Future<void> _edit() async {
    final updated = await showAppSheet<AuthUser>(
      context: context,
      builder: (_) =>
          ProfileEditor(user: _edited ?? widget.user, backend: widget.backend),
    );
    if (mounted && updated != null) setState(() => _edited = updated);
  }

  @override
  Widget build(BuildContext context) {
    final user = _edited ?? widget.user;
    final name = '${user.firstName} ${user.lastName}'.trim();
    return PageFrame(
      header: const PageHeading('Account'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppSurface(
            fillColor: WeekPactColors.mintGreen,
            builder: (context) => Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    alignment: Alignment.centerRight,
                    child: IconButton(
                      tooltip: 'Edit profile',
                      onPressed: widget.signingOut ? null : _edit,
                      icon: HugeIcon(
                        icon: HugeIconsStrokeRounded.pencilEdit02,
                        color: context.ink,
                        size: 22,
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      ProfileAvatar(backend: widget.backend),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name.isEmpty ? 'Your profile' : name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              user.email,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: context.muted,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          const DiagnosticsControl(),
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (context, constraints) {
              final twoColumns =
                  constraints.maxWidth >= 340 &&
                  MediaQuery.textScalerOf(context).scale(1) <= 1.15;
              final side = twoColumns
                  ? (constraints.maxWidth - 8) / 2
                  : constraints.maxWidth;
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  SizedBox.square(
                    dimension: side,
                    child: AccountPreferenceTile(
                      color: WeekPactColors.softYellow,
                      icon: Icons.contrast,
                      title: 'Appearance',
                      subtitle: 'Choose your theme',
                      control: const AppearanceChoices(),
                    ),
                  ),
                  SizedBox.square(
                    dimension: side,
                    child: AccountPreferenceTile(
                      color: WeekPactColors.cream,
                      icon: Icons.notifications_none,
                      title: 'Notifications',
                      subtitle: 'Stay in the loop',
                      control: const _NotificationControl(),
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 8),
          AppSurface(
            builder: (context) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
              child: AccountActions(
                backend: widget.backend,
                enabled: !widget.signingOut,
                asRows: true,
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: widget.signingOut ? null : widget.onSignOut,
            style: TextButton.styleFrom(
              foregroundColor: context.muted,
              minimumSize: const Size.fromHeight(48),
            ),
            icon: const Icon(Icons.logout, size: 22),
            label: Text(widget.signingOut ? 'Logging out…' : 'LOG OUT'),
          ),
        ],
      ),
    );
  }
}

class AccountPreferenceTile extends StatelessWidget {
  const AccountPreferenceTile({
    super.key,
    required this.color,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.control,
  });
  final Color color;
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget control;

  @override
  Widget build(BuildContext context) => AppSurface(
    fillColor: color,
    builder: (context) => Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 29),
          const SizedBox(height: 10),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              title,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 4),
          Text(subtitle, style: TextStyle(fontSize: 13, color: context.muted)),
          const Spacer(),
          control,
        ],
      ),
    ),
  );
}

class AppearanceChoices extends StatelessWidget {
  const AppearanceChoices({super.key});
  @override
  Widget build(BuildContext context) {
    final preference = ThemePreference.of(context);
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: context.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          for (final entry in [
            (ThemeMode.light, 'Light'),
            (ThemeMode.dark, 'Dark'),
            (ThemeMode.system, 'Device'),
          ])
            Expanded(
              child: Semantics(
                selected: preference.mode == entry.$1,
                button: true,
                child: Material(
                  color: preference.mode == entry.$1
                      ? WeekPactColors.black
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(7),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => preference.onChanged(entry.$1),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: 13,
                        horizontal: 2,
                      ),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          entry.$2,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: preference.mode == entry.$1
                                ? WeekPactColors.cream
                                : WeekPactColors.black,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _NotificationControl extends StatelessWidget {
  const _NotificationControl();
  @override
  Widget build(BuildContext context) {
    final service = NotificationScope.maybeOf(context);
    return Row(
      children: [
        Switch(
          activeTrackColor: WeekPactColors.mintGreen,
          activeThumbColor: WeekPactColors.black,
          value: service?.enabled ?? false,
          onChanged: service == null || service.busy
              ? null
              : (enabled) async {
                  if (enabled) {
                    await service.enable();
                  } else {
                    await service.disable();
                  }
                  if (context.mounted &&
                      (service.error != null ||
                          service.registrationError != null ||
                          !service.available ||
                          (enabled && !service.allowed))) {
                    await showAppSheet<void>(
                      context: context,
                      builder: (_) => AppSheet(
                        builder: (_) => const NotificationSettingsCard(),
                      ),
                    );
                  }
                },
        ),
        const SizedBox(width: 4),
        Text(
          service?.enabled == true ? 'On' : 'Off',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}
