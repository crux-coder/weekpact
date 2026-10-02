import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:hugeicons/styles/stroke_rounded.dart';

import '../crew/crew_backend.dart';
import '../invites/invite_link_entry.dart';
import '../widgets/app_icon.dart';
import '../theme/weekpact_theme.dart';
import '../widgets/app_components.dart';
import '../widgets/viewport_scroll_view.dart';
import '../widgets/welcome_card.dart';
import 'auth_backend.dart';
import 'password_page.dart';
import 'account_actions.dart';

/// The pages of the front door.
///
/// [welcome] is the first thing a new phone sees: two doors and a small line
/// for people who already have an account. [link] takes a pasted invite.
/// [invite] shows the crew behind a pending invitation before any form, so
/// creating an account is the price of joining something visible rather than
/// a wall in front of an empty app. [login] and [signup] are the forms.
enum AuthMode { welcome, link, invite, login, signup }

class AuthPage extends StatefulWidget {
  const AuthPage({
    super.key,
    required this.authBackend,
    this.pendingInviteToken,
    this.invitePreview,
    this.onInviteToken,
    this.initialError,
    this.returning = false,
  });

  final AuthBackend authBackend;
  final String? pendingInviteToken;

  /// Somebody who was signed in on this phone a moment ago. They know the
  /// app, so the page opens on the log-in form rather than the front door.
  final bool returning;

  /// What the pending invitation says about its crew, when it has arrived.
  /// Null while it loads, or when the token turned out to be nothing.
  final CrewInvitePreview? invitePreview;

  /// Handed the token from a pasted link. Null where nobody upstream can act
  /// on one, in which case the "I have an invite link" door is not offered.
  final ValueChanged<String>? onInviteToken;
  final String? initialError;

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  late AuthMode _mode = _initialMode;
  bool _passwordHidden = true;
  bool _confirmPasswordHidden = true;
  bool _submitting = false;

  bool get _isLogin => _mode == AuthMode.login;
  bool get _isForm => _mode == AuthMode.login || _mode == AuthMode.signup;
  bool get _hasInvite => widget.pendingInviteToken != null;

  /// An error from a failed email link belongs on the login form, where the
  /// fix is. An invitation opens on the crew it is for. Everyone else gets
  /// the front door.
  AuthMode get _initialMode => widget.initialError != null
      ? AuthMode.login
      : _hasInvite
      ? AuthMode.invite
      : widget.returning
      ? AuthMode.login
      : AuthMode.welcome;

