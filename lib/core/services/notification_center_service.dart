import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:teamcash/app/app.dart';
import 'package:teamcash/app/bootstrap/firebase_bootstrap.dart';
import 'package:teamcash/core/models/app_role.dart';
import 'package:teamcash/core/models/notification_models.dart';
import 'package:teamcash/core/models/workspace_models.dart';
import 'package:teamcash/core/session/app_session.dart';
import 'package:teamcash/core/session/session_controller.dart';

final notificationCenterServiceProvider =
    Provider<NotificationCenterService>(
      (ref) => NotificationCenterService(FirebaseFirestore.instance),
    );

final currentNotificationsProvider =
    StreamProvider<List<AppNotificationItem>>((ref) {
      final session = ref.watch(currentSessionProvider);
      final bootstrap = ref.watch(firebaseStatusProvider);
      final snapshot = ref.watch(appSnapshotProvider);

      if (session == null) {
        return Stream.value(const <AppNotificationItem>[]);
      }

      if (session.isPreview ||
          bootstrap.mode != FirebaseBootstrapMode.connected ||
          session.uid == null ||
          session.uid!.trim().isEmpty) {
        return Stream.value(
          _buildPreviewNotifications(
            session: session,
            snapshot: snapshot,
          ),
        );
      }

      return ref
          .watch(notificationCenterServiceProvider)
          .watchNotifications(session.uid!.trim());
    });

final unreadNotificationsCountProvider = Provider<int>((ref) {
  final notifications = ref.watch(currentNotificationsProvider).asData?.value;
  if (notifications == null) {
    return 0;
  }

  return notifications.where((notification) => !notification.isRead).length;
});

class NotificationCenterService {
  const NotificationCenterService(this._firestore);

  final FirebaseFirestore _firestore;

  Stream<List<AppNotificationItem>> watchNotifications(String uid) {
    return _firestore
        .collection('notifications')
        .where('recipientUid', isEqualTo: uid)
        .snapshots()
        .map((snapshot) {
          final notifications = snapshot.docs
              .map((doc) => _mapNotification(doc.id, doc.data()))
              .toList()
            ..sort(
              (left, right) => right.createdAt.compareTo(left.createdAt),
            );
          return notifications;
        });
  }

  Future<void> markRead(String notificationId) async {
    await _firestore.doc('notifications/$notificationId').update({
      'isRead': true,
      'readAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> markAllRead(Iterable<String> notificationIds) async {
    final ids = notificationIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
    if (ids.isEmpty) {
      return;
    }

    final batch = _firestore.batch();
    for (final id in ids) {
      batch.update(_firestore.doc('notifications/$id'), {
        'isRead': true,
        'readAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  }

  AppNotificationItem _mapNotification(
    String notificationId,
    Map<String, dynamic> data,
  ) {
    final createdAtRaw = data['createdAt'];
    final createdAt = createdAtRaw is Timestamp
        ? createdAtRaw.toDate()
        : DateTime.now();

    return AppNotificationItem(
      id: notificationId,
      title: data['title'] as String? ?? 'Notification',
      body: data['body'] as String? ?? '',
      type: data['kind'] as String? ?? 'general',
      createdAt: createdAt,
      isRead: data['isRead'] as bool? ?? false,
      roleSurface: data['roleSurface'] as String? ?? 'general',
      businessId: data['businessId'] as String?,
      customerId: data['customerId'] as String?,
      groupId: data['groupId'] as String?,
      entityId: data['entityId'] as String?,
      actionRoute: data['actionRoute'] as String?,
      actionLabel: data['actionLabel'] as String?,
    );
  }
}

List<AppNotificationItem> _buildPreviewNotifications({
  required AppSession session,
  required AppWorkspaceSnapshot snapshot,
}) {
  final now = DateTime.now();

  switch (session.role) {
    case AppRole.owner:
      final activeBusinessName = snapshot.owner.businesses.first.name;
      return [
        AppNotificationItem(
          id: 'preview-owner-join-request',
          title: 'Cedar Studio is waiting for your vote',
          body:
              'A pending join request is still open in Old Town Circle. Open group approvals from the owner surface to respond.',
          type: 'group_join_requested',
          createdAt: now.subtract(const Duration(minutes: 15)),
          isRead: false,
          roleSurface: 'owner',
          businessId: snapshot.owner.businesses.first.id,
          groupId: snapshot.owner.businesses.first.groupId,
          entityId: 'join-cedar',
          actionRoute: '/owner',
          actionLabel: 'Open approvals',
        ),
        AppNotificationItem(
          id: 'preview-owner-expiry-sweep',
          title: 'Expiry sweep recommended for $activeBusinessName',
          body:
              'Two cashback lots are approaching expiry and should be swept before the next reporting cycle.',
          type: 'expiry_sweep',
          createdAt: now.subtract(const Duration(hours: 3)),
          isRead: true,
          roleSurface: 'owner',
          businessId: snapshot.owner.businesses.first.id,
          groupId: snapshot.owner.businesses.first.groupId,
          actionRoute: '/owner',
          actionLabel: 'Open dashboard',
        ),
      ];
    case AppRole.staff:
      return [
        AppNotificationItem(
          id: 'preview-staff-shared-checkout',
          title: 'Shared checkout still needs participants',
          body:
              'Checkout SH-219 is open and still has a remaining balance. Keep it visible on the scan surface.',
          type: 'shared_checkout_open',
          createdAt: now.subtract(const Duration(minutes: 22)),
          isRead: false,
          roleSurface: 'staff',
          businessId: snapshot.staff.businessId,
          groupId: snapshot.staff.groupId,
          entityId: 'SH-219',
          actionRoute: '/staff',
          actionLabel: 'Open scan tab',
        ),
        AppNotificationItem(
          id: 'preview-staff-assignment',
          title: 'Single-business scope is active',
          body:
              'Your account remains limited to ${snapshot.staff.businessName}. Cross-business actions stay blocked by design.',
          type: 'staff_assignment',
          createdAt: now.subtract(const Duration(hours: 4)),
          isRead: true,
          roleSurface: 'staff',
          businessId: snapshot.staff.businessId,
          groupId: snapshot.staff.groupId,
          actionRoute: '/staff',
        ),
      ];
    case AppRole.client:
      return [
        AppNotificationItem(
          id: 'preview-client-gift',
          title: 'Pending gift is ready to claim',
          body:
              'A same-group cashback gift tied to your verified phone is waiting in the wallet transfer section.',
          type: 'gift_pending',
          createdAt: now.subtract(const Duration(minutes: 8)),
          isRead: false,
          roleSurface: 'client',
          customerId: 'preview-customer',
          groupId: snapshot.client.walletLots.first.groupId,
          actionRoute: '/client',
          actionLabel: 'Open wallet',
        ),
        AppNotificationItem(
          id: 'preview-client-expiry',
          title: 'Cashback will expire soon',
          body:
              'One of your active lots expires within the next 14 days. Review expiring cashback before checkout.',
          type: 'cashback_expiring',
          createdAt: now.subtract(const Duration(hours: 2)),
          isRead: true,
          roleSurface: 'client',
          customerId: 'preview-customer',
          groupId: snapshot.client.walletLots.first.groupId,
          actionRoute: '/client',
        ),
      ];
  }
}
