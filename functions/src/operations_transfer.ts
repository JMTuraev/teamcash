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
  assertOperatorCanAccessBusiness,
  auth,
  buildOperatorAliasEmail,
  createOperationKey,
  db,
  ensureBusinessGroupMatch,
  getBusinessDayId,
  normalizePhoneE164,
  normalizeUsername,
  requireClaimedCustomerLink,
  requireOperatorRole,
  serverTimestamp,
  type BusinessRecord,
  type CustomerRecord,
  type WalletLotRecord,
} from './core.js';
import {
  notifyClaimedCustomerAdminAdjustment,
  notifyClaimedCustomerCashbackIssued,
  notifyClaimedCustomerCashbackRedeemed,
  notifyClaimedCustomerSharedCheckoutContributionReserved,
  notifyCustomersOfExpiredLots,
  notifyCustomersOfFinalizedSharedCheckout,
  notifyOwnersOfGroupJoinRequest,
  notifyRecipientOfPendingGift,
  notifyRefundBatchCustomers,
  notifySenderOfGiftClaim,
  notifyStaffAssignment,
  notifyTargetOwnersOfGroupJoinVote,
  safelyRunNotificationTask,
} from './notifications.js';
import {
  DEFAULT_CASHBACK_EXPIRY_DAYS,
  expireActiveWalletLotDocument,
  getOrCreateCustomerIdentity,
  incrementBusinessStats,
  loadBusinessContext,
  markBusinessCustomerTouch,
  normalizeError,
  normalizeExpirySweepLimit,
  readCashbackBasisPoints,
  readCashbackExpiryDays,
  readIntValue,
  readStringList,
  resolveCustomerIdForRedeem,
  resolveCustomerIdentityForAdminAdjustment,
  resolveJoinRequestReference,
  resolveRefundExpiryTimestamp,
  resolveVoterBusinessId,
  toIsoStringOrNull,
  uniqueStrings,
  type BusinessContext,
  type CustomerIdentityResult,
  type ExpireLotResult,
} from './operations_support.js';
import type {
  AdminAdjustCashbackInput,
  CreateBusinessInput,
  CreateGroupInput,
  ExpireWalletLotsInput,
  GiftTransferInput,
  GroupJoinRequestInput,
  GroupJoinVoteInput,
  IssueCashbackInput,
  RedeemCashbackInput,
  RefundCashbackInput,
  ResetStaffPasswordInput,
  SharedCheckoutContributionInput,
  SharedCheckoutInput,
  StaffAccountInput,
  UpdateStaffProfileInput,
} from './types.js';
import { claimCustomerWalletByPhoneFlow } from './operations_group.js';

