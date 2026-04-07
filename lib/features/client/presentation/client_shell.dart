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

    return Scaffold(
      key: const ValueKey('client-workspace-root'),
      appBar: AppBar(
        title: Text('Client wallet · ${client.clientName}'),
        actions: [
          NotificationBellButton(
            unreadCount: unreadNotificationsCount,
            onPressed: () => _openNotificationsCenter(notifications, client),
          ),
          if (session?.role == AppRole.client)
            IconButton(
              tooltip: session!.isPreview ? 'Exit preview' : 'Sign out',
              onPressed: () async {
                await ref.read(appSessionControllerProvider.notifier).signOut();
                if (!context.mounted) return;
                context.go('/');
              },
              icon: const Icon(Icons.logout),
            ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
          children: [
            InfoBanner(
              title: session?.isPreview == false
                  ? hasVerifiedPhoneClaimActions
                        ? 'Wallet claimed by verified phone'
                        : 'Wallet linked to client session'
                  : 'Phone-first identity',
              message: session?.isPreview == false
                  ? hasVerifiedPhoneClaimActions
                        ? 'Verified phone ${session?.phoneNumber ?? client.phoneNumber} is attached to customer wallet ${session?.customerId ?? 'pending'}. Ledger history remains preserved from the original phone-first identity.'
                        : 'Client session is linked to customer wallet ${session?.customerId ?? 'pending'} for automated smoke coverage. Real client claim still happens through verified phone auth.'
                  : 'Wallet ownership is attached to the phone-backed customer identity first, then claimed by app auth once the same number is verified.',
            ),
            const SizedBox(height: 16),
            IndexedStack(
              index: _selectedIndex,
              children: [
                _StoresTab(stores: client.storeDirectory),
                _WalletTab(
                  client: client,
                  canRunLiveTransferActions: canRunLiveTransfers,
                  hasVerifiedPhoneClaimActions: hasVerifiedPhoneClaimActions,
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
            icon: Icon(Icons.store_mall_directory_outlined),
            selectedIcon: Icon(Icons.store_mall_directory),
            label: 'Stores',
          ),
          NavigationDestination(
            icon: Icon(Icons.account_balance_wallet_outlined),
            selectedIcon: Icon(Icons.account_balance_wallet),
            label: 'Wallet',
          ),
          NavigationDestination(
            icon: Icon(Icons.history_outlined),
            selectedIcon: Icon(Icons.history),
            label: 'History',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
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
}

enum _ClientStoreFilter { all, active, pending }

class _StoresTab extends StatefulWidget {
  const _StoresTab({required this.stores});

  final List<BusinessDirectoryEntry> stores;

  @override
  State<_StoresTab> createState() => _StoresTabState();
}

class _StoresTabState extends State<_StoresTab> {
  final _searchController = TextEditingController();
  _ClientStoreFilter _selectedFilter = _ClientStoreFilter.all;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final searchTerm = _searchController.text.trim().toLowerCase();
    final filteredStores = widget.stores
        .where((store) => _matchesStoreFilter(store, _selectedFilter))
        .where((store) => _matchesStoreSearch(store, searchTerm))
        .toList();

    return SectionCard(
      key: const ValueKey('client-stores-section'),
      title: 'Tandem stores',
      subtitle:
          'Clients browse trusted private-group businesses, not a public marketplace feed.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            key: const ValueKey('client-store-search-input'),
            controller: _searchController,
            decoration: const InputDecoration(
              labelText: 'Search stores, categories, or offers',
              hintText: 'Cafe, diagnostics, bakery...',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: _ClientStoreFilter.values
                .map(
                  (filter) => ChoiceChip(
                    key: ValueKey('client-store-filter-${filter.name}'),
                    label: Text(_labelForStoreFilter(filter)),
                    selected: filter == _selectedFilter,
                    onSelected: (_) {
                      setState(() {
                        _selectedFilter = filter;
                      });
                    },
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 16),
          Text(
            'Showing ${filteredStores.length} of ${widget.stores.length} stores.',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: const Color(0xFF52606D)),
          ),
          const SizedBox(height: 12),
          if (filteredStores.isEmpty)
            const ListTile(
              key: ValueKey('client-store-empty-state'),
              contentPadding: EdgeInsets.zero,
              title: Text('No stores match this search'),
              subtitle: Text(
                'Try another keyword or switch the tandem membership filter.',
              ),
            )
          else
            ...filteredStores.map(
              (store) => Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: _StoreTile(store: store),
              ),
            ),
        ],
      ),
    );
  }

  bool _matchesStoreFilter(
    BusinessDirectoryEntry store,
    _ClientStoreFilter filter,
  ) {
    switch (filter) {
      case _ClientStoreFilter.all:
        return true;
      case _ClientStoreFilter.active:
        return store.groupStatus == GroupMembershipStatus.active;
      case _ClientStoreFilter.pending:
        return store.groupStatus == GroupMembershipStatus.pendingApproval;
    }
  }

  bool _matchesStoreSearch(BusinessDirectoryEntry store, String searchTerm) {
    if (searchTerm.isEmpty) {
      return true;
    }

    final haystack = <String>[
      store.name,
      store.category,
      store.description,
      store.address,
      store.redeemPolicy,
      ...store.products.map((product) => product.name),
      ...store.services.map((service) => service.name),
    ].join(' ').toLowerCase();

    return haystack.contains(searchTerm);
  }

  String _labelForStoreFilter(_ClientStoreFilter filter) {
    return switch (filter) {
      _ClientStoreFilter.all => 'All',
      _ClientStoreFilter.active => 'Active tandems',
      _ClientStoreFilter.pending => 'Pending approval',
    };
  }
}

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

enum _ClientHistoryFilter { all, incoming, outgoing, transfers, checkouts }

class _HistoryTab extends StatefulWidget {
  const _HistoryTab({required this.events});

  final List<WalletEvent> events;

  @override
  State<_HistoryTab> createState() => _HistoryTabState();
}

class _HistoryTabState extends State<_HistoryTab> {
  _ClientHistoryFilter _selectedFilter = _ClientHistoryFilter.all;
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final searchTerm = _searchController.text.trim().toLowerCase();
    final filteredEvents =
        widget.events
            .where((event) => _matchesHistoryFilter(event, _selectedFilter))
            .where((event) => _matchesHistorySearch(event, searchTerm))
            .toList()
          ..sort((left, right) => right.occurredAt.compareTo(left.occurredAt));
    final groupedEvents = _groupEventsByDay(filteredEvents);

    return SectionCard(
      key: const ValueKey('client-history-tab'),
      title: 'Ledger history',
      subtitle:
          'History is append-only and never disappears, even when ownership changes or gifts stay pending.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            key: const ValueKey('client-history-search-input'),
            controller: _searchController,
            decoration: const InputDecoration(
              labelText: 'Search history',
              hintText: 'Gift, Silk Road, checkout...',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: (_) {
              setState(() {});
            },
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: _ClientHistoryFilter.values
                .map(
                  (filter) => ChoiceChip(
                    key: ValueKey('client-history-filter-${filter.name}'),
                    label: Text(_labelForHistoryFilter(filter)),
                    selected: filter == _selectedFilter,
                    onSelected: (_) {
                      setState(() {
                        _selectedFilter = filter;
                      });
                    },
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 16),
          Text(
            'Showing ${filteredEvents.length} of ${widget.events.length} ledger events.',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: const Color(0xFF52606D)),
          ),
          const SizedBox(height: 8),
          if (filteredEvents.isEmpty)
            const ListTile(
              key: ValueKey('client-history-empty-state'),
              contentPadding: EdgeInsets.zero,
              title: Text('No ledger events match this filter'),
              subtitle: Text(
                'Try another filter to inspect incoming, outgoing, transfer, or shared checkout activity.',
              ),
            ),
          ...groupedEvents.entries.map(
            (entry) => Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.key,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: const Color(0xFF2455A6),
                    ),
                  ),
                  const SizedBox(height: 6),
                  ...entry.value.map(
                    (event) => ListTile(
                      key: ValueKey('client-history-event-${event.id}'),
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        backgroundColor: event.isIncoming
                            ? const Color(0xFFE7F5EF)
                            : const Color(0xFFFFF2D8),
                        child: Icon(
                          event.isIncoming
                              ? Icons.south_west_outlined
                              : Icons.north_east_outlined,
                          color: event.isIncoming
                              ? const Color(0xFF1B7F5B)
                              : const Color(0xFF9C6100),
                        ),
                      ),
                      title: Text(event.title),
                      subtitle: Text(
                        '${event.subtitle}\n${event.issuerBusinessName} • ${formatDateTime(event.occurredAt)}',
                      ),
                      trailing: Text(
                        '${event.isIncoming ? '+' : '-'}${formatCurrency(event.amount)}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  bool _matchesHistoryFilter(WalletEvent event, _ClientHistoryFilter filter) {
    switch (filter) {
      case _ClientHistoryFilter.all:
        return true;
      case _ClientHistoryFilter.incoming:
        return event.isIncoming;
      case _ClientHistoryFilter.outgoing:
        return !event.isIncoming;
      case _ClientHistoryFilter.transfers:
        return switch (event.type) {
          WalletEventType.transferOut ||
          WalletEventType.transferIn ||
          WalletEventType.giftPending ||
          WalletEventType.giftClaimed => true,
          _ => false,
        };
      case _ClientHistoryFilter.checkouts:
        return switch (event.type) {
          WalletEventType.sharedCheckoutCreated ||
          WalletEventType.sharedCheckoutContribution ||
          WalletEventType.sharedCheckoutFinalized => true,
          _ => false,
        };
    }
  }

  bool _matchesHistorySearch(WalletEvent event, String searchTerm) {
    if (searchTerm.isEmpty) {
      return true;
    }

    final haystack = [
      event.title,
      event.subtitle,
      event.groupName,
      event.issuerBusinessName,
    ].join(' ').toLowerCase();
    return haystack.contains(searchTerm);
  }

  String _labelForHistoryFilter(_ClientHistoryFilter filter) {
    return switch (filter) {
      _ClientHistoryFilter.all => 'All',
      _ClientHistoryFilter.incoming => 'Incoming',
      _ClientHistoryFilter.outgoing => 'Outgoing',
      _ClientHistoryFilter.transfers => 'Transfers',
      _ClientHistoryFilter.checkouts => 'Checkouts',
    };
  }

  Map<String, List<WalletEvent>> _groupEventsByDay(List<WalletEvent> events) {
    final grouped = <String, List<WalletEvent>>{};
    for (final event in events) {
      final key = formatShortDate(event.occurredAt);
      grouped.putIfAbsent(key, () => <WalletEvent>[]).add(event);
    }
    return grouped;
  }
}

class _ProfileTab extends ConsumerStatefulWidget {
  const _ProfileTab({
    required this.client,
    required this.customerIdentityToken,
    required this.customerId,
    required this.canEditProfile,
  });

  final ClientWorkspace client;
  final CustomerIdentificationToken customerIdentityToken;
  final String? customerId;
  final bool canEditProfile;

  @override
  ConsumerState<_ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends ConsumerState<_ProfileTab> {
  bool _savingProfile = false;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      key: const ValueKey('client-profile-section'),
      title: widget.client.clientName,
      subtitle: widget.client.phoneNumber,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _ProfileLine(
            label: 'Claim status',
            value: 'Verified app user linked to a phone-first customer wallet',
          ),
          const _ProfileLine(
            label: 'Transfer rules',
            value:
                'Only to recipients inside the same tandem group; issuer and expiry stay intact',
          ),
          const _ProfileLine(
            label: 'Chrome fallback',
            value:
                'If camera access is limited during web testing, the same TeamCash payload can be copied from here and pasted into the staff scan surface.',
          ),
          _ProfileLine(
            label: 'Marketing updates',
            value: widget.client.marketingOptIn
                ? 'Enabled for tandem-related offers'
                : 'Disabled',
          ),
          _ProfileLine(
            label: 'Preferred start tab',
            value: _clientTabLabel(widget.client.preferredStartTabIndex),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.tonalIcon(
                key: const ValueKey('client-profile-edit-action'),
                onPressed: widget.canEditProfile && !_savingProfile
                    ? _editProfile
                    : null,
                icon: _savingProfile
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.edit_outlined),
                label: const Text('Edit profile'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          CustomerIdentityQrCard(
            token: widget.customerIdentityToken,
            onCopyPayload: () async {
              await Clipboard.setData(
                ClipboardData(text: widget.customerIdentityToken.qrPayload),
              );
              if (!context.mounted) {
                return;
              }
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Client ID payload copied. Staff can paste it into the Scan surface while Chrome is the active test target.',
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Future<void> _editProfile() async {
    final customerId = widget.customerId;
    if (customerId == null || customerId.isEmpty) {
      return;
    }

    final payload = await showDialog<_ClientProfilePayload>(
      context: context,
      builder: (context) => _ClientProfileDialog(
        initialDisplayName: widget.client.clientName,
        initialMarketingOptIn: widget.client.marketingOptIn,
        initialPreferredTabIndex: widget.client.preferredStartTabIndex,
      ),
    );
    if (payload == null) {
      return;
    }

    setState(() {
      _savingProfile = true;
    });

    try {
      await ref
          .read(accountProfileServiceProvider)
          .updateCurrentClientProfile(
            customerId: customerId,
            displayName: payload.displayName,
            marketingOptIn: payload.marketingOptIn,
            preferredClientTab: _clientTabPreferenceValue(
              payload.preferredTabIndex,
            ),
          );
      await ref
          .read(appSessionControllerProvider.notifier)
          .refreshCurrentSession();
      ref.invalidate(clientWorkspaceProvider);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Client profile updated.')));
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
          _savingProfile = false;
        });
      }
    }
  }
}

class _StoreTile extends StatelessWidget {
  const _StoreTile({required this.store});

  final BusinessDirectoryEntry store;

  @override
  Widget build(BuildContext context) {
    final status = switch (store.groupStatus) {
      GroupMembershipStatus.active => 'Active tandem member',
      GroupMembershipStatus.pendingApproval => 'Join request pending',
      GroupMembershipStatus.rejected => 'Not active in tandem',
      GroupMembershipStatus.notGrouped => 'No tandem group yet',
    };
    final primaryLocation = store.locations.isEmpty
        ? null
        : store.locations.first;
    final featuredMediaPreview = store.featuredMedia.take(3).toList();
    final productsPreview = store.products.take(4).toList();
    final servicesPreview = store.services.take(4).toList();

    return Container(
      key: ValueKey('client-store-${store.id}'),
      padding: const EdgeInsets.all(18),
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
                  store.name,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              Chip(label: Text(formatPercent(store.cashbackBasisPoints))),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            store.description,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: const Color(0xFF52606D)),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              Chip(label: Text(store.category)),
              Chip(label: Text(store.workingHours)),
              Chip(label: Text(status)),
              Chip(
                label: Text(
                  '${store.locationsCount} location${store.locationsCount == 1 ? '' : 's'}',
                ),
              ),
              Chip(
                label: Text(
                  '${store.productsCount + store.servicesCount} offers',
                ),
              ),
              if (store.mediaCount > 0)
                Chip(
                  label: Text(
                    '${store.mediaCount} media item${store.mediaCount == 1 ? '' : 's'}',
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          FilledButton.tonalIcon(
            key: ValueKey('client-store-open-details-${store.id}'),
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              useSafeArea: true,
              builder: (context) => _StoreDetailSheet(store: store),
            ),
            icon: const Icon(Icons.menu_book_outlined),
            label: const Text('View full details'),
          ),
          const SizedBox(height: 12),
          Text('${store.address} • ${store.redeemPolicy}'),
          if (store.phoneNumbers.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: store.phoneNumbers
                  .map((phone) => Chip(label: Text(phone)))
                  .toList(),
            ),
          ],
          if (featuredMediaPreview.isNotEmpty) ...[
            const SizedBox(height: 14),
            _StoreMediaStrip(storeId: store.id, media: featuredMediaPreview),
          ],
          if (primaryLocation != null) ...[
            const SizedBox(height: 14),
            _StoreDetailBlock(
              title: 'Primary location',
              lines: [
                primaryLocation.name,
                primaryLocation.address,
                primaryLocation.workingHours,
                if (primaryLocation.notes.trim().isNotEmpty)
                  primaryLocation.notes.trim(),
              ],
            ),
          ],
          if (productsPreview.isNotEmpty) ...[
            const SizedBox(height: 14),
            _StoreDetailBlock(
              key: ValueKey('client-store-products-${store.id}'),
              title: 'Products',
              lines: productsPreview
                  .map(
                    (product) =>
                        '${product.name}${product.priceLabel.trim().isEmpty ? '' : ' • ${product.priceLabel}'}',
                  )
                  .toList(),
            ),
          ],
          if (servicesPreview.isNotEmpty) ...[
            const SizedBox(height: 14),
            _StoreDetailBlock(
              key: ValueKey('client-store-services-${store.id}'),
              title: 'Services',
              lines: servicesPreview
                  .map(
                    (service) =>
                        '${service.name}${service.priceLabel.trim().isEmpty ? '' : ' • ${service.priceLabel}'}',
                  )
                  .toList(),
            ),
          ],
          if (store.locations.length > 1 ||
              store.products.length > productsPreview.length ||
              store.services.length > servicesPreview.length ||
              store.featuredMedia.length > featuredMediaPreview.length) ...[
            const SizedBox(height: 10),
            Text(
              'Open full details to inspect every location, offer, and gallery item.',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: const Color(0xFF6B7280)),
            ),
          ],
        ],
      ),
    );
  }
}

class _StoreDetailSheet extends StatelessWidget {
  const _StoreDetailSheet({required this.store});

  final BusinessDirectoryEntry store;

  @override
  Widget build(BuildContext context) {
    final hasCoverImage = store.coverImageUrl.trim().isNotEmpty;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.88,
      maxChildSize: 0.96,
      minChildSize: 0.6,
      builder: (context, scrollController) => Material(
        color: Theme.of(context).scaffoldBackgroundColor,
        child: ListView(
          key: ValueKey('client-store-detail-sheet-${store.id}'),
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
          children: [
            Center(
              child: Container(
                width: 56,
                height: 5,
                decoration: BoxDecoration(
                  color: const Color(0xFFD6E4DD),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(store.name, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(
              '${store.category} • ${formatPercent(store.cashbackBasisPoints)} cashback',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(color: const Color(0xFF2455A6)),
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: Container(
                height: 220,
                color: const Color(0xFFEAF2EE),
                child: hasCoverImage
                    ? Image.network(
                        store.coverImageUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) =>
                            const _StoreMediaFallback(mediaType: 'cover'),
                      )
                    : const _StoreMediaFallback(mediaType: 'cover'),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              store.description,
              style: Theme.of(
                context,
              ).textTheme.bodyLarge?.copyWith(color: const Color(0xFF52606D)),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                Chip(label: Text(store.workingHours)),
                Chip(label: Text(store.groupName)),
                Chip(label: Text(store.redeemPolicy)),
              ],
            ),
            if (store.phoneNumbers.isNotEmpty) ...[
              const SizedBox(height: 18),
              _StoreDetailBlock(
                key: ValueKey('client-store-detail-contact-${store.id}'),
                title: 'Contact',
                lines: [store.address, ...store.phoneNumbers],
              ),
            ],
            if (store.locations.isNotEmpty) ...[
              const SizedBox(height: 18),
              _StoreDetailBlock(
                key: ValueKey('client-store-detail-locations-${store.id}'),
                title: 'All locations',
                lines: store.locations
                    .map(
                      (location) =>
                          '${location.name} • ${location.address} • ${location.workingHours}',
                    )
                    .toList(),
              ),
            ],
            if (store.products.isNotEmpty) ...[
              const SizedBox(height: 18),
              _StoreDetailBlock(
                key: ValueKey('client-store-detail-products-${store.id}'),
                title: 'Full product list',
                lines: store.products
                    .map(
                      (product) =>
                          '${product.name}${product.priceLabel.trim().isEmpty ? '' : ' • ${product.priceLabel}'}',
                    )
                    .toList(),
              ),
            ],
            if (store.services.isNotEmpty) ...[
              const SizedBox(height: 18),
              _StoreDetailBlock(
                key: ValueKey('client-store-detail-services-${store.id}'),
                title: 'Full service list',
                lines: store.services
                    .map(
                      (service) =>
                          '${service.name}${service.priceLabel.trim().isEmpty ? '' : ' • ${service.priceLabel}'}',
                    )
                    .toList(),
              ),
            ],
            if (store.featuredMedia.isNotEmpty) ...[
              const SizedBox(height: 18),
              _StoreMediaStrip(
                storeId: '${store.id}-detail',
                media: store.featuredMedia,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StoreMediaStrip extends StatelessWidget {
  const _StoreMediaStrip({required this.storeId, required this.media});

  final String storeId;
  final List<BusinessMediaSummary> media;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: ValueKey('client-store-media-$storeId'),
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F4EE),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Portfolio', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Text(
            'Media from the live business gallery so clients can preview the storefront before visiting.',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: const Color(0xFF52606D)),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: media
                .map(
                  (entry) => SizedBox(
                    width: 170,
                    child: _StoreMediaCard(storeId: storeId, media: entry),
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }
}

class _StoreMediaCard extends StatelessWidget {
  const _StoreMediaCard({required this.storeId, required this.media});

  final String storeId;
  final BusinessMediaSummary media;

  @override
  Widget build(BuildContext context) {
    final hasImage = media.imageUrl.trim().isNotEmpty;

    return Container(
      key: ValueKey('client-store-media-item-$storeId-${media.id}'),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE6DED1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: AspectRatio(
              aspectRatio: 4 / 3,
              child: hasImage
                  ? Image.network(
                      media.imageUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) =>
                          _StoreMediaFallback(mediaType: media.mediaType),
                    )
                  : _StoreMediaFallback(mediaType: media.mediaType),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  media.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              if (media.isFeatured)
                const Padding(
                  padding: EdgeInsets.only(left: 8),
                  child: Icon(
                    Icons.star_rounded,
                    size: 18,
                    color: Color(0xFF1B7F5B),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            media.mediaType,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: const Color(0xFF2455A6),
              fontWeight: FontWeight.w700,
            ),
          ),
          if (media.caption.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              media.caption,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: const Color(0xFF52606D)),
            ),
          ],
        ],
      ),
    );
  }
}

class _StoreMediaFallback extends StatelessWidget {
  const _StoreMediaFallback({required this.mediaType});

  final String mediaType;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFEAF2EE),
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.photo_library_outlined, color: Color(0xFF6B7280)),
          const SizedBox(height: 8),
          Text(
            mediaType,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(color: const Color(0xFF52606D)),
          ),
        ],
      ),
    );
  }
}

class _StoreDetailBlock extends StatelessWidget {
  const _StoreDetailBlock({
    super.key,
    required this.title,
    required this.lines,
  });

  final String title;
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F4EE),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          ...lines.map(
            (line) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(line),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileLine extends StatelessWidget {
  const _ProfileLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.labelLarge?.copyWith(color: const Color(0xFF52606D)),
          ),
          const SizedBox(height: 4),
          Text(value),
        ],
      ),
    );
  }
}

