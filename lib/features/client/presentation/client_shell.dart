import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:teamcash/app/app.dart';
import 'package:teamcash/core/models/app_role.dart';
import 'package:teamcash/core/models/business_content_models.dart';
import 'package:teamcash/core/models/business_models.dart';
import 'package:teamcash/core/models/customer_identity_models.dart';
import 'package:teamcash/core/models/notification_models.dart';
import 'package:teamcash/core/models/wallet_models.dart';
import 'package:teamcash/core/models/workspace_models.dart';
import 'package:teamcash/core/services/account_profile_service.dart';
import 'package:teamcash/core/services/customer_identity_token_service.dart';
import 'package:teamcash/core/services/notification_center_service.dart';
import 'package:teamcash/core/services/teamcash_functions_service.dart';
import 'package:teamcash/core/session/session_controller.dart';
import 'package:teamcash/core/utils/formatters.dart';
import 'package:teamcash/data/firestore/firestore_workspace_repository.dart';
import 'package:teamcash/features/client/application/client_transfer_controller.dart';
import 'package:teamcash/features/shared/presentation/customer_identity_widgets.dart';
import 'package:teamcash/features/shared/presentation/notification_center_widgets.dart';
import 'package:teamcash/features/shared/presentation/shell_widgets.dart';

part 'client_shell_chrome.dart';
part 'client_shell_stores.dart';
part 'client_shell_wallet.dart';
part 'client_shell_history.dart';
part 'client_shell_profile.dart';

class ClientShell extends ConsumerStatefulWidget {
  const ClientShell({super.key});

  @override
  ConsumerState<ClientShell> createState() => _ClientShellState();
}

class _ClientShellState extends ConsumerState<ClientShell> {
  int _selectedIndex = 1;
  bool _hasAppliedPreferredTab = false;

