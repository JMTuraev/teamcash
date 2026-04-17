part of 'staff_shell.dart';

class _StaffMobileHeader extends StatelessWidget {
  const _StaffMobileHeader({
    required this.staffName,
    required this.businessName,
    required this.unreadNotificationsCount,
    required this.onOpenNotifications,
    required this.onSignOut,
  });

  final String staffName;
  final String businessName;
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
          child: const Icon(Icons.badge_outlined, color: Color(0xFF6678FF)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Staff workspace',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              Text(staffName, style: theme.textTheme.titleLarge),
              Text(
                businessName,
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

class _StaffMobileSummaryCard extends StatelessWidget {
  const _StaffMobileSummaryCard({
    required this.workspace,
    required this.canRunLedgerActions,
    required this.actionInProgress,
    required this.onOpenScan,
  });

  final StaffWorkspace workspace;
  final bool canRunLedgerActions;
  final bool actionInProgress;
  final VoidCallback onOpenScan;

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
            Text(
              'Today at ${workspace.businessName}',
              style: theme.textTheme.bodySmall?.copyWith(color: Colors.white70),
            ),
            const SizedBox(height: 4),
            Text(
              '${formatPercent(workspace.cashbackBasisPoints)} cashback basis',
              style: theme.textTheme.headlineSmall?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _StaffMobilePill(
                  icon: Icons.groups_outlined,
                  label: workspace.groupId,
                ),
                _StaffMobilePill(
                  icon: Icons.receipt_long_outlined,
                  label: '${workspace.recentTransactions.length} recent ops',
                ),
                _StaffMobilePill(
                  icon: Icons.share_outlined,
                  label:
                      '${workspace.activeSharedCheckouts.length} shared checkouts',
                ),
              ],
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: canRunLedgerActions && !actionInProgress
                  ? onOpenScan
                  : null,
              icon: const Icon(Icons.qr_code_scanner_rounded),
              label: const Text('Open operator actions'),
            ),
          ],
        ),
      ),
    );
  }
}

class _StaffMobileDashboardPanel extends StatelessWidget {
  const _StaffMobileDashboardPanel({
    required this.workspace,
    required this.canRunLedgerActions,
    required this.onOpenIssueAction,
    required this.onOpenRedeemAction,
    required this.onOpenSharedCheckoutAction,
    required this.onFinalizeSharedCheckout,
  });

  final StaffWorkspace workspace;
  final bool canRunLedgerActions;
  final VoidCallback onOpenIssueAction;
  final VoidCallback onOpenRedeemAction;
  final VoidCallback onOpenSharedCheckoutAction;
  final Future<void> Function(String checkoutId) onFinalizeSharedCheckout;

