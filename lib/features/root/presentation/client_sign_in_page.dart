import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:teamcash/app/app.dart';
import 'package:teamcash/app/bootstrap/firebase_bootstrap.dart';
import 'package:teamcash/core/auth/client_phone_auth_controller.dart';
import 'package:teamcash/core/models/app_role.dart';
import 'package:teamcash/core/session/session_controller.dart';
import 'package:teamcash/features/shared/presentation/shell_widgets.dart';

class ClientSignInPage extends ConsumerStatefulWidget {
  const ClientSignInPage({super.key});

  @override
  ConsumerState<ClientSignInPage> createState() => _ClientSignInPageState();
}

class _ClientSignInPageState extends ConsumerState<ClientSignInPage> {
  final _phoneController = TextEditingController();
  final _codeController = TextEditingController();

  @override
  void dispose() {
    _phoneController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bootstrap = ref.watch(firebaseStatusProvider);
    final authState = ref.watch(clientPhoneAuthControllerProvider);
    final session = ref.watch(currentSessionProvider);
    final theme = Theme.of(context);
    final hasLinkedClientSession = session?.role == AppRole.client;

    return Scaffold(
      body: AppBackdrop(
        child: SafeArea(
          child: MobileAppFrame(
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
                      gradient: const LinearGradient(
                        colors: [Color(0xFF6576FF), Color(0xFF8666FF)],
                      ),
                      borderRadius: BorderRadius.circular(22),
                    ),
                    alignment: Alignment.center,
                    child: const Icon(
                      Icons.link_rounded,
                      size: 34,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Center(
                  child: Text(
                    'Client Wallet',
                    style: theme.textTheme.headlineSmall,
                  ),
                ),
                const SizedBox(height: 6),
                Center(
                  child: Text(
                    'Claim cashback with the same number staff already used.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: _AuthRoleBadge(
                        label: 'Customer',
                        icon: Icons.person_outline_rounded,
                        selected: true,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _AuthRoleBadge(
                        label: 'Owner',
                        icon: Icons.storefront_outlined,
                        selected: false,
                        onTap: () => context.go('/sign-in/owner'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _AuthRoleBadge(
                        label: 'Staff',
                        icon: Icons.badge_outlined,
                        selected: false,
                        onTap: () => context.go('/sign-in/staff'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                InfoBanner(
                  title: bootstrap.mode == FirebaseBootstrapMode.connected
                      ? 'Phone verification is active'
                      : 'Preview client mode',
                  message: bootstrap.mode == FirebaseBootstrapMode.connected
                      ? 'Verify the same number and TeamCash will attach the older phone-first wallet to this app session.'
                      : bootstrap.message,
                  color: bootstrap.mode == FirebaseBootstrapMode.connected
                      ? const Color(0xFFE8FBF4)
                      : const Color(0xFFFFF3DF),
                  icon: bootstrap.mode == FirebaseBootstrapMode.connected
                      ? Icons.verified_user_outlined
                      : Icons.visibility_outlined,
                ),
                if (authState.statusMessage != null) ...[
                  const SizedBox(height: 10),
                  InfoBanner(
                    title: 'Phone claim status',
                    message: authState.statusMessage!,
                    color: authState.lastErrorCode == null
                        ? const Color(0xFFEFF2FF)
                        : const Color(0xFFFFF3DF),
                    icon: authState.lastErrorCode == null
                        ? Icons.sms_outlined
                        : Icons.warning_amber_rounded,
                  ),
                ],
                const SizedBox(height: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (hasLinkedClientSession) ...[
                        InfoBanner(
                          title: 'Client wallet linked',
                          message:
                              'Verified phone ${session?.phoneNumber ?? ''} is already attached to customer wallet ${session?.customerId ?? ''}.',
                          color: const Color(0xFFE8FBF4),
                          icon: Icons.account_balance_wallet_outlined,
                        ),
                        const Spacer(),
                        FilledButton(
                          onPressed: () => context.go('/client'),
                          child: const Text('Open Client Wallet'),
                        ),
                      ] else if (bootstrap.mode ==
                          FirebaseBootstrapMode.preview) ...[
                        CompactStatTile(
                          label: 'Mode',
                          value: 'Preview wallet',
                          tint: const Color(0xFF6474FF),
                          icon: Icons.visibility_outlined,
                        ),
                        const Spacer(),
                        FilledButton(
                          onPressed: () async {
                            await ref
                                .read(appSessionControllerProvider.notifier)
                                .continueInPreview(AppRole.client);
                            if (!context.mounted) return;
                            context.go('/client');
                          },
                          child: const Text('Open Preview Wallet'),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'UX fix: long preview explanation was replaced by a direct path into the wallet.',
                          style: theme.textTheme.bodySmall,
                        ),
                      ] else if (authState.hasVerifiedPhoneUser) ...[
                        InfoBanner(
                          title: 'Verified phone detected',
                          message:
                              'Phone ${authState.verifiedPhoneNumber!} is signed in. Finish the claim to attach the older wallet history.',
                          color: const Color(0xFFE8FBF4),
                          icon: Icons.phone_android_rounded,
                        ),
                        if (authState.recoveryHint != null) ...[
                          const SizedBox(height: 10),
                          Text(
                            authState.recoveryHint!,
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                        const Spacer(),
                        FilledButton(
                          onPressed: authState.isSubmitting
                              ? null
                              : _claimExistingWallet,
                          child: authState.isSubmitting
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text('Claim Wallet History'),
                        ),
                        const SizedBox(height: 10),
                        OutlinedButton(
                          onPressed: authState.isSubmitting
                              ? null
                              : _useAnotherNumber,
                          child: const Text('Use Another Number'),
                        ),
                      ] else ...[
                        TextField(
                          key: const ValueKey('client-auth-phone-input'),
                          controller: _phoneController,
                          keyboardType: TextInputType.phone,
                          decoration: const InputDecoration(
                            labelText: 'Phone number',
                            hintText: '+998901234567',
                          ),
                        ),
                        if (authState.isAwaitingCode) ...[
                          const SizedBox(height: 12),
                          TextField(
                            key: const ValueKey('client-auth-code-input'),
                            controller: _codeController,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              LengthLimitingTextInputFormatter(6),
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            decoration: InputDecoration(
                              labelText: 'SMS code',
                              hintText: '123456',
                              helperText:
                                  '${authState.normalizedPhone ?? 'your number'} • attempt ${authState.attemptCount}',
                            ),
                          ),
                        ],
                        const SizedBox(height: 10),
                        Text(
                          authState.isAwaitingCode
                              ? 'Second step appears only after the code is sent, reducing initial input load on mobile.'
                              : 'UX fix: first screen asks only for the phone number, so the client is not overloaded.',
                          style: theme.textTheme.bodySmall,
                        ),
                        const Spacer(),
                        if (!authState.isAwaitingCode)
                          FilledButton(
                            key: const ValueKey('client-auth-send-code'),
                            onPressed: authState.isSubmitting ? null : _sendCode,
                            child: authState.isSubmitting
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Text('Send SMS Code'),
                          )
                        else ...[
                          FilledButton(
                            key: const ValueKey('client-auth-verify-code'),
                            onPressed: authState.isSubmitting
                                ? null
                                : _verifyCode,
                            child: authState.isSubmitting
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Text('Verify and Claim Wallet'),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  key: const ValueKey(
                                    'client-auth-change-number',
                                  ),
                                  onPressed: authState.isSubmitting
                                      ? null
                                      : _useAnotherNumber,
                                  child: const Text('Change Number'),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _ResendCodeButton(
                                  codeSentAt: authState.codeSentAt,
                                  attemptCount: authState.attemptCount,
                                  isSubmitting: authState.isSubmitting,
                                  onResend: _resendCode,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _sendCode() async {
    try {
      await ref
          .read(clientPhoneAuthControllerProvider.notifier)
          .startWebPhoneSignIn(_phoneController.text);
    } catch (error) {
      _showSnackBar(error.toString());
    }
  }

  Future<void> _verifyCode() async {
    try {
      await ref
          .read(clientPhoneAuthControllerProvider.notifier)
          .confirmSmsCode(_codeController.text);
      if (!mounted) return;
      context.go('/client');
    } catch (error) {
      _showSnackBar(error.toString());
    }
  }

  Future<void> _resendCode() async {
    try {
      await ref
          .read(clientPhoneAuthControllerProvider.notifier)
          .resendSmsCode();
    } catch (error) {
      _showSnackBar(error.toString());
    }
  }

  Future<void> _claimExistingWallet() async {
    try {
      await ref
          .read(clientPhoneAuthControllerProvider.notifier)
          .claimCurrentVerifiedPhone();
      if (!mounted) return;
      context.go('/client');
    } catch (error) {
      _showSnackBar(error.toString());
    }
  }

  Future<void> _useAnotherNumber() async {
    try {
      await ref
          .read(clientPhoneAuthControllerProvider.notifier)
          .abandonCurrentAttempt();
      _phoneController.clear();
      _codeController.clear();
    } catch (error) {
      _showSnackBar(error.toString());
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

class _AuthRoleBadge extends StatelessWidget {
  const _AuthRoleBadge({
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

class _ResendCodeButton extends StatefulWidget {
  const _ResendCodeButton({
    required this.codeSentAt,
    required this.attemptCount,
    required this.isSubmitting,
    required this.onResend,
  });

  final DateTime? codeSentAt;
  final int attemptCount;
  final bool isSubmitting;
  final Future<void> Function() onResend;

  @override
  State<_ResendCodeButton> createState() => _ResendCodeButtonState();
}

class _ResendCodeButtonState extends State<_ResendCodeButton> {
  static const _resendCooldown = Duration(seconds: 30);
  Timer? _timer;

  @override
  void didUpdateWidget(covariant _ResendCodeButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.codeSentAt != widget.codeSentAt) {
      _restartTimerIfNeeded();
    }
  }

  @override
  void initState() {
    super.initState();
    _restartTimerIfNeeded();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final remainingSeconds = _secondsRemaining;
    final canResend =
        !widget.isSubmitting &&
        widget.codeSentAt != null &&
        remainingSeconds == 0;

    return FilledButton.tonalIcon(
      key: const ValueKey('client-auth-resend-code'),
      onPressed: canResend
          ? () async {
              await widget.onResend();
              if (mounted) {
                setState(() {});
              }
            }
          : null,
      icon: const Icon(Icons.refresh_outlined),
      label: Text(
        canResend
            ? 'Resend code'
            : widget.codeSentAt == null
            ? 'Send a code first'
            : 'Resend in ${remainingSeconds}s',
      ),
    );
  }

  int get _secondsRemaining {
    final sentAt = widget.codeSentAt;
    if (sentAt == null) {
      return 0;
    }
    final elapsed = DateTime.now().difference(sentAt);
    final remaining = _resendCooldown.inSeconds - elapsed.inSeconds;
    if (remaining <= 0) {
      return 0;
    }
    return remaining;
  }

  void _restartTimerIfNeeded() {
    _timer?.cancel();
    if (widget.codeSentAt == null) {
      return;
    }

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      if (_secondsRemaining == 0) {
        timer.cancel();
      }
      setState(() {});
    });
  }
}
