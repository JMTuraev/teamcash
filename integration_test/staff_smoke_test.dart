import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:teamcash/core/services/customer_identity_token_service.dart';
import 'package:teamcash/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('staff localhost flow issues, redeems, and opens shared checkout', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await app.main();
    await tester.pumpAndSettle(const Duration(seconds: 2));

    final staffAction = find.byKey(const ValueKey('role-action-staff'));
    await _pumpUntilVisible(tester, staffAction);
    await tester.tap(staffAction);
    await tester.pumpAndSettle(const Duration(seconds: 2));

    final usernameField = find.byKey(
      const ValueKey('operator-sign-in-username'),
    );
    if (usernameField.evaluate().isNotEmpty) {
      await tester.enterText(
        usernameField,
        const String.fromEnvironment(
          'TEAMCASH_STAFF_USERNAME',
          defaultValue: 'nadia.silkroad',
        ),
      );
      await tester.enterText(
        find.byKey(const ValueKey('operator-sign-in-password')),
        const String.fromEnvironment(
          'TEAMCASH_STAFF_PASSWORD',
          defaultValue: 'Teamcash!2026',
        ),
      );
      await tester.tap(find.byKey(const ValueKey('operator-sign-in-submit')));
      await tester.pump();
    }

    final staffRoot = find.byKey(const ValueKey('staff-workspace-root'));
    final staffLoadError = find.text(
      'Staff workspace could not be loaded from Firestore.',
    );
    final staffResolved = await _pumpUntilAnyVisible(tester, [
      staffRoot,
      staffLoadError,
    ], timeout: const Duration(seconds: 90));

    if (!staffResolved) {
      final diagnostics = await _collectStaffDiagnostics();
      fail(
        'Staff route did not resolve. Visible texts: ${_collectVisibleTexts(tester)}. Diagnostics: $diagnostics',
      );
    }

    if (staffLoadError.evaluate().isNotEmpty) {
      final diagnostics = await _collectStaffDiagnostics();
      fail(
        'Staff workspace failed to load. Visible texts: ${_collectVisibleTexts(tester)}. Diagnostics: $diagnostics',
      );
    }

    expect(staffRoot, findsOneWidget);
    await tester.tap(find.text('Scan').last);
    await tester.pumpAndSettle(const Duration(seconds: 1));
    expect(find.byKey(const ValueKey('staff-scan-section')), findsOneWidget);

    final staffContext = await _loadStaffContext();
    final uniqueSuffix = DateTime.now().millisecondsSinceEpoch
        .remainder(10000000)
        .toString()
        .padLeft(7, '0');
    final customerPhone = '+99890$uniqueSuffix';
    final issueTicketRef = 'IT-$uniqueSuffix';
    final redeemTicketRef = 'RT-$uniqueSuffix';
    final sharedCheckoutTicketRef = 'SC-$uniqueSuffix';
    const paidMinorUnits = 49000;
    final expectedIssuedMinorUnits =
        (paidMinorUnits * staffContext.cashbackBasisPoints) ~/ 10000;
    const redeemMinorUnits = 2000;
    const sharedCheckoutTotalMinorUnits = 180000;

    if (expectedIssuedMinorUnits <= redeemMinorUnits) {
      fail(
        'Test setup produced too little cashback to redeem. basisPoints=${staffContext.cashbackBasisPoints}',
      );
    }

    final clientIdentityToken = const CustomerIdentityTokenService().buildToken(
      customerId: 'staff-smoke-$uniqueSuffix',
      phoneE164: customerPhone,
      displayName: 'Chrome QR Smoke',
    );
    await tester.enterText(
      find.byKey(const ValueKey('staff-customer-identifier-input')),
      clientIdentityToken.qrPayload,
    );
    await tester.tap(
      find.byKey(const ValueKey('staff-customer-identifier-resolve')),
    );
    await tester.pumpAndSettle(const Duration(seconds: 1));
    expect(
      find.byKey(const ValueKey('staff-resolved-customer-card')),
      findsOneWidget,
    );

    await tester.enterText(
      find.byKey(const ValueKey('staff-customer-phone-input')),
      customerPhone,
    );
    await tester.enterText(
      find.byKey(const ValueKey('staff-amount-input')),
      paidMinorUnits.toString(),
    );
    await tester.enterText(
      find.byKey(const ValueKey('staff-ticket-ref-input')),
      issueTicketRef,
    );
    await tester.tap(find.byKey(const ValueKey('staff-issue-submit')));
    await tester.pump();

    final issueArtifacts = await _waitForIssueArtifacts(
      businessId: staffContext.businessId,
      phoneE164: customerPhone,
      sourceTicketRef: issueTicketRef,
      expectedIssuedMinorUnits: expectedIssuedMinorUnits,
    );
    if (issueArtifacts == null) {
      fail(
        'Issue cashback did not persist expected Firestore artifacts. Visible texts: ${_collectVisibleTexts(tester)}',
      );
    }

    await tester.pumpAndSettle(const Duration(seconds: 2));
    await _pumpUntilVisible(
      tester,
      find.byKey(const ValueKey('staff-scan-section')),
    );
    await _pumpUntilVisible(
      tester,
      find.byKey(const ValueKey('staff-redeem-submit')),
    );
    await tester.enterText(
      find.byKey(const ValueKey('staff-amount-input')),
      redeemMinorUnits.toString(),
    );
    await tester.enterText(
      find.byKey(const ValueKey('staff-ticket-ref-input')),
      redeemTicketRef,
    );
    await tester.tap(find.byKey(const ValueKey('staff-redeem-submit')));
    await tester.pumpAndSettle(const Duration(seconds: 1));

    final redeemArtifacts = await _waitForRedeemArtifacts(
      businessId: staffContext.businessId,
      sourceTicketRef: redeemTicketRef,
      expectedRedeemMinorUnits: redeemMinorUnits,
      customerId: issueArtifacts.customerId,
    );
    if (redeemArtifacts == null) {
      fail(
        'Redeem cashback did not persist expected Firestore artifacts. Visible texts: ${_collectVisibleTexts(tester)}',
      );
    }

    await tester.pumpAndSettle(const Duration(seconds: 2));
    await _pumpUntilVisible(
      tester,
      find.byKey(const ValueKey('staff-shared-checkout-submit')),
    );
    await tester.tap(
      find.byKey(const ValueKey('staff-shared-checkout-submit')),
    );
    await tester.pumpAndSettle(const Duration(seconds: 1));
    await _pumpUntilVisible(
      tester,
      find.byKey(const ValueKey('staff-shared-checkout-open-new')),
    );
    await tester.tap(
      find.byKey(const ValueKey('staff-shared-checkout-open-new')),
    );
    await tester.pumpAndSettle(const Duration(seconds: 1));
    await _pumpUntilVisible(
      tester,
      find.byKey(const ValueKey('staff-shared-checkout-total-input')),
    );
    await tester.enterText(
      find.byKey(const ValueKey('staff-shared-checkout-total-input')),
      sharedCheckoutTotalMinorUnits.toString(),
    );
    await tester.enterText(
      find.byKey(const ValueKey('staff-shared-checkout-ticket-input')),
      sharedCheckoutTicketRef,
    );
    await tester.tap(
      find.byKey(const ValueKey('staff-shared-checkout-open-submit')),
    );
    await tester.pump();

    final sharedCheckoutArtifacts = await _waitForSharedCheckoutArtifacts(
      businessId: staffContext.businessId,
      sourceTicketRef: sharedCheckoutTicketRef,
      expectedTotalMinorUnits: sharedCheckoutTotalMinorUnits,
    );
    if (sharedCheckoutArtifacts == null) {
      fail(
        'Shared checkout did not persist expected Firestore artifacts. Visible texts: ${_collectVisibleTexts(tester)}',
      );
    }

    await tester.tap(find.text('Dashboard').last);
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(
      find.byKey(const ValueKey('staff-dashboard-section')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('staff-quick-actions-section')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('staff-trend-section')), findsOneWidget);
    await _pumpUntilVisible(
      tester,
      find.byKey(
        ValueKey('staff-shared-checkout-${sharedCheckoutArtifacts.id}'),
      ),
    );
    expect(find.textContaining(sharedCheckoutTicketRef), findsWidgets);

    await tester.tap(find.text('Profile').last);
    await tester.pumpAndSettle(const Duration(seconds: 1));
    await _pumpUntilVisible(
      tester,
      find.byKey(const ValueKey('staff-profile-section')),
    );
    final editedStaffName = 'Nadia Smoke $uniqueSuffix';
    await tester.tap(find.byKey(const ValueKey('staff-profile-edit-action')));
    await tester.pumpAndSettle(const Duration(seconds: 1));
    await _pumpUntilVisible(
      tester,
      find.byKey(const ValueKey('staff-profile-display-name-input')),
    );
    await tester.enterText(
      find.byKey(const ValueKey('staff-profile-display-name-input')),
      editedStaffName,
    );
    final staffProfileSave = find.byKey(
      const ValueKey('staff-profile-save-submit'),
    );
    await tester.ensureVisible(staffProfileSave);
    await tester.tap(staffProfileSave, warnIfMissed: false);
    await tester.pumpAndSettle(const Duration(seconds: 1));

    final profileUpdated = await _waitForStaffProfileUpdate(
      uid: staffContext.uid,
      expectedDisplayName: editedStaffName,
      expectedPreferredStartTab: staffContext.preferredStartTab,
      expectedNotificationDigestOptIn: staffContext.notificationDigestOptIn,
    );
    if (!profileUpdated) {
      fail(
        'Staff profile update did not persist expected fields. Visible texts: ${_collectVisibleTexts(tester)}',
      );
    }
  });
}

