part of 'owner_shell.dart';

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