  @override
  Widget build(BuildContext context) {
    final previewClient = ref.watch(appSnapshotProvider).client;
    final session = ref.watch(currentSessionProvider);
    final clientAsync = ref.watch(clientWorkspaceProvider);
    final notificationsAsync = ref.watch(currentNotificationsProvider);
    final canRunLiveTransfers =
        session?.role == AppRole.client &&
        session?.isPreview == false &&
        (session?.customerId?.isNotEmpty ?? false);
    final hasVerifiedPhoneClaimActions =
        session?.role == AppRole.client &&
        session?.isPreview == false &&
        (session?.phoneNumber?.isNotEmpty ?? false);
    final notifications =
        notificationsAsync.asData?.value ?? const <AppNotificationItem>[];
    final unreadNotificationsCount = notifications
        .where((notification) => !notification.isRead)
        .length;

    if (canRunLiveTransfers && clientAsync.isLoading && !clientAsync.hasValue) {
      return Scaffold(
        appBar: AppBar(title: const Text('Client wallet')),
        body: const SafeArea(child: Center(child: CircularProgressIndicator())),
      );
    }

    if (canRunLiveTransfers && clientAsync.hasError && !clientAsync.hasValue) {
      return Scaffold(
        appBar: AppBar(title: const Text('Client wallet')),
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Client wallet could not be loaded from Firestore.',
                  ),
                  const SizedBox(height: 12),
                  Text(
                    clientAsync.error.toString(),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () => ref.invalidate(clientWorkspaceProvider),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final client = canRunLiveTransfers
        ? clientAsync.requireValue
        : previewClient;
    _applyPreferredTabIfNeeded(client.preferredStartTabIndex);
    final customerIdentityToken = ref
        .watch(customerIdentityTokenServiceProvider)
        .buildForClient(client: client, session: session);

    final incomingPendingAmount = client.pendingTransfers
        .where(
          (transfer) => transfer.direction == PendingTransferDirection.incoming,
        )
        .fold<int>(0, (sum, transfer) => sum + transfer.amount);
    final activePartnerCount = client.storeDirectory
        .where((store) => store.groupStatus == GroupMembershipStatus.active)
        .length;
    final expiringLotsCount = client.walletLots
        .where((lot) => lot.expiresAt.difference(DateTime.now()).inDays <= 14)
        .length;

    return Scaffold(
      key: const ValueKey('client-workspace-root'),
      body: AppBackdrop(
        child: SafeArea(
          child: MobileAppFrame(
            padding: const EdgeInsets.fromLTRB(10, 4, 10, 14),
            child: Column(
              children: [
                _ClientTopBar(
                  greeting: _greetingForNow(),
                  clientName: client.clientName,
                  onOpenNotifications: () =>
                      _openNotificationsCenter(notifications, client),
                  unreadNotificationsCount: unreadNotificationsCount,
                  onSignOut: session?.role == AppRole.client
                      ? () async {
                          await ref
                              .read(appSessionControllerProvider.notifier)
                              .signOut();
                          if (!context.mounted) return;
                          context.go('/');
                        }
                      : null,
                ),
                const SizedBox(height: 8),
                HeroSummaryCard(
                  eyebrow: 'Total cashback',
                  title: formatCurrency(client.totalWalletBalance),
                  badge: activePartnerCount > 0
                      ? '$activePartnerCount partners'
                      : 'Wallet ready',
                  icon: Icons.verified_outlined,
                  supporting: Wrap(
                    spacing: 14,
                    runSpacing: 10,
                    children: [
                      _HeroStat(
                        label: 'Available',
                        value: formatCurrency(client.totalWalletBalance),
                        icon: Icons.check_circle_outline_rounded,
                      ),
                      _HeroStat(
                        label: 'Pending',
                        value: formatCurrency(incomingPendingAmount),
                        icon: Icons.schedule_rounded,
                      ),
                      _HeroStat(
                        label: 'Expiring',
                        value: '$expiringLotsCount lots',
                        icon: Icons.timelapse_rounded,
                      ),
                    ],
                  ),
                  footer: Text(
                    session?.isPreview == false
                        ? hasVerifiedPhoneClaimActions
                              ? 'Verified phone is linked. The wallet keeps its older phone-first history.'
                              : 'Client session is attached, but the real claim still runs through phone verification.'
                        : 'Preview mode keeps the mobile wallet flow reviewable without extra setup.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.white.withValues(alpha: 0.82),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    QuickActionTile(
                      icon: Icons.storefront_outlined,
                      label: 'Partners',
                      tint: const Color(0xFF5D6BFF),
                      onTap: () => setState(() => _selectedIndex = 0),
                    ),
                    QuickActionTile(
                      icon: Icons.card_giftcard_outlined,
                      label: 'Send Gift',
                      tint: const Color(0xFFFF8C6B),
                      onTap: () => setState(() => _selectedIndex = 1),
                    ),
                    QuickActionTile(
                      icon: Icons.receipt_long_outlined,
                      label: 'Activity',
                      tint: const Color(0xFF8F6CFF),
                      onTap: () => setState(() => _selectedIndex = 2),
                    ),
                    QuickActionTile(
                      icon: Icons.qr_code_2_outlined,
                      label: 'Profile ID',
                      tint: const Color(0xFF45C1B2),
                      onTap: () => setState(() => _selectedIndex = 3),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: IndexedStack(
                    index: _selectedIndex,
                    children: [
                      _StoresTab(stores: client.storeDirectory),
                      _WalletTab(
                        client: client,
                        canRunLiveTransferActions: canRunLiveTransfers,
                        hasVerifiedPhoneClaimActions:
                            hasVerifiedPhoneClaimActions,
                        customerId: session?.customerId,
                      ),
                      _HistoryTab(events: client.history),
                      _ProfileTab(
                        client: client,
                        customerIdentityToken: customerIdentityToken,
                        customerId: session?.customerId,
                        canEditProfile:
                            session?.role == AppRole.client &&
                            session?.isPreview == false &&
                            (session?.customerId?.isNotEmpty ?? false),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: NavigationBar(
            selectedIndex: _selectedIndex,
            onDestinationSelected: (index) {
              setState(() {
                _selectedIndex = index;
              });
            },
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home_rounded),
                label: 'Stores',
              ),
              NavigationDestination(
                icon: Icon(Icons.account_balance_wallet_outlined),
                selectedIcon: Icon(Icons.account_balance_wallet_rounded),
                label: 'Wallet',
              ),
              NavigationDestination(
                icon: Icon(Icons.receipt_long_outlined),
                selectedIcon: Icon(Icons.receipt_long_rounded),
                label: 'Activity',
              ),
              NavigationDestination(
                icon: Icon(Icons.person_outline_rounded),
                selectedIcon: Icon(Icons.person_rounded),
                label: 'Profile',
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _applyPreferredTabIfNeeded(int preferredTabIndex) {
    if (_hasAppliedPreferredTab) {
      return;
    }

    _hasAppliedPreferredTab = true;
    if (_selectedIndex == preferredTabIndex) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _selectedIndex = preferredTabIndex;
      });
    });
  }

  Future<void> _openNotificationsCenter(
    List<AppNotificationItem> notifications,
    ClientWorkspace client,
  ) async {
    await showNotificationCenterBottomSheet(
      context: context,
      title: 'Client notifications',
      notifications: notifications,
      onMarkRead: (notificationId) async {
        final session = ref.read(currentSessionProvider);
        if (session == null || session.isPreview) {
          return;
        }
        await ref
            .read(notificationCenterServiceProvider)
            .markRead(notificationId);
      },
      onMarkAllRead: (notificationIds) async {
        final session = ref.read(currentSessionProvider);
        if (session == null || session.isPreview) {
          return;
        }
        await ref
            .read(notificationCenterServiceProvider)
            .markAllRead(notificationIds);
      },
      onOpenNotification: (notification) async {
        _openClientNotification(notification, client);
      },
    );
  }

  void _openClientNotification(
    AppNotificationItem notification,
    ClientWorkspace client,
  ) {
    final route = notification.actionRoute?.trim();
    if (route != null && route.isNotEmpty && route != '/client') {
      context.go(route);
      return;
    }

    setState(() {
      _selectedIndex = _clientTabForNotification(notification, client);
    });
  }

  int _clientTabForNotification(
    AppNotificationItem notification,
    ClientWorkspace client,
  ) {
    switch (notification.type) {
      case 'cashback_expiring':
      case 'gift_pending':
      case 'gift_claimed':
      case 'shared_checkout_created':
      case 'shared_checkout_contribution':
      case 'shared_checkout_finalized':
        return 1;
      case 'cashback_issued':
      case 'cashback_redeemed':
      case 'cashback_refunded':
      case 'cashback_expired':
      case 'admin_adjustment':
        return 2;
      case 'business_updated':
        return 0;
      default:
        return client.pendingTransfers.isNotEmpty ? 1 : 2;
    }
  }

  String _greetingForNow() {
    final hour = DateTime.now().hour;
    if (hour < 12) {
      return 'Good morning';
    }
    if (hour < 18) {
      return 'Good afternoon';
    }
    return 'Good evening';
  }
}
