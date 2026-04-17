part of 'owner_shell.dart';

class _CreateStaffPayload {
  const _CreateStaffPayload({
    required this.displayName,
    required this.username,
    required this.password,
  });

  final String displayName;
  final String username;
  final String password;
}

class _EditStaffPayload {
  const _EditStaffPayload({required this.displayName});

  final String displayName;
}

class _ResetStaffPasswordPayload {
  const _ResetStaffPasswordPayload({required this.password});

  final String password;
}

class _CreateStaffDialog extends StatefulWidget {
  const _CreateStaffDialog({required this.businessName});

  final String businessName;

  @override
  State<_CreateStaffDialog> createState() => _CreateStaffDialogState();
}

class _CreateStaffDialogState extends State<_CreateStaffDialog> {
  final _formKey = GlobalKey<FormState>();
  final _displayNameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void dispose() {
    _displayNameController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Create staff for ${widget.businessName}'),
      content: SizedBox(
        width: 440,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _displayNameController,
                decoration: const InputDecoration(
                  labelText: 'Display name',
                  hintText: 'Nadia Rasulova',
                ),
                validator: _required,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _usernameController,
                decoration: const InputDecoration(
                  labelText: 'Username',
                  hintText: 'nadia.silkroad',
                ),
                validator: _required,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _passwordController,
                decoration: const InputDecoration(
                  labelText: 'Temporary password',
                ),
                obscureText: true,
                validator: (value) {
                  if (value == null || value.trim().length < 8) {
                    return 'Use at least 8 characters.';
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
          onPressed: () {
            if (!_formKey.currentState!.validate()) {
              return;
            }

            Navigator.of(context).pop(
              _CreateStaffPayload(
                displayName: _displayNameController.text.trim(),
                username: _usernameController.text.trim(),
                password: _passwordController.text,
              ),
            );
          },
          child: const Text('Create'),
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

class _ResetStaffPasswordDialog extends StatefulWidget {
  const _ResetStaffPasswordDialog({required this.staff});

  final StaffMemberSummary staff;

  @override
  State<_ResetStaffPasswordDialog> createState() =>
      _ResetStaffPasswordDialogState();
}

class _ResetStaffPasswordDialogState extends State<_ResetStaffPasswordDialog> {
  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Reset password for ${widget.staff.name}'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '@${widget.staff.username} · ${widget.staff.businessName}',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const ValueKey('owner-staff-reset-password-input'),
                controller: _passwordController,
                decoration: const InputDecoration(
                  labelText: 'New temporary password',
                  hintText: 'Teamcash!2026',
                ),
                obscureText: true,
                validator: (value) {
                  if (value == null || value.trim().length < 8) {
                    return 'Use at least 8 characters.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              Text(
                'Firebase Auth updates immediately. Share the new temporary password through a trusted channel.',
                style: Theme.of(context).textTheme.bodySmall,
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
          key: const ValueKey('owner-staff-reset-submit'),
          onPressed: () {
            if (!_formKey.currentState!.validate()) {
              return;
            }

            Navigator.of(context).pop(
              _ResetStaffPasswordPayload(password: _passwordController.text),
            );
          },
          child: const Text('Update password'),
        ),
      ],
    );
  }
}

class _EditStaffDialog extends StatefulWidget {
  const _EditStaffDialog({required this.staff});

  final StaffMemberSummary staff;

  @override
  State<_EditStaffDialog> createState() => _EditStaffDialogState();
}

class _EditStaffDialogState extends State<_EditStaffDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _displayNameController;

  @override
  void initState() {
    super.initState();
    _displayNameController = TextEditingController(text: widget.staff.name);
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Edit ${widget.staff.username}'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Assigned to ${widget.staff.businessName}',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const ValueKey('owner-staff-edit-display-name-input'),
                controller: _displayNameController,
                decoration: const InputDecoration(
                  labelText: 'Display name',
                  hintText: 'Nadia Rasulova',
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Display name is required.';
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
          key: const ValueKey('owner-staff-edit-submit'),
          onPressed: () {
            if (!_formKey.currentState!.validate()) {
              return;
            }

            Navigator.of(context).pop(
              _EditStaffPayload(
                displayName: _displayNameController.text.trim(),
              ),
            );
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
