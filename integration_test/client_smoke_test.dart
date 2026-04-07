import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:teamcash/firebase_options.dart';
import 'package:teamcash/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'client localhost flow shows incoming gifts, sends a gift, and contributes to shared checkout',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 2200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final clientContext = await _signInSmokeClient();

      await app.main();
      await tester.pumpAndSettle(const Duration(seconds: 2));

      final clientAction = find.byKey(const ValueKey('role-action-client'));
      await _pumpUntilVisible(tester, clientAction);
      await tester.tap(clientAction);
      await tester.pumpAndSettle(const Duration(seconds: 2));

      final clientRoot = find.byKey(const ValueKey('client-workspace-root'));
      final clientLoadError = find.text(
        'Client wallet could not be loaded from Firestore.',
      );
      final clientResolved = await _pumpUntilAnyVisible(tester, [
        clientRoot,
        clientLoadError,
      ], timeout: const Duration(seconds: 90));

      if (!clientResolved) {
        fail(
          'Client route did not resolve. Visible texts: ${_collectVisibleTexts(tester)}',
        );
      }

      if (clientLoadError.evaluate().isNotEmpty) {
        fail(
          'Client workspace failed to load. Visible texts: ${_collectVisibleTexts(tester)}',
        );
      }

      expect(clientRoot, findsOneWidget);
      await tester.tap(find.text('Stores').last);
      await tester.pumpAndSettle(const Duration(seconds: 1));
      await _pumpUntilVisible(
        tester,
        find.byKey(const ValueKey('client-stores-section')),
      );
      await _pumpUntilVisible(
        tester,
        find.byKey(const ValueKey('client-store-media-silk-road-cafe')),
      );
      await tester.tap(find.text('Profile').last);
      await tester.pumpAndSettle(const Duration(seconds: 1));
      await _pumpUntilVisible(
        tester,
        find.byKey(const ValueKey('client-profile-section')),
      );
      expect(
        find.byKey(const ValueKey('client-identity-qr-card')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('client-identity-qr-symbol')),
        findsOneWidget,
      );
      final smokeSuffix = DateTime.now().millisecondsSinceEpoch
          .remainder(10000000)
          .toString()
          .padLeft(7, '0');
      final editedClientName = 'Client Smoke $smokeSuffix';
      await tester.tap(
        find.byKey(const ValueKey('client-profile-edit-action')),
      );
      await tester.pumpAndSettle(const Duration(seconds: 1));
      await _pumpUntilVisible(
        tester,
        find.byKey(const ValueKey('client-profile-display-name-input')),
      );
      await tester.enterText(
        find.byKey(const ValueKey('client-profile-display-name-input')),
        editedClientName,
      );
      await tester.tap(
        find.byKey(const ValueKey('client-profile-marketing-toggle')),
      );
      await tester.pumpAndSettle(const Duration(milliseconds: 600));
      await tester.tap(
        find.byKey(const ValueKey('client-profile-save-submit')),
      );
      await tester.pump();

      final profileUpdated = await _waitForClientProfileUpdate(
        customerId: clientContext.customerId,
        expectedDisplayName: editedClientName,
        expectedMarketingOptIn: false,
      );
      if (!profileUpdated) {
        fail(
          'Client profile update did not persist expected fields. Visible texts: ${_collectVisibleTexts(tester)}',
        );
      }

      await tester.tap(find.text('Wallet').last);
      await tester.pumpAndSettle(const Duration(seconds: 1));
      expect(find.byKey(const ValueKey('client-wallet-tab')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('client-group-balances-section')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('client-expiring-cashback-section')),
        findsOneWidget,
      );

      final incomingTransfer = await _loadIncomingPendingTransfer(
        clientContext.phoneE164,
      );
      if (incomingTransfer == null) {
        fail('Incoming smoke transfer fixture was not found.');
      }

      final expiringLot = await _loadSoonestExpiringActiveLot(
        clientContext.customerId,
      );
      if (expiringLot == null) {
        fail('Expiring wallet lot fixture was not found.');
      }

      await _pumpUntilVisible(
        tester,
        find.byKey(ValueKey('client-pending-transfer-${incomingTransfer.id}')),
      );
      await _pumpUntilVisible(
        tester,
        find.byKey(ValueKey('client-expiring-lot-${expiringLot.id}')),
      );

      final uniqueSuffix = '${smokeSuffix}1'.substring(0, 7);
      final recipientPhone = '+99893$uniqueSuffix';
      const outgoingGiftMinorUnits = 7000;

      await tester.tap(find.byKey(const ValueKey('client-send-gift-action')));
      await tester.pumpAndSettle(const Duration(seconds: 1));
      await _pumpUntilVisible(
        tester,
        find.byKey(const ValueKey('client-send-gift-phone-input')),
      );
      await tester.enterText(
        find.byKey(const ValueKey('client-send-gift-phone-input')),
        recipientPhone,
      );
      await tester.enterText(
        find.byKey(const ValueKey('client-send-gift-amount-input')),
        outgoingGiftMinorUnits.toString(),
      );
      await tester.tap(find.byKey(const ValueKey('client-send-gift-submit')));
      await tester.pump();

      final outgoingTransfer = await _waitForOutgoingTransfer(
        customerId: clientContext.customerId,
        recipientPhoneE164: recipientPhone,
        amountMinorUnits: outgoingGiftMinorUnits,
      );
      if (outgoingTransfer == null) {
        fail(
          'Outgoing gift transfer was not persisted. Visible texts: ${_collectVisibleTexts(tester)}',
        );
      }

      final outgoingHistoryEvent = await _waitForHistoryEvent(
        customerId: clientContext.customerId,
        eventType: 'transfer_out',
        amountMinorUnits: outgoingGiftMinorUnits,
      );
      if (outgoingHistoryEvent == null) {
        fail('Outgoing transfer history event was not persisted.');
      }

      await _pumpUntilVisible(
        tester,
        find.byKey(ValueKey('client-pending-transfer-${outgoingTransfer.id}')),
      );

      final sharedCheckout = await _loadNewestOpenSharedCheckout(
        clientContext.customerId,
      );
      if (sharedCheckout == null) {
        fail('Active shared checkout fixture was not found.');
      }

      await _pumpUntilVisible(
        tester,
        find.byKey(ValueKey('client-shared-checkout-${sharedCheckout.id}')),
      );
      await tester.ensureVisible(
        find.byKey(ValueKey('client-shared-checkout-${sharedCheckout.id}')),
      );
      await tester.pumpAndSettle(const Duration(milliseconds: 600));

      const contributionMinorUnits = 4000;
      final contributeButton = find.byKey(
        ValueKey('client-shared-checkout-contribute-${sharedCheckout.id}'),
      );
      await tester.ensureVisible(contributeButton);
      await tester.pumpAndSettle(const Duration(milliseconds: 600));
      await tester.tap(contributeButton, warnIfMissed: false);
      await tester.pumpAndSettle(const Duration(seconds: 1));
      await _pumpUntilVisible(
        tester,
        find.byKey(const ValueKey('client-shared-checkout-amount-input')),
      );
      await tester.enterText(
        find.byKey(const ValueKey('client-shared-checkout-amount-input')),
        contributionMinorUnits.toString(),
      );
      await tester.tap(
        find.byKey(const ValueKey('client-shared-checkout-submit')),
      );
      await tester.pump();

      final contribution = await _waitForSharedCheckoutContribution(
        checkoutId: sharedCheckout.id,
        customerId: clientContext.customerId,
        amountMinorUnits: contributionMinorUnits,
      );
      if (contribution == null) {
        fail(
          'Shared checkout contribution was not persisted. Visible texts: ${_collectVisibleTexts(tester)}',
        );
      }

      final contributionHistoryEvent = await _waitForHistoryEvent(
        customerId: clientContext.customerId,
        eventType: 'shared_checkout_contribution',
        amountMinorUnits: contributionMinorUnits,
      );
      if (contributionHistoryEvent == null) {
        fail('Shared checkout contribution history event was not persisted.');
      }

      await _pumpUntilVisible(
        tester,
        find.byKey(ValueKey('client-shared-checkout-${sharedCheckout.id}')),
      );

      await tester.tap(find.text('History'));
      await tester.pumpAndSettle(const Duration(seconds: 1));
      await _pumpUntilVisible(
        tester,
        find.byKey(const ValueKey('client-history-tab')),
      );

      final transfersFilter = find.byKey(
        const ValueKey('client-history-filter-transfers'),
      );
      await tester.ensureVisible(transfersFilter);
      await tester.pumpAndSettle(const Duration(milliseconds: 600));
      await tester.tap(transfersFilter, warnIfMissed: false);
      await tester.pumpAndSettle(const Duration(milliseconds: 600));
      final outgoingHistoryEventFinder = find.byKey(
        ValueKey('client-history-event-${outgoingHistoryEvent.id}'),
      );
      await tester.ensureVisible(outgoingHistoryEventFinder);
      await tester.pumpAndSettle(const Duration(milliseconds: 600));
      expect(outgoingHistoryEventFinder, findsOneWidget);

      final checkoutsFilter = find.byKey(
        const ValueKey('client-history-filter-checkouts'),
      );
      await tester.ensureVisible(checkoutsFilter);
      await tester.pumpAndSettle(const Duration(milliseconds: 600));
      await tester.tap(checkoutsFilter, warnIfMissed: false);
      await tester.pumpAndSettle(const Duration(milliseconds: 600));
      final contributionHistoryEventFinder = find.byKey(
        ValueKey('client-history-event-${contributionHistoryEvent.id}'),
      );
      await _pumpUntilVisible(tester, contributionHistoryEventFinder);
      await tester.ensureVisible(contributionHistoryEventFinder);
      await tester.pumpAndSettle(const Duration(milliseconds: 600));
      expect(contributionHistoryEventFinder, findsOneWidget);

      await tester.tap(find.text('Stores').last);
      await tester.pumpAndSettle(const Duration(seconds: 1));
      final storeDetailButton = find.byKey(
        const ValueKey('client-store-open-details-silk-road-cafe'),
      );
      await tester.ensureVisible(storeDetailButton);
      await tester.tap(storeDetailButton, warnIfMissed: false);
      await tester.pumpAndSettle(const Duration(seconds: 1));
      await _pumpUntilVisible(
        tester,
        find.byKey(const ValueKey('client-store-detail-sheet-silk-road-cafe')),
      );
      expect(
        find.byKey(
          const ValueKey('client-store-detail-contact-silk-road-cafe'),
        ),
        findsOneWidget,
      );
    },
  );
}

