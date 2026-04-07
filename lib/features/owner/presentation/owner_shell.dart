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

enum _CatalogCollectionType { product, service }

enum _StaffAccountAction { edit, resetPassword, disable }

enum _AdjustmentDirection { credit, debit }

class OwnerShell extends ConsumerStatefulWidget {
  const OwnerShell({super.key});

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

    return Scaffold(
      key: const ValueKey('owner-workspace-root'),
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
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
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
                            child: CircularProgressIndicator(strokeWidth: 2),
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
                      : (media) =>
                            _handleUpsertMedia(activeBusiness, initial: media),
                  onDeleteMedia: _ownerActionInProgress
                      ? null
                      : (media) => _handleDeleteMedia(activeBusiness, media),
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
                  onEditStaff: _ownerActionInProgress ? null : _handleEditStaff,
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
      bottomNavigationBar: NavigationBar(
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

class _BusinessesTab extends ConsumerWidget {
  const _BusinessesTab({
    required this.businesses,
    required this.activeBusiness,
    required this.activeBusinessId,
    required this.canManageBusinesses,
    required this.actionInProgress,
    required this.onEditBusiness,
    required this.onCreateLocation,
    required this.onEditLocation,
    required this.onDeleteLocation,
    required this.onCreateProduct,
    required this.onEditProduct,
    required this.onDeleteProduct,
    required this.onCreateService,
    required this.onEditService,
    required this.onDeleteService,
    required this.onEditBranding,
    required this.onCreateMedia,
    required this.onEditMedia,
    required this.onDeleteMedia,
  });

  final List<BusinessSummary> businesses;
  final BusinessSummary activeBusiness;
  final String activeBusinessId;
  final bool canManageBusinesses;
  final bool actionInProgress;
  final Future<void> Function(BusinessSummary business)? onEditBusiness;
  final Future<void> Function()? onCreateLocation;
  final Future<void> Function(BusinessLocationSummary location)? onEditLocation;
  final Future<void> Function(BusinessLocationSummary location)?
  onDeleteLocation;
  final Future<void> Function()? onCreateProduct;
  final Future<void> Function(BusinessCatalogItemSummary item)? onEditProduct;
  final Future<void> Function(BusinessCatalogItemSummary item)? onDeleteProduct;
  final Future<void> Function()? onCreateService;
  final Future<void> Function(BusinessCatalogItemSummary item)? onEditService;
  final Future<void> Function(BusinessCatalogItemSummary item)? onDeleteService;
  final Future<void> Function()? onEditBranding;
  final Future<void> Function()? onCreateMedia;
  final Future<void> Function(BusinessMediaSummary media)? onEditMedia;
  final Future<void> Function(BusinessMediaSummary media)? onDeleteMedia;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locationsAsync = ref.watch(
      businessLocationsProvider(activeBusiness.id),
    );
    final productsAsync = ref.watch(
      businessProductsProvider(activeBusiness.id),
    );
    final servicesAsync = ref.watch(
      businessServicesProvider(activeBusiness.id),
    );
    final mediaAsync = ref.watch(businessMediaProvider(activeBusiness.id));

    return SectionCard(
      title: 'Business portfolio',
      subtitle:
          'Owners can run multiple businesses independently while keeping tandem membership at the business level.',
      child: Column(
        children: [
          ...businesses.map(
            (business) => Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: _BusinessTile(
                business: business,
                isActive: business.id == activeBusinessId,
                canManageBusinesses: canManageBusinesses,
                actionInProgress: actionInProgress,
                onEditBusiness: onEditBusiness,
              ),
            ),
          ),
          const SizedBox(height: 8),
          _BusinessCatalogSection(
            activeBusiness: activeBusiness,
            locationsAsync: locationsAsync,
            productsAsync: productsAsync,
            servicesAsync: servicesAsync,
            canManageBusinesses: canManageBusinesses,
            actionInProgress: actionInProgress,
            onCreateLocation: onCreateLocation,
            onEditLocation: onEditLocation,
            onDeleteLocation: onDeleteLocation,
            onCreateProduct: onCreateProduct,
            onEditProduct: onEditProduct,
            onDeleteProduct: onDeleteProduct,
            onCreateService: onCreateService,
            onEditService: onEditService,
            onDeleteService: onDeleteService,
          ),
          const SizedBox(height: 16),
          _BusinessBrandingSection(
            activeBusiness: activeBusiness,
            mediaAsync: mediaAsync,
            canManageBusinesses: canManageBusinesses,
            actionInProgress: actionInProgress,
            onEditBranding: onEditBranding,
            onCreateMedia: onCreateMedia,
            onEditMedia: onEditMedia,
            onDeleteMedia: onDeleteMedia,
          ),
        ],
      ),
    );
  }
}

class _BusinessCatalogSection extends StatelessWidget {
  const _BusinessCatalogSection({
    required this.activeBusiness,
    required this.locationsAsync,
    required this.productsAsync,
    required this.servicesAsync,
    required this.canManageBusinesses,
    required this.actionInProgress,
    required this.onCreateLocation,
    required this.onEditLocation,
    required this.onDeleteLocation,
    required this.onCreateProduct,
    required this.onEditProduct,
    required this.onDeleteProduct,
    required this.onCreateService,
    required this.onEditService,
    required this.onDeleteService,
  });

  final BusinessSummary activeBusiness;
  final AsyncValue<List<BusinessLocationSummary>> locationsAsync;
  final AsyncValue<List<BusinessCatalogItemSummary>> productsAsync;
  final AsyncValue<List<BusinessCatalogItemSummary>> servicesAsync;
  final bool canManageBusinesses;
  final bool actionInProgress;
  final Future<void> Function()? onCreateLocation;
  final Future<void> Function(BusinessLocationSummary location)? onEditLocation;
  final Future<void> Function(BusinessLocationSummary location)?
  onDeleteLocation;
  final Future<void> Function()? onCreateProduct;
  final Future<void> Function(BusinessCatalogItemSummary item)? onEditProduct;
  final Future<void> Function(BusinessCatalogItemSummary item)? onDeleteProduct;
  final Future<void> Function()? onCreateService;
  final Future<void> Function(BusinessCatalogItemSummary item)? onEditService;
  final Future<void> Function(BusinessCatalogItemSummary item)? onDeleteService;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      key: const ValueKey('owner-live-catalog-section'),
      title: 'Live catalog for ${activeBusiness.name}',
      subtitle:
          'Locations, products, and services are stored directly in Firestore so the owner surface reflects the real business profile.',
      child: Column(
        children: [
          _CatalogBlock<BusinessLocationSummary>(
            title: 'Locations',
            subtitle:
                'Physical branches, counters, or pickup points shown inside the private tandem directory.',
            emptyMessage:
                'No locations yet. Add the first branch for this business.',
            addLabel: 'Add location',
            itemsAsync: locationsAsync,
            canManageBusinesses: canManageBusinesses,
            actionInProgress: actionInProgress,
            onAdd: onCreateLocation,
            itemBuilder: (location) => _LocationRow(
              location: location,
              canManageBusinesses: canManageBusinesses,
              actionInProgress: actionInProgress,
              onEdit: onEditLocation,
              onDelete: onDeleteLocation,
            ),
          ),
          const SizedBox(height: 16),
          _CatalogBlock<BusinessCatalogItemSummary>(
            title: 'Products',
            subtitle:
                'Menu items and sellable goods that help clients browse the business before checkout.',
            emptyMessage: 'No products yet. Add items customers can browse.',
            addLabel: 'Add product',
            itemsAsync: productsAsync,
            canManageBusinesses: canManageBusinesses,
            actionInProgress: actionInProgress,
            onAdd: onCreateProduct,
            itemBuilder: (item) => _CatalogItemRow(
              item: item,
              itemTypeLabel: 'Product',
              canManageBusinesses: canManageBusinesses,
              actionInProgress: actionInProgress,
              onEdit: onEditProduct,
              onDelete: onDeleteProduct,
            ),
          ),
          const SizedBox(height: 16),
          _CatalogBlock<BusinessCatalogItemSummary>(
            title: 'Services',
            subtitle:
                'Service catalogue entries that appear alongside products in the business profile.',
            emptyMessage:
                'No services yet. Add the services this business provides.',
            addLabel: 'Add service',
            itemsAsync: servicesAsync,
            canManageBusinesses: canManageBusinesses,
            actionInProgress: actionInProgress,
            onAdd: onCreateService,
            itemBuilder: (item) => _CatalogItemRow(
              item: item,
              itemTypeLabel: 'Service',
              canManageBusinesses: canManageBusinesses,
              actionInProgress: actionInProgress,
              onEdit: onEditService,
              onDelete: onDeleteService,
            ),
          ),
        ],
      ),
    );
  }
}

class _BusinessBrandingSection extends StatelessWidget {
  const _BusinessBrandingSection({
    required this.activeBusiness,
    required this.mediaAsync,
    required this.canManageBusinesses,
    required this.actionInProgress,
    required this.onEditBranding,
    required this.onCreateMedia,
    required this.onEditMedia,
    required this.onDeleteMedia,
  });

