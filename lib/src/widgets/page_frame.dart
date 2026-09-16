import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
        onRefresh: () {
          unawaited(HapticFeedback.mediumImpact().catchError((Object _) {}));
          return onRefresh!();
        },
        // context.surface is cream in both themes; a dark-canvas ink arrow
        // would be invisible on it.
        color: WeekPactColors.black,
        backgroundColor: WeekPactColors.cream,
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
  const PageHeading(
    this.title, {
    super.key,
    this.dotColor = WeekPactColors.coolGrey,
  });
  final String title;
  final Color dotColor;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      color: context.ink,
      fontSize: 32,
      height: 1.1,
      fontWeight: FontWeight.w900,
      letterSpacing: -.5,
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Flexible(child: Text(title, style: style)),
        ExcludeSemantics(
          child: Text('.', style: style.copyWith(color: dotColor)),
        ),
      ],
    );
  }
}

class SkeletonBar extends StatelessWidget {
  const SkeletonBar({
    super.key,
    this.width,
    required this.height,
    this.radius = 5,
    this.shape,
    this.color,
  });
  final double? width;
  final double height;
  final double radius;
  final ShapeBorder? shape;
  final Color? color;

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: height,
    decoration: ShapeDecoration(
      color: color ?? context.ink.withValues(alpha: .14),
      shape:
          shape ??
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
    ),
  );
}
