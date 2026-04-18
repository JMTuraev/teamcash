import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_country_selector/flutter_country_selector.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phone_form_field/phone_form_field.dart';
import 'package:phone_numbers_parser/metadata.dart';

import 'package:teamcash/app/app.dart';
import 'package:teamcash/app/bootstrap/firebase_bootstrap.dart';
import 'package:teamcash/app/theme/teamcash_icons.dart';
import 'package:teamcash/core/auth/client_phone_auth_controller.dart';
import 'package:teamcash/core/models/app_role.dart';
import 'package:teamcash/core/session/session_controller.dart';

const _actionBlue = Color(0xFF0088FF);

class ClientSignInPage extends ConsumerStatefulWidget {
  const ClientSignInPage({super.key});

  @override
  ConsumerState<ClientSignInPage> createState() => _ClientSignInPageState();
}

class _ClientSignInPageState extends ConsumerState<ClientSignInPage> {
  final _phoneController = PhoneController(
    initialValue: const PhoneNumber(isoCode: IsoCode.UZ, nsn: ''),
  );
  final _codeController = TextEditingController();
  final _phoneFocusNode = FocusNode();
  final _codeFocusNode = FocusNode();

  String? _desktopPreviewPhone;
  DateTime? _desktopPreviewCodeSentAt;