  final BusinessSummary activeBusiness;
  final AsyncValue<List<BusinessMediaSummary>> mediaAsync;
  final bool canManageBusinesses;
  final bool actionInProgress;
  final Future<void> Function()? onEditBranding;
  final Future<void> Function()? onCreateMedia;
  final Future<void> Function(BusinessMediaSummary media)? onEditMedia;
  final Future<void> Function(BusinessMediaSummary media)? onDeleteMedia;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      key: const ValueKey('owner-branding-section'),
      title: 'Branding and media',
      subtitle:
          'Logo, cover, and gallery content live in Firebase-backed business documents so the directory can show rich business profiles.',
      trailing: canManageBusinesses
          ? FilledButton.icon(
              key: const ValueKey('owner-edit-branding-button'),
              onPressed: actionInProgress || onEditBranding == null
                  ? null
                  : onEditBranding,
              icon: const Icon(Icons.photo_camera_back_outlined),
              label: const Text('Edit branding'),
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _BrandingPreview(activeBusiness: activeBusiness),
          const SizedBox(height: 16),
          _CatalogBlock<BusinessMediaSummary>(
            title: 'Gallery',
            subtitle:
                'Curated content, portfolio, and storefront imagery for the business profile.',
            emptyMessage:
                'No media items yet. Add gallery cards for clients to browse.',
            addLabel: 'Add media',
            itemsAsync: mediaAsync,
            canManageBusinesses: canManageBusinesses,
            actionInProgress: actionInProgress,
            addButtonKey: const ValueKey('owner-media-add-button'),
            onAdd: onCreateMedia,
            itemBuilder: (media) => _MediaRow(
              media: media,
              canManageBusinesses: canManageBusinesses,
              actionInProgress: actionInProgress,
              onEdit: onEditMedia,
              onDelete: onDeleteMedia,
            ),
          ),
        ],
      ),
    );
  }
}

class _CatalogBlock<T> extends StatelessWidget {
  const _CatalogBlock({
    required this.title,
    required this.subtitle,
    required this.emptyMessage,
    required this.addLabel,
    required this.itemsAsync,
    required this.canManageBusinesses,
    required this.actionInProgress,
    this.addButtonKey,
    required this.onAdd,
    required this.itemBuilder,
  });

  final String title;
  final String subtitle;
  final String emptyMessage;
  final String addLabel;
  final AsyncValue<List<T>> itemsAsync;
  final bool canManageBusinesses;
  final bool actionInProgress;
  final Key? addButtonKey;
  final Future<void> Function()? onAdd;
  final Widget Function(T item) itemBuilder;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FBF9),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFDDE8E1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFF52606D),
                      ),
                    ),
                  ],
                ),
              ),
              if (canManageBusinesses)
                FilledButton.tonalIcon(
                  key: addButtonKey,
                  onPressed: actionInProgress || onAdd == null ? null : onAdd,
                  icon: const Icon(Icons.add),
                  label: Text(addLabel),
                ),
            ],
          ),
          const SizedBox(height: 14),
          itemsAsync.when(
            data: (items) {
              if (items.isEmpty) {
                return Text(
                  emptyMessage,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF6B7280),
                  ),
                );
              }

              return Column(
                children: [
                  for (final item in items) ...[
                    itemBuilder(item),
                    if (item != items.last) const SizedBox(height: 12),
                  ],
                ],
              );
            },
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (error, _) => Text(
              error.toString(),
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: const Color(0xFFB23A48)),
            ),
          ),
        ],
      ),
    );
  }
}

class _BrandingPreview extends StatelessWidget {
  const _BrandingPreview({required this.activeBusiness});

