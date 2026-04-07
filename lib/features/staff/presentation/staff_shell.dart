import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:teamcash/app/app.dart';
import 'package:teamcash/core/models/app_role.dart';
import 'package:teamcash/core/models/customer_identity_models.dart';
import 'package:teamcash/core/models/dashboard_models.dart';
import 'package:teamcash/core/models/notification_models.dart';
import 'package:teamcash/core/services/account_profile_service.dart';
import 'package:teamcash/core/services/customer_identity_token_service.dart';
import 'package:teamcash/core/services/notification_center_service.dart';
import 'package:teamcash/core/services/teamcash_functions_service.dart';
import 'package:teamcash/core/session/session_controller.dart';
import 'package:teamcash/core/models/workspace_models.dart';
import 'package:teamcash/core/utils/formatters.dart';
import 'package:teamcash/data/firestore/firestore_workspace_repository.dart';
import 'package:teamcash/features/shared/presentation/customer_identity_widgets.dart';
import 'package:teamcash/features/shared/presentation/notification_center_widgets.dart';
import 'package:teamcash/features/shared/presentation/shell_widgets.dart';

class StaffShell extends ConsumerStatefulWidget {
  const StaffShell({super.key});

  @override
  ConsumerState<StaffShell> createState() => _StaffShellState();
}

class _StaffShellState extends ConsumerState<StaffShell> {
  int _selectedIndex = 1;
  bool _hasAppliedPreferredTab = false;
  final TextEditingController _identifierController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController(
    text: '+998 90 555 11 22',
  );
  final TextEditingController _amountController = TextEditingController(
    text: '49000',
  );
  final TextEditingController _ticketRefController = TextEditingController(
    text: 'SR-2201',
  );
  bool _submittingAction = false;
  ResolvedCustomerIdentifier? _resolvedCustomerIdentifier;