Future<_ClientContext> _signInSmokeClient() async {
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  }

  await FirebaseAuth.instance.signOut();
  await FirebaseAuth.instance.signInWithEmailAndPassword(
    email: const String.fromEnvironment(
      'TEAMCASH_CLIENT_SMOKE_EMAIL',
      defaultValue: 'client.smoke@teamcash.local',
    ),
    password: const String.fromEnvironment(
      'TEAMCASH_CLIENT_SMOKE_PASSWORD',
      defaultValue: 'Teamcash!2026',
    ),
  );

  return _loadClientContext();
}

Future<_ClientContext> _loadClientContext() async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) {
    throw TestFailure('Client auth user is missing.');
  }

  final firestore = FirebaseFirestore.instance;
  final linkDoc = await firestore.doc('customerAuthLinks/${user.uid}').get();
  final linkData = linkDoc.data() ?? <String, dynamic>{};
  final customerId = linkData['customerId'] as String? ?? '';
  final phoneE164 = linkData['phoneE164'] as String? ?? '';
  if (customerId.isEmpty || phoneE164.isEmpty) {
    throw TestFailure('Client smoke auth link is incomplete.');
  }

  return _ClientContext(
    uid: user.uid,
    customerId: customerId,
    phoneE164: phoneE164,
  );
}

