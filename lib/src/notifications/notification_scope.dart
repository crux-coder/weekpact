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
}