  final BusinessSummary activeBusiness;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('owner-branding-preview'),
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FBF9),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFDDE8E1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Directory presentation',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ImagePreviewCard(
                title: 'Logo',
                imageUrl: activeBusiness.logoUrl,
                fallbackIcon: Icons.storefront_outlined,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _ImagePreviewCard(
                  title: 'Cover image',
                  imageUrl: activeBusiness.coverImageUrl,
                  fallbackIcon: Icons.landscape_outlined,
                  height: 132,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ImagePreviewCard extends StatelessWidget {
  const _ImagePreviewCard({
    required this.title,
    required this.imageUrl,
    required this.fallbackIcon,
    this.height = 96,
  });

  final String title;
  final String imageUrl;
  final IconData fallbackIcon;
  final double height;

  @override
  Widget build(BuildContext context) {
    final hasImage = imageUrl.trim().isNotEmpty;
    final width = title == 'Logo' ? 120.0 : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.labelLarge?.copyWith(color: const Color(0xFF52606D)),
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Container(
            width: width,
            height: height,
            decoration: BoxDecoration(
              color: const Color(0xFFEAF2EE),
              border: Border.all(color: const Color(0xFFD6E4DD)),
            ),
            child: hasImage
                ? Image.network(
                    imageUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => Center(
                      child: Icon(
                        fallbackIcon,
                        color: const Color(0xFF6B7280),
                        size: 32,
                      ),
                    ),
                  )
                : Center(
                    child: Icon(
                      fallbackIcon,
                      color: const Color(0xFF6B7280),
                      size: 32,
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}

class _MediaRow extends StatelessWidget {
  const _MediaRow({
    required this.media,
    required this.canManageBusinesses,
    required this.actionInProgress,
    required this.onEdit,
    required this.onDelete,
  });

  final BusinessMediaSummary media;
  final bool canManageBusinesses;
  final bool actionInProgress;
  final Future<void> Function(BusinessMediaSummary media)? onEdit;
  final Future<void> Function(BusinessMediaSummary media)? onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: ValueKey('owner-media-row-${media.id}'),
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE4E7EB)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Container(
              width: 112,
              height: 84,
              color: const Color(0xFFEAF2EE),
              child: media.imageUrl.trim().isEmpty
                  ? const Icon(Icons.image_outlined, color: Color(0xFF6B7280))
                  : Image.network(
                      media.imageUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => const Icon(
                        Icons.image_outlined,
                        color: Color(0xFF6B7280),
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            media.title,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          if (media.isFeatured || media.isStorageBacked) ...[
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                if (media.isFeatured)
                                  const StatusPill(
                                    label: 'Featured',
                                    backgroundColor: Color(0xFFE7F5EF),
                                    foregroundColor: Color(0xFF1B7F5B),
                                  ),
                                if (media.isStorageBacked)
                                  const StatusPill(
                                    label: 'Storage-backed',
                                    backgroundColor: Color(0xFFE8F1FF),
                                    foregroundColor: Color(0xFF2457C5),
                                  ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  media.mediaType,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF1F2933),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (media.caption.trim().isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    media.caption,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: const Color(0xFF52606D),
                    ),
                  ),
                ],
                if (canManageBusinesses) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    children: [
                      TextButton.icon(
                        key: ValueKey('owner-media-edit-${media.id}'),
                        onPressed: actionInProgress || onEdit == null
                            ? null
                            : () => onEdit!(media),
                        icon: const Icon(Icons.edit_outlined),
                        label: const Text('Edit'),
                      ),
                      TextButton.icon(
                        key: ValueKey('owner-media-delete-${media.id}'),
                        onPressed: actionInProgress || onDelete == null
                            ? null
                            : () => onDelete!(media),
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('Delete'),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LocationRow extends StatelessWidget {
  const _LocationRow({
    required this.location,
    required this.canManageBusinesses,
    required this.actionInProgress,
    required this.onEdit,
    required this.onDelete,
  });

  final BusinessLocationSummary location;
  final bool canManageBusinesses;
  final bool actionInProgress;
  final Future<void> Function(BusinessLocationSummary location)? onEdit;
  final Future<void> Function(BusinessLocationSummary location)? onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE4E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  location.name,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              if (location.isPrimary)
                const StatusPill(
                  label: 'Primary',
                  backgroundColor: Color(0xFFE7F5EF),
                  foregroundColor: Color(0xFF1B7F5B),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${location.address}\n${location.workingHours} • ${location.phoneNumbers.join(', ')}',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          if (location.notes.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              location.notes,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: const Color(0xFF52606D)),
            ),
          ],
          if (canManageBusinesses) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              children: [
                TextButton.icon(
                  onPressed: actionInProgress || onEdit == null
                      ? null
                      : () => onEdit!(location),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Edit'),
                ),
                TextButton.icon(
                  onPressed: actionInProgress || onDelete == null
                      ? null
                      : () => onDelete!(location),
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Delete'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _CatalogItemRow extends StatelessWidget {
  const _CatalogItemRow({
    required this.item,
    required this.itemTypeLabel,
    required this.canManageBusinesses,
    required this.actionInProgress,
    required this.onEdit,
    required this.onDelete,
  });

  final BusinessCatalogItemSummary item;
  final String itemTypeLabel;
  final bool canManageBusinesses;
  final bool actionInProgress;
  final Future<void> Function(BusinessCatalogItemSummary item)? onEdit;
  final Future<void> Function(BusinessCatalogItemSummary item)? onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE4E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  item.name,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              StatusPill(
                label: item.isActive ? 'Active' : 'Paused',
                backgroundColor: item.isActive
                    ? const Color(0xFFE7F5EF)
                    : const Color(0xFFFFF2D8),
                foregroundColor: item.isActive
                    ? const Color(0xFF1B7F5B)
                    : const Color(0xFF9C6100),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '$itemTypeLabel • ${item.priceLabel}',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: const Color(0xFF1F2933),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            item.description,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: const Color(0xFF52606D)),
          ),
          if (canManageBusinesses) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              children: [
                TextButton.icon(
                  onPressed: actionInProgress || onEdit == null
                      ? null
                      : () => onEdit!(item),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Edit'),
                ),
                TextButton.icon(
                  onPressed: actionInProgress || onDelete == null
                      ? null
                      : () => onDelete!(item),
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Delete'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _DashboardTab extends StatelessWidget {
  const _DashboardTab({
    required this.metrics,
    required this.trendPoints,
    required this.businessPerformance,
    required this.activeBusiness,
    required this.canManageLedger,
    required this.actionInProgress,
    required this.onAdminAdjustCashback,
    required this.onRefundCashback,
    required this.onExpireWalletLots,
  });

  final List<DashboardMetric> metrics;
  final List<DashboardTrendPoint> trendPoints;
  final List<BusinessPerformanceSnapshot> businessPerformance;
  final BusinessSummary activeBusiness;
  final bool canManageLedger;
  final bool actionInProgress;
  final Future<void> Function()? onAdminAdjustCashback;
  final Future<void> Function()? onRefundCashback;
  final Future<void> Function()? onExpireWalletLots;

  @override
  Widget build(BuildContext context) {
    final hasTandemGroup = activeBusiness.groupId.trim().isNotEmpty;

    return Column(
      children: [
        SectionCard(
          title: 'Portfolio dashboard',
          subtitle:
              'Aggregated analytics are split per business in the backend, then rolled up for the owner surface.',
          child: MetricGrid(metrics: metrics),
        ),
        const SizedBox(height: 16),
        SectionCard(
          key: const ValueKey('owner-dashboard-trend-section'),
          title: '7 day trend',
          subtitle:
              'Live Firestore daily stats are rolled into a short operating view across all owned businesses.',
          child: trendPoints.isEmpty
              ? const Text(
                  'Trend data will appear after live operator activity.',
                )
              : Column(
                  children: trendPoints
                      .map(
                        (point) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _OwnerTrendRow(point: point),
                        ),
                      )
                      .toList(),
                ),
        ),
        const SizedBox(height: 16),
        SectionCard(
          key: const ValueKey('owner-business-performance-section'),
          title: 'Per-business analytics',
          subtitle:
              'Each owned business keeps its own private tandem performance footprint while the owner can still compare them side by side.',
          child: businessPerformance.isEmpty
              ? const Text(
                  'Business analytics will appear once daily stats exist.',
                )
              : Column(
                  children: businessPerformance
                      .map(
                        (snapshot) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _OwnerBusinessPerformanceTile(
                            snapshot: snapshot,
                          ),
                        ),
                      )
                      .toList(),
                ),
        ),
        const SizedBox(height: 16),
        SectionCard(
          key: const ValueKey('owner-ledger-controls-section'),
          title: 'Ledger controls',
          subtitle:
              'Refunds, manual adjustments, and expiry sweeps go through backend callables so the cashback ledger stays auditable.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  FilledButton.icon(
                    key: const ValueKey('owner-admin-adjust-button'),
                    onPressed:
                        canManageLedger && !actionInProgress && hasTandemGroup
                        ? onAdminAdjustCashback
                        : null,
                    icon: const Icon(Icons.tune_outlined),
                    label: const Text('Admin adjustment'),
                  ),
                  OutlinedButton.icon(
                    key: const ValueKey('owner-refund-cashback-button'),
                    onPressed: canManageLedger && !actionInProgress
                        ? onRefundCashback
                        : null,
                    icon: const Icon(Icons.undo_outlined),
                    label: const Text('Refund redemption'),
                  ),
                  OutlinedButton.icon(
                    key: const ValueKey('owner-expire-wallet-lots-button'),
                    onPressed:
                        canManageLedger && !actionInProgress && hasTandemGroup
                        ? onExpireWalletLots
                        : null,
                    icon: const Icon(Icons.hourglass_bottom_outlined),
                    label: const Text('Run expiry sweep'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                hasTandemGroup
                    ? 'Active group: ${activeBusiness.groupName}'
                    : 'This business is not attached to a tandem group yet, so manual adjustments and expiry sweeps stay locked.',
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const SectionCard(
          title: 'Operational notes',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _PlainBullet(
                'Cashback issuance must calculate only on paid value, never on redeemed cashback.',
              ),
              _PlainBullet(
                'Staff accounts remain soft-disabled for audit continuity instead of being deleted.',
              ),
              _PlainBullet(
                'Group join requests stay blocked until every current member business votes yes.',
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _OwnerTrendRow extends StatelessWidget {
  const _OwnerTrendRow({required this.point});

  final DashboardTrendPoint point;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE6DED1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(point.label, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 10),
          Wrap(
            spacing: 12,
            runSpacing: 10,
            children: [
              Chip(
                label: Text('Sales ${formatCurrency(point.salesMinorUnits)}'),
              ),
              Chip(
                label: Text('Issued ${formatCurrency(point.issuedMinorUnits)}'),
              ),
              Chip(
                label: Text(
                  'Redeemed ${formatCurrency(point.redeemedMinorUnits)}',
                ),
              ),
              Chip(label: Text('Clients ${point.clientsCount}')),
              Chip(label: Text('Lookups ${point.lookupsCount}')),
            ],
          ),
        ],
      ),
    );
  }
}

class _OwnerBusinessPerformanceTile extends StatelessWidget {
  const _OwnerBusinessPerformanceTile({required this.snapshot});

  final BusinessPerformanceSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FBF9),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFD1E3DC)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      snapshot.businessName,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      snapshot.groupName,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFF52606D),
                      ),
                    ),
                  ],
                ),
              ),
              Chip(label: Text('Today ${snapshot.todaySalesCount} tickets')),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 12,
            runSpacing: 10,
            children: [
              Chip(
                label: Text(
                  'Today sales ${formatCurrency(snapshot.todaySalesMinorUnits)}',
                ),
              ),
              Chip(
                label: Text(
                  '7d sales ${formatCurrency(snapshot.rolling7DaySalesMinorUnits)}',
                ),
              ),
              Chip(
                label: Text(
                  '7d issued ${formatCurrency(snapshot.rolling7DayIssuedMinorUnits)}',
                ),
              ),
              Chip(
                label: Text(
                  '7d redeemed ${formatCurrency(snapshot.rolling7DayRedeemedMinorUnits)}',
                ),
              ),
              Chip(
                label: Text('7d lookups ${snapshot.rolling7DayLookupsCount}'),
              ),
              Chip(label: Text('Today clients ${snapshot.todayClientsCount}')),
              Chip(label: Text('Total clients ${snapshot.totalClientsCount}')),
            ],
          ),
        ],
      ),
    );
  }
}

class _StaffTab extends StatelessWidget {
  const _StaffTab({
    required this.activeBusiness,
    required this.ownerBusinesses,
    required this.staffMembers,
    required this.joinRequests,
    required this.groupAuditEvents,
    required this.canManageStaff,
    required this.actionInProgress,
    required this.onCreateStaff,
    required this.onEditStaff,
    required this.onResetStaffPassword,
    required this.onDisableStaff,
    required this.onVoteOnJoinRequest,
  });

