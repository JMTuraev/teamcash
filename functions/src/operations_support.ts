import { HttpsError } from 'firebase-functions/v2/https';
import {
  FieldPath,
  FieldValue,
  Timestamp,
  type DocumentReference,
  type Transaction,
} from 'firebase-admin/firestore';

import {
  addDays,
  db,
  getBusinessDayId,
  normalizePhoneE164,
  serverTimestamp,
  type BusinessRecord,
  type CustomerRecord,
  type WalletLotRecord,
} from './core.js';
import type {
  AdminAdjustCashbackInput,
  RedeemCashbackInput,
} from './types.js';

export const DEFAULT_CASHBACK_EXPIRY_DAYS = 180;
const REFUND_GRACE_DAYS = 30;
const DEFAULT_EXPIRY_SWEEP_LIMIT = 100;
const MAX_EXPIRY_SWEEP_LIMIT = 200;

export interface CustomerIdentityResult {
  customerId: string;
  customerRef: DocumentReference;
  indexRef: DocumentReference;
  created: boolean;
  customerExists: boolean;
  customerData?: CustomerRecord;
  indexExists: boolean;
}

export interface BusinessContext {
  businessId: string;
  data: BusinessRecord;
}

export interface ExpireLotResult {
  lotId: string;
  eventId: string;
  customerId: string;
  amountMinorUnits: number;
  issuerBusinessId: string;
  groupId: string;
}

export function resolveRefundExpiryTimestamp(
  originalExpiresAt: Timestamp | null,
  now: Date,
): Timestamp {
  const refundGraceExpiry = Timestamp.fromDate(addDays(now, REFUND_GRACE_DAYS));
  if (originalExpiresAt == null) {
    return refundGraceExpiry;
  }

  return originalExpiresAt.toMillis() > refundGraceExpiry.toMillis()
    ? originalExpiresAt
    : refundGraceExpiry;
}

export function normalizeExpirySweepLimit(value: number | undefined): number {
  if (value == null || !Number.isInteger(value) || value <= 0) {
    return DEFAULT_EXPIRY_SWEEP_LIMIT;
  }

  return Math.min(value, MAX_EXPIRY_SWEEP_LIMIT);
}

export async function expireActiveWalletLotDocument({
  lotRef,
  actorBusinessId,
  operatorUid,
  trigger,
}: {
  lotRef: DocumentReference;
  actorBusinessId?: string;
  operatorUid?: string;
  trigger: 'manual_sweep' | 'scheduled_sweep';
}): Promise<ExpireLotResult | null> {
  return db.runTransaction(async (transaction) => {
    const lotSnap = await transaction.get(lotRef);
    if (!lotSnap.exists) {
      return null;
    }

    const lot = lotSnap.data() as WalletLotRecord;
    const expiresAt = lot.expiresAt ?? null;
    if (
      expiresAt == null ||
      expiresAt.toMillis() > Timestamp.now().toMillis() ||
      lot.status != 'active' ||
      lot.availableMinorUnits <= 0 ||
      lot.ownerCustomerId == null
    ) {
      return null;
    }

    const expireEventRef = db.collection('ledgerEvents').doc();
    const resolvedActorBusinessId = actorBusinessId ?? lot.issuerBusinessId;

    transaction.set(
      lotRef,
      {
        availableMinorUnits: 0,
        status: 'expired',
        lastExpiredAt: serverTimestamp(),
        expiredByTrigger: trigger,
        updatedAt: serverTimestamp(),
      },
      { merge: true },
    );
    transaction.set(expireEventRef, {
      eventType: 'expire',
      groupId: lot.groupId,
      issuerBusinessId: lot.issuerBusinessId,
      actorBusinessId: resolvedActorBusinessId,
      targetBusinessId: resolvedActorBusinessId,
      operatorUid: operatorUid ?? null,
      sourceCustomerId: lot.ownerCustomerId,
      targetCustomerId: lot.ownerCustomerId,
      amountMinorUnits: lot.availableMinorUnits,
      lotId: lotSnap.id,
      originalIssueEventId: lot.originalIssueEventId,
      expiryTrigger: trigger,
      participantBusinessIds: uniqueStrings([
        resolvedActorBusinessId,
        lot.issuerBusinessId,
      ]),
      participantCustomerIds: [lot.ownerCustomerId],
      expiresAt,
      createdAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
    });
    transaction.set(
      db.doc(`customers/${lot.ownerCustomerId}`),
      {
        updatedAt: serverTimestamp(),
        lastActivityAt: serverTimestamp(),
      },
      { merge: true },
    );

    return {
      lotId: lotSnap.id,
      eventId: expireEventRef.id,
      customerId: lot.ownerCustomerId,
      amountMinorUnits: lot.availableMinorUnits,
      issuerBusinessId: lot.issuerBusinessId,
      groupId: lot.groupId,
    };
  });
}