Future<_GiftTransferSnapshot?> _loadIncomingPendingTransfer(
  String phoneE164,
) async {
  final firestore = FirebaseFirestore.instance;
  final query = await firestore
      .collection('giftTransfers')
      .where('recipientPhoneE164', isEqualTo: phoneE164)
      .where('status', isEqualTo: 'pending')
      .get();

  final docs = query.docs.toList()
    ..sort(
      (left, right) => _createdAtForSort(
        right.data(),
      ).compareTo(_createdAtForSort(left.data())),
    );
  if (docs.isEmpty) {
    return null;
  }

  return _GiftTransferSnapshot(
    id: docs.first.id,
    amountMinorUnits:
        (docs.first.data()['amountMinorUnits'] as num?)?.toInt() ?? 0,
  );
}

Future<_GiftTransferSnapshot?> _waitForOutgoingTransfer({
  required String customerId,
  required String recipientPhoneE164,
  required int amountMinorUnits,
  Duration timeout = const Duration(seconds: 45),
}) async {
  final firestore = FirebaseFirestore.instance;
  final end = DateTime.now().add(timeout);

  while (DateTime.now().isBefore(end)) {
    final query = await firestore
        .collection('giftTransfers')
        .where('sourceCustomerId', isEqualTo: customerId)
        .where('status', isEqualTo: 'pending')
        .get();

    for (final doc in query.docs) {
      final data = doc.data();
      if ((data['recipientPhoneE164'] as String?) != recipientPhoneE164) {
        continue;
      }
      if ((data['amountMinorUnits'] as num?)?.toInt() != amountMinorUnits) {
        continue;
      }

      return _GiftTransferSnapshot(
        id: doc.id,
        amountMinorUnits: amountMinorUnits,
      );
    }

    await Future<void>.delayed(const Duration(milliseconds: 500));
  }

  return null;
}

