enum CustomerIdentifierSource { qrToken, phoneNumber }

class CustomerIdentificationToken {
  const CustomerIdentificationToken({
    required this.customerId,
    required this.phoneE164,
    required this.displayName,
    required this.rawToken,
    required this.qrPayload,
    required this.generatedAt,
    required this.isPreview,
  });

  final String customerId;
  final String phoneE164;
  final String displayName;
  final String rawToken;
  final String qrPayload;
  final DateTime generatedAt;
  final bool isPreview;

  String get compactPayload {
    if (rawToken.length <= 36) {
      return rawToken;
    }
    return '${rawToken.substring(0, 18)}...${rawToken.substring(rawToken.length - 10)}';
  }
}

class ResolvedCustomerIdentifier {
  const ResolvedCustomerIdentifier({
    required this.source,
    required this.phoneE164,
    required this.rawInput,
    this.customerId,
    this.displayName,
    this.isPreview = false,
  });

  final CustomerIdentifierSource source;
  final String phoneE164;
  final String rawInput;
  final String? customerId;
  final String? displayName;
  final bool isPreview;

  bool get cameFromQr => source == CustomerIdentifierSource.qrToken;
}
