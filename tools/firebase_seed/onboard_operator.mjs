import { readFile } from 'node:fs/promises';
import { homedir } from 'node:os';
import { join } from 'node:path';

const projectId = process.env.TEAMCASH_PROJECT_ID || 'teamcash-83a6e';

await main();

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const uid = requireArg(args, 'uid');
  const role = requireArg(args, 'role');
  const username = normalizeUsername(requireArg(args, 'username'));
  const displayName = requireArg(args, 'display-name');
  const ownerUid = args['owner-uid'] || (role === 'owner' ? uid : '');
  const businessId = args['business-id'] || '';
  const businessIds = (
    args['business-ids'] || (businessId ? businessId : '')
  )
    .split(',')
    .map((value) => value.trim())
    .filter(Boolean);

  if (!['owner', 'staff'].includes(role)) {
    throw new Error('role must be either owner or staff.');
  }
  if (role === 'staff' && (!ownerUid || !businessId)) {
    throw new Error('staff onboarding requires --owner-uid and --business-id.');
  }
  if (businessIds.length === 0) {
    throw new Error('At least one business id is required.');
  }

  const accessToken = await readFirebaseAccessToken();
  const timestamp = new Date().toISOString();
  const aliasEmail = `${username}@operators.teamcash.local`;

  await upsertFirestoreDocument(accessToken, `operatorAccounts/${uid}`, {
    role,
    ownerId: ownerUid || null,
    businessId: businessId || null,
    businessIds,
    displayName,
    usernameNormalized: username,
    disabledAt: null,
    createdAt: timestamp,
    updatedAt: timestamp,
  });
  await upsertFirestoreDocument(accessToken, `operatorUsernames/${username}`, {
    uid,
    loginAliasEmail: aliasEmail,
    status: 'active',
    role,
    ownerId: ownerUid || null,
    businessId: businessId || null,
    businessIds,
    displayName,
    createdAt: timestamp,
    updatedAt: timestamp,
  });

  console.log(
    JSON.stringify(
      {
        ok: true,
        projectId,
        uid,
        role,
        username,
        aliasEmail,
        businessIds,
        note:
          'Firestore operator mapping was upserted. Auth user creation/reset should still happen through Firebase Auth or the live owner flow.',
      },
      null,
      2,
    ),
  );
}

function parseArgs(argv) {
  const result = {};
  for (let index = 0; index < argv.length; index += 1) {
    const entry = argv[index];
    if (!entry.startsWith('--')) {
      continue;
    }

    const key = entry.slice(2);
    const next = argv[index + 1];
    result[key] = next && !next.startsWith('--') ? next : 'true';
    if (result[key] === next) {
      index += 1;
    }
  }
  return result;
}

function requireArg(args, key) {
  const value = args[key];
  if (typeof value !== 'string' || value.trim().length === 0) {
    throw new Error(`Missing required argument --${key}`);
  }
  return value.trim();
}

function normalizeUsername(username) {
  return username.trim().toLowerCase().replace(/\s+/g, '.');
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

async function upsertFirestoreDocument(accessToken, path, data) {
  const url =
    `https://firestore.googleapis.com/v1/projects/${projectId}` +
    `/databases/(default)/documents/${path}`;
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

  if (!response.ok) {
    throw new Error(
      `Firestore upsert failed for ${path}: ${response.status} ${await response.text()}`,
    );
  }
}

function toFirestoreFields(value) {
  const entries = Object.entries(value);
  return Object.fromEntries(entries.map(([key, fieldValue]) => [key, toFirestoreValue(fieldValue)]));
}

function toFirestoreValue(value) {
  if (value == null) {
    return { nullValue: null };
  }
  if (Array.isArray(value)) {
    return {
      arrayValue: {
        values: value.map((entry) => toFirestoreValue(entry)),
      },
    };
  }
  if (typeof value === 'boolean') {
    return { booleanValue: value };
  }
  if (typeof value === 'number') {
    return Number.isInteger(value)
      ? { integerValue: String(value) }
      : { doubleValue: value };
  }
  if (typeof value === 'string') {
    if (/^\d{4}-\d{2}-\d{2}T/.test(value)) {
      return { timestampValue: value };
    }
    return { stringValue: value };
  }
  if (typeof value === 'object') {
    return { mapValue: { fields: toFirestoreFields(value) } };
  }

  throw new Error(`Unsupported Firestore value: ${value}`);
}
