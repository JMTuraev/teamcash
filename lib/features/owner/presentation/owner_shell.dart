import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:teamcash/app/app.dart';
import 'package:teamcash/core/models/business_models.dart';
import 'package:teamcash/core/models/business_content_models.dart';
import 'package:teamcash/core/models/dashboard_models.dart';
import 'package:teamcash/core/models/notification_models.dart';
import 'package:teamcash/core/models/app_role.dart';
import 'package:teamcash/core/models/workspace_models.dart';
import 'package:teamcash/core/services/business_asset_picker.dart';
import 'package:teamcash/core/services/notification_center_service.dart';
import 'package:teamcash/core/services/owner_business_admin_service.dart';
import 'package:teamcash/core/services/teamcash_functions_service.dart';
import 'package:teamcash/core/session/session_controller.dart';
import 'package:teamcash/core/utils/formatters.dart';
import 'package:teamcash/data/firestore/firestore_workspace_repository.dart';
import 'package:teamcash/features/shared/presentation/notification_center_widgets.dart';
import 'package:teamcash/features/shared/presentation/shell_widgets.dart';

part 'owner_shell_mobile.dart';
part 'owner_shell_businesses.dart';
part 'owner_shell_dashboard.dart';
part 'owner_shell_staff.dart';
part 'owner_shell_dialog_models.dart';
part 'owner_shell_business_dialogs.dart';
part 'owner_shell_finance_dialogs.dart';
part 'owner_shell_staff_dialogs.dart';

enum _CatalogCollectionType { product, service }

enum _StaffAccountAction { edit, resetPassword, disable }

enum _AdjustmentDirection { credit, debit }

class OwnerShell extends ConsumerStatefulWidget {
  const OwnerShell({super.key, this.initialTabIndex});

  final int? initialTabIndex;

  @override
  ConsumerState<OwnerShell> createState() => _OwnerShellState();
}

class _OwnerShellState extends ConsumerState<OwnerShell> {
  int _selectedIndex = 1;
  late String _activeBusinessId;
  bool _ownerActionInProgress = false;

  @override
  void initState() {
    super.initState();
    final businesses = ref.read(appSnapshotProvider).owner.businesses;
    _activeBusinessId = businesses.first.id;
    _selectedIndex = _normalizeTabIndex(widget.initialTabIndex, fallback: 1);
  }