  @override
  void dispose() {
    _phoneController.dispose();
    _codeController.dispose();
    _phoneFocusNode.dispose();
    _codeFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(clientPhoneAuthControllerProvider);
    final session = ref.watch(currentSessionProvider);
    final hasLinkedClientSession = session?.role == AppRole.client;
    final isCodeStage =
        authState.isAwaitingCode || _desktopPreviewPhone != null;
    final activePhone =
        authState.normalizedPhone ?? _desktopPreviewPhone ?? _normalizeDraft();

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _TopBar(),
              const SizedBox(height: 24),
              if (hasLinkedClientSession)
                _LinkedWalletStage(
                  phoneNumber: session?.phoneNumber,
                  onOpen: () => context.go('/client'),
                )
              else if (authState.hasVerifiedPhoneUser)
                _ClaimWalletStage(
                  phoneNumber: authState.verifiedPhoneNumber,
                  isSubmitting: authState.isSubmitting,
                  onClaim: _claimExistingWallet,
                  onUseAnotherNumber: _useAnotherNumber,
                )
              else if (isCodeStage)
                Expanded(
                  child: _VerifyCodeStage(
                    phoneNumber: activePhone,
                    codeController: _codeController,
                    codeFocusNode: _codeFocusNode,
                    isSubmitting: authState.isSubmitting,
                    codeSentAt:
                        authState.codeSentAt ?? _desktopPreviewCodeSentAt,
                    errorText: authState.lastErrorCode == null
                        ? null
                        : authState.statusMessage,
                    onVerify: _verifyCode,
                    onResend: _resendCode,
                    onChangeNumber: _useAnotherNumber,
                  ),
                )
              else
                Expanded(
                  child: _PhoneEntryStage(
                    phoneController: _phoneController,
                    phoneFocusNode: _phoneFocusNode,
                    isSubmitting: authState.isSubmitting,
                    statusText: authState.lastErrorCode == null
                        ? null
                        : authState.statusMessage,
                    onOpenCountryPicker: _pickCountry,
                    onContinue: _sendCode,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _sendCode() async {
    try {
      final normalizedPhone = _normalizePhone();
      final bootstrap = ref.read(firebaseStatusProvider);
      if (bootstrap.mode == FirebaseBootstrapMode.preview || !kIsWeb) {
        setState(() {
          _desktopPreviewPhone = normalizedPhone;
          _desktopPreviewCodeSentAt = DateTime.now();
          _codeController.clear();
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _codeFocusNode.requestFocus();
          }
        });
        return;
      }

      await ref
          .read(clientPhoneAuthControllerProvider.notifier)
          .startWebPhoneSignIn(normalizedPhone);
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _codeFocusNode.requestFocus();
          }
        });
      }
    } catch (error) {
      _showSnackBar(error.toString());
    }
  }

  Future<void> _verifyCode() async {
    try {
      final bootstrap = ref.read(firebaseStatusProvider);
      if (bootstrap.mode == FirebaseBootstrapMode.preview || !kIsWeb) {
        if (_codeController.text.trim().length < 4) {
          throw const FormatException('Kodni toliq kiriting.');
        }
        await ref
            .read(appSessionControllerProvider.notifier)
            .continueInPreview(AppRole.client);
        if (!mounted) {
          return;
        }
        context.go('/client');
        return;
      }

      await ref
          .read(clientPhoneAuthControllerProvider.notifier)
          .confirmSmsCode(_codeController.text);
      if (!mounted) {
        return;
      }
      context.go('/client');
    } catch (error) {
      _showSnackBar(error.toString());
    }
  }

  Future<void> _resendCode() async {
    try {
      final bootstrap = ref.read(firebaseStatusProvider);
      if (bootstrap.mode == FirebaseBootstrapMode.preview || !kIsWeb) {
        setState(() {
          _desktopPreviewCodeSentAt = DateTime.now();
        });
        return;
      }
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
      if (!mounted) {
        return;
      }
      context.go('/client');
    } catch (error) {
      _showSnackBar(error.toString());
    }
  }

  Future<void> _useAnotherNumber() async {
    try {
      _desktopPreviewPhone = null;
      _desktopPreviewCodeSentAt = null;
      _phoneController.value = const PhoneNumber(isoCode: IsoCode.UZ, nsn: '');
      _codeController.clear();
      await ref
          .read(clientPhoneAuthControllerProvider.notifier)
          .abandonCurrentAttempt();
      if (mounted) {
        setState(() {});
      }
    } catch (error) {
      _showSnackBar(error.toString());
    }
  }

  String _normalizeDraft() {
    final phoneNumber = _phoneController.value;
    if (phoneNumber.nsn.isEmpty) {
      return '+${phoneNumber.countryCode}';
    }
    return phoneNumber.international;
  }

  String _normalizePhone() {
    final phoneNumber = _phoneController.value;
    if (phoneNumber.nsn.isEmpty || !phoneNumber.isValid()) {
      final example = _formattedPhoneExample(phoneNumber.isoCode);
      throw FormatException(
        example == null
            ? 'Phone numberni toliq kiriting. Davlatni tanlang va raqamni davom ettiring.'
            : 'Phone numberni toliq kiriting. Masalan: +${phoneNumber.countryCode} $example',
      );
    }
    return phoneNumber.international;
  }

  Future<void> _pickCountry() async {
    final theme = Theme.of(context);

    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      showDragHandle: true,
      builder: (sheetContext) {
        return CountrySelector.sheet(
          onCountrySelected: (isoCode) {
            Navigator.of(sheetContext).pop();
            _phoneController.changeCountry(isoCode);
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                _phoneFocusNode.requestFocus();
              }
            });
          },
          favoriteCountries: const [
            IsoCode.UZ,
            IsoCode.RU,
            IsoCode.KZ,
            IsoCode.TR,
            IsoCode.US,
          ],
          showDialCode: true,
          flagSize: 24,
          titleStyle: theme.textTheme.bodyLarge?.copyWith(
            color: Colors.black,
            fontWeight: FontWeight.w600,
          ),
          subtitleStyle: theme.textTheme.bodySmall?.copyWith(
            color: Colors.black.withValues(alpha: 0.62),
          ),
          searchBoxDecoration: InputDecoration(
            hintText: 'Search country',
            hintStyle: theme.textTheme.bodyMedium?.copyWith(
              color: Colors.black.withValues(alpha: 0.36),
            ),
            border: const UnderlineInputBorder(),
            focusedBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: _actionBlue),
            ),
          ),
        );
      },
    );
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

class _TopBar extends StatelessWidget {
  const _TopBar();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Text(
        'Together',
        style: theme.textTheme.headlineSmall?.copyWith(
          color: _actionBlue,
          fontWeight: FontWeight.w900,
          fontSize: 30,
          letterSpacing: -1.2,
        ),
      ),
    );
  }
}

class _PhoneEntryStage extends StatelessWidget {
  const _PhoneEntryStage({
    required this.phoneController,
    required this.phoneFocusNode,
    required this.isSubmitting,
    required this.statusText,
    required this.onOpenCountryPicker,
    required this.onContinue,
  });