  final BusinessSummary activeBusiness;
  final List<BusinessSummary> ownerBusinesses;
  final List<StaffMemberSummary> staffMembers;
  final List<GroupJoinRequestSummary> joinRequests;
  final List<GroupAuditEventSummary> groupAuditEvents;
  final bool canManageStaff;
  final bool actionInProgress;
  final Future<void> Function()? onCreateStaff;
  final Future<void> Function(StaffMemberSummary staff)? onEditStaff;
  final Future<void> Function(StaffMemberSummary staff)? onResetStaffPassword;
  final Future<void> Function(StaffMemberSummary staff)? onDisableStaff;
  final Future<void> Function(
    GroupJoinRequestSummary request,
    List<BusinessSummary> ownerBusinesses,
  )?
  onVoteOnJoinRequest;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SectionCard(
          key: const ValueKey('owner-staff-section'),
          title: 'Staff accounts',
          subtitle:
              'Each staff account is locked to one business and managed by backend-owned auth flows.',
          trailing: FilledButton.icon(
            key: const ValueKey('owner-staff-create'),
            onPressed: canManageStaff && !actionInProgress
                ? onCreateStaff
                : null,
            icon: actionInProgress
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.person_add_alt_1),
            label: Text(
              canManageStaff
                  ? 'Create for ${activeBusiness.name}'
                  : 'Owner sign-in required',
            ),
          ),
          child: Column(
            children: staffMembers
                .map(
                  (staff) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(staff.name),
                    subtitle: Text(
                      '${staff.roleLabel} • ${staff.businessName}\n${staff.username}',
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        StatusPill(
                          label: staff.isActive ? 'Active' : 'Disabled',
                          backgroundColor: staff.isActive
                              ? const Color(0xFFE7F5EF)
                              : const Color(0xFFFDECEC),
                          foregroundColor: staff.isActive
                              ? const Color(0xFF1B7F5B)
                              : const Color(0xFFB23A48),
                        ),
                        if (canManageStaff) ...[
                          const SizedBox(width: 4),
                          PopupMenuButton<_StaffAccountAction>(
                            key: ValueKey(
                              'owner-staff-actions-${staff.username}',
                            ),
                            tooltip: 'Staff actions',
                            enabled: !actionInProgress,
                            onSelected: (action) async {
                              if (action == _StaffAccountAction.edit) {
                                await onEditStaff?.call(staff);
                                return;
                              }

                              if (action == _StaffAccountAction.resetPassword) {
                                if (staff.isActive) {
                                  await onResetStaffPassword?.call(staff);
                                }
                                return;
                              }

                              if (staff.isActive) {
                                await onDisableStaff?.call(staff);
                              }
                            },
                            itemBuilder: (context) => [
                              PopupMenuItem<_StaffAccountAction>(
                                key: ValueKey(
                                  'owner-staff-edit-${staff.username}',
                                ),
                                value: _StaffAccountAction.edit,
                                child: const Text('Edit staff'),
                              ),
                              if (staff.isActive)
                                PopupMenuItem<_StaffAccountAction>(
                                  key: ValueKey(
                                    'owner-staff-reset-${staff.username}',
                                  ),
                                  value: _StaffAccountAction.resetPassword,
                                  child: const Text('Reset password'),
                                ),
                              if (staff.isActive)
                                PopupMenuItem<_StaffAccountAction>(
                                  key: ValueKey(
                                    'owner-staff-disable-${staff.username}',
                                  ),
                                  value: _StaffAccountAction.disable,
                                  child: const Text('Disable'),
                                ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                )
                .toList(),
          ),
        ),
        const SizedBox(height: 16),
        SectionCard(
          title: 'Group approvals',
          subtitle:
              'Closed-group trust is enforced through unanimous business-level approvals.',
          child: Column(
            children: joinRequests
                .map(
                  (request) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    isThreeLine: true,
                    title: Text(request.businessName),
                    subtitle: Text(
                      '${request.groupName}\n${request.status} • ${request.approvalsReceived}/${request.approvalsRequired}\nRequested ${request.requestedAtLabel}',
                    ),
                    trailing:
                        request.statusCode == 'pending' &&
                            canManageStaff &&
                            onVoteOnJoinRequest != null
                        ? OutlinedButton(
                            onPressed: actionInProgress
                                ? null
                                : () => onVoteOnJoinRequest!(
                                    request,
                                    ownerBusinesses,
                                  ),
                            child: const Text('Vote'),
                          )
                        : null,
                  ),
                )
                .toList(),
          ),
        ),
        const SizedBox(height: 16),
        SectionCard(
          key: const ValueKey('owner-group-audit-section'),
          title: 'Tandem audit trail',
          subtitle:
              'Membership decisions stay traceable at the group level so approvals, rejections, and onboarding remain auditable.',
          child: groupAuditEvents.isEmpty
              ? const Text(
                  'Audit history will appear here once the tandem group records membership actions.',
                )
              : Column(
                  children: groupAuditEvents
                      .map(
                        (event) => ListTile(
                          key: ValueKey('owner-group-audit-event-${event.id}'),
                          contentPadding: EdgeInsets.zero,
                          leading: CircleAvatar(
                            backgroundColor: _auditBackgroundColor(
                              event.eventType,
                            ),
                            foregroundColor: _auditForegroundColor(
                              event.eventType,
                            ),
                            child: Icon(_auditIcon(event.eventType), size: 20),
                          ),
                          title: Text(event.title),
                          subtitle: Text(
                            '${event.detail}\n${event.groupName} • ${formatDateTime(event.occurredAt)}',
                          ),
                        ),
                      )
                      .toList(),
                ),
        ),
      ],
    );
  }
}

class _EditBusinessPayload {
  const _EditBusinessPayload({
    required this.name,
    required this.category,
    required this.description,
    required this.address,
    required this.workingHours,
    required this.phoneNumbers,
    required this.cashbackBasisPoints,
    required this.redeemPolicy,
  });

  final String name;
  final String category;
  final String description;
  final String address;
  final String workingHours;
  final List<String> phoneNumbers;
  final int cashbackBasisPoints;
  final String redeemPolicy;
}

IconData _auditIcon(String eventType) {
  switch (eventType) {
    case 'group_created':
      return Icons.groups_2_outlined;
    case 'join_request_created':
    case 'join_request_pending':
      return Icons.hourglass_top_outlined;
    case 'join_request_vote_yes':
      return Icons.how_to_vote_outlined;
    case 'join_request_approved':
      return Icons.verified_outlined;
    case 'join_request_rejected':
      return Icons.cancel_outlined;
    default:
      return Icons.timeline_outlined;
  }
}

Color _auditBackgroundColor(String eventType) {
  switch (eventType) {
    case 'join_request_rejected':
      return const Color(0xFFFDECEC);
    case 'join_request_approved':
    case 'group_created':
      return const Color(0xFFE7F5EF);
    case 'join_request_created':
    case 'join_request_pending':
    case 'join_request_vote_yes':
      return const Color(0xFFFFF2D8);
    default:
      return const Color(0xFFEFF4FF);
  }
}

Color _auditForegroundColor(String eventType) {
  switch (eventType) {
    case 'join_request_rejected':
      return const Color(0xFFB23A48);
    case 'join_request_approved':
    case 'group_created':
      return const Color(0xFF1B7F5B);
    case 'join_request_created':
    case 'join_request_pending':
    case 'join_request_vote_yes':
      return const Color(0xFF9C6100);
    default:
      return const Color(0xFF2455A6);
  }
}

class _CreateBusinessPayload extends _EditBusinessPayload {
  const _CreateBusinessPayload({
    required super.name,
    required super.category,
    required super.description,
    required super.address,
    required super.workingHours,
    required super.phoneNumbers,
    required super.cashbackBasisPoints,
    required super.redeemPolicy,
  });
}

class _RequestJoinGroupPayload {
  const _RequestJoinGroupPayload({
    required this.groupId,
    required this.groupName,
  });

  final String groupId;
  final String groupName;
}

class _LocationPayload {
  const _LocationPayload({
    required this.name,
    required this.address,
    required this.workingHours,
    required this.phoneNumbers,
    required this.notes,
    required this.isPrimary,
  });

  final String name;
  final String address;
  final String workingHours;
  final List<String> phoneNumbers;
  final String notes;
  final bool isPrimary;
}

class _CatalogItemPayload {
  const _CatalogItemPayload({
    required this.name,
    required this.description,
    required this.priceLabel,
    required this.isActive,
  });

  final String name;
  final String description;
  final String priceLabel;
  final bool isActive;
}

class _BrandingPayload {
  const _BrandingPayload({
    required this.logoUrl,
    required this.coverImageUrl,
    this.logoFile,
    this.coverFile,
  });

  final String logoUrl;
  final String coverImageUrl;
  final PickedBusinessAsset? logoFile;
  final PickedBusinessAsset? coverFile;
}

class _MediaPayload {
  const _MediaPayload({
    required this.title,
    required this.caption,
    required this.mediaType,
    required this.imageUrl,
    required this.isFeatured,
    this.imageFile,
  });

  final String title;
  final String caption;
  final String mediaType;
  final String imageUrl;
  final bool isFeatured;
  final PickedBusinessAsset? imageFile;
}

class _BrandingDialog extends ConsumerStatefulWidget {
  const _BrandingDialog({required this.business});

  final BusinessSummary business;

  @override
  ConsumerState<_BrandingDialog> createState() => _BrandingDialogState();
}

