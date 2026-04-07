import 'package:flutter_test/flutter_test.dart';

import 'package:teamcash/core/models/customer_identity_models.dart';
import 'package:teamcash/core/services/customer_identity_token_service.dart';

void main() {
  const service = CustomerIdentityTokenService();

  test('builds and resolves TeamCash customer QR payload', () {
    final token = service.buildToken(
      customerId: 'customer-smoke-1',
      phoneE164: '+998901234567',
      displayName: 'Javohir Smoke',
    );

    final resolved = service.resolveForStaffInput(token.qrPayload);

    expect(resolved.source, CustomerIdentifierSource.qrToken);
    expect(resolved.customerId, 'customer-smoke-1');
    expect(resolved.phoneE164, '+998901234567');
    expect(resolved.displayName, 'Javohir Smoke');
    expect(resolved.isPreview, isFalse);
  });

  test('normalizes raw phone input for staff fallback flow', () {
    final resolved = service.resolveForStaffInput('+998 90 123 45 67');

    expect(resolved.source, CustomerIdentifierSource.phoneNumber);
    expect(resolved.phoneE164, '+998901234567');
    expect(resolved.customerId, isNull);
  });
}
