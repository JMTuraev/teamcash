import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:teamcash/app/app.dart';
import 'package:teamcash/app/bootstrap/firebase_bootstrap.dart';
import 'package:teamcash/core/services/teamcash_functions_service.dart';

final accountProfileServiceProvider = Provider<AccountProfileService>(
  (ref) => AccountProfileService(
    firestore: FirebaseFirestore.instance,
    auth: FirebaseAuth.instance,
    bootstrapResult: ref.watch(firebaseStatusProvider),
  ),
);

class AccountProfileService {
  const AccountProfileService({
    required FirebaseFirestore firestore,
    required FirebaseAuth auth,
    required FirebaseBootstrapResult bootstrapResult,
  }) : _firestore = firestore,
       _auth = auth,
       _bootstrapResult = bootstrapResult;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final FirebaseBootstrapResult _bootstrapResult;

  bool get isConnected =>
      _bootstrapResult.mode == FirebaseBootstrapMode.connected;

  Future<void> updateCurrentOperatorProfile({
    required String displayName,
    required String preferredStartTab,
    required bool notificationDigestOptIn,
  }) async {
    _ensureConnected();
    final user = _currentUser();
    final trimmedDisplayName = displayName.trim();
    if (trimmedDisplayName.isEmpty) {
      throw const TeamCashActionUnavailable(
        'Display name is required before saving the profile.',
      );
    }

    await user.updateDisplayName(trimmedDisplayName);
    await _firestore.doc('operatorAccounts/${user.uid}').update({
      'displayName': trimmedDisplayName,
      'preferredStartTab': preferredStartTab.trim(),
      'notificationDigestOptIn': notificationDigestOptIn,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> updateCurrentClientProfile({
    required String customerId,
    required String displayName,
    required bool marketingOptIn,
    required String preferredClientTab,
  }) async {
    _ensureConnected();
    final user = _currentUser();
    final trimmedCustomerId = customerId.trim();
    final trimmedDisplayName = displayName.trim();
    if (trimmedCustomerId.isEmpty) {
      throw const TeamCashActionUnavailable(
        'Customer wallet link is missing for this client session.',
      );
    }
    if (trimmedDisplayName.isEmpty) {
      throw const TeamCashActionUnavailable(
        'Display name is required before saving the profile.',
      );
    }

    await user.updateDisplayName(trimmedDisplayName);
    await _firestore.doc('customers/$trimmedCustomerId').update({
      'displayName': trimmedDisplayName,
      'marketingOptIn': marketingOptIn,
      'preferredClientTab': preferredClientTab.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> changeCurrentOperatorPassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    _ensureConnected();
    final user = _currentUser();
    final email = user.email?.trim();
    if (email == null || email.isEmpty) {
      throw const TeamCashActionUnavailable(
        'Only owner and staff password sessions can change password here.',
      );
    }

    final trimmedCurrentPassword = currentPassword.trim();
    final trimmedNewPassword = newPassword.trim();
    if (trimmedCurrentPassword.isEmpty || trimmedNewPassword.isEmpty) {
      throw const TeamCashActionUnavailable(
        'Current password and new password are both required.',
      );
    }
    if (trimmedNewPassword.length < 8) {
      throw const TeamCashActionUnavailable(
        'New password must contain at least 8 characters.',
      );
    }

    await user.reauthenticateWithCredential(
      EmailAuthProvider.credential(
        email: email,
        password: trimmedCurrentPassword,
      ),
    );
    await user.updatePassword(trimmedNewPassword);
    await _firestore.doc('operatorAccounts/${user.uid}').update({
      'passwordChangedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  User _currentUser() {
    final user = _auth.currentUser;
    if (user == null) {
      throw const TeamCashActionUnavailable(
        'A signed-in Firebase session is required for this action.',
      );
    }
    return user;
  }

  void _ensureConnected() {
    if (!isConnected) {
      throw TeamCashActionUnavailable(_bootstrapResult.message);
    }
  }
}