class _BrandingDialogState extends ConsumerState<_BrandingDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _logoUrlController;
  late final TextEditingController _coverImageUrlController;
  PickedBusinessAsset? _logoFile;
  PickedBusinessAsset? _coverFile;
  bool _logoPickerBusy = false;
  bool _coverPickerBusy = false;

  @override
  void initState() {
    super.initState();
    _logoUrlController = TextEditingController(text: widget.business.logoUrl);
    _coverImageUrlController = TextEditingController(
      text: widget.business.coverImageUrl,
    );
  }

  @override
  void dispose() {
    _logoUrlController.dispose();
    _coverImageUrlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Edit branding for ${widget.business.name}'),
      content: SizedBox(
        width: 520,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  key: const ValueKey('owner-branding-logo-url-input'),
                  controller: _logoUrlController,
                  decoration: const InputDecoration(
                    labelText: 'Logo image URL',
                    hintText: 'https://...',
                  ),
                  validator: _validateOptionalUrl,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    OutlinedButton.icon(
                      key: const ValueKey('owner-branding-upload-logo'),
                      onPressed: _logoPickerBusy ? null : _pickLogoImage,
                      icon: _logoPickerBusy
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.upload_file_outlined),
                      label: Text(
                        _logoFile == null ? 'Upload logo' : 'Replace logo file',
                      ),
                    ),
                    if (_logoFile != null) ...[
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Selected: ${_logoFile!.fileName}',
                          key: const ValueKey(
                            'owner-branding-logo-upload-name',
                          ),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const ValueKey('owner-branding-cover-url-input'),
                  controller: _coverImageUrlController,
                  decoration: const InputDecoration(
                    labelText: 'Cover image URL',
                    hintText: 'https://...',
                  ),
                  validator: _validateOptionalUrl,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    OutlinedButton.icon(
                      key: const ValueKey('owner-branding-upload-cover'),
                      onPressed: _coverPickerBusy ? null : _pickCoverImage,
                      icon: _coverPickerBusy
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.upload_file_outlined),
                      label: Text(
                        _coverFile == null
                            ? 'Upload cover'
                            : 'Replace cover file',
                      ),
                    ),
                    if (_coverFile != null) ...[
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Selected: ${_coverFile!.fileName}',
                          key: const ValueKey(
                            'owner-branding-cover-upload-name',
                          ),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'URLs still work as a fallback. If you upload a file here, it will go to Firebase Storage and the business profile will keep the storage path for future replacements.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF52606D),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'If Storage has not been initialized in Firebase Console yet, upload will fail fast with a clear setup message instead of hanging.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF6B7280),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('owner-branding-save'),
          onPressed: () {
            if (!_formKey.currentState!.validate()) {
              return;
            }

            Navigator.of(context).pop(
              _BrandingPayload(
                logoUrl: _logoUrlController.text.trim(),
                coverImageUrl: _coverImageUrlController.text.trim(),
                logoFile: _logoFile,
                coverFile: _coverFile,
              ),
            );
          },
          child: const Text('Save'),
        ),
      ],
    );
  }

  Future<void> _pickLogoImage() async {
    await _pickImage(isLogo: true, dialogTitle: 'Choose logo image');
  }

  Future<void> _pickCoverImage() async {
    await _pickImage(isLogo: false, dialogTitle: 'Choose cover image');
  }

  Future<void> _pickImage({
    required bool isLogo,
    required String dialogTitle,
  }) async {
    setState(() {
      if (isLogo) {
        _logoPickerBusy = true;
      } else {
        _coverPickerBusy = true;
      }
    });

    try {
      final picked = await ref
          .read(businessAssetPickerProvider)
          .pickImage(dialogTitle: dialogTitle);
      if (!mounted || picked == null) {
        return;
      }

      setState(() {
        if (isLogo) {
          _logoFile = picked;
        } else {
          _coverFile = picked;
        }
      });
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
          if (isLogo) {
            _logoPickerBusy = false;
          } else {
            _coverPickerBusy = false;
          }
        });
      }
    }
  }

  String? _validateOptionalUrl(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) {
      return null;
    }
    final uri = Uri.tryParse(trimmed);
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
      return 'Use a valid http or https URL.';
    }
    return null;
  }
}

class _MediaDialog extends ConsumerStatefulWidget {
  const _MediaDialog({required this.businessName, this.initial});

  final String businessName;
  final BusinessMediaSummary? initial;

  @override
  ConsumerState<_MediaDialog> createState() => _MediaDialogState();
}

class _MediaDialogState extends ConsumerState<_MediaDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late final TextEditingController _captionController;
  late final TextEditingController _imageUrlController;
  late String _mediaType;
  late bool _isFeatured;
  PickedBusinessAsset? _imageFile;
  bool _pickerBusy = false;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _titleController = TextEditingController(text: initial?.title ?? '');
    _captionController = TextEditingController(text: initial?.caption ?? '');
    _imageUrlController = TextEditingController(text: initial?.imageUrl ?? '');
    _mediaType = initial?.mediaType ?? 'gallery';
    _isFeatured = initial?.isFeatured ?? false;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _captionController.dispose();
    _imageUrlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.initial != null;

    return AlertDialog(
      title: Text(isEditing ? 'Edit media item' : 'Add media item'),
      content: SizedBox(
        width: 520,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'This media entry belongs to ${widget.businessName}.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  key: const ValueKey('owner-media-title-input'),
                  controller: _titleController,
                  decoration: const InputDecoration(labelText: 'Title'),
                  validator: _required,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _mediaType,
                  decoration: const InputDecoration(labelText: 'Media type'),
                  items: const [
                    DropdownMenuItem(value: 'gallery', child: Text('Gallery')),
                    DropdownMenuItem(
                      value: 'menu',
                      child: Text('Menu highlight'),
                    ),
                    DropdownMenuItem(
                      value: 'portfolio',
                      child: Text('Portfolio'),
                    ),
                    DropdownMenuItem(
                      value: 'storefront',
                      child: Text('Storefront'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value == null) {
                      return;
                    }
                    setState(() {
                      _mediaType = value;
                    });
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const ValueKey('owner-media-image-url-input'),
                  controller: _imageUrlController,
                  decoration: const InputDecoration(
                    labelText: 'Image URL',
                    hintText: 'https://...',
                  ),
                  validator: _validateMediaImageSource,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    OutlinedButton.icon(
                      key: const ValueKey('owner-media-upload-image'),
                      onPressed: _pickerBusy ? null : _pickImage,
                      icon: _pickerBusy
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.upload_file_outlined),
                      label: Text(
                        _imageFile == null ? 'Upload image' : 'Replace image',
                      ),
                    ),
                    if (_imageFile != null) ...[
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Selected: ${_imageFile!.fileName}',
                          key: const ValueKey('owner-media-upload-name'),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'Use either a direct URL or a Storage upload. Upload needs Firebase Storage to be initialized for this project.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF6B7280),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const ValueKey('owner-media-caption-input'),
                  controller: _captionController,
                  decoration: const InputDecoration(
                    labelText: 'Caption',
                    hintText:
                        'Seasonal menu, signature service, inside view...',
                  ),
                  minLines: 2,
                  maxLines: 4,
                ),
                const SizedBox(height: 12),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Featured media'),
                  subtitle: const Text(
                    'Featured items stay pinned higher in the gallery section.',
                  ),
                  value: _isFeatured,
                  onChanged: (value) {
                    setState(() {
                      _isFeatured = value;
                    });
                  },
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('owner-media-save'),
          onPressed: () {
            if (!_formKey.currentState!.validate()) {
              return;
            }

            Navigator.of(context).pop(
              _MediaPayload(
                title: _titleController.text.trim(),
                caption: _captionController.text.trim(),
                mediaType: _mediaType,
                imageUrl: _imageUrlController.text.trim(),
                isFeatured: _isFeatured,
                imageFile: _imageFile,
              ),
            );
          },
          child: Text(isEditing ? 'Save' : 'Add'),
        ),
      ],
    );
  }

  String? _required(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'This field is required.';
    }
    return null;
  }

  Future<void> _pickImage() async {
    setState(() {
      _pickerBusy = true;
    });

    try {
      final picked = await ref
          .read(businessAssetPickerProvider)
          .pickImage(dialogTitle: 'Choose gallery image');
      if (!mounted || picked == null) {
        return;
      }

      setState(() {
        _imageFile = picked;
      });
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
          _pickerBusy = false;
        });
      }
    }
  }

  String? _validateMediaImageSource(String? value) {
    if (_imageFile != null) {
      return null;
    }
    if (value == null || value.trim().isEmpty) {
      return 'Provide an image URL or upload a file.';
    }
    final uri = Uri.tryParse(value.trim());
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
      return 'Use a valid http or https URL.';
    }
    return null;
  }
}

class _BusinessLocationDialog extends StatefulWidget {
  const _BusinessLocationDialog({required this.businessName, this.initial});

  final String businessName;
  final BusinessLocationSummary? initial;

  @override
  State<_BusinessLocationDialog> createState() =>
      _BusinessLocationDialogState();
}

class _BusinessLocationDialogState extends State<_BusinessLocationDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _addressController;
  late final TextEditingController _workingHoursController;
  late final TextEditingController _phoneNumbersController;
  late final TextEditingController _notesController;
  late bool _isPrimary;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _nameController = TextEditingController(text: initial?.name ?? '');
    _addressController = TextEditingController(text: initial?.address ?? '');
    _workingHoursController = TextEditingController(
      text: initial?.workingHours ?? '',
    );
    _phoneNumbersController = TextEditingController(
      text: initial?.phoneNumbers.join(', ') ?? '',
    );
    _notesController = TextEditingController(text: initial?.notes ?? '');
    _isPrimary = initial?.isPrimary ?? false;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    _workingHoursController.dispose();
    _phoneNumbersController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.initial != null;

    return AlertDialog(
      title: Text(isEditing ? 'Edit location' : 'Add location'),
      content: SizedBox(
        width: 520,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'This location belongs to ${widget.businessName}.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Location name',
                    hintText: 'Old Town branch',
                  ),
                  validator: _required,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _addressController,
                  decoration: const InputDecoration(labelText: 'Address'),
                  validator: _required,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _workingHoursController,
                  decoration: const InputDecoration(labelText: 'Working hours'),
                  validator: _required,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _phoneNumbersController,
                  decoration: const InputDecoration(
                    labelText: 'Phone numbers',
                    hintText: '+998712000111, +998901234567',
                  ),
                  validator: (value) {
                    final phoneNumbers = _parsePhoneNumbers(value);
                    if (phoneNumbers.isEmpty) {
                      return 'Enter at least one phone number.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _notesController,
                  decoration: const InputDecoration(
                    labelText: 'Location notes',
                    hintText:
                        'Second floor, takeaway counter, parking available',
                  ),
                  minLines: 2,
                  maxLines: 4,
                ),
                const SizedBox(height: 12),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Primary location'),
                  subtitle: const Text(
                    'Use this for the main branch highlighted in the business profile.',
                  ),
                  value: _isPrimary,
                  onChanged: (value) {
                    setState(() {
                      _isPrimary = value;
                    });
                  },
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (!_formKey.currentState!.validate()) {
              return;
            }

            Navigator.of(context).pop(
              _LocationPayload(
                name: _nameController.text.trim(),
                address: _addressController.text.trim(),
                workingHours: _workingHoursController.text.trim(),
                phoneNumbers: _parsePhoneNumbers(_phoneNumbersController.text),
                notes: _notesController.text.trim(),
                isPrimary: _isPrimary,
              ),
            );
          },
          child: Text(isEditing ? 'Save' : 'Add'),
        ),
      ],
    );
  }

  List<String> _parsePhoneNumbers(String? value) {
    return (value ?? '')
        .split(',')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
  }

  String? _required(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'This field is required.';
    }
    return null;
  }
}

