class AppNotificationItem {
  const AppNotificationItem({
    required this.id,
    required this.title,
    required this.body,
    required this.type,
    required this.createdAt,
    required this.isRead,
    required this.roleSurface,
    this.businessId,
    this.customerId,
    this.groupId,
    this.entityId,
    this.actionRoute,
    this.actionLabel,
  });

  final String id;
  final String title;
  final String body;
  final String type;
  final DateTime createdAt;
  final bool isRead;
  final String roleSurface;
  final String? businessId;
  final String? customerId;
  final String? groupId;
  final String? entityId;
  final String? actionRoute;
  final String? actionLabel;
}
