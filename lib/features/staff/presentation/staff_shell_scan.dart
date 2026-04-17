part of 'staff_shell.dart';

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