class _CatalogItemDialog extends StatefulWidget {
  const _CatalogItemDialog({
    required this.title,
    required this.itemTypeLabel,
    this.initial,
  });

  final String title;
  final String itemTypeLabel;
  final BusinessCatalogItemSummary? initial;

  @override
  State<_CatalogItemDialog> createState() => _CatalogItemDialogState();
}

class _CatalogItemDialogState extends State<_CatalogItemDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _priceLabelController;
  late bool _isActive;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _nameController = TextEditingController(text: initial?.name ?? '');
    _descriptionController = TextEditingController(
      text: initial?.description ?? '',
    );
    _priceLabelController = TextEditingController(
      text: initial?.priceLabel ?? '',
    );
    _isActive = initial?.isActive ?? true;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _priceLabelController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 520,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _nameController,
                  decoration: InputDecoration(
                    labelText: '${widget.itemTypeLabel} name',
                    hintText: widget.itemTypeLabel == 'product'
                        ? 'Signature breakfast set'
                        : 'Private tasting session',
                  ),
                  validator: _required,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _descriptionController,
                  decoration: InputDecoration(
                    labelText: '${widget.itemTypeLabel} description',
                  ),
                  minLines: 3,
                  maxLines: 5,
                  validator: _required,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _priceLabelController,
                  decoration: const InputDecoration(
                    labelText: 'Price label',
                    hintText: '55 000 UZS / from 90 000 UZS / seasonal',
                  ),
                  validator: _required,
                ),
                const SizedBox(height: 12),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Visible in catalog'),
                  subtitle: const Text(
                    'Paused items stay in Firestore but are clearly marked in the owner view.',
                  ),
                  value: _isActive,
                  onChanged: (value) {
                    setState(() {
                      _isActive = value;
                    });
                  },
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (!_formKey.currentState!.validate()) {
              return;
            }

            Navigator.of(context).pop(
              _CatalogItemPayload(
                name: _nameController.text.trim(),
                description: _descriptionController.text.trim(),
                priceLabel: _priceLabelController.text.trim(),
                isActive: _isActive,
              ),
            );
          },
          child: const Text('Save'),
        ),
      ],
    );
  }

  String? _required(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'This field is required.';
    }
    return null;
  }
}

class _CreateBusinessDialog extends StatefulWidget {
  const _CreateBusinessDialog();

  @override
  State<_CreateBusinessDialog> createState() => _CreateBusinessDialogState();
}

class _CreateBusinessDialogState extends State<_CreateBusinessDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _categoryController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _addressController = TextEditingController();
  final _workingHoursController = TextEditingController();
  final _phoneNumbersController = TextEditingController();
  final _cashbackController = TextEditingController(text: '500');
  final _redeemPolicyController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _categoryController.dispose();
    _descriptionController.dispose();
    _addressController.dispose();
    _workingHoursController.dispose();
    _phoneNumbersController.dispose();
    _cashbackController.dispose();
    _redeemPolicyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Create business'),
      content: SizedBox(
        width: 520,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(labelText: 'Business name'),
                  validator: _required,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _categoryController,
                  decoration: const InputDecoration(labelText: 'Category'),
                  validator: _required,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _descriptionController,
                  decoration: const InputDecoration(labelText: 'Description'),
                  minLines: 3,
                  maxLines: 5,
                  validator: _required,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _addressController,
                  decoration: const InputDecoration(labelText: 'Address'),
                  validator: _required,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _workingHoursController,
                  decoration: const InputDecoration(labelText: 'Working hours'),
                  validator: _required,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _phoneNumbersController,
                  decoration: const InputDecoration(
                    labelText: 'Phone numbers',
                    hintText: '+998712000111, +998901234567',
                  ),
                  validator: (value) {
                    final phoneNumbers = _parsePhoneNumbers(value);
                    if (phoneNumbers.isEmpty) {
                      return 'Enter at least one phone number.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _cashbackController,
                  decoration: const InputDecoration(
                    labelText: 'Cashback basis points',
                    hintText: '500',
                  ),
                  keyboardType: TextInputType.number,
                  validator: (value) {
                    final parsed = int.tryParse(value?.trim() ?? '');
                    if (parsed == null || parsed < 0 || parsed > 10000) {
                      return 'Use a whole number between 0 and 10000.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _redeemPolicyController,
                  decoration: const InputDecoration(labelText: 'Redeem policy'),
                  minLines: 2,
                  maxLines: 4,
                  validator: _required,
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (!_formKey.currentState!.validate()) {
              return;
            }

            Navigator.of(context).pop(
              _CreateBusinessPayload(
                name: _nameController.text.trim(),
                category: _categoryController.text.trim(),
                description: _descriptionController.text.trim(),
                address: _addressController.text.trim(),
                workingHours: _workingHoursController.text.trim(),
                phoneNumbers: _parsePhoneNumbers(_phoneNumbersController.text),
                cashbackBasisPoints: int.parse(_cashbackController.text.trim()),
                redeemPolicy: _redeemPolicyController.text.trim(),
              ),
            );
          },
          child: const Text('Create'),
        ),
      ],
    );
  }

  List<String> _parsePhoneNumbers(String? value) {
    return (value ?? '')
        .split(',')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
  }

  String? _required(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'This field is required.';
    }
    return null;
  }
}

class _CreateTandemGroupDialog extends StatefulWidget {
  const _CreateTandemGroupDialog({required this.businessName});

  final String businessName;

  @override
  State<_CreateTandemGroupDialog> createState() =>
      _CreateTandemGroupDialogState();
}

class _CreateTandemGroupDialogState extends State<_CreateTandemGroupDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: '${widget.businessName} Circle',
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Create tandem group for ${widget.businessName}'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: TextFormField(
            controller: _nameController,
            decoration: const InputDecoration(labelText: 'Group name'),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Group name is required.';
              }
              return null;
            },
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (!_formKey.currentState!.validate()) {
              return;
            }

            Navigator.of(context).pop(_nameController.text.trim());
          },
          child: const Text('Create group'),
        ),
      ],
    );
  }
}

class _RequestJoinGroupDialog extends StatefulWidget {
  const _RequestJoinGroupDialog({required this.business, required this.groups});

  final BusinessSummary business;
  final List<JoinableGroupOption> groups;

  @override
  State<_RequestJoinGroupDialog> createState() =>
      _RequestJoinGroupDialogState();
}

class _RequestJoinGroupDialogState extends State<_RequestJoinGroupDialog> {
  late String _selectedGroupId;

  @override
  void initState() {
    super.initState();
    _selectedGroupId = widget.groups.first.id;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Request ${widget.business.name} to join a group'),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Every active member business in the selected group must approve this request.',
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _selectedGroupId,
              decoration: const InputDecoration(labelText: 'Target group'),
              items: widget.groups
                  .map(
                    (group) => DropdownMenuItem<String>(
                      value: group.id,
                      child: Text(
                        '${group.name} (${group.activeBusinessCount} active)',
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value == null) {
                  return;
                }
                setState(() {
                  _selectedGroupId = value;
                });
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final selectedGroup = widget.groups.firstWhere(
              (group) => group.id == _selectedGroupId,
            );
            Navigator.of(context).pop(
              _RequestJoinGroupPayload(
                groupId: selectedGroup.id,
                groupName: selectedGroup.name,
              ),
            );
          },
          child: const Text('Request join'),
        ),
      ],
    );
  }
}

class _EditBusinessDialog extends StatefulWidget {
  const _EditBusinessDialog({required this.business});

  final BusinessSummary business;

  @override
  State<_EditBusinessDialog> createState() => _EditBusinessDialogState();
}

