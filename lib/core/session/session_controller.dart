import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:teamcash/app/app.dart';
import 'package:teamcash/app/bootstrap/firebase_bootstrap.dart';
import 'package:teamcash/core/models/app_role.dart';
import 'package:teamcash/core/session/app_session.dart';

final appSessionControllerProvider =
    AsyncNotifierProvider<AppSessionController, AppSession?>(
      AppSessionController.new,
    );

final currentSessionProvider = Provider<AppSession?>(
  (ref) => ref.watch(appSessionControllerProvider).asData?.value,
);

class AppSessionController extends AsyncNotifier<AppSession?> {
  @override
  Future<AppSession?> build() async {
    final bootstrap = ref.watch(firebaseStatusProvider);

    if (bootstrap.mode == FirebaseBootstrapMode.preview) {
      return null;
    }

    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      return null;
    }

    return _resolveConnectedSession(currentUser);
  }

  Future<void> continueInPreview(AppRole role) async {
    final snapshot = ref.read(appSnapshotProvider);

    state = AsyncData(switch (role) {
      AppRole.owner => AppSession(
        role: role,
        displayName: snapshot.owner.ownerName,
        isPreview: true,
        businessIds: snapshot.owner.businesses.map((it) => it.id).toList(),
      ),
      AppRole.staff => AppSession(
        role: role,
        displayName: snapshot.staff.staffName,
        isPreview: true,
        businessId: snapshot.staff.businessId,
        businessIds: [snapshot.staff.businessId],
      ),
      AppRole.client => AppSession(
        role: role,
        displayName: snapshot.client.clientName,
        isPreview: true,
        phoneNumber: snapshot.client.phoneNumber,
      ),
    });
  }

  Future<void> signInOperator({
    required AppRole role,
    required String username,
    required String password,
  }) async {
    final bootstrap = ref.read(firebaseStatusProvider);
    if (bootstrap.mode == FirebaseBootstrapMode.preview) {
      await continueInPreview(role);
      return;
    }

    final previous = state.asData?.value;
    state = const AsyncLoading();

    try {
      final credential = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _buildOperatorAliasEmail(username),
        password: password,
      );

      final resolved = await _resolveConnectedSession(credential.user!);
      if (resolved == null) {
        await FirebaseAuth.instance.signOut();
        throw StateError('Signed in user does not have an app session.');
      }

      if (resolved.role != role) {
        await FirebaseAuth.instance.signOut();
        throw StateError(
          'This account belongs to the ${resolved.role.label.toLowerCase()} surface, not ${role.label.toLowerCase()}.',
        );
      }

      state = AsyncData(resolved);
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      state = AsyncData(previous);
      rethrow;
    }
  }

  Future<void> signOut() async {
    final current = state.asData?.value;

    if (current?.isPreview == true) {
      state = const AsyncData(null);
      return;
    }

    final bootstrap = ref.read(firebaseStatusProvider);
    if (bootstrap.mode == FirebaseBootstrapMode.connected) {
      await FirebaseAuth.instance.signOut();
    }

    state = const AsyncData(null);
  }

  Future<AppSession?> refreshCurrentSession() async {
    final bootstrap = ref.read(firebaseStatusProvider);
    if (bootstrap.mode == FirebaseBootstrapMode.preview) {
      state = const AsyncData(null);
      return null;
    }

    final currentUser = FirebaseAuth.instance.currentUser;
    final resolved = currentUser == null
        ? null
        : await _resolveConnectedSession(currentUser);
    state = AsyncData(resolved);
    return resolved;
  }

  Future<AppSession?> _resolveConnectedSession(User user) async {
    final firestore = FirebaseFirestore.instance;

    final operatorSnap = await firestore
        .doc('operatorAccounts/${user.uid}')
        .get();
    if (operatorSnap.exists) {
      final data = operatorSnap.data() ?? <String, dynamic>{};
      final roleValue = data['role'] as String?;
      final role = switch (roleValue) {
        'owner' => AppRole.owner,
        'staff' => AppRole.staff,
        _ => null,
      };

      if (role != null) {
        return AppSession(
          role: role,
          displayName:
              (data['displayName'] as String?) ??
              user.displayName ??
              user.email ??
              role.label,
          isPreview: false,
          uid: user.uid,
          businessId: data['businessId'] as String?,
          businessIds: ((data['businessIds'] as List<dynamic>?) ?? const [])
              .whereType<String>()
              .toList(),
        );
      }
    }

    final clientLinkSnap = await firestore
        .doc('customerAuthLinks/${user.uid}')
        .get();
    if (clientLinkSnap.exists) {
      final linkData = clientLinkSnap.data() ?? <String, dynamic>{};
      final customerId = linkData['customerId'] as String?;
      final customerSnap = customerId == null
          ? null
          : await firestore.doc('customers/$customerId').get();
      final customerData = customerSnap?.data() ?? <String, dynamic>{};

      return AppSession(
        role: AppRole.client,
        displayName:
            (customerData['displayName'] as String?) ??
            user.displayName ??
            user.phoneNumber ??
            'Client',
        isPreview: false,
        uid: user.uid,
        customerId: customerId,
        phoneNumber: user.phoneNumber,
      );
    }

    return null;
  }

  String _buildOperatorAliasEmail(String username) {
    final normalized = username.trim().toLowerCase().replaceAll(
      RegExp(r'\s+'),
      '.',
    );
    return '$normalized@operators.teamcash.local';
  }
}
