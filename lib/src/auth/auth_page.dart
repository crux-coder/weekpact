import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme/weekpact_theme.dart';
import '../widgets/brutal_widgets.dart';
import '../widgets/viewport_scroll_view.dart';
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
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final horizontalPadding = size.width < 420 ? 12.0 : 20.0;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: AutofillGroup(
              child: Form(
                key: _formKey,
                child: ViewportScrollView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: EdgeInsets.fromLTRB(
                    horizontalPadding,
                    28,
                    horizontalPadding,
                    40,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'WEEKPACT',
                          style: TextStyle(
                            color: context.ink,
                            fontSize: 44,
                            height: 0.9,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -2.4,
                          ),
                        ),
                      ),
                      if (widget.pendingInviteToken != null) ...[
                        const SizedBox(height: 24),
                        BrutalShadow(
                          fillColor: context.mint,
                          shadowOffset: WeekPactMetrics.smallShadow,
                          child: Padding(
                            padding: EdgeInsets.all(14),
                            child: Text(
                              'CREW INVITE READY · LOG IN OR CREATE AN ACCOUNT WITH THE INVITED EMAIL.',
                              style: TextStyle(
                                color: context.ink,
                                fontSize: 13,
                                height: 1.25,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ),
                      ],
                      SizedBox(height: _isLogin ? 58 : 44),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 180),
                        child: Column(
                          key: ValueKey(_mode),
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _isLogin ? 'Welcome back.' : 'Make it official.',
                              style: TextStyle(
                                color: context.ink,
                                fontSize: size.width < 380 ? 38 : 46,
                                height: 0.95,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -1.8,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              _isLogin
                                  ? 'Good to see you again. Pick up where you left off.'
                                  : 'One account. Shared goals. A pact to show up.',
                              style: TextStyle(
                                color: context.ink,
                                fontSize: 17,
                                height: 1.35,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (widget.initialError != null) ...[
                        const SizedBox(height: 16),
                        Text(
                          widget.initialError!,
                          style: TextStyle(color: context.errorInk),
                        ),
                      ],
                      const SizedBox(height: 34),
                      BrutalTextField(
                        label: 'EMAIL',
                        hint: 'you@example.com',
                        controller: _emailController,
                        validator: _validateEmail,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        autofillHints: const [AutofillHints.email],
                      ),
                      const SizedBox(height: 24),
                      BrutalTextField(
                        label: 'PASSWORD',
                        hint: 'At least 8 characters',
                        controller: _passwordController,
                        validator: _validatePassword,
                        textInputAction: _isLogin
                            ? TextInputAction.done
                            : TextInputAction.next,
                        obscureText: _passwordHidden,
                        onToggleObscure: () =>
                            setState(() => _passwordHidden = !_passwordHidden),
                        autofillHints: [
                          _isLogin
                              ? AutofillHints.password
                              : AutofillHints.newPassword,
                        ],
                      ),
                      if (!_isLogin) ...[
                        const SizedBox(height: 24),
                        BrutalTextField(
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
                          autofillHints: const [AutofillHints.newPassword],
                        ),
                      ],
                      const SizedBox(height: 34),
                      BrutalButton(
                        label: _isLogin ? 'LOG IN' : 'CREATE ACCOUNT',
                        color: _isLogin ? context.coral : context.yellow,
                        isLoading: _submitting,
                        onPressed: _submit,
                      ),
                      const SizedBox(height: 34),
                      Row(
                        children: [
                          Expanded(
                            child: Divider(
                              color: context.border,
                              thickness: WeekPactMetrics.fineBorder,
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 22),
                            child: Text(
                              'OR',
                              style: TextStyle(
                                color: context.ink,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Divider(
                              color: context.border,
                              thickness: WeekPactMetrics.fineBorder,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
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
                        child: const Text(
                          'Forgot password or need a confirmation email?',
                        ),
                      ),
                      const PublicAccountLinks(),
                      const SizedBox(height: 28),
                      BrutalShadow(
                        child: TextButton(
                          onPressed: _submitting ? null : _switchMode,
                          style: TextButton.styleFrom(
                            foregroundColor: context.fieldInk,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(5),
                            ),
                            padding: WeekPactMetrics.buttonPadding,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            minimumSize: const Size(
                              0,
                              WeekPactMetrics.buttonHeight,
                            ),
                          ),
                          child: Text.rich(
                            TextSpan(
                              text: _isLogin ? 'New here?  ' : 'Already in?  ',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                              children: [
                                TextSpan(
                                  text: _isLogin ? 'CREATE ACCOUNT' : 'LOG IN',
                                  style: TextStyle(
                                    color: context.accent,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ],
                            ),
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
    );
  }
}