class _EditBusinessDialogState extends State<_EditBusinessDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _categoryController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _addressController;
  late final TextEditingController _workingHoursController;
  late final TextEditingController _phoneNumbersController;
  late final TextEditingController _cashbackController;
  late final TextEditingController _redeemPolicyController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.business.name);
    _categoryController = TextEditingController(text: widget.business.category);
    _descriptionController = TextEditingController(
      text: widget.business.description,
    );
    _addressController = TextEditingController(text: widget.business.address);
    _workingHoursController = TextEditingController(
      text: widget.business.workingHours,
    );
    _phoneNumbersController = TextEditingController(
      text: widget.business.phoneNumbers.join(', '),
    );
    _cashbackController = TextEditingController(
      text: widget.business.cashbackBasisPoints.toString(),
    );
    _redeemPolicyController = TextEditingController(
      text: widget.business.redeemPolicy,
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _categoryController.dispose();
    _descriptionController.dispose();
    _addressController.dispose();
    _workingHoursController.dispose();
    _phoneNumbersController.dispose();
    _cashbackController.dispose();
    _redeemPolicyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Edit ${widget.business.name}'),
      content: SizedBox(
        width: 520,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(labelText: 'Business name'),
                  validator: _required,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _categoryController,
                  decoration: const InputDecoration(labelText: 'Category'),
                  validator: _required,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _descriptionController,
                  decoration: const InputDecoration(labelText: 'Description'),
                  minLines: 3,
                  maxLines: 5,
                  validator: _required,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _addressController,
                  decoration: const InputDecoration(labelText: 'Address'),
                  validator: _required,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _workingHoursController,
                  decoration: const InputDecoration(labelText: 'Working hours'),
                  validator: _required,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _phoneNumbersController,
                  decoration: const InputDecoration(
                    labelText: 'Phone numbers',
                    hintText: '+998712000111, +998901234567',
                  ),
                  validator: (value) {
                    final phoneNumbers = _parsePhoneNumbers(value);
                    if (phoneNumbers.isEmpty) {
                      return 'Enter at least one phone number.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _cashbackController,
                  decoration: const InputDecoration(
                    labelText: 'Cashback basis points',
                    hintText: '700',
                  ),
                  keyboardType: TextInputType.number,
                  validator: (value) {
                    final parsed = int.tryParse(value?.trim() ?? '');
                    if (parsed == null || parsed < 0 || parsed > 10000) {
                      return 'Use a whole number between 0 and 10000.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _redeemPolicyController,
                  decoration: const InputDecoration(labelText: 'Redeem policy'),
                  minLines: 2,
                  maxLines: 4,
                  validator: _required,
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (!_formKey.currentState!.validate()) {
              return;
            }

            Navigator.of(context).pop(
              _EditBusinessPayload(
                name: _nameController.text.trim(),
                category: _categoryController.text.trim(),
                description: _descriptionController.text.trim(),
                address: _addressController.text.trim(),
                workingHours: _workingHoursController.text.trim(),
                phoneNumbers: _parsePhoneNumbers(_phoneNumbersController.text),
                cashbackBasisPoints: int.parse(_cashbackController.text.trim()),
                redeemPolicy: _redeemPolicyController.text.trim(),
              ),
            );
          },
          child: const Text('Save'),
        ),
      ],
    );
  }

  List<String> _parsePhoneNumbers(String? value) {
    return (value ?? '')
        .split(',')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
  }

  String? _required(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'This field is required.';
    }
    return null;
  }
}

class _VoteOnJoinRequestPayload {
  const _VoteOnJoinRequestPayload({
    required this.voterBusinessId,
    required this.voterBusinessName,
    required this.vote,
  });

  final String voterBusinessId;
  final String voterBusinessName;
  final String vote;
}

class _VoteOnJoinRequestDialog extends StatefulWidget {
  const _VoteOnJoinRequestDialog({
    required this.request,
    required this.eligibleBusinesses,
  });

  final GroupJoinRequestSummary request;
  final List<BusinessSummary> eligibleBusinesses;

  @override
  State<_VoteOnJoinRequestDialog> createState() =>
      _VoteOnJoinRequestDialogState();
}

class _VoteOnJoinRequestDialogState extends State<_VoteOnJoinRequestDialog> {
  final _formKey = GlobalKey<FormState>();
  late String _selectedBusinessId;
  String _selectedVote = 'yes';

  @override
  void initState() {
    super.initState();
    _selectedBusinessId = widget.eligibleBusinesses.first.id;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Vote on ${widget.request.businessName}'),
      content: SizedBox(
        width: 460,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Each active member business must vote separately before the join request can be approved.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _selectedBusinessId,
                decoration: const InputDecoration(labelText: 'Voting business'),
                items: widget.eligibleBusinesses
                    .map(
                      (business) => DropdownMenuItem<String>(
                        value: business.id,
                        child: Text(business.name),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value == null) {
                    return;
                  }

                  setState(() {
                    _selectedBusinessId = value;
                  });
                },
              ),
              const SizedBox(height: 16),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment<String>(
                    value: 'yes',
                    label: Text('Approve'),
                    icon: Icon(Icons.thumb_up_alt_outlined),
                  ),
                  ButtonSegment<String>(
                    value: 'no',
                    label: Text('Reject'),
                    icon: Icon(Icons.thumb_down_alt_outlined),
                  ),
                ],
                selected: {_selectedVote},
                onSelectionChanged: (selection) {
                  setState(() {
                    _selectedVote = selection.first;
                  });
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (!_formKey.currentState!.validate()) {
              return;
            }

            final selectedBusiness = widget.eligibleBusinesses.firstWhere(
              (business) => business.id == _selectedBusinessId,
            );

            Navigator.of(context).pop(
              _VoteOnJoinRequestPayload(
                voterBusinessId: selectedBusiness.id,
                voterBusinessName: selectedBusiness.name,
                vote: _selectedVote,
              ),
            );
          },
          child: Text(_selectedVote == 'yes' ? 'Approve' : 'Reject'),
        ),
      ],
    );
  }
}

class _AdminAdjustmentPayload {
  const _AdminAdjustmentPayload({
    required this.customerPhoneE164,
    required this.amountMinorUnits,
    required this.note,
    required this.direction,
  });

  final String customerPhoneE164;
  final int amountMinorUnits;
  final String note;
  final _AdjustmentDirection direction;
}

class _RefundCashbackPayload {
  const _RefundCashbackPayload({required this.redemptionBatchId, this.note});

  final String redemptionBatchId;
  final String? note;
}

class _ExpireWalletLotsPayload {
  const _ExpireWalletLotsPayload({this.maxLots});

  final int? maxLots;
}

class _AdminAdjustmentDialog extends StatefulWidget {
  const _AdminAdjustmentDialog({required this.business});

  final BusinessSummary business;

  @override
  State<_AdminAdjustmentDialog> createState() => _AdminAdjustmentDialogState();
}

class _AdminAdjustmentDialogState extends State<_AdminAdjustmentDialog> {
  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();
  final _amountController = TextEditingController(text: '12000');
  final _noteController = TextEditingController(text: 'Owner manual credit');
  _AdjustmentDirection _direction = _AdjustmentDirection.credit;

  @override
  void dispose() {
    _phoneController.dispose();
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Admin adjustment · ${widget.business.name}'),
      content: SizedBox(
        width: 460,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'The original issuer business and full audit trail stay preserved. Use this only for controlled corrections.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<_AdjustmentDirection>(
                key: const ValueKey('owner-admin-adjust-direction-input'),
                initialValue: _direction,
                decoration: const InputDecoration(labelText: 'Direction'),
                items: const [
                  DropdownMenuItem(
                    value: _AdjustmentDirection.credit,
                    child: Text('Credit wallet'),
                  ),
                  DropdownMenuItem(
                    value: _AdjustmentDirection.debit,
                    child: Text('Debit wallet'),
                  ),
                ],
                onChanged: (value) {
                  if (value == null) {
                    return;
                  }
                  setState(() {
                    _direction = value;
                    if (_direction == _AdjustmentDirection.credit &&
                        _noteController.text.trim().isEmpty) {
                      _noteController.text = 'Owner manual credit';
                    }
                    if (_direction == _AdjustmentDirection.debit &&
                        _noteController.text.trim().isEmpty) {
                      _noteController.text = 'Owner manual debit';
                    }
                  });
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const ValueKey('owner-admin-adjust-phone-input'),
                controller: _phoneController,
                decoration: const InputDecoration(
                  labelText: 'Customer phone (E.164)',
                  hintText: '+998901234567',
                ),
                validator: (value) {
                  final trimmed = value?.trim() ?? '';
                  if (!RegExp(r'^\+\d{10,15}$').hasMatch(trimmed)) {
                    return 'Use a valid E.164 phone number.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const ValueKey('owner-admin-adjust-amount-input'),
                controller: _amountController,
                decoration: const InputDecoration(
                  labelText: 'Amount (UZS)',
                  hintText: '12000',
                ),
                keyboardType: TextInputType.number,
                validator: (value) {
                  final parsed = int.tryParse(value?.trim() ?? '');
                  if (parsed == null || parsed <= 0) {
                    return 'Use a positive whole number.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const ValueKey('owner-admin-adjust-note-input'),
                controller: _noteController,
                decoration: const InputDecoration(
                  labelText: 'Audit note',
                  hintText: 'Owner manual credit',
                ),
                minLines: 2,
                maxLines: 4,
                validator: _required,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('owner-admin-adjust-submit'),
          onPressed: () {
            if (!_formKey.currentState!.validate()) {
              return;
            }

            Navigator.of(context).pop(
              _AdminAdjustmentPayload(
                customerPhoneE164: _phoneController.text.trim(),
                amountMinorUnits: int.parse(_amountController.text.trim()),
                note: _noteController.text.trim(),
                direction: _direction,
              ),
            );
          },
          child: Text(
            _direction == _AdjustmentDirection.debit
                ? 'Apply debit'
                : 'Apply credit',
          ),
        ),
      ],
    );
  }

  String? _required(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'This field is required.';
    }
    return null;
  }
}

class _RefundCashbackDialog extends StatefulWidget {
  const _RefundCashbackDialog({required this.business});

  final BusinessSummary business;

  @override
  State<_RefundCashbackDialog> createState() => _RefundCashbackDialogState();
}

class _RefundCashbackDialogState extends State<_RefundCashbackDialog> {
  final _formKey = GlobalKey<FormState>();
  final _batchIdController = TextEditingController();
  final _noteController = TextEditingController();

  @override
  void dispose() {
    _batchIdController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Refund redemption · ${widget.business.name}'),
      content: SizedBox(
        width: 460,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Enter the redemption batch id that should be restored to customer wallets.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              TextFormField(
                key: const ValueKey('owner-refund-batch-id-input'),
                controller: _batchIdController,
                decoration: const InputDecoration(
                  labelText: 'Redemption batch id',
                ),
                validator: _required,
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const ValueKey('owner-refund-note-input'),
                controller: _noteController,
                decoration: const InputDecoration(
                  labelText: 'Internal note (optional)',
                ),
                minLines: 2,
                maxLines: 3,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('owner-refund-submit'),
          onPressed: () {
            if (!_formKey.currentState!.validate()) {
              return;
            }

            Navigator.of(context).pop(
              _RefundCashbackPayload(
                redemptionBatchId: _batchIdController.text.trim(),
                note: _noteController.text.trim().isEmpty
                    ? null
                    : _noteController.text.trim(),
              ),
            );
          },
          child: const Text('Create refund'),
        ),
      ],
    );
  }

  String? _required(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'This field is required.';
    }
    return null;
  }
}

