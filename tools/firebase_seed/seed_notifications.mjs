import { readFile } from 'node:fs/promises';
import { homedir } from 'node:os';
import { join } from 'node:path';

const projectId = 'teamcash-83a6e';
const databaseId = '(default)';
const groupId = 'old-town-circle';
const businessId = 'silk-road-cafe';
const businessName = 'Silk Road Cafe';
const firebaseCliOAuthClientId =
  '563584335869-fgrhgmd47bqnekij5i8b5pr03ho849e6.apps.googleusercontent.com';
const firebaseCliOAuthClientSecret = 'j9iVZfS8kkCEFUPaAeJV0sAi';

await main();

async function main() {
  const accessToken = await readFirebaseAccessToken();
  const ownerUid = await readOperatorUid(accessToken, 'aziza.owner');
  const staffUid = await readOperatorUid(accessToken, 'nadia.silkroad');
  const clientLink = await readAnyCustomerAuthLink(accessToken);
  const now = new Date().toISOString();

  const documents = [
    [
      `notifications/seed-owner-join-request-${ownerUid}`,
      {
        recipientUid: ownerUid,
        roleSurface: 'owner',
        kind: 'group_join_requested',
        title: 'Cedar Studio is waiting for your vote',
        body:
          'A pending tandem join request is still open. All active members must approve before membership becomes active.',
        businessId: 'cedar-studio',
        customerId: null,
        groupId,
        entityId: 'join-cedar',
        actionRoute: '/owner',
        actionLabel: 'Open approvals',
        isRead: false,
        readAt: null,
        createdAt: now,
        updatedAt: now,
      },
    ],
    [
      `notifications/seed-staff-assignment-${staffUid}`,
      {
        recipientUid: staffUid,
        roleSurface: 'staff',
        kind: 'staff_assignment',
        title: `Assigned to ${businessName}`,
        body:
          'Your staff permissions are limited to this business only. Dashboard and scan actions remain scoped here.',
        businessId,
        customerId: null,
        groupId,
        entityId: businessId,
        actionRoute: '/staff',
        actionLabel: 'Open staff workspace',
        isRead: false,
        readAt: null,
        createdAt: now,
        updatedAt: now,
      },
    ],
  ];

  if (clientLink != null) {
    documents.push([
      `notifications/seed-client-wallet-${clientLink.uid}`,
      {
        recipientUid: clientLink.uid,
        roleSurface: 'client',
        kind: 'cashback_expiring',
        title: 'Cashback will expire soon',
        body:
          'One of your active tandem lots expires within the next 14 days. Review expiring cashback before checkout.',
        businessId,
        customerId: clientLink.customerId,
        groupId,
        entityId: 'seed-client-wallet-alert',
        actionRoute: '/client',
        actionLabel: 'Open wallet',
        isRead: false,
        readAt: null,
        createdAt: now,
        updatedAt: now,
      },
    ]);
  }

  for (const [path, data] of documents) {
    await upsertFirestoreDocument(accessToken, path, data);
  }

  console.log(
    JSON.stringify(
      {
        ok: true,
        projectId,
        ownerUid,
        staffUid,
        clientUid: clientLink?.uid ?? null,
        seededDocuments: documents.length,
      },
      null,
      2,
    ),
  );
}

async function readOperatorUid(accessToken, username) {
  const accounts = await listCollectionDocuments(accessToken, 'operatorAccounts', 50);
  const candidates = accounts
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
    throw new Error(`Could not resolve uid for ${username}.`);
  }
  return uid.trim();
}

async function readAnyCustomerAuthLink(accessToken) {
  const [document] = await listCollectionDocuments(
    accessToken,
    'customerAuthLinks',
    1,
  );
  if (document == null) {
    return null;
  }

  const uid = `${document.name}`.split('/').pop();
  const customerId = document?.fields?.customerId?.stringValue;
  if (
    typeof uid !== 'string' ||
    uid.trim().length === 0 ||
    typeof customerId !== 'string' ||
    customerId.trim().length === 0
  ) {
    return null;
  }

  return {
    uid: uid.trim(),
    customerId: customerId.trim(),
  };
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

async function readFirestoreDocument(accessToken, path) {
  const url =
    `https://firestore.googleapis.com/v1/projects/${projectId}` +
    `/databases/${databaseId}/documents/${path}`;
  const response = await fetch(url, {
    headers: {
      Authorization: `Bearer ${accessToken}`,
    },
  });

  if (!response.ok) {
    const errorText = await response.text();
    throw new Error(`Could not read ${path}: ${response.status} ${errorText}`);
  }

  return response.json();
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

function isIsoTimestamp(value) {
  return /^\d{4}-\d{2}-\d{2}T/.test(value);
}
