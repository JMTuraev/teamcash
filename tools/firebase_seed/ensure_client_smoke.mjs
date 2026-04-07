import { readFile } from 'node:fs/promises';
import { homedir } from 'node:os';
import { join } from 'node:path';

import { initializeApp } from 'firebase/app';
import {
  createUserWithEmailAndPassword,
  getAuth,
  signInWithEmailAndPassword,
  signOut,
} from 'firebase/auth';

const firebaseConfig = {
  apiKey: 'AIzaSyAeu0zJbsfE6Ng6FROZ9LuJ1K7ByIiZQb0',
  appId: '1:136324996533:web:08b0be6cad81672b984dfc',
  messagingSenderId: '136324996533',
  projectId: 'teamcash-83a6e',
  authDomain: 'teamcash-83a6e.firebaseapp.com',
  storageBucket: 'teamcash-83a6e.firebasestorage.app',
  measurementId: 'G-3ZJQYKQ2D2',
};

const projectId = firebaseConfig.projectId;
const databaseId = '(default)';
const groupId = 'old-town-circle';
const firebaseCliOAuthClientId =
  '563584335869-fgrhgmd47bqnekij5i8b5pr03ho849e6.apps.googleusercontent.com';
const firebaseCliOAuthClientSecret = 'j9iVZfS8kkCEFUPaAeJV0sAi';
const clientAuth = {
  email: 'client.smoke@teamcash.local',
  password: 'Teamcash!2026',
};

const app = initializeApp(firebaseConfig);
const auth = getAuth(app);

await main();

async function main() {
  const authUser = await ensureUser(clientAuth.email, clientAuth.password);
  await signOut(auth);

  const suffix = `${Date.now()}`.slice(-9);
  const customerId = `customer-client-smoke-${suffix}`;
  const customerPhone = `+99890${suffix.slice(-7)}`;
  const senderCustomerId = `customer-client-smoke-sender-${suffix}`;
  const senderPhone = `+99891${suffix.slice(-7)}`;
  const checkoutId = `shared-checkout-client-smoke-${suffix}`;
  const incomingTransferId = `gift-transfer-client-smoke-incoming-${suffix}`;
  const accessToken = await readFirebaseAccessToken();
  const documents = buildFixtureDocuments({
    authUid: authUser.uid,
    customerId,
    customerPhone,
    senderCustomerId,
    senderPhone,
    checkoutId,
    incomingTransferId,
    suffix,
  });

  for (const [path, data] of documents) {
    await upsertFirestoreDocument(accessToken, path, data);
  }

  console.log(
    JSON.stringify(
      {
        ok: true,
        email: clientAuth.email,
        password: clientAuth.password,
        uid: authUser.uid,
        customerId,
        customerPhone,
        checkoutId,
        incomingTransferId,
      },
      null,
      2,
    ),
  );
}

async function ensureUser(email, password) {
  try {
    const credential = await createUserWithEmailAndPassword(auth, email, password);
    return { uid: credential.user.uid, created: true };
  } catch (error) {
    if (error?.code !== 'auth/email-already-in-use') {
      throw error;
    }

    const credential = await signInWithEmailAndPassword(auth, email, password);
    return { uid: credential.user.uid, created: false };
  }
}

