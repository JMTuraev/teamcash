import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:teamcash/app/app.dart';
import 'package:teamcash/core/models/notification_models.dart';
import 'package:teamcash/features/shared/presentation/notification_center_widgets.dart';

void main() {
  testWidgets('role hub renders production shells entry points', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      TeamCashApp(bootstrapState: AppBootstrapState.preview()),
    );

    await tester.pumpAndSettle();

    expect(
      find.text('Private cashback tandems for trusted business groups'),
      findsOneWidget,
    );
    expect(find.text('Open Owner Surface'), findsOneWidget);
    expect(find.text('Open Staff Surface'), findsOneWidget);
    expect(find.text('Open Client Surface'), findsOneWidget);
  });

  testWidgets('owner preview route shows catalog and branding sections', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      TeamCashApp(bootstrapState: AppBootstrapState.preview()),
    );

    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('role-action-owner')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('owner-workspace-root')), findsOneWidget);
    await tester.tap(find.text('Businesses').last);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('owner-live-catalog-section')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('owner-branding-section')),
      findsOneWidget,
    );

    await tester.tap(find.text('Dashboard').last);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('owner-dashboard-trend-section')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('owner-business-performance-section')),
      findsOneWidget,
    );
    await tester.tap(find.text('Staffs').last);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('owner-group-audit-section')),
      findsOneWidget,
    );
  });

  testWidgets('staff preview route shows trend and quick actions', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      TeamCashApp(bootstrapState: AppBootstrapState.preview()),
    );

    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('role-action-staff')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('staff-workspace-root')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('staff-quick-actions-section')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('staff-trend-section')), findsOneWidget);
    await tester.tap(find.text('Scan').last);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('staff-customer-identifier-input')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('staff-customer-identifier-resolve')),
      findsOneWidget,
    );
    await tester.tap(find.text('Profile').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('staff-profile-section')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('staff-profile-edit-action')),
      findsOneWidget,
    );
  });

  testWidgets('client preview route shows live store catalog details', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      TeamCashApp(bootstrapState: AppBootstrapState.preview()),
    );

    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('role-action-client')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('client-workspace-root')), findsOneWidget);
    await tester.tap(find.text('Stores').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('client-stores-section')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('client-store-silk-road-cafe')),
      findsOneWidget,
    );
    await tester.tap(find.text('Profile').last);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('client-profile-section')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('client-identity-qr-card')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('client-identity-qr-symbol')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('client-profile-edit-action')),
      findsOneWidget,
    );
    await tester.tap(find.text('Stores').last);
    await tester.pumpAndSettle();
    final detailOpener = tester.widget<GestureDetector>(
      find.byKey(const ValueKey('client-store-open-details-silk-road-cafe')),
    );
    detailOpener.onTap?.call();
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('client-store-detail-sheet-silk-road-cafe')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('client-store-detail-products-silk-road-cafe')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('client-store-detail-services-silk-road-cafe')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('client-store-media-silk-road-cafe-detail')),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey(
          'client-store-media-item-silk-road-cafe-detail-silk-road-cover',
        ),
      ),
      findsOneWidget,
    );
  });

  testWidgets('notification center sheet renders unread entries', (
    tester,
  ) async {
    String? openedNotificationId;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NotificationCenterSheet(
            title: 'Owner notifications',
            notifications: [
              AppNotificationItem(
                id: 'n1',
                title: 'Cedar Studio is waiting for your vote',
                body: 'Open approvals to accept or reject the join request.',
                type: 'group_join_requested',
                createdAt: DateTime(2026, 4, 7, 12, 0),
                isRead: false,
                roleSurface: 'owner',
                businessId: 'cedar-studio',
                groupId: 'old-town-circle',
                entityId: 'join-cedar',
              ),
            ],
            onMarkRead: (_) async {},
            onMarkAllRead: (_) async {},
            onOpenNotification: (notification) async {
              openedNotificationId = notification.id;
            },
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('notification-center-sheet')),
      findsOneWidget,
    );
    expect(find.text('Owner notifications'), findsOneWidget);
    expect(find.textContaining('Cedar Studio'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('notification-mark-read-n1')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('notification-open-n1')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('notification-open-n1')));
    await tester.pumpAndSettle();
    expect(openedNotificationId, 'n1');
  });
}
