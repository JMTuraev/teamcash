import { initializeApp } from 'firebase/app';
import {
  createUserWithEmailAndPassword,
  getAuth,
  signInWithEmailAndPassword,
  signOut,
} from 'firebase/auth';
import {
  doc,
  getDoc,
  getFirestore,
  serverTimestamp,
  setDoc,
} from 'firebase/firestore/lite';

const firebaseConfig = {
  apiKey: 'AIzaSyAeu0zJbsfE6Ng6FROZ9LuJ1K7ByIiZQb0',
  appId: '1:136324996533:web:08b0be6cad81672b984dfc',
  messagingSenderId: '136324996533',
  projectId: 'teamcash-83a6e',
  authDomain: 'teamcash-83a6e.firebaseapp.com',
  storageBucket: 'teamcash-83a6e.firebasestorage.app',
  measurementId: 'G-3ZJQYKQ2D2',
};

const owner = {
  username: 'aziza.owner',
  displayName: 'Aziza Karimova',
  password: 'Teamcash!2026',
};
const staff = {
  username: 'nadia.silkroad',
  displayName: 'Nadia Rasulova',
  password: 'Teamcash!2026',
  businessId: 'silk-road-cafe',
};
const groupId = 'old-town-circle';
const groupName = 'Old Town Circle';
const customerId = 'customer-jasur';
const customerPhone = '+998904447755';
const pendingGiftTransferId = 'pending-gift-seed-1';
const pendingGiftRecipientPhone = '+998901112233';
const sharedCheckoutId = 'shared-checkout-seed-1';
const sharedCheckoutContributionId = 'shared-contribution-seed-1';

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

const app = initializeApp(firebaseConfig);
const auth = getAuth(app);
const firestore = getFirestore(app);

await main();