function buildFixtureDocuments({
  authUid,
  customerId,
  customerPhone,
  senderCustomerId,
  senderPhone,
  checkoutId,
  incomingTransferId,
  suffix,
}) {
  const now = new Date();
  const seededAt = now.toISOString();
  const customerExpiry = addDays(now, 90).toISOString();
  const customerExpirySoon = addDays(now, 6).toISOString();
  const giftExpiry = addDays(now, 30).toISOString();
  const sharedCheckoutCreatedEventId = `shared-checkout-created-client-smoke-${suffix}`;
  const clientIssueEventId = `issue-client-smoke-main-${suffix}`;
  const clientIssueLotId = `lot-client-smoke-main-${suffix}`;
  const clientIssueEventTwoId = `issue-client-smoke-secondary-${suffix}`;
  const clientIssueLotTwoId = `lot-client-smoke-secondary-${suffix}`;
  const senderIssueEventId = `issue-client-smoke-sender-${suffix}`;
  const senderParentLotId = `lot-client-smoke-sender-parent-${suffix}`;
  const pendingGiftLotId = `lot-client-smoke-incoming-pending-${suffix}`;
  const transferOutEventId = `transfer-out-client-smoke-incoming-${suffix}`;
  const giftPendingEventId = `gift-pending-client-smoke-incoming-${suffix}`;

  return [
    [
      `customerPhoneIndex/${customerPhone}`,
      {
        customerId,
        phoneE164: customerPhone,
        createdAt: seededAt,
        updatedAt: seededAt,
      },
    ],
    [
      `customers/${customerId}`,
      {
        phoneE164: customerPhone,
        displayName: 'Client Smoke',
        isClaimed: true,
        claimedByUid: authUid,
        createdFrom: 'client_smoke_helper',
        createdAt: seededAt,
        updatedAt: seededAt,
        lastActivityAt: seededAt,
      },
    ],
    [
      `customerAuthLinks/${authUid}`,
      {
        customerId,
        phoneE164: customerPhone,
        linkedAt: seededAt,
        verifiedAt: seededAt,
      },
    ],
    [
      `ledgerEvents/${clientIssueEventId}`,
      {
        eventType: 'issue',
        groupId,
        issuerBusinessId: 'silk-road-cafe',
        actorBusinessId: 'silk-road-cafe',
        operatorUid: 'client-smoke-helper',
        targetCustomerId: customerId,
        amountMinorUnits: 72000,
        sourceTicketRef: `CLIENT-SMOKE-ISSUE-${suffix}`,
        paidMinorUnits: 1028572,
        cashbackBasisPoints: 700,
        customerPhoneE164: customerPhone,
        lotId: clientIssueLotId,
        originalIssueEventId: clientIssueEventId,
        participantBusinessIds: ['silk-road-cafe'],
        participantCustomerIds: [customerId],
        expiresAt: customerExpiry,
        createdAt: seededAt,
        updatedAt: seededAt,
      },
    ],
    [
      `walletLots/${clientIssueLotId}`,
      {
        ownerCustomerId: customerId,
        groupId,
        issuerBusinessId: 'silk-road-cafe',
        issuedByOperatorUid: 'client-smoke-helper',
        originalIssueEventId: clientIssueEventId,
        initialMinorUnits: 72000,
        availableMinorUnits: 72000,
        sourceTicketRef: `CLIENT-SMOKE-ISSUE-${suffix}`,
        customerPhoneE164: customerPhone,
        status: 'active',
        expiresAt: customerExpiry,
        createdAt: seededAt,
        updatedAt: seededAt,
      },
    ],
    [
      `ledgerEvents/${clientIssueEventTwoId}`,
      {
        eventType: 'issue',
        groupId,
        issuerBusinessId: 'atlas-dental',
        actorBusinessId: 'atlas-dental',
        operatorUid: 'client-smoke-helper',
        targetCustomerId: customerId,
        amountMinorUnits: 64000,
        sourceTicketRef: `CLIENT-SMOKE-ISSUE-SECONDARY-${suffix}`,
        paidMinorUnits: 1280000,
        cashbackBasisPoints: 500,
        customerPhoneE164: customerPhone,
        lotId: clientIssueLotTwoId,
        originalIssueEventId: clientIssueEventTwoId,
        participantBusinessIds: ['atlas-dental'],
        participantCustomerIds: [customerId],
        expiresAt: customerExpirySoon,
        createdAt: seededAt,
        updatedAt: seededAt,
      },
    ],
    [
      `walletLots/${clientIssueLotTwoId}`,
      {
        ownerCustomerId: customerId,
        groupId,
        issuerBusinessId: 'atlas-dental',
        issuedByOperatorUid: 'client-smoke-helper',
        originalIssueEventId: clientIssueEventTwoId,
        initialMinorUnits: 64000,
        availableMinorUnits: 64000,
        sourceTicketRef: `CLIENT-SMOKE-ISSUE-SECONDARY-${suffix}`,
        customerPhoneE164: customerPhone,
        status: 'active',
        expiresAt: customerExpirySoon,
        createdAt: seededAt,
        updatedAt: seededAt,
      },
    ],
    [
      `customers/${senderCustomerId}`,
      {
        phoneE164: senderPhone,
        displayName: 'Smoke Sender',
        isClaimed: false,
        claimedByUid: null,
        createdFrom: 'client_smoke_helper',
        createdAt: seededAt,
        updatedAt: seededAt,
      },
    ],
    [
      `ledgerEvents/${senderIssueEventId}`,
      {
        eventType: 'issue',
        groupId,
        issuerBusinessId: 'bread-and-ember',
        actorBusinessId: 'bread-and-ember',
        operatorUid: 'client-smoke-helper',
        targetCustomerId: senderCustomerId,
        amountMinorUnits: 15000,
        sourceTicketRef: `CLIENT-SMOKE-SENDER-${suffix}`,
        paidMinorUnits: 250000,
        cashbackBasisPoints: 600,
        customerPhoneE164: senderPhone,
        lotId: senderParentLotId,
        originalIssueEventId: senderIssueEventId,
        participantBusinessIds: ['bread-and-ember'],
        participantCustomerIds: [senderCustomerId],
        expiresAt: giftExpiry,
        createdAt: seededAt,
        updatedAt: seededAt,
      },
    ],
    [
      `walletLots/${senderParentLotId}`,
      {
        ownerCustomerId: senderCustomerId,
        groupId,
        issuerBusinessId: 'bread-and-ember',
        issuedByOperatorUid: 'client-smoke-helper',
        originalIssueEventId: senderIssueEventId,
        initialMinorUnits: 15000,
        availableMinorUnits: 0,
        sourceTicketRef: `CLIENT-SMOKE-SENDER-${suffix}`,
        customerPhoneE164: senderPhone,
        status: 'transferred',
        lastTransferredAt: seededAt,
        expiresAt: giftExpiry,
        createdAt: seededAt,
        updatedAt: seededAt,
      },
    ],
    [
      `giftTransfers/${incomingTransferId}`,
      {
        status: 'pending',
        requestedByUid: 'client-smoke-helper',
        sourceCustomerId: senderCustomerId,
        recipientPhoneE164: customerPhone,
        groupId,
        amountMinorUnits: 15000,
        requestId: `client-smoke-incoming-${suffix}`,
        participantBusinessIds: ['bread-and-ember'],
        participantCustomerIds: [senderCustomerId],
        pendingLotIds: [pendingGiftLotId],
        earliestExpiresAt: giftExpiry,
        latestExpiresAt: giftExpiry,
        transferOutEventId,
        giftPendingEventId,
        createdAt: seededAt,
        updatedAt: seededAt,
      },
    ],
    [
      `walletLots/${pendingGiftLotId}`,
      {
        ownerCustomerId: null,
        sourceCustomerId: senderCustomerId,
        groupId,
        issuerBusinessId: 'bread-and-ember',
        originalIssueEventId: senderIssueEventId,
        initialMinorUnits: 15000,
        availableMinorUnits: 15000,
        parentLotId: senderParentLotId,
        pendingGiftTransferId: incomingTransferId,
        pendingRecipientPhoneE164: customerPhone,
        status: 'gift_pending',
        expiresAt: giftExpiry,
        createdAt: seededAt,
        updatedAt: seededAt,
      },
    ],
    [
      `ledgerEvents/${transferOutEventId}`,
      {
        eventType: 'transfer_out',
        groupId,
        sourceCustomerId: senderCustomerId,
        recipientPhoneE164: customerPhone,
        amountMinorUnits: 15000,
        giftTransferId: incomingTransferId,
        pendingLotIds: [pendingGiftLotId],
        participantBusinessIds: ['bread-and-ember'],
        participantCustomerIds: [senderCustomerId],
        createdAt: seededAt,
        updatedAt: seededAt,
      },
    ],
    [
      `ledgerEvents/${giftPendingEventId}`,
      {
        eventType: 'gift_pending',
        groupId,
        sourceCustomerId: senderCustomerId,
        recipientPhoneE164: customerPhone,
        amountMinorUnits: 15000,
        giftTransferId: incomingTransferId,
        pendingLotIds: [pendingGiftLotId],
        participantBusinessIds: ['bread-and-ember'],
        participantCustomerIds: [senderCustomerId],
        earliestExpiresAt: giftExpiry,
        latestExpiresAt: giftExpiry,
        createdAt: seededAt,
        updatedAt: seededAt,
      },
    ],
    [
      `sharedCheckouts/${checkoutId}`,
      {
        businessId: 'silk-road-cafe',
        groupId,
        status: 'open',
        totalMinorUnits: 90000,
        contributedMinorUnits: 0,
        remainingMinorUnits: 90000,
        sourceTicketRef: `CLIENT-SMOKE-CHECKOUT-${suffix}`,
        createdByOperatorUid: 'client-smoke-helper',
        createdEventId: sharedCheckoutCreatedEventId,
        participantBusinessIds: ['silk-road-cafe'],
        participantCustomerIds: [customerId],
        contributionsCount: 0,
        createdAt: seededAt,
        updatedAt: seededAt,
      },
    ],
    [
      `ledgerEvents/${sharedCheckoutCreatedEventId}`,
      {
        eventType: 'shared_checkout_created',
        groupId,
        actorBusinessId: 'silk-road-cafe',
        targetBusinessId: 'silk-road-cafe',
        operatorUid: 'client-smoke-helper',
        amountMinorUnits: 90000,
        checkoutId,
        sourceTicketRef: `CLIENT-SMOKE-CHECKOUT-${suffix}`,
        participantBusinessIds: ['silk-road-cafe'],
        participantCustomerIds: [customerId],
        createdAt: seededAt,
        updatedAt: seededAt,
      },
    ],
  ];
}