export async function createGiftTransferFlow(
  uid: string,
  input: GiftTransferInput,
) {
  const customerLink = await requireClaimedCustomerLink(uid);
  if (customerLink.customerId != input.sourceCustomerId) {
    throw new HttpsError(
      'permission-denied',
      'Clients can transfer cashback only from their own claimed wallet.',
    );
  }

  const recipientPhoneE164 = normalizePhoneE164(input.recipientPhoneE164);
  if (
    customerLink.phoneE164 != null &&
    normalizePhoneE164(customerLink.phoneE164) == recipientPhoneE164
  ) {
    throw new HttpsError(
      'failed-precondition',
      'Cashback cannot be gifted to the same phone-backed wallet.',
    );
  }

  const operationKey = createOperationKey(
    'gift_transfer',
    input.sourceCustomerId,
    input.requestId.trim(),
  );
  const lockRef = db.doc(`operationLocks/${operationKey}`);
  const transferRef = db.collection('giftTransfers').doc();
  const transferOutEventRef = db.collection('ledgerEvents').doc();
  const giftPendingEventRef = db.collection('ledgerEvents').doc();
  const now = Timestamp.now();

  const result = await db.runTransaction(async (transaction) => {
    const lockSnap = await transaction.get(lockRef);
    if (lockSnap.exists) {
      return lockSnap.data()?.result;
    }

    const sourceCustomerRef = db.doc(`customers/${input.sourceCustomerId}`);
    const sourceCustomerSnap = await transaction.get(sourceCustomerRef);
    if (!sourceCustomerSnap.exists) {
      throw new HttpsError('not-found', 'Source customer wallet was not found.');
    }

    const lotsQuery = db
      .collection('walletLots')
      .where('ownerCustomerId', '==', input.sourceCustomerId)
      .where('groupId', '==', input.groupId)
      .orderBy('expiresAt', 'asc');

    const lotSnapshots = await transaction.get(lotsQuery);
    const usableLots = lotSnapshots.docs
      .map((doc) => ({
        id: doc.id,
        ref: doc.ref,
        data: doc.data() as WalletLotRecord,
      }))
      .filter((lot) => {
        const expiresAt = lot.data.expiresAt;
        const isExpired =
          expiresAt != null && expiresAt.toMillis() <= now.toMillis();
        if (
          isExpired &&
          lot.data.availableMinorUnits > 0 &&
          lot.data.status != 'expired'
        ) {
          transaction.set(
            lot.ref,
            {
              status: 'expired',
              updatedAt: serverTimestamp(),
            },
            { merge: true },
          );
        }

        return (
          !isExpired &&
          lot.data.availableMinorUnits > 0 &&
          lot.data.status != 'redeemed' &&
          lot.data.status != 'expired' &&
          lot.data.status != 'gift_pending' &&
          lot.data.status != 'shared_checkout_reserved'
        );
      });

    const availableTotal = usableLots.reduce(
      (sum, lot) => sum + lot.data.availableMinorUnits,
      0,
    );
    if (availableTotal < input.amountMinorUnits) {
      throw new HttpsError(
        'failed-precondition',
        'The client does not have enough active cashback in this tandem group.',
      );
    }

    let remaining = input.amountMinorUnits;
    const pendingLots: Array<{
      lotId: string;
      issuerBusinessId: string;
      amountMinorUnits: number;
      expiresAt: Timestamp | null;
    }> = [];
    const issuerBusinessIds = new Set<string>();
    let earliestExpiresAt: Timestamp | null = null;
    let latestExpiresAt: Timestamp | null = null;

    for (const lot of usableLots) {
      if (remaining <= 0) {
        break;
      }

      const transferMinorUnits = Math.min(remaining, lot.data.availableMinorUnits);
      const nextAvailable = lot.data.availableMinorUnits - transferMinorUnits;
      const pendingLotRef = db.collection('walletLots').doc();
      const expiresAt = lot.data.expiresAt ?? null;

      transaction.set(
        lot.ref,
        {
          availableMinorUnits: nextAvailable,
          status: nextAvailable == 0 ? 'transferred' : 'active',
          lastTransferredAt: serverTimestamp(),
          updatedAt: serverTimestamp(),
        },
        { merge: true },
      );
      transaction.set(pendingLotRef, {
        ownerCustomerId: null,
        sourceCustomerId: input.sourceCustomerId,
        groupId: input.groupId,
        issuerBusinessId: lot.data.issuerBusinessId,
        originalIssueEventId: lot.data.originalIssueEventId,
        initialMinorUnits: transferMinorUnits,
        availableMinorUnits: transferMinorUnits,
        parentLotId: lot.id,
        pendingGiftTransferId: transferRef.id,
        pendingRecipientPhoneE164: recipientPhoneE164,
        status: 'gift_pending',
        expiresAt,
        createdAt: serverTimestamp(),
        updatedAt: serverTimestamp(),
      });

      pendingLots.push({
        lotId: pendingLotRef.id,
        issuerBusinessId: lot.data.issuerBusinessId,
        amountMinorUnits: transferMinorUnits,
        expiresAt,
      });
      issuerBusinessIds.add(lot.data.issuerBusinessId);
      if (expiresAt != null) {
        if (
          earliestExpiresAt == null ||
          expiresAt.toMillis() < earliestExpiresAt.toMillis()
        ) {
          earliestExpiresAt = expiresAt;
        }
        if (
          latestExpiresAt == null ||
          expiresAt.toMillis() > latestExpiresAt.toMillis()
        ) {
          latestExpiresAt = expiresAt;
        }
      }
      remaining -= transferMinorUnits;
    }

    if (remaining > 0) {
      throw new HttpsError(
        'internal',
        'Gift transfer reservation did not cover the requested amount.',
      );
    }

    transaction.set(transferRef, {
      status: 'pending',
      requestedByUid: uid,
      sourceCustomerId: input.sourceCustomerId,
      recipientPhoneE164,
      groupId: input.groupId,
      amountMinorUnits: input.amountMinorUnits,
      requestId: input.requestId.trim(),
      participantBusinessIds: [...issuerBusinessIds],
      participantCustomerIds: [input.sourceCustomerId],
      pendingLotIds: pendingLots.map((lot) => lot.lotId),
      earliestExpiresAt,
      latestExpiresAt,
      transferOutEventId: transferOutEventRef.id,
      giftPendingEventId: giftPendingEventRef.id,
      createdAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
    });
    transaction.set(transferOutEventRef, {
      eventType: 'transfer_out',
      groupId: input.groupId,
      sourceCustomerId: input.sourceCustomerId,
      recipientPhoneE164,
      amountMinorUnits: input.amountMinorUnits,
      giftTransferId: transferRef.id,
      pendingLotIds: pendingLots.map((lot) => lot.lotId),
      participantBusinessIds: [...issuerBusinessIds],
      participantCustomerIds: [input.sourceCustomerId],
      createdAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
    });
    transaction.set(giftPendingEventRef, {
      eventType: 'gift_pending',
      groupId: input.groupId,
      sourceCustomerId: input.sourceCustomerId,
      recipientPhoneE164,
      amountMinorUnits: input.amountMinorUnits,
      giftTransferId: transferRef.id,
      pendingLotIds: pendingLots.map((lot) => lot.lotId),
      participantBusinessIds: [...issuerBusinessIds],
      participantCustomerIds: [input.sourceCustomerId],
      earliestExpiresAt,
      latestExpiresAt,
      createdAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
    });
    transaction.set(
      sourceCustomerRef,
      {
        updatedAt: serverTimestamp(),
        lastActivityAt: serverTimestamp(),
      },
      { merge: true },
    );

    const result = {
      operationKey,
      transferId: transferRef.id,
      amountMinorUnits: input.amountMinorUnits,
      recipientPhoneE164,
      pendingLotCount: pendingLots.length,
      earliestExpiresAtIso: toIsoStringOrNull(earliestExpiresAt),
      latestExpiresAtIso: toIsoStringOrNull(latestExpiresAt),
      transferOutEventId: transferOutEventRef.id,
      giftPendingEventId: giftPendingEventRef.id,
    };

    transaction.set(lockRef, {
      operationType: 'gift_transfer',
      customerId: input.sourceCustomerId,
      requestId: input.requestId.trim(),
      createdAt: serverTimestamp(),
      result,
    });

    return result;
  });

  await safelyRunNotificationTask('gift pending recipient notification', async () => {
    await notifyRecipientOfPendingGift({
      transferId:
        typeof result.transferId == 'string' ? result.transferId : transferRef.id,
      recipientPhoneE164,
      groupId: input.groupId,
      amountMinorUnits: input.amountMinorUnits,
    });
  });

  return result;
}

