import test, { beforeEach, afterEach } from 'node:test';
import assert from 'node:assert/strict';

import {
  assertFails,
  assertSucceeds,
} from '@firebase/rules-unit-testing';

import {
  adminDb,
  createRulesTestEnvironment,
  resetEmulators,
} from './support/emulator_test_helper.mjs';

let rulesEnv;

beforeEach(async () => {
  await resetEmulators();
  rulesEnv = await createRulesTestEnvironment();
});

afterEach(async () => {
  await rulesEnv.cleanup();
});

test('client can update only allowed customer profile fields', async () => {
  const uid = 'client-rules-1';
  const customerId = 'customer-rules-1';

  await adminDb.doc(`customerAuthLinks/${uid}`).set({
    customerId,
    phoneE164: '+998901234567',
    linkedAt: new Date(),
  });
  await adminDb.doc(`customers/${customerId}`).set({
    displayName: 'Client Rules',
    marketingOptIn: true,
    preferredClientTab: 'wallet',
    updatedAt: new Date(),
  });

  const clientDb = rulesEnv.authenticatedContext(uid).firestore();
  const customerRef = clientDb.doc(`customers/${customerId}`);

  await assertSucceeds(
    customerRef.update({
      displayName: 'Updated Client',
      marketingOptIn: false,
      preferredClientTab: 'stores',
      updatedAt: new Date(),
    }),
  );

  await assertFails(
    customerRef.update({
      claimedByUid: 'other-user',
      updatedAt: new Date(),
    }),
  );
});

test('notification recipient can read and mark own notification as read', async () => {
  const uid = 'owner-rules-1';
  const notificationId = 'notification-rules-1';

  await adminDb.doc(`operatorAccounts/${uid}`).set({
    role: 'owner',
    businessIds: ['biz-1'],
    displayName: 'Owner Rules',
    disabledAt: null,
    createdAt: new Date(),
    updatedAt: new Date(),
  });
  await adminDb.doc(`notifications/${notificationId}`).set({
    recipientUid: uid,
    title: 'Needs review',
    body: 'Open and mark as read.',
    roleSurface: 'owner',
    kind: 'group_join_requested',
    isRead: false,
    readAt: null,
    createdAt: new Date(),
    updatedAt: new Date(),
  });

  const ownerDb = rulesEnv.authenticatedContext(uid).firestore();
  const notificationRef = ownerDb.doc(`notifications/${notificationId}`);

  await assertSucceeds(notificationRef.get());
  await assertSucceeds(
    notificationRef.update({
      isRead: true,
      readAt: new Date(),
      updatedAt: new Date(),
    }),
  );

  await assertFails(
    notificationRef.update({
      recipientUid: 'other-owner',
      updatedAt: new Date(),
    }),
  );
});

test('unrelated client cannot read another customer wallet lot', async () => {
  const readerUid = 'client-reader';
  const ownerCustomerId = 'wallet-owner-customer';
  const readerCustomerId = 'wallet-reader-customer';

  await adminDb.doc(`customerAuthLinks/${readerUid}`).set({
    customerId: readerCustomerId,
    phoneE164: '+998900000111',
    linkedAt: new Date(),
  });
  await adminDb.doc('walletLots/lot-1').set({
    ownerCustomerId,
    groupId: 'group-1',
    issuerBusinessId: 'biz-1',
    originalIssueEventId: 'event-1',
    initialMinorUnits: 10000,
    availableMinorUnits: 10000,
    status: 'active',
    expiresAt: new Date(),
  });

  const readerDb = rulesEnv.authenticatedContext(readerUid).firestore();
  await assertFails(readerDb.doc('walletLots/lot-1').get());
});
