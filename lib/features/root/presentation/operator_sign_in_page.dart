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

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bootstrap = ref.watch(firebaseStatusProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text('${widget.role.label} access')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                SectionCard(
                  title: '${widget.role.label} sign in',
                  subtitle:
                      'Owner and staff use username/password login backed by Firebase Auth alias emails.',
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        InfoBanner(
                          title:
                              bootstrap.mode == FirebaseBootstrapMode.connected
                              ? 'Firebase runtime connected'
                              : 'Preview runtime active',
                          message: bootstrap.message,
                          color:
                              bootstrap.mode == FirebaseBootstrapMode.connected
                              ? const Color(0xFFE7F5EF)
                              : const Color(0xFFFFF2D8),
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
                          decoration: const InputDecoration(
                            labelText: 'Password',
                          ),
                          obscureText: true,
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Password is required.';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 18),
                        FilledButton.icon(
                          key: const ValueKey('operator-sign-in-submit'),
                          onPressed: _submitting ? null : _submit,
                          icon: _submitting
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.login),
                          label: Text(
                            bootstrap.mode == FirebaseBootstrapMode.connected
                                ? 'Sign in'
                                : 'Open preview workspace',
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          bootstrap.mode == FirebaseBootstrapMode.connected
                              ? 'Use the username created by the owner. The app maps it to a hidden Firebase-compatible alias email.'
                              : 'Preview mode keeps product work moving on Chrome even before final web auth/runtime settings are supplied.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: const Color(0xFF52606D),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
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