  @override
  void dispose() {
    _identifierController.dispose();
    _phoneController.dispose();
    _amountController.dispose();
    _ticketRefController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final previewStaff = ref.watch(appSnapshotProvider).staff;
    final session = ref.watch(currentSessionProvider);
    final staffAsync = ref.watch(staffWorkspaceProvider);
    final notificationsAsync = ref.watch(currentNotificationsProvider);
    final canRunLedgerActions =
        session?.role == AppRole.staff && session?.isPreview == false;
    final notifications =
        notificationsAsync.asData?.value ?? const <AppNotificationItem>[];
    final unreadNotificationsCount = notifications
        .where((notification) => !notification.isRead)
        .length;

    if (canRunLedgerActions && staffAsync.isLoading && !staffAsync.hasValue) {
      return Scaffold(
        appBar: AppBar(title: const Text('Staff workspace')),
        body: const SafeArea(child: Center(child: CircularProgressIndicator())),
      );
    }

    if (canRunLedgerActions && staffAsync.hasError && !staffAsync.hasValue) {
      return Scaffold(
        appBar: AppBar(title: const Text('Staff workspace')),
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Staff workspace could not be loaded from Firestore.',
                  ),
                  const SizedBox(height: 12),
                  Text(
                    staffAsync.error.toString(),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () => ref.invalidate(staffWorkspaceProvider),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final staff = canRunLedgerActions ? staffAsync.requireValue : previewStaff;
    _applyPreferredTabIfNeeded(staff.preferredStartTabIndex);

    return Scaffold(
      key: const ValueKey('staff-workspace-root'),
      appBar: AppBar(
        title: Text(
          'Staff workspace · ${staff.businessName}',
          key: const ValueKey('staff-workspace-title'),
        ),
        actions: [
          NotificationBellButton(
            unreadCount: unreadNotificationsCount,
            onPressed: () => _openNotificationsCenter(notifications, staff),
          ),
          if (session?.role == AppRole.staff)
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
              title: 'Single-business permissions enforced',
              message:
                  '${staff.staffName} can operate only inside ${staff.businessName}. Cross-business staff access is intentionally blocked.',
            ),
            if (!canRunLedgerActions) ...[
              const SizedBox(height: 12),
              const InfoBanner(
                title: 'Preview-only ledger actions',
                message:
                    'Issue and redeem become live after signing in with a real staff account on a connected Firebase runtime.',
                color: Color(0xFFFFF2D8),
              ),
            ],
            const SizedBox(height: 16),
            IndexedStack(
              index: _selectedIndex,
              children: [
                _StaffDashboardTab(
                  workspace: staff,
                  canRunLedgerActions:
                      canRunLedgerActions && !_submittingAction,
                  onOpenIssueAction: () {
                    setState(() {
                      _selectedIndex = 1;
                    });
                  },
                  onOpenRedeemAction: () {
                    setState(() {
                      _selectedIndex = 1;
                    });
                  },
                  onOpenSharedCheckoutAction: () {
                    setState(() {
                      _selectedIndex = 1;
                    });
                  },
                  onFinalizeSharedCheckout: _finalizeSharedCheckout,
                ),
                _ScanTab(
                  workspace: staff,
                  identifierController: _identifierController,
                  phoneController: _phoneController,
                  amountController: _amountController,
                  ticketRefController: _ticketRefController,
                  resolvedCustomerIdentifier: _resolvedCustomerIdentifier,
                  canRunLedgerActions: canRunLedgerActions,
                  actionInProgress: _submittingAction,
                  onResolveIdentifier: _handleResolveCustomerIdentifier,
                  onClearResolvedIdentifier: _clearResolvedCustomerIdentifier,
                  onIssueCashback: _submittingAction
                      ? null
                      : () => _handleIssueCashback(staff),
                  onRedeemCashback: _submittingAction
                      ? null
                      : () => _handleRedeemCashback(staff),
                  onManageSharedCheckout: _submittingAction
                      ? null
                      : () => _handleSharedCheckout(staff),
                ),
                _ProfileTab(
                  workspace: staff,
                  canEditProfile: canRunLedgerActions,
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
            icon: Icon(Icons.insights_outlined),
            selectedIcon: Icon(Icons.insights),
            label: 'Dashboard',
          ),
          NavigationDestination(
            icon: Icon(Icons.qr_code_scanner_outlined),
            selectedIcon: Icon(Icons.qr_code_scanner),
            label: 'Scan',
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
    StaffWorkspace staff,
  ) async {
    await showNotificationCenterBottomSheet(
      context: context,
      title: 'Staff notifications',
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
        _openStaffNotification(notification, staff);
      },
    );
  }

  void _openStaffNotification(
    AppNotificationItem notification,
    StaffWorkspace staff,
  ) {
    final route = notification.actionRoute?.trim();
    if (route != null && route.isNotEmpty && route != '/staff') {
      context.go(route);
      return;
    }

    setState(() {
      _selectedIndex = _staffTabForNotification(notification, staff);
    });
  }

  int _staffTabForNotification(
    AppNotificationItem notification,
    StaffWorkspace staff,
  ) {
    switch (notification.type) {
      case 'staff_assignment':
        return 2;
      case 'shared_checkout_created':
      case 'shared_checkout_contribution':
      case 'shared_checkout_finalized':
        return 0;
      case 'cashback_issued':
      case 'cashback_redeemed':
      case 'cashback_refunded':
      case 'cashback_expired':
      case 'admin_adjustment':
        return notification.businessId == staff.businessId ? 0 : 2;
      default:
        return 0;
    }
  }

  Future<void> _handleResolveCustomerIdentifier() async {
    final rawInput = _identifierController.text.trim();
    if (rawInput.isEmpty) {
      _showSnackBar(
        'Paste the TeamCash QR payload or type the customer phone number.',
      );
      return;
    }

    try {
      final resolved = ref
          .read(customerIdentityTokenServiceProvider)
          .resolveForStaffInput(rawInput);
      setState(() {
        _resolvedCustomerIdentifier = resolved;
        _phoneController.text = resolved.phoneE164;
      });
      _showSnackBar(
        resolved.cameFromQr
            ? 'Client ID resolved. Phone number has been filled for the live operator flow.'
            : 'Phone number normalized for live operator flow.',
      );
    } on FormatException catch (error) {
      _showSnackBar(error.message);
    } catch (error) {
      _showSnackBar(error.toString());
    }
  }

  void _clearResolvedCustomerIdentifier() {
    setState(() {
      _identifierController.clear();
      _resolvedCustomerIdentifier = null;
    });
  }

  Future<void> _handleIssueCashback(StaffWorkspace staff) async {
    final paidMinorUnits = int.tryParse(_amountController.text.trim());
    if (paidMinorUnits == null || paidMinorUnits <= 0) {
      _showSnackBar('Paid amount must be a positive whole number.');
      return;
    }

    if (_ticketRefController.text.trim().isEmpty) {
      _showSnackBar('Ticket reference is required.');
      return;
    }

    setState(() {
      _submittingAction = true;
    });

    try {
      final result = await ref
          .read(teamCashFunctionsServiceProvider)
          .issueCashback(
            businessId: staff.businessId,
            groupId: staff.groupId,
            customerPhoneE164: _phoneController.text.trim(),
            paidMinorUnits: paidMinorUnits,
            cashbackBasisPoints: staff.cashbackBasisPoints,
            sourceTicketRef: _ticketRefController.text.trim(),
          );

      _showSnackBar(
        'Issued ${formatCurrency(result.issuedMinorUnits)}. Event ${result.eventId}',
      );
      ref.invalidate(staffWorkspaceProvider);
    } catch (error) {
      _showSnackBar(error.toString());
    } finally {
      if (mounted) {
        setState(() {
          _submittingAction = false;
        });
      }
    }
  }

  Future<void> _handleRedeemCashback(StaffWorkspace staff) async {
    final redeemMinorUnits = int.tryParse(_amountController.text.trim());
    if (redeemMinorUnits == null || redeemMinorUnits <= 0) {
      _showSnackBar('Redeem amount must be a positive whole number.');
      return;
    }

    if (_ticketRefController.text.trim().isEmpty) {
      _showSnackBar('Ticket reference is required.');
      return;
    }

    setState(() {
      _submittingAction = true;
    });

    try {
      final result = await ref
          .read(teamCashFunctionsServiceProvider)
          .redeemCashback(
            businessId: staff.businessId,
            groupId: staff.groupId,
            redeemMinorUnits: redeemMinorUnits,
            sourceTicketRef: _ticketRefController.text.trim(),
            customerPhoneE164: _phoneController.text.trim(),
          );

      _showSnackBar(
        'Redeemed ${formatCurrency(result.redeemedMinorUnits)} across ${result.consumedLotsCount} lot(s).',
      );
      ref.invalidate(staffWorkspaceProvider);
    } catch (error) {
      _showSnackBar(error.toString());
    } finally {
      if (mounted) {
        setState(() {
          _submittingAction = false;
        });
      }
    }
  }

  Future<void> _handleSharedCheckout(StaffWorkspace staff) async {
    final action = await showDialog<_SharedCheckoutAction>(
      context: context,
      builder: (context) => const _SharedCheckoutActionDialog(),
    );

    if (action == null) {
      return;
    }
    if (!context.mounted) {
      return;
    }

    switch (action) {
      case _SharedCheckoutAction.create:
        await _createSharedCheckout(staff);
      case _SharedCheckoutAction.finalize:
        await _finalizeSharedCheckout();
    }
  }

  Future<void> _createSharedCheckout(StaffWorkspace staff) async {
    final payload = await showDialog<_CreateSharedCheckoutPayload>(
      context: context,
      builder: (context) => _CreateSharedCheckoutDialog(
        defaultAmount: _amountController.text.trim(),
        defaultTicketRef: _ticketRefController.text.trim(),
      ),
    );

    if (payload == null) {
      return;
    }

    setState(() {
      _submittingAction = true;
    });

    try {
      final result = await ref
          .read(teamCashFunctionsServiceProvider)
          .createSharedCheckout(
            businessId: staff.businessId,
            groupId: staff.groupId,
            totalMinorUnits: payload.totalMinorUnits,
            sourceTicketRef: payload.sourceTicketRef,
          );

      _showSnackBar(
        'Shared checkout opened. Checkout id: ${result.checkoutId}. Remaining ${formatCurrency(result.remainingMinorUnits)}.',
      );
      ref.invalidate(staffWorkspaceProvider);
    } catch (error) {
      _showSnackBar(error.toString());
    } finally {
      if (mounted) {
        setState(() {
          _submittingAction = false;
        });
      }
    }
  }

  Future<void> _finalizeSharedCheckout([String? seededCheckoutId]) async {
    final checkoutId =
        seededCheckoutId ??
        await showDialog<String>(
          context: context,
          builder: (context) => const _FinalizeSharedCheckoutDialog(),
        );

    if (checkoutId == null || checkoutId.trim().isEmpty) {
      return;
    }

    setState(() {
      _submittingAction = true;
    });

    try {
      final result = await ref
          .read(teamCashFunctionsServiceProvider)
          .finalizeSharedCheckout(checkoutId: checkoutId.trim());

      _showSnackBar(
        result.status == 'finalized'
            ? 'Shared checkout finalized. Redeemed ${formatCurrency(result.contributedMinorUnits)}.'
            : 'Shared checkout still open. Remaining ${formatCurrency(result.remainingMinorUnits)} after expiry reconciliation.',
      );
      ref.invalidate(staffWorkspaceProvider);
    } catch (error) {
      _showSnackBar(error.toString());
    } finally {
      if (mounted) {
        setState(() {
          _submittingAction = false;
        });
      }
    }
  }

  void _showSnackBar(String message) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

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

class _ScanTab extends StatelessWidget {
  const _ScanTab({
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
  final Future<void> Function()? onResolveIdentifier;
  final VoidCallback onClearResolvedIdentifier;
  final Future<void> Function()? onIssueCashback;
  final Future<void> Function()? onRedeemCashback;
  final Future<void> Function()? onManageSharedCheckout;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey('staff-scan-section'),
      children: [
        const SectionCard(
          title: 'Chrome-safe operation mode',
          child: InfoBanner(
            title: 'Mobile-first scan, Chrome-safe fallback',
            message:
                'The same customer resolver will power mobile camera scanning later. While Chrome is the active dev target, staff can paste the TeamCash QR payload or fall back to manual phone entry without blocking ledger work.',
          ),
        ),
        const SizedBox(height: 16),
        SectionCard(
          title: 'Customer action',
          subtitle:
              'Identification stays separate from the ledger mutation itself. Once the customer is resolved, issue, redeem, and shared checkout still run through server-authoritative Cloud Functions.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                key: const ValueKey('staff-customer-identifier-input'),
                controller: identifierController,
                decoration: const InputDecoration(
                  labelText: 'Client QR payload or phone',
                  hintText: 'teamcash://customer/... or +998901234567',
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  FilledButton.tonalIcon(
                    key: const ValueKey('staff-customer-identifier-resolve'),
                    onPressed: !actionInProgress
                        ? () => onResolveIdentifier?.call()
                        : null,
                    icon: const Icon(Icons.qr_code_2_outlined),
                    label: const Text('Resolve client ID'),
                  ),
                  OutlinedButton.icon(
                    key: const ValueKey('staff-customer-identifier-clear'),
                    onPressed: !actionInProgress
                        ? onClearResolvedIdentifier
                        : null,
                    icon: const Icon(Icons.refresh_outlined),
                    label: const Text('Clear'),
                  ),
                ],
              ),
              if (resolvedCustomerIdentifier != null) ...[
                const SizedBox(height: 12),
                ResolvedCustomerIdentityCard(
                  identifier: resolvedCustomerIdentifier!,
                  onClear: onClearResolvedIdentifier,
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('staff-customer-phone-input'),
                controller: phoneController,
                decoration: const InputDecoration(
                  labelText: 'Customer phone number',
                  hintText: '+998 90 123 45 67',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('staff-amount-input'),
                controller: amountController,
                decoration: const InputDecoration(
                  labelText: 'Amount',
                  hintText: '49000',
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('staff-ticket-ref-input'),
                controller: ticketRefController,
                decoration: const InputDecoration(
                  labelText: 'Ticket reference',
                  hintText: 'SR-2201',
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Business ${workspace.businessName} • Group ${workspace.groupId} • ${formatPercent(workspace.cashbackBasisPoints)} cashback',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: const Color(0xFF52606D),
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  FilledButton.icon(
                    key: const ValueKey('staff-issue-submit'),
                    onPressed: canRunLedgerActions && !actionInProgress
                        ? () => onIssueCashback?.call()
                        : null,
                    icon: actionInProgress
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.add_card_outlined),
                    label: const Text('Issue cashback'),
                  ),
                  OutlinedButton.icon(
                    key: const ValueKey('staff-redeem-submit'),
                    onPressed: canRunLedgerActions && !actionInProgress
                        ? () => onRedeemCashback?.call()
                        : null,
                    icon: const Icon(Icons.remove_circle_outline),
                    label: const Text('Redeem'),
                  ),
                  OutlinedButton.icon(
                    key: const ValueKey('staff-shared-checkout-submit'),
                    onPressed: canRunLedgerActions && !actionInProgress
                        ? () => onManageSharedCheckout?.call()
                        : null,
                    icon: const Icon(Icons.groups_outlined),
                    label: const Text('Shared checkout'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

enum _SharedCheckoutAction { create, finalize }

class _CreateSharedCheckoutPayload {
  const _CreateSharedCheckoutPayload({
    required this.totalMinorUnits,
    required this.sourceTicketRef,
  });

  final int totalMinorUnits;
  final String sourceTicketRef;
}

class _SharedCheckoutActionDialog extends StatelessWidget {
  const _SharedCheckoutActionDialog();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Shared checkout'),
      content: const Text(
        'Open a new shared checkout or finalize an existing contribution session.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        OutlinedButton(
          key: const ValueKey('staff-shared-checkout-finalize-existing'),
          onPressed: () =>
              Navigator.of(context).pop(_SharedCheckoutAction.finalize),
          child: const Text('Finalize existing'),
        ),
        FilledButton(
          key: const ValueKey('staff-shared-checkout-open-new'),
          onPressed: () =>
              Navigator.of(context).pop(_SharedCheckoutAction.create),
          child: const Text('Open new'),
        ),
      ],
    );
  }
}

class _CreateSharedCheckoutDialog extends StatefulWidget {
  const _CreateSharedCheckoutDialog({
    required this.defaultAmount,
    required this.defaultTicketRef,
  });

  final String defaultAmount;
  final String defaultTicketRef;

  @override
  State<_CreateSharedCheckoutDialog> createState() =>
      _CreateSharedCheckoutDialogState();
}

class _CreateSharedCheckoutDialogState
    extends State<_CreateSharedCheckoutDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amountController;
  late final TextEditingController _ticketRefController;

  @override
  void initState() {
    super.initState();
    _amountController = TextEditingController(text: widget.defaultAmount);
    _ticketRefController = TextEditingController(text: widget.defaultTicketRef);
  }

  @override
  void dispose() {
    _amountController.dispose();
    _ticketRefController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Open shared checkout'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                key: const ValueKey('staff-shared-checkout-total-input'),
                controller: _amountController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Checkout total',
                  hintText: '180000',
                ),
                validator: (value) {
                  final parsed = int.tryParse(value?.trim() ?? '');
                  if (parsed == null || parsed <= 0) {
                    return 'Enter a positive whole amount.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const ValueKey('staff-shared-checkout-ticket-input'),
                controller: _ticketRefController,
                decoration: const InputDecoration(
                  labelText: 'Ticket reference',
                  hintText: 'SR-2201',
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Ticket reference is required.';
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
          key: const ValueKey('staff-shared-checkout-open-submit'),
          onPressed: () {
            if (!_formKey.currentState!.validate()) {
              return;
            }

            Navigator.of(context).pop(
              _CreateSharedCheckoutPayload(
                totalMinorUnits: int.parse(_amountController.text.trim()),
                sourceTicketRef: _ticketRefController.text.trim(),
              ),
            );
          },
          child: const Text('Open'),
        ),
      ],
    );
  }
}

class _FinalizeSharedCheckoutDialog extends StatefulWidget {
  const _FinalizeSharedCheckoutDialog();

  @override
  State<_FinalizeSharedCheckoutDialog> createState() =>
      _FinalizeSharedCheckoutDialogState();
}

class _FinalizeSharedCheckoutDialogState
    extends State<_FinalizeSharedCheckoutDialog> {
  final _formKey = GlobalKey<FormState>();
  final _checkoutIdController = TextEditingController();

  @override
  void dispose() {
    _checkoutIdController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Finalize shared checkout'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: TextFormField(
            controller: _checkoutIdController,
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

            Navigator.of(context).pop(_checkoutIdController.text.trim());
          },
          child: const Text('Finalize'),
        ),
      ],
    );
  }
}

class _ProfileTab extends ConsumerStatefulWidget {
  const _ProfileTab({required this.workspace, required this.canEditProfile});

  final StaffWorkspace workspace;
  final bool canEditProfile;

  @override
  ConsumerState<_ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends ConsumerState<_ProfileTab> {
  bool _savingProfile = false;
  bool _changingPassword = false;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      key: const ValueKey('staff-profile-section'),
      title: widget.workspace.staffName,
      subtitle: widget.workspace.businessName,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _ProfileRow(
            label: 'Access scope',
            value: 'Single business only',
          ),
          _ProfileRow(
            label: 'Preferred start tab',
            value: _staffTabLabel(widget.workspace.preferredStartTabIndex),
          ),
          _ProfileRow(
            label: 'Notification digest',
            value: widget.workspace.notificationDigestOptIn
                ? 'Enabled'
                : 'Disabled',
          ),
          const _ProfileRow(
            label: 'Password policy',
            value:
                'Owner resets are supported, and staff self-service password change is now available for web testing.',
          ),
          const _ProfileRow(
            label: 'Deletion mode',
            value: 'Soft disable only for audit retention',
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.tonalIcon(
                key: const ValueKey('staff-profile-edit-action'),
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
              OutlinedButton.icon(
                key: const ValueKey('staff-profile-change-password-action'),
                onPressed: widget.canEditProfile && !_changingPassword
                    ? _changePassword
                    : null,
                icon: _changingPassword
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.password_outlined),
                label: const Text('Change password'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _editProfile() async {
    final payload = await showDialog<_StaffProfilePayload>(
      context: context,
      builder: (context) => _StaffProfileDialog(
        initialDisplayName: widget.workspace.staffName,
        initialPreferredTabIndex: widget.workspace.preferredStartTabIndex,
        initialNotificationDigestOptIn:
            widget.workspace.notificationDigestOptIn,
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
          .updateCurrentOperatorProfile(
            displayName: payload.displayName,
            preferredStartTab: _staffTabPreferenceValue(
              payload.preferredTabIndex,
            ),
            notificationDigestOptIn: payload.notificationDigestOptIn,
          );
      await ref
          .read(appSessionControllerProvider.notifier)
          .refreshCurrentSession();
      ref.invalidate(staffWorkspaceProvider);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Staff profile updated.')));
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

  Future<void> _changePassword() async {
    final payload = await showDialog<_StaffPasswordPayload>(
      context: context,
      builder: (context) => const _StaffPasswordDialog(),
    );
    if (payload == null) {
      return;
    }

    setState(() {
      _changingPassword = true;
    });

    try {
      await ref
          .read(accountProfileServiceProvider)
          .changeCurrentOperatorPassword(
            currentPassword: payload.currentPassword,
            newPassword: payload.newPassword,
          );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Password updated for this staff account.'),
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
          _changingPassword = false;
        });
      }
    }
  }
}

class _ProfileRow extends StatelessWidget {
  const _ProfileRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: const Color(0xFF52606D)),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: Theme.of(
                context,
              ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _StaffProfilePayload {
  const _StaffProfilePayload({
    required this.displayName,
    required this.preferredTabIndex,
    required this.notificationDigestOptIn,
  });

  final String displayName;
  final int preferredTabIndex;
  final bool notificationDigestOptIn;
}

class _StaffProfileDialog extends StatefulWidget {
  const _StaffProfileDialog({
    required this.initialDisplayName,
    required this.initialPreferredTabIndex,
    required this.initialNotificationDigestOptIn,
  });

  final String initialDisplayName;
  final int initialPreferredTabIndex;
  final bool initialNotificationDigestOptIn;

  @override
  State<_StaffProfileDialog> createState() => _StaffProfileDialogState();
}

class _StaffProfileDialogState extends State<_StaffProfileDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _displayNameController;
  late int _preferredTabIndex;
  late bool _notificationDigestOptIn;

  @override
  void initState() {
    super.initState();
    _displayNameController = TextEditingController(
      text: widget.initialDisplayName,
    );
    _preferredTabIndex = widget.initialPreferredTabIndex;
    _notificationDigestOptIn = widget.initialNotificationDigestOptIn;
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit staff profile'),
      content: SizedBox(
        width: 440,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                key: const ValueKey('staff-profile-display-name-input'),
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
                key: const ValueKey('staff-profile-preferred-tab-input'),
                initialValue: _preferredTabIndex,
                decoration: const InputDecoration(
                  labelText: 'Preferred start tab',
                ),
                items: List<DropdownMenuItem<int>>.generate(
                  3,
                  (index) => DropdownMenuItem<int>(
                    value: index,
                    child: Text(_staffTabLabel(index)),
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
                key: const ValueKey('staff-profile-notification-toggle'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Receive notification digest'),
                subtitle: const Text(
                  'Keeps the operator informed about tandem actions that need attention.',
                ),
                value: _notificationDigestOptIn,
                onChanged: (value) {
                  setState(() {
                    _notificationDigestOptIn = value;
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
          key: const ValueKey('staff-profile-save-submit'),
          onPressed: () {
            if (!_formKey.currentState!.validate()) {
              return;
            }

            Navigator.of(context).pop(
              _StaffProfilePayload(
                displayName: _displayNameController.text.trim(),
                preferredTabIndex: _preferredTabIndex,
                notificationDigestOptIn: _notificationDigestOptIn,
              ),
            );
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _StaffPasswordPayload {
  const _StaffPasswordPayload({
    required this.currentPassword,
    required this.newPassword,
  });

  final String currentPassword;
  final String newPassword;
}

class _StaffPasswordDialog extends StatefulWidget {
  const _StaffPasswordDialog();

  @override
  State<_StaffPasswordDialog> createState() => _StaffPasswordDialogState();
}

class _StaffPasswordDialogState extends State<_StaffPasswordDialog> {
  final _formKey = GlobalKey<FormState>();
  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _obscureCurrentPassword = true;
  bool _obscureNewPassword = true;
  bool _obscureConfirmPassword = true;

  @override
  void dispose() {
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Change password'),
      content: SizedBox(
        width: 460,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                key: const ValueKey('staff-password-current-input'),
                controller: _currentPasswordController,
                obscureText: _obscureCurrentPassword,
                decoration: InputDecoration(
                  labelText: 'Current password',
                  suffixIcon: IconButton(
                    onPressed: () {
                      setState(() {
                        _obscureCurrentPassword = !_obscureCurrentPassword;
                      });
                    },
                    icon: Icon(
                      _obscureCurrentPassword
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                  ),
                ),
                validator: _required,
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const ValueKey('staff-password-new-input'),
                controller: _newPasswordController,
                obscureText: _obscureNewPassword,
                decoration: InputDecoration(
                  labelText: 'New password',
                  helperText: 'At least 8 characters.',
                  suffixIcon: IconButton(
                    onPressed: () {
                      setState(() {
                        _obscureNewPassword = !_obscureNewPassword;
                      });
                    },
                    icon: Icon(
                      _obscureNewPassword
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                  ),
                ),
                validator: (value) {
                  final trimmed = value?.trim() ?? '';
                  if (trimmed.length < 8) {
                    return 'Use at least 8 characters.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const ValueKey('staff-password-confirm-input'),
                controller: _confirmPasswordController,
                obscureText: _obscureConfirmPassword,
                decoration: InputDecoration(
                  labelText: 'Confirm new password',
                  suffixIcon: IconButton(
                    onPressed: () {
                      setState(() {
                        _obscureConfirmPassword = !_obscureConfirmPassword;
                      });
                    },
                    icon: Icon(
                      _obscureConfirmPassword
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                  ),
                ),
                validator: (value) {
                  if ((value?.trim() ?? '') !=
                      _newPasswordController.text.trim()) {
                    return 'Passwords do not match.';
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
          key: const ValueKey('staff-password-save-submit'),
          onPressed: () {
            if (!_formKey.currentState!.validate()) {
              return;
            }

            Navigator.of(context).pop(
              _StaffPasswordPayload(
                currentPassword: _currentPasswordController.text.trim(),
                newPassword: _newPasswordController.text.trim(),
              ),
            );
          },
          child: const Text('Update password'),
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

String _staffTabLabel(int tabIndex) {
  switch (tabIndex) {
    case 0:
      return 'Dashboard';
    case 1:
      return 'Scan';
    case 2:
      return 'Profile';
    default:
      return 'Dashboard';
  }
}

String _staffTabPreferenceValue(int tabIndex) {
  switch (tabIndex) {
    case 0:
      return 'dashboard';
    case 1:
      return 'scan';
    case 2:
      return 'profile';
    default:
      return 'dashboard';
  }
}
