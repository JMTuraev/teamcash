part of 'staff_shell.dart';

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