class _ExpireWalletLotsDialog extends StatefulWidget {
  const _ExpireWalletLotsDialog({required this.business});

  final BusinessSummary business;

  @override
  State<_ExpireWalletLotsDialog> createState() =>
      _ExpireWalletLotsDialogState();
}

class _ExpireWalletLotsDialogState extends State<_ExpireWalletLotsDialog> {
  final _formKey = GlobalKey<FormState>();
  final _maxLotsController = TextEditingController(text: '50');

  @override
  void dispose() {
    _maxLotsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Run expiry sweep · ${widget.business.name}'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'This scans the active wallet lots in ${widget.business.groupName} and appends expire events for anything already past due.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              TextFormField(
                key: const ValueKey('owner-expire-max-lots-input'),
                controller: _maxLotsController,
                decoration: const InputDecoration(
                  labelText: 'Max lots to scan',
                  hintText: '50',
                ),
                keyboardType: TextInputType.number,
                validator: (value) {
                  final trimmed = value?.trim() ?? '';
                  if (trimmed.isEmpty) {
                    return null;
                  }
                  final parsed = int.tryParse(trimmed);
                  if (parsed == null || parsed <= 0) {
                    return 'Use a positive whole number or leave it blank.';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('owner-expire-submit'),
          onPressed: () {
            if (!_formKey.currentState!.validate()) {
              return;
            }

            final trimmed = _maxLotsController.text.trim();
            Navigator.of(context).pop(
              _ExpireWalletLotsPayload(
                maxLots: trimmed.isEmpty ? null : int.parse(trimmed),
              ),
            );
          },
          child: const Text('Run sweep'),
        ),
      ],
    );
  }
}

class _BusinessTile extends StatelessWidget {
  const _BusinessTile({
    required this.business,
    required this.isActive,
    required this.canManageBusinesses,
    required this.actionInProgress,
    required this.onEditBusiness,
  });

  final BusinessSummary business;
  final bool isActive;
  final bool canManageBusinesses;
  final bool actionInProgress;
  final Future<void> Function(BusinessSummary business)? onEditBusiness;

  @override
  Widget build(BuildContext context) {
    final status = switch (business.groupStatus) {
      GroupMembershipStatus.active => (
        label: 'Active in tandem',
        background: const Color(0xFFE7F5EF),
        foreground: const Color(0xFF1B7F5B),
      ),
      GroupMembershipStatus.pendingApproval => (
        label: 'Pending approval',
        background: const Color(0xFFFFF2D8),
        foreground: const Color(0xFF9C6100),
      ),
      GroupMembershipStatus.rejected => (
        label: 'Rejected',
        background: const Color(0xFFFDECEC),
        foreground: const Color(0xFFB23A48),
      ),
      GroupMembershipStatus.notGrouped => (
        label: 'No tandem group',
        background: const Color(0xFFEFF4FF),
        foreground: const Color(0xFF2455A6),
      ),
    };

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isActive ? const Color(0xFFF1F7F4) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isActive ? const Color(0xFF1B5E52) : const Color(0xFFE6DED1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  business.name,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              StatusPill(
                label: status.label,
                backgroundColor: status.background,
                foregroundColor: status.foreground,
              ),
            ],
          ),
          if (canManageBusinesses) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: actionInProgress || onEditBusiness == null
                    ? null
                    : () => onEditBusiness!(business),
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Edit profile'),
              ),
            ),
          ],
          const SizedBox(height: 10),
          Text(
            business.description,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: const Color(0xFF52606D)),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              Chip(label: Text(business.category)),
              Chip(label: Text(business.workingHours)),
              Chip(label: Text('${business.locationsCount} locations')),
              Chip(label: Text('${business.productsCount} products/services')),
              Chip(label: Text(formatPercent(business.cashbackBasisPoints))),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '${business.address}\n${business.phoneNumbers.join(', ')}\n${business.groupName} • ${business.redeemPolicy}',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}

class _PlainBullet extends StatelessWidget {
  const _PlainBullet(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Icon(Icons.circle, size: 8),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

class _CreateStaffPayload {
  const _CreateStaffPayload({
    required this.displayName,
    required this.username,
    required this.password,
  });

  final String displayName;
  final String username;
  final String password;
}

class _EditStaffPayload {
  const _EditStaffPayload({required this.displayName});

  final String displayName;
}

class _ResetStaffPasswordPayload {
  const _ResetStaffPasswordPayload({required this.password});

  final String password;
}

class _CreateStaffDialog extends StatefulWidget {
  const _CreateStaffDialog({required this.businessName});

  final String businessName;

  @override
  State<_CreateStaffDialog> createState() => _CreateStaffDialogState();
}

class _CreateStaffDialogState extends State<_CreateStaffDialog> {
  final _formKey = GlobalKey<FormState>();
  final _displayNameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void dispose() {
    _displayNameController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Create staff for ${widget.businessName}'),
      content: SizedBox(
        width: 440,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _displayNameController,
                decoration: const InputDecoration(
                  labelText: 'Display name',
                  hintText: 'Nadia Rasulova',
                ),
                validator: _required,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _usernameController,
                decoration: const InputDecoration(
                  labelText: 'Username',
                  hintText: 'nadia.silkroad',
                ),
                validator: _required,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _passwordController,
                decoration: const InputDecoration(
                  labelText: 'Temporary password',
                ),
                obscureText: true,
                validator: (value) {
                  if (value == null || value.trim().length < 8) {
                    return 'Use at least 8 characters.';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (!_formKey.currentState!.validate()) {
              return;
            }

            Navigator.of(context).pop(
              _CreateStaffPayload(
                displayName: _displayNameController.text.trim(),
                username: _usernameController.text.trim(),
                password: _passwordController.text,
              ),
            );
          },
          child: const Text('Create'),
        ),
      ],
    );
  }

  String? _required(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'This field is required.';
    }
    return null;
  }
}

class _ResetStaffPasswordDialog extends StatefulWidget {
  const _ResetStaffPasswordDialog({required this.staff});

  final StaffMemberSummary staff;

  @override
  State<_ResetStaffPasswordDialog> createState() =>
      _ResetStaffPasswordDialogState();
}

class _ResetStaffPasswordDialogState extends State<_ResetStaffPasswordDialog> {
  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Reset password for ${widget.staff.name}'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '@${widget.staff.username} · ${widget.staff.businessName}',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const ValueKey('owner-staff-reset-password-input'),
                controller: _passwordController,
                decoration: const InputDecoration(
                  labelText: 'New temporary password',
                  hintText: 'Teamcash!2026',
                ),
                obscureText: true,
                validator: (value) {
                  if (value == null || value.trim().length < 8) {
                    return 'Use at least 8 characters.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              Text(
                'Firebase Auth updates immediately. Share the new temporary password through a trusted channel.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('owner-staff-reset-submit'),
          onPressed: () {
            if (!_formKey.currentState!.validate()) {
              return;
            }

            Navigator.of(context).pop(
              _ResetStaffPasswordPayload(password: _passwordController.text),
            );
          },
          child: const Text('Update password'),
        ),
      ],
    );
  }
}

class _EditStaffDialog extends StatefulWidget {
  const _EditStaffDialog({required this.staff});

  final StaffMemberSummary staff;

  @override
  State<_EditStaffDialog> createState() => _EditStaffDialogState();
}

class _EditStaffDialogState extends State<_EditStaffDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _displayNameController;

  @override
  void initState() {
    super.initState();
    _displayNameController = TextEditingController(text: widget.staff.name);
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Edit ${widget.staff.username}'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Assigned to ${widget.staff.businessName}',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const ValueKey('owner-staff-edit-display-name-input'),
                controller: _displayNameController,
                decoration: const InputDecoration(
                  labelText: 'Display name',
                  hintText: 'Nadia Rasulova',
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Display name is required.';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('owner-staff-edit-submit'),
          onPressed: () {
            if (!_formKey.currentState!.validate()) {
              return;
            }

            Navigator.of(context).pop(
              _EditStaffPayload(
                displayName: _displayNameController.text.trim(),
              ),
            );
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
