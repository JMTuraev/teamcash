part of 'staff_shell.dart';

class _StaffDashboardTab extends StatelessWidget {
  const _StaffDashboardTab({
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
    return Column(
      key: const ValueKey('staff-dashboard-section'),
      children: [
        SectionCard(
          title: 'Today',
          subtitle:
              'Operator actions are intended to call backend ledger functions, not mutate balances directly from the client.',
          child: MetricGrid(metrics: workspace.dashboardMetrics),
        ),
        const SizedBox(height: 16),
        SectionCard(
          key: const ValueKey('staff-quick-actions-section'),
          title: 'Quick actions',
          subtitle:
              'Dashboard shortcuts jump straight into the live operator flow without leaving the staff workspace.',
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.icon(
                key: const ValueKey('staff-quick-issue-action'),
                onPressed: onOpenIssueAction,
                icon: const Icon(Icons.add_card_outlined),
                label: const Text('Issue cashback'),
              ),
              OutlinedButton.icon(
                key: const ValueKey('staff-quick-redeem-action'),
                onPressed: onOpenRedeemAction,
                icon: const Icon(Icons.payments_outlined),
                label: const Text('Redeem cashback'),
              ),
              OutlinedButton.icon(
                key: const ValueKey('staff-quick-shared-checkout-action'),
                onPressed: onOpenSharedCheckoutAction,
                icon: const Icon(Icons.groups_2_outlined),
                label: const Text('Shared checkout'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SectionCard(
          key: const ValueKey('staff-trend-section'),
          title: '7 day operating trend',
          subtitle:
              'Daily stats come from the same server-authoritative ledger events used for issue and redeem.',
          child: workspace.trendPoints.isEmpty
              ? const Text(
                  'Trend data will appear after live operator activity.',
                )
              : Column(
                  children: workspace.trendPoints
                      .map(
                        (point) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _StaffTrendRow(point: point),
                        ),
                      )
                      .toList(),
                ),
        ),
        const SizedBox(height: 16),
        SectionCard(
          key: const ValueKey('staff-shared-checkouts-section'),
          title: 'Active shared checkouts',
          subtitle:
              'Open sessions stay group-bound and can be finalized directly from the operator surface once contributions are ready.',
          child: workspace.activeSharedCheckouts.isEmpty
              ? const Text('No active shared checkouts yet.')
              : Column(
                  children: workspace.activeSharedCheckouts
                      .map<Widget>(
                        (checkout) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _StaffSharedCheckoutTile(
                            checkout: checkout,
                            canFinalize: canRunLedgerActions,
                            onFinalize: () =>
                                onFinalizeSharedCheckout(checkout.id),
                          ),
                        ),
                      )
                      .toList(),
                ),
        ),
        const SizedBox(height: 16),
        SectionCard(
          title: 'Recent transactions',
          child: Column(
            children: workspace.recentTransactions
                .map<Widget>(
                  (event) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      backgroundColor: event.isIncoming
                          ? const Color(0xFFE7F5EF)
                          : const Color(0xFFFFF2D8),
                      child: Icon(
                        event.isIncoming
                            ? Icons.call_received_outlined
                            : Icons.call_made_outlined,
                        color: event.isIncoming
                            ? const Color(0xFF1B7F5B)
                            : const Color(0xFF9C6100),
                      ),
                    ),
                    title: Text(event.title),
                    subtitle: Text(
                      '${event.subtitle}\n${formatDateTime(event.occurredAt)}',
                    ),
                    trailing: Text(
                      formatCurrency(event.amount),
                      style: Theme.of(context).textTheme.titleMedium,
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

class _StaffTrendRow extends StatelessWidget {
  const _StaffTrendRow({required this.point});

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

class _StaffSharedCheckoutTile extends StatelessWidget {
  const _StaffSharedCheckoutTile({
    required this.checkout,
    required this.canFinalize,
    required this.onFinalize,
  });

  final StaffSharedCheckoutSummary checkout;
  final bool canFinalize;
  final Future<void> Function() onFinalize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isShortfall = checkout.status == 'open_shortfall';

    return Container(
      key: ValueKey('staff-shared-checkout-${checkout.id}'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF7FBF9),
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
                      'Ticket ${checkout.sourceTicketRef}',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Checkout id ${checkout.id}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: const Color(0xFF52606D),
                      ),
                    ),
                  ],
                ),
              ),
              _StatusChip(
                label: isShortfall ? 'Shortfall' : 'Open',
                color: isShortfall
                    ? const Color(0xFFFFF2D8)
                    : const Color(0xFFE7F5EF),
                foregroundColor: isShortfall
                    ? const Color(0xFF9C6100)
                    : const Color(0xFF1B7F5B),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _MetricPill(
                label: 'Total',
                value: formatCurrency(checkout.totalMinorUnits),
              ),
              _MetricPill(
                label: 'Contributed',
                value: formatCurrency(checkout.contributedMinorUnits),
              ),
              _MetricPill(
                label: 'Remaining',
                value: formatCurrency(checkout.remainingMinorUnits),
              ),
              _MetricPill(
                label: 'Contributors',
                value: checkout.contributionsCount.toString(),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Opened ${formatDateTime(checkout.createdAt)}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: const Color(0xFF52606D),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              OutlinedButton.icon(
                key: ValueKey('staff-shared-checkout-copy-${checkout.id}'),
                onPressed: () =>
                    Clipboard.setData(ClipboardData(text: checkout.id)),
                icon: const Icon(Icons.copy_outlined),
                label: const Text('Copy id'),
              ),
              FilledButton.tonalIcon(
                key: ValueKey('staff-shared-checkout-finalize-${checkout.id}'),
                onPressed: canFinalize ? () => onFinalize() : null,
                icon: const Icon(Icons.check_circle_outline),
                label: const Text('Finalize'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MetricPill extends StatelessWidget {
  const _MetricPill({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8E4)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: const Color(0xFF52606D)),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.label,
    required this.color,
    required this.foregroundColor,
  });

  final String label;
  final Color color;
  final Color foregroundColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: foregroundColor,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