async function main() {
  const ownerEmail = buildAliasEmail(owner.username);
  const staffEmail = buildAliasEmail(staff.username);

  const ownerCredential = await ensureUser(ownerEmail, owner.password);
  await signOut(auth);
  const staffCredential = await ensureUser(staffEmail, staff.password);
  await signOut(auth);
  await signInWithEmailAndPassword(auth, ownerEmail, owner.password);

  const todayId = formatBusinessDay(new Date());

  await createIfMissing(doc(firestore, `groups/${groupId}`), {
    name: groupName,
    status: 'active',
    createdByOwnerUid: ownerCredential.uid,
    activeBusinessIds: ['silk-road-cafe', 'atlas-dental', 'bread-and-ember'],
    pendingBusinessIds: ['cedar-studio'],
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
  });

  for (const business of businesses) {
    await createIfMissing(doc(firestore, `businesses/${business.id}`), {
      ...business,
      groupId,
      groupName,
      tandemStatus: business.groupMembershipStatus,
      ownerUid: ownerCredential.uid,
      createdAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
    });

    await createIfMissing(
      doc(firestore, `businesses/${business.id}/statsDaily/${todayId}`),
      {
        salesCount:
          business.id === 'silk-road-cafe'
            ? 43
            : business.id === 'atlas-dental'
              ? 18
              : business.id === 'bread-and-ember'
                ? 16
                : 0,
        totalSalesMinorUnits:
          business.id === 'silk-road-cafe'
            ? 4260000
            : business.id === 'atlas-dental'
              ? 1890000
              : business.id === 'bread-and-ember'
                ? 1420000
                : 0,
        cashbackIssuedMinorUnits:
          business.id === 'silk-road-cafe'
            ? 48000
            : business.id === 'atlas-dental'
              ? 93000
              : business.id === 'bread-and-ember'
                ? 55000
                : 0,
        cashbackIssueCount: business.id === 'cedar-studio' ? 0 : 1,
        cashbackRedeemedMinorUnits: business.id === 'silk-road-cafe' ? 27000 : 0,
        cashbackRedeemCount: business.id === 'silk-road-cafe' ? 1 : 0,
        qrScanCount:
          business.id === 'silk-road-cafe'
            ? 29
            : business.id === 'cedar-studio'
              ? 0
              : 11,
        todayClientCount:
          business.id === 'silk-road-cafe'
            ? 24
            : business.id === 'cedar-studio'
              ? 0
              : 8,
        uniqueClientsCount:
          business.id === 'silk-road-cafe'
            ? 24
            : business.id === 'cedar-studio'
              ? 0
              : 8,
        updatedAt: serverTimestamp(),
      },
    );
  }

  for (const memberId of ['silk-road-cafe', 'atlas-dental', 'bread-and-ember']) {
    await createIfMissing(doc(firestore, `groups/${groupId}/members/${memberId}`), {
      businessId: memberId,
      status: 'active',
      addedAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
    });
  }

  await createIfMissing(doc(firestore, `groups/${groupId}/joinRequests/join-cedar`), {
    businessId: 'cedar-studio',
    targetBusinessId: 'cedar-studio',
    groupId,
    status: 'pending',
    approvalsReceived: 2,
    approvalsRequired: 3,
    requestedAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
  });

  await createIfMissing(doc(firestore, `groups/${groupId}/history/seed-bootstrap`), {
    eventType: 'group_seeded',
    actorOwnerUid: ownerCredential.uid,
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
  });

  await createIfMissing(doc(firestore, `operatorAccounts/${ownerCredential.uid}`), {
    role: 'owner',
    roleLabel: 'Owner',
    ownerId: ownerCredential.uid,
    businessIds: businesses.map((business) => business.id),
    displayName: owner.displayName,
    usernameNormalized: owner.username,
    disabledAt: null,
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
  });

  await createIfMissing(doc(firestore, `operatorUsernames/${owner.username}`), {
    uid: ownerCredential.uid,
    loginAliasEmail: ownerEmail,
    status: 'active',
    role: 'owner',
    ownerId: ownerCredential.uid,
    businessIds: businesses.map((business) => business.id),
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
  });

  await createIfMissing(doc(firestore, `operatorAccounts/${staffCredential.uid}`), {
    role: 'staff',
    roleLabel: 'Floor manager',
    ownerId: ownerCredential.uid,
    businessId: staff.businessId,
    businessIds: [staff.businessId],
    displayName: staff.displayName,
    usernameNormalized: staff.username,
    disabledAt: null,
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
  });

  await createIfMissing(doc(firestore, `operatorUsernames/${staff.username}`), {
    uid: staffCredential.uid,
    loginAliasEmail: staffEmail,
    status: 'active',
    role: 'staff',
    ownerId: ownerCredential.uid,
    businessId: staff.businessId,
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
  });

  await createIfMissing(doc(firestore, `customerPhoneIndex/${customerPhone}`), {
    customerId,
    phoneE164: customerPhone,
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
  });

  await createIfMissing(doc(firestore, `customers/${customerId}`), {
    phoneE164: customerPhone,
    displayName: 'Jasur Ergashev',
    isClaimed: false,
    claimedByUid: null,
    createdFrom: 'spark_seed_script',
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
  });

  await createIfMissing(doc(firestore, 'ledgerEvents/seed-issue-silk-road-1'), {
    eventType: 'issue',
    groupId,
    issuerBusinessId: 'silk-road-cafe',
    actorBusinessId: 'silk-road-cafe',
    operatorUid: staffCredential.uid,
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
    expiresAt: new Date('2026-05-10T00:00:00.000Z'),
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
  });

  await createIfMissing(doc(firestore, 'walletLots/lot-seed-silk-road-1'), {
    ownerCustomerId: customerId,
    groupId,
    issuerBusinessId: 'silk-road-cafe',
    issuedByOperatorUid: staffCredential.uid,
    originalIssueEventId: 'seed-issue-silk-road-1',
    initialMinorUnits: 48000,
    availableMinorUnits: 23000,
    sourceTicketRef: 'SEED-SR-1001',
    customerPhoneE164: customerPhone,
    status: 'active',
    lastTransferredAt: serverTimestamp(),
    expiresAt: new Date('2026-05-10T00:00:00.000Z'),
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
  });

  await createIfMissing(doc(firestore, `giftTransfers/${pendingGiftTransferId}`), {
    status: 'pending',
    requestedByUid: ownerCredential.uid,
    sourceCustomerId: customerId,
    recipientPhoneE164: pendingGiftRecipientPhone,
    groupId,
    amountMinorUnits: 25000,
    requestId: 'seed-request-gift-1',
    participantBusinessIds: ['silk-road-cafe'],
    participantCustomerIds: [customerId],
    pendingLotIds: ['lot-seed-gift-pending-1'],
    earliestExpiresAt: new Date('2026-05-10T00:00:00.000Z'),
    latestExpiresAt: new Date('2026-05-10T00:00:00.000Z'),
    transferOutEventId: 'seed-transfer-out-1',
    giftPendingEventId: 'seed-gift-pending-1',
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
  });

  await createIfMissing(doc(firestore, 'walletLots/lot-seed-gift-pending-1'), {
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
    expiresAt: new Date('2026-05-10T00:00:00.000Z'),
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
  });

  await createIfMissing(doc(firestore, 'ledgerEvents/seed-transfer-out-1'), {
    eventType: 'transfer_out',
    groupId,
    sourceCustomerId: customerId,
    recipientPhoneE164: pendingGiftRecipientPhone,
    amountMinorUnits: 25000,
    giftTransferId: pendingGiftTransferId,
    pendingLotIds: ['lot-seed-gift-pending-1'],
    participantBusinessIds: ['silk-road-cafe'],
    participantCustomerIds: [customerId],
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
  });

  await createIfMissing(doc(firestore, 'ledgerEvents/seed-gift-pending-1'), {
    eventType: 'gift_pending',
    groupId,
    sourceCustomerId: customerId,
    recipientPhoneE164: pendingGiftRecipientPhone,
    amountMinorUnits: 25000,
    giftTransferId: pendingGiftTransferId,
    pendingLotIds: ['lot-seed-gift-pending-1'],
    participantBusinessIds: ['silk-road-cafe'],
    participantCustomerIds: [customerId],
    earliestExpiresAt: new Date('2026-05-10T00:00:00.000Z'),
    latestExpiresAt: new Date('2026-05-10T00:00:00.000Z'),
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
  });

  await createIfMissing(doc(firestore, 'ledgerEvents/seed-issue-atlas-1'), {
    eventType: 'issue',
    groupId,
    issuerBusinessId: 'atlas-dental',
    actorBusinessId: 'atlas-dental',
    operatorUid: ownerCredential.uid,
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
    expiresAt: new Date('2026-06-01T00:00:00.000Z'),
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
  });

  await createIfMissing(doc(firestore, 'walletLots/lot-seed-atlas-1'), {
    ownerCustomerId: customerId,
    groupId,
    issuerBusinessId: 'atlas-dental',
    issuedByOperatorUid: ownerCredential.uid,
    originalIssueEventId: 'seed-issue-atlas-1',
    initialMinorUnits: 93000,
    availableMinorUnits: 93000,
    sourceTicketRef: 'SEED-AT-1002',
    customerPhoneE164: customerPhone,
    status: 'active',
    expiresAt: new Date('2026-06-01T00:00:00.000Z'),
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
  });

  await createIfMissing(doc(firestore, 'ledgerEvents/seed-issue-bread-1'), {
    eventType: 'issue',
    groupId,
    issuerBusinessId: 'bread-and-ember',
    actorBusinessId: 'bread-and-ember',
    operatorUid: ownerCredential.uid,
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
    expiresAt: new Date('2026-04-22T00:00:00.000Z'),
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
  });

  await createIfMissing(doc(firestore, 'walletLots/lot-seed-bread-and-ember-1'), {
    ownerCustomerId: customerId,
    groupId,
    issuerBusinessId: 'bread-and-ember',
    issuedByOperatorUid: ownerCredential.uid,
    originalIssueEventId: 'seed-issue-bread-1',
    initialMinorUnits: 55000,
    availableMinorUnits: 15000,
    sourceTicketRef: 'SEED-BE-1003',
    customerPhoneE164: customerPhone,
    status: 'active',
    lastReservedAt: serverTimestamp(),
    expiresAt: new Date('2026-04-22T00:00:00.000Z'),
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
  });

  await createIfMissing(doc(firestore, `sharedCheckouts/${sharedCheckoutId}`), {
    businessId: 'silk-road-cafe',
    groupId,
    status: 'open',
    totalMinorUnits: 180000,
    contributedMinorUnits: 40000,
    remainingMinorUnits: 140000,
    sourceTicketRef: 'SEED-SHARED-2201',
    createdByOperatorUid: staffCredential.uid,
    createdEventId: 'seed-shared-checkout-created-1',
    participantBusinessIds: ['silk-road-cafe', 'bread-and-ember'],
    participantCustomerIds: [customerId],
    contributionsCount: 1,
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
  });

  await createIfMissing(
    doc(
      firestore,
      `sharedCheckouts/${sharedCheckoutId}/contributions/${sharedCheckoutContributionId}`,
    ),
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
      createdByUid: ownerCredential.uid,
      createdAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
    },
  );

  await createIfMissing(doc(firestore, 'walletLots/lot-seed-shared-reserved-1'), {
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
    expiresAt: new Date('2026-04-22T00:00:00.000Z'),
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
  });

  await createIfMissing(doc(firestore, 'ledgerEvents/seed-shared-checkout-created-1'), {
    eventType: 'shared_checkout_created',
    groupId,
    actorBusinessId: 'silk-road-cafe',
    targetBusinessId: 'silk-road-cafe',
    operatorUid: staffCredential.uid,
    amountMinorUnits: 180000,
    checkoutId: sharedCheckoutId,
    sourceTicketRef: 'SEED-SHARED-2201',
    participantBusinessIds: ['silk-road-cafe'],
    participantCustomerIds: [],
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
  });

  await createIfMissing(doc(firestore, 'ledgerEvents/seed-shared-checkout-contribution-1'), {
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
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
  });

  console.log(
    JSON.stringify(
      {
        ok: true,
        projectId: firebaseConfig.projectId,
        owner: {
          username: owner.username,
          password: owner.password,
          uid: ownerCredential.uid,
        },
        staff: {
          username: staff.username,
          password: staff.password,
          uid: staffCredential.uid,
        },
        customer: {
          customerId,
          phone: customerPhone,
        },
        pendingGiftTransferId,
        sharedCheckoutId,
      },
      null,
      2,
    ),
  );
}

async function createIfMissing(ref, data) {
  const existing = await getDoc(ref);
  if (existing.exists()) {
    return;
  }

  await setDoc(ref, data);
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

function buildAliasEmail(username) {
  return `${username}@operators.teamcash.local`;
}

function formatBusinessDay(date) {
  return new Intl.DateTimeFormat('en-CA', {
    timeZone: 'Asia/Tashkent',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).format(date).replace(/-/g, '');
}