Future<void> _pumpUntilVisible(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 30),
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 250));
    if (finder.evaluate().isNotEmpty) {
      return;
    }
  }

  throw TestFailure('Timed out waiting for $finder');
}

Future<bool> _pumpUntilAnyVisible(
  WidgetTester tester,
  List<Finder> finders, {
  Duration timeout = const Duration(seconds: 30),
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 250));
    if (finders.any((finder) => finder.evaluate().isNotEmpty)) {
      return true;
    }
  }

  return false;
}

String _collectVisibleTexts(WidgetTester tester) {
  final texts = <String>{};
  for (final element in find.byType(Text).evaluate()) {
    final widget = element.widget as Text;
    final text = widget.data ?? widget.textSpan?.toPlainText() ?? '';
    final trimmed = text.trim();
    if (trimmed.isNotEmpty) {
      texts.add(trimmed);
    }
  }

  return texts.take(30).join(' | ');
}

Future<String> _collectStaffDiagnostics() async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) {
    return 'authUser=null';
  }

  final tokenResult = await user
      .getIdTokenResult(true)
      .timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw TimeoutException('idToken timeout'),
      );

  final firestore = FirebaseFirestore.instance;
  final operatorDoc = await firestore
      .doc('operatorAccounts/${user.uid}')
      .get()
      .timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw TimeoutException('operatorAccounts timeout'),
      );

  final operatorData = operatorDoc.data() ?? <String, dynamic>{};
  final businessId = operatorData['businessId'] as String? ?? '';
  String businessStatus = 'n/a';
  String statsStatus = 'n/a';

  if (businessId.isNotEmpty) {
    final businessDoc = await firestore
        .doc('businesses/$businessId')
        .get()
        .timeout(
          const Duration(seconds: 10),
          onTimeout: () => throw TimeoutException('business doc timeout'),
        );
    businessStatus = 'exists=${businessDoc.exists}';

    final statsQuery = await firestore
        .collection('businesses')
        .doc(businessId)
        .collection('statsDaily')
        .get()
        .timeout(
          const Duration(seconds: 10),
          onTimeout: () => throw TimeoutException('statsDaily timeout'),
        );
    statsStatus = 'docs=${statsQuery.docs.length}';
  }

  return [
    'uid=${user.uid}',
    'email=${user.email ?? 'n/a'}',
    'claimsRole=${tokenResult.claims?['role'] ?? 'n/a'}',
    'operatorDocExists=${operatorDoc.exists}',
    'businessId=$businessId',
    'business=$businessStatus',
    'statsDaily=$statsStatus',
  ].join(', ');
}

