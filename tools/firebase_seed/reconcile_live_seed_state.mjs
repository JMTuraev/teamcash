import { readFile } from 'node:fs/promises';
import { homedir } from 'node:os';
import { join } from 'node:path';

const projectId = 'teamcash-83a6e';
const databaseId = '(default)';
const firebaseCliOAuthClientId =
  '563584335869-fgrhgmd47bqnekij5i8b5pr03ho849e6.apps.googleusercontent.com';
const firebaseCliOAuthClientSecret = 'j9iVZfS8kkCEFUPaAeJV0sAi';

const canonicalOwnerUsername = 'aziza.owner';
const canonicalStaffUsername = 'nadia.silkroad';
const canonicalBusinesses = [
  'silk-road-cafe',
  'atlas-dental',
  'bread-and-ember',
  'cedar-studio',
];
const nowIso = new Date().toISOString();

await main();

async function main() {
  const accessToken = await readFirebaseAccessToken();
  const operatorAccounts = await listCollectionDocuments(
    accessToken,
    'operatorAccounts',
    50,
  );

  const ownerUid = resolveCanonicalOperatorUid(
    operatorAccounts,
    canonicalOwnerUsername,
  );
  const staffUid = resolveCanonicalOperatorUid(
    operatorAccounts,
    canonicalStaffUsername,
  );
  const staffDisplayName = resolveOperatorDisplayName(
    operatorAccounts,
    staffUid,
    'Nadia Silk Road',
  );

  const patches = [
    [
      `operatorUsernames/${canonicalOwnerUsername}`,
      {
        uid: ownerUid,
        role: 'owner',
        ownerId: ownerUid,
        businessIds: canonicalBusinesses,
        loginAliasEmail: `${canonicalOwnerUsername}@operators.teamcash.local`,
        status: 'active',
        updatedAt: nowIso,
      },
    ],
    [
      `operatorUsernames/${canonicalStaffUsername}`,
      {
        uid: staffUid,
        role: 'staff',
        ownerId: ownerUid,
        businessId: 'silk-road-cafe',
        loginAliasEmail: `${canonicalStaffUsername}@operators.teamcash.local`,
        status: 'active',
        displayName: staffDisplayName,
        updatedAt: nowIso,
      },
    ],
    [
      'groups/old-town-circle',
      {
        createdByOwnerUid: ownerUid,
        updatedAt: nowIso,
      },
    ],
    [
      'groups/old-town-circle/history/seed-bootstrap',
      {
        actorOwnerUid: ownerUid,
        updatedAt: nowIso,
      },
    ],
    [
      'giftTransfers/pending-gift-seed-1',
      {
        requestedByUid: ownerUid,
        updatedAt: nowIso,
      },
    ],
    [
      'ledgerEvents/seed-issue-silk-road-1',
      {
        operatorUid: staffUid,
        updatedAt: nowIso,
      },
    ],
    [
      'walletLots/lot-seed-silk-road-1',
      {
        issuedByOperatorUid: staffUid,
        updatedAt: nowIso,
      },
    ],
    [
      'ledgerEvents/seed-issue-atlas-1',
      {
        operatorUid: ownerUid,
        updatedAt: nowIso,
      },
    ],
    [
      'walletLots/lot-seed-atlas-1',
      {
        issuedByOperatorUid: ownerUid,
        updatedAt: nowIso,
      },
    ],
    [
      'ledgerEvents/seed-issue-bread-1',
      {
        operatorUid: ownerUid,
        updatedAt: nowIso,
      },
    ],
    [
      'walletLots/lot-seed-bread-and-ember-1',
      {
        issuedByOperatorUid: ownerUid,
        updatedAt: nowIso,
      },
    ],
    [
      'sharedCheckouts/shared-checkout-seed-1',
      {
        createdByOperatorUid: staffUid,
        updatedAt: nowIso,
      },
    ],
    [
      'sharedCheckouts/shared-checkout-seed-1/contributions/shared-contribution-seed-1',
      {
        createdByUid: ownerUid,
        updatedAt: nowIso,
      },
    ],
    [
      'ledgerEvents/seed-shared-checkout-created-1',
      {
        operatorUid: staffUid,
        updatedAt: nowIso,
      },
    ],
  ];

  for (const businessId of canonicalBusinesses) {
    patches.push([
      `businesses/${businessId}`,
      {
        ownerUid,
        updatedAt: nowIso,
      },
    ]);
  }

  for (const [path, data] of patches) {
    await patchFirestoreDocument(accessToken, path, data);
  }

  const deletions = [
    'operatorAccounts/owner-aziza-seed',
    'operatorAccounts/staff-nadia-seed',
    'notifications/seed-owner-join-request-owner-aziza-seed',
    'notifications/seed-staff-assignment-staff-nadia-seed',
  ];

  for (const path of deletions) {
    await deleteFirestoreDocument(accessToken, path);
  }

  console.log(
    JSON.stringify(
      {
        ok: true,
        ownerUid,
        staffUid,
        patchedDocuments: patches.length,
        deletedDocuments: deletions.length,
      },
      null,
      2,
    ),
  );
}