  final PhoneController phoneController;
  final FocusNode phoneFocusNode;
  final bool isSubmitting;
  final String? statusText;
  final VoidCallback onOpenCountryPicker;
  final Future<void> Function() onContinue;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final countryLocalization = CountrySelectorLocalization.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxHeight < 590;
        return AnimatedBuilder(
          animation: phoneController,
          child: Row(
            children: [
              IgnorePointer(
                child: CountryButton(
                  isoCode: phoneController.value.isoCode,
                  onTap: null,
                  padding: EdgeInsets.zero,
                  flagSize: compact ? 20 : 22,
                  showDialCode: false,
                  showDropdownIcon: false,
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              const SizedBox(width: 12),
            ],
          ),
          builder: (context, countryFlag) {
            final phoneNumber = phoneController.value;
            final countryName =
                countryLocalization?.countryName(phoneNumber.isoCode) ??
                phoneNumber.isoCode.name;
            final phoneHint =
                _formattedPhoneExample(phoneNumber.isoCode) ?? 'Phone number';

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Continue with phone',
                  style:
                      (compact
                              ? theme.textTheme.headlineSmall
                              : theme.textTheme.headlineMedium)
                          ?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: Colors.black,
                            letterSpacing: -0.8,
                          ),
                ),
                SizedBox(height: compact ? 8 : 12),
                Text(
                  'Create your Together cashback account or come back in with the same number.',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: Colors.black.withValues(alpha: 0.68),
                    height: 1.3,
                  ),
                ),
                SizedBox(height: compact ? 18 : 28),
                _LineRow(
                  height: compact ? 50 : 56,
                  child: InkWell(
                    onTap: onOpenCountryPicker,
                    borderRadius: BorderRadius.circular(16),
                    child: Row(
                      children: [
                        countryFlag!,
                        Expanded(
                          child: Text(
                            countryName,
                            style: theme.textTheme.titleSmall?.copyWith(
                              color: Colors.black,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Icon(
                          TeamCashIcons.chevronDown,
                          size: 22,
                          color: Colors.black.withValues(alpha: 0.54),
                        ),
                      ],
                    ),
                  ),
                ),
                _LineRow(
                  height: compact ? 52 : 58,
                  removeBottomBorder: true,
                  child: Row(
                    children: [
                      Text(
                        '+${phoneNumber.countryCode}',
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: Colors.black,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Container(
                        width: 1,
                        height: 26,
                        margin: const EdgeInsets.symmetric(horizontal: 14),
                        color: const Color(0xFFD7DBE0),
                      ),
                      Expanded(
                        child: PhoneFormField(
                          key: const ValueKey('client-auth-phone-input'),
                          controller: phoneController,
                          focusNode: phoneFocusNode,
                          autovalidateMode: AutovalidateMode.disabled,
                          isCountrySelectionEnabled: false,
                          isCountryButtonPersistent: false,
                          shouldLimitLengthByCountry: true,
                          keyboardType: TextInputType.phone,
                          textInputAction: TextInputAction.done,
                          autofillHints: const [AutofillHints.telephoneNumber],
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: Colors.black,
                            fontWeight: FontWeight.w500,
                          ),
                          decoration: InputDecoration(
                            isDense: true,
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            errorBorder: InputBorder.none,
                            focusedErrorBorder: InputBorder.none,
                            contentPadding: EdgeInsets.zero,
                            hintText: phoneHint,
                            hintStyle: theme.textTheme.titleSmall?.copyWith(
                              color: Colors.black.withValues(alpha: 0.36),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          countryButtonStyle: const CountryButtonStyle(
                            showFlag: false,
                            showDialCode: false,
                            showDropdownIcon: false,
                            padding: EdgeInsets.zero,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (statusText != null) ...[
                  SizedBox(height: compact ? 10 : 14),
                  Text(
                    statusText!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: const Color(0xFFC34F5D),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                SizedBox(height: compact ? 16 : 22),
                FilledButton(
                  key: const ValueKey('client-auth-send-code'),
                  onPressed: isSubmitting ? null : onContinue,
                  style: FilledButton.styleFrom(
                    backgroundColor: _actionBlue,
                    foregroundColor: Colors.white,
                    minimumSize: Size.fromHeight(compact ? 52 : 56),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: isSubmitting
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Continue'),
                ),
                SizedBox(height: compact ? 12 : 18),
                const Spacer(),
                const _LegalFooter(),
              ],
            );
          },
        );
      },
    );
  }
}

String? _formattedPhoneExample(IsoCode isoCode) {
  final examples = metadataExamplesByIsoCode[isoCode];
  if (examples == null) {
    return null;
  }

  for (final sample in [
    examples.mobile,
    examples.fixedLine,
    examples.voip,
    examples.personalNumber,
    examples.uan,
  ]) {
    if (sample.isNotEmpty) {
      return PhoneNumber(isoCode: isoCode, nsn: sample).formatNsn();
    }
  }

  return null;
}

class _VerifyCodeStage extends StatelessWidget {
  const _VerifyCodeStage({
    required this.phoneNumber,
    required this.codeController,
    required this.codeFocusNode,
    required this.isSubmitting,
    required this.codeSentAt,
    required this.errorText,
    required this.onVerify,
    required this.onResend,
    required this.onChangeNumber,
  });

  final String phoneNumber;
  final TextEditingController codeController;
  final FocusNode codeFocusNode;
  final bool isSubmitting;
  final DateTime? codeSentAt;
  final String? errorText;
  final Future<void> Function() onVerify;
  final Future<void> Function() onResend;
  final Future<void> Function() onChangeNumber;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxHeight < 590;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Verify your phone number',
              style:
                  (compact
                          ? theme.textTheme.headlineSmall
                          : theme.textTheme.headlineMedium)
                      ?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: Colors.black,
                        letterSpacing: -0.9,
                      ),
            ),
            SizedBox(height: compact ? 8 : 12),
            Text(
              'We’ve sent an SMS with an activation code to your phone $phoneNumber',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: Colors.black.withValues(alpha: 0.68),
                height: 1.3,
              ),
            ),
            SizedBox(height: compact ? 18 : 28),
            GestureDetector(
              onTap: () => codeFocusNode.requestFocus(),
              child: ValueListenableBuilder<TextEditingValue>(
                valueListenable: codeController,
                builder: (context, value, _) {
                  final code = value.text.trim();
                  return Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: List.generate(
                      6,
                      (index) => _CodeBox(
                        value: index < code.length ? code[index] : '',
                        compact: compact,
                      ),
                    ),
                  );
                },
              ),
            ),
            Opacity(
              opacity: 0.01,
              child: SizedBox(
                height: 1,
                child: TextField(
                  key: const ValueKey('client-auth-code-input'),
                  controller: codeController,
                  focusNode: codeFocusNode,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    LengthLimitingTextInputFormatter(6),
                    FilteringTextInputFormatter.digitsOnly,
                  ],
                  decoration: const InputDecoration(
                    isCollapsed: true,
                    border: InputBorder.none,
                  ),
                ),
              ),
            ),
            if (errorText != null) ...[
              SizedBox(height: compact ? 10 : 14),
              Text(
                errorText!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: const Color(0xFFC34F5D),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ] else
              SizedBox(height: compact ? 10 : 14),
            Center(
              child: _InlineResendAction(
                codeSentAt: codeSentAt,
                isSubmitting: isSubmitting,
                onResend: onResend,
                onChangeNumber: onChangeNumber,
              ),
            ),
            SizedBox(height: compact ? 16 : 22),
            FilledButton(
              key: const ValueKey('client-auth-verify-code'),
              onPressed: isSubmitting ? null : onVerify,
              style: FilledButton.styleFrom(
                backgroundColor: _actionBlue,
                foregroundColor: Colors.white,
                minimumSize: Size.fromHeight(compact ? 52 : 56),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: isSubmitting
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Verify'),
            ),
            SizedBox(height: compact ? 12 : 18),
            const Spacer(),
          ],
        );
      },
    );
  }
}

