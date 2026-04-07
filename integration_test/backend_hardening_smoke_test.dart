import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:teamcash/firebase_options.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'claimCustomerWalletByPhone rejects sessions without verified phone auth',
    (tester) async {
      await _ensureInitialized();
      await _signOutQuietly();
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

      try {
        await _functions().httpsCallable('claimCustomerWalletByPhone').call({});
        fail(
          'claimCustomerWalletByPhone should reject sessions without phone auth.',
        );
      } on FirebaseFunctionsException catch (error) {
        expect(error.code, 'failed-precondition');
        expect(
          error.message ?? '',
          contains('Verified phone auth is required'),
        );
      }
    },
  );

  testWidgets(
    'requestGroupJoin reuses the existing pending request for duplicate submissions',
    (tester) async {
      await _ensureInitialized();
      await _signOutQuietly();
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: const String.fromEnvironment(
          'TEAMCASH_OWNER_ALIAS_EMAIL',
          defaultValue: 'aziza.owner@operators.teamcash.local',
        ),
        password: const String.fromEnvironment(
          'TEAMCASH_OWNER_PASSWORD',
          defaultValue: 'Teamcash!2026',
        ),
      );

      final suffix = DateTime.now().microsecondsSinceEpoch.toString();
      final createResponse = await _functions()
          .httpsCallable('createBusiness')
          .call({
            'name': 'Hardening Join $suffix',
            'category': 'Clinic',
            'description':
                'Integration test business for duplicate join coverage.',
            'address': '88 Hardening Street, Tashkent',
            'workingHours': '09:00 - 18:00',
            'phoneNumbers': ['+99890${suffix.substring(suffix.length - 7)}'],
            'cashbackBasisPoints': 450,
            'redeemPolicy': 'Integration test policy only.',
          });
      final createData = Map<String, dynamic>.from(
        createResponse.data as Map<dynamic, dynamic>,
      );
      final businessId = createData['businessId'] as String? ?? '';
      if (businessId.isEmpty) {
        fail('createBusiness did not return businessId: $createData');
      }

      final firstJoinResponse = await _functions()
          .httpsCallable('requestGroupJoin')
          .call({'groupId': 'old-town-circle', 'businessId': businessId});
      final secondJoinResponse = await _functions()
          .httpsCallable('requestGroupJoin')
          .call({'groupId': 'old-town-circle', 'businessId': businessId});

      final firstJoin = Map<String, dynamic>.from(
        firstJoinResponse.data as Map<dynamic, dynamic>,
      );
      final secondJoin = Map<String, dynamic>.from(
        secondJoinResponse.data as Map<dynamic, dynamic>,
      );

      expect(firstJoin['requestId'], isNotEmpty);
      expect(secondJoin['requestId'], firstJoin['requestId']);
      expect(secondJoin['reusedExisting'], isTrue);
      expect(secondJoin['status'], anyOf('pending', 'approved'));
    },
  );

  testWidgets(
    'notification recipients can mark their own notifications as read',
    (tester) async {
      await _ensureInitialized();
      await _signOutQuietly();
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: const String.fromEnvironment(
          'TEAMCASH_OWNER_ALIAS_EMAIL',
          defaultValue: 'aziza.owner@operators.teamcash.local',
        ),
        password: const String.fromEnvironment(
          'TEAMCASH_OWNER_PASSWORD',
          defaultValue: 'Teamcash!2026',
        ),
      );

      final ownerUid = FirebaseAuth.instance.currentUser?.uid;
      if (ownerUid == null) {
        fail('Owner auth session is missing.');
      }

      final query = await FirebaseFirestore.instance
          .collection('notifications')
          .where('recipientUid', isEqualTo: ownerUid)
          .limit(1)
          .get();
      if (query.docs.isEmpty) {
        fail(
          'Expected at least one owner notification for notification rules coverage.',
        );
      }

      final notificationRef = query.docs.first.reference;
      await notificationRef.update({
        'isRead': true,
        'readAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      final refreshed = await notificationRef.get();
      final data = refreshed.data() ?? <String, dynamic>{};
      expect(data['isRead'], isTrue);
    },
  );
}

Future<void> _ensureInitialized() async {
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  }
}

FirebaseFunctions _functions() {
  return FirebaseFunctions.instanceFor(
    region: const String.fromEnvironment(
      'TEAMCASH_FUNCTIONS_REGION',
      defaultValue: 'us-central1',
    ),
  );
}

Future<void> _signOutQuietly() async {
  await FirebaseAuth.instance.signOut().catchError((_) => null);
}
