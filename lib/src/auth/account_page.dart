import '../telemetry/diagnostics_control.dart';

import 'package:flutter/material.dart';

import '../widgets/app_icon.dart';

import 'package:hugeicons/styles/stroke_rounded.dart';

import 'auth_backend.dart';
import 'profile_editor.dart';
import 'account_actions.dart';
import '../onboarding/profile_avatar.dart';
import '../notifications/notification_scope.dart';
import '../notifications/notification_settings_card.dart';
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
    final initials = [user.firstName, user.lastName]
        .where((part) => part.trim().isNotEmpty)
        .map((part) => part.trim().characters.first.toUpperCase())
        .join();
    return PageFrame(
      header: const PageHeading('Account', dotColor: WeekPactColors.coolGrey),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppSurface(
            key: const ValueKey('account-profile'),
            fillColor: WeekPactColors.stone,
            builder: (context) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
              child: Column(
                children: [
                  ProfileAvatar(
                    backend: widget.backend,
                    size: 88,
                    initials: initials,
                    backgroundColor: WeekPactColors.mintGreen,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    name.isEmpty ? 'Your profile' : name,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    user.email,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: context.muted, fontSize: 15),
                  ),
                  const SizedBox(height: 14),
                  Tooltip(
                    message: 'Edit profile',
                    child: FilledButton.icon(
                      onPressed: widget.signingOut ? null : _edit,
                      style: FilledButton.styleFrom(
                        backgroundColor: WeekPactColors.black,
                        foregroundColor: WeekPactColors.cream,
                        minimumSize: const Size(168, 44),
                        shape: WeekPactMetrics.buttonShape,
                      ),
                      icon: const AppIcon(
                        icon: HugeIconsStrokeRounded.pencilEdit02,
                        size: 20,
                      ),
                      label: const Text(
                        'Edit profile',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          AppSurface(
            key: const ValueKey('account-preferences'),
            builder: (_) => Column(
              children: [
                _NotificationControl(enabled: !widget.signingOut),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Divider(height: 1),
                ),
                DiagnosticsControl(enabled: !widget.signingOut),
              ],
            ),
          ),
          const SizedBox(height: 8),
          const PublicAccountLinks(asTiles: true),
          const SizedBox(height: 12),
          AppSurface(
            builder: (context) => ListTile(
              onTap: widget.signingOut ? null : widget.onSignOut,
              enabled: !widget.signingOut,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 18,
                vertical: 2,
              ),
              leading: AppIcon(
                icon: HugeIconsStrokeRounded.logout01,
                color: context.ink,
                size: 24,
              ),
              title: Text(
                widget.signingOut ? 'Logging out…' : 'Log out',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              trailing: AppIcon(
                icon: HugeIconsStrokeRounded.arrowRight01,
                color: context.ink,
                size: 20,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Divider(height: 1, color: context.border.withValues(alpha: .3)),
          const SizedBox(height: 4),
          AccountActions(
            backend: widget.backend,
            enabled: !widget.signingOut,
            showPasswordReset: false,
            showPublicLinks: false,
            asRows: true,
          ),
        ],
      ),
    );
  }
}

class _NotificationControl extends StatelessWidget {
  const _NotificationControl({required this.enabled});
  final bool enabled;
  @override
  Widget build(BuildContext context) {
    final service = NotificationScope.maybeOf(context);
    return SwitchListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      secondary: const AppIcon(
        icon: HugeIconsStrokeRounded.notification02,
        size: 26,
      ),
      title: const Text(
        'Notifications',
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
      ),
      activeTrackColor: WeekPactColors.coolGrey,
      activeThumbColor: WeekPactColors.black,
      value: service?.enabled ?? false,
      onChanged: !enabled || service == null || service.busy
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
    );
  }
}
