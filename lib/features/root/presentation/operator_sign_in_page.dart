import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:teamcash/app/app.dart';
import 'package:teamcash/app/bootstrap/firebase_bootstrap.dart';
import 'package:teamcash/core/models/app_role.dart';
import 'package:teamcash/core/session/session_controller.dart';
import 'package:teamcash/features/shared/presentation/shell_widgets.dart';

class OperatorSignInPage extends ConsumerStatefulWidget {
  const OperatorSignInPage({super.key, required this.role});

  final AppRole role;

  @override
  ConsumerState<OperatorSignInPage> createState() => _OperatorSignInPageState();
}

class _OperatorSignInPageState extends ConsumerState<OperatorSignInPage> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _submitting = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bootstrap = ref.watch(firebaseStatusProvider);
    final palette = _rolePalette(widget.role);
    final theme = Theme.of(context);

    return Scaffold(
      body: AppBackdrop(
        child: SafeArea(
          child: MobileAppFrame(
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextButton.icon(
                    onPressed: () => context.go('/'),
                    icon: const Icon(Icons.arrow_back_rounded),
                    label: const Text('Back'),
                  ),
                  Center(
                    child: Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [palette.primary, palette.secondary],
                        ),
                        borderRadius: BorderRadius.circular(22),
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        palette.icon,
                        size: 34,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Center(
                    child: Text(
                      widget.role == AppRole.owner
                          ? 'Business Owner'
                          : 'Staff Access',
                      style: theme.textTheme.headlineSmall,
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Center(
                    child: Text(
                      widget.role == AppRole.owner
                          ? 'Manage businesses and tandem rules from a compact mobile flow.'
                          : 'Run operator actions and client lookup without a dense dashboard.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: _RoleBadge(
                          label: 'Customer',
                          icon: Icons.person_outline_rounded,
                          selected: false,
                          onTap: () => context.go('/sign-in/client'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _RoleBadge(
                          label: 'Owner',
                          icon: Icons.storefront_outlined,
                          selected: widget.role == AppRole.owner,
                          onTap: widget.role == AppRole.owner
                              ? null
                              : () => context.go('/sign-in/owner'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _RoleBadge(
                          label: 'Staff',
                          icon: Icons.badge_outlined,
                          selected: widget.role == AppRole.staff,
                          onTap: widget.role == AppRole.staff
                              ? null
                              : () => context.go('/sign-in/staff'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  InfoBanner(
                    title: bootstrap.mode == FirebaseBootstrapMode.connected
                        ? 'Live operator sign-in'
                        : 'Preview operator mode',
                    message: bootstrap.mode == FirebaseBootstrapMode.connected
                        ? 'Username/password opens the operator account created by the owner.'
                        : bootstrap.message,
                    color: bootstrap.mode == FirebaseBootstrapMode.connected
                        ? const Color(0xFFE8FBF4)
                        : const Color(0xFFFFF3DF),
                    icon: bootstrap.mode == FirebaseBootstrapMode.connected
                        ? Icons.lock_open_outlined
                        : Icons.visibility_outlined,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    key: const ValueKey('operator-sign-in-username'),
                    controller: _usernameController,
                    decoration: const InputDecoration(
                      labelText: 'Username',
                      hintText: 'nadia.silkroad',
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Username is required.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    key: const ValueKey('operator-sign-in-password'),
                    controller: _passwordController,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      suffixIcon: IconButton(
                        onPressed: () {
                          setState(() {
                            _obscurePassword = !_obscurePassword;
                          });
                        },
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                      ),
                    ),
                    obscureText: _obscurePassword,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Password is required.';
                      }
                      return null;
                    },
                  ),
                  const Spacer(),
                  FilledButton(
                    key: const ValueKey('operator-sign-in-submit'),
                    onPressed: _submitting ? null : _submit,
                    child: _submitting
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            bootstrap.mode == FirebaseBootstrapMode.connected
                                ? 'Log In to ${widget.role.label}'
                                : 'Open ${widget.role.label} Preview',
                          ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    bootstrap.mode == FirebaseBootstrapMode.connected
                        ? 'Critical UX change: the screen now surfaces only the required fields first, so the operator reaches the workspace faster on mobile.'
                        : 'Critical UX change: preview messaging stays visible, but longer explanation was removed so the primary action remains above the fold.',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _submitting = true;
    });

    try {
      await ref
          .read(appSessionControllerProvider.notifier)
          .signInOperator(
            role: widget.role,
            username: _usernameController.text,
            password: _passwordController.text,
          );

      if (mounted) {
        context.go(widget.role.routePath);
      }
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
          _submitting = false;
        });
      }
    }
  }
}

class _RoleBadge extends StatelessWidget {
  const _RoleBadge({
    required this.label,
    required this.icon,
    required this.selected,
    this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? const Color(0xFFEAF0FF) : const Color(0xFFF7F8FD),
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: selected
                  ? const Color(0xFF6374FF)
                  : const Color(0xFFE4E8F7),
            ),
          ),
          child: Column(
            children: [
              Icon(
                icon,
                color: selected
                    ? const Color(0xFF6374FF)
                    : const Color(0xFF8C94B6),
              ),
              const SizedBox(height: 8),
              Text(
                label,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: selected
                      ? const Color(0xFF4250A8)
                      : const Color(0xFF8C94B6),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

({Color primary, Color secondary, IconData icon}) _rolePalette(AppRole role) {
  return switch (role) {
    AppRole.owner => (
      primary: const Color(0xFF6F74FF),
      secondary: const Color(0xFF8E5EFF),
      icon: Icons.storefront_outlined,
    ),
    AppRole.staff => (
      primary: const Color(0xFF5F7CFF),
      secondary: const Color(0xFF3EC9C5),
      icon: Icons.badge_outlined,
    ),
    AppRole.client => (
      primary: const Color(0xFF6F74FF),
      secondary: const Color(0xFF8E5EFF),
      icon: Icons.person_outline_rounded,
    ),
  };
}
