import 'package:flutter/material.dart';
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
  const PublicAccountLinks({super.key});

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
  Widget build(BuildContext context) => Wrap(
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
}

class AccountActions extends StatefulWidget {
  const AccountActions({
    super.key,
    required this.backend,
    this.showPasswordReset = true,
    this.enabled = true,
  });
  final AuthBackend backend;
  final bool showPasswordReset;
  final bool enabled;
  @override
  State<AccountActions> createState() => _AccountActionsState();
}

class _AccountActionsState extends State<AccountActions> {
  bool _busy = false;
  String? _error;

  Future<void> _delete() async {
    final password = await showDialog<String>(
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
      const SizedBox(height: 20),
      if (widget.showPasswordReset)
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
      const PublicAccountLinks(),
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
            'This permanently removes your profile, photo, check-ins, invitations and notification registrations. Goals you created, including everyone’s check-ins on those goals, are removed too.\n\nIf you own a crew, its longest-standing remaining member becomes owner. A crew with no remaining members is deleted. This cannot be undone.',
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
