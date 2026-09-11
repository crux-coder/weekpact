import 'package:flutter/material.dart';

import '../theme/weekpact_theme.dart';
import 'app_components.dart';

/// Shared introduction card for signing in and setting up a profile.
class WelcomeCard extends StatelessWidget {
  const WelcomeCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.color,
    this.eyebrow,
  });
  final String title;
  final String subtitle;
  final String? eyebrow;
  final Color color;

  @override
  Widget build(BuildContext context) => AppSurface(
    fillColor: color,
    builder: (context) => Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (eyebrow != null) ...[
            Text(
              eyebrow!,
              style: TextStyle(
                color: context.muted,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 12),
          ],
          Text(
            title,
            style: TextStyle(
              color: context.ink,
              fontSize: 36,
              height: 1.05,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            subtitle,
            style: TextStyle(color: context.muted, fontSize: 16, height: 1.3),
          ),
        ],
      ),
    ),
  );
}