export async function resolveCustomerIdentityForAdminAdjustment(
  transaction: Transaction,
  input: AdminAdjustCashbackInput,
  allowCreateFromPhone: boolean,
): Promise<{
  customerId: string;
  customerRef: DocumentReference;
  customerData?: CustomerRecord;
  created: boolean;
  existedBefore: boolean;
  phoneE164: string | null;
}> {
  if (input.customerId != null && input.customerId.trim().length > 0) {
    const customerId = input.customerId.trim();
    const customerRef = db.doc(`customers/${customerId}`);
    const customerSnap = await transaction.get(customerRef);
    if (!customerSnap.exists) {
      throw new HttpsError('not-found', 'Customer wallet was not found.');
    }

    const customerData = customerSnap.data() as CustomerRecord | undefined;
    if (
      input.customerPhoneE164 != null &&
      input.customerPhoneE164.trim().length > 0 &&
      customerData?.phoneE164 != null &&
      normalizePhoneE164(input.customerPhoneE164) !=
        normalizePhoneE164(customerData.phoneE164)
    ) {
      throw new HttpsError(
        'failed-precondition',
        'customerId and customerPhoneE164 do not point to the same wallet.',
      );
    }

    return {
      customerId,
      customerRef,
      customerData,
      created: false,
      existedBefore: true,
      phoneE164: customerData?.phoneE164 ?? null,
    };
  }

  const phoneE164 = normalizePhoneE164(input.customerPhoneE164 ?? '');
  if (allowCreateFromPhone) {
    const customerIdentity = await getOrCreateCustomerIdentity(
      transaction,
      phoneE164,
      'admin_adjustment',
    );

    if (!customerIdentity.indexExists) {
      transaction.set(customerIdentity.indexRef, {
        customerId: customerIdentity.customerId,
        phoneE164,
        createdAt: serverTimestamp(),
        updatedAt: serverTimestamp(),
      });
    }

    return {
      customerId: customerIdentity.customerId,
      customerRef: customerIdentity.customerRef,
      customerData: customerIdentity.customerData,
      created: customerIdentity.created,
      existedBefore: customerIdentity.customerExists,
      phoneE164,
    };
  }

  const phoneIndexRef = db.doc(`customerPhoneIndex/${phoneE164}`);
  const phoneIndexSnap = await transaction.get(phoneIndexRef);
  if (!phoneIndexSnap.exists) {
    throw new HttpsError(
      'not-found',
      'No wallet was found for this phone number.',
    );
  }

  const customerId = phoneIndexSnap.data()?.customerId;
  if (typeof customerId !== 'string' || customerId.length === 0) {
    throw new HttpsError(
      'data-loss',
      'Phone wallet index is missing the customer id.',
    );
  }

  const customerRef = db.doc(`customers/${customerId}`);
  const customerSnap = await transaction.get(customerRef);
  if (!customerSnap.exists) {
    throw new HttpsError('not-found', 'Customer wallet was not found.');
  }

  return {
    customerId,
    customerRef,
    customerData: customerSnap.data() as CustomerRecord | undefined,
    created: false,
    existedBefore: true,
    phoneE164,
  };
}

