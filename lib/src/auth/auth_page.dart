import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme/weekpact_theme.dart';
import '../widgets/app_components.dart';
import '../widgets/viewport_scroll_view.dart';
import '../widgets/welcome_card.dart';
import 'auth_backend.dart';
import 'password_page.dart';
import 'account_actions.dart';

enum AuthMode { login, signup }

const _inviteRedirectBase = String.fromEnvironment(
  'INVITE_REDIRECT_BASE',
  defaultValue: 'weekpact://invite',
);

class AuthPage extends StatefulWidget {
  const AuthPage({
    super.key,
    required this.authBackend,
    this.pendingInviteToken,
    this.initialError,
  });

  final AuthBackend authBackend;
  final String? pendingInviteToken;
  final String? initialError;

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  AuthMode _mode = AuthMode.login;
  bool _passwordHidden = true;
  bool _confirmPasswordHidden = true;
  bool _submitting = false;

  bool get _isLogin => _mode == AuthMode.login;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _switchMode() {
    setState(() {
      _mode = _isLogin ? AuthMode.signup : AuthMode.login;
      _submitting = false;
      _confirmPasswordController.clear();
      _formKey.currentState?.reset();
    });
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _submitting = true);
    try {
      final email = _emailController.text.trim();
      final password = _passwordController.text;
      if (_isLogin) {
        await widget.authBackend.signIn(email: email, password: password);
      } else {
        final result = await widget.authBackend.signUp(
          email: email,
          password: password,
          emailRedirectTo: _confirmationRedirectUrl,
        );
        if (result == SignUpResult.emailConfirmationRequired && mounted) {
          _showMessage('Check your email to confirm your account.');
          setState(() => _mode = AuthMode.login);
        }
      }
    } on AuthException catch (error) {
      if (mounted) _showMessage(error.message);
    } catch (error) {
      if (mounted) {
        final message = error is StateError
            ? error.message.toString()
            : 'Something went wrong. Please try again.';
        _showMessage(message);
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  String get _confirmationRedirectUrl {
    final token = widget.pendingInviteToken;
    if (token == null) return _inviteRedirectBase;
    return Uri.parse(_inviteRedirectBase)
        .replace(queryParameters: {'invite': token})
        .toString();
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  String? _validateEmail(String? value) {
    final email = value?.trim() ?? '';
    if (email.isEmpty) return 'Email is required';
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      return 'Enter a valid email';
    }
    return null;
  }

  String? _validatePassword(String? value) {
    if ((value ?? '').length < 8) return 'Use at least 8 characters';
    return null;
  }

  String? _validateConfirmation(String? value) {
    if (value != _passwordController.text) return 'Passwords do not match';
    return null;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: AutofillGroup(
            child: Form(
              key: _formKey,
              child: ViewportScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(12, 20, 12, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'WeekPact.',
                      style: TextStyle(
                        color: context.ink,
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 20),
                    WelcomeCard(
                      title: _isLogin ? 'Welcome back.' : 'Make it official.',
                      subtitle: _isLogin
                          ? 'Your people. Your pacts. A fresh start today.'
                          : 'Build better habits with your people.',
                      color: _isLogin
                          ? WeekPactColors.mintGreen
                          : WeekPactColors.softYellow,
                      eyebrow: _isLogin
                          ? 'SHOW UP TOGETHER'
                          : 'YOUR NEXT CHAPTER',
                    ),
                    const SizedBox(height: 8),
                    if (widget.pendingInviteToken != null) ...[
                      AppSurface(
                        fillColor: WeekPactColors.softYellow,
                        builder: (context) => const Padding(
                          padding: EdgeInsets.all(14),
                          child: Text(
                            'Crew invite ready. Use your invited email.',
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                    AppSurface(
                      builder: (context) => Padding(
                        padding: const EdgeInsets.all(18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (widget.initialError != null) ...[
                              Text(
                                widget.initialError!,
                                style: TextStyle(color: context.errorInk),
                              ),
                              const SizedBox(height: 12),
                            ],
                            AppTextField(
                              label: 'EMAIL',
                              hint: 'you@example.com',
                              controller: _emailController,
                              validator: _validateEmail,
                              keyboardType: TextInputType.emailAddress,
                              textInputAction: TextInputAction.next,
                              autofillHints: const [AutofillHints.email],
                            ),
                            const SizedBox(height: 14),
                            AppTextField(
                              label: 'PASSWORD',
                              hint: 'At least 8 characters',
                              controller: _passwordController,
                              validator: _validatePassword,
                              textInputAction: _isLogin
                                  ? TextInputAction.done
                                  : TextInputAction.next,
                              obscureText: _passwordHidden,
                              onToggleObscure: () => setState(
                                () => _passwordHidden = !_passwordHidden,
                              ),
                              autofillHints: [
                                _isLogin
                                    ? AutofillHints.password
                                    : AutofillHints.newPassword,
                              ],
                            ),
                            if (!_isLogin) ...[
                              const SizedBox(height: 14),
                              AppTextField(
                                label: 'CONFIRM PASSWORD',
                                hint: 'Type it again',
                                controller: _confirmPasswordController,
                                validator: _validateConfirmation,
                                textInputAction: TextInputAction.done,
                                obscureText: _confirmPasswordHidden,
                                onToggleObscure: () => setState(
                                  () => _confirmPasswordHidden =
                                      !_confirmPasswordHidden,
                                ),
                                autofillHints: const [
                                  AutofillHints.newPassword,
                                ],
                              ),
                            ],
                            const SizedBox(height: 20),
                            AppButton(
                              label: _isLogin ? 'LOG IN' : 'CREATE ACCOUNT',
                              isLoading: _submitting,
                              onPressed: _submit,
                            ),
                            const SizedBox(height: 8),
                            TextButton(
                              onPressed: _submitting
                                  ? null
                                  : () => Navigator.of(context).push(
                                      MaterialPageRoute<void>(
                                        builder: (_) => PasswordPage(
                                          backend: widget.authBackend,
                                          initialEmail: _emailController.text,
                                          confirmationRedirect:
                                              _confirmationRedirectUrl,
                                        ),
                                      ),
                                    ),
                              style: TextButton.styleFrom(
                                foregroundColor: context.muted,
                              ),
                              child: const Text(
                                'Forgot password or need a confirmation email?',
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    AppSurface(
                      fillColor: _isLogin
                          ? WeekPactColors.softYellow
                          : WeekPactColors.mintGreen,
                      builder: (context) => TextButton(
                        onPressed: _submitting ? null : _switchMode,
                        style: TextButton.styleFrom(
                          foregroundColor: context.ink,
                          minimumSize: const Size.fromHeight(52),
                        ),
                        child: Text(
                          _isLogin
                              ? 'New here?  CREATE ACCOUNT'
                              : 'Already in?  LOG IN',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const PublicAccountLinks(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