Future<_StaffContext> _loadStaffContext() async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) {
    throw TestFailure('Staff auth user is missing.');
  }

  final firestore = FirebaseFirestore.instance;
  final operatorDoc = await firestore.doc('operatorAccounts/${user.uid}').get();
  final operatorData = operatorDoc.data() ?? <String, dynamic>{};
  final businessId = operatorData['businessId'] as String? ?? '';
  if (businessId.isEmpty) {
    throw TestFailure('Staff operator account is missing businessId.');
  }

  final businessDoc = await firestore.doc('businesses/$businessId').get();
  final businessData = businessDoc.data() ?? <String, dynamic>{};
  return _StaffContext(
    uid: user.uid,
    businessId: businessId,
    cashbackBasisPoints:
        (businessData['cashbackBasisPoints'] as num?)?.toInt() ?? 0,
    preferredStartTab:
        operatorData['preferredStartTab'] as String? ?? 'dashboard',
    notificationDigestOptIn:
        operatorData['notificationDigestOptIn'] as bool? ?? true,
  );
}

Future<bool> _waitForStaffProfileUpdate({
  required String uid,
  required String expectedDisplayName,
  required String expectedPreferredStartTab,
  required bool expectedNotificationDigestOptIn,
  Duration timeout = const Duration(seconds: 45),
}) async {
  final firestore = FirebaseFirestore.instance;
  final end = DateTime.now().add(timeout);

  while (DateTime.now().isBefore(end)) {
    final snapshot = await firestore.doc('operatorAccounts/$uid').get();
    final data = snapshot.data() ?? <String, dynamic>{};
    if ((data['displayName'] as String?) == expectedDisplayName &&
        (data['preferredStartTab'] as String?) == expectedPreferredStartTab &&
        (data['notificationDigestOptIn'] as bool?) ==
            expectedNotificationDigestOptIn) {
      return true;
    }

    await Future<void>.delayed(const Duration(milliseconds: 500));
  }

  return false;
}