export async function resolveCustomerIdForRedeem(
  input: RedeemCashbackInput,
): Promise<string> {
  if (input.customerId != null && input.customerId.trim().length > 0) {
    return input.customerId.trim();
  }

  const phoneE164 = normalizePhoneE164(input.customerPhoneE164 ?? '');
  const phoneIndexSnap = await db.doc(`customerPhoneIndex/${phoneE164}`).get();
  if (!phoneIndexSnap.exists) {
    throw new HttpsError(
      'not-found',
      'No wallet was found for this phone number.',
    );
  }

  const customerId = phoneIndexSnap.data()?.customerId;
  if (typeof customerId !== 'string' || customerId.length === 0) {
    throw new HttpsError(
      'data-loss',
      'Phone wallet index is missing the customer id.',
    );
  }

  return customerId;
}

export async function resolveJoinRequestReference(requestId: string) {
  const querySnap = await db
    .collectionGroup('joinRequests')
    .where(FieldPath.documentId(), '==', requestId)
    .limit(1)
    .get();

  if (querySnap.empty) {
    throw new HttpsError('not-found', 'Join request was not found.');
  }

  return querySnap.docs[0].ref;
}

export async function loadBusinessContext(
  businessId: string,
): Promise<BusinessContext> {
  const businessRef = db.doc(`businesses/${businessId}`);
  const businessSnap = await businessRef.get();
  if (!businessSnap.exists) {
    throw new HttpsError(
      'failed-precondition',
      'Business must exist before ledger operations can be performed.',
    );
  }

  return {
    businessId,
    data: businessSnap.data() as BusinessRecord,
  };
}

export async function getOrCreateCustomerIdentity(
  transaction: Transaction,
  phoneE164: string,
  createdFrom: string,
): Promise<CustomerIdentityResult> {
  const indexRef = db.doc(`customerPhoneIndex/${phoneE164}`);
  const indexSnap = await transaction.get(indexRef);

  let customerRef: DocumentReference;

  if (indexSnap.exists) {
    const existingCustomerId = indexSnap.data()?.customerId;
    if (typeof existingCustomerId != 'string' || existingCustomerId.length == 0) {
      throw new HttpsError(
        'data-loss',
        'Phone index is corrupted and does not contain a customer id.',
      );
    }
    customerRef = db.doc(`customers/${existingCustomerId}`);
  } else {
    customerRef = db.collection('customers').doc();
  }

  const customerSnap = await transaction.get(customerRef);
  const customerData = customerSnap.data() as CustomerRecord | undefined;

  return {
    customerId: customerRef.id,
    customerRef,
    indexRef,
    created: !indexSnap.exists || !customerSnap.exists,
    customerExists: customerSnap.exists,
    customerData,
    indexExists: indexSnap.exists,
  };
}

export function incrementBusinessStats(
  transaction: Transaction,
  businessId: string,
  increments: Record<string, number>,
  activityAt: Date = new Date(),
) {
  const statsRef = db.doc(
    `businesses/${businessId}/statsDaily/${getBusinessDayId(activityAt)}`,
  );

  const statsPayload: Record<string, unknown> = {
    updatedAt: serverTimestamp(),
  };

  for (const [key, value] of Object.entries(increments)) {
    statsPayload[key] = FieldValue.increment(value);
  }

  transaction.set(statsRef, statsPayload, { merge: true });
}

