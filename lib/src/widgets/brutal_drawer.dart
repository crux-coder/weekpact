import 'package:flutter/material.dart';

import '../theme/keepup_theme.dart';

Future<T?> showBrutalDrawer<T>({
  required BuildContext context,
  required WidgetBuilder builder,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: KeepUpColors.black.withValues(alpha: .55),
    constraints: BoxConstraints.tightFor(
      width: MediaQuery.sizeOf(context).width,
    ),
    builder: builder,
  );
}

/// A content-sized, edge-to-edge sheet with safe-area space inside its surface.
class BrutalDrawer extends StatelessWidget {
  const BrutalDrawer({super.key, required this.child});

  final Widget child;

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
                    width: KeepUpMetrics.border,
                  ),
                ),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
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
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      child,
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