Future<_IssueArtifacts?> _waitForIssueArtifacts({
  required String businessId,
  required String phoneE164,
  required String sourceTicketRef,
  required int expectedIssuedMinorUnits,
  Duration timeout = const Duration(seconds: 45),
}) async {
  final firestore = FirebaseFirestore.instance;
  final end = DateTime.now().add(timeout);

  while (DateTime.now().isBefore(end)) {
    final eventsQuery = await firestore
        .collection('ledgerEvents')
        .where('participantBusinessIds', arrayContains: businessId)
        .get();

    QueryDocumentSnapshot<Map<String, dynamic>>? issueDoc;
    for (final doc in eventsQuery.docs) {
      final data = doc.data();
      if ((data['eventType'] as String?) != 'issue') {
        continue;
      }
      if ((data['sourceTicketRef'] as String?) != sourceTicketRef) {
        continue;
      }
      if ((data['customerPhoneE164'] as String?) != phoneE164) {
        continue;
      }
      issueDoc = doc;
      break;
    }

    final issuedMinorUnits =
        (issueDoc?.data()['amountMinorUnits'] as num?)?.toInt() ?? 0;
    final customerId = issueDoc?.data()['targetCustomerId'] as String? ?? '';

    if (issueDoc != null &&
        customerId.isNotEmpty &&
        issuedMinorUnits == expectedIssuedMinorUnits) {
      return _IssueArtifacts(
        customerId: customerId,
        issueEventId: issueDoc.id,
        issuedMinorUnits: issuedMinorUnits,
      );
    }

    await Future<void>.delayed(const Duration(milliseconds: 500));
  }

  return null;
}