async function readFirebaseAccessToken() {
  const configPath = join(
    homedir(),
    '.config',
    'configstore',
    'firebase-tools.json',
  );
  const raw = await readFile(configPath, 'utf8');
  const config = JSON.parse(raw);
  const refreshToken = config?.tokens?.refresh_token;
  if (typeof refreshToken !== 'string' || refreshToken.length === 0) {
    throw new Error('Firebase CLI refresh token was not found.');
  }

  const response = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/x-www-form-urlencoded',
    },
    body: new URLSearchParams({
      client_id: firebaseCliOAuthClientId,
      client_secret: firebaseCliOAuthClientSecret,
      refresh_token: refreshToken,
      grant_type: 'refresh_token',
    }),
  });

  if (!response.ok) {
    const errorText = await response.text();
    throw new Error(
      `Could not refresh Firebase CLI Google API token: ${response.status} ${errorText}`,
    );
  }

  const payload = await response.json();
  const accessToken = payload?.access_token;
  if (typeof accessToken !== 'string' || accessToken.length === 0) {
    throw new Error('Refreshed Google API access token was missing.');
  }

  return accessToken;
}

async function upsertFirestoreDocument(accessToken, path, data) {
  const url =
    `https://firestore.googleapis.com/v1/projects/${projectId}` +
    `/databases/${databaseId}/documents/${path}`;
  const response = await fetch(url, {
    method: 'PATCH',
    headers: {
      Authorization: `Bearer ${accessToken}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      fields: toFirestoreFields(data),
    }),
  });

  if (response.ok) {
    return;
  }

  const errorText = await response.text();
  throw new Error(`Failed to upsert ${path}: ${response.status} ${errorText}`);
}

function toFirestoreFields(data) {
  const fields = {};
  for (const [key, value] of Object.entries(data)) {
    fields[key] = toFirestoreValue(value);
  }
  return fields;
}

function toFirestoreValue(value) {
  if (value === null) {
    return { nullValue: null };
  }
  if (Array.isArray(value)) {
    return {
      arrayValue: {
        values: value.map((entry) => toFirestoreValue(entry)),
      },
    };
  }
  if (typeof value === 'string') {
    if (isIsoTimestamp(value)) {
      return { timestampValue: value };
    }
    return { stringValue: value };
  }
  if (typeof value === 'boolean') {
    return { booleanValue: value };
  }
  if (typeof value === 'number') {
    if (Number.isInteger(value)) {
      return { integerValue: value.toString() };
    }
    return { doubleValue: value };
  }
  if (typeof value === 'object') {
    return {
      mapValue: {
        fields: toFirestoreFields(value),
      },
    };
  }
  throw new Error(`Unsupported Firestore value: ${value}`);
}

function addDays(date, days) {
  return new Date(date.getTime() + days * 24 * 60 * 60 * 1000);
}

function isIsoTimestamp(value) {
  return /^\d{4}-\d{2}-\d{2}T/.test(value);
}