Future<_SharedCheckoutSnapshot?> _loadNewestOpenSharedCheckout(
  String customerId,
) async {
  final firestore = FirebaseFirestore.instance;
  final query = await firestore
      .collection('sharedCheckouts')
      .where('participantCustomerIds', arrayContains: customerId)
      .get();
  final docs =
      query.docs
          .where((doc) => (doc.data()['status'] as String?) == 'open')
          .toList()
        ..sort(
          (left, right) => _createdAtForSort(
            right.data(),
          ).compareTo(_createdAtForSort(left.data())),
        );
  if (docs.isEmpty) {
    return null;
  }

  return _SharedCheckoutSnapshot(id: docs.first.id);
}

Future<_SharedCheckoutContributionSnapshot?>
_waitForSharedCheckoutContribution({
  required String checkoutId,
  required String customerId,
  required int amountMinorUnits,
  Duration timeout = const Duration(seconds: 45),
}) async {
  final firestore = FirebaseFirestore.instance;
  final end = DateTime.now().add(timeout);

  while (DateTime.now().isBefore(end)) {
    final query = await firestore
        .collection('sharedCheckouts')
        .doc(checkoutId)
        .collection('contributions')
        .where('customerId', isEqualTo: customerId)
        .get();

    for (final doc in query.docs) {
      final data = doc.data();
      if ((data['amountMinorUnits'] as num?)?.toInt() != amountMinorUnits) {
        continue;
      }

      return _SharedCheckoutContributionSnapshot(id: doc.id);
    }

    await Future<void>.delayed(const Duration(milliseconds: 500));
  }

  return null;
}

