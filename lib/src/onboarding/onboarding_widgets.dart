import 'package:flutter/material.dart';
import 'package:hugeicons/styles/stroke_rounded.dart';

import '../auth/auth_backend.dart';
import '../theme/weekpact_theme.dart';
import '../widgets/app_components.dart';
import '../widgets/app_icon.dart';

/// The frame every onboarding screen shares: back on the left, progress in
/// the middle, Log in on the right while there is no account yet; a question,
/// one short line under it, the answer, and the way on pinned at the foot.
class OnboardingScaffold extends StatelessWidget {
  const OnboardingScaffold({
    super.key,
    this.onBack,
    this.step,
    this.steps,
    this.onLogIn,
    this.eyebrow,
    required this.title,
    this.subtitle,
    required this.body,
    this.footer = const [],
    this.centered = false,
    this.centerBody = false,
  });

  final VoidCallback? onBack;

  /// 1-based. Both set, or neither.
  final int? step;
  final int? steps;
  final VoidCallback? onLogIn;
  final String? eyebrow;
  final String title;
  final String? subtitle;
  final List<Widget> body;
  final List<Widget> footer;

  /// For the screens that are one thing in the middle of the page.
  final bool centered;

  /// For a picture under the title: the body sits in the middle of whatever
  /// room the title and the pinned footer leave, rather than right under the
  /// subtitle. It still scrolls when that room runs out.
  final bool centerBody;

  @override
  Widget build(BuildContext context) {
    final head = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (eyebrow != null) ...[
          Text(
            eyebrow!,
            textAlign: centered ? TextAlign.center : TextAlign.start,
            style: TextStyle(
              color: context.muted,
              fontSize: 12,
              fontWeight: FontWeight.w500,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 8),
        ],
        Text(
          title,
          textAlign: centered ? TextAlign.center : TextAlign.start,
          style: TextStyle(
            color: context.ink,
            fontSize: 30,
            height: 1.1,
            fontWeight: FontWeight.w700,
            letterSpacing: -.3,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 8),
          Text(
            subtitle!,
            textAlign: centered ? TextAlign.center : TextAlign.start,
            style: TextStyle(color: context.muted, fontSize: 16, height: 1.4),
          ),
        ],
        const SizedBox(height: 20),
        if (centerBody)
          Expanded(
            child: Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: body),
            ),
          )
        else
          ...body,
      ],
    );
    // The answer scrolls; the way on stays pinned above the keyboard and the
    // home bar, so Continue is never below the fold on a small phone.
    const scrollPadding = EdgeInsets.only(top: 26, bottom: 12);
    final scroll = centerBody
        ? LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              padding: scrollPadding,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight - scrollPadding.vertical,
                ),
                child: IntrinsicHeight(child: head),
              ),
            ),
          )
        : SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: scrollPadding,
            child: head,
          );
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // A screen with nothing to go back to, no progress and no
                  // Log in (the front door) gives the bar's room to its title.
                  if (onBack != null || step != null || onLogIn != null)
                    SizedBox(
                      height: 48,
                      child: Row(
                        children: [
                          if (onBack != null)
                            OnboardingBackButton(onPressed: onBack!)
                          else
                            const SizedBox(width: 44),
                          const SizedBox(width: 14),
                          Expanded(
                            child: step != null && steps != null
                                ? StepPips(step: step!, steps: steps!)
                                : const SizedBox.shrink(),
                          ),
                          const SizedBox(width: 14),
                          if (onLogIn != null)
                            TextButton(
                              onPressed: onLogIn,
                              style: TextButton.styleFrom(
                                foregroundColor: context.muted,
                                minimumSize: const Size(44, 44),
                              ),
                              child: const Text(
                                'Log in',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            )
                          else
                            const SizedBox(width: 44),
                        ],
                      ),
                    ),
                  Expanded(child: centered ? Center(child: scroll) : scroll),
                  ...footer,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class OnboardingBackButton extends StatelessWidget {
  const OnboardingBackButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: 44,
    child: AppSurface(
      fillColor: WeekPactColors.graphite,
      outlineColor: WeekPactColors.graphiteEdge,
      resolveTone: false,
      shape: WeekPactMetrics.buttonShape,
      builder: (context) => IconButton(
        tooltip: 'Back',
        onPressed: onPressed,
        padding: EdgeInsets.zero,
        icon: const AppIcon(
          icon: HugeIconsStrokeRounded.arrowLeft01,
          color: WeekPactColors.darkInk,
          size: 22,
        ),
      ),
    ),
  );
}

/// Where in the setup the person is, as a row of pills.
class StepPips extends StatelessWidget {
  const StepPips({super.key, required this.step, required this.steps});

  final int step;
  final int steps;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Step $step of $steps',
    excludeSemantics: true,
    child: Row(
      children: [
        for (var i = 0; i < steps; i++) ...[
          if (i > 0) const SizedBox(width: 5),
          Expanded(
            child: Container(
              height: 6,
              decoration: BoxDecoration(
                color: i < step
                    ? WeekPactColors.mintGreen
                    : WeekPactColors.graphite,
                borderRadius: WeekPactMetrics.pill,
              ),
            ),
          ),
        ],
      ],
    ),
  );
}

/// Sign in with each provider this phone offers, Apple first where it is
/// offered at all.
class ProviderButtons extends StatelessWidget {
  const ProviderButtons({
    super.key,
    required this.providers,
    required this.onPressed,
    this.busy,
    this.verb = 'Continue',
  });

  final List<SignInProvider> providers;
  final ValueChanged<SignInProvider>? onPressed;

  /// The provider whose sheet is open, if any.
  final SignInProvider? busy;

  /// "Continue" for a new crew, "Join" for an invite.
  final String verb;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final (index, provider) in providers.indexed) ...[
        if (index > 0) const SizedBox(height: 10),
        AppButton(
          key: ValueKey('sign-in-${provider.name}'),
          label: switch (provider) {
            SignInProvider.apple => '$verb with Apple',
            SignInProvider.google => '$verb with Google',
          },
          icon: switch (provider) {
            SignInProvider.apple => HugeIconsStrokeRounded.apple,
            SignInProvider.google => HugeIconsStrokeRounded.google,
          },
          color: provider == SignInProvider.apple
              ? Colors.white
              : WeekPactColors.cream,
          height: 56,
          isLoading: busy == provider,
          onPressed: busy != null || onPressed == null
              ? null
              : () => onPressed!(provider),
        ),
      ],
    ],
  );
}

/// The one line of small print under the sign-in buttons.
class TermsLine extends StatelessWidget {
  const TermsLine({super.key});

  @override
  Widget build(BuildContext context) => Text(
    'By continuing you agree to the Terms and Privacy Policy.',
    textAlign: TextAlign.center,
    style: TextStyle(color: context.muted, fontSize: 12, height: 1.4),
  );
}

/// A sign-in that failed for a reason other than the person closing the
/// sheet, in words they can do something about.
String signInErrorMessage(Object error) {
  final message = error.toString();
  if (message.contains('SocketException') ||
      message.contains('Failed host lookup') ||
      message.contains('ClientException')) {
    return 'Could not reach WeekPact. Check your connection and try again.';
  }
  if (error is StateError) return error.message;
  return 'Sign-in didn’t go through. Please try again.';
}
