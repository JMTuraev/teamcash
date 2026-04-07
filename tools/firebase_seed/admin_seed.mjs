import { readFile } from 'node:fs/promises';
import { homedir } from 'node:os';
import { join } from 'node:path';

const projectId = 'teamcash-83a6e';
const databaseId = '(default)';
const ownerUid = 'owner-aziza-seed';
const staffUid = 'staff-nadia-seed';
const groupId = 'old-town-circle';
const groupName = 'Old Town Circle';
const customerId = 'customer-jasur';
const customerPhone = '+998904447755';
const pendingGiftTransferId = 'pending-gift-seed-1';
const pendingGiftRecipientPhone = '+998901112233';
const sharedCheckoutId = 'shared-checkout-seed-1';
const sharedCheckoutContributionId = 'shared-contribution-seed-1';
const seededAt = new Date().toISOString();
const todayId = formatBusinessDay(new Date());

const businesses = [
  {
    id: 'silk-road-cafe',
    name: 'Silk Road Cafe',
    category: 'Cafe',
    description:
      'Core tandem member with brunch, desserts, and strong lunch traffic.',
    address: '14 Afrosiyob Street, Tashkent',
    workingHours: '08:00 - 23:00',
    phoneNumbers: ['+998712000111'],
    cashbackBasisPoints: 700,
    cashbackExpiryDays: 180,
    redeemPolicy: 'Redeem up to 30% of a ticket in a single checkout.',
    groupMembershipStatus: 'active',
    locationsCount: 2,
    productsCount: 14,
    manualPhoneIssuingEnabled: true,
  },
  {
    id: 'atlas-dental',
    name: 'Atlas Dental',
    category: 'Clinic',
    description: 'Healthcare anchor business with recurring family visits.',
    address: '51 Bobur Street, Tashkent',
    workingHours: '09:00 - 19:00',
    phoneNumbers: ['+998712000222'],
    cashbackBasisPoints: 500,
    cashbackExpiryDays: 180,
    redeemPolicy: 'Redeem on diagnostics and hygiene packages only.',
    groupMembershipStatus: 'active',
    locationsCount: 1,
    productsCount: 9,
    manualPhoneIssuingEnabled: true,
  },
  {
    id: 'bread-and-ember',
    name: 'Bread & Ember',
    category: 'Bakery',
    description: 'Wood-fired bakery inside the same trusted tandem.',
    address: '19 Sayilgoh Street, Tashkent',
    workingHours: '07:30 - 21:00',
    phoneNumbers: ['+998712000333'],
    cashbackBasisPoints: 600,
    cashbackExpiryDays: 180,
    redeemPolicy: 'Redeem on dine-in and takeaway, excluding catering.',
    groupMembershipStatus: 'active',
    locationsCount: 1,
    productsCount: 11,
    manualPhoneIssuingEnabled: true,
  },
  {
    id: 'cedar-studio',
    name: 'Cedar Studio',
    category: 'Salon',
    description:
      'Pending member waiting for unanimous approval from current businesses.',
    address: '8 Movarounnahr Street, Tashkent',
    workingHours: '10:00 - 20:00',
    phoneNumbers: ['+998712000444'],
    cashbackBasisPoints: 800,
    cashbackExpiryDays: 180,
    redeemPolicy: 'Redeem up to 25% per appointment.',
    groupMembershipStatus: 'pending',
    locationsCount: 1,
    productsCount: 17,
    manualPhoneIssuingEnabled: true,
  },
];

await main();

async function main() {
  const accessToken = await readFirebaseAccessToken();
  const documents = buildDocuments();

  for (const [path, data] of documents) {
    await createFirestoreDocument(accessToken, path, data);
  }

  console.log(
    JSON.stringify(
      {
        ok: true,
        projectId,
        authConfigured: false,
        seededDocuments: documents.length,
        ownerUid,
        staffUid,
        customerId,
        pendingGiftTransferId,
        sharedCheckoutId,
      },
      null,
      2,
    ),
  );
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
  const token = config?.tokens?.access_token;
  if (typeof token !== 'string' || token.length === 0) {
    throw new Error('Firebase CLI access token was not found.');
  }
  return token;
}

