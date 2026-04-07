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
      appBar: AppBar(title: const Text('Client phone verification')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                SectionCard(
                  title: 'Claim your existing cashback history',
                  subtitle:
                      'Staff can issue cashback before the app is installed. Once the same phone number is verified, the phone-first wallet is claimed into the client surface.',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      InfoBanner(
                        title: bootstrap.mode == FirebaseBootstrapMode.connected
                            ? 'Firebase runtime connected'
                            : 'Preview runtime active',
                        message: bootstrap.message,
                        color: bootstrap.mode == FirebaseBootstrapMode.connected
                            ? const Color(0xFFE7F5EF)
                            : const Color(0xFFFFF2D8),
                      ),
                      const SizedBox(height: 16),
                      if (authState.statusMessage != null) ...[
                        InfoBanner(
                          title: 'Phone claim status',
                          message: authState.statusMessage!,
                          color: authState.lastErrorCode == null
                              ? const Color(0xFFEFF4FF)
                              : const Color(0xFFFFF2D8),
                        ),
                        const SizedBox(height: 16),
                      ],
                      if (authState.recoveryHint != null) ...[
                        InfoBanner(
                          title: 'Recovery hint',
                          message: authState.recoveryHint!,
                          color: const Color(0xFFFFF2D8),
                        ),
                        const SizedBox(height: 16),
                      ],
                      if (hasLinkedClientSession) ...[
                        InfoBanner(
                          title: 'Client wallet linked',
                          message:
                              'Verified phone ${session?.phoneNumber ?? ''} is already attached to customer wallet ${session?.customerId ?? ''}.',
                          color: const Color(0xFFE7F5EF),
                        ),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: () => context.go('/client'),
                          icon: const Icon(
                            Icons.account_balance_wallet_outlined,
                          ),
                          label: const Text('Open client wallet'),
                        ),
                      ] else if (bootstrap.mode ==
                          FirebaseBootstrapMode.preview) ...[
                        FilledButton.icon(
                          onPressed: () async {
                            await ref
                                .read(appSessionControllerProvider.notifier)
                                .continueInPreview(AppRole.client);
                            if (!context.mounted) return;
                            context.go('/client');
                          },
                          icon: const Icon(Icons.visibility_outlined),
                          label: const Text('Open preview wallet'),
                        ),
                      ] else ...[
                        if (authState.hasVerifiedPhoneUser) ...[
                          InfoBanner(
                            title: 'Verified phone detected',
                            message:
                                'Phone ${authState.verifiedPhoneNumber!} is signed in. Finish the claim step to attach existing shadow-wallet history.',
                            color: const Color(0xFFE7F5EF),
                          ),
                          const SizedBox(height: 16),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              FilledButton.icon(
                                onPressed: authState.isSubmitting
                                    ? null
                                    : _claimExistingWallet,
                                icon: authState.isSubmitting
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.verified_user_outlined),
                                label: const Text('Claim wallet history'),
                              ),
                              OutlinedButton(
                                onPressed: authState.isSubmitting
                                    ? null
                                    : _useAnotherNumber,
                                child: const Text('Use another number'),
                              ),
                            ],
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
                          const SizedBox(height: 16),
                          FilledButton.icon(
                            key: const ValueKey('client-auth-send-code'),
                            onPressed: authState.isSubmitting
                                ? null
                                : _sendCode,
                            icon: authState.isSubmitting
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.sms_outlined),
                            label: const Text('Send SMS code'),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Use the same phone number that staff used when issuing cashback before you installed the app.',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: const Color(0xFF52606D),
                            ),
                          ),
                          if (authState.isAwaitingCode) ...[
                            const SizedBox(height: 20),
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
                                    'Sent to ${authState.normalizedPhone ?? 'your verified number'} • attempt ${authState.attemptCount}',
                              ),
                            ),
                            const SizedBox(height: 16),
                            Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              children: [
                                FilledButton.icon(
                                  key: const ValueKey(
                                    'client-auth-verify-code',
                                  ),
                                  onPressed: authState.isSubmitting
                                      ? null
                                      : _verifyCode,
                                  icon: authState.isSubmitting
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(Icons.verified_outlined),
                                  label: const Text('Verify and claim wallet'),
                                ),
                                OutlinedButton(
                                  key: const ValueKey(
                                    'client-auth-change-number',
                                  ),
                                  onPressed: authState.isSubmitting
                                      ? null
                                      : _useAnotherNumber,
                                  child: const Text('Change number'),
                                ),
                                _ResendCodeButton(
                                  codeSentAt: authState.codeSentAt,
                                  attemptCount: authState.attemptCount,
                                  isSubmitting: authState.isSubmitting,
                                  onResend: _resendCode,
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Chrome/web remains the active verification target for now. Mobile-native SMS polish will layer onto the same phone-first claim flow later.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: const Color(0xFF6B7280),
                              ),
                            ),
                          ],
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
