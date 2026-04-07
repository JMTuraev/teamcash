import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:teamcash/core/services/teamcash_functions_service.dart';
import 'package:teamcash/core/session/session_controller.dart';

final clientPhoneAuthControllerProvider =
    NotifierProvider<ClientPhoneAuthController, ClientPhoneAuthState>(
      ClientPhoneAuthController.new,
    );

class ClientPhoneAuthState {
  const ClientPhoneAuthState({
    this.isSubmitting = false,
    this.isAwaitingCode = false,
    this.attemptCount = 0,
    this.normalizedPhone,
    this.verifiedPhoneNumber,
    this.statusMessage,
    this.recoveryHint,
    this.lastErrorCode,
    this.codeSentAt,
  });

  final bool isSubmitting;
  final bool isAwaitingCode;
  final int attemptCount;
  final String? normalizedPhone;
  final String? verifiedPhoneNumber;
  final String? statusMessage;
  final String? recoveryHint;
  final String? lastErrorCode;
  final DateTime? codeSentAt;

  bool get hasVerifiedPhoneUser =>
      verifiedPhoneNumber != null && verifiedPhoneNumber!.isNotEmpty;

  ClientPhoneAuthState copyWith({
    bool? isSubmitting,
    bool? isAwaitingCode,
    int? attemptCount,
    String? normalizedPhone,
    bool clearNormalizedPhone = false,
    String? verifiedPhoneNumber,
    bool clearVerifiedPhoneNumber = false,
    String? statusMessage,
    bool clearStatusMessage = false,
    String? recoveryHint,
    bool clearRecoveryHint = false,
    String? lastErrorCode,
    bool clearLastErrorCode = false,
    DateTime? codeSentAt,
    bool clearCodeSentAt = false,
  }) {
    return ClientPhoneAuthState(
      isSubmitting: isSubmitting ?? this.isSubmitting,
      isAwaitingCode: isAwaitingCode ?? this.isAwaitingCode,
      attemptCount: attemptCount ?? this.attemptCount,
      normalizedPhone: clearNormalizedPhone
          ? null
          : normalizedPhone ?? this.normalizedPhone,
      verifiedPhoneNumber: clearVerifiedPhoneNumber
          ? null
          : verifiedPhoneNumber ?? this.verifiedPhoneNumber,
      statusMessage: clearStatusMessage
          ? null
          : statusMessage ?? this.statusMessage,
      recoveryHint: clearRecoveryHint
          ? null
          : recoveryHint ?? this.recoveryHint,
      lastErrorCode: clearLastErrorCode
          ? null
          : lastErrorCode ?? this.lastErrorCode,
      codeSentAt: clearCodeSentAt ? null : codeSentAt ?? this.codeSentAt,
    );
  }
}

class ClientPhoneAuthController extends Notifier<ClientPhoneAuthState> {
  ConfirmationResult? _confirmationResult;

  @override
  ClientPhoneAuthState build() {
    final currentPhone = FirebaseAuth.instance.currentUser?.phoneNumber;
    return ClientPhoneAuthState(
      verifiedPhoneNumber: currentPhone,
      statusMessage: currentPhone == null
          ? null
          : 'Phone number is already verified. Finish wallet claim to attach the existing cashback history.',
    );
  }

  Future<void> startWebPhoneSignIn(String rawPhoneNumber) async {
    if (!kIsWeb) {
      throw const TeamCashActionUnavailable(
        'Phone verification UI is currently enabled for Chrome/web development. Mobile-specific verification will be layered in next.',
      );
    }

    final normalizedPhone = _normalizePhone(rawPhoneNumber);
    state = state.copyWith(
      isSubmitting: true,
      clearStatusMessage: true,
      clearRecoveryHint: true,
      clearLastErrorCode: true,
      clearVerifiedPhoneNumber: true,
    );

    try {
      _confirmationResult = await FirebaseAuth.instance.signInWithPhoneNumber(
        normalizedPhone,
      );
      state = state.copyWith(
        isSubmitting: false,
        isAwaitingCode: true,
        attemptCount: state.attemptCount + 1,
        normalizedPhone: normalizedPhone,
        codeSentAt: DateTime.now(),
        statusMessage:
            'SMS code sent to $normalizedPhone. After verification, the app will claim the existing phone-backed wallet history.',
      );
    } catch (error) {
      final feedback = _mapPhoneAuthError(error, isSendingCode: true);
      state = state.copyWith(
        isSubmitting: false,
        isAwaitingCode: false,
        statusMessage: feedback.message,
        recoveryHint: feedback.recoveryHint,
        lastErrorCode: feedback.code,
      );
      rethrow;
    }
  }

  Future<ClaimCustomerWalletResult> confirmSmsCode(String smsCode) async {
    final trimmedCode = smsCode.trim();
    if (trimmedCode.length < 4) {
      throw const TeamCashActionUnavailable(
        'Enter the SMS code that was sent to the verified phone number.',
      );
    }

    final confirmationResult = _confirmationResult;
    if (confirmationResult == null) {
      throw const TeamCashActionUnavailable(
        'Send the phone verification code first.',
      );
    }

    state = state.copyWith(isSubmitting: true, clearStatusMessage: true);

    try {
      await confirmationResult.confirm(trimmedCode);
      final result = await _claimCurrentWallet();
      return result;
    } catch (error) {
      final feedback = _mapPhoneAuthError(error, isSendingCode: false);
      state = state.copyWith(
        isSubmitting: false,
        statusMessage: feedback.message,
        recoveryHint: feedback.recoveryHint,
        lastErrorCode: feedback.code,
      );
      rethrow;
    }
  }