class _LinkedWalletStage extends StatelessWidget {
  const _LinkedWalletStage({required this.phoneNumber, required this.onOpen});

  final String? phoneNumber;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Cashback wallet ready',
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: Colors.black,
              letterSpacing: -0.8,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            phoneNumber ?? 'Verified phone linked',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: Colors.black.withValues(alpha: 0.68),
            ),
          ),
          const SizedBox(height: 28),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFFD8DADC)),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: [
                const Icon(TeamCashIcons.walletLinked, color: Colors.black),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Open your cashback account.',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: Colors.black,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          FilledButton(
            onPressed: onOpen,
            style: FilledButton.styleFrom(
              backgroundColor: _actionBlue,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(56),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: const Text('Open Wallet'),
          ),
          const Spacer(),
        ],
      ),
    );
  }
}

class _ClaimWalletStage extends StatelessWidget {
  const _ClaimWalletStage({
    required this.phoneNumber,
    required this.isSubmitting,
    required this.onClaim,
    required this.onUseAnotherNumber,
  });

  final String? phoneNumber;
  final bool isSubmitting;
  final Future<void> Function() onClaim;
  final Future<void> Function() onUseAnotherNumber;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Phone verified',
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: Colors.black,
              letterSpacing: -0.8,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            phoneNumber ?? 'Verified number found',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: Colors.black.withValues(alpha: 0.68),
            ),
          ),
          const SizedBox(height: 28),
          FilledButton(
            onPressed: isSubmitting ? null : onClaim,
            style: FilledButton.styleFrom(
              backgroundColor: _actionBlue,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(56),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: isSubmitting
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text('Open Wallet'),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: isSubmitting ? null : onUseAnotherNumber,
            style: OutlinedButton.styleFrom(
              foregroundColor: _actionBlue,
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: const Text('Use another number'),
          ),
          const Spacer(),
        ],
      ),
    );
  }
}