Future<_RedeemArtifacts?> _waitForRedeemArtifacts({
  required String businessId,
  required String sourceTicketRef,
  required int expectedRedeemMinorUnits,
  required String customerId,
  Duration timeout = const Duration(seconds: 45),
}) async {
  final firestore = FirebaseFirestore.instance;
  final end = DateTime.now().add(timeout);

  while (DateTime.now().isBefore(end)) {
    final eventsQuery = await firestore
        .collection('ledgerEvents')
        .where('participantBusinessIds', arrayContains: businessId)
        .get();

    final redeemDocs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    for (final doc in eventsQuery.docs) {
      final data = doc.data();
      if ((data['eventType'] as String?) == 'redeem' &&
          (data['sourceTicketRef'] as String?) == sourceTicketRef &&
          (data['sourceCustomerId'] as String?) == customerId) {
        redeemDocs.add(doc);
      }
    }

    if (redeemDocs.isNotEmpty) {
      final redeemedMinorUnits = redeemDocs.fold<int>(
        0,
        (total, doc) =>
            total + ((doc.data()['amountMinorUnits'] as num?)?.toInt() ?? 0),
      );
      final redemptionBatchId =
          redeemDocs.first.data()['redemptionBatchId'] as String? ?? '';
      if (redeemedMinorUnits == expectedRedeemMinorUnits &&
          redemptionBatchId.isNotEmpty) {
        return _RedeemArtifacts(
          redemptionBatchId: redemptionBatchId,
          redeemedMinorUnits: redeemedMinorUnits,
        );
      }
    }

    await Future<void>.delayed(const Duration(milliseconds: 500));
  }

  return null;
}

Future<_SharedCheckoutArtifacts?> _waitForSharedCheckoutArtifacts({
  required String businessId,
  required String sourceTicketRef,
  required int expectedTotalMinorUnits,
  Duration timeout = const Duration(seconds: 45),
}) async {
  final firestore = FirebaseFirestore.instance;
  final end = DateTime.now().add(timeout);

  while (DateTime.now().isBefore(end)) {
    final query = await firestore
        .collection('sharedCheckouts')
        .where('businessId', isEqualTo: businessId)
        .get();

    for (final doc in query.docs) {
      final data = doc.data();
      if ((data['sourceTicketRef'] as String?) != sourceTicketRef) {
        continue;
      }
      if ((data['status'] as String?) == 'finalized') {
        continue;
      }
      final totalMinorUnits = (data['totalMinorUnits'] as num?)?.toInt() ?? 0;
      final remainingMinorUnits =
          (data['remainingMinorUnits'] as num?)?.toInt() ?? 0;
      if (totalMinorUnits == expectedTotalMinorUnits &&
          remainingMinorUnits == expectedTotalMinorUnits) {
        return _SharedCheckoutArtifacts(id: doc.id);
      }
    }

    await Future<void>.delayed(const Duration(milliseconds: 500));
  }

  return null;
}

class _StaffContext {
  const _StaffContext({
    required this.uid,
    required this.businessId,
    required this.cashbackBasisPoints,
    required this.preferredStartTab,
    required this.notificationDigestOptIn,
  });

  final String uid;
  final String businessId;
  final int cashbackBasisPoints;
  final String preferredStartTab;
  final bool notificationDigestOptIn;
}

class _IssueArtifacts {
  const _IssueArtifacts({
    required this.customerId,
    required this.issueEventId,
    required this.issuedMinorUnits,
  });

  final String customerId;
  final String issueEventId;
  final int issuedMinorUnits;
}

class _RedeemArtifacts {
  const _RedeemArtifacts({
    required this.redemptionBatchId,
    required this.redeemedMinorUnits,
  });

  final String redemptionBatchId;
  final int redeemedMinorUnits;
}

class _SharedCheckoutArtifacts {
  const _SharedCheckoutArtifacts({required this.id});

  final String id;
}