export async function claimGiftTransferFlow(
  uid: string,
  transferId: string,
  phoneNumber: unknown,
) {
  const claimLink = await claimCustomerWalletByPhoneFlow(uid, phoneNumber);
  const now = Timestamp.now();
  const transferRef = db.doc(`giftTransfers/${transferId}`);

  const result = await db.runTransaction(async (transaction) => {
    const transferSnap = await transaction.get(transferRef);
    if (!transferSnap.exists) {
      throw new HttpsError('not-found', 'Gift transfer was not found.');
    }

    const transfer = transferSnap.data() as {
      status?: string | null;
      sourceCustomerId?: string;
      recipientPhoneE164?: string;
      groupId?: string;
      amountMinorUnits?: number;
      result?: Record<string, unknown>;
    };

    if (
      transfer.recipientPhoneE164 == null ||
      normalizePhoneE164(transfer.recipientPhoneE164) != claimLink.phoneE164
    ) {
      throw new HttpsError(
        'permission-denied',
        'This verified phone number is not the intended gift recipient.',
      );
    }

    if (transfer.status != null && transfer.status != 'pending') {
      if (transfer.result != null) {
        return transfer.result;
      }

      throw new HttpsError(
        'failed-precondition',
        'This gift transfer is no longer pending.',
      );
    }

    if (transfer.sourceCustomerId == null || transfer.groupId == null) {
      throw new HttpsError(
        'data-loss',
        'Gift transfer is missing required ownership metadata.',
      );
    }

    const pendingLotsQuery = db
      .collection('walletLots')
      .where('pendingGiftTransferId', '==', transferId);
    const pendingLotSnapshots = await transaction.get(pendingLotsQuery);
    if (pendingLotSnapshots.empty) {
      throw new HttpsError(
        'data-loss',
        'Gift transfer does not contain any reserved wallet lots.',
      );
    }

    const claimedLotIds: string[] = [];
    const expiredLotIds: string[] = [];
    const issuerBusinessIds = new Set<string>();
    let claimedMinorUnits = 0;
    let expiredMinorUnits = 0;

    for (const pendingLotSnap of pendingLotSnapshots.docs) {
      const pendingLot = pendingLotSnap.data() as WalletLotRecord;
      const expiresAt = pendingLot.expiresAt ?? null;
      const isExpired =
        expiresAt != null && expiresAt.toMillis() <= now.toMillis();

      if (
        isExpired ||
        pendingLot.availableMinorUnits <= 0 ||
        pendingLot.status == 'expired'
      ) {
        expiredMinorUnits += Math.max(pendingLot.availableMinorUnits, 0);
        expiredLotIds.push(pendingLotSnap.id);
        transaction.set(
          pendingLotSnap.ref,
          {
            status: 'expired',
            updatedAt: serverTimestamp(),
          },
          { merge: true },
        );
        continue;
      }

      claimedMinorUnits += pendingLot.availableMinorUnits;
      claimedLotIds.push(pendingLotSnap.id);
      issuerBusinessIds.add(pendingLot.issuerBusinessId);

      transaction.set(
        pendingLotSnap.ref,
        {
          ownerCustomerId: claimLink.customerId,
          status: 'active',
          claimedAt: serverTimestamp(),
          updatedAt: serverTimestamp(),
        },
        { merge: true },
      );
    }

    const recipientCustomerRef = db.doc(`customers/${claimLink.customerId}`);
    transaction.set(
      recipientCustomerRef,
      {
        updatedAt: serverTimestamp(),
        lastActivityAt: serverTimestamp(),
      },
      { merge: true },
    );

    const finalStatus =
      claimedMinorUnits <= 0
          ? 'expired'
          : expiredMinorUnits > 0
          ? 'claimed_partial'
          : 'claimed';

    let giftClaimedEventId: string | null = null;
    let transferInEventId: string | null = null;

    if (claimedMinorUnits > 0) {
      const giftClaimedEventRef = db.collection('ledgerEvents').doc();
      const transferInEventRef = db.collection('ledgerEvents').doc();
      giftClaimedEventId = giftClaimedEventRef.id;
      transferInEventId = transferInEventRef.id;

      transaction.set(giftClaimedEventRef, {
        eventType: 'gift_claimed',
        groupId: transfer.groupId,
        sourceCustomerId: transfer.sourceCustomerId,
        targetCustomerId: claimLink.customerId,
        recipientPhoneE164: claimLink.phoneE164,
        amountMinorUnits: claimedMinorUnits,
        expiredMinorUnits,
        giftTransferId: transferId,
        claimedLotIds,
        participantBusinessIds: [...issuerBusinessIds],
        participantCustomerIds: uniqueStrings([
          transfer.sourceCustomerId,
          claimLink.customerId,
        ]),
        createdAt: serverTimestamp(),
        updatedAt: serverTimestamp(),
      });
      transaction.set(transferInEventRef, {
        eventType: 'transfer_in',
        groupId: transfer.groupId,
        sourceCustomerId: transfer.sourceCustomerId,
        targetCustomerId: claimLink.customerId,
        recipientPhoneE164: claimLink.phoneE164,
        amountMinorUnits: claimedMinorUnits,
        expiredMinorUnits,
        giftTransferId: transferId,
        claimedLotIds,
        participantBusinessIds: [...issuerBusinessIds],
        participantCustomerIds: uniqueStrings([
          transfer.sourceCustomerId,
          claimLink.customerId,
        ]),
        createdAt: serverTimestamp(),
        updatedAt: serverTimestamp(),
      });
    }

    const result = {
      transferId,
      customerId: claimLink.customerId,
      claimedMinorUnits,
      expiredMinorUnits,
      claimedLotCount: claimedLotIds.length,
      expiredLotCount: expiredLotIds.length,
      status: finalStatus,
      giftClaimedEventId,
      transferInEventId,
    };

    transaction.set(
      transferRef,
      {
        status: finalStatus,
        recipientCustomerId: claimLink.customerId,
        claimedByUid: uid,
        claimedAt: serverTimestamp(),
        participantBusinessIds: [...issuerBusinessIds],
        participantCustomerIds: uniqueStrings([
          transfer.sourceCustomerId,
          claimLink.customerId,
        ]),
        claimedMinorUnits,
        expiredMinorUnits,
        claimedLotIds,
        expiredLotIds,
        giftClaimedEventId,
        transferInEventId,
        updatedAt: serverTimestamp(),
        result,
      },
      { merge: true },
    );

    return result;
  });

  await safelyRunNotificationTask('gift claimed sender notification', async () => {
    await notifySenderOfGiftClaim({
      transferId,
      claimedMinorUnits:
        typeof result.claimedMinorUnits == 'number' ? result.claimedMinorUnits : 0,
      expiredMinorUnits:
        typeof result.expiredMinorUnits == 'number' ? result.expiredMinorUnits : 0,
    });
  });

  return result;
}

