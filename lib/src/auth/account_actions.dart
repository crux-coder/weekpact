import 'package:hugeicons/styles/stroke_rounded.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:flutter/material.dart';

import '../theme/weekpact_theme.dart';
import '../widgets/app_components.dart';

import '../widgets/app_sheet.dart';
import '../widgets/settings_row.dart';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'auth_backend.dart';
import 'password_page.dart';

const privacyUrl = String.fromEnvironment(
  'PRIVACY_URL',
  defaultValue: 'https://weekpact.codepeaktrail.dev/privacy/',
);
const supportUrl = String.fromEnvironment(
  'SUPPORT_URL',
  defaultValue: 'https://weekpact.codepeaktrail.dev/support/',
);

class PublicAccountLinks extends StatelessWidget {
  const PublicAccountLinks({
    super.key,
    this.asRows = false,
    this.asTiles = false,
  });
  final bool asRows;
  final bool asTiles;

  Future<void> _open(BuildContext context, String url) async {
    try {
      final uri = Uri.parse(url);
      if (uri.scheme != 'https' ||
          !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        throw StateError('Link unavailable');
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Couldn’t open the page. Contact codepeaktrail@gmail.com for help.',
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => asTiles
      ? IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _tile(
                  context,
                  'Support',
                  supportUrl,
                  HugeIconsStrokeRounded.customerService,
                  WeekPactColors.coolGrey,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _tile(
                  context,
                  'Privacy policy',
                  privacyUrl,
                  HugeIconsStrokeRounded.file02,
                  WeekPactColors.cream,
                ),
              ),
            ],
          ),
        )
      : asRows
      ? Column(
          children: [
            SettingsRow(
              icon: HugeIconsStrokeRounded.customerService,
              label: 'Support',
              onTap: () => _open(context, supportUrl),
            ),
            const Divider(height: 1),
            SettingsRow(
              icon: HugeIconsStrokeRounded.file02,
              label: 'Privacy policy',
              onTap: () => _open(context, privacyUrl),
            ),
          ],
        )
      : Wrap(
          alignment: WrapAlignment.center,
          children: [
            TextButton(
              onPressed: () => _open(context, privacyUrl),
              child: const Text('Privacy policy'),
            ),
            TextButton(
              onPressed: () => _open(context, supportUrl),
              child: const Text('Support'),
            ),
          ],
        );

  Widget _tile(
    BuildContext context,
    String title,
    String url,
    List<List<dynamic>> icon,
    Color color,
  ) => AppSurface(
    fillColor: color,
    builder: (context) => InkWell(
      onTap: () => _open(context, url),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            HugeIcon(icon: icon, size: 28, color: context.ink),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    ),
  );
}

class AccountActions extends StatefulWidget {
  const AccountActions({
    super.key,
    required this.backend,
    this.showPasswordReset = true,
    this.showPublicLinks = true,
    this.enabled = true,
    this.asRows = false,
  });
  final bool asRows;
  final AuthBackend backend;
  final bool showPasswordReset;
  final bool showPublicLinks;
  final bool enabled;
  @override
  State<AccountActions> createState() => _AccountActionsState();
}

class _AccountActionsState extends State<AccountActions> {
  bool _busy = false;
  String? _error;

  Future<void> _delete() async {
    final password = await showAppDialog<String>(
      context: context,
      builder: (_) => const _DeleteAccountDialog(),
    );
    if (password == null || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.backend.deleteAccount(password);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is FunctionException && error.status == 403
              ? 'Incorrect password. Try again, or reset your password first.'
              : 'Couldn’t finish deletion. Please retry. If it still fails, contact codepeaktrail@gmail.com.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (!widget.asRows) const SizedBox(height: 20),
      if (widget.showPasswordReset && widget.asRows) ...[
        SettingsRow(
          icon: HugeIconsStrokeRounded.lockPassword,
          label: 'Reset password',
          onTap: _busy || !widget.enabled
              ? null
              : () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => PasswordPage(
                      backend: widget.backend,
                      initialEmail: widget.backend.currentUser?.email ?? '',
                    ),
                  ),
                ),
        ),
        const Divider(height: 1),
      ],
      if (widget.showPasswordReset && !widget.asRows)
        TextButton(
          onPressed: _busy || !widget.enabled
              ? null
              : () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => PasswordPage(
                      backend: widget.backend,
                      initialEmail: widget.backend.currentUser?.email ?? '',
                    ),
                  ),
                ),
          child: const Text('Reset password'),
        ),
      if (widget.showPublicLinks) PublicAccountLinks(asRows: widget.asRows),
      TextButton(
        onPressed: _busy || !widget.enabled ? null : _delete,
        style: TextButton.styleFrom(
          foregroundColor: Theme.of(context).colorScheme.error,
        ),
        child: Text(_busy ? 'Deleting account…' : 'Delete account'),
      ),
      if (_error != null)
        Text(
          _error!,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
    ],
  );
}

class _DeleteAccountDialog extends StatefulWidget {
  const _DeleteAccountDialog();
  @override
  State<_DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<_DeleteAccountDialog> {
  final _password = TextEditingController();
  bool _confirmed = false;
  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Delete your account?'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'This permanently removes your profile, profile and check-in photos, check-ins, invitations and notification registrations. Pacts you created, including everyone’s check-ins on those pacts, are removed too.\n\nIf you own a crew, its longest-standing remaining member becomes owner. A crew with no remaining members is deleted. This cannot be undone.',
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _password,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(labelText: 'Current password'),
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _confirmed,
            onChanged: (value) => setState(() => _confirmed = value ?? false),
            title: const Text('I understand this is permanent.'),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      TextButton(
        onPressed: _confirmed && _password.text.isNotEmpty
            ? () => Navigator.pop(context, _password.text)
            : null,
        child: const Text('Permanently delete'),
      ),
    ],
  );
}
