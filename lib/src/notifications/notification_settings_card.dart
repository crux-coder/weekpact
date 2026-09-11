import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/weekpact_theme.dart';
import '../widgets/app_components.dart';
import 'notification_scope.dart';

class NotificationSettingsCard extends StatelessWidget {
  const NotificationSettingsCard({super.key});

  @override
  Widget build(BuildContext context) {
    final service = NotificationScope.maybeOf(context);
    if (service == null) return const SizedBox.shrink();
    final denied = service.permission == AuthorizationStatus.denied;
    return Padding(
      padding: const EdgeInsets.only(top: 26),
      child: AppSectionCard(
        title: 'Notifications',
        builder: (context) => Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                !service.available
                    ? 'Notifications aren’t available in this build yet.'
                    : service.enabled &&
                          service.allowed &&
                          service.token != null
                    ? 'Notifications are enabled on this device.'
                    : denied
                    ? 'Allow notifications in your phone’s app settings, then return here.'
                    : service.enabled
                    ? 'Finishing notification setup…'
                    : 'Choose whether WeekPact can send notifications to this device.',
                style: TextStyle(color: context.ink, fontSize: 16),
              ),
              if (service.error != null && service.available) ...[
                const SizedBox(height: 10),
                Text(service.error!, style: TextStyle(color: context.errorInk)),
              ],
              if (service.registrationError != null) ...[
                const SizedBox(height: 10),
                Text(
                  service.registrationError!,
                  style: TextStyle(color: context.errorInk),
                ),
              ],
              const SizedBox(height: 12),
              AppButton(
                label: !service.available
                    ? 'RETRY SETUP'
                    : service.enabled
                    ? 'TURN OFF'
                    : 'ENABLE NOTIFICATIONS',

                isLoading: service.busy,
                onPressed: service.busy
                    ? null
                    : !service.available
                    ? service.initialize
                    : service.enabled
                    ? service.disable
                    : service.enable,
              ),
              if (service.available &&
                  service.enabled &&
                  (service.token == null || service.registrationError != null))
                TextButton(
                  onPressed: service.busy ? null : service.refresh,
                  child: const Text('Retry registration'),
                ),
              if (kDebugMode && service.token != null) ...[
                TextButton(
                  onPressed: () async {
                    await Clipboard.setData(
                      ClipboardData(text: service.token!),
                    );
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Test device token copied.'),
                        ),
                      );
                    }
                  },
                  child: const Text('Copy FCM test token'),
                ),
                Text(
                  'Foreground messages: ${service.receivedCount} · Opened notification: ${service.lastOpenedMessage == null ? 'no' : 'yes'}',
                  style: TextStyle(color: context.muted, fontSize: 12),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