function resolveCanonicalOperatorUid(operatorAccounts, username) {
  const candidates = operatorAccounts
    .map((document) => ({
      uid: `${document.name}`.split('/').pop(),
      usernameNormalized:
        document?.fields?.usernameNormalized?.stringValue ?? null,
      updateTime: document?.updateTime ?? '',
    }))
    .filter(
      (candidate) =>
        candidate.usernameNormalized === username &&
        typeof candidate.uid === 'string' &&
        candidate.uid.trim().length > 0,
    )
    .sort((left, right) => {
      const leftSeed = left.uid.includes('-seed') ? 1 : 0;
      const rightSeed = right.uid.includes('-seed') ? 1 : 0;
      if (leftSeed !== rightSeed) {
        return leftSeed - rightSeed;
      }
      return `${right.updateTime}`.localeCompare(`${left.updateTime}`);
    });

  const uid = candidates[0]?.uid;
  if (typeof uid !== 'string' || uid.trim().length === 0) {
    throw new Error(`Could not resolve canonical uid for ${username}.`);
  }

  return uid.trim();
}

function resolveOperatorDisplayName(operatorAccounts, uid, fallback) {
  const match = operatorAccounts.find((document) => {
    const documentUid = `${document.name}`.split('/').pop();
    return documentUid === uid;
  });
  const value = match?.fields?.displayName?.stringValue;
  return typeof value === 'string' && value.trim().length > 0
    ? value.trim()
    : fallback;
}

async function listCollectionDocuments(accessToken, collectionId, pageSize) {
  const url =
    `https://firestore.googleapis.com/v1/projects/${projectId}` +
    `/databases/${databaseId}/documents/${collectionId}?pageSize=${pageSize}`;
  const response = await fetch(url, {
    headers: {
      Authorization: `Bearer ${accessToken}`,
    },
  });

  if (!response.ok) {
    const errorText = await response.text();
    throw new Error(
      `Could not list ${collectionId}: ${response.status} ${errorText}`,
    );
  }

  const payload = await response.json();
  return Array.isArray(payload?.documents) ? payload.documents : [];
}

async function patchFirestoreDocument(accessToken, path, data) {
  const masks = Object.keys(data)
    .map((key) => `updateMask.fieldPaths=${encodeURIComponent(key)}`)
    .join('&');
  const url =
    `https://firestore.googleapis.com/v1/projects/${projectId}` +
    `/databases/${databaseId}/documents/${path}?${masks}`;
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
  throw new Error(`Failed to patch ${path}: ${response.status} ${errorText}`);
}

async function deleteFirestoreDocument(accessToken, path) {
  const url =
    `https://firestore.googleapis.com/v1/projects/${projectId}` +
    `/databases/${databaseId}/documents/${path}`;
  const response = await fetch(url, {
    method: 'DELETE',
    headers: {
      Authorization: `Bearer ${accessToken}`,
    },
  });

  if (response.ok || response.status === 404) {
    return;
  }

  const errorText = await response.text();
  throw new Error(`Failed to delete ${path}: ${response.status} ${errorText}`);
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