export async function createSharedCheckoutFlow(
  operatorUid: string,
  input: SharedCheckoutInput,
) {
  const operator = await requireOperatorRole(operatorUid, ['owner', 'staff']);
  assertOperatorCanAccessBusiness(operator, input.businessId);

  const business = await loadBusinessContext(input.businessId);
  ensureBusinessGroupMatch(business.data, input.groupId);

  const operationKey = createOperationKey(
    'shared_checkout_create',
    input.businessId,
    input.sourceTicketRef.trim(),
  );
  const lockRef = db.doc(`operationLocks/${operationKey}`);
  const checkoutRef = db.collection('sharedCheckouts').doc();
  const createdEventRef = db.collection('ledgerEvents').doc();

  return db.runTransaction(async (transaction) => {
    const lockSnap = await transaction.get(lockRef);
    if (lockSnap.exists) {
      return lockSnap.data()?.result;
    }

    transaction.set(checkoutRef, {
      businessId: input.businessId,
      groupId: input.groupId,
      status: 'open',
      totalMinorUnits: input.totalMinorUnits,
      contributedMinorUnits: 0,
      remainingMinorUnits: input.totalMinorUnits,
      sourceTicketRef: input.sourceTicketRef.trim(),
      createdByOperatorUid: operatorUid,
      createdEventId: createdEventRef.id,
      participantBusinessIds: [input.businessId],
      participantCustomerIds: [],
      contributionsCount: 0,
      createdAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
    });
    transaction.set(createdEventRef, {
      eventType: 'shared_checkout_created',
      groupId: input.groupId,
      actorBusinessId: input.businessId,
      targetBusinessId: input.businessId,
      operatorUid,
      amountMinorUnits: input.totalMinorUnits,
      checkoutId: checkoutRef.id,
      sourceTicketRef: input.sourceTicketRef.trim(),
      participantBusinessIds: [input.businessId],
      participantCustomerIds: [],
      createdAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
    });

    const result = {
      operationKey,
      checkoutId: checkoutRef.id,
      status: 'open',
      totalMinorUnits: input.totalMinorUnits,
      contributedMinorUnits: 0,
      remainingMinorUnits: input.totalMinorUnits,
      createdEventId: createdEventRef.id,
    };

    transaction.set(lockRef, {
      operationType: 'shared_checkout_create',
      businessId: input.businessId,
      sourceTicketRef: input.sourceTicketRef.trim(),
      createdAt: serverTimestamp(),
      result,
    });

    return result;
  });
}