  @override
  Widget build(BuildContext context) {
    final latestTrend = workspace.trendPoints.isEmpty
        ? null
        : workspace.trendPoints.last;
    final latestCheckout = workspace.activeSharedCheckouts.isEmpty
        ? null
        : workspace.activeSharedCheckouts.first;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE4E8F7)),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            key: const ValueKey('staff-quick-actions-section'),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: canRunLedgerActions ? onOpenIssueAction : null,
                    child: const Text('Issue'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: canRunLedgerActions ? onOpenRedeemAction : null,
                    child: const Text('Redeem'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: canRunLedgerActions
                        ? onOpenSharedCheckoutAction
                        : null,
                    child: const Text('Shared'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Container(
            key: const ValueKey('staff-trend-section'),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF4F6FF),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      latestTrend == null
                          ? 'Awaiting live data'
                          : '${latestTrend.label} • ${formatCurrency(latestTrend.salesMinorUnits)} sales',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                  if (latestCheckout != null)
                    TextButton(
                      onPressed: () =>
                          onFinalizeSharedCheckout(latestCheckout.id),
                      child: const Text('Finalize'),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StaffMobileScanPanel extends StatelessWidget {
  const _StaffMobileScanPanel({
    required this.workspace,
    required this.identifierController,
    required this.phoneController,
    required this.amountController,
    required this.ticketRefController,
    required this.resolvedCustomerIdentifier,
    required this.canRunLedgerActions,
    required this.actionInProgress,
    required this.onResolveIdentifier,
    required this.onClearResolvedIdentifier,
    required this.onIssueCashback,
    required this.onRedeemCashback,
    required this.onManageSharedCheckout,
  });

  final StaffWorkspace workspace;
  final TextEditingController identifierController;
  final TextEditingController phoneController;
  final TextEditingController amountController;
  final TextEditingController ticketRefController;
  final ResolvedCustomerIdentifier? resolvedCustomerIdentifier;
  final bool canRunLedgerActions;
  final bool actionInProgress;
  final VoidCallback? onResolveIdentifier;
  final VoidCallback onClearResolvedIdentifier;
  final VoidCallback? onIssueCashback;
  final VoidCallback? onRedeemCashback;
  final VoidCallback? onManageSharedCheckout;

  @override
  Widget build(BuildContext context) {
    final resolved = resolvedCustomerIdentifier;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE4E8F7)),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            key: const ValueKey('staff-customer-identifier-input'),
            controller: identifierController,
            decoration: const InputDecoration(
              labelText: 'Client QR payload or phone',
              hintText: 'teamcash://customer/... or +998901234567',
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  key: const ValueKey('staff-customer-identifier-resolve'),
                  onPressed: !actionInProgress ? onResolveIdentifier : null,
                  child: const Text('Resolve'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: !actionInProgress
                      ? onClearResolvedIdentifier
                      : null,
                  child: const Text('Clear'),
                ),
              ),
            ],
          ),
          if (resolved != null) ...[
            const SizedBox(height: 8),
            _StaffResolvedCustomerBanner(resolved: resolved),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton(
                onPressed: canRunLedgerActions && !actionInProgress
                    ? onIssueCashback
                    : null,
                child: const Text('Issue'),
              ),
              OutlinedButton(
                onPressed: canRunLedgerActions && !actionInProgress
                    ? onRedeemCashback
                    : null,
                child: const Text('Redeem'),
              ),
              OutlinedButton(
                onPressed: canRunLedgerActions && !actionInProgress
                    ? onManageSharedCheckout
                    : null,
                child: const Text('Shared'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StaffMobileProfilePanel extends StatelessWidget {
  const _StaffMobileProfilePanel({
    required this.workspace,
    required this.canEditProfile,
    required this.onEditProfile,
  });

  final StaffWorkspace workspace;
  final bool canEditProfile;
  final VoidCallback? onEditProfile;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      key: const ValueKey('staff-profile-section'),
      title: workspace.staffName,
      subtitle: workspace.businessName,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _StaffMobileSectionBlock(
            title: 'Access',
            description: 'Single business only',
            chips: [
              formatPercent(workspace.cashbackBasisPoints),
              workspace.notificationDigestOptIn ? 'Digest on' : 'Digest off',
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              key: const ValueKey('staff-profile-edit-action'),
              onPressed: canEditProfile ? onEditProfile : null,
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Edit profile'),
            ),
          ),
        ],
      ),
    );
  }
}

class _StaffResolvedCustomerBanner extends StatelessWidget {
  const _StaffResolvedCustomerBanner({required this.resolved});

  final ResolvedCustomerIdentifier resolved;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFE9FBF6),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          const Icon(Icons.verified_user_outlined, color: Color(0xFF0E9F6E)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  resolved.displayName ?? 'Resolved customer',
                  style: theme.textTheme.titleSmall,
                ),
                Text(
                  '${resolved.phoneE164} • ${resolved.cameFromQr ? 'QR' : 'Phone'}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StaffMobileSectionBlock extends StatelessWidget {
  const _StaffMobileSectionBlock({
    required this.title,
    required this.description,
    required this.chips,
  });

  final String title;
  final String description;
  final List<String> chips;

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
        ],
      ),
    );
  }
}

class _StaffMobilePill extends StatelessWidget {
  const _StaffMobilePill({required this.icon, required this.label});

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
IconData _staffMetricIcon(MetricTrendDirection direction) {
  switch (direction) {
    case MetricTrendDirection.up:
      return Icons.trending_up_rounded;
    case MetricTrendDirection.down:
      return Icons.trending_down_rounded;
    case MetricTrendDirection.neutral:
      return Icons.show_chart_rounded;
  }
}
