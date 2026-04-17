part of 'owner_shell.dart';

class _OwnerMobileHeader extends StatelessWidget {
  const _OwnerMobileHeader({
    required this.ownerName,
    required this.activeBusinessName,
    required this.unreadNotificationsCount,
    required this.onOpenNotifications,
    required this.onSignOut,
  });

  final String ownerName;
  final String activeBusinessName;
  final int unreadNotificationsCount;
  final VoidCallback onOpenNotifications;
  final VoidCallback? onSignOut;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: const Color(0xFF6678FF).withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Icon(Icons.storefront_rounded, color: Color(0xFF6678FF)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Owner workspace',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              Text(ownerName, style: theme.textTheme.titleLarge),
              Text(
                activeBusinessName,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        SurfaceIconButton(
          icon: Icons.notifications_none_rounded,
          tooltip: unreadNotificationsCount > 0
              ? '$unreadNotificationsCount unread notifications'
              : 'Notifications',
          hasDot: unreadNotificationsCount > 0,
          onPressed: onOpenNotifications,
        ),
        if (onSignOut case final signOut) ...[
          const SizedBox(width: 8),
          SurfaceIconButton(
            icon: Icons.logout_rounded,
            tooltip: 'Sign out',
            onPressed: signOut,
          ),
        ],
      ],
    );
  }
}

class _OwnerMobileSummaryCard extends StatelessWidget {
  const _OwnerMobileSummaryCard({
    required this.ownerName,
    required this.activeBusiness,
    required this.businesses,
    required this.actionInProgress,
    required this.canManageOwnerActions,
    required this.onSwitchBusiness,
    required this.onEditBusiness,
    required this.onCreateBusiness,
  });