export async function contributeSharedCheckoutFlow(
  uid: string,
  input: SharedCheckoutContributionInput,
) {
  const customerLink = await requireClaimedCustomerLink(uid);
  if (customerLink.customerId != input.customerId) {
    throw new HttpsError(
      'permission-denied',
      'Clients can contribute only from their own claimed wallet.',
    );
  }

  const operationKey = createOperationKey(
    'shared_checkout_contribution',
    input.checkoutId,
    input.customerId,
    input.requestId.trim(),
  );
  const lockRef = db.doc(`operationLocks/${operationKey}`);
  const now = Timestamp.now();

  const result = await db.runTransaction(async (transaction) => {
    const lockSnap = await transaction.get(lockRef);
    if (lockSnap.exists) {
      return lockSnap.data()?.result;
    }

    const checkoutRef = db.doc(`sharedCheckouts/${input.checkoutId}`);
    const checkoutSnap = await transaction.get(checkoutRef);
    if (!checkoutSnap.exists) {
      throw new HttpsError('not-found', 'Shared checkout was not found.');
    }

    const checkout = checkoutSnap.data() as {
      businessId?: string;
      groupId?: string;
      status?: string | null;
      totalMinorUnits?: number;
      contributedMinorUnits?: number;
    };

    if (
      typeof checkout.businessId !== 'string' ||
      typeof checkout.groupId !== 'string' ||
      typeof checkout.totalMinorUnits !== 'number'
    ) {
      throw new HttpsError(
        'data-loss',
        'Shared checkout is missing required business or group metadata.',
      );
    }

    if (checkout.status != null && checkout.status != 'open') {
      throw new HttpsError(
        'failed-precondition',
        'This shared checkout is not accepting contributions anymore.',
      );
    }

    const contributedMinorUnits =
      typeof checkout.contributedMinorUnits == 'number'
        ? checkout.contributedMinorUnits
        : 0;
    if (
      contributedMinorUnits + input.contributionMinorUnits >
      checkout.totalMinorUnits
    ) {
      throw new HttpsError(
        'failed-precondition',
        'This contribution would exceed the checkout total.',
      );
    }

    const customerRef = db.doc(`customers/${input.customerId}`);
    const customerSnap = await transaction.get(customerRef);
    if (!customerSnap.exists) {
      throw new HttpsError('not-found', 'Customer wallet was not found.');
    }

    const lotsQuery = db
      .collection('walletLots')
      .where('ownerCustomerId', '==', input.customerId)
      .where('groupId', '==', checkout.groupId)
      .orderBy('expiresAt', 'asc');

    const lotSnapshots = await transaction.get(lotsQuery);
    const usableLots = lotSnapshots.docs
      .map((doc) => ({
        id: doc.id,
        ref: doc.ref,
        data: doc.data() as WalletLotRecord,
      }))
      .filter((lot) => {
        const expiresAt = lot.data.expiresAt;
        const isExpired =
          expiresAt != null && expiresAt.toMillis() <= now.toMillis();
        if (
          isExpired &&
          lot.data.availableMinorUnits > 0 &&
          lot.data.status != 'expired'
        ) {
          transaction.set(
            lot.ref,
            {
              status: 'expired',
              updatedAt: serverTimestamp(),
            },
            { merge: true },
          );
        }

        return (
          !isExpired &&
          lot.data.availableMinorUnits > 0 &&
          lot.data.status != 'redeemed' &&
          lot.data.status != 'expired' &&
          lot.data.status != 'gift_pending' &&
          lot.data.status != 'shared_checkout_reserved'
        );
      });

    const availableTotal = usableLots.reduce(
      (sum, lot) => sum + lot.data.availableMinorUnits,
      0,
    );
    if (availableTotal < input.contributionMinorUnits) {
      throw new HttpsError(
        'failed-precondition',
        'The client does not have enough active cashback for this shared checkout.',
      );
    }

    const contributionRef = checkoutRef.collection('contributions').doc();
    const contributionEventRef = db.collection('ledgerEvents').doc();
    let remaining = input.contributionMinorUnits;
    const reservedLotIds: string[] = [];
    const issuerBusinessIds = new Set<string>([checkout.businessId]);

    for (const lot of usableLots) {
      if (remaining <= 0) {
        break;
      }

      const reserveMinorUnits = Math.min(
        remaining,
        lot.data.availableMinorUnits,
      );
      const nextAvailable = lot.data.availableMinorUnits - reserveMinorUnits;
      const reservedLotRef = db.collection('walletLots').doc();

      transaction.set(
        lot.ref,
        {
          availableMinorUnits: nextAvailable,
          status: nextAvailable == 0 ? 'shared_checkout_reserved' : 'active',
          lastReservedAt: serverTimestamp(),
          updatedAt: serverTimestamp(),
        },
        { merge: true },
      );
      transaction.set(reservedLotRef, {
        ownerCustomerId: input.customerId,
        sourceCustomerId: input.customerId,
        groupId: checkout.groupId,
        issuerBusinessId: lot.data.issuerBusinessId,
        originalIssueEventId: lot.data.originalIssueEventId,
        initialMinorUnits: reserveMinorUnits,
        availableMinorUnits: reserveMinorUnits,
        parentLotId: lot.id,
        reservedForCheckoutId: input.checkoutId,
        reservedForContributionId: contributionRef.id,
        status: 'shared_checkout_reserved',
        expiresAt: lot.data.expiresAt ?? null,
        createdAt: serverTimestamp(),
        updatedAt: serverTimestamp(),
      });

      reservedLotIds.push(reservedLotRef.id);
      issuerBusinessIds.add(lot.data.issuerBusinessId);
      remaining -= reserveMinorUnits;
    }

    if (remaining > 0) {
      throw new HttpsError(
        'internal',
        'Shared checkout reservation did not cover the requested contribution.',
      );
    }

    transaction.set(contributionRef, {
      checkoutId: input.checkoutId,
      businessId: checkout.businessId,
      groupId: checkout.groupId,
      customerId: input.customerId,
      amountMinorUnits: input.contributionMinorUnits,
      requestId: input.requestId.trim(),
      status: 'reserved',
      reservedLotIds,
      issuerBusinessIds: [...issuerBusinessIds],
      createdByUid: uid,
      createdAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
    });
    transaction.set(contributionEventRef, {
      eventType: 'shared_checkout_contribution',
      groupId: checkout.groupId,
      actorBusinessId: checkout.businessId,
      targetBusinessId: checkout.businessId,
      sourceCustomerId: input.customerId,
      amountMinorUnits: input.contributionMinorUnits,
      checkoutId: input.checkoutId,
      contributionId: contributionRef.id,
      reservedLotIds,
      participantBusinessIds: [...issuerBusinessIds],
      participantCustomerIds: [input.customerId],
      createdAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
    });
    transaction.set(
      checkoutRef,
      {
        contributedMinorUnits: FieldValue.increment(input.contributionMinorUnits),
        remainingMinorUnits: FieldValue.increment(-input.contributionMinorUnits),
        contributionsCount: FieldValue.increment(1),
        participantCustomerIds: FieldValue.arrayUnion(input.customerId),
        participantBusinessIds: FieldValue.arrayUnion(...[...issuerBusinessIds]),
        updatedAt: serverTimestamp(),
      },
      { merge: true },
    );
    transaction.set(
      customerRef,
      {
        updatedAt: serverTimestamp(),
        lastActivityAt: serverTimestamp(),
      },
      { merge: true },
    );

    const result = {
      operationKey,
      checkoutId: input.checkoutId,
      contributionId: contributionRef.id,
      contributedMinorUnits: input.contributionMinorUnits,
      reservedLotCount: reservedLotIds.length,
      remainingMinorUnits:
        checkout.totalMinorUnits -
        (contributedMinorUnits + input.contributionMinorUnits),
      contributionEventId: contributionEventRef.id,
    };

    transaction.set(lockRef, {
      operationType: 'shared_checkout_contribution',
      checkoutId: input.checkoutId,
      customerId: input.customerId,
      requestId: input.requestId.trim(),
      createdAt: serverTimestamp(),
      result,
    });

    return result;
  });

  await safelyRunNotificationTask(
    'shared checkout contribution notification',
    async () => {
      const checkoutSnap = await db.doc(`sharedCheckouts/${input.checkoutId}`).get();
      if (!checkoutSnap.exists) {
        return;
      }

      const checkout = checkoutSnap.data() as {
        businessId?: string | null;
        groupId?: string | null;
      };
      if (typeof checkout.businessId != 'string') {
        return;
      }

      const business = await loadBusinessContext(checkout.businessId);
      await notifyClaimedCustomerSharedCheckoutContributionReserved({
        customerId: input.customerId,
        businessId: checkout.businessId,
        businessName: business.data.name ?? checkout.businessId,
        groupId:
          typeof checkout.groupId == 'string' && checkout.groupId.trim().length > 0
            ? checkout.groupId.trim()
            : null,
        amountMinorUnits: result.contributedMinorUnits,
        checkoutId: input.checkoutId,
        contributionId: result.contributionId,
      });
    },
  );

  return result;
}