Future<_WalletLotSnapshot?> _loadSoonestExpiringActiveLot(
  String customerId,
) async {
  final firestore = FirebaseFirestore.instance;
  final query = await firestore
      .collection('walletLots')
      .where('ownerCustomerId', isEqualTo: customerId)
      .get();
  final docs =
      query.docs
          .where(
            (doc) =>
                ((doc.data()['availableMinorUnits'] as num?)?.toInt() ?? 0) >
                    0 &&
                (doc.data()['status'] as String?) == 'active',
          )
          .toList()
        ..sort(
          (left, right) => _expiresAtForSort(
            left.data(),
          ).compareTo(_expiresAtForSort(right.data())),
        );
  if (docs.isEmpty) {
    return null;
  }

  return _WalletLotSnapshot(id: docs.first.id);
}

Future<_HistoryEventSnapshot?> _waitForHistoryEvent({
  required String customerId,
  required String eventType,
  required int amountMinorUnits,
  Duration timeout = const Duration(seconds: 45),
}) async {
  final firestore = FirebaseFirestore.instance;
  final end = DateTime.now().add(timeout);

  while (DateTime.now().isBefore(end)) {
    final query = await firestore
        .collection('ledgerEvents')
        .where('participantCustomerIds', arrayContains: customerId)
        .get();

    final docs = query.docs.toList()
      ..sort(
        (left, right) => _createdAtForSort(
          right.data(),
        ).compareTo(_createdAtForSort(left.data())),
      );

    for (final doc in docs) {
      final data = doc.data();
      if ((data['eventType'] as String?) != eventType) {
        continue;
      }
      if ((data['amountMinorUnits'] as num?)?.toInt() != amountMinorUnits) {
        continue;
      }

      return _HistoryEventSnapshot(id: doc.id);
    }

    await Future<void>.delayed(const Duration(milliseconds: 500));
  }

  return null;
}

Future<bool> _waitForClientProfileUpdate({
  required String customerId,
  required String expectedDisplayName,
  required bool expectedMarketingOptIn,
  Duration timeout = const Duration(seconds: 45),
}) async {
  final firestore = FirebaseFirestore.instance;
  final end = DateTime.now().add(timeout);

  while (DateTime.now().isBefore(end)) {
    final snapshot = await firestore.doc('customers/$customerId').get();
    final data = snapshot.data() ?? <String, dynamic>{};
    if ((data['displayName'] as String?) == expectedDisplayName &&
        (data['marketingOptIn'] as bool?) == expectedMarketingOptIn) {
      return true;
    }

    await Future<void>.delayed(const Duration(milliseconds: 500));
  }

  return false;
}

DateTime _createdAtForSort(Map<String, dynamic> data) {
  final value = data['createdAt'];
  if (value is Timestamp) {
    return value.toDate();
  }
  if (value is DateTime) {
    return value;
  }
  return DateTime.fromMillisecondsSinceEpoch(0);
}

DateTime _expiresAtForSort(Map<String, dynamic> data) {
  final value = data['expiresAt'];
  if (value is Timestamp) {
    return value.toDate();
  }
  if (value is DateTime) {
    return value;
  }
  return DateTime.fromMillisecondsSinceEpoch(0);
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

class _ClientContext {
  const _ClientContext({
    required this.uid,
    required this.customerId,
    required this.phoneE164,
  });

  final String uid;
  final String customerId;
  final String phoneE164;
}

class _GiftTransferSnapshot {
  const _GiftTransferSnapshot({
    required this.id,
    required this.amountMinorUnits,
  });

  final String id;
  final int amountMinorUnits;
}

class _SharedCheckoutSnapshot {
  const _SharedCheckoutSnapshot({required this.id});

  final String id;
}

class _SharedCheckoutContributionSnapshot {
  const _SharedCheckoutContributionSnapshot({required this.id});

  final String id;
}

class _WalletLotSnapshot {
  const _WalletLotSnapshot({required this.id});

  final String id;
}

class _HistoryEventSnapshot {
  const _HistoryEventSnapshot({required this.id});

  final String id;
}