  Future<ClaimCustomerWalletResult> claimCurrentVerifiedPhone() async {
    final phoneNumber = FirebaseAuth.instance.currentUser?.phoneNumber;
    if (phoneNumber == null || phoneNumber.isEmpty) {
      throw const TeamCashActionUnavailable(
        'Verify the phone number first before claiming the wallet history.',
      );
    }

    state = state.copyWith(isSubmitting: true, clearStatusMessage: true);

    try {
      final result = await _claimCurrentWallet();
      return result;
    } catch (error) {
      final feedback = _mapPhoneAuthError(error, isSendingCode: false);
      state = state.copyWith(
        isSubmitting: false,
        statusMessage: feedback.message,
        recoveryHint: feedback.recoveryHint,
        lastErrorCode: feedback.code,
      );
      rethrow;
    }
  }

  Future<void> resendSmsCode() async {
    final phoneNumber = state.normalizedPhone;
    if (phoneNumber == null || phoneNumber.isEmpty) {
      throw const TeamCashActionUnavailable(
        'Enter the phone number first so the verification code can be resent.',
      );
    }
    await startWebPhoneSignIn(phoneNumber);
  }

  Future<void> abandonCurrentAttempt() async {
    _confirmationResult = null;
    await ref.read(appSessionControllerProvider.notifier).signOut();
    state = const ClientPhoneAuthState(attemptCount: 0);
  }

  String _normalizePhone(String rawPhoneNumber) {
    final compact = rawPhoneNumber.replaceAll(RegExp(r'[^\d+]'), '');
    if (!compact.startsWith('+')) {
      throw const TeamCashActionUnavailable(
        'Enter the customer phone in international format, for example +998901234567.',
      );
    }

    final digitsOnly = compact.substring(1);
    if (!RegExp(r'^\d{10,15}$').hasMatch(digitsOnly)) {
      throw const TeamCashActionUnavailable(
        'Enter a valid international phone number in E.164 format.',
      );
    }

    return '+$digitsOnly';
  }

  Future<ClaimCustomerWalletResult> _claimCurrentWallet() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    final phoneNumber = currentUser?.phoneNumber;
    if (currentUser == null || phoneNumber == null || phoneNumber.isEmpty) {
      throw const TeamCashActionUnavailable(
        'Phone verification must complete before wallet claim can run.',
      );
    }

    final result = await ref
        .read(teamCashFunctionsServiceProvider)
        .claimCustomerWalletByPhone();
    await ref
        .read(appSessionControllerProvider.notifier)
        .refreshCurrentSession();

    _confirmationResult = null;
    state = state.copyWith(
      isSubmitting: false,
      isAwaitingCode: false,
      attemptCount: 0,
      clearNormalizedPhone: true,
      verifiedPhoneNumber: phoneNumber,
      clearRecoveryHint: true,
      clearLastErrorCode: true,
      clearCodeSentAt: true,
      statusMessage:
          'Wallet claimed for $phoneNumber. Existing cashback history is now attached to this verified app user.',
    );

    return result;
  }

  _PhoneAuthFeedback _mapPhoneAuthError(
    Object error, {
    required bool isSendingCode,
  }) {
    if (error is FirebaseAuthException) {
      return switch (error.code) {
        'invalid-phone-number' => const _PhoneAuthFeedback(
          code: 'invalid-phone-number',
          message:
              'The phone number is not in a valid international format yet.',
          recoveryHint:
              'Use a full E.164 number such as +998901234567 with no local leading zero.',
        ),
        'too-many-requests' => const _PhoneAuthFeedback(
          code: 'too-many-requests',
          message: 'Too many verification attempts were made for now.',
          recoveryHint:
              'Wait a few minutes before retrying. New projects may also have temporary SMS quota limits.',
        ),
        'quota-exceeded' => const _PhoneAuthFeedback(
          code: 'quota-exceeded',
          message:
              'Firebase SMS quota is temporarily exhausted for this project.',
          recoveryHint:
              'Retry later or use a seeded linked client during Chrome development until quota resets.',
        ),
        'captcha-check-failed' => const _PhoneAuthFeedback(
          code: 'captcha-check-failed',
          message:
              'The web verification challenge did not complete successfully.',
          recoveryHint:
              'Refresh the page, allow the reCAPTCHA prompt to finish, then resend the code.',
        ),
        'session-expired' => const _PhoneAuthFeedback(
          code: 'session-expired',
          message:
              'The SMS verification session expired before it was confirmed.',
          recoveryHint: 'Resend the code and enter the latest SMS immediately.',
        ),
        'invalid-verification-code' => const _PhoneAuthFeedback(
          code: 'invalid-verification-code',
          message:
              'The SMS code does not match the latest verification attempt.',
          recoveryHint:
              'Use the most recent code you received, or resend a fresh code if multiple attempts were sent.',
        ),
        'web-context-cancelled' => const _PhoneAuthFeedback(
          code: 'web-context-cancelled',
          message: 'The browser interrupted the verification flow.',
          recoveryHint:
              'Keep this tab open while the reCAPTCHA and SMS flow completes, then retry.',
        ),
        _ => _PhoneAuthFeedback(
          code: error.code,
          message:
              error.message ??
              (isSendingCode
                  ? 'Phone verification code could not be sent.'
                  : 'Phone verification could not be completed.'),
          recoveryHint:
              'Retry the flow or switch to another number if this device/browser is holding stale verification state.',
        ),
      };
    }

    return _PhoneAuthFeedback(
      message: error.toString(),
      recoveryHint:
          'Retry the verification flow. If the problem repeats, refresh the page and request a fresh code.',
    );
  }
}

class _PhoneAuthFeedback {
  const _PhoneAuthFeedback({
    required this.message,
    this.recoveryHint,
    this.code,
  });

  final String message;
  final String? recoveryHint;
  final String? code;
}