export async function finalizeSharedCheckoutFlow(
  operatorUid: string,
  checkoutId: string,
) {
  const operator = await requireOperatorRole(operatorUid, ['owner', 'staff']);
  const now = Timestamp.now();

  const result = await db.runTransaction(async (transaction) => {
    const checkoutRef = db.doc(`sharedCheckouts/${checkoutId}`);
    const checkoutSnap = await transaction.get(checkoutRef);
    if (!checkoutSnap.exists) {
      throw new HttpsError('not-found', 'Shared checkout was not found.');
    }

    const checkout = checkoutSnap.data() as {
      businessId?: string;
      groupId?: string;
      status?: string | null;
      totalMinorUnits?: number;
      sourceTicketRef?: string;
      finalizationResult?: Record<string, unknown>;
    };

    if (typeof checkout.businessId !== 'string') {
      throw new HttpsError(
        'data-loss',
        'Shared checkout is missing the business id.',
      );
    }
    assertOperatorCanAccessBusiness(operator, checkout.businessId);

    if (checkout.status == 'finalized') {
      return (
        checkout.finalizationResult ?? {
          checkoutId,
          status: 'finalized',
        }
      );
    }

    if (
      typeof checkout.groupId !== 'string' ||
      typeof checkout.totalMinorUnits !== 'number' ||
      typeof checkout.sourceTicketRef !== 'string'
    ) {
      throw new HttpsError(
        'data-loss',
        'Shared checkout is missing required group or ticket metadata.',
      );
    }

    const contributionsSnap = await transaction.get(
      checkoutRef.collection('contributions'),
    );
    const contributionSummaries: Array<{
      id: string;
      ref: DocumentReference;
      customerId: string;
      validLots: Array<{
        id: string;
        ref: DocumentReference;
        data: WalletLotRecord;
      }>;
      validMinorUnits: number;
      expiredMinorUnits: number;
    }> = [];
    const participantCustomerIds = new Set<string>();
    const participantBusinessIds = new Set<string>([checkout.businessId]);
    let reconciledContributedMinorUnits = 0;
    let expiredMinorUnits = 0;

    for (const contributionDoc of contributionsSnap.docs) {
      const contribution = contributionDoc.data() as {
        customerId?: string;
        reservedLotIds?: string[];
      };
      if (
        typeof contribution.customerId !== 'string' ||
        !Array.isArray(contribution.reservedLotIds)
      ) {
        throw new HttpsError(
          'data-loss',
          'Shared checkout contribution is missing reserved lot metadata.',
        );
      }

      participantCustomerIds.add(contribution.customerId);
      const validLots: Array<{
        id: string;
        ref: DocumentReference;
        data: WalletLotRecord;
      }> = [];
      let contributionValidMinorUnits = 0;
      let contributionExpiredMinorUnits = 0;

      for (const reservedLotId of contribution.reservedLotIds) {
        const reservedLotRef = db.doc(`walletLots/${reservedLotId}`);
        const reservedLotSnap = await transaction.get(reservedLotRef);
        if (!reservedLotSnap.exists) {
          throw new HttpsError(
            'data-loss',
            'A reserved shared-checkout lot is missing.',
          );
        }

        const reservedLot = reservedLotSnap.data() as WalletLotRecord & {
          reservedForCheckoutId?: string | null;
        };
        if (reservedLot.reservedForCheckoutId != checkoutId) {
          throw new HttpsError(
            'data-loss',
            'Reserved lot does not belong to the requested shared checkout.',
          );
        }

        const expiresAt = reservedLot.expiresAt ?? null;
        const isExpired =
          expiresAt != null && expiresAt.toMillis() <= now.toMillis();
        if (
          reservedLot.status == 'expired' ||
          isExpired ||
          reservedLot.availableMinorUnits <= 0
        ) {
          contributionExpiredMinorUnits += Math.max(
            reservedLot.availableMinorUnits,
            0,
          );
          expiredMinorUnits += Math.max(reservedLot.availableMinorUnits, 0);
          if (reservedLot.status != 'expired') {
            transaction.set(
              reservedLotRef,
              {
                status: 'expired',
                updatedAt: serverTimestamp(),
              },
              { merge: true },
            );
          }
          continue;
        }

        if (reservedLot.status != 'shared_checkout_reserved') {
          throw new HttpsError(
            'failed-precondition',
            'Shared checkout contains a reserved lot in an unexpected state.',
          );
        }

        contributionValidMinorUnits += reservedLot.availableMinorUnits;
        participantBusinessIds.add(reservedLot.issuerBusinessId);
        validLots.push({
          id: reservedLotSnap.id,
          ref: reservedLotRef,
          data: reservedLot,
        });
      }

      reconciledContributedMinorUnits += contributionValidMinorUnits;
      contributionSummaries.push({
        id: contributionDoc.id,
        ref: contributionDoc.ref,
        customerId: contribution.customerId,
        validLots,
        validMinorUnits: contributionValidMinorUnits,
        expiredMinorUnits: contributionExpiredMinorUnits,
      });
    }

    if (reconciledContributedMinorUnits < checkout.totalMinorUnits) {
      for (const contribution of contributionSummaries) {
        transaction.set(
          contribution.ref,
          {
            status:
              contribution.validMinorUnits > 0
                ? 'reserved'
                : contribution.expiredMinorUnits > 0
                  ? 'expired'
                  : 'reserved',
            reservedMinorUnits: contribution.validMinorUnits,
            expiredMinorUnits: contribution.expiredMinorUnits,
            updatedAt: serverTimestamp(),
          },
          { merge: true },
        );
      }

      const result = {
        checkoutId,
        status: 'open_shortfall',
        contributedMinorUnits: reconciledContributedMinorUnits,
        remainingMinorUnits:
          checkout.totalMinorUnits - reconciledContributedMinorUnits,
        expiredMinorUnits,
      };

      transaction.set(
        checkoutRef,
        {
          status: 'open',
          contributedMinorUnits: reconciledContributedMinorUnits,
          remainingMinorUnits:
            checkout.totalMinorUnits - reconciledContributedMinorUnits,
          participantCustomerIds: [...participantCustomerIds],
          participantBusinessIds: [...participantBusinessIds],
          updatedAt: serverTimestamp(),
        },
        { merge: true },
      );

      return result;
    }

    const redemptionBatchId = db.collection('ledgerEvents').doc().id;
    const finalizationEventRef = db.collection('ledgerEvents').doc();
    const redemptionEventIds: string[] = [];

    for (const contribution of contributionSummaries) {
      const contributionRedemptionEventIds: string[] = [];

      for (const reservedLot of contribution.validLots) {
        const redeemEventRef = db.collection('ledgerEvents').doc();
        redemptionEventIds.push(redeemEventRef.id);
        contributionRedemptionEventIds.push(redeemEventRef.id);

        transaction.set(
          reservedLot.ref,
          {
            availableMinorUnits: 0,
            status: 'redeemed',
            lastRedeemedAt: serverTimestamp(),
            updatedAt: serverTimestamp(),
          },
          { merge: true },
        );
        transaction.set(redeemEventRef, {
          eventType: 'redeem',
          groupId: checkout.groupId,
          issuerBusinessId: reservedLot.data.issuerBusinessId,
          actorBusinessId: checkout.businessId,
          targetBusinessId: checkout.businessId,
          operatorUid,
          sourceCustomerId: contribution.customerId,
          amountMinorUnits: reservedLot.data.availableMinorUnits,
          lotId: reservedLot.id,
          originalIssueEventId: reservedLot.data.originalIssueEventId,
          redemptionBatchId,
          sharedCheckoutId: checkoutId,
          contributionId: contribution.id,
          sourceTicketRef: checkout.sourceTicketRef,
          participantBusinessIds: uniqueStrings([
            checkout.businessId,
            reservedLot.data.issuerBusinessId,
          ]),
          participantCustomerIds: [contribution.customerId],
          expiresAt: reservedLot.data.expiresAt ?? null,
          createdAt: serverTimestamp(),
          updatedAt: serverTimestamp(),
        });
      }

      transaction.set(
        contribution.ref,
        {
          status: 'finalized',
          redeemedMinorUnits: contribution.validMinorUnits,
          expiredMinorUnits: contribution.expiredMinorUnits,
          redemptionEventIds: contributionRedemptionEventIds,
          finalizedAt: serverTimestamp(),
          updatedAt: serverTimestamp(),
        },
        { merge: true },
      );
    }

    transaction.set(finalizationEventRef, {
      eventType: 'shared_checkout_finalized',
      groupId: checkout.groupId,
      actorBusinessId: checkout.businessId,
      targetBusinessId: checkout.businessId,
      operatorUid,
      amountMinorUnits: checkout.totalMinorUnits,
      checkoutId,
      redemptionBatchId,
      sourceTicketRef: checkout.sourceTicketRef,
      participantBusinessIds: [...participantBusinessIds],
      participantCustomerIds: [...participantCustomerIds],
      createdAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
    });

    const result = {
      checkoutId,
      status: 'finalized',
      contributedMinorUnits: checkout.totalMinorUnits,
      remainingMinorUnits: 0,
      expiredMinorUnits,
      redemptionBatchId,
      finalizationEventId: finalizationEventRef.id,
      redemptionEventIds,
    };

    transaction.set(
      checkoutRef,
      {
        status: 'finalized',
        contributedMinorUnits: checkout.totalMinorUnits,
        remainingMinorUnits: 0,
        participantCustomerIds: [...participantCustomerIds],
        participantBusinessIds: [...participantBusinessIds],
        redemptionBatchId,
        finalizationEventId: finalizationEventRef.id,
        finalizedByOperatorUid: operatorUid,
        finalizedAt: serverTimestamp(),
        finalizationResult: result,
        updatedAt: serverTimestamp(),
      },
      { merge: true },
    );

    incrementBusinessStats(transaction, checkout.businessId, {
      cashbackRedeemedMinorUnits: checkout.totalMinorUnits,
      cashbackRedeemCount: 1,
    });

    return result;
  });

  await safelyRunNotificationTask(
    'shared checkout finalization notification',
    async () => {
      if (result.status != 'finalized') {
        return;
      }

      const checkoutSnap = await db.doc(`sharedCheckouts/${checkoutId}`).get();
      if (!checkoutSnap.exists) {
        return;
      }

      const checkout = checkoutSnap.data() as {
        businessId?: string | null;
        groupId?: string | null;
      };
      if (typeof checkout.businessId != 'string') {
        return;
      }

      const business = await loadBusinessContext(checkout.businessId);
      await notifyCustomersOfFinalizedSharedCheckout({
        checkoutId,
        businessId: checkout.businessId,
        businessName: business.data.name ?? checkout.businessId,
        groupId:
          typeof checkout.groupId == 'string' && checkout.groupId.trim().length > 0
            ? checkout.groupId.trim()
            : null,
      });
    },
  );

  return result;
}
