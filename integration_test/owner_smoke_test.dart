import 'dart:convert';
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:teamcash/core/services/business_asset_picker.dart';
import 'package:teamcash/core/services/owner_business_admin_service.dart';
import 'package:teamcash/app/bootstrap/firebase_bootstrap.dart';
import 'package:teamcash/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('owner localhost flow loads workspace catalog and branding', (
    tester,
  ) async {
    const activeBusinessId = String.fromEnvironment(
      'TEAMCASH_OWNER_ACTIVE_BUSINESS_ID',
      defaultValue: 'silk-road-cafe',
    );
    const expectStorageReady = bool.fromEnvironment(
      'TEAMCASH_EXPECT_STORAGE_READY',
      defaultValue: false,
    );
    const editStaffDisplayName = String.fromEnvironment(
      'TEAMCASH_EDIT_STAFF_NAME',
      defaultValue: 'Nadia Silk Road',
    );
    const resetStaffUsername = String.fromEnvironment(
      'TEAMCASH_RESET_STAFF_USERNAME',
      defaultValue: 'nadia.silkroad',
    );
    tester.view.physicalSize = const Size(1440, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await app.mainWithOverrides(
      overrides: [
        businessAssetPickerProvider.overrideWithValue(
          const _FakeBusinessAssetPicker(),
        ),
      ],
    );
    await tester.pumpAndSettle(const Duration(seconds: 2));
    await FirebaseAuth.instance.signOut();
    await tester.pumpAndSettle(const Duration(seconds: 2));

    final ownerAction = find.byKey(const ValueKey('role-action-owner'));
    await _pumpUntilVisible(tester, ownerAction);
    await tester.tap(ownerAction);
    await tester.pumpAndSettle(const Duration(seconds: 2));

    final usernameField = find.byKey(
      const ValueKey('operator-sign-in-username'),
    );
    if (usernameField.evaluate().isNotEmpty) {
      await tester.enterText(
        usernameField,
        const String.fromEnvironment(
          'TEAMCASH_OWNER_USERNAME',
          defaultValue: 'aziza.owner',
        ),
      );
      await tester.enterText(
        find.byKey(const ValueKey('operator-sign-in-password')),
        const String.fromEnvironment(
          'TEAMCASH_OWNER_PASSWORD',
          defaultValue: 'Teamcash!2026',
        ),
      );
      await tester.tap(find.byKey(const ValueKey('operator-sign-in-submit')));
      await tester.pump();
    }

    final ownerRoot = find.byKey(const ValueKey('owner-workspace-root'));
    final ownerLoadError = find.text(
      'Owner workspace could not be loaded from Firestore.',
    );
    final ownerSurfaceResolved = await _pumpUntilAnyVisible(tester, [
      ownerRoot,
      ownerLoadError,
    ], timeout: const Duration(seconds: 90));

    if (!ownerSurfaceResolved) {
      final diagnostics = await _collectOwnerDiagnostics();
      fail(
        'Owner route did not resolve. Visible texts: ${_collectVisibleTexts(tester)}. Diagnostics: $diagnostics',
      );
    }

    if (ownerLoadError.evaluate().isNotEmpty) {
      final diagnostics = await _collectOwnerDiagnostics();
      fail(
        'Owner workspace failed to load. Visible texts: ${_collectVisibleTexts(tester)}. Diagnostics: $diagnostics',
      );
    }

    if (ownerRoot.evaluate().isEmpty) {
      final diagnostics = await _collectOwnerDiagnostics();
      fail(
        'Owner workspace did not appear. Visible texts: ${_collectVisibleTexts(tester)}. Diagnostics: $diagnostics',
      );
    }

    expect(ownerRoot, findsOneWidget);

    await tester.tap(find.text('Businesses').last);
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(
      find.byKey(const ValueKey('owner-live-catalog-section')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('owner-branding-section')),
      findsOneWidget,
    );
    expect(find.textContaining('Active business:'), findsOneWidget);

    final businessSnapshot = await FirebaseFirestore.instance
        .doc('businesses/$activeBusinessId')
        .get();
    final businessData = businessSnapshot.data() ?? <String, dynamic>{};
    final activeGroupId = businessData['groupId'] as String? ?? '';
    if (activeGroupId.trim().isEmpty) {
      fail('Owner smoke needs an active tandem group on $activeBusinessId.');
    }

    final smokeNonce = DateTime.now().microsecondsSinceEpoch.toString();
    final adjustmentPhone = _buildSmokePhone(smokeNonce);
    final adjustmentNote = 'owner smoke credit $smokeNonce';
    const adjustmentAmount = 12000;
    const redeemAmount = 5000;
    final redeemTicketRef = 'owner-smoke-redeem-$smokeNonce';
    final mediaTitle = 'Owner smoke media $smokeNonce';
    final mediaCaption = 'Storage media smoke card $smokeNonce';

    if (expectStorageReady) {
      final beforeBrandingDoc = await FirebaseFirestore.instance
          .doc('businesses/$activeBusinessId')
          .get();
      final beforeBrandingData =
          beforeBrandingDoc.data() ?? <String, dynamic>{};
      final previousLogoStoragePath =
          beforeBrandingData['logoStoragePath'] as String? ?? '';
      final previousCoverStoragePath =
          beforeBrandingData['coverImageStoragePath'] as String? ?? '';
      final adminService = OwnerBusinessAdminService(
        firestore: FirebaseFirestore.instance,
        storage: FirebaseStorage.instance,
        bootstrapResult: const FirebaseBootstrapResult.connected(
          'Owner storage smoke',
        ),
      );
      final fakePicker = const _FakeBusinessAssetPicker();
      final logoFile = await fakePicker.pickImage(dialogTitle: 'branding-logo');
      final coverFile = await fakePicker.pickImage(
        dialogTitle: 'branding-cover',
      );
      if (logoFile == null || coverFile == null) {
        fail('Fake business asset picker did not return branding files.');
      }

      await adminService.updateBusinessBranding(
        businessId: activeBusinessId,
        logoUrl: '',
        coverImageUrl: '',
        currentLogoStoragePath: previousLogoStoragePath,
        currentCoverImageStoragePath: previousCoverStoragePath,
        logoFile: logoFile,
        coverFile: coverFile,
      );
      final brandingData = await _waitForBrandingAssetChange(
        businessId: activeBusinessId,
        previousLogoStoragePath: previousLogoStoragePath,
        previousCoverStoragePath: previousCoverStoragePath,
      );

      if (brandingData == null) {
        fail(
          'Branding upload service did not persist new Storage-backed fields.',
        );
      }

      final logoStoragePath = brandingData['logoStoragePath'] as String? ?? '';
      final coverStoragePath =
          brandingData['coverImageStoragePath'] as String? ?? '';
      final logoUrl = brandingData['logoUrl'] as String? ?? '';
      final coverUrl = brandingData['coverImageUrl'] as String? ?? '';

      if (logoStoragePath.isEmpty ||
          coverStoragePath.isEmpty ||
          logoUrl.isEmpty ||
          coverUrl.isEmpty) {
        fail(
          'Branding upload did not persist Storage-backed fields. businessData=$brandingData',
        );
      }

      await FirebaseStorage.instance.ref(logoStoragePath).getMetadata();
      await FirebaseStorage.instance.ref(coverStoragePath).getMetadata();
    } else {
      debugPrint(
        'Skipping live branding upload because TEAMCASH_EXPECT_STORAGE_READY is false.',
      );
    }

    final addMediaButton = find.byKey(const ValueKey('owner-media-add-button'));
    await _scrollIntoView(tester, addMediaButton);
    await tester.tap(addMediaButton, warnIfMissed: false);
    await tester.pumpAndSettle(const Duration(seconds: 2));
    await tester.enterText(
      find.byKey(const ValueKey('owner-media-title-input')),
      mediaTitle,
    );
    await tester.tap(
      find.byKey(const ValueKey('owner-media-upload-image')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle(const Duration(seconds: 1));
    await _pumpUntilVisible(
      tester,
      find.byKey(const ValueKey('owner-media-upload-name')),
    );
    await tester.enterText(
      find.byKey(const ValueKey('owner-media-caption-input')),
      mediaCaption,
    );
    await tester.tap(find.byKey(const ValueKey('owner-media-save')));
    await tester.pump();

    final mediaDocument = await _waitForMediaDocument(
      businessId: activeBusinessId,
      title: mediaTitle,
      requireStorageBacked: true,
    );
    if (mediaDocument == null) {
      fail(
        'Owner media create flow did not persist a document. Visible texts: ${_collectVisibleTexts(tester)}',
      );
    }

    final mediaDocId = mediaDocument.id;
    final mediaImageUrl = mediaDocument.data['imageUrl'] as String? ?? '';
    final mediaStoragePath = mediaDocument.data['storagePath'] as String? ?? '';
    if (mediaImageUrl.isEmpty || mediaStoragePath.isEmpty) {
      fail('Owner media upload did not persist Storage-backed fields.');
    }
    await FirebaseStorage.instance.ref(mediaStoragePath).getMetadata();

    final mediaRow = find.byKey(ValueKey('owner-media-row-$mediaDocId'));
    await _scrollIntoView(tester, mediaRow);
    expect(mediaRow, findsOneWidget);
    expect(find.text('Storage-backed'), findsWidgets);

    final deleteMediaButton = find.byKey(
      ValueKey('owner-media-delete-$mediaDocId'),
    );
    await _pumpUntilVisible(tester, deleteMediaButton);
    await tester.ensureVisible(deleteMediaButton);
    await tester.pumpAndSettle(const Duration(milliseconds: 600));
    await tester.tap(deleteMediaButton, warnIfMissed: false);
    await tester.pumpAndSettle(const Duration(seconds: 2));
    final confirmDeleteButton = find.byKey(
      const ValueKey('owner-media-confirm-delete'),
    );
    final confirmDeleteFallback = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.text('Delete'),
    );
    final deleteDialogResolved = await _pumpUntilAnyVisible(tester, [
      confirmDeleteButton,
      confirmDeleteFallback,
    ], timeout: const Duration(seconds: 15));
    if (!deleteDialogResolved) {
      fail(
        'Owner media delete dialog did not open. Visible texts: ${_collectVisibleTexts(tester)}',
      );
    }
    await tester.tap(
      confirmDeleteButton.evaluate().isNotEmpty
          ? confirmDeleteButton
          : confirmDeleteFallback,
      warnIfMissed: false,
    );
    await tester.pump();

    final mediaDeleted = await _waitForMediaDeletion(
      businessId: activeBusinessId,
      mediaId: mediaDocId,
    );
    if (!mediaDeleted) {
      fail(
        'Owner media delete flow did not remove the document. Visible texts: ${_collectVisibleTexts(tester)}',
      );
    }
    final mediaStorageDeleted = await _waitForStorageDeletion(mediaStoragePath);
    if (!mediaStorageDeleted) {
      fail('Owner media delete flow did not remove the Storage object.');
    }

    await tester.tap(find.text('Dashboard').last);
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(
      find.byKey(const ValueKey('owner-dashboard-trend-section')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('owner-business-performance-section')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('owner-ledger-controls-section')),
      findsOneWidget,
    );

    final adminAdjustButton = find.byKey(
      const ValueKey('owner-admin-adjust-button'),
    );
    await _scrollIntoView(tester, adminAdjustButton);
    await tester.tap(adminAdjustButton, warnIfMissed: false);
    await tester.pumpAndSettle(const Duration(seconds: 2));
    await tester.enterText(
      find.byKey(const ValueKey('owner-admin-adjust-phone-input')),
      adjustmentPhone,
    );
    await tester.enterText(
      find.byKey(const ValueKey('owner-admin-adjust-amount-input')),
      adjustmentAmount.toString(),
    );
    await tester.enterText(
      find.byKey(const ValueKey('owner-admin-adjust-note-input')),
      adjustmentNote,
    );
    await tester.tap(find.byKey(const ValueKey('owner-admin-adjust-submit')));
    await tester.pump();

    final adminAdjustSuccess = find.textContaining(
      'Manual credit adjustment applied',
    );
    final adminAdjustError = find.textContaining('Cloud Function call failed');
    final adminAdjustResolved = await _pumpUntilAnyVisible(tester, [
      adminAdjustSuccess,
      adminAdjustError,
    ], timeout: const Duration(seconds: 45));

    if (!adminAdjustResolved || adminAdjustSuccess.evaluate().isEmpty) {
      fail(
        'Admin adjustment flow did not resolve successfully. Visible texts: ${_collectVisibleTexts(tester)}',
      );
    }

    final redeemResponse = await FirebaseFunctions.instance
        .httpsCallable('redeemCashback')
        .call({
          'businessId': activeBusinessId,
          'groupId': activeGroupId,
          'redeemMinorUnits': redeemAmount,
          'sourceTicketRef': redeemTicketRef,
          'customerPhoneE164': adjustmentPhone,
        });
    final redeemData = Map<String, dynamic>.from(
      redeemResponse.data as Map<dynamic, dynamic>,
    );
    final redemptionBatchId = redeemData['redemptionBatchId'] as String? ?? '';
    if (redemptionBatchId.isEmpty) {
      fail('Redeem callable did not return redemptionBatchId: $redeemData');
    }
    final redeemedMinorUnits =
        (redeemData['redeemedMinorUnits'] as num?)?.toInt() ?? 0;
    if (redeemedMinorUnits != redeemAmount) {
      fail(
        'Redeem callable returned unexpected amount. expected=$redeemAmount actual=$redeemedMinorUnits data=$redeemData',
      );
    }

    final refundButton = find.byKey(
      const ValueKey('owner-refund-cashback-button'),
    );
    await _scrollIntoView(tester, refundButton);
    await tester.tap(refundButton, warnIfMissed: false);
    await tester.pumpAndSettle(const Duration(seconds: 2));
    await tester.enterText(
      find.byKey(const ValueKey('owner-refund-batch-id-input')),
      redemptionBatchId,
    );
    await tester.enterText(
      find.byKey(const ValueKey('owner-refund-note-input')),
      'owner smoke refund $smokeNonce',
    );
    await tester.tap(find.byKey(const ValueKey('owner-refund-submit')));
    await tester.pump();

    final refundSuccess = find.textContaining('Refund created for batch');
    final refundError = find.textContaining('Cloud Function call failed');
    final refundResolved = await _pumpUntilAnyVisible(tester, [
      refundSuccess,
      refundError,
    ], timeout: const Duration(seconds: 45));

    if (!refundResolved || refundSuccess.evaluate().isEmpty) {
      fail(
        'Refund flow did not resolve successfully. Visible texts: ${_collectVisibleTexts(tester)}',
      );
    }

    final refundVerificationResponse = await FirebaseFunctions.instance
        .httpsCallable('redeemCashback')
        .call({
          'businessId': activeBusinessId,
          'groupId': activeGroupId,
          'redeemMinorUnits': adjustmentAmount,
          'sourceTicketRef': 'owner-smoke-refund-verify-$smokeNonce',
          'customerPhoneE164': adjustmentPhone,
        });
    final refundVerificationData = Map<String, dynamic>.from(
      refundVerificationResponse.data as Map<dynamic, dynamic>,
    );
    final refundVerifiedAmount =
        (refundVerificationData['redeemedMinorUnits'] as num?)?.toInt() ?? 0;
    if (refundVerifiedAmount != adjustmentAmount) {
      fail(
        'Refund verification redeem returned unexpected amount. expected=$adjustmentAmount actual=$refundVerifiedAmount data=$refundVerificationData',
      );
    }

    final expireButton = find.byKey(
      const ValueKey('owner-expire-wallet-lots-button'),
    );
    await _scrollIntoView(tester, expireButton);
    await tester.tap(expireButton, warnIfMissed: false);
    await tester.pumpAndSettle(const Duration(seconds: 2));
    await tester.tap(find.byKey(const ValueKey('owner-expire-submit')));
    await tester.pump();

    final expireSuccess = find.textContaining('Expiry sweep finished.');
    final expireError = find.textContaining('Cloud Function call failed');
    final expireResolved = await _pumpUntilAnyVisible(tester, [
      expireSuccess,
      expireError,
    ], timeout: const Duration(seconds: 45));

    if (!expireResolved || expireSuccess.evaluate().isEmpty) {
      fail(
        'Expiry sweep flow did not resolve successfully. Visible texts: ${_collectVisibleTexts(tester)}',
      );
    }

    await tester.tap(find.text('Staffs').last);
    await tester.pumpAndSettle(const Duration(seconds: 2));
    await _scrollToTop(tester);
    expect(find.byKey(const ValueKey('owner-staff-section')), findsOneWidget);
    await _pumpUntilVisible(
      tester,
      find.byKey(const ValueKey('owner-group-audit-section')),
    );
    expect(
      find.byKey(const ValueKey('owner-group-audit-section')),
      findsOneWidget,
    );

    final notificationBell = find.byKey(
      const ValueKey('notification-bell-button'),
    );
    await _pumpUntilVisible(tester, notificationBell);
    final bellRect = tester.getRect(notificationBell);
    await tester.tapAt(Offset(bellRect.left + 8, bellRect.center.dy));
    await tester.pumpAndSettle(const Duration(seconds: 2));
    await _pumpUntilVisible(
      tester,
      find.byKey(const ValueKey('notification-center-sheet')),
    );
    final openApprovalsButton = find.text('Open approvals');
    await _pumpUntilVisible(tester, openApprovalsButton);
    await tester.tap(openApprovalsButton, warnIfMissed: false);
    await tester.pumpAndSettle(const Duration(seconds: 2));
    await _pumpUntilVisible(
      tester,
      find.byKey(const ValueKey('owner-staff-section')),
    );

    final staffActions = find.byKey(
      const ValueKey('owner-staff-actions-$resetStaffUsername'),
    );
    await _scrollIntoView(tester, staffActions);
    await tester.tap(staffActions, warnIfMissed: false);
    await tester.pumpAndSettle(const Duration(seconds: 2));

    final editStaffAction = find.byKey(
      const ValueKey('owner-staff-edit-$resetStaffUsername'),
    );
    await _pumpUntilVisible(tester, editStaffAction);
    await tester.tap(editStaffAction);
    await tester.pumpAndSettle(const Duration(seconds: 2));

    final editDisplayNameField = find.byKey(
      const ValueKey('owner-staff-edit-display-name-input'),
    );
    expect(editDisplayNameField, findsOneWidget);
    await tester.enterText(editDisplayNameField, editStaffDisplayName);
    await tester.tap(find.byKey(const ValueKey('owner-staff-edit-submit')));
    await tester.pump();

    final editSuccess = find.textContaining('Staff profile updated for');
    final editResolved = await _pumpUntilAnyVisible(tester, [
      editSuccess,
      find.textContaining('Cloud Function call failed'),
    ], timeout: const Duration(seconds: 45));

    if (!editResolved || editSuccess.evaluate().isEmpty) {
      fail(
        'Edit staff flow did not resolve successfully. Visible texts: ${_collectVisibleTexts(tester)}',
      );
    }
    await _scrollIntoView(tester, staffActions);

    await tester.tap(staffActions, warnIfMissed: false);
    await tester.pumpAndSettle(const Duration(seconds: 2));

    final resetAction = find.byKey(
      const ValueKey('owner-staff-reset-$resetStaffUsername'),
    );
    await _pumpUntilVisible(tester, resetAction);
    await tester.tap(resetAction);
    await tester.pumpAndSettle(const Duration(seconds: 2));

    final resetPasswordField = find.byKey(
      const ValueKey('owner-staff-reset-password-input'),
    );
    expect(resetPasswordField, findsOneWidget);
    await tester.enterText(
      resetPasswordField,
      const String.fromEnvironment(
        'TEAMCASH_RESET_STAFF_PASSWORD',
        defaultValue: 'Teamcash!2026',
      ),
    );
    await tester.tap(find.byKey(const ValueKey('owner-staff-reset-submit')));
    await tester.pump();

    final resetSuccess = find.textContaining('Password updated for');
    final resetError = find.textContaining('Cloud Function call failed');
    final resetResolved = await _pumpUntilAnyVisible(tester, [
      resetSuccess,
      resetError,
    ], timeout: const Duration(seconds: 45));

    if (!resetResolved) {
      fail(
        'Reset password flow did not resolve. Visible texts: ${_collectVisibleTexts(tester)}',
      );
    }

    if (resetError.evaluate().isNotEmpty) {
      fail(
        'Reset password flow failed. Visible texts: ${_collectVisibleTexts(tester)}',
      );
    }

    expect(resetSuccess, findsOneWidget);
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

Future<void> _scrollIntoView(
  WidgetTester tester,
  Finder finder, {
  double delta = 400,
}) async {
  await _pumpUntilVisible(tester, finder);
  final scrollables = find.byType(Scrollable);
  if (scrollables.evaluate().isNotEmpty) {
    await tester.scrollUntilVisible(
      finder,
      delta,
      scrollable: scrollables.first,
    );
    await tester.pumpAndSettle(const Duration(seconds: 1));
    return;
  }

  await tester.ensureVisible(finder);
  await tester.pumpAndSettle(const Duration(seconds: 1));
}

Future<void> _scrollToTop(WidgetTester tester) async {
  final scrollables = find.byType(Scrollable);
  if (scrollables.evaluate().isEmpty) {
    return;
  }

  await tester.fling(scrollables.first, const Offset(0, 1600), 2000);
  await tester.pumpAndSettle(const Duration(seconds: 1));
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

String _buildSmokePhone(String seed) {
  final digits = seed.replaceAll(RegExp(r'\D'), '');
  final suffix = digits.length >= 9
      ? digits.substring(digits.length - 9)
      : digits.padLeft(9, '0');
  return '+998$suffix';
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

  return texts.take(20).join(' | ');
}

Future<String> _collectOwnerDiagnostics() async {
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
  final businessIds =
      ((operatorData['businessIds'] as List<dynamic>?) ?? const [])
          .whereType<String>()
          .toList();
  String firstBusinessStatus = 'n/a';
  String statsStatus = 'n/a';
  String staffQueryStatus = 'n/a';
  String groupStatus = 'n/a';
  String joinRequestsStatus = 'n/a';

  if (businessIds.isNotEmpty) {
    final firstBusinessId = businessIds.first;
    final businessDoc = await firestore
        .doc('businesses/$firstBusinessId')
        .get()
        .timeout(
          const Duration(seconds: 10),
          onTimeout: () => throw TimeoutException('business doc timeout'),
        );
    firstBusinessStatus = 'exists=${businessDoc.exists}';

    final statsQuery = await firestore
        .collection('businesses')
        .doc(firstBusinessId)
        .collection('statsDaily')
        .get()
        .timeout(
          const Duration(seconds: 10),
          onTimeout: () => throw TimeoutException('statsDaily timeout'),
        );
    statsStatus = 'docs=${statsQuery.docs.length}';

    final businessData = businessDoc.data() ?? <String, dynamic>{};
    final groupId = businessData['groupId'] as String?;
    if (groupId != null && groupId.isNotEmpty) {
      final groupDoc = await firestore
          .doc('groups/$groupId')
          .get()
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () => throw TimeoutException('group doc timeout'),
          );
      groupStatus = 'exists=${groupDoc.exists}';

      final joinRequestsQuery = await firestore
          .collection('groups')
          .doc(groupId)
          .collection('joinRequests')
          .get()
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () => throw TimeoutException('joinRequests timeout'),
          );
      joinRequestsStatus = 'docs=${joinRequestsQuery.docs.length}';
    }
  }

  final staffQuery = await firestore
      .collection('operatorAccounts')
      .where('ownerId', isEqualTo: user.uid)
      .where('role', isEqualTo: 'staff')
      .limit(50)
      .get()
      .timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw TimeoutException('staff query timeout'),
      );
  staffQueryStatus = 'docs=${staffQuery.docs.length}';

  return [
    'uid=${user.uid}',
    'email=${user.email ?? 'n/a'}',
    'phone=${user.phoneNumber ?? 'n/a'}',
    'claimsRole=${tokenResult.claims?['role'] ?? 'n/a'}',
    'operatorDocExists=${operatorDoc.exists}',
    'businessIds=${businessIds.join('|')}',
    'firstBusiness=$firstBusinessStatus',
    'statsDaily=$statsStatus',
    'staffQuery=$staffQueryStatus',
    'group=$groupStatus',
    'joinRequests=$joinRequestsStatus',
  ].join(', ');
}

Future<Map<String, dynamic>?> _waitForBrandingAssetChange({
  required String businessId,
  required String previousLogoStoragePath,
  required String previousCoverStoragePath,
  Duration timeout = const Duration(seconds: 90),
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    final snapshot = await FirebaseFirestore.instance
        .doc('businesses/$businessId')
        .get();
    final data = snapshot.data() ?? <String, dynamic>{};
    final logoStoragePath = data['logoStoragePath'] as String? ?? '';
    final coverStoragePath = data['coverImageStoragePath'] as String? ?? '';
    final logoChanged =
        logoStoragePath.isNotEmpty &&
        logoStoragePath != previousLogoStoragePath;
    final coverChanged =
        coverStoragePath.isNotEmpty &&
        coverStoragePath != previousCoverStoragePath;
    if (logoChanged && coverChanged) {
      return data;
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }

  return null;
}

Future<_MediaDocumentState?> _waitForMediaDocument({
  required String businessId,
  required String title,
  bool requireStorageBacked = false,
  Duration timeout = const Duration(seconds: 45),
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    final query = await FirebaseFirestore.instance
        .collection('businesses')
        .doc(businessId)
        .collection('media')
        .where('title', isEqualTo: title)
        .limit(1)
        .get();
    if (query.docs.isNotEmpty) {
      final doc = query.docs.first;
      final data = doc.data();
      final hasStorageFields =
          (data['storagePath'] as String? ?? '').isNotEmpty &&
          (data['imageUrl'] as String? ?? '').isNotEmpty;
      if (!requireStorageBacked || hasStorageFields) {
        return _MediaDocumentState(id: doc.id, data: data);
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }

  return null;
}

Future<bool> _waitForMediaDeletion({
  required String businessId,
  required String mediaId,
  Duration timeout = const Duration(seconds: 45),
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    final snapshot = await FirebaseFirestore.instance
        .doc('businesses/$businessId/media/$mediaId')
        .get();
    if (!snapshot.exists) {
      return true;
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }

  return false;
}

Future<bool> _waitForStorageDeletion(
  String storagePath, {
  Duration timeout = const Duration(seconds: 45),
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    try {
      await FirebaseStorage.instance.ref(storagePath).getMetadata();
    } on FirebaseException catch (error) {
      final normalizedMessage = error.message?.toLowerCase() ?? '';
      if (error.code == 'object-not-found' ||
          normalizedMessage.contains('object') &&
              normalizedMessage.contains('not found')) {
        return true;
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }

  return false;
}

class _MediaDocumentState {
  const _MediaDocumentState({required this.id, required this.data});

  final String id;
  final Map<String, dynamic> data;
}

class _FakeBusinessAssetPicker implements BusinessAssetPicker {
  const _FakeBusinessAssetPicker();

  @override
  Future<PickedBusinessAsset?> pickImage({String? dialogTitle}) async {
    final bytes = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO7Z0ioAAAAASUVORK5CYII=',
    );
    final label = (dialogTitle ?? 'upload')
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'-{2,}'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
    return PickedBusinessAsset(
      bytes: bytes,
      fileName: '$label.png',
      contentType: 'image/png',
    );
  }
}
