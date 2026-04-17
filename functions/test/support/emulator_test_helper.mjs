import { readFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import { initializeApp, cert, getApps } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore } from 'firebase-admin/firestore';
import { initializeTestEnvironment } from '@firebase/rules-unit-testing';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const rootDir = path.resolve(__dirname, '..', '..', '..');
let resetEnvironmentPromise;

export const emulatorProjectId = 'demo-teamcash';
export const callableRegion = 'us-central1';
export const emulatorHosts = {
  auth: '127.0.0.1:9099',
  firestore: '127.0.0.1:8080',
  functions: '127.0.0.1:5001',
};

process.env.GCLOUD_PROJECT = emulatorProjectId;
process.env.FIREBASE_AUTH_EMULATOR_HOST = emulatorHosts.auth;
process.env.FIRESTORE_EMULATOR_HOST = emulatorHosts.firestore;

if (getApps().length === 0) {
  initializeApp({ projectId: emulatorProjectId });
}

export const adminAuth = getAuth();
export const adminDb = getFirestore();

export async function resetEmulators() {
  const resetEnvironment = await getResetEnvironment();

  await Promise.all([
    resetEnvironment.clearFirestore(),
    fetch(
      `http://${emulatorHosts.auth}/emulator/v1/projects/${emulatorProjectId}/accounts`,
      { method: 'DELETE' },
    ),
  ]);
}

export async function createEmailUser({
  uid,
  email,
  password,
  displayName,
}) {
  const userRecord = await adminAuth.createUser({
    uid,
    email,
    password,
    displayName,
    emailVerified: true,
  });

  return userRecord;
}

export async function seedOwnerAccount({
  uid,
  displayName,
  businessIds = [],
}) {
  await adminDb.doc(`operatorAccounts/${uid}`).set({
    role: 'owner',
    ownerId: null,
    businessIds,
    displayName,
    disabledAt: null,
    createdAt: new Date(),
    updatedAt: new Date(),
  });
}

export async function seedBusiness({
  businessId,
  ownerUid,
  name,
  groupId = null,
  groupName = null,
  groupMembershipStatus = 'none',
}) {
  await adminDb.doc(`businesses/${businessId}`).set({
    id: businessId,
    ownerUid,
    name,
    category: 'Cafe',
    description: `${name} description`,
    address: 'Tashkent',
    workingHours: '09:00 - 21:00',
    phoneNumbers: ['+998901112233'],
    cashbackBasisPoints: 500,
    cashbackExpiryDays: 180,
    redeemPolicy: 'Standard',
    groupId,
    groupName,
    groupMembershipStatus,
    tandemStatus: groupMembershipStatus,
    locationsCount: 0,
    productsCount: 0,
    manualPhoneIssuingEnabled: true,
    createdAt: new Date(),
    updatedAt: new Date(),
  });
}

export async function seedGroup({
  groupId,
  name,
  activeBusinessIds,
  createdByOwnerUid,
  createdByBusinessId,
}) {
  await adminDb.doc(`groups/${groupId}`).set({
    name,
    status: 'active',
    activeBusinessIds,
    pendingBusinessIds: [],
    createdByOwnerUid,
    createdByBusinessId,
    createdAt: new Date(),
    updatedAt: new Date(),
  });
}

export async function signInWithPassword(email, password) {
  const response = await fetch(
    `http://${emulatorHosts.auth}/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=fake-api-key`,
    {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({
        email,
        password,
        returnSecureToken: true,
      }),
    },
  );
  const body = await response.json();
  if (!response.ok) {
    throw new Error(body.error?.message ?? 'Auth emulator sign-in failed.');
  }

  return body.idToken;
}

export async function callFunction(name, payload, idToken) {
  const response = await fetch(
    `http://${emulatorHosts.functions}/${emulatorProjectId}/${callableRegion}/${name}`,
    {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        ...(idToken ? { authorization: `Bearer ${idToken}` } : {}),
      },
      body: JSON.stringify({ data: payload }),
    },
  );
  const body = await response.json();

  if (!response.ok || body.error) {
    const message = body.error?.message ?? body.error?.status ?? 'Callable failed.';
    const code = body.error?.status?.toLowerCase().replaceAll('_', '-') ?? 'unknown';
    const error = new Error(message);
    error.code = code;
    throw error;
  }

  return body.result;
}

export async function createRulesTestEnvironment() {
  const rules = await readFirestoreRules();

  return initializeTestEnvironment({
    projectId: emulatorProjectId,
    firestore: {
      host: '127.0.0.1',
      port: 8080,
      rules,
    },
  });
}

async function getResetEnvironment() {
  if (resetEnvironmentPromise == null) {
    resetEnvironmentPromise = createRulesTestEnvironment();
  }

  return resetEnvironmentPromise;
}

async function readFirestoreRules() {
  const rules = await readFile(path.join(rootDir, 'firestore.rules'), 'utf8');

  return rules;
}
