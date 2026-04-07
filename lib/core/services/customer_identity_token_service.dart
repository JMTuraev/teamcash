import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:teamcash/core/models/customer_identity_models.dart';
import 'package:teamcash/core/models/workspace_models.dart';
import 'package:teamcash/core/session/app_session.dart';

final customerIdentityTokenServiceProvider =
    Provider<CustomerIdentityTokenService>(
      (ref) => const CustomerIdentityTokenService(),
    );

class CustomerIdentityTokenService {
  const CustomerIdentityTokenService();

  static const String _tokenPrefix = 'TCID1:';
  static const String _deepLinkPrefix = 'teamcash://customer/';

  CustomerIdentificationToken buildForClient({
    required ClientWorkspace client,
    required AppSession? session,
  }) {
    final sessionCustomerId = session?.customerId?.trim();
    final isPreview = session?.isPreview ?? true;
    return buildToken(
      customerId: sessionCustomerId != null && sessionCustomerId.isNotEmpty
          ? sessionCustomerId
          : _buildPreviewCustomerId(client.phoneNumber),
      phoneE164: client.phoneNumber,
      displayName: client.clientName,
      isPreview: isPreview,
    );
  }

  CustomerIdentificationToken buildToken({
    required String customerId,
    required String phoneE164,
    required String displayName,
    bool isPreview = false,
    DateTime? generatedAt,
  }) {
    final normalizedPhone = _normalizePhone(phoneE164);
    final issuedAt = (generatedAt ?? DateTime.now()).toUtc();
    final payload = <String, dynamic>{
      'v': 1,
      'kind': 'customer_identity',
      'customerId': customerId.trim(),
      'phoneE164': normalizedPhone,
      'displayName': displayName.trim().isEmpty
          ? 'TeamCash client'
          : displayName.trim(),
      'preview': isPreview,
      'generatedAt': issuedAt.toIso8601String(),
    };
    final encoded = _base64UrlNoPadding(jsonEncode(payload));
    final rawToken = '$_tokenPrefix$encoded';
    return CustomerIdentificationToken(
      customerId: payload['customerId'] as String,
      phoneE164: normalizedPhone,
      displayName: payload['displayName'] as String,
      rawToken: rawToken,
      qrPayload: '$_deepLinkPrefix${Uri.encodeComponent(rawToken)}',
      generatedAt: issuedAt,
      isPreview: isPreview,
    );
  }

  ResolvedCustomerIdentifier resolveForStaffInput(String rawInput) {
    final trimmedInput = rawInput.trim();
    if (trimmedInput.isEmpty) {
      throw const FormatException(
        'Paste the TeamCash client QR payload or enter a customer phone number.',
      );
    }

    if (_looksLikeToken(trimmedInput)) {
      final token = parseToken(trimmedInput);
      return ResolvedCustomerIdentifier(
        source: CustomerIdentifierSource.qrToken,
        phoneE164: token.phoneE164,
        customerId: token.customerId,
        displayName: token.displayName,
        rawInput: trimmedInput,
        isPreview: token.isPreview,
      );
    }

    return ResolvedCustomerIdentifier(
      source: CustomerIdentifierSource.phoneNumber,
      phoneE164: _normalizePhone(trimmedInput),
      rawInput: trimmedInput,
    );
  }

  CustomerIdentificationToken parseToken(String rawInput) {
    final compact = rawInput.trim();
    final rawToken = _extractRawToken(compact);
    if (!rawToken.startsWith(_tokenPrefix)) {
      throw const FormatException(
        'This QR payload is not a TeamCash customer identifier.',
      );
    }

    final encodedPayload = rawToken.substring(_tokenPrefix.length);
    final decoded = utf8.decode(
      base64Url.decode(_restoreBase64Padding(encodedPayload)),
    );
    final payload = jsonDecode(decoded);
    if (payload is! Map) {
      throw const FormatException(
        'The pasted TeamCash QR payload could not be decoded.',
      );
    }
    final map = payload.cast<String, dynamic>();

    final customerId = (map['customerId'] as String? ?? '').trim();
    final phoneE164 = _normalizePhone(map['phoneE164'] as String? ?? '');
    final displayName = (map['displayName'] as String? ?? '').trim();
    final generatedAtRaw = map['generatedAt'] as String?;
    if (customerId.isEmpty || displayName.isEmpty) {
      throw const FormatException(
        'The TeamCash QR payload is missing customer identity fields.',
      );
    }

    return CustomerIdentificationToken(
      customerId: customerId,
      phoneE164: phoneE164,
      displayName: displayName,
      rawToken: rawToken,
      qrPayload: '$_deepLinkPrefix${Uri.encodeComponent(rawToken)}',
      generatedAt:
          DateTime.tryParse(generatedAtRaw ?? '')?.toUtc() ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      isPreview: map['preview'] as bool? ?? false,
    );
  }

  bool _looksLikeToken(String value) {
    return value.startsWith(_tokenPrefix) || value.startsWith(_deepLinkPrefix);
  }

  String _extractRawToken(String value) {
    if (value.startsWith(_tokenPrefix)) {
      return value;
    }
    if (value.startsWith(_deepLinkPrefix)) {
      final encodedToken = value.substring(_deepLinkPrefix.length);
      return Uri.decodeComponent(encodedToken);
    }
    throw const FormatException(
      'Paste the TeamCash QR payload or enter the phone number in E.164 format.',
    );
  }

  String _normalizePhone(String rawPhoneNumber) {
    final compact = rawPhoneNumber.replaceAll(RegExp(r'[^\d+]'), '');
    if (!compact.startsWith('+')) {
      throw const FormatException(
        'Enter the customer phone in international format, for example +998901234567.',
      );
    }

    final digitsOnly = compact.substring(1);
    if (!RegExp(r'^\d{10,15}$').hasMatch(digitsOnly)) {
      throw const FormatException(
        'Enter a valid international phone number in E.164 format.',
      );
    }

    return '+$digitsOnly';
  }

  String _buildPreviewCustomerId(String phoneE164) {
    final digits = phoneE164.replaceAll(RegExp(r'\D'), '');
    return 'preview-$digits';
  }

  String _base64UrlNoPadding(String value) {
    return base64Url.encode(utf8.encode(value)).replaceAll('=', '');
  }

  String _restoreBase64Padding(String value) {
    final remainder = value.length % 4;
    if (remainder == 0) {
      return value;
    }
    return '$value${List.filled(4 - remainder, '=').join()}';
  }
}