  final String ownerName;
  final BusinessSummary activeBusiness;
  final List<BusinessSummary> businesses;
  final bool actionInProgress;
  final bool canManageOwnerActions;
  final ValueChanged<String> onSwitchBusiness;
  final VoidCallback? onEditBusiness;
  final VoidCallback? onCreateBusiness;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF6678FF), Color(0xFF725CFF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: const [
          BoxShadow(
            color: Color(0x336678FF),
            blurRadius: 28,
            offset: Offset(0, 16),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
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
                        'Active business',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.white70,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        activeBusiness.name,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$ownerName • ${activeBusiness.groupName}',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: Colors.white70,
                        ),
                      ),
                    ],
                  ),
                ),
                if (businesses.length > 1)
                  PopupMenuButton<String>(
                    tooltip: 'Switch business',
                    onSelected: onSwitchBusiness,
                    itemBuilder: (context) => businesses
                        .map(
                          (business) => PopupMenuItem<String>(
                            value: business.id,
                            child: Text(business.name),
                          ),
                        )
                        .toList(),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        Icons.swap_horiz_rounded,
                        color: Colors.white,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _OwnerMobilePill(
                  icon: Icons.percent_rounded,
                  label:
                      '${formatPercent(activeBusiness.cashbackBasisPoints)} cashback',
                ),
                _OwnerMobilePill(
                  icon: Icons.pin_drop_outlined,
                  label: '${activeBusiness.locationsCount} locations',
                ),
                _OwnerMobilePill(
                  icon: Icons.shopping_bag_outlined,
                  label: '${activeBusiness.productsCount} products',
                ),
              ],
            ),
            if (canManageOwnerActions) ...[
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: actionInProgress ? null : onEditBusiness,
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('Edit'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: actionInProgress ? null : onCreateBusiness,
                      icon: const Icon(Icons.add_business_outlined),
                      label: const Text('New'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white54),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _OwnerMobileBusinessesPanel extends StatelessWidget {
  const _OwnerMobileBusinessesPanel({
    required this.businesses,
    required this.activeBusiness,
    required this.canManageBusinesses,
    required this.actionInProgress,
    required this.onEditBusiness,
    required this.onEditBranding,
  });

  final List<BusinessSummary> businesses;
  final BusinessSummary activeBusiness;
  final bool canManageBusinesses;
  final bool actionInProgress;
  final VoidCallback? onEditBusiness;
  final VoidCallback? onEditBranding;

  @override
  Widget build(BuildContext context) {
    final phoneLabel = activeBusiness.phoneNumbers.isEmpty
        ? 'Phone missing'
        : activeBusiness.phoneNumbers.first;
    final logoReady =
        activeBusiness.logoUrl.isNotEmpty ||
        activeBusiness.logoStoragePath.isNotEmpty;
    final coverReady =
        activeBusiness.coverImageUrl.isNotEmpty ||
        activeBusiness.coverImageStoragePath.isNotEmpty;

    return SectionCard(
      title: 'Business setup',
      padding: const EdgeInsets.all(14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _OwnerMobileSectionBlock(
            key: const ValueKey('owner-live-catalog-section'),
            title: 'Live catalog',
            description:
                '${activeBusiness.locationsCount} loc • ${activeBusiness.productsCount} prod • ${activeBusiness.manualPhoneIssuingEnabled ? 'phone' : 'QR'}',
            chips: [activeBusiness.category, phoneLabel],
            actionLabel: canManageBusinesses ? 'Edit' : null,
            onAction: actionInProgress ? null : onEditBusiness,
          ),
          const SizedBox(height: 8),
          _OwnerMobileSectionBlock(
            key: const ValueKey('owner-branding-section'),
            title: 'Branding',
            description: logoReady && coverReady
                ? 'Logo and cover ready'
                : 'Finish brand assets',
            chips: [activeBusiness.groupName],
            actionLabel: canManageBusinesses ? 'Open' : null,
            onAction: actionInProgress ? null : onEditBranding,
          ),
        ],
      ),
    );
  }
}

class _OwnerMobileDashboardPanel extends StatelessWidget {
  const _OwnerMobileDashboardPanel({
    required this.metrics,
    required this.trendPoints,
    required this.businessPerformance,
    required this.activeBusiness,
    required this.canManageLedger,
    required this.actionInProgress,
    required this.onAdminAdjustCashback,
    required this.onRefundCashback,
  });

  final List<DashboardMetric> metrics;
  final List<DashboardTrendPoint> trendPoints;
  final List<BusinessPerformanceSnapshot> businessPerformance;
  final BusinessSummary activeBusiness;
  final bool canManageLedger;
  final bool actionInProgress;
  final VoidCallback? onAdminAdjustCashback;
  final VoidCallback? onRefundCashback;

  @override
  Widget build(BuildContext context) {
    final trendPoint = trendPoints.isEmpty ? null : trendPoints.last;
    final performance = _matchingPerformanceSnapshot(
      activeBusiness.id,
      businessPerformance,
    );

    return SectionCard(
      title: 'Owner dashboard',
      padding: const EdgeInsets.all(14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _OwnerMobileSectionBlock(
            key: const ValueKey('owner-dashboard-trend-section'),
            title: 'Trend',
            description: trendPoint == null
                ? 'Awaiting live data'
                : '${trendPoint.label} • ${formatCurrency(trendPoint.salesMinorUnits)} sales',
            chips: [
              trendPoint == null
                  ? 'No trend'
                  : '${trendPoint.lookupsCount} lookups',
            ],
          ),
          const SizedBox(height: 8),
          _OwnerMobileSectionBlock(
            key: const ValueKey('owner-business-performance-section'),
            title: 'Performance',
            description: performance == null
                ? 'Awaiting analytics'
                : '${performance.businessName} • ${formatCurrency(performance.todaySalesMinorUnits)} today',
            chips: [
              performance == null
                  ? activeBusiness.name
                  : '${performance.todayClientsCount} clients',
            ],
            actionLabel: canManageLedger ? 'Adjust' : null,
            onAction: actionInProgress ? null : onAdminAdjustCashback,
            secondaryLabel: canManageLedger ? 'Refund' : null,
            onSecondaryAction: actionInProgress ? null : onRefundCashback,
          ),
        ],
      ),
    );
  }
}

class _OwnerMobileStaffPanel extends StatelessWidget {
  const _OwnerMobileStaffPanel({
    required this.activeBusiness,
    required this.staffMembers,
    required this.joinRequests,
    required this.groupAuditEvents,
    required this.canManageStaff,
    required this.actionInProgress,
    required this.onCreateStaff,
    required this.onEditStaff,
    required this.onResetStaffPassword,
    required this.onVoteOnJoinRequest,
  });

  final BusinessSummary activeBusiness;
  final List<StaffMemberSummary> staffMembers;
  final List<GroupJoinRequestSummary> joinRequests;
  final List<GroupAuditEventSummary> groupAuditEvents;
  final bool canManageStaff;
  final bool actionInProgress;
  final VoidCallback? onCreateStaff;
  final Future<void> Function(StaffMemberSummary staff)? onEditStaff;
  final Future<void> Function(StaffMemberSummary staff)? onResetStaffPassword;
  final Future<void> Function(GroupJoinRequestSummary request)?
  onVoteOnJoinRequest;