  @override
  void didUpdateWidget(covariant AuthPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A failed email link is reported on the form where the fix is, wherever
    // the page was when the failure came in.
    if (widget.initialError != null && oldWidget.initialError == null) {
      setState(() => _mode = AuthMode.login);
      return;
    }
    // A link tapped while the front door is open, or pasted into it, turns
    // the page to the crew it names. A form already being filled in is left
    // alone; the chip on it picks the crew up.
    if (widget.pendingInviteToken != oldWidget.pendingInviteToken &&
        _hasInvite &&
        !_isForm) {
      setState(() => _mode = AuthMode.invite);
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _switchMode() => _setMode(_isLogin ? AuthMode.signup : AuthMode.login);

  /// Where "Back" from a form goes: to the crew when there is one, otherwise
  /// to the front door.
  void _back() => _setMode(_hasInvite ? AuthMode.invite : AuthMode.welcome);

  /// Clearing the form is the only way to take the fields' error text back off,
  /// and it takes the email with it. The address is put back afterwards:
  /// somebody who has just discovered they are on the wrong form has typed it
  /// once already, and the passwords are the only part that belongs to the
  /// form being left.
  void _setMode(AuthMode mode) {
    final email = _emailController.text;
    setState(() {
      _mode = mode;
      _submitting = false;
      _formKey.currentState?.reset();
      _emailController.text = email;
      _passwordController.clear();
      _confirmPasswordController.clear();
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
        if (result == SignUpResult.emailAlreadyRegistered && mounted) {
          _showMessage(
            'An account with this email already exists. Log in instead.',
          );
          _setMode(AuthMode.login);
        } else if (result == SignUpResult.emailConfirmationRequired &&
            mounted) {
          _showMessage('Check your email to confirm your account.');
          _setMode(AuthMode.login);
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
    if (token == null) return inviteRedirectBase;
    return Uri.parse(inviteRedirectBase)
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
                    _brand(context),
                    const SizedBox(height: 20),
                    ...switch (_mode) {
                      AuthMode.welcome => _welcome(context),
                      AuthMode.link => _link(context),
                      AuthMode.invite => _invite(context),
                      AuthMode.login || AuthMode.signup => _form(context),
                    },
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

  Widget _brand(BuildContext context) => Row(
    children: [
      // The asset is the full-bleed platform icon, so the home-screen corner
      // is cut here rather than baked in.
      ClipPath(
        clipper: const ShapeBorderClipper(
          shape: ContinuousRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(22)),
          ),
        ),
        child: Image.asset(
          'assets/branding/weekpact-icon.png',
          width: 44,
          height: 44,
          excludeFromSemantics: true,
        ),
      ),
      const SizedBox(width: 10),
      Flexible(
        child: Text(
          'WeekPact.',
          style: TextStyle(
            color: context.ink,
            fontSize: 28,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    ],
  );

  /// Two doors and a small line. No feature tour: the app explains itself
  /// by being used, and the first minute is spent getting into a crew.
  List<Widget> _welcome(BuildContext context) => [
    const WelcomeCard(
      title: 'Good habits.\nGreat company.',
      subtitle: 'A few friends, one small pact, one week at a time.',
      color: WeekPactColors.stone,
      eyebrow: 'WELCOME',
    ),
    const SizedBox(height: 8),
    AppSurface(
      builder: (context) => Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.onInviteToken != null) ...[
              AppButton(
                label: 'I HAVE AN INVITE LINK',
                icon: HugeIconsStrokeRounded.link01,
                color: WeekPactColors.lantern,
                onPressed: () => _setMode(AuthMode.link),
              ),
              const SizedBox(height: 10),
            ],
            AppButton(
              label: 'START A NEW CREW',
              icon: HugeIconsStrokeRounded.userGroup,
              color: WeekPactColors.mintGreen,
              onPressed: () => _setMode(AuthMode.signup),
            ),
          ],
        ),
      ),
    ),
    const SizedBox(height: 8),
    _modeSwitch(
      context,
      label: 'Already in?  LOG IN',
      color: WeekPactColors.coolGrey,
      onPressed: () => _setMode(AuthMode.login),
    ),
  ];

  List<Widget> _link(BuildContext context) => [
    const WelcomeCard(
      title: 'Got a link?',
      subtitle: 'Paste the invite your friend sent and we’ll find the crew.',
      color: WeekPactColors.lantern,
      eyebrow: 'JOIN A CREW',
    ),
    const SizedBox(height: 8),
    AppSurface(
      builder: (context) => Padding(
        padding: const EdgeInsets.all(18),
        child: InviteLinkEntry(
          buttonLabel: 'FIND MY CREW',
          onToken: widget.onInviteToken!,
        ),
      ),
    ),
    const SizedBox(height: 8),
    _backButton(context, () => _setMode(AuthMode.welcome)),
  ];

  /// The crew, before the form. Only what an invitation may say about it:
  /// its name, its size and who started it, or nothing while that loads.
  List<Widget> _invite(BuildContext context) => [
    AppSurface(
      fillColor: WeekPactColors.mintGreen,
      builder: (context) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'YOU’VE BEEN INVITED TO',
              style: TextStyle(
                color: context.muted,
                fontSize: 12,
                fontWeight: FontWeight.w500,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              widget.invitePreview?.crewName ?? 'A crew that’s waiting.',
              style: TextStyle(
                color: context.ink,
                fontSize: 36,
                height: 1.05,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              _inviteLine,
              style: TextStyle(color: context.muted, fontSize: 16, height: 1.3),
            ),
          ],
        ),
      ),
    ),
    const SizedBox(height: 8),
    AppSurface(
      builder: (context) => Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'One account, and you’re in. Your crew is waiting on the '
              'other side.',
              style: TextStyle(color: context.muted, height: 1.4),
            ),
            const SizedBox(height: 16),
            AppButton(
              label: _joinLabel,
              icon: HugeIconsStrokeRounded.arrowRight01,
              onPressed: () => _setMode(AuthMode.signup),
            ),
          ],
        ),
      ),
    ),
    const SizedBox(height: 8),
    _modeSwitch(
      context,
      label: 'Already in?  LOG IN',
      color: WeekPactColors.coolGrey,
      onPressed: () => _setMode(AuthMode.login),
    ),
  ];

  String get _inviteLine {
    final preview = widget.invitePreview;
    if (preview == null) return 'Sign in or create an account to join.';
    final members = preview.memberCount == 1
        ? '1 member'
        : '${preview.memberCount} members';
    return '$members · started by ${preview.ownerName}';
  }

  String get _joinLabel {
    final name = widget.invitePreview?.crewName;
    return name == null ? 'JOIN THE CREW' : 'JOIN ${name.toUpperCase()}';
  }

  List<Widget> _form(BuildContext context) => [
    WelcomeCard(
      title: _isLogin ? 'Welcome back.' : 'Make it official.',
      subtitle: _isLogin
          ? 'Your people. Your pacts. A fresh start today.'
          : 'Build better habits with your people.',
      color: _isLogin ? WeekPactColors.coolGrey : WeekPactColors.stone,
      eyebrow: _isLogin ? 'SHOW UP TOGETHER' : 'YOUR NEXT CHAPTER',
    ),
    const SizedBox(height: 8),
    if (_hasInvite) ...[
      AppSurface(
        fillColor: WeekPactColors.mintGreen,
        builder: (context) => Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              AppIcon(
                icon: HugeIconsStrokeRounded.userGroup,
                size: 20,
                color: context.ink,
              ),
              const SizedBox(width: 6),
              Expanded(
                // A share link takes any confirmed account, so the line
                // cannot send everyone hunting for an invited address most
                // of them were never sent.
                child: Text(
                  widget.invitePreview == null
                      ? 'Crew invite ready. Sign in or create an account '
                            'to join.'
                      : 'Joining ${widget.invitePreview!.crewName}',
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
              ),
            ],
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
              onToggleObscure: () =>
                  setState(() => _passwordHidden = !_passwordHidden),
              autofillHints: [
                _isLogin ? AutofillHints.password : AutofillHints.newPassword,
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
                  () => _confirmPasswordHidden = !_confirmPasswordHidden,
                ),
                autofillHints: const [AutofillHints.newPassword],
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
                          confirmationRedirect: _confirmationRedirectUrl,
                        ),
                      ),
                    ),
              style: TextButton.styleFrom(foregroundColor: context.muted),
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
    _modeSwitch(
      context,
      label: _isLogin ? 'New here?  CREATE ACCOUNT' : 'Already in?  LOG IN',
      color: _isLogin ? WeekPactColors.stone : WeekPactColors.coolGrey,
      onPressed: _switchMode,
    ),
    const SizedBox(height: 8),
    _backButton(context, _back),
  ];

  Widget _modeSwitch(
    BuildContext context, {
    required String label,
    required Color color,
    required VoidCallback onPressed,
  }) => AppSurface(
    fillColor: color,
    builder: (context) => TextButton(
      onPressed: _submitting ? null : onPressed,
      style: TextButton.styleFrom(
        foregroundColor: context.ink,
        minimumSize: const Size.fromHeight(52),
      ),
      child: Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
    ),
  );

  Widget _backButton(BuildContext context, VoidCallback onPressed) =>
      TextButton(
        onPressed: _submitting ? null : onPressed,
        style: TextButton.styleFrom(foregroundColor: context.muted),
        child: const Text('Back'),
      );
}
