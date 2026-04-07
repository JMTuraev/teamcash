import { readFile } from 'node:fs/promises';
import { homedir } from 'node:os';
import { join } from 'node:path';

const projectId = 'teamcash-83a6e';
const databaseId = '(default)';
const firebaseCliOAuthClientId =
  '563584335869-fgrhgmd47bqnekij5i8b5pr03ho849e6.apps.googleusercontent.com';
const firebaseCliOAuthClientSecret = 'j9iVZfS8kkCEFUPaAeJV0sAi';

const businesses = [
  {
    id: 'silk-road-cafe',
    logoUrl: buildPlaceholderUrl('Silk Road Cafe Logo', 420, 420),
    coverImageUrl: buildPlaceholderUrl('Silk Road Cafe Cover', 1280, 720),
    media: [
      {
        id: 'live-silk-road-cover',
        title: 'Garden brunch room',
        caption:
          'Natural-light tables and all-day brunch seating for shared tandem visits.',
        mediaType: 'interior',
        imageUrl: buildPlaceholderUrl('Garden Brunch Room', 960, 640),
        isFeatured: true,
      },
      {
        id: 'live-silk-road-dessert',
        title: 'Dessert counter',
        caption:
          'Signature cake shelf and fast takeaway pickup near the entrance.',
        mediaType: 'menu highlight',
        imageUrl: buildPlaceholderUrl('Dessert Counter', 960, 640),
        isFeatured: false,
      },
    ],
  },
  {
    id: 'atlas-dental',
    logoUrl: buildPlaceholderUrl('Atlas Dental Logo', 420, 420),
    coverImageUrl: buildPlaceholderUrl('Atlas Dental Cover', 1280, 720),
    media: [
      {
        id: 'live-atlas-room',
        title: 'Family consultation room',
        caption: 'Diagnostics and routine care environment for repeat visits.',
        mediaType: 'clinic',
        imageUrl: buildPlaceholderUrl('Family Consultation Room', 960, 640),
        isFeatured: true,
      },
    ],
  },
  {
    id: 'bread-and-ember',
    logoUrl: buildPlaceholderUrl('Bread and Ember Logo', 420, 420),
    coverImageUrl: buildPlaceholderUrl('Bread and Ember Cover', 1280, 720),
    media: [
      {
        id: 'live-bread-oven',
        title: 'Oven deck',
        caption: 'Fresh bread line, takeaway pastry case, and warm storefront.',
        mediaType: 'bakery',
        imageUrl: buildPlaceholderUrl('Oven Deck', 960, 640),
        isFeatured: true,
      },
    ],
  },
  {
    id: 'cedar-studio',
    logoUrl: buildPlaceholderUrl('Cedar Studio Logo', 420, 420),
    coverImageUrl: buildPlaceholderUrl('Cedar Studio Cover', 1280, 720),
    media: [
      {
        id: 'live-cedar-style',
        title: 'Style lounge',
        caption: 'Boutique salon portfolio card while waiting for group approval.',
        mediaType: 'portfolio',
        imageUrl: buildPlaceholderUrl('Style Lounge', 960, 640),
        isFeatured: true,
      },
    ],
  },
];

await main();

async function main() {
  const accessToken = await readFirebaseAccessToken();
  const now = new Date().toISOString();
  let patchedDocuments = 0;

  for (const business of businesses) {
    await upsertFirestoreDocument(
      accessToken,
      `businesses/${business.id}`,
      {
        logoUrl: business.logoUrl,
        logoStoragePath: '',
        coverImageUrl: business.coverImageUrl,
        coverImageStoragePath: '',
        updatedAt: now,
      },
      [
        'logoUrl',
        'logoStoragePath',
        'coverImageUrl',
        'coverImageStoragePath',
        'updatedAt',
      ],
    );
    patchedDocuments += 1;

    for (const media of business.media) {
      await upsertFirestoreDocument(
        accessToken,
        `businesses/${business.id}/media/${media.id}`,
        {
          id: media.id,
          businessId: business.id,
          title: media.title,
          caption: media.caption,
          mediaType: media.mediaType,
          imageUrl: media.imageUrl,
          storagePath: '',
          isFeatured: media.isFeatured,
          createdAt: now,
          updatedAt: now,
        },
      );
      patchedDocuments += 1;
    }
  }

  console.log(
    JSON.stringify(
      {
        ok: true,
        projectId,
        patchedDocuments,
        businesses: businesses.map((business) => ({
          id: business.id,
          mediaCount: business.media.length,
        })),
      },
      null,
      2,
    ),
  );
}

function buildPlaceholderUrl(text, width, height) {
  return `https://placehold.co/${width}x${height}/EAF2EE/1F2933.png?text=${encodeURIComponent(
    text,
  )}`;
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

async function upsertFirestoreDocument(
  accessToken,
  path,
  data,
  updateMaskFieldPaths,
) {
  const url =
    `https://firestore.googleapis.com/v1/projects/${projectId}` +
    `/databases/${databaseId}/documents/${path}`;
  const search = new URLSearchParams();
  for (const fieldPath of updateMaskFieldPaths ?? Object.keys(data)) {
    search.append('updateMask.fieldPaths', fieldPath);
  }
  const response = await fetch(search.size > 0 ? `${url}?${search}` : url, {
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