function buildDocuments() {
  const docs = [];

  docs.push([
    `groups/${groupId}`,
    {
      name: groupName,
      status: 'active',
      createdByOwnerUid: ownerUid,
      activeBusinessIds: ['silk-road-cafe', 'atlas-dental', 'bread-and-ember'],
      pendingBusinessIds: ['cedar-studio'],
      createdAt: seededAt,
      updatedAt: seededAt,
    },
  ]);

  for (const business of businesses) {
    docs.push([
      `businesses/${business.id}`,
      {
        ...business,
        groupId,
        groupName,
        tandemStatus: business.groupMembershipStatus,
        ownerUid,
        createdAt: seededAt,
        updatedAt: seededAt,
      },
    ]);

    docs.push([
      `businesses/${business.id}/statsDaily/${todayId}`,
      buildStatsDocument(business.id),
    ]);
  }

  for (const memberId of ['silk-road-cafe', 'atlas-dental', 'bread-and-ember']) {
    docs.push([
      `groups/${groupId}/members/${memberId}`,
      {
        businessId: memberId,
        status: 'active',
        addedAt: seededAt,
        updatedAt: seededAt,
      },
    ]);
  }

  docs.push([
    `groups/${groupId}/joinRequests/join-cedar`,
    {
      businessId: 'cedar-studio',
      targetBusinessId: 'cedar-studio',
      groupId,
      status: 'pending',
      approvalsReceived: 2,
      approvalsRequired: 3,
      requestedAt: seededAt,
      updatedAt: seededAt,
    },
  ]);

  docs.push([
    `groups/${groupId}/history/seed-bootstrap`,
    {
      eventType: 'group_seeded',
      actorOwnerUid: ownerUid,
      createdAt: seededAt,
      updatedAt: seededAt,
    },
  ]);

  docs.push([
    `operatorAccounts/${ownerUid}`,
    {
      role: 'owner',
      roleLabel: 'Owner',
      ownerId: ownerUid,
      businessIds: businesses.map((business) => business.id),
      displayName: 'Aziza Karimova',
      usernameNormalized: 'aziza.owner',
      disabledAt: null,
      createdAt: seededAt,
      updatedAt: seededAt,
    },
  ]);

  docs.push([
    'operatorUsernames/aziza.owner',
    {
      uid: ownerUid,
      loginAliasEmail: 'aziza.owner@operators.teamcash.local',
      status: 'auth_not_initialized',
      role: 'owner',
      ownerId: ownerUid,
      businessIds: businesses.map((business) => business.id),
      createdAt: seededAt,
      updatedAt: seededAt,
    },
  ]);

  docs.push([
    `operatorAccounts/${staffUid}`,
    {
      role: 'staff',
      roleLabel: 'Floor manager',
      ownerId: ownerUid,
      businessId: 'silk-road-cafe',
      businessIds: ['silk-road-cafe'],
      displayName: 'Nadia Rasulova',
      usernameNormalized: 'nadia.silkroad',
      disabledAt: null,
      createdAt: seededAt,
      updatedAt: seededAt,
    },
  ]);

  docs.push([
    'operatorUsernames/nadia.silkroad',
    {
      uid: staffUid,
      loginAliasEmail: 'nadia.silkroad@operators.teamcash.local',
      status: 'auth_not_initialized',
      role: 'staff',
      ownerId: ownerUid,
      businessId: 'silk-road-cafe',
      createdAt: seededAt,
      updatedAt: seededAt,
    },
  ]);

  docs.push([
    `customerPhoneIndex/${customerPhone}`,
    {
      customerId,
      phoneE164: customerPhone,
      createdAt: seededAt,
      updatedAt: seededAt,
    },
  ]);

  docs.push([
    `customers/${customerId}`,
    {
      phoneE164: customerPhone,
      displayName: 'Jasur Ergashev',
      isClaimed: false,
      claimedByUid: null,
      createdFrom: 'admin_firestore_seed',
      createdAt: seededAt,
      updatedAt: seededAt,
    },
  ]);

  docs.push([
    'ledgerEvents/seed-issue-silk-road-1',
    {
      eventType: 'issue',
      groupId,
      issuerBusinessId: 'silk-road-cafe',
      actorBusinessId: 'silk-road-cafe',
      operatorUid: staffUid,
      targetCustomerId: customerId,
      amountMinorUnits: 48000,
      sourceTicketRef: 'SEED-SR-1001',
      paidMinorUnits: 690000,
      cashbackBasisPoints: 700,
      customerPhoneE164: customerPhone,
      lotId: 'lot-seed-silk-road-1',
      originalIssueEventId: 'seed-issue-silk-road-1',
      participantBusinessIds: ['silk-road-cafe'],
      participantCustomerIds: [customerId],
      expiresAt: '2026-05-10T00:00:00.000Z',
      createdAt: seededAt,
      updatedAt: seededAt,
    },
  ]);

  docs.push([
    'walletLots/lot-seed-silk-road-1',
    {
      ownerCustomerId: customerId,
      groupId,
      issuerBusinessId: 'silk-road-cafe',
      issuedByOperatorUid: staffUid,
      originalIssueEventId: 'seed-issue-silk-road-1',
      initialMinorUnits: 48000,
      availableMinorUnits: 23000,
      sourceTicketRef: 'SEED-SR-1001',
      customerPhoneE164: customerPhone,
      status: 'active',
      lastTransferredAt: seededAt,
      expiresAt: '2026-05-10T00:00:00.000Z',
      createdAt: seededAt,
      updatedAt: seededAt,
    },
  ]);

  docs.push([
    `giftTransfers/${pendingGiftTransferId}`,
    {
      status: 'pending',
      requestedByUid: ownerUid,
      sourceCustomerId: customerId,
      recipientPhoneE164: pendingGiftRecipientPhone,
      groupId,
      amountMinorUnits: 25000,
      requestId: 'seed-request-gift-1',
      participantBusinessIds: ['silk-road-cafe'],
      participantCustomerIds: [customerId],
      pendingLotIds: ['lot-seed-gift-pending-1'],
      earliestExpiresAt: '2026-05-10T00:00:00.000Z',
      latestExpiresAt: '2026-05-10T00:00:00.000Z',
      transferOutEventId: 'seed-transfer-out-1',
      giftPendingEventId: 'seed-gift-pending-1',
      createdAt: seededAt,
      updatedAt: seededAt,
    },
  ]);

  docs.push([
    'walletLots/lot-seed-gift-pending-1',
    {
      ownerCustomerId: null,
      sourceCustomerId: customerId,
      groupId,
      issuerBusinessId: 'silk-road-cafe',
      originalIssueEventId: 'seed-issue-silk-road-1',
      initialMinorUnits: 25000,
      availableMinorUnits: 25000,
      parentLotId: 'lot-seed-silk-road-1',
      pendingGiftTransferId,
      pendingRecipientPhoneE164: pendingGiftRecipientPhone,
      status: 'gift_pending',
      expiresAt: '2026-05-10T00:00:00.000Z',
      createdAt: seededAt,
      updatedAt: seededAt,
    },
  ]);

  docs.push([
    'ledgerEvents/seed-transfer-out-1',
    {
      eventType: 'transfer_out',
      groupId,
      sourceCustomerId: customerId,
      recipientPhoneE164: pendingGiftRecipientPhone,
      amountMinorUnits: 25000,
      giftTransferId: pendingGiftTransferId,
      pendingLotIds: ['lot-seed-gift-pending-1'],
      participantBusinessIds: ['silk-road-cafe'],
      participantCustomerIds: [customerId],
      createdAt: seededAt,
      updatedAt: seededAt,
    },
  ]);

  docs.push([
    'ledgerEvents/seed-gift-pending-1',
    {
      eventType: 'gift_pending',
      groupId,
      sourceCustomerId: customerId,
      recipientPhoneE164: pendingGiftRecipientPhone,
      amountMinorUnits: 25000,
      giftTransferId: pendingGiftTransferId,
      pendingLotIds: ['lot-seed-gift-pending-1'],
      participantBusinessIds: ['silk-road-cafe'],
      participantCustomerIds: [customerId],
      earliestExpiresAt: '2026-05-10T00:00:00.000Z',
      latestExpiresAt: '2026-05-10T00:00:00.000Z',
      createdAt: seededAt,
      updatedAt: seededAt,
    },
  ]);

  docs.push([
    'ledgerEvents/seed-issue-atlas-1',
    {
      eventType: 'issue',
      groupId,
      issuerBusinessId: 'atlas-dental',
      actorBusinessId: 'atlas-dental',
      operatorUid: ownerUid,
      targetCustomerId: customerId,
      amountMinorUnits: 93000,
      sourceTicketRef: 'SEED-AT-1002',
      paidMinorUnits: 1860000,
      cashbackBasisPoints: 500,
      customerPhoneE164: customerPhone,
      lotId: 'lot-seed-atlas-1',
      originalIssueEventId: 'seed-issue-atlas-1',
      participantBusinessIds: ['atlas-dental'],
      participantCustomerIds: [customerId],
      expiresAt: '2026-06-01T00:00:00.000Z',
      createdAt: seededAt,
      updatedAt: seededAt,
    },
  ]);

  docs.push([
    'walletLots/lot-seed-atlas-1',
    {
      ownerCustomerId: customerId,
      groupId,
      issuerBusinessId: 'atlas-dental',
      issuedByOperatorUid: ownerUid,
      originalIssueEventId: 'seed-issue-atlas-1',
      initialMinorUnits: 93000,
      availableMinorUnits: 93000,
      sourceTicketRef: 'SEED-AT-1002',
      customerPhoneE164: customerPhone,
      status: 'active',
      expiresAt: '2026-06-01T00:00:00.000Z',
      createdAt: seededAt,
      updatedAt: seededAt,
    },
  ]);

  docs.push([
    'ledgerEvents/seed-issue-bread-1',
    {
      eventType: 'issue',
      groupId,
      issuerBusinessId: 'bread-and-ember',
      actorBusinessId: 'bread-and-ember',
      operatorUid: ownerUid,
      targetCustomerId: customerId,
      amountMinorUnits: 55000,
      sourceTicketRef: 'SEED-BE-1003',
      paidMinorUnits: 916000,
      cashbackBasisPoints: 600,
      customerPhoneE164: customerPhone,
      lotId: 'lot-seed-bread-and-ember-1',
      originalIssueEventId: 'seed-issue-bread-1',
      participantBusinessIds: ['bread-and-ember'],
      participantCustomerIds: [customerId],
      expiresAt: '2026-04-22T00:00:00.000Z',
      createdAt: seededAt,
      updatedAt: seededAt,
    },
  ]);

  docs.push([
    'walletLots/lot-seed-bread-and-ember-1',
    {
      ownerCustomerId: customerId,
      groupId,
      issuerBusinessId: 'bread-and-ember',
      issuedByOperatorUid: ownerUid,
      originalIssueEventId: 'seed-issue-bread-1',
      initialMinorUnits: 55000,
      availableMinorUnits: 15000,
      sourceTicketRef: 'SEED-BE-1003',
      customerPhoneE164: customerPhone,
      status: 'active',
      lastReservedAt: seededAt,
      expiresAt: '2026-04-22T00:00:00.000Z',
      createdAt: seededAt,
      updatedAt: seededAt,
    },
  ]);

  docs.push([
    `sharedCheckouts/${sharedCheckoutId}`,
    {
      businessId: 'silk-road-cafe',
      groupId,
      status: 'open',
      totalMinorUnits: 180000,
      contributedMinorUnits: 40000,
      remainingMinorUnits: 140000,
      sourceTicketRef: 'SEED-SHARED-2201',
      createdByOperatorUid: staffUid,
      createdEventId: 'seed-shared-checkout-created-1',
      participantBusinessIds: ['silk-road-cafe', 'bread-and-ember'],
      participantCustomerIds: [customerId],
      contributionsCount: 1,
      createdAt: seededAt,
      updatedAt: seededAt,
    },
  ]);

  docs.push([
    `sharedCheckouts/${sharedCheckoutId}/contributions/${sharedCheckoutContributionId}`,
    {
      checkoutId: sharedCheckoutId,
      businessId: 'silk-road-cafe',
      groupId,
      customerId,
      amountMinorUnits: 40000,
      requestId: 'seed-shared-request-1',
      status: 'reserved',
      reservedLotIds: ['lot-seed-shared-reserved-1'],
      issuerBusinessIds: ['silk-road-cafe', 'bread-and-ember'],
      createdByUid: ownerUid,
      createdAt: seededAt,
      updatedAt: seededAt,
    },
  ]);

  docs.push([
    'walletLots/lot-seed-shared-reserved-1',
    {
      ownerCustomerId: customerId,
      sourceCustomerId: customerId,
      groupId,
      issuerBusinessId: 'bread-and-ember',
      originalIssueEventId: 'seed-issue-bread-1',
      initialMinorUnits: 40000,
      availableMinorUnits: 40000,
      parentLotId: 'lot-seed-bread-and-ember-1',
      reservedForCheckoutId: sharedCheckoutId,
      reservedForContributionId: sharedCheckoutContributionId,
      status: 'shared_checkout_reserved',
      expiresAt: '2026-04-22T00:00:00.000Z',
      createdAt: seededAt,
      updatedAt: seededAt,
    },
  ]);

  docs.push([
    'ledgerEvents/seed-shared-checkout-created-1',
    {
      eventType: 'shared_checkout_created',
      groupId,
      actorBusinessId: 'silk-road-cafe',
      targetBusinessId: 'silk-road-cafe',
      operatorUid: staffUid,
      amountMinorUnits: 180000,
      checkoutId: sharedCheckoutId,
      sourceTicketRef: 'SEED-SHARED-2201',
      participantBusinessIds: ['silk-road-cafe'],
      participantCustomerIds: [],
      createdAt: seededAt,
      updatedAt: seededAt,
    },
  ]);

  docs.push([
    'ledgerEvents/seed-shared-checkout-contribution-1',
    {
      eventType: 'shared_checkout_contribution',
      groupId,
      actorBusinessId: 'silk-road-cafe',
      targetBusinessId: 'silk-road-cafe',
      sourceCustomerId: customerId,
      amountMinorUnits: 40000,
      checkoutId: sharedCheckoutId,
      contributionId: sharedCheckoutContributionId,
      reservedLotIds: ['lot-seed-shared-reserved-1'],
      participantBusinessIds: ['silk-road-cafe', 'bread-and-ember'],
      participantCustomerIds: [customerId],
      createdAt: seededAt,
      updatedAt: seededAt,
    },
  ]);

  return docs;
}