class _LineRow extends StatelessWidget {
  const _LineRow({
    required this.child,
    this.height = 56,
    this.removeBottomBorder = false,
  });

  final Widget child;
  final double height;
  final bool removeBottomBorder;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        border: Border(
          top: const BorderSide(color: Color(0xFFD8DADC)),
          bottom: removeBottomBorder
              ? BorderSide.none
              : const BorderSide(color: Color(0xFFD8DADC)),
        ),
      ),
      child: child,
    );
  }
}

class _CodeBox extends StatelessWidget {
  const _CodeBox({required this.value, this.compact = false});

  final String value;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: compact ? 48 : 50,
      height: compact ? 58 : 64,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFD8DADC)),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Text(
        value,
        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
          color: Colors.black,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _InlineResendAction extends StatefulWidget {
  const _InlineResendAction({
    required this.codeSentAt,
    required this.isSubmitting,
    required this.onResend,
    required this.onChangeNumber,
  });

  final DateTime? codeSentAt;
  final bool isSubmitting;
  final Future<void> Function() onResend;
  final Future<void> Function() onChangeNumber;

  @override
  State<_InlineResendAction> createState() => _InlineResendActionState();
}

class _InlineResendActionState extends State<_InlineResendAction> {
  static const _resendCooldown = Duration(seconds: 30);
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _restartTimerIfNeeded();
  }

  @override
  void didUpdateWidget(covariant _InlineResendAction oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.codeSentAt != widget.codeSentAt) {
      _restartTimerIfNeeded();
    }
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
    final theme = Theme.of(context);

    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 10,
      runSpacing: 2,
      children: [
        Text(
          'Wrong number?',
          style: theme.textTheme.bodyLarge?.copyWith(
            color: Colors.black.withValues(alpha: 0.68),
          ),
        ),
        TextButton(
          onPressed: widget.isSubmitting ? null : widget.onChangeNumber,
          style: TextButton.styleFrom(
            foregroundColor: _actionBlue,
            padding: EdgeInsets.zero,
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: Text(
            'Change',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: _actionBlue,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Text(
          'No code?',
          style: theme.textTheme.bodyLarge?.copyWith(
            color: Colors.black.withValues(alpha: 0.68),
          ),
        ),
        TextButton(
          onPressed: canResend ? widget.onResend : null,
          style: TextButton.styleFrom(
            foregroundColor: _actionBlue,
            padding: EdgeInsets.zero,
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: Text(
            canResend
                ? 'Resend'
                : widget.codeSentAt == null
                ? 'Resend'
                : 'Resend ${remainingSeconds}s',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: canResend
                  ? _actionBlue
                  : Colors.black.withValues(alpha: 0.42),
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
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

class _LegalFooter extends StatelessWidget {
  const _LegalFooter();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          'By continuing, you agree to Together account terms.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: Colors.black.withValues(alpha: 0.48),
            height: 1.35,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 10),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 16,
          runSpacing: 4,
          children: [
            _LegalLink(
              label: 'Privacy',
              onTap: () => _showLegalSheet(
                context,
                title: 'Privacy Policy',
                body:
                    'Together uses your phone number to secure sign in, restore access, and connect cashback activity to your account.',
              ),
            ),
            _LegalLink(
              label: 'Terms',
              onTap: () => _showLegalSheet(
                context,
                title: 'Terms of Use',
                body:
                    'Together gives you access to cashback wallets and partner rewards. Individual cashback rules are defined by participating businesses.',
              ),
            ),
            _LegalLink(
              label: 'Support',
              onTap: () => _showLegalSheet(
                context,
                title: 'Support',
                body:
                    'Release support contacts and public help center links will be connected before launch. For now this flow is in product preview.',
              ),
            ),
            _LegalLink(
              label: 'Licenses',
              onTap: () => showLicensePage(
                context: context,
                applicationName: 'Together',
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _showLegalSheet(
    BuildContext context, {
    required String title,
    required String body,
  }) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      showDragHandle: true,
      builder: (context) {
        final theme = Theme.of(context);
        return Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.titleLarge?.copyWith(
                  color: Colors.black,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                body,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: Colors.black.withValues(alpha: 0.72),
                  height: 1.45,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _LegalLink extends StatelessWidget {
  const _LegalLink({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: _actionBlue,
        padding: EdgeInsets.zero,
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Text(
        label,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: _actionBlue,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