  @override
  Widget build(BuildContext context) {
    final previewOwner = ref.watch(appSnapshotProvider).owner;
    final session = ref.watch(currentSessionProvider);
    final ownerAsync = ref.watch(ownerWorkspaceProvider);
    final notificationsAsync = ref.watch(currentNotificationsProvider);
    final expectsLiveWorkspace =
        session?.role == AppRole.owner && session?.isPreview == false;
    final notifications =
        notificationsAsync.asData?.value ?? const <AppNotificationItem>[];
    final unreadNotificationsCount = notifications
        .where((notification) => !notification.isRead)
        .length;

    if (expectsLiveWorkspace && ownerAsync.isLoading && !ownerAsync.hasValue) {
      return Scaffold(
        appBar: AppBar(title: const Text('Owner workspace')),
        body: const SafeArea(child: Center(child: CircularProgressIndicator())),
      );
    }

    if (expectsLiveWorkspace && ownerAsync.hasError && !ownerAsync.hasValue) {
      return Scaffold(
        appBar: AppBar(title: const Text('Owner workspace')),
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Owner workspace could not be loaded from Firestore.',
                  ),
                  const SizedBox(height: 12),
                  Text(
                    ownerAsync.error.toString(),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () => ref.invalidate(ownerWorkspaceProvider),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final owner = expectsLiveWorkspace ? ownerAsync.requireValue : previewOwner;
    if (owner.businesses.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text('Owner workspace · ${owner.ownerName}')),
        body: const SafeArea(
          child: Center(
            child: Text('No businesses were found for this owner.'),
          ),
        ),
      );
    }

    final activeBusiness = owner.businesses.firstWhere(
      (business) => business.id == _activeBusinessId,
      orElse: () => owner.businesses.first,
    );
    final canManageOwnerActions =
        session?.role == AppRole.owner && session?.isPreview == false;

    if (MediaQuery.sizeOf(context).height > 0) {
      return Scaffold(
        key: const ValueKey('owner-workspace-root'),
        body: AppBackdrop(
          child: SafeArea(
            minimum: const EdgeInsets.fromLTRB(12, 10, 12, 0),
            child: MobileAppFrame(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 16, 14, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _OwnerMobileHeader(
                      ownerName: owner.ownerName,
                      activeBusinessName: activeBusiness.name,
                      unreadNotificationsCount: unreadNotificationsCount,
                      onOpenNotifications: () =>
                          _openNotificationsCenter(notifications, owner),
                      onSignOut: session?.role == AppRole.owner
                          ? () async {
                              await ref
                                  .read(appSessionControllerProvider.notifier)
                                  .signOut();
                              if (!context.mounted) return;
                              context.go('/');
                            }
                          : null,
                    ),
                    const SizedBox(height: 12),
                    _OwnerMobileSummaryCard(
                      ownerName: owner.ownerName,
                      activeBusiness: activeBusiness,
                      businesses: owner.businesses,
                      actionInProgress: _ownerActionInProgress,
                      canManageOwnerActions: canManageOwnerActions,
                      onSwitchBusiness: (businessId) {
                        setState(() {
                          _activeBusinessId = businessId;
                        });
                      },
                      onEditBusiness: _ownerActionInProgress
                          ? null
                          : () => _handleEditBusiness(activeBusiness),
                      onCreateBusiness: _ownerActionInProgress
                          ? null
                          : _handleCreateBusiness,
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: IndexedStack(
                        index: _selectedIndex,
                        children: [
                          _OwnerMobileBusinessesPanel(
                            businesses: owner.businesses,
                            activeBusiness: activeBusiness,
                            canManageBusinesses: canManageOwnerActions,
                            actionInProgress: _ownerActionInProgress,
                            onEditBusiness: _ownerActionInProgress
                                ? null
                                : () => _handleEditBusiness(activeBusiness),
                            onEditBranding: _ownerActionInProgress
                                ? null
                                : () => _handleEditBranding(activeBusiness),
                          ),
                          _OwnerMobileDashboardPanel(
                            metrics: owner.dashboardMetrics,
                            trendPoints: owner.trendPoints,
                            businessPerformance: owner.businessPerformance,
                            activeBusiness: activeBusiness,
                            canManageLedger: canManageOwnerActions,
                            actionInProgress: _ownerActionInProgress,
                            onAdminAdjustCashback: _ownerActionInProgress
                                ? null
                                : () => _handleAdminAdjustment(activeBusiness),
                            onRefundCashback: _ownerActionInProgress
                                ? null
                                : () => _handleRefundCashback(activeBusiness),
                          ),
                          _OwnerMobileStaffPanel(
                            activeBusiness: activeBusiness,
                            staffMembers: owner.staffMembers,
                            joinRequests: owner.joinRequests,
                            groupAuditEvents: owner.groupAuditEvents,
                            canManageStaff: canManageOwnerActions,
                            actionInProgress: _ownerActionInProgress,
                            onCreateStaff: _ownerActionInProgress
                                ? null
                                : () => _handleCreateStaff(activeBusiness),
                            onEditStaff: _ownerActionInProgress
                                ? null
                                : _handleEditStaff,
                            onResetStaffPassword: _ownerActionInProgress
                                ? null
                                : _handleResetStaffPassword,
                            onVoteOnJoinRequest: _ownerActionInProgress
                                ? null
                                : (request) => _handleVoteOnJoinRequest(
                                    request,
                                    owner.businesses,
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
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
                  icon: Icon(Icons.storefront_outlined),
                  selectedIcon: Icon(Icons.storefront),
                  label: 'Businesses',
                ),
                NavigationDestination(
                  icon: Icon(Icons.insights_outlined),
                  selectedIcon: Icon(Icons.insights),
                  label: 'Dashboard',
                ),
                NavigationDestination(
                  icon: Icon(Icons.badge_outlined),
                  selectedIcon: Icon(Icons.badge),
                  label: 'Staffs',
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      key: const ValueKey('owner-workspace-root'),
      extendBody: true,
      appBar: AppBar(
        title: Text(
          'Owner workspace · ${owner.ownerName}',
          key: const ValueKey('owner-workspace-title'),
        ),
        actions: [
          if (owner.businesses.length > 1)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: PopupMenuButton<String>(
                tooltip: 'Switch active business',
                onSelected: (businessId) {
                  setState(() {
                    _activeBusinessId = businessId;
                  });
                },
                itemBuilder: (context) => owner.businesses
                    .map(
                      (business) => PopupMenuItem<String>(
                        value: business.id,
                        child: Text(business.name),
                      ),
                    )
                    .toList(),
                child: Chip(
                  label: Text(activeBusiness.name),
                  avatar: const Icon(Icons.storefront_outlined),
                ),
              ),
            ),
          NotificationBellButton(
            unreadCount: unreadNotificationsCount,
            onPressed: () => _openNotificationsCenter(notifications, owner),
          ),
          if (session?.role == AppRole.owner)
            IconButton(
              tooltip: session!.isPreview ? 'Exit preview' : 'Sign out',
              onPressed: () async {
                await ref.read(appSessionControllerProvider.notifier).signOut();
                if (!context.mounted) return;
                context.go('/');
              },
              icon: const Icon(Icons.logout),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: AppBackdrop(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1220),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 124),
              children: [
                InfoBanner(
                  title: 'Active business: ${activeBusiness.name}',
                  message:
                      '${activeBusiness.groupName} • ${formatPercent(activeBusiness.cashbackBasisPoints)} cashback • ${activeBusiness.redeemPolicy}',
                ),
                if (canManageOwnerActions) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      FilledButton.icon(
                        onPressed: _ownerActionInProgress
                            ? null
                            : () => _handleEditBusiness(activeBusiness),
                        icon: _ownerActionInProgress
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.edit_outlined),
                        label: const Text('Edit active business'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _ownerActionInProgress
                            ? null
                            : _handleCreateBusiness,
                        icon: const Icon(Icons.add_business_outlined),
                        label: const Text('Create business'),
                      ),
                      if (_canConfigureTandem(activeBusiness))
                        OutlinedButton.icon(
                          onPressed: _ownerActionInProgress
                              ? null
                              : () => _handleCreateTandemGroup(activeBusiness),
                          icon: const Icon(Icons.group_work_outlined),
                          label: const Text('Create tandem group'),
                        ),
                      if (_canConfigureTandem(activeBusiness))
                        OutlinedButton.icon(
                          onPressed: _ownerActionInProgress
                              ? null
                              : () => _handleRequestJoinGroup(activeBusiness),
                          icon: const Icon(Icons.group_add_outlined),
                          label: const Text('Request join group'),
                        ),
                    ],
                  ),
                ],
                if (!canManageOwnerActions) ...[
                  const SizedBox(height: 12),
                  const InfoBanner(
                    title: 'Preview-only staff management',
                    message:
                        'Create/reset/disable staff actions become live after signing in with a real owner account on a connected Firebase runtime.',
                    color: Color(0xFFFFF2D8),
                  ),
                ],
                const SizedBox(height: 16),
                IndexedStack(
                  index: _selectedIndex,
                  children: [
                    _BusinessesTab(
                      businesses: owner.businesses,
                      activeBusiness: activeBusiness,
                      activeBusinessId: _activeBusinessId,
                      canManageBusinesses: canManageOwnerActions,
                      actionInProgress: _ownerActionInProgress,
                      onEditBusiness: _ownerActionInProgress
                          ? null
                          : _handleEditBusiness,
                      onCreateLocation: _ownerActionInProgress
                          ? null
                          : () => _handleUpsertLocation(activeBusiness),
                      onEditLocation: _ownerActionInProgress
                          ? null
                          : (location) => _handleUpsertLocation(
                              activeBusiness,
                              initial: location,
                            ),
                      onDeleteLocation: _ownerActionInProgress
                          ? null
                          : (location) =>
                                _handleDeleteLocation(activeBusiness, location),
                      onCreateProduct: _ownerActionInProgress
                          ? null
                          : () => _handleUpsertCatalogItem(
                              activeBusiness,
                              _CatalogCollectionType.product,
                            ),
                      onEditProduct: _ownerActionInProgress
                          ? null
                          : (item) => _handleUpsertCatalogItem(
                              activeBusiness,
                              _CatalogCollectionType.product,
                              initial: item,
                            ),
                      onDeleteProduct: _ownerActionInProgress
                          ? null
                          : (item) => _handleDeleteCatalogItem(
                              activeBusiness,
                              _CatalogCollectionType.product,
                              item,
                            ),
                      onCreateService: _ownerActionInProgress
                          ? null
                          : () => _handleUpsertCatalogItem(
                              activeBusiness,
                              _CatalogCollectionType.service,
                            ),
                      onEditService: _ownerActionInProgress
                          ? null
                          : (item) => _handleUpsertCatalogItem(
                              activeBusiness,
                              _CatalogCollectionType.service,
                              initial: item,
                            ),
                      onDeleteService: _ownerActionInProgress
                          ? null
                          : (item) => _handleDeleteCatalogItem(
                              activeBusiness,
                              _CatalogCollectionType.service,
                              item,
                            ),
                      onEditBranding: _ownerActionInProgress
                          ? null
                          : () => _handleEditBranding(activeBusiness),
                      onCreateMedia: _ownerActionInProgress
                          ? null
                          : () => _handleUpsertMedia(activeBusiness),
                      onEditMedia: _ownerActionInProgress
                          ? null
                          : (media) => _handleUpsertMedia(
                              activeBusiness,
                              initial: media,
                            ),
                      onDeleteMedia: _ownerActionInProgress
                          ? null
                          : (media) =>
                                _handleDeleteMedia(activeBusiness, media),
                    ),
                    _DashboardTab(
                      metrics: owner.dashboardMetrics,
                      trendPoints: owner.trendPoints,
                      businessPerformance: owner.businessPerformance,
                      activeBusiness: activeBusiness,
                      canManageLedger: canManageOwnerActions,
                      actionInProgress: _ownerActionInProgress,
                      onAdminAdjustCashback: _ownerActionInProgress
                          ? null
                          : () => _handleAdminAdjustment(activeBusiness),
                      onRefundCashback: _ownerActionInProgress
                          ? null
                          : () => _handleRefundCashback(activeBusiness),
                      onExpireWalletLots: _ownerActionInProgress
                          ? null
                          : () => _handleExpireWalletLots(activeBusiness),
                    ),
                    _StaffTab(
                      activeBusiness: activeBusiness,
                      ownerBusinesses: owner.businesses,
                      staffMembers: owner.staffMembers,
                      joinRequests: owner.joinRequests,
                      groupAuditEvents: owner.groupAuditEvents,
                      canManageStaff: canManageOwnerActions,
                      actionInProgress: _ownerActionInProgress,
                      onCreateStaff: _ownerActionInProgress
                          ? null
                          : () => _handleCreateStaff(activeBusiness),
                      onEditStaff: _ownerActionInProgress
                          ? null
                          : _handleEditStaff,
                      onResetStaffPassword: _ownerActionInProgress
                          ? null
                          : _handleResetStaffPassword,
                      onDisableStaff: _ownerActionInProgress
                          ? null
                          : _handleDisableStaff,
                      onVoteOnJoinRequest: _ownerActionInProgress
                          ? null
                          : _handleVoteOnJoinRequest,
                    ),
                  ],
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
                icon: Icon(Icons.storefront_outlined),
                selectedIcon: Icon(Icons.storefront),
                label: 'Businesses',
              ),
              NavigationDestination(
                icon: Icon(Icons.insights_outlined),
                selectedIcon: Icon(Icons.insights),
                label: 'Dashboard',
              ),
              NavigationDestination(
                icon: Icon(Icons.badge_outlined),
                selectedIcon: Icon(Icons.badge),
                label: 'Staffs',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openNotificationsCenter(
    List<AppNotificationItem> notifications,
    OwnerWorkspace owner,
  ) async {
    await showNotificationCenterBottomSheet(
      context: context,
      title: 'Owner notifications',
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
        _openOwnerNotification(notification, owner);
      },
    );
  }

  void _openOwnerNotification(
    AppNotificationItem notification,
    OwnerWorkspace owner,
  ) {
    final route = notification.actionRoute?.trim();
    if (route != null && route.isNotEmpty && route != '/owner') {
      context.go(route);
      return;
    }

    final targetBusinessId = _resolveOwnerNotificationBusinessId(
      notification,
      owner,
    );

    setState(() {
      if (targetBusinessId != null && targetBusinessId.isNotEmpty) {
        _activeBusinessId = targetBusinessId;
      }
      _selectedIndex = _ownerTabForNotification(notification);
    });
  }

  int _ownerTabForNotification(AppNotificationItem notification) {
    switch (notification.type) {
      case 'group_join_requested':
      case 'group_join_vote_yes':
      case 'group_join_approved':
      case 'group_join_rejected':
      case 'staff_assignment':
        return 2;
      case 'cashback_issued':
      case 'cashback_redeemed':
      case 'cashback_refunded':
      case 'cashback_expired':
      case 'admin_adjustment':
        return 1;
      default:
        return 0;
    }
  }

  String? _resolveOwnerNotificationBusinessId(
    AppNotificationItem notification,
    OwnerWorkspace owner,
  ) {
    final ownedBusinessIds = owner.businesses
        .map((business) => business.id)
        .toSet();
    final notificationBusinessId = notification.businessId?.trim();
    if (notificationBusinessId != null &&
        notificationBusinessId.isNotEmpty &&
        ownedBusinessIds.contains(notificationBusinessId)) {
      return notificationBusinessId;
    }

    final notificationGroupId = notification.groupId?.trim();
    if (notificationGroupId != null && notificationGroupId.isNotEmpty) {
      for (final business in owner.businesses) {
        if (business.groupId == notificationGroupId) {
          return business.id;
        }
      }
    }

    return _activeBusinessId;
  }

  Future<void> _handleEditBusiness(BusinessSummary business) async {
    final payload = await showDialog<_EditBusinessPayload>(
      context: context,
      builder: (context) => _EditBusinessDialog(business: business),
    );

    if (payload == null) {
      return;
    }

    setState(() {
      _ownerActionInProgress = true;
    });

    try {
      await ref
          .read(ownerBusinessAdminServiceProvider)
          .updateBusinessProfile(
            businessId: business.id,
            name: payload.name,
            category: payload.category,
            description: payload.description,
            address: payload.address,
            workingHours: payload.workingHours,
            phoneNumbers: payload.phoneNumbers,
            cashbackBasisPoints: payload.cashbackBasisPoints,
            redeemPolicy: payload.redeemPolicy,
          );

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${payload.name} business profile was updated.'),
        ),
      );
      ref.invalidate(ownerWorkspaceProvider);
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) {
        setState(() {
          _ownerActionInProgress = false;
        });
      }
    }
  }

  Future<void> _handleCreateBusiness() async {
    final payload = await showDialog<_CreateBusinessPayload>(
      context: context,
      builder: (context) => const _CreateBusinessDialog(),
    );

    if (payload == null) {
      return;
    }

    setState(() {
      _ownerActionInProgress = true;
    });

    try {
      final result = await ref
          .read(teamCashFunctionsServiceProvider)
          .createBusiness(
            name: payload.name,
            category: payload.category,
            description: payload.description,
            address: payload.address,
            workingHours: payload.workingHours,
            phoneNumbers: payload.phoneNumbers,
            cashbackBasisPoints: payload.cashbackBasisPoints,
            redeemPolicy: payload.redeemPolicy,
          );

      await ref
          .read(appSessionControllerProvider.notifier)
          .refreshCurrentSession();
      ref.invalidate(ownerWorkspaceProvider);

      if (!mounted) {
        return;
      }

      setState(() {
        _activeBusinessId = result.businessId;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${result.name} was created. You can now attach it to a tandem group.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) {
        setState(() {
          _ownerActionInProgress = false;
        });
      }
    }
  }

  Future<void> _handleCreateTandemGroup(BusinessSummary business) async {
    final groupName = await showDialog<String>(
      context: context,
      builder: (context) =>
          _CreateTandemGroupDialog(businessName: business.name),
    );

    if (groupName == null) {
      return;
    }

    setState(() {
      _ownerActionInProgress = true;
    });

    try {
      final result = await ref
          .read(teamCashFunctionsServiceProvider)
          .createGroup(businessId: business.id, name: groupName);

      ref.invalidate(ownerWorkspaceProvider);

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${business.name} now anchors tandem group ${result.groupName}.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) {
        setState(() {
          _ownerActionInProgress = false;
        });
      }
    }
  }

  Future<void> _handleRequestJoinGroup(BusinessSummary business) async {
    try {
      final groups = await ref
          .read(ownerBusinessAdminServiceProvider)
          .loadVisibleGroups();
      final availableGroups = groups
          .where((group) => group.id != business.groupId)
          .toList();

      if (availableGroups.isEmpty) {
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No visible tandem groups are available to join yet.',
            ),
          ),
        );
        return;
      }

      if (!mounted) {
        return;
      }

      final payload = await showDialog<_RequestJoinGroupPayload>(
        context: context,
        builder: (context) => _RequestJoinGroupDialog(
          business: business,
          groups: availableGroups,
        ),
      );

      if (payload == null) {
        return;
      }

      setState(() {
        _ownerActionInProgress = true;
      });

      final result = await ref
          .read(teamCashFunctionsServiceProvider)
          .requestGroupJoin(groupId: payload.groupId, businessId: business.id);

      ref.invalidate(ownerWorkspaceProvider);

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Join request sent to ${payload.groupName}. ${result.approvalsReceived}/${result.approvalsRequired} approvals complete.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) {
        setState(() {
          _ownerActionInProgress = false;
        });
      }
    }
  }

  Future<void> _handleAdminAdjustment(BusinessSummary business) async {
    if (business.groupId.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Manual ledger adjustments need an active tandem group on the business.',
          ),
        ),
      );
      return;
    }

    final payload = await showDialog<_AdminAdjustmentPayload>(
      context: context,
      builder: (context) => _AdminAdjustmentDialog(business: business),
    );

    if (payload == null) {
      return;
    }

    setState(() {
      _ownerActionInProgress = true;
    });

    try {
      final signedAmount = payload.direction == _AdjustmentDirection.debit
          ? -payload.amountMinorUnits
          : payload.amountMinorUnits;
      final result = await ref
          .read(teamCashFunctionsServiceProvider)
          .adminAdjustCashback(
            businessId: business.id,
            groupId: business.groupId,
            customerPhoneE164: payload.customerPhoneE164,
            amountMinorUnits: signedAmount,
            note: payload.note,
            requestId:
                'owner-admin-${DateTime.now().microsecondsSinceEpoch}-${business.id}',
          );

      ref.invalidate(ownerWorkspaceProvider);

      if (!mounted) {
        return;
      }

      final directionLabel = result.direction == 'debit' ? 'debit' : 'credit';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Manual $directionLabel adjustment applied for ${payload.customerPhoneE164}: ${formatCurrency(result.adjustedMinorUnits)}.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) {
        setState(() {
          _ownerActionInProgress = false;
        });
      }
    }
  }

  Future<void> _handleRefundCashback(BusinessSummary business) async {
    final payload = await showDialog<_RefundCashbackPayload>(
      context: context,
      builder: (context) => _RefundCashbackDialog(business: business),
    );

    if (payload == null) {
      return;
    }

    setState(() {
      _ownerActionInProgress = true;
    });

    try {
      final result = await ref
          .read(teamCashFunctionsServiceProvider)
          .refundCashback(
            businessId: business.id,
            redemptionBatchId: payload.redemptionBatchId,
            note: payload.note,
          );

      ref.invalidate(ownerWorkspaceProvider);

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Refund created for batch ${result.redemptionBatchId}. Restored ${formatCurrency(result.refundedMinorUnits)}.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) {
        setState(() {
          _ownerActionInProgress = false;
        });
      }
    }
  }

  Future<void> _handleExpireWalletLots(BusinessSummary business) async {
    if (business.groupId.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Expiry sweeps need an active tandem group on the business.',
          ),
        ),
      );
      return;
    }

    final payload = await showDialog<_ExpireWalletLotsPayload>(
      context: context,
      builder: (context) => _ExpireWalletLotsDialog(business: business),
    );

    if (payload == null) {
      return;
    }

    setState(() {
      _ownerActionInProgress = true;
    });

    try {
      final result = await ref
          .read(teamCashFunctionsServiceProvider)
          .expireWalletLots(
            businessId: business.id,
            groupId: business.groupId,
            maxLots: payload.maxLots,
          );

      ref.invalidate(ownerWorkspaceProvider);

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Expiry sweep finished. ${result.expiredLotCount} lots expired for ${formatCurrency(result.expiredMinorUnits)}.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) {
        setState(() {
          _ownerActionInProgress = false;
        });
      }
    }
  }

  Future<void> _handleUpsertLocation(
    BusinessSummary business, {
    BusinessLocationSummary? initial,
  }) async {
    final payload = await showDialog<_LocationPayload>(
      context: context,
      builder: (context) => _BusinessLocationDialog(
        businessName: business.name,
        initial: initial,
      ),
    );

    if (payload == null) {
      return;
    }

    setState(() {
      _ownerActionInProgress = true;
    });

    try {
      await ref
          .read(ownerBusinessAdminServiceProvider)
          .upsertLocation(
            businessId: business.id,
            locationId: initial?.id,
            name: payload.name,
            address: payload.address,
            workingHours: payload.workingHours,
            phoneNumbers: payload.phoneNumbers,
            notes: payload.notes,
            isPrimary: payload.isPrimary,
          );

      _scheduleOwnerPortfolioRefresh();

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            initial == null
                ? '${payload.name} location was added.'
                : '${payload.name} location was updated.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) {
        setState(() {
          _ownerActionInProgress = false;
        });
      }
    }
  }

  Future<void> _handleDeleteLocation(
    BusinessSummary business,
    BusinessLocationSummary location,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${location.name}?'),
        content: const Text(
          'This removes the location from the business directory and owner catalog.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('owner-media-confirm-delete'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      return;
    }

    setState(() {
      _ownerActionInProgress = true;
    });

    try {
      await ref
          .read(ownerBusinessAdminServiceProvider)
          .deleteLocation(businessId: business.id, locationId: location.id);

      _scheduleOwnerPortfolioRefresh();

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('${location.name} was deleted.')));
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) {
        setState(() {
          _ownerActionInProgress = false;
        });
      }
    }
  }

  Future<void> _handleUpsertCatalogItem(
    BusinessSummary business,
    _CatalogCollectionType type, {
    BusinessCatalogItemSummary? initial,
  }) async {
    final typeLabel = _catalogTypeLabel(type);
    final payload = await showDialog<_CatalogItemPayload>(
      context: context,
      builder: (context) => _CatalogItemDialog(
        title: initial == null ? 'Add $typeLabel' : 'Edit $typeLabel',
        itemTypeLabel: typeLabel,
        initial: initial,
      ),
    );

    if (payload == null) {
      return;
    }

    setState(() {
      _ownerActionInProgress = true;
    });

    try {
      final service = ref.read(ownerBusinessAdminServiceProvider);
      if (type == _CatalogCollectionType.product) {
        await service.upsertProduct(
          businessId: business.id,
          productId: initial?.id,
          name: payload.name,
          description: payload.description,
          priceLabel: payload.priceLabel,
          isActive: payload.isActive,
        );
      } else {
        await service.upsertService(
          businessId: business.id,
          serviceId: initial?.id,
          name: payload.name,
          description: payload.description,
          priceLabel: payload.priceLabel,
          isActive: payload.isActive,
        );
      }

      _scheduleOwnerPortfolioRefresh();

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            initial == null
                ? '${payload.name} $typeLabel was added.'
                : '${payload.name} $typeLabel was updated.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) {
        setState(() {
          _ownerActionInProgress = false;
        });
      }
    }
  }

  Future<void> _handleDeleteCatalogItem(
    BusinessSummary business,
    _CatalogCollectionType type,
    BusinessCatalogItemSummary item,
  ) async {
    final typeLabel = _catalogTypeLabel(type);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${item.name}?'),
        content: Text(
          'This removes the $typeLabel from ${business.name}. Historical cashback data stays untouched.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      return;
    }

    setState(() {
      _ownerActionInProgress = true;
    });

    try {
      final service = ref.read(ownerBusinessAdminServiceProvider);
      if (type == _CatalogCollectionType.product) {
        await service.deleteProduct(
          businessId: business.id,
          productId: item.id,
        );
      } else {
        await service.deleteService(
          businessId: business.id,
          serviceId: item.id,
        );
      }

      _scheduleOwnerPortfolioRefresh();

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${item.name} $typeLabel was deleted.')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) {
        setState(() {
          _ownerActionInProgress = false;
        });
      }
    }
  }

  void _scheduleOwnerPortfolioRefresh() {
    ref.invalidate(ownerWorkspaceProvider);
    Future<void>.delayed(const Duration(milliseconds: 900), () {
      if (!mounted) {
        return;
      }
      ref.invalidate(ownerWorkspaceProvider);
    });
  }

  Future<void> _handleEditBranding(BusinessSummary business) async {
    final payload = await showDialog<_BrandingPayload>(
      context: context,
      builder: (context) => _BrandingDialog(business: business),
    );

    if (payload == null) {
      return;
    }

    setState(() {
      _ownerActionInProgress = true;
    });

    try {
      await ref
          .read(ownerBusinessAdminServiceProvider)
          .updateBusinessBranding(
            businessId: business.id,
            logoUrl: payload.logoUrl,
            coverImageUrl: payload.coverImageUrl,
            currentLogoStoragePath: business.logoStoragePath,
            currentCoverImageStoragePath: business.coverImageStoragePath,
            logoFile: payload.logoFile,
            coverFile: payload.coverFile,
          );

      _scheduleOwnerPortfolioRefresh();

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${business.name} branding was updated.')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) {
        setState(() {
          _ownerActionInProgress = false;
        });
      }
    }
  }

  Future<void> _handleUpsertMedia(
    BusinessSummary business, {
    BusinessMediaSummary? initial,
  }) async {
    final payload = await showDialog<_MediaPayload>(
      context: context,
      builder: (context) =>
          _MediaDialog(businessName: business.name, initial: initial),
    );

    if (payload == null) {
      return;
    }

    setState(() {
      _ownerActionInProgress = true;
    });

    try {
      await ref
          .read(ownerBusinessAdminServiceProvider)
          .upsertMedia(
            businessId: business.id,
            mediaId: initial?.id,
            title: payload.title,
            caption: payload.caption,
            mediaType: payload.mediaType,
            imageUrl: payload.imageUrl,
            isFeatured: payload.isFeatured,
            currentStoragePath: initial?.storagePath ?? '',
            imageFile: payload.imageFile,
          );

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            initial == null
                ? '${payload.title} media item was added.'
                : '${payload.title} media item was updated.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) {
        setState(() {
          _ownerActionInProgress = false;
        });
      }
    }
  }

  Future<void> _handleDeleteMedia(
    BusinessSummary business,
    BusinessMediaSummary media,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${media.title}?'),
        content: Text(
          'This removes the media entry from ${business.name}. Existing wallet and ledger history are unaffected.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      return;
    }

    setState(() {
      _ownerActionInProgress = true;
    });

    try {
      await ref
          .read(ownerBusinessAdminServiceProvider)
          .deleteMedia(
            businessId: business.id,
            mediaId: media.id,
            storagePath: media.storagePath,
          );

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${media.title} media item was deleted.')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) {
        setState(() {
          _ownerActionInProgress = false;
        });
      }
    }
  }

  Future<void> _handleCreateStaff(BusinessSummary activeBusiness) async {
    final payload = await showDialog<_CreateStaffPayload>(
      context: context,
      builder: (context) =>
          _CreateStaffDialog(businessName: activeBusiness.name),
    );

    if (payload == null) {
      return;
    }

    setState(() {
      _ownerActionInProgress = true;
    });

    try {
      final result = await ref
          .read(teamCashFunctionsServiceProvider)
          .createStaffAccount(
            businessId: activeBusiness.id,
            username: payload.username,
            displayName: payload.displayName,
            password: payload.password,
          );

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Staff created for ${result.businessName}. Login alias: ${result.loginAliasEmail}',
          ),
        ),
      );
      ref.invalidate(ownerWorkspaceProvider);
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) {
        setState(() {
          _ownerActionInProgress = false;
        });
      }
    }
  }

  Future<void> _handleEditStaff(StaffMemberSummary staff) async {
    final payload = await showDialog<_EditStaffPayload>(
      context: context,
      builder: (context) => _EditStaffDialog(staff: staff),
    );

    if (payload == null) {
      return;
    }

    setState(() {
      _ownerActionInProgress = true;
    });

    try {
      final result = await ref
          .read(teamCashFunctionsServiceProvider)
          .updateStaffProfile(
            staffUid: staff.id,
            displayName: payload.displayName,
          );

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Staff profile updated for ${result.displayName} (@${result.username}).',
          ),
        ),
      );
      ref.invalidate(ownerWorkspaceProvider);
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) {
        setState(() {
          _ownerActionInProgress = false;
        });
      }
    }
  }

  Future<void> _handleDisableStaff(StaffMemberSummary staff) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Disable ${staff.name}?'),
        content: const Text(
          'This keeps all historical records intact and prevents further staff sign-ins.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Disable'),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      return;
    }

    setState(() {
      _ownerActionInProgress = true;
    });

    try {
      await ref
          .read(teamCashFunctionsServiceProvider)
          .disableStaffAccount(staffUid: staff.id);

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('${staff.name} was disabled.')));
      ref.invalidate(ownerWorkspaceProvider);
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) {
        setState(() {
          _ownerActionInProgress = false;
        });
      }
    }
  }

  Future<void> _handleResetStaffPassword(StaffMemberSummary staff) async {
    final payload = await showDialog<_ResetStaffPasswordPayload>(
      context: context,
      builder: (context) => _ResetStaffPasswordDialog(staff: staff),
    );

    if (payload == null) {
      return;
    }

    setState(() {
      _ownerActionInProgress = true;
    });

    try {
      final result = await ref
          .read(teamCashFunctionsServiceProvider)
          .resetStaffPassword(staffUid: staff.id, password: payload.password);

      if (!mounted) {
        return;
      }

      final displayName = result.displayName.isNotEmpty
          ? result.displayName
          : staff.name;
      final username = result.username.isNotEmpty
          ? result.username
          : staff.username;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Password updated for $displayName (@$username). Share the temporary password securely.',
          ),
        ),
      );
      ref.invalidate(ownerWorkspaceProvider);
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) {
        setState(() {
          _ownerActionInProgress = false;
        });
      }
    }
  }

  Future<void> _handleVoteOnJoinRequest(
    GroupJoinRequestSummary request,
    List<BusinessSummary> ownerBusinesses,
  ) async {
    final eligibleBusinesses = ownerBusinesses
        .where(
          (business) =>
              business.groupStatus == GroupMembershipStatus.active &&
              business.groupId == request.groupId,
        )
        .toList();

    if (eligibleBusinesses.isEmpty) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No eligible active business is available to vote on this request.',
          ),
        ),
      );
      return;
    }

    final payload = await showDialog<_VoteOnJoinRequestPayload>(
      context: context,
      builder: (context) => _VoteOnJoinRequestDialog(
        request: request,
        eligibleBusinesses: eligibleBusinesses,
      ),
    );

    if (payload == null) {
      return;
    }

    setState(() {
      _ownerActionInProgress = true;
    });

    try {
      final result = await ref
          .read(teamCashFunctionsServiceProvider)
          .voteOnGroupJoin(
            requestId: request.id,
            vote: payload.vote,
            voterBusinessId: payload.voterBusinessId,
          );

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.status == 'approved'
                ? 'Join request approved. ${result.approvalsReceived}/${result.approvalsRequired} approvals recorded.'
                : result.status == 'rejected'
                ? 'Join request rejected by ${payload.voterBusinessName}.'
                : 'Vote recorded from ${payload.voterBusinessName}. ${result.approvalsReceived}/${result.approvalsRequired} approvals complete.',
          ),
        ),
      );
      ref.invalidate(ownerWorkspaceProvider);
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) {
        setState(() {
          _ownerActionInProgress = false;
        });
      }
    }
  }

  bool _canConfigureTandem(BusinessSummary business) {
    return business.groupStatus == GroupMembershipStatus.notGrouped ||
        business.groupStatus == GroupMembershipStatus.rejected;
  }

  String _catalogTypeLabel(_CatalogCollectionType type) {
    switch (type) {
      case _CatalogCollectionType.product:
        return 'product';
      case _CatalogCollectionType.service:
        return 'service';
    }
  }
}

int _normalizeTabIndex(int? value, {required int fallback}) {
  if (value == null) {
    return fallback;
  }
  if (value < 0) {
    return 0;
  }
  if (value > 2) {
    return 2;
  }
  return value;
}