function buildStatsDocument(businessId) {
  return {
    salesCount:
      businessId === 'silk-road-cafe'
        ? 43
        : businessId === 'atlas-dental'
          ? 18
          : businessId === 'bread-and-ember'
            ? 16
            : 0,
    totalSalesMinorUnits:
      businessId === 'silk-road-cafe'
        ? 4260000
        : businessId === 'atlas-dental'
          ? 1890000
          : businessId === 'bread-and-ember'
            ? 1420000
            : 0,
    cashbackIssuedMinorUnits:
      businessId === 'silk-road-cafe'
        ? 48000
        : businessId === 'atlas-dental'
          ? 93000
          : businessId === 'bread-and-ember'
            ? 55000
            : 0,
    cashbackIssueCount: businessId === 'cedar-studio' ? 0 : 1,
    cashbackRedeemedMinorUnits: businessId === 'silk-road-cafe' ? 27000 : 0,
    cashbackRedeemCount: businessId === 'silk-road-cafe' ? 1 : 0,
    qrScanCount:
      businessId === 'silk-road-cafe'
        ? 29
        : businessId === 'cedar-studio'
          ? 0
          : 11,
    todayClientCount:
      businessId === 'silk-road-cafe'
        ? 24
        : businessId === 'cedar-studio'
          ? 0
          : 8,
    uniqueClientsCount:
      businessId === 'silk-road-cafe'
        ? 24
        : businessId === 'cedar-studio'
          ? 0
          : 8,
    updatedAt: seededAt,
  };
}

async function createFirestoreDocument(accessToken, path, data) {
  const url =
    `https://firestore.googleapis.com/v1/projects/${projectId}` +
    `/databases/${databaseId}/documents/${path}?currentDocument.exists=false`;
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
  if (
    (response.status === 400 || response.status === 409) &&
    (errorText.includes('document to exist') ||
        errorText.includes('ALREADY_EXISTS'))
  ) {
    return;
  }

  throw new Error(`Failed to create ${path}: ${response.status} ${errorText}`);
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

function isIsoTimestamp(value) {
  return /^\d{4}-\d{2}-\d{2}T/.test(value);
}

function formatBusinessDay(date) {
  return new Intl.DateTimeFormat('en-CA', {
    timeZone: 'Asia/Tashkent',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).format(date).replace(/-/g, '');
}
