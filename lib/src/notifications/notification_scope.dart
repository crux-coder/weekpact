import 'package:flutter/widgets.dart';

import 'notification_service.dart';

class NotificationScope extends InheritedNotifier<NotificationService> {
  const NotificationScope({
    super.key,
    required NotificationService service,
    required super.child,
  }) : super(notifier: service);

  static NotificationService? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<NotificationScope>()?.notifier;

  /// The service without rebuilding when it changes: for listening to its
  /// streams rather than showing its state.
  static NotificationService? read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<NotificationScope>()?.notifier;
}
