import 'package:flutter/material.dart';

import '../theme/weekpact_theme.dart';

/// Completes once the sheet is gone, not merely popped, so callers can follow a
/// sheet with motion of their own without it playing behind the closing drawer.
Future<T?> showAppSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
}) async {
  ModalRoute<T>? route;
  final result = await showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: WeekPactColors.barrier,
    constraints: BoxConstraints.tightFor(
      width: MediaQuery.sizeOf(context).width,
    ),
    builder: (context) {
      route ??= ModalRoute.of<T>(context);
      return AppSurfaceTheme(builder: builder);
    },
  );
  await route?.completed;
  return result;
}

/// A content-sized, edge-to-edge sheet with safe-area space inside its surface.
class AppSheet extends StatelessWidget {
  const AppSheet({super.key, required this.builder, this.dark = false});

  final WidgetBuilder builder;

  /// Draws the sheet on the dark card surface, with its content in the dark
  /// theme, for sheets that open over a dark page such as a story.
  final bool dark;

  @override
  Widget build(BuildContext context) {
    if (dark) {
      return Theme(
        data: WeekPactTheme.dark,
        child: Builder(
          builder: (context) => DefaultTextStyle(
            style: Theme.of(context).textTheme.bodyMedium!,
            child: IconTheme(
              data: const IconThemeData(color: WeekPactDarkCard.ink),
              child: _build(context),
            ),
          ),
        ),
      );
    }
    return _build(context);
  }

  Widget _build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final keyboard = MediaQuery.viewInsetsOf(context).bottom;
        return Padding(
          padding: EdgeInsets.only(bottom: keyboard),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight:
                  (constraints.maxHeight - keyboard).clamp(0, double.infinity) *
                  .95,
            ),
            child: Container(
              width: double.infinity,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: dark ? WeekPactDarkCard.fill : context.surface,
                border: Border(
                  top: BorderSide(
                    color: dark ? WeekPactDarkCard.outline : context.border,
                    width: WeekPactMetrics.border,
                  ),
                ),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(WeekPactMetrics.sheetRadius),
                ),
              ),
              // A sheet runs on under the home indicator rather than
              // stopping at the safe area; the padding keeps its end clear.
              child: SafeArea(
                top: false,
                bottom: false,
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                    16,
                    12,
                    16,
                    24 + MediaQuery.paddingOf(context).bottom,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Container(
                          width: 44,
                          height: 5,
                          decoration: BoxDecoration(
                            color: dark
                                ? WeekPactDarkCard.ink.withValues(alpha: .2)
                                : context.border,
                            borderRadius: WeekPactMetrics.pill,
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      builder(context),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

Future<T?> showAppDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
}) => showDialog<T>(
  context: context,
  barrierColor: WeekPactColors.barrier,
  builder: (context) => AppSurfaceTheme(builder: builder),
);
