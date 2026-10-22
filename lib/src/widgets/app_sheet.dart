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
  const AppSheet({super.key, required this.builder});

  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) {
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
                color: context.surface,
                border: Border(
                  top: BorderSide(
                    color: context.border,
                    width: WeekPactMetrics.border,
                  ),
                ),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(WeekPactMetrics.sheetRadius),
                ),
              ),
              child: SafeArea(
                top: false,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Container(
                          width: 44,
                          height: 5,
                          decoration: BoxDecoration(
                            color: context.border,
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