  @override
  Widget build(BuildContext context) {
    final businessStaff = staffMembers
        .where((staff) => staff.businessName == activeBusiness.name)
        .toList();
    final request = _matchingJoinRequest(activeBusiness, joinRequests);
    final audit = _matchingAuditEvent(activeBusiness, groupAuditEvents);

    return SectionCard(
      title: 'Staff and approvals',
      padding: const EdgeInsets.all(14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _OwnerMobileSectionBlock(
            title: 'Team',
            description: businessStaff.isEmpty
                ? 'No staff yet'
                : '${businessStaff.first.name} • ${businessStaff.first.roleLabel}',
            chips: ['${businessStaff.length} staff'],
            actionLabel: canManageStaff ? 'Add' : null,
            onAction: actionInProgress ? null : onCreateStaff,
          ),
          const SizedBox(height: 8),
          _OwnerMobileSectionBlock(
            key: const ValueKey('owner-group-audit-section'),
            title: 'Audit',
            description: audit == null ? 'No audit yet' : audit.title,
            chips: [request == null ? 'No request' : request.status],
            actionLabel: canManageStaff && request != null
                ? 'Review request'
                : null,
            onAction:
                canManageStaff &&
                    !actionInProgress &&
                    request != null &&
                    onVoteOnJoinRequest != null
                ? () => onVoteOnJoinRequest!(request)
                : null,
          ),
        ],
      ),
    );
  }
}

class _OwnerMobileSectionBlock extends StatelessWidget {
  const _OwnerMobileSectionBlock({
    super.key,
    required this.title,
    required this.description,
    required this.chips,
    this.actionLabel,
    this.onAction,
    this.secondaryLabel,
    this.onSecondaryAction,
  });

  final String title;
  final String description;
  final List<String> chips;
  final String? actionLabel;
  final VoidCallback? onAction;
  final String? secondaryLabel;
  final VoidCallback? onSecondaryAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.42,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title, style: theme.textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(description, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: chips
                .where((chip) => chip.trim().isNotEmpty)
                .map(
                  (chip) => Chip(
                    label: Text(chip),
                    visualDensity: VisualDensity.compact,
                  ),
                )
                .toList(),
          ),
          if (actionLabel != null || secondaryLabel != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                if (actionLabel != null)
                  Expanded(
                    child: FilledButton(
                      onPressed: onAction,
                      child: Text(actionLabel!),
                    ),
                  ),
                if (actionLabel != null && secondaryLabel != null)
                  const SizedBox(width: 10),
                if (secondaryLabel != null)
                  Expanded(
                    child: OutlinedButton(
                      onPressed: onSecondaryAction,
                      child: Text(secondaryLabel!),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _OwnerMobilePill extends StatelessWidget {
  const _OwnerMobilePill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: Colors.white),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(color: Colors.white),
          ),
        ],
      ),
    );
  }
}

// ignore: unused_element
String _ownerGroupStatusLabel(GroupMembershipStatus status) {
  switch (status) {
    case GroupMembershipStatus.active:
      return 'Active';
    case GroupMembershipStatus.pendingApproval:
      return 'Pending';
    case GroupMembershipStatus.rejected:
      return 'Rejected';
    case GroupMembershipStatus.notGrouped:
      return 'Solo';
  }
}

// ignore: unused_element
IconData _ownerMetricIcon(MetricTrendDirection direction) {
  switch (direction) {
    case MetricTrendDirection.up:
      return Icons.trending_up_rounded;
    case MetricTrendDirection.down:
      return Icons.trending_down_rounded;
    case MetricTrendDirection.neutral:
      return Icons.show_chart_rounded;
  }
}

BusinessPerformanceSnapshot? _matchingPerformanceSnapshot(
  String businessId,
  List<BusinessPerformanceSnapshot> snapshots,
) {
  for (final snapshot in snapshots) {
    if (snapshot.businessId == businessId) {
      return snapshot;
    }
  }
  return snapshots.isEmpty ? null : snapshots.first;
}

GroupJoinRequestSummary? _matchingJoinRequest(
  BusinessSummary business,
  List<GroupJoinRequestSummary> requests,
) {
  for (final request in requests) {
    if (request.businessId == business.id ||
        request.groupId == business.groupId) {
      return request;
    }
  }
  return null;
}

GroupAuditEventSummary? _matchingAuditEvent(
  BusinessSummary business,
  List<GroupAuditEventSummary> events,
) {
  for (final event in events) {
    if (event.businessId == business.id || event.groupId == business.groupId) {
      return event;
    }
  }
  return null;
}
