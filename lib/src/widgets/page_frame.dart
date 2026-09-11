import 'package:flutter/material.dart';

import '../theme/weekpact_theme.dart';
import 'viewport_scroll_view.dart';

/// Shared full-height page shell. Headers stay visible during initial loading.
class PageFrame extends StatelessWidget {
  const PageFrame({
    super.key,
    required this.header,
    required this.child,
    this.loading = false,
    this.skeleton,
    this.onRefresh,
    this.footer,
    this.topPadding = 16,
  }) : assert(!loading || skeleton != null);

  final double topPadding;
  final Widget header;
  final Widget child;
  final bool loading;
  final Widget? skeleton;
  final Future<void> Function()? onRefresh;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    Widget content = ViewportScrollView(
      padding: EdgeInsets.fromLTRB(12, topPadding, 12, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          const SizedBox(height: WeekPactMetrics.sectionGap),
          if (loading) skeleton! else child,
        ],
      ),
    );
    if (onRefresh != null) {
      content = RefreshIndicator(
        onRefresh: onRefresh!,
        color: context.ink,
        backgroundColor: context.surface,
        child: content,
      );
    }
    return SafeArea(
      bottom: false,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: content),
              if (footer != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                  child: footer!,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class PageHeading extends StatelessWidget {
  const PageHeading(this.title, {super.key});
  final String title;

  @override
  Widget build(BuildContext context) => Text(
    title,
    style: TextStyle(
      color: context.ink,
      fontSize: 32,
      height: 1.1,
      fontWeight: FontWeight.w900,
      letterSpacing: -.5,
    ),
  );
}

class SkeletonBar extends StatelessWidget {
  const SkeletonBar({
    super.key,
    this.width,
    required this.height,
    this.radius = 5,
  });
  final double? width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: height,
    decoration: BoxDecoration(
      color: context.ink.withValues(alpha: .14),
      borderRadius: BorderRadius.circular(radius),
    ),
  );
}
