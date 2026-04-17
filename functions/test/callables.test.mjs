import test, { beforeEach } from 'node:test';
import assert from 'node:assert/strict';

import {
  callFunction,
  createEmailUser,
  resetEmulators,
  seedBusiness,
  seedGroup,
  seedOwnerAccount,
  signInWithPassword,
  adminDb,
} from './support/emulator_test_helper.mjs';

beforeEach(async () => {
  await resetEmulators();
});

test('createBusiness creates a business and links it to the owner', async () => {
  const ownerUid = 'owner-create-business';
  const ownerEmail = 'owner.create@teamcash.local';
  const ownerPassword = 'Teamcash!2026';

  await createEmailUser({
    uid: ownerUid,
    email: ownerEmail,
    password: ownerPassword,
    displayName: 'Owner Create',
  });
  await seedOwnerAccount({
    uid: ownerUid,
    displayName: 'Owner Create',
  });

  const idToken = await signInWithPassword(ownerEmail, ownerPassword);
  const result = await callFunction(
    'createBusiness',
    {
      name: 'Sunrise Bakery',
      category: 'Bakery',
      description: 'Fresh bread and coffee.',
      address: 'Tashkent',
      workingHours: '08:00 - 20:00',
      phoneNumbers: ['+998901234567'],
      cashbackBasisPoints: 650,
      redeemPolicy: 'Redeem up to 30%.',
    },
    idToken,
  );

  assert.equal(result.status, 'created');
  assert.ok(result.businessId);

  const businessDoc = await adminDb.doc(`businesses/${result.businessId}`).get();
  const ownerDoc = await adminDb.doc(`operatorAccounts/${ownerUid}`).get();
  assert.equal(businessDoc.data()?.name, 'Sunrise Bakery');
  assert.ok(ownerDoc.data()?.businessIds.includes(result.businessId));
});

test('createStaffAccount writes auth and Firestore records', async () => {
  const ownerUid = 'owner-create-staff';
  const ownerEmail = 'owner.staff@teamcash.local';
  const ownerPassword = 'Teamcash!2026';
  const businessId = 'anchor-owner-biz';

  await createEmailUser({
    uid: ownerUid,
    email: ownerEmail,
    password: ownerPassword,
    displayName: 'Owner Staff',
  });
  await seedOwnerAccount({
    uid: ownerUid,
    displayName: 'Owner Staff',
    businessIds: [businessId],
  });
  await seedBusiness({
    businessId,
    ownerUid,
    name: 'Anchor Business',
  });

  const idToken = await signInWithPassword(ownerEmail, ownerPassword);
  const result = await callFunction(
    'createStaffAccount',
    {
      businessId,
      username: 'nadia.silkroad',
      displayName: 'Nadia Silk Road',
      password: 'Teamcash!2026',
    },
    idToken,
  );

  assert.equal(result.businessId, businessId);
  assert.equal(result.username, 'nadia.silkroad');
  assert.match(result.loginAliasEmail, /operators\.teamcash\.local$/);

  const operatorDoc = await adminDb.doc(`operatorAccounts/${result.staffUid}`).get();
  const usernameDoc = await adminDb.doc('operatorUsernames/nadia.silkroad').get();
  assert.equal(operatorDoc.data()?.role, 'staff');
  assert.equal(usernameDoc.data()?.uid, result.staffUid);
});

test('requestGroupJoin is idempotent for duplicate submissions', async () => {
  const ownerUid = 'owner-join-request';
  const ownerEmail = 'owner.join@teamcash.local';
  const ownerPassword = 'Teamcash!2026';
  const anchorBusinessId = 'old-town-anchor';
  const pendingBusinessId = 'pending-join-business';
  const groupId = 'old-town-circle';

  await createEmailUser({
    uid: ownerUid,
    email: ownerEmail,
    password: ownerPassword,
    displayName: 'Owner Join',
  });
  await seedOwnerAccount({
    uid: ownerUid,
    displayName: 'Owner Join',
    businessIds: [pendingBusinessId],
  });
  await seedBusiness({
    businessId: anchorBusinessId,
    ownerUid: 'anchor-owner',
    name: 'Anchor Cafe',
    groupId,
    groupName: 'Old Town Circle',
    groupMembershipStatus: 'active',
  });
  await seedBusiness({
    businessId: pendingBusinessId,
    ownerUid,
    name: 'Pending Salon',
  });
  await seedGroup({
    groupId,
    name: 'Old Town Circle',
    activeBusinessIds: [anchorBusinessId],
    createdByOwnerUid: 'anchor-owner',
    createdByBusinessId: anchorBusinessId,
  });

  const idToken = await signInWithPassword(ownerEmail, ownerPassword);
  const firstResult = await callFunction(
    'requestGroupJoin',
    { groupId, businessId: pendingBusinessId },
    idToken,
  );
  const secondResult = await callFunction(
    'requestGroupJoin',
    { groupId, businessId: pendingBusinessId },
    idToken,
  );

  assert.ok(firstResult.requestId);
  assert.equal(secondResult.requestId, firstResult.requestId);
  assert.equal(secondResult.reusedExisting, true);
});

test('claimCustomerWalletByPhone rejects non-phone sessions', async () => {
  const clientUid = 'client-no-phone';
  const clientEmail = 'client.no.phone@teamcash.local';
  const clientPassword = 'Teamcash!2026';

  await createEmailUser({
    uid: clientUid,
    email: clientEmail,
    password: clientPassword,
    displayName: 'Client No Phone',
  });

  const idToken = await signInWithPassword(clientEmail, clientPassword);

  await assert.rejects(
    () => callFunction('claimCustomerWalletByPhone', {}, idToken),
    (error) => {
      assert.equal(error.code, 'failed-precondition');
      assert.match(error.message, /Verified phone auth is required/i);
      return true;
    },
  );
});
