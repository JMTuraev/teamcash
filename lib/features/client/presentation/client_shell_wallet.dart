part of 'client_shell.dart';

class _WalletTab extends ConsumerWidget {
  const _WalletTab({
    required this.client,
    required this.canRunLiveTransferActions,
    required this.hasVerifiedPhoneClaimActions,
    required this.customerId,
  });

  final ClientWorkspace client;
  final bool canRunLiveTransferActions;
  final bool hasVerifiedPhoneClaimActions;
  final String? customerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final transferState = ref.watch(clientTransferControllerProvider);
    final availableGroups = _buildAvailableGroups(client.walletLots);
    final groupBalances = _buildGroupBalances(client.walletLots);
    final expiringLots = _buildExpiringLots(client.walletLots);
    final spendableLots = client.walletLots.toList()
      ..sort(
        (left, right) => right.availableAmount.compareTo(left.availableAmount),
      );
    final outgoingTransfers = client.pendingTransfers
        .where(
          (transfer) => transfer.direction == PendingTransferDirection.outgoing,
        )
        .toList();
    final incomingTransfers = client.pendingTransfers
        .where(
          (transfer) => transfer.direction == PendingTransferDirection.incoming,
        )
        .toList();
    final featuredLot = spendableLots.isEmpty ? null : spendableLots.first;
    final highlightedCheckout = client.activeSharedCheckouts.isEmpty
        ? null
        : client.activeSharedCheckouts.first;

