part of 'owner_shell.dart';

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
