import { createHash } from 'node:crypto';

import { initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import {
  FieldValue,
  getFirestore,
  type DocumentData,
  type Timestamp,
} from 'firebase-admin/firestore';
import { HttpsError } from 'firebase-functions/v2/https';

import type { OperatorRole } from './types.js';

initializeApp();

export const db = getFirestore();
export const auth = getAuth();

const DEFAULT_TIMEZONE = 'Asia/Tashkent';

export interface OperatorAccountRecord extends DocumentData {
  role: OperatorRole;
  ownerId?: string | null;
  businessId?: string | null;
  businessIds?: string[];
  displayName?: string | null;
  usernameNormalized?: string | null;
  disabledAt?: Timestamp | null;
}

export interface BusinessRecord extends DocumentData {
  name?: string | null;
  groupId?: string | null;
  cashbackBasisPoints?: number | null;
  cashbackExpiryDays?: number | null;
  groupMembershipStatus?: string | null;
  tandemStatus?: string | null;
}

export interface CustomerRecord extends DocumentData {
  phoneE164: string;
  displayName?: string | null;
  isClaimed?: boolean;
  claimedByUid?: string | null;
}

export interface CustomerAuthLinkRecord extends DocumentData {
  customerId: string;
  phoneE164?: string | null;
}

export interface WalletLotRecord extends DocumentData {
  ownerCustomerId?: string | null;
  groupId: string;
  issuerBusinessId: string;
  originalIssueEventId: string;
  initialMinorUnits: number;
  availableMinorUnits: number;
  status?: string | null;
  expiresAt?: Timestamp | null;
}

export interface OperatorContext {
  uid: string;
  data: OperatorAccountRecord;
}

export function requireAuthUid(uid: string | undefined): string {
  if (!uid) {
    throw new HttpsError('unauthenticated', 'Authentication is required.');
  }
  return uid;
}

export function assertObject<T>(value: unknown): T {
  if (value == null || typeof value !== 'object' || Array.isArray(value)) {
    throw new HttpsError('invalid-argument', 'Expected an object payload.');
  }
  return value as T;
}

export function assertNonEmptyString(value: unknown, fieldName: string): string {
  if (typeof value !== 'string' || value.trim().length === 0) {
    throw new HttpsError(
      'invalid-argument',
      `${fieldName} must be a non-empty string.`,
    );
  }

  return value.trim();
}

export function assertPositiveInteger(value: unknown, fieldName: string): number {
  if (typeof value !== 'number' || !Number.isInteger(value) || value <= 0) {
    throw new HttpsError(
      'invalid-argument',
      `${fieldName} must be a positive integer.`,
    );
  }

  return value;
}

export function assertIntegerRange(
  value: unknown,
  fieldName: string,
  minimum: number,
  maximum: number,
): number {
  if (
    typeof value !== 'number' ||
    !Number.isInteger(value) ||
    value < minimum ||
    value > maximum
  ) {
    throw new HttpsError(
      'invalid-argument',
      `${fieldName} must be a whole number between ${minimum} and ${maximum}.`,
    );
  }

  return value;
}

export function assertStringMaxLength(
  value: unknown,
  fieldName: string,
  maxLength: number,
): string {
  const trimmed = assertNonEmptyString(value, fieldName);
  if (trimmed.length > maxLength) {
    throw new HttpsError(
      'invalid-argument',
      `${fieldName} must be at most ${maxLength} characters long.`,
    );
  }
  return trimmed;
}

export function assertOptionalStringMaxLength(
  value: unknown,
  fieldName: string,
  maxLength: number,
): string | undefined {
  if (value == null) {
    return undefined;
  }

  if (typeof value !== 'string') {
    throw new HttpsError(
      'invalid-argument',
      `${fieldName} must be a string when provided.`,
    );
  }

  const trimmed = value.trim();
  if (trimmed.length == 0) {
    return undefined;
  }
  if (trimmed.length > maxLength) {
    throw new HttpsError(
      'invalid-argument',
      `${fieldName} must be at most ${maxLength} characters long.`,
    );
  }
  return trimmed;
}

export function assertStringArray(
  value: unknown,
  fieldName: string,
  options: {
    minItems?: number;
    maxItems?: number;
    maxItemLength?: number;
  } = {},
): string[] {
  const { minItems = 0, maxItems = 20, maxItemLength = 120 } = options;
  if (!Array.isArray(value)) {
    throw new HttpsError(
      'invalid-argument',
      `${fieldName} must be an array of strings.`,
    );
  }

  const normalized = [...new Set(value.map((entry) => {
    if (typeof entry !== 'string') {
      throw new HttpsError(
        'invalid-argument',
        `${fieldName} must contain only strings.`,
      );
    }

    const trimmed = entry.trim();
    if (trimmed.length == 0) {
      throw new HttpsError(
        'invalid-argument',
        `${fieldName} cannot contain empty values.`,
      );
    }
    if (trimmed.length > maxItemLength) {
      throw new HttpsError(
        'invalid-argument',
        `${fieldName} entries must be at most ${maxItemLength} characters long.`,
      );
    }
    return trimmed;
  }))];

  if (normalized.length < minItems || normalized.length > maxItems) {
    throw new HttpsError(
      'invalid-argument',
      `${fieldName} must contain between ${minItems} and ${maxItems} values.`,
    );
  }

  return normalized;
}

export function normalizeUsername(username: string): string {
  return username.trim().toLowerCase().replace(/\s+/g, '.');
}

export function normalizePhoneE164(rawPhone: string): string {
  let normalized = rawPhone.replace(/[^\d+]/g, '');

  if (normalized.startsWith('00')) {
    normalized = `+${normalized.substring(2)}`;
  } else if (!normalized.startsWith('+')) {
    normalized = `+${normalized}`;
  }

  normalized = `+${normalized.substring(1).replace(/\D/g, '')}`;

  if (!/^\+\d{10,15}$/.test(normalized)) {
    throw new HttpsError(
      'invalid-argument',
      'Phone number must be a valid E.164 value.',
    );
  }

  return normalized;
}

export function buildOperatorAliasEmail(username: string): string {
  return `${normalizeUsername(username)}@operators.teamcash.local`;
}

export function createOperationKey(...parts: string[]): string {
  return createHash('sha256').update(parts.join('|')).digest('hex');
}

export function addDays(date: Date, days: number): Date {
  return new Date(date.getTime() + days * 24 * 60 * 60 * 1000);
}

export function getBusinessDayId(date: Date): string {
  return new Intl.DateTimeFormat('en-CA', {
    timeZone: DEFAULT_TIMEZONE,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).format(date).replace(/-/g, '');
}

export function serverTimestamp() {
  return FieldValue.serverTimestamp();
}

export async function requireOperatorRole(
  uid: string,
  allowedRoles: OperatorRole[],
): Promise<OperatorContext> {
  const snap = await db.doc(`operatorAccounts/${uid}`).get();
  if (!snap.exists) {
    throw new HttpsError('permission-denied', 'Operator account not found.');
  }

  const data = snap.data() as OperatorAccountRecord | undefined;
  if (!data) {
    throw new HttpsError('permission-denied', 'Operator account is empty.');
  }

  if (data.disabledAt) {
    throw new HttpsError('permission-denied', 'Operator account is disabled.');
  }

  if (!allowedRoles.includes(data.role)) {
    throw new HttpsError(
      'permission-denied',
      'Insufficient role for this operation.',
    );
  }

  return {
    uid,
    data,
  };
}

export function assertOperatorCanAccessBusiness(
  operator: OperatorContext,
  businessId: string,
): void {
  if (operator.data.role == 'owner') {
    if (!(operator.data.businessIds ?? []).includes(businessId)) {
      throw new HttpsError(
        'permission-denied',
        'Owner does not have access to this business.',
      );
    }
    return;
  }

  if (operator.data.role == 'staff' && operator.data.businessId == businessId) {
    return;
  }

  throw new HttpsError(
    'permission-denied',
    'Staff can operate only inside the assigned business.',
  );
}

export function ensureBusinessGroupMatch(
  business: BusinessRecord,
  requestedGroupId: string,
): void {
  if (business.groupId != null && business.groupId != requestedGroupId) {
    throw new HttpsError(
      'failed-precondition',
      'Business does not belong to the requested tandem group.',
    );
  }

  const status = business.groupMembershipStatus ?? business.tandemStatus;
  if (status != null && status != 'active') {
    throw new HttpsError(
      'failed-precondition',
      'Business is not active in the tandem group.',
    );
  }
}

export async function requireClaimedCustomerLink(
  uid: string,
): Promise<CustomerAuthLinkRecord> {
  const snap = await db.doc(`customerAuthLinks/${uid}`).get();
  if (!snap.exists) {
    throw new HttpsError(
      'permission-denied',
      'The verified client must claim the phone-backed wallet before transferring cashback.',
    );
  }

  const data = snap.data() as CustomerAuthLinkRecord | undefined;
  if (
    !data ||
    typeof data.customerId !== 'string' ||
    data.customerId.trim().length === 0
  ) {
    throw new HttpsError(
      'data-loss',
      'Customer auth link is missing the wallet identity.',
    );
  }

  return data;
}

export function normalizeHttpsError(error: unknown): HttpsError {
  if (error instanceof HttpsError) {
    return error;
  }

  if (error instanceof Error) {
    return new HttpsError('internal', error.message);
  }

  return new HttpsError('internal', 'Unexpected backend failure.');
}
