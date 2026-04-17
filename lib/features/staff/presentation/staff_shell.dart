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

part 'staff_shell_mobile.dart';
part 'staff_shell_dashboard.dart';
part 'staff_shell_scan.dart';
part 'staff_shell_profile.dart';

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

    if (MediaQuery.sizeOf(context).height > 0) {
      return Scaffold(
        key: const ValueKey('staff-workspace-root'),
        body: AppBackdrop(
          child: SafeArea(
            minimum: const EdgeInsets.fromLTRB(12, 10, 12, 0),
            child: MobileAppFrame(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 16, 14, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _StaffMobileHeader(
                      staffName: staff.staffName,
                      businessName: staff.businessName,
                      unreadNotificationsCount: unreadNotificationsCount,
                      onOpenNotifications: () =>
                          _openNotificationsCenter(notifications, staff),
                      onSignOut: session?.role == AppRole.staff
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
                    _StaffMobileSummaryCard(
                      workspace: staff,
                      canRunLedgerActions: canRunLedgerActions,
                      actionInProgress: _submittingAction,
                      onOpenScan: () {
                        setState(() {
                          _selectedIndex = 1;
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: IndexedStack(
                        index: _selectedIndex,
                        children: [
                          _StaffMobileDashboardPanel(
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
                          _StaffMobileScanPanel(
                            workspace: staff,
                            identifierController: _identifierController,
                            phoneController: _phoneController,
                            amountController: _amountController,
                            ticketRefController: _ticketRefController,
                            resolvedCustomerIdentifier:
                                _resolvedCustomerIdentifier,
                            canRunLedgerActions: canRunLedgerActions,
                            actionInProgress: _submittingAction,
                            onResolveIdentifier:
                                _handleResolveCustomerIdentifier,
                            onClearResolvedIdentifier:
                                _clearResolvedCustomerIdentifier,
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
                          _StaffMobileProfilePanel(
                            workspace: staff,
                            canEditProfile: canRunLedgerActions,
                            onEditProfile: canRunLedgerActions
                                ? () => _showSnackBar(
                                    'Profile editor stays in the full workspace flow for now.',
                                  )
                                : null,
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
          ),
        ),
      );
    }

    return Scaffold(
      key: const ValueKey('staff-workspace-root'),
      extendBody: true,
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
      body: AppBackdrop(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1160),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 124),
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
                      onClearResolvedIdentifier:
                          _clearResolvedCustomerIdentifier,
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
