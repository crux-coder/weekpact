import 'package:flutter/material.dart';

import '../auth/auth_backend.dart';
import 'onboarding_page.dart';

/// Keeps onboarding mounted through the SDK's userUpdated event until saving finishes.
class OnboardingGate extends StatefulWidget {
  const OnboardingGate({
    super.key,
    required this.user,
    required this.backend,
    this.onCompleted,
    required this.builder,
    this.joiningCrewName,
  });
  final AuthUser user;
  final AuthBackend backend;
  final String? joiningCrewName;

  /// Optional: a caller that has nothing to retire when the profile is saved
  /// leaves it out rather than passing an empty callback.
  final VoidCallback? onCompleted;
  final Widget Function(AuthUser) builder;
  @override
  State<OnboardingGate> createState() => _OnboardingGateState();
}

class _OnboardingGateState extends State<OnboardingGate> {
  late bool _complete = widget.user.onboardingCompleted;
  AuthUser? _savedUser;
  @override
  Widget build(BuildContext context) {
    if (_complete) return widget.builder(_savedUser ?? widget.user);
    return OnboardingPage(
      user: widget.user,
      backend: widget.backend,
      joiningCrewName: widget.joiningCrewName,
      onCompleted: (user) {
        widget.onCompleted?.call();
        setState(() {
          _savedUser = user;
          _complete = true;
        });
      },
    );
  }
}
