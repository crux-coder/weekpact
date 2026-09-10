import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Fills the available page height, and scrolls when content needs more space.
class ViewportScrollView extends StatelessWidget {
  const ViewportScrollView({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
    this.physics = const AlwaysScrollableScrollPhysics(),
    this.keyboardDismissBehavior = ScrollViewKeyboardDismissBehavior.manual,
  });

  final Widget child;
  final EdgeInsets padding;
  final ScrollPhysics physics;
  final ScrollViewKeyboardDismissBehavior keyboardDismissBehavior;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: physics,
        keyboardDismissBehavior: keyboardDismissBehavior,
        padding: padding,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: math.max(0, constraints.maxHeight - padding.vertical),
          ),
          child: child,
        ),
      ),
    );
  }
}