class _ClientProfilePayload {
  const _ClientProfilePayload({
    required this.displayName,
    required this.marketingOptIn,
    required this.preferredTabIndex,
  });

  final String displayName;
  final bool marketingOptIn;
  final int preferredTabIndex;
}

class _ClientProfileDialog extends StatefulWidget {
  const _ClientProfileDialog({
    required this.initialDisplayName,
    required this.initialMarketingOptIn,
    required this.initialPreferredTabIndex,
  });

  final String initialDisplayName;
  final bool initialMarketingOptIn;
  final int initialPreferredTabIndex;

  @override
  State<_ClientProfileDialog> createState() => _ClientProfileDialogState();
}

class _ClientProfileDialogState extends State<_ClientProfileDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _displayNameController;
  late bool _marketingOptIn;
  late int _preferredTabIndex;

  @override
  void initState() {
    super.initState();
    _displayNameController = TextEditingController(
      text: widget.initialDisplayName,
    );
    _marketingOptIn = widget.initialMarketingOptIn;
    _preferredTabIndex = widget.initialPreferredTabIndex;
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit client profile'),
      content: SizedBox(
        width: 440,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                key: const ValueKey('client-profile-display-name-input'),
                controller: _displayNameController,
                decoration: const InputDecoration(labelText: 'Display name'),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Display name is required.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<int>(
                key: const ValueKey('client-profile-preferred-tab-input'),
                initialValue: _preferredTabIndex,
                decoration: const InputDecoration(
                  labelText: 'Preferred start tab',
                ),
                items: List<DropdownMenuItem<int>>.generate(
                  4,
                  (index) => DropdownMenuItem<int>(
                    value: index,
                    child: Text(_clientTabLabel(index)),
                  ),
                ),
                onChanged: (value) {
                  if (value == null) {
                    return;
                  }
                  setState(() {
                    _preferredTabIndex = value;
                  });
                },
              ),
              const SizedBox(height: 12),
              SwitchListTile.adaptive(
                key: const ValueKey('client-profile-marketing-toggle'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Receive tandem marketing updates'),
                subtitle: const Text(
                  'Only business and loyalty updates inside your closed tandem groups.',
                ),
                value: _marketingOptIn,
                onChanged: (value) {
                  setState(() {
                    _marketingOptIn = value;
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
          key: const ValueKey('client-profile-save-submit'),
          onPressed: () {
            if (!_formKey.currentState!.validate()) {
              return;
            }

            Navigator.of(context).pop(
              _ClientProfilePayload(
                displayName: _displayNameController.text.trim(),
                marketingOptIn: _marketingOptIn,
                preferredTabIndex: _preferredTabIndex,
              ),
            );
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

String _clientTabLabel(int tabIndex) {
  switch (tabIndex) {
    case 0:
      return 'Stores';
    case 1:
      return 'Wallet';
    case 2:
      return 'History';
    case 3:
      return 'Profile';
    default:
      return 'Wallet';
  }
}

String _clientTabPreferenceValue(int tabIndex) {
  switch (tabIndex) {
    case 0:
      return 'stores';
    case 1:
      return 'wallet';
    case 2:
      return 'history';
    case 3:
      return 'profile';
    default:
      return 'wallet';
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
