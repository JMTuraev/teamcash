import 'package:flutter/material.dart';

import 'package:teamcash/core/models/notification_models.dart';
import 'package:teamcash/core/utils/formatters.dart';

class NotificationBellButton extends StatelessWidget {
  const NotificationBellButton({
    super.key,
    required this.unreadCount,
    required this.onPressed,
  });

  final int unreadCount;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        IconButton(
          key: const ValueKey('notification-bell-button'),
          tooltip: 'Notifications',
          onPressed: onPressed,
          icon: const Icon(Icons.notifications_none_outlined),
        ),
        if (unreadCount > 0)
          Positioned(
            right: 8,
            top: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFFB23A48),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                unreadCount > 99 ? '99+' : unreadCount.toString(),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

Future<void> showNotificationCenterBottomSheet({
  required BuildContext context,
  required String title,
  required List<AppNotificationItem> notifications,
  required Future<void> Function(String notificationId) onMarkRead,
  required Future<void> Function(List<String> notificationIds) onMarkAllRead,
  Future<void> Function(AppNotificationItem notification)? onOpenNotification,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) {
      return NotificationCenterSheet(
        title: title,
        notifications: notifications,
        onMarkRead: onMarkRead,
        onMarkAllRead: onMarkAllRead,
        onOpenNotification: onOpenNotification,
      );
    },
  );
}

class NotificationCenterSheet extends StatelessWidget {
  const NotificationCenterSheet({
    super.key,
    required this.title,
    required this.notifications,
    required this.onMarkRead,
    required this.onMarkAllRead,
    this.onOpenNotification,
  });

  final String title;
  final List<AppNotificationItem> notifications;
  final Future<void> Function(String notificationId) onMarkRead;
  final Future<void> Function(List<String> notificationIds) onMarkAllRead;
  final Future<void> Function(AppNotificationItem notification)?
  onOpenNotification;

  @override
  Widget build(BuildContext context) {
    final unreadNotifications = notifications
        .where((notification) => !notification.isRead)
        .toList();

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          key: const ValueKey('notification-center-sheet'),
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Close'),
                ),
                if (unreadNotifications.isNotEmpty)
                  TextButton(
                    key: const ValueKey('notification-center-mark-all-read'),
                    onPressed: () async {
                      await onMarkAllRead(
                        unreadNotifications
                            .map((notification) => notification.id)
                            .toList(),
                      );
                      if (!context.mounted) {
                        return;
                      }
                      Navigator.of(context).pop();
                    },
                    child: const Text('Mark all read'),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Flexible(
              child: notifications.isEmpty
                  ? _EmptyNotificationsState(title: title)
                  : ListView.separated(
                      shrinkWrap: true,
                      itemCount: notifications.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final notification = notifications[index];
                        return _NotificationTile(
                          notification: notification,
                          onMarkRead: notification.isRead
                              ? null
                              : () => onMarkRead(notification.id),
                          onOpen: onOpenNotification == null
                              ? null
                              : () async {
                                  if (!notification.isRead) {
                                    await onMarkRead(notification.id);
                                  }
                                  if (!context.mounted) {
                                    return;
                                  }
                                  Navigator.of(context).pop();
                                  await onOpenNotification!(notification);
                                },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({
    required this.notification,
    required this.onMarkRead,
    this.onOpen,
  });

  final AppNotificationItem notification;
  final Future<void> Function()? onMarkRead;
  final Future<void> Function()? onOpen;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: ValueKey('notification-tile-${notification.id}'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: notification.isRead ? Colors.white : const Color(0xFFEFF4FF),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: notification.isRead
              ? const Color(0xFFE6DED1)
              : const Color(0xFFC8DBF8),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  notification.title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: notification.isRead
                        ? FontWeight.w600
                        : FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                formatDateTime(notification.createdAt),
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: const Color(0xFF52606D)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            notification.body,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: const Color(0xFF52606D)),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              Chip(label: Text(notification.roleSurface)),
              Chip(label: Text(notification.type.replaceAll('_', ' '))),
              if (notification.groupId case final groupId?)
                Chip(label: Text(groupId)),
              if (notification.businessId case final businessId?)
                Chip(label: Text(businessId)),
              if (onOpen != null)
                FilledButton.tonal(
                  key: ValueKey('notification-open-${notification.id}'),
                  onPressed: () async {
                    await onOpen!();
                  },
                  child: Text(
                    notification.actionLabel?.trim().isNotEmpty == true
                        ? notification.actionLabel!.trim()
                        : 'Open',
                  ),
                ),
              if (notification.isRead == false)
                OutlinedButton(
                  key: ValueKey('notification-mark-read-${notification.id}'),
                  onPressed: onMarkRead == null
                      ? null
                      : () async {
                          await onMarkRead!();
                        },
                  child: const Text('Mark read'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EmptyNotificationsState extends StatelessWidget {
  const _EmptyNotificationsState({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F4EE),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'No notifications yet',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            '$title will appear here once backend events fan out to this account.',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: const Color(0xFF52606D)),
          ),
        ],
      ),
    );
  }
}