export async function markBusinessCustomerTouch(
  transaction: Transaction,
  {
    businessId,
    customerId,
    phoneE164,
    activityAt,
    source,
  }: {
    businessId: string;
    customerId: string;
    phoneE164?: string;
    activityAt: Date;
    source: 'issue' | 'redeem';
  },
) {
  const dayId = getBusinessDayId(activityAt);
  const dailyTouchRef = db.doc(
    `businesses/${businessId}/statsDaily/${dayId}/customerTouches/${customerId}`,
  );
  const customerSummaryRef = db.doc(
    `businesses/${businessId}/customerSummaries/${customerId}`,
  );

  const [dailyTouchSnap, customerSummarySnap] = await Promise.all([
    transaction.get(dailyTouchRef),
    transaction.get(customerSummaryRef),
  ]);

  if (!dailyTouchSnap.exists) {
    incrementBusinessStats(
      transaction,
      businessId,
      {
        todayClientCount: 1,
        uniqueClientsCount: 1,
      },
      activityAt,
    );
  }

  if (!customerSummarySnap.exists) {
    incrementBusinessStats(
      transaction,
      businessId,
      {
        newClientCount: 1,
      },
      activityAt,
    );
  }

  const dailyTouchPayload: Record<string, unknown> = {
    customerId,
    phoneE164: phoneE164 ?? null,
    source,
    dayId,
    updatedAt: serverTimestamp(),
    lastTouchedAt: serverTimestamp(),
  };
  if (!dailyTouchSnap.exists) {
    dailyTouchPayload.createdAt = serverTimestamp();
    dailyTouchPayload.firstTouchedAt = serverTimestamp();
  }

  const customerSummaryPayload: Record<string, unknown> = {
    customerId,
    phoneE164: phoneE164 ?? null,
    lastActivitySource: source,
    lastActivityDayId: dayId,
    updatedAt: serverTimestamp(),
    lastActivityAt: serverTimestamp(),
  };
  if (!customerSummarySnap.exists) {
    customerSummaryPayload.createdAt = serverTimestamp();
    customerSummaryPayload.firstSeenAt = serverTimestamp();
  }

  transaction.set(dailyTouchRef, dailyTouchPayload, { merge: true });
  transaction.set(customerSummaryRef, customerSummaryPayload, { merge: true });
}

export function readCashbackBasisPoints(
  business: BusinessRecord,
  requestedBasisPoints: number,
): number {
  return typeof business.cashbackBasisPoints == 'number'
    ? business.cashbackBasisPoints
    : requestedBasisPoints;
}

export function readCashbackExpiryDays(business: BusinessRecord): number {
  return typeof business.cashbackExpiryDays == 'number' &&
      business.cashbackExpiryDays > 0
    ? business.cashbackExpiryDays
    : DEFAULT_CASHBACK_EXPIRY_DAYS;
}

export function uniqueStrings(values: string[]): string[] {
  return [...new Set(values)];
}

export function resolveVoterBusinessId({
  ownerBusinessIds,
  activeBusinessIds,
  requestedBusinessId,
}: {
  ownerBusinessIds: string[];
  activeBusinessIds: string[];
  requestedBusinessId?: string;
}): string {
  const eligibleBusinessIds = ownerBusinessIds.filter((businessId) =>
    activeBusinessIds.includes(businessId),
  );

  if (requestedBusinessId != null && requestedBusinessId.trim().length > 0) {
    const trimmedBusinessId = requestedBusinessId.trim();
    if (!eligibleBusinessIds.includes(trimmedBusinessId)) {
      throw new HttpsError(
        'permission-denied',
        'The selected business cannot vote on this join request.',
      );
    }
    return trimmedBusinessId;
  }

  if (eligibleBusinessIds.length == 1) {
    return eligibleBusinessIds[0];
  }

  if (eligibleBusinessIds.length == 0) {
    throw new HttpsError(
      'permission-denied',
      'This owner does not manage any active business inside the tandem group.',
    );
  }

  throw new HttpsError(
    'invalid-argument',
    'voterBusinessId is required because this owner manages multiple active businesses in the tandem group.',
  );
}

export function readStringList(
  data: Record<string, unknown> | undefined,
  key: string,
): string[] {
  const value = data?.[key];
  if (!Array.isArray(value)) {
    return [];
  }

  return value.filter((item): item is string => typeof item == 'string');
}

export function readIntValue(
  data: Record<string, unknown> | undefined,
  key: string,
): number | null {
  const value = data?.[key];
  if (typeof value == 'number') {
    return Math.trunc(value);
  }
  return null;
}

export function toIsoStringOrNull(value: Timestamp | null): string | null {
  return value?.toDate().toISOString() ?? null;
}

export function normalizeError(error: unknown): never {
  if (error instanceof HttpsError) {
    throw error;
  }

  if (error instanceof Error) {
    throw new HttpsError('internal', error.message);
  }

  throw new HttpsError('internal', 'Unexpected backend failure.');
}
