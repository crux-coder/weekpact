import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme/weekpact_theme.dart';
import '../widgets/app_components.dart';
import 'auth_backend.dart';

class PasswordPage extends StatefulWidget {
  const PasswordPage({
    super.key,
    required this.backend,
    this.recovery = false,
    this.initialEmail = '',
    this.confirmationRedirect,
  });
  final AuthBackend backend;
  final bool recovery;
  final String initialEmail;
  final String? confirmationRedirect;
  @override
  State<PasswordPage> createState() => _PasswordPageState();
}

class _PasswordPageState extends State<PasswordPage> {
  final _form = GlobalKey<FormState>();
  late final _email = TextEditingController(text: widget.initialEmail);
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  Timer? _timer;
  int _cooldown = 0;
  bool _busy = false;
  bool _updated = false;
  String? _message;
  bool _failed = false;

  @override
  void dispose() {
    _timer?.cancel();
    _email.dispose();
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  Future<void> _submit({bool resend = false}) async {
    if (_busy || !_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _message = null;
      _failed = false;
    });
    try {
      if (widget.recovery) {
        await widget.backend.updatePassword(_password.text);
        _password.clear();
        _confirmation.clear();
        if (mounted) setState(() => _updated = true);
      } else {
        if (resend) {
          await widget.backend.resendConfirmation(
            _email.text,
            emailRedirectTo: widget.confirmationRedirect,
          );
        } else {
          await widget.backend.requestPasswordReset(_email.text);
        }
        if (mounted) {
          setState(() {
            _message = resend
                ? 'If this account needs confirmation, an email is on its way. Check your spam folder too.'
                : 'If an account exists for this email, a reset link is on its way. Open it on this device. Check your spam folder too.';
            _cooldown = 60;
          });
          _timer?.cancel();
          _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
            if (!mounted) {
              timer.cancel();
              return;
            }
            setState(() => _cooldown--);
            if (_cooldown == 0) timer.cancel();
          });
        }
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _failed = true;
          _message = error is AuthException && widget.recovery ? error.message : 'Couldn’t complete the request. Please wait a moment and try again.';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _leaveRecovery() async {
    setState(() => _busy = true);
    try {
      await widget.backend.signOut();
    } catch (_) {
      if (mounted) {
        setState(() {
          _message = 'Couldn’t sign out. Please try again.';
          _failed = true;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        widget.recovery ? 'Choose a new password' : 'Account recovery',
      ),
      automaticallyImplyLeading: !widget.recovery,
    ),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: AppSurface(
              builder: (context) => Padding(
                padding: const EdgeInsets.all(16),
                child: Form(
                  key: _form,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_updated) ...[
                        const Text(
                          'Your password has been updated. Sign in again with your new password.',
                        ),
                        const SizedBox(height: 24),
                        AppButton(
                          label: 'BACK TO LOGIN',

                          isLoading: _busy,
                          onPressed: _busy ? null : _leaveRecovery,
                        ),
                      ] else ...[
                        Text(
                          widget.recovery
                              ? 'Use at least 8 characters for your new password.'
                              : 'Enter your account email to reset your password or resend your signup confirmation.',
                        ),
                        const SizedBox(height: 24),
                        if (!widget.recovery)
                          TextFormField(
                            controller: _email,
                            enabled: !_busy,
                            keyboardType: TextInputType.emailAddress,
                            autofillHints: const [AutofillHints.email],
                            decoration: const InputDecoration(
                              labelText: 'Email',
                            ),
                            validator: (value) =>
                                RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
                                    .hasMatch(value?.trim() ?? '')
                                ? null
                                : 'Enter a valid email',
                          ),
                        if (widget.recovery) ...[
                          TextFormField(
                            controller: _password,
                            obscureText: true,
                            enabled: !_busy,
                            autofillHints: const [AutofillHints.newPassword],
                            decoration: const InputDecoration(
                              labelText: 'New password',
                            ),
                            validator: (value) => (value?.length ?? 0) < 8
                                ? 'Use at least 8 characters'
                                : null,
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _confirmation,
                            obscureText: true,
                            enabled: !_busy,
                            decoration: const InputDecoration(
                              labelText: 'Confirm new password',
                            ),
                            validator: (value) => value == _password.text
                                ? null
                                : 'Passwords do not match',
                          ),
                        ],
                        const SizedBox(height: 24),
                        AppButton(
                          label: widget.recovery
                              ? 'SAVE PASSWORD'
                              : 'SEND RESET LINK',

                          isLoading: _busy,
                          onPressed: _busy || _cooldown > 0
                              ? null
                              : () => _submit(),
                        ),
                        if (!widget.recovery)
                          TextButton(
                            onPressed: _busy || _cooldown > 0
                                ? null
                                : () => _submit(resend: true),
                            child: const Text('Resend confirmation email'),
                          ),
                        if (_cooldown > 0)
                          Text(
                            'You can request another email in $_cooldown seconds.',
                          ),
                        if (widget.recovery)
                          TextButton(
                            onPressed: _busy ? null : _leaveRecovery,
                            child: const Text('Cancel and sign out'),
                          ),
                      ],
                      if (_message != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: Text(
                            _message!,
                            style: TextStyle(
                              color: _failed ? context.errorInk : context.ink,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
