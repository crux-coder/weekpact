import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../onboarding/onboarding_widgets.dart';
import '../theme/weekpact_theme.dart';
import '../widgets/app_components.dart';
import 'auth_backend.dart';
import 'password_page.dart';

/// Email and password, for accounts made before sign-up moved to Apple and
/// Google. There is no sign-up here, only the way back in and the reset.
class EmailLogInPage extends StatefulWidget {
  const EmailLogInPage({super.key, required this.authBackend});

  final AuthBackend authBackend;

  @override
  State<EmailLogInPage> createState() => _EmailLogInPageState();
}

class _EmailLogInPageState extends State<EmailLogInPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _passwordHidden = true;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await widget.authBackend.signIn(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
      // The auth stream replaces the onboarding under this route; this one
      // has to go too or it would sit on top of Home.
      if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
    } on AuthException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (error) {
      if (mounted) setState(() => _error = signInErrorMessage(error));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  String? _validateEmail(String? value) {
    final email = value?.trim() ?? '';
    if (email.isEmpty) return 'Email is required';
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      return 'Enter a valid email';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) => AutofillGroup(
    child: Form(
      key: _formKey,
      child: OnboardingScaffold(
        onBack: () => Navigator.of(context).pop(),
        title: 'Log in with email.',
        subtitle: 'For accounts made with an email and password.',
        body: [
          AppSurface(
            builder: (context) => Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
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
                    hint: 'Your password',
                    controller: _passwordController,
                    validator: (value) =>
                        (value ?? '').isEmpty ? 'Enter your password' : null,
                    textInputAction: TextInputAction.done,
                    obscureText: _passwordHidden,
                    onToggleObscure: () =>
                        setState(() => _passwordHidden = !_passwordHidden),
                    autofillHints: const [AutofillHints.password],
                  ),
                ],
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: context.errorInk)),
          ],
        ],
        footer: [
          AppButton(
            key: const ValueKey('email-log-in-submit'),
            label: 'LOG IN',
            color: WeekPactColors.mintGreen,
            height: 56,
            isLoading: _submitting,
            onPressed: _submit,
          ),
          const SizedBox(height: 4),
          TextButton(
            onPressed: _submitting
                ? null
                : () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => PasswordPage(
                        backend: widget.authBackend,
                        initialEmail: _emailController.text,
                      ),
                    ),
                  ),
            style: TextButton.styleFrom(foregroundColor: context.muted),
            child: const Text('Forgot your password?'),
          ),
        ],
      ),
    ),
  );
}
