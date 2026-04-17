part of 'client_shell.dart';

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
    if (context.mounted) {
      return SizedBox.expand(
        child: SectionCard(
          key: const ValueKey('client-profile-section'),
          title: widget.client.clientName,
          subtitle: widget.client.phoneNumber,
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: CompactStatTile(
                      label: 'Marketing',
                      value: widget.client.marketingOptIn ? 'Enabled' : 'Off',
                      tint: const Color(0xFF45C1B2),
                      icon: Icons.campaign_outlined,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: CompactStatTile(
                      label: 'Start tab',
                      value: _clientTabLabel(
                        widget.client.preferredStartTabIndex,
                      ),
                      tint: const Color(0xFF6678FF),
                      icon: Icons.space_dashboard_outlined,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              const _ProfileLine(
                label: 'Claim status',
                value:
                    'Phone-linked wallet is ready for cashier scan, same-group transfers, and fallback payload copy.',
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.tonalIcon(
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
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 278,
                child: Align(
                  alignment: Alignment.topCenter,
                  child: CustomerIdentityQrCard(
                    token: widget.customerIdentityToken,
                    onCopyPayload: () async {
                      await Clipboard.setData(
                        ClipboardData(
                          text: widget.customerIdentityToken.qrPayload,
                        ),
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
                ),
              ),
            ],
          ),
        ),
      );
    }

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