    if (MediaQuery.sizeOf(context).height > 0) {
      return SizedBox.expand(
        key: const ValueKey('client-wallet-tab'),
        child: SectionCard(
          title: 'Wallet',
          subtitle:
              'Critical UX fix: one screen now holds only the next decision, not the whole ledger stack.',
          padding: const EdgeInsets.all(18),
          child: DefaultTabController(
            length: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF2F5FF),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: const TabBar(
                    dividerColor: Colors.transparent,
                    indicatorSize: TabBarIndicatorSize.tab,
                    labelColor: Color(0xFF4A57A9),
                    unselectedLabelColor: Color(0xFF8A92B3),
                    indicator: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.all(Radius.circular(14)),
                      boxShadow: [
                        BoxShadow(
                          color: Color(0x12414B98),
                          blurRadius: 18,
                          offset: Offset(0, 6),
                        ),
                      ],
                    ),
                    tabs: [
                      Tab(text: 'Overview'),
                      Tab(text: 'Actions'),
                      Tab(text: 'Pending'),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 338,
                  child: TabBarView(
                    physics: const NeverScrollableScrollPhysics(),
                    children: [
                      _WalletOverviewPanel(
                        totalBalance: client.totalWalletBalance,
                        groupBalances: groupBalances,
                        totalLotsCount: client.walletLots.length,
                        pendingTransfersCount: client.pendingTransfers.length,
                        featuredLot: featuredLot,
                        expiringLot: expiringLots.isEmpty
                            ? null
                            : expiringLots.first,
                        highlightedCheckout: highlightedCheckout,
                        buildExpiryCountdown: _buildExpiryCountdown,
                      ),
                      _WalletActionsPanel(
                        statusMessage: transferState.statusMessage,
                        isSubmitting: transferState.isSubmitting,
                        bannerMessage: _buildTransferBannerMessage(),
                        canRunLiveTransferActions: canRunLiveTransferActions,
                        hasVerifiedPhoneClaimActions:
                            hasVerifiedPhoneClaimActions,
                        availableGroups: availableGroups,
                        highlightedCheckout: highlightedCheckout,
                        onSendGift:
                            canRunLiveTransferActions &&
                                !transferState.isSubmitting &&
                                availableGroups.isNotEmpty &&
                                customerId != null
                            ? () => _openSendGiftDialog(
                                context,
                                ref,
                                customerId!,
                                availableGroups,
                              )
                            : null,
                        onClaimById:
                            canRunLiveTransferActions &&
                                hasVerifiedPhoneClaimActions &&
                                !transferState.isSubmitting
                            ? () => _openClaimGiftDialog(context, ref)
                            : null,
                        onJoinCheckout:
                            canRunLiveTransferActions &&
                                !transferState.isSubmitting &&
                                customerId != null
                            ? () => _openSharedCheckoutContributionDialog(
                                context,
                                ref,
                                customerId!,
                              )
                            : null,
                      ),
                      _WalletPendingPanel(
                        incomingTransfers: incomingTransfers,
                        outgoingTransfers: outgoingTransfers,
                        isSubmitting: transferState.isSubmitting,
                        canRunLiveTransferActions: canRunLiveTransferActions,
                        hasVerifiedPhoneClaimActions:
                            hasVerifiedPhoneClaimActions,
                        onClaimTransfer: (transferId) =>
                            _claimPendingTransfer(context, ref, transferId),
                        onCopyTransfer: (transferId) => _copyToClipboard(
                          context,
                          transferId,
                          'Transfer id copied.',
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Column(
      key: const ValueKey('client-wallet-tab'),
      children: [
        SectionCard(
          title: 'Wallet balance',
          subtitle:
              'Lots remain group-bound and issuer-preserving even after transfers and shared checkout contributions.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                formatCurrency(client.totalWalletBalance),
                style: Theme.of(context).textTheme.displaySmall,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: const [
                  Chip(label: Text('Transferable to same-group clients')),
                  Chip(label: Text('Issuer preserved after transfer')),
                  Chip(label: Text('Expiry preserved after transfer')),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SectionCard(
          key: const ValueKey('client-group-balances-section'),
          title: 'Group balances',
          subtitle:
              'Each tandem group keeps its own spend boundary. Balance here is derived from the live wallet lots already loaded from Firestore.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: groupBalances.isEmpty
                ? const [
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('No active group balances yet'),
                      subtitle: Text(
                        'Once cashback is issued, each group wallet will appear here separately.',
                      ),
                    ),
                  ]
                : groupBalances
                      .map<Widget>(
                        (groupBalance) => Container(
                          key: ValueKey(
                            'client-group-balance-${groupBalance.groupId}',
                          ),
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: const Color(0xFFE6DED1)),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      groupBalance.groupName,
                                      style: Theme.of(
                                        context,
                                      ).textTheme.titleMedium,
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      '${groupBalance.lotsCount} active lot${groupBalance.lotsCount == 1 ? '' : 's'} • ${groupBalance.earliestExpiry == null ? 'No expiry tracked yet' : 'Next expiry ${formatShortDate(groupBalance.earliestExpiry!)}'}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium
                                          ?.copyWith(
                                            color: const Color(0xFF52606D),
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 16),
                              Text(
                                formatCurrency(groupBalance.balanceAmount),
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                            ],
                          ),
                        ),
                      )
                      .toList(),
          ),
        ),
        const SizedBox(height: 16),
        SectionCard(
          key: const ValueKey('client-transfer-section'),
          title: 'Transfer / gift',
          subtitle:
              'Client-to-client cashback transfer stays inside the same tandem group. Original issuer and expiry remain preserved on every transferred lot.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InfoBanner(
                title: canRunLiveTransferActions
                    ? 'Live transfer actions enabled'
                    : 'Preview transfer surface',
                message: _buildTransferBannerMessage(),
                color: canRunLiveTransferActions
                    ? const Color(0xFFEFF4FF)
                    : const Color(0xFFFFF2D8),
              ),
              if (transferState.statusMessage case final statusText?) ...[
                const SizedBox(height: 12),
                InfoBanner(
                  title: 'Transfer status',
                  message: statusText,
                  color: const Color(0xFFE7F5EF),
                ),
              ],
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  FilledButton.icon(
                    key: const ValueKey('client-send-gift-action'),
                    onPressed:
                        canRunLiveTransferActions &&
                            !transferState.isSubmitting &&
                            availableGroups.isNotEmpty &&
                            customerId != null
                        ? () => _openSendGiftDialog(
                            context,
                            ref,
                            customerId!,
                            availableGroups,
                          )
                        : null,
                    icon: transferState.isSubmitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.redeem_outlined),
                    label: const Text('Send gift'),
                  ),
                  OutlinedButton.icon(
                    key: const ValueKey('client-claim-by-id-action'),
                    onPressed:
                        canRunLiveTransferActions &&
                            hasVerifiedPhoneClaimActions &&
                            !transferState.isSubmitting
                        ? () => _openClaimGiftDialog(context, ref)
                        : null,
                    icon: const Icon(Icons.card_giftcard_outlined),
                    label: const Text('Claim by transfer id'),
                  ),
                  OutlinedButton.icon(
                    key: const ValueKey('client-join-checkout-action'),
                    onPressed:
                        canRunLiveTransferActions &&
                            !transferState.isSubmitting &&
                            customerId != null
                        ? () => _openSharedCheckoutContributionDialog(
                            context,
                            ref,
                            customerId!,
                          )
                        : null,
                    icon: const Icon(Icons.groups_outlined),
                    label: const Text('Join shared checkout'),
                  ),
                ],
              ),
              if (availableGroups.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  'Eligible tandem groups: ${availableGroups.map((group) => group.groupName).join(', ')}',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF52606D),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        SectionCard(
          key: const ValueKey('client-wallet-lots-section'),
          title: 'Available lots',
          child: Column(
            children: client.walletLots
                .map<Widget>(
                  (lot) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(lot.issuerBusinessName),
                    subtitle: Text(
                      '${lot.groupName}\n${lot.currentOwnerLabel} • Expires ${formatShortDate(lot.expiresAt)}',
                    ),
                    trailing: Text(
                      formatCurrency(lot.availableAmount),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                )
                .toList(),
          ),
        ),
        const SizedBox(height: 16),
        SectionCard(
          key: const ValueKey('client-expiring-cashback-section'),
          title: 'Expiring cashback',
          subtitle:
              'These lots need attention soon. Expiry is preserved even after transfer, so the countdown always follows the original issue rules.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: expiringLots.isEmpty
                ? const [
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('Nothing is expiring soon'),
                      subtitle: Text(
                        'The wallet has no active lots expiring in the next 14 days.',
                      ),
                    ),
                  ]
                : expiringLots
                      .map<Widget>(
                        (lot) => ListTile(
                          key: ValueKey('client-expiring-lot-${lot.id}'),
                          contentPadding: EdgeInsets.zero,
                          title: Text(lot.issuerBusinessName),
                          subtitle: Text(
                            '${lot.groupName} • ${_buildExpiryCountdown(lot.expiresAt)} • Expires ${formatShortDate(lot.expiresAt)}',
                          ),
                          trailing: Text(
                            formatCurrency(lot.availableAmount),
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                      )
                      .toList(),
          ),
        ),
        const SizedBox(height: 16),
        SectionCard(
          key: const ValueKey('client-pending-transfers-section'),
          title: 'Pending transfer / gift',
          subtitle:
              'Outgoing gifts stay pending until claimed. Incoming gifts can be claimed only from a verified phone-auth client session.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: client.pendingTransfers.isEmpty
                ? const [
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('No pending gifts right now'),
                      subtitle: Text(
                        'New outgoing gifts will appear here until the recipient claims them.',
                      ),
                    ),
                  ]
                : [
                    if (incomingTransfers.isNotEmpty) ...[
                      Text(
                        'Incoming gifts',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 12),
                      ...incomingTransfers.map<Widget>(
                        (transfer) => Container(
                          key: ValueKey(
                            'client-pending-transfer-${transfer.id}',
                          ),
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: const Color(0xFFE6DED1)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      'Incoming gift for ${transfer.phoneNumber}',
                                      style: Theme.of(
                                        context,
                                      ).textTheme.titleMedium,
                                    ),
                                  ),
                                  Text(
                                    formatCurrency(transfer.amount),
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleMedium,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '${transfer.groupName} • ${transfer.statusLabel} • Expires ${formatShortDate(transfer.expiresAt)}',
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(color: const Color(0xFF52606D)),
                              ),
                              const SizedBox(height: 12),
                              Wrap(
                                spacing: 10,
                                runSpacing: 10,
                                children: [
                                  FilledButton.icon(
                                    key: ValueKey(
                                      'client-pending-transfer-claim-${transfer.id}',
                                    ),
                                    onPressed:
                                        canRunLiveTransferActions &&
                                            hasVerifiedPhoneClaimActions &&
                                            !transferState.isSubmitting &&
                                            transfer.canClaim
                                        ? () => _claimPendingTransfer(
                                            context,
                                            ref,
                                            transfer.id,
                                          )
                                        : null,
                                    icon: const Icon(
                                      Icons.card_giftcard_outlined,
                                    ),
                                    label: const Text('Claim gift'),
                                  ),
                                  OutlinedButton.icon(
                                    key: ValueKey(
                                      'client-pending-transfer-copy-${transfer.id}',
                                    ),
                                    onPressed: () => _copyToClipboard(
                                      context,
                                      transfer.id,
                                      'Transfer id copied.',
                                    ),
                                    icon: const Icon(Icons.copy_outlined),
                                    label: const Text('Copy id'),
                                  ),
                                ],
                              ),
                              if (!hasVerifiedPhoneClaimActions) ...[
                                const SizedBox(height: 10),
                                Text(
                                  'Claiming still requires a verified phone-auth client session.',
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: const Color(0xFF9C6100),
                                      ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ],
                    if (incomingTransfers.isNotEmpty &&
                        outgoingTransfers.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      const Divider(height: 1),
                      const SizedBox(height: 16),
                    ],
                    if (outgoingTransfers.isNotEmpty) ...[
                      Text(
                        'Outgoing gifts',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 12),
                      ...outgoingTransfers.map<Widget>(
                        (transfer) => Container(
                          key: ValueKey(
                            'client-pending-transfer-${transfer.id}',
                          ),
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: const Color(0xFFE6DED1)),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Gift to ${transfer.phoneNumber}',
                                      style: Theme.of(
                                        context,
                                      ).textTheme.titleMedium,
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      '${transfer.groupName} • ${transfer.statusLabel} • Expires ${formatShortDate(transfer.expiresAt)}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium
                                          ?.copyWith(
                                            color: const Color(0xFF52606D),
                                          ),
                                    ),
                                    const SizedBox(height: 12),
                                    OutlinedButton.icon(
                                      key: ValueKey(
                                        'client-pending-transfer-copy-${transfer.id}',
                                      ),
                                      onPressed: () => _copyToClipboard(
                                        context,
                                        transfer.id,
                                        'Transfer id copied.',
                                      ),
                                      icon: const Icon(Icons.copy_outlined),
                                      label: const Text('Copy id'),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 16),
                              Text(
                                formatCurrency(transfer.amount),
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
          ),
        ),
        const SizedBox(height: 16),
        SectionCard(
          key: const ValueKey('client-shared-checkouts-section'),
          title: 'Active shared checkouts',
          subtitle:
              'Shared checkout is separate from transfer. Each participant contribution is tracked individually.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: client.activeSharedCheckouts.isEmpty
                ? const [
                    Text(
                      'No open shared checkout is currently attached to this wallet.',
                    ),
                  ]
                : client.activeSharedCheckouts
                      .map<Widget>(
                        (checkout) => Container(
                          key: ValueKey(
                            'client-shared-checkout-${checkout.id}',
                          ),
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: const Color(0xFFE6DED1)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      checkout.businessName,
                                      style: Theme.of(
                                        context,
                                      ).textTheme.titleLarge,
                                    ),
                                  ),
                                  StatusPill(
                                    label: checkout.status == 'open_shortfall'
                                        ? 'Shortfall'
                                        : 'Open',
                                    backgroundColor:
                                        checkout.status == 'open_shortfall'
                                        ? const Color(0xFFFFF2D8)
                                        : const Color(0xFFE7F5EF),
                                    foregroundColor:
                                        checkout.status == 'open_shortfall'
                                        ? const Color(0xFF9C6100)
                                        : const Color(0xFF1B7F5B),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Text(
                                'Ticket ${checkout.sourceTicketRef} • Total ${formatCurrency(checkout.totalAmount)} • Remaining ${formatCurrency(checkout.remainingAmount)}',
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(color: const Color(0xFF52606D)),
                              ),
                              const SizedBox(height: 12),
                              Wrap(
                                spacing: 10,
                                runSpacing: 10,
                                children: [
                                  Chip(
                                    label: Text(
                                      'Contributed ${formatCurrency(checkout.contributedAmount)}',
                                    ),
                                  ),
                                  Chip(
                                    label: Text(
                                      'Opened ${formatShortDate(checkout.createdAt)}',
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              ...checkout.contributions.map<Widget>(
                                (contribution) => Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          contribution.participantName,
                                        ),
                                      ),
                                      Text(formatCurrency(contribution.amount)),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              Wrap(
                                spacing: 10,
                                runSpacing: 10,
                                children: [
                                  FilledButton.icon(
                                    key: ValueKey(
                                      'client-shared-checkout-contribute-${checkout.id}',
                                    ),
                                    onPressed:
                                        canRunLiveTransferActions &&
                                            !transferState.isSubmitting &&
                                            customerId != null &&
                                            checkout.remainingAmount > 0
                                        ? () =>
                                              _openSharedCheckoutContributionDialog(
                                                context,
                                                ref,
                                                customerId!,
                                                checkout: checkout,
                                              )
                                        : null,
                                    icon: const Icon(Icons.groups_outlined),
                                    label: const Text('Contribute'),
                                  ),
                                  OutlinedButton.icon(
                                    key: ValueKey(
                                      'client-shared-checkout-copy-${checkout.id}',
                                    ),
                                    onPressed: () => _copyToClipboard(
                                      context,
                                      checkout.id,
                                      'Checkout id copied.',
                                    ),
                                    icon: const Icon(Icons.copy_outlined),
                                    label: const Text('Copy id'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      )
                      .toList(),
          ),
        ),
      ],
    );
  }

  String _buildTransferBannerMessage() {
    if (!canRunLiveTransferActions) {
      return 'Gift actions become live after the client verifies a phone number and claims the existing wallet. The sections below still preview the intended UX.';
    }
    if (!hasVerifiedPhoneClaimActions) {
      return 'Wallet, history, pending gifts, and shared checkout load live from Firestore. Sending gifts and joining shared checkout are enabled, while claiming incoming gifts still requires a verified phone-auth session.';
    }
    return 'Wallet, history, pending gifts, and shared checkout now load from Firestore and call live backend functions.';
  }

  List<_WalletGroupOption> _buildAvailableGroups(List<WalletLot> lots) {
    final groupsById = <String, _WalletGroupOption>{};
    for (final lot in lots) {
      groupsById.putIfAbsent(
        lot.groupId,
        () =>
            _WalletGroupOption(groupId: lot.groupId, groupName: lot.groupName),
      );
    }

    return groupsById.values.toList();
  }

  List<_GroupBalanceViewData> _buildGroupBalances(List<WalletLot> lots) {
    final balancesById = <String, _GroupBalanceViewData>{};
    for (final lot in lots) {
      final current = balancesById[lot.groupId];
      if (current == null) {
        balancesById[lot.groupId] = _GroupBalanceViewData(
          groupId: lot.groupId,
          groupName: lot.groupName,
          balanceAmount: lot.availableAmount,
          lotsCount: 1,
          earliestExpiry: lot.expiresAt,
        );
        continue;
      }

      balancesById[lot.groupId] = _GroupBalanceViewData(
        groupId: current.groupId,
        groupName: current.groupName,
        balanceAmount: current.balanceAmount + lot.availableAmount,
        lotsCount: current.lotsCount + 1,
        earliestExpiry:
            current.earliestExpiry == null ||
                lot.expiresAt.isBefore(current.earliestExpiry!)
            ? lot.expiresAt
            : current.earliestExpiry,
      );
    }

    final result = balancesById.values.toList()
      ..sort(
        (left, right) => right.balanceAmount.compareTo(left.balanceAmount),
      );
    return result;
  }

  List<WalletLot> _buildExpiringLots(List<WalletLot> lots) {
    final now = DateTime.now();
    final threshold = now.add(const Duration(days: 14));
    final result =
        lots
            .where(
              (lot) =>
                  !lot.expiresAt.isBefore(now) &&
                  !lot.expiresAt.isAfter(threshold),
            )
            .toList()
          ..sort((left, right) => left.expiresAt.compareTo(right.expiresAt));
    return result.take(6).toList();
  }

  String _buildExpiryCountdown(DateTime expiresAt) {
    final remaining = expiresAt.difference(DateTime.now());
    if (remaining.inDays <= 0) {
      return 'Expires today';
    }
    if (remaining.inDays == 1) {
      return '1 day left';
    }
    return '${remaining.inDays} days left';
  }

  Future<void> _openSendGiftDialog(
    BuildContext context,
    WidgetRef ref,
    String customerId,
    List<_WalletGroupOption> availableGroups,
  ) async {
    final payload = await showDialog<_SendGiftPayload>(
      context: context,
      builder: (context) => _SendGiftDialog(availableGroups: availableGroups),
    );

    if (payload == null) {
      return;
    }

    try {
      final result = await ref
          .read(clientTransferControllerProvider.notifier)
          .createGiftTransfer(
            sourceCustomerId: customerId,
            recipientPhoneE164: payload.recipientPhoneE164,
            groupId: payload.groupId,
            amountMinorUnits: payload.amountMinorUnits,
          );

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Gift created for ${result.recipientPhoneE164}. Transfer id: ${result.transferId}.',
          ),
        ),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _openClaimGiftDialog(BuildContext context, WidgetRef ref) async {
    final transferId = await showDialog<String>(
      context: context,
      builder: (context) => const _ClaimGiftDialog(),
    );

    if (transferId == null) {
      return;
    }

    try {
      final result = await ref
          .read(clientTransferControllerProvider.notifier)
          .claimGiftTransfer(transferId: transferId);

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Transfer ${result.transferId} processed with status ${result.status}.',
          ),
        ),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _claimPendingTransfer(
    BuildContext context,
    WidgetRef ref,
    String transferId,
  ) async {
    try {
      final result = await ref
          .read(clientTransferControllerProvider.notifier)
          .claimGiftTransfer(transferId: transferId);

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Transfer ${result.transferId} processed with status ${result.status}.',
          ),
        ),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _openSharedCheckoutContributionDialog(
    BuildContext context,
    WidgetRef ref,
    String customerId, {
    SharedCheckoutSummary? checkout,
  }) async {
    final payload = await showDialog<_SharedCheckoutContributionPayload>(
      context: context,
      builder: (context) =>
          _SharedCheckoutContributionDialog(initialCheckout: checkout),
    );

    if (payload == null) {
      return;
    }

    try {
      final result = await ref
          .read(teamCashFunctionsServiceProvider)
          .contributeSharedCheckout(
            checkoutId: payload.checkoutId,
            customerId: customerId,
            contributionMinorUnits: payload.contributionMinorUnits,
            requestId: _buildRequestId('shared-checkout'),
          );

      if (!context.mounted) return;
      ref.invalidate(clientWorkspaceProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Contribution saved. Checkout ${result.checkoutId} remaining ${formatCurrency(result.remainingMinorUnits)}.',
          ),
        ),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  String _buildRequestId(String prefix) {
    final now = DateTime.now().toUtc();
    return '$prefix-${now.microsecondsSinceEpoch}';
  }

  Future<void> _copyToClipboard(
    BuildContext context,
    String value,
    String confirmation,
  ) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(confirmation)));
  }
}

class _WalletOverviewPanel extends StatelessWidget {
  const _WalletOverviewPanel({
    required this.totalBalance,
    required this.groupBalances,
    required this.totalLotsCount,
    required this.pendingTransfersCount,
    required this.featuredLot,
    required this.expiringLot,
    required this.highlightedCheckout,
    required this.buildExpiryCountdown,
  });

  final int totalBalance;
  final List<_GroupBalanceViewData> groupBalances;
  final int totalLotsCount;
  final int pendingTransfersCount;
  final WalletLot? featuredLot;
  final WalletLot? expiringLot;
  final SharedCheckoutSummary? highlightedCheckout;
  final String Function(DateTime expiresAt) buildExpiryCountdown;

  @override
  Widget build(BuildContext context) {
    final topGroup = groupBalances.isEmpty ? null : groupBalances.first;

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: CompactStatTile(
                label: 'Available',
                value: formatCurrency(totalBalance),
                tint: const Color(0xFF6678FF),
                icon: Icons.account_balance_wallet_outlined,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: CompactStatTile(
                label: 'Pending',
                value: '$pendingTransfersCount gifts',
                tint: const Color(0xFFFF8C6B),
                icon: Icons.schedule_send_outlined,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Expanded(
          child: Column(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: _WalletFocusCard(
                        key: const ValueKey('client-group-balances-section'),
                        title: topGroup == null
                            ? 'Top group'
                            : topGroup.groupName,
                        headline: topGroup == null
                            ? 'Waiting'
                            : formatCurrency(topGroup.balanceAmount),
                        supporting: topGroup == null
                            ? 'Issued cashback will split into tandem-specific balances here.'
                            : '${topGroup.lotsCount} lots${topGroup.earliestExpiry == null ? '' : ' • Next expiry ${formatShortDate(topGroup.earliestExpiry!)}'}',
                        accent: const Color(0xFF6678FF),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _WalletFocusCard(
                        key: const ValueKey('client-wallet-lots-section'),
                        title: featuredLot == null
                            ? 'Spendable lots'
                            : featuredLot!.issuerBusinessName,
                        headline: featuredLot == null
                            ? '$totalLotsCount lots'
                            : formatCurrency(featuredLot!.availableAmount),
                        supporting: featuredLot == null
                            ? 'No active lot is loaded yet.'
                            : '${featuredLot!.groupName} • ${featuredLot!.currentOwnerLabel}',
                        accent: const Color(0xFF45C1B2),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: _WalletFocusCard(
                        key: const ValueKey('client-expiring-cashback-section'),
                        title: expiringLot == null
                            ? 'Expiry buffer'
                            : 'Expiry risk',
                        headline: expiringLot == null
                            ? 'All clear'
                            : buildExpiryCountdown(expiringLot!.expiresAt),
                        supporting: expiringLot == null
                            ? 'No lot expires in the next 14 days.'
                            : '${formatCurrency(expiringLot!.availableAmount)} • ${expiringLot!.issuerBusinessName}',
                        accent: const Color(0xFFFF8C6B),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _WalletFocusCard(
                        key: const ValueKey('client-shared-checkouts-section'),
                        title: highlightedCheckout == null
                            ? 'Shared checkout'
                            : highlightedCheckout!.businessName,
                        headline: highlightedCheckout == null
                            ? 'Inactive'
                            : formatCurrency(
                                highlightedCheckout!.remainingAmount,
                              ),
                        supporting: highlightedCheckout == null
                            ? 'Open contributions will surface here before checkout finalization.'
                            : 'Ticket ${highlightedCheckout!.sourceTicketRef} • ${highlightedCheckout!.contributions.length} members',
                        accent: const Color(0xFFB47BFF),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _WalletActionsPanel extends StatelessWidget {
  const _WalletActionsPanel({
    required this.statusMessage,
    required this.isSubmitting,
    required this.bannerMessage,
    required this.canRunLiveTransferActions,
    required this.hasVerifiedPhoneClaimActions,
    required this.availableGroups,
    required this.highlightedCheckout,
    required this.onSendGift,
    required this.onClaimById,
    required this.onJoinCheckout,
  });

  final String? statusMessage;
  final bool isSubmitting;
  final String bannerMessage;
  final bool canRunLiveTransferActions;
  final bool hasVerifiedPhoneClaimActions;
  final List<_WalletGroupOption> availableGroups;
  final SharedCheckoutSummary? highlightedCheckout;
  final VoidCallback? onSendGift;
  final VoidCallback? onClaimById;
  final VoidCallback? onJoinCheckout;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        InfoBanner(
          title: canRunLiveTransferActions
              ? 'Live transfer actions enabled'
              : 'Preview transfer surface',
          message: bannerMessage,
          color: canRunLiveTransferActions
              ? const Color(0xFFEFF4FF)
              : const Color(0xFFFFF2D8),
        ),
        if (statusMessage case final statusText?) ...[
          const SizedBox(height: 10),
          InfoBanner(
            title: 'Transfer status',
            message: statusText,
            color: const Color(0xFFE7F5EF),
          ),
        ],
        const SizedBox(height: 10),
        Expanded(
          child: Column(
            children: [
              Expanded(
                child: _WalletActionCard(
                  key: const ValueKey('client-transfer-section'),
                  accent: const Color(0xFF6678FF),
                  title: 'Send a gift',
                  body:
                      'Same-group only. The receiver inherits the original issuer and expiry window.',
                  footer: availableGroups.isEmpty
                      ? 'No eligible tandem group is loaded yet.'
                      : 'Eligible groups: ${availableGroups.map((group) => group.groupName).join(', ')}',
                  action: FilledButton.icon(
                    key: const ValueKey('client-send-gift-action'),
                    onPressed: onSendGift,
                    icon: isSubmitting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.redeem_outlined),
                    label: const Text('Send gift'),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: _WalletActionCard(
                  accent: const Color(0xFFFF8C6B),
                  title: 'Claim by transfer ID',
                  body:
                      'Best for shared family flows where the sender passes the gift ID manually.',
                  footer: hasVerifiedPhoneClaimActions
                      ? 'Verified phone session detected, so claiming can proceed.'
                      : 'Claiming stays locked until the client signs in with a verified phone number.',
                  action: OutlinedButton.icon(
                    key: const ValueKey('client-claim-by-id-action'),
                    onPressed: onClaimById,
                    icon: const Icon(Icons.card_giftcard_outlined),
                    label: const Text('Claim'),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: _WalletActionCard(
                  key: const ValueKey('client-shared-checkouts-section'),
                  accent: const Color(0xFF45C1B2),
                  title: highlightedCheckout == null
                      ? 'Join shared checkout'
                      : 'Contribute to ${highlightedCheckout!.businessName}',
                  body: highlightedCheckout == null
                      ? 'Split a purchase without breaking issuer boundaries or gift rules.'
                      : 'Remaining ${formatCurrency(highlightedCheckout!.remainingAmount)} on ticket ${highlightedCheckout!.sourceTicketRef}.',
                  footer: highlightedCheckout == null
                      ? 'This stays separate from direct gifts so each contribution keeps its own audit trail.'
                      : 'Already contributed: ${formatCurrency(highlightedCheckout!.contributedAmount)}',
                  action: OutlinedButton.icon(
                    key: const ValueKey('client-join-checkout-action'),
                    onPressed: onJoinCheckout,
                    icon: const Icon(Icons.groups_outlined),
                    label: const Text('Join'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _WalletPendingPanel extends StatelessWidget {
  const _WalletPendingPanel({
    required this.incomingTransfers,
    required this.outgoingTransfers,
    required this.isSubmitting,
    required this.canRunLiveTransferActions,
    required this.hasVerifiedPhoneClaimActions,
    required this.onClaimTransfer,
    required this.onCopyTransfer,
  });

  final List<PendingTransferSummary> incomingTransfers;
  final List<PendingTransferSummary> outgoingTransfers;
  final bool isSubmitting;
  final bool canRunLiveTransferActions;
  final bool hasVerifiedPhoneClaimActions;
  final ValueChanged<String> onClaimTransfer;
  final ValueChanged<String> onCopyTransfer;

  @override
  Widget build(BuildContext context) {
    final incoming = incomingTransfers.isEmpty ? null : incomingTransfers.first;
    final outgoing = outgoingTransfers.isEmpty ? null : outgoingTransfers.first;

    return Container(
      key: const ValueKey('client-pending-transfers-section'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            incoming == null && outgoing == null
                ? 'No pending gifts right now.'
                : 'Pending gifts are reduced to one incoming and one outgoing focus card.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: const Color(0xFF52606D)),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: incoming == null && outgoing == null
                ? const Center(
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('Nothing to claim or track'),
                      subtitle: Text(
                        'New outgoing gifts and incoming claims will surface here immediately.',
                      ),
                    ),
                  )
                : Row(
                    children: [
                      if (incoming != null)
                        Expanded(
                          child: _PendingTransferPreviewCard(
                            title: 'Incoming',
                            transfer: incoming,
                            extraCount: incomingTransfers.length - 1,
                            helperText: hasVerifiedPhoneClaimActions
                                ? null
                                : 'Claim requires verified phone auth.',
                            claimAction:
                                canRunLiveTransferActions &&
                                    hasVerifiedPhoneClaimActions &&
                                    !isSubmitting &&
                                    incoming.canClaim
                                ? () => onClaimTransfer(incoming.id)
                                : null,
                            copyAction: () => onCopyTransfer(incoming.id),
                          ),
                        ),
                      if (incoming != null && outgoing != null)
                        const SizedBox(width: 10),
                      if (outgoing != null)
                        Expanded(
                          child: _PendingTransferPreviewCard(
                            title: 'Outgoing',
                            transfer: outgoing,
                            extraCount: outgoingTransfers.length - 1,
                            helperText:
                                'Transfer stays pending until the receiver claims it.',
                            claimAction: null,
                            copyAction: () => onCopyTransfer(outgoing.id),
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

class _WalletFocusCard extends StatelessWidget {
  const _WalletFocusCard({
    super.key,
    required this.title,
    required this.headline,
    required this.supporting,
    required this.accent,
  });

  final String title;
  final String headline;
  final String supporting;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.11),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.labelLarge?.copyWith(color: const Color(0xFF52606D)),
          ),
          const SizedBox(height: 8),
          Text(
            headline,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            supporting,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: const Color(0xFF52606D)),
          ),
        ],
      ),
    );
  }
}

class _WalletActionCard extends StatelessWidget {
  const _WalletActionCard({
    super.key,
    required this.accent,
    required this.title,
    required this.body,
    required this.footer,
    required this.action,
  });

  final Color accent;
  final String title;
  final String body;
  final String footer;
  final Widget action;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            body,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: const Color(0xFF52606D)),
          ),
          const Spacer(),
          Text(
            footer,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: const Color(0xFF52606D)),
          ),
          const SizedBox(height: 10),
          action,
        ],
      ),
    );
  }
}

class _PendingTransferPreviewCard extends StatelessWidget {
  const _PendingTransferPreviewCard({
    required this.title,
    required this.transfer,
    required this.extraCount,
    required this.helperText,
    required this.claimAction,
    required this.copyAction,
  });

  final String title;
  final PendingTransferSummary transfer;
  final int extraCount;
  final String? helperText;
  final VoidCallback? claimAction;
  final VoidCallback copyAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: ValueKey('client-pending-transfer-${transfer.id}'),
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE4E8F7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              Text(
                formatCurrency(transfer.amount),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${transfer.groupName} • ${transfer.statusLabel}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: const Color(0xFF52606D)),
          ),
          const SizedBox(height: 6),
          Text(
            '${transfer.phoneNumber} • Expires ${formatShortDate(transfer.expiresAt)}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: const Color(0xFF52606D)),
          ),
          if (extraCount > 0) ...[
            const SizedBox(height: 6),
            Text(
              '+$extraCount more in this lane',
              style: Theme.of(
                context,
              ).textTheme.labelMedium?.copyWith(color: const Color(0xFF4A57A9)),
            ),
          ],
          const Spacer(),
          if (helperText case final text?) ...[
            Text(
              text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: const Color(0xFF9C6100)),
            ),
            const SizedBox(height: 10),
          ],
          Row(
            children: [
              if (claimAction != null) ...[
                Expanded(
                  child: FilledButton.icon(
                    key: ValueKey(
                      'client-pending-transfer-claim-${transfer.id}',
                    ),
                    onPressed: claimAction,
                    icon: const Icon(Icons.card_giftcard_outlined),
                    label: const Text('Claim'),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: OutlinedButton.icon(
                  key: ValueKey('client-pending-transfer-copy-${transfer.id}'),
                  onPressed: copyAction,
                  icon: const Icon(Icons.copy_outlined),
                  label: const Text('Copy id'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _GroupBalanceViewData {
  const _GroupBalanceViewData({
    required this.groupId,
    required this.groupName,
    required this.balanceAmount,
    required this.lotsCount,
    required this.earliestExpiry,
  });

  final String groupId;
  final String groupName;
  final int balanceAmount;
  final int lotsCount;
  final DateTime? earliestExpiry;
}

class _WalletGroupOption {
  const _WalletGroupOption({required this.groupId, required this.groupName});

  final String groupId;
  final String groupName;
}

class _SendGiftPayload {
  const _SendGiftPayload({
    required this.recipientPhoneE164,
    required this.groupId,
    required this.amountMinorUnits,
  });

  final String recipientPhoneE164;
  final String groupId;
  final int amountMinorUnits;
}

class _SendGiftDialog extends StatefulWidget {
  const _SendGiftDialog({required this.availableGroups});

  final List<_WalletGroupOption> availableGroups;

  @override
  State<_SendGiftDialog> createState() => _SendGiftDialogState();
}

class _SendGiftDialogState extends State<_SendGiftDialog> {
  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();
  final _amountController = TextEditingController();
  late String _selectedGroupId;

  @override
  void initState() {
    super.initState();
    _selectedGroupId = widget.availableGroups.first.groupId;
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Send cashback gift'),
      content: SizedBox(
        width: 440,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                key: const ValueKey('client-send-gift-group-input'),
                initialValue: _selectedGroupId,
                decoration: const InputDecoration(labelText: 'Tandem group'),
                items: widget.availableGroups
                    .map(
                      (group) => DropdownMenuItem<String>(
                        value: group.groupId,
                        child: Text(group.groupName),
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
              const SizedBox(height: 12),
              TextFormField(
                key: const ValueKey('client-send-gift-phone-input'),
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Recipient phone',
                  hintText: '+998901112233',
                ),
                validator: _required,
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const ValueKey('client-send-gift-amount-input'),
                controller: _amountController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Amount',
                  hintText: '25000',
                ),
                validator: (value) {
                  final parsed = int.tryParse(value?.trim() ?? '');
                  if (parsed == null || parsed <= 0) {
                    return 'Enter a positive whole amount.';
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
          key: const ValueKey('client-send-gift-submit'),
          onPressed: () {
            if (!_formKey.currentState!.validate()) {
              return;
            }

            Navigator.of(context).pop(
              _SendGiftPayload(
                recipientPhoneE164: _phoneController.text.trim(),
                groupId: _selectedGroupId,
                amountMinorUnits: int.parse(_amountController.text.trim()),
              ),
            );
          },
          child: const Text('Send'),
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

class _ClaimGiftDialog extends StatefulWidget {
  const _ClaimGiftDialog();

  @override
  State<_ClaimGiftDialog> createState() => _ClaimGiftDialogState();
}

class _ClaimGiftDialogState extends State<_ClaimGiftDialog> {
  final _formKey = GlobalKey<FormState>();
  final _transferIdController = TextEditingController();

  @override
  void dispose() {
    _transferIdController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Claim pending gift'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: TextFormField(
            key: const ValueKey('client-claim-gift-id-input'),
            controller: _transferIdController,
            decoration: const InputDecoration(
              labelText: 'Transfer id',
              hintText: 'giftTransferId',
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Transfer id is required.';
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
          key: const ValueKey('client-claim-gift-submit'),
          onPressed: () {
            if (!_formKey.currentState!.validate()) {
              return;
            }

            Navigator.of(context).pop(_transferIdController.text.trim());
          },
          child: const Text('Claim'),
        ),
      ],
    );
  }
}

class _SharedCheckoutContributionPayload {
  const _SharedCheckoutContributionPayload({
    required this.checkoutId,
    required this.contributionMinorUnits,
  });

  final String checkoutId;
  final int contributionMinorUnits;
}

class _SharedCheckoutContributionDialog extends StatefulWidget {
  const _SharedCheckoutContributionDialog({this.initialCheckout});

  final SharedCheckoutSummary? initialCheckout;

  @override
  State<_SharedCheckoutContributionDialog> createState() =>
      _SharedCheckoutContributionDialogState();
}

class _SharedCheckoutContributionDialogState
    extends State<_SharedCheckoutContributionDialog> {
  final _formKey = GlobalKey<FormState>();
  final _checkoutIdController = TextEditingController();
  final _amountController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final checkout = widget.initialCheckout;
    if (checkout != null) {
      _checkoutIdController.text = checkout.id;
    }
  }

  @override
  void dispose() {
    _checkoutIdController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.initialCheckout == null
            ? 'Join shared checkout'
            : 'Contribute to ${widget.initialCheckout!.businessName}',
      ),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                key: const ValueKey('client-shared-checkout-id-input'),
                controller: _checkoutIdController,
                readOnly: widget.initialCheckout != null,
                decoration: const InputDecoration(
                  labelText: 'Checkout id',
                  hintText: 'sharedCheckoutId',
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Checkout id is required.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const ValueKey('client-shared-checkout-amount-input'),
                controller: _amountController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Contribution amount',
                  hintText: '40000',
                ),
                validator: (value) {
                  final parsed = int.tryParse(value?.trim() ?? '');
                  if (parsed == null || parsed <= 0) {
                    return 'Enter a positive whole amount.';
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
          key: const ValueKey('client-shared-checkout-submit'),
          onPressed: () {
            if (!_formKey.currentState!.validate()) {
              return;
            }

            Navigator.of(context).pop(
              _SharedCheckoutContributionPayload(
                checkoutId: _checkoutIdController.text.trim(),
                contributionMinorUnits: int.parse(
                  _amountController.text.trim(),
                ),
              ),
            );
          },
          child: const Text('Contribute'),
        ),
      ],
    );
  }
}
