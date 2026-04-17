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

export async function issueCashbackFlow(
  operatorUid: string,
  input: IssueCashbackInput,
) {
  const operator = await requireOperatorRole(operatorUid, ['owner', 'staff']);
  assertOperatorCanAccessBusiness(operator, input.businessId);

  const business = await loadBusinessContext(input.businessId);
  ensureBusinessGroupMatch(business.data, input.groupId);

  const phoneE164 = normalizePhoneE164(input.customerPhoneE164);
  const cashbackBasisPoints = readCashbackBasisPoints(
    business.data,
    input.cashbackBasisPoints,
  );
  const cashbackMinorUnits = Math.floor(
    (input.paidMinorUnits * cashbackBasisPoints) / 10000,
  );
  if (cashbackMinorUnits <= 0) {
    throw new HttpsError(
      'failed-precondition',
      'This purchase amount is too small to generate cashback.',
    );
  }

  const operationKey = createOperationKey(
    'issue',
    input.businessId,
    input.sourceTicketRef.trim(),
  );
  const lockRef = db.doc(`operationLocks/${operationKey}`);
  const issueEventRef = db.collection('ledgerEvents').doc();
  const lotRef = db.collection('walletLots').doc();
  const now = new Date();
  const expiresAt = Timestamp.fromDate(
    addDays(now, readCashbackExpiryDays(business.data)),
  );

  const result = await db.runTransaction(async (transaction) => {
    const lockSnap = await transaction.get(lockRef);
    if (lockSnap.exists) {
      return lockSnap.data()?.result;
    }

    const customer = await getOrCreateCustomerIdentity(
      transaction,
      phoneE164,
      'staff_issue',
    );

    await markBusinessCustomerTouch(transaction, {
      businessId: input.businessId,
      customerId: customer.customerId,
      phoneE164,
      activityAt: now,
      source: 'issue',
    });

    if (!customer.indexExists) {
      transaction.set(customer.indexRef, {
        customerId: customer.customerId,
        phoneE164,
        createdAt: serverTimestamp(),
        updatedAt: serverTimestamp(),
      });
    }

    transaction.set(
      customer.customerRef,
      {
        phoneE164,
        displayName: customer.customerData?.displayName ?? null,
        isClaimed: customer.customerData?.isClaimed ?? false,
        claimedByUid: customer.customerData?.claimedByUid ?? null,
        createdFrom: customer.customerData?.createdFrom ?? 'staff_issue',
        createdAt: customer.customerData?.createdAt ?? serverTimestamp(),
        updatedAt: serverTimestamp(),
        lastActivityAt: serverTimestamp(),
      },
      { merge: true },
    );

    transaction.set(issueEventRef, {
      eventType: 'issue',
      groupId: input.groupId,
      issuerBusinessId: input.businessId,
      actorBusinessId: input.businessId,
      operatorUid,
      targetCustomerId: customer.customerId,
      amountMinorUnits: cashbackMinorUnits,
      sourceTicketRef: input.sourceTicketRef.trim(),
      paidMinorUnits: input.paidMinorUnits,
      cashbackBasisPoints,
      customerPhoneE164: phoneE164,
      lotId: lotRef.id,
      originalIssueEventId: issueEventRef.id,
      participantBusinessIds: [input.businessId],
      participantCustomerIds: [customer.customerId],
      expiresAt,
      createdAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
    });

    transaction.set(lotRef, {
      ownerCustomerId: customer.customerId,
      groupId: input.groupId,
      issuerBusinessId: input.businessId,
      issuedByOperatorUid: operatorUid,
      originalIssueEventId: issueEventRef.id,
      initialMinorUnits: cashbackMinorUnits,
      availableMinorUnits: cashbackMinorUnits,
      sourceTicketRef: input.sourceTicketRef.trim(),
      customerPhoneE164: phoneE164,
      status: 'active',
      expiresAt,
      createdAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
    });

    incrementBusinessStats(transaction, input.businessId, {
      totalSalesMinorUnits: input.paidMinorUnits,
      salesCount: 1,
      cashbackIssuedMinorUnits: cashbackMinorUnits,
      cashbackIssueCount: 1,
      scanCount: 1,
      qrScanCount: 1,
    });

    const result = {
      operationKey,
      customerId: customer.customerId,
      createdCustomer: customer.created,
      eventId: issueEventRef.id,
      lotId: lotRef.id,
      issuedMinorUnits: cashbackMinorUnits,
      expiresAtIso: expiresAt.toDate().toISOString(),
      cashbackBasisPoints,
    };

    transaction.set(lockRef, {
      operationType: 'issue',
      businessId: input.businessId,
      sourceTicketRef: input.sourceTicketRef.trim(),
      createdAt: serverTimestamp(),
      result,
    });

    return result;
  });

  await safelyRunNotificationTask('cashback issue notification', async () => {
    await notifyClaimedCustomerCashbackIssued({
      customerId: result.customerId,
      businessId: input.businessId,
      businessName: business.data.name ?? input.businessId,
      groupId: input.groupId,
      amountMinorUnits: result.issuedMinorUnits,
      eventId: result.eventId,
    });
  });

  return result;
}

export async function redeemCashbackFlow(
  operatorUid: string,
  input: RedeemCashbackInput,
) {
  const operator = await requireOperatorRole(operatorUid, ['owner', 'staff']);
  assertOperatorCanAccessBusiness(operator, input.businessId);

  const business = await loadBusinessContext(input.businessId);
  ensureBusinessGroupMatch(business.data, input.groupId);

  const operationKey = createOperationKey(
    'redeem',
    input.businessId,
    input.sourceTicketRef.trim(),
  );
  const lockRef = db.doc(`operationLocks/${operationKey}`);
  const activityAt = new Date();
  const now = Timestamp.now();
  const resolvedCustomerId = await resolveCustomerIdForRedeem(input);

  const result = await db.runTransaction(async (transaction) => {
    const lockSnap = await transaction.get(lockRef);
    if (lockSnap.exists) {
      return lockSnap.data()?.result;
    }

    const customerRef = db.doc(`customers/${resolvedCustomerId}`);
    const customerSnap = await transaction.get(customerRef);
    if (!customerSnap.exists) {
      throw new HttpsError('not-found', 'Customer wallet was not found.');
    }

    const lotsQuery = db
      .collection('walletLots')
      .where('ownerCustomerId', '==', resolvedCustomerId)
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
        if (isExpired && lot.data.availableMinorUnits > 0 && lot.data.status != 'expired') {
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
          lot.data.status != 'shared_checkout_reserved'
        );
      });

    const availableTotal = usableLots.reduce(
      (sum, lot) => sum + lot.data.availableMinorUnits,
      0,
    );
    if (availableTotal < input.redeemMinorUnits) {
      throw new HttpsError(
        'failed-precondition',
        'Customer does not have enough active cashback in this group.',
      );
    }

    const customerData = customerSnap.data() as CustomerRecord | undefined;
    const customerPhoneE164 =
      typeof customerData?.phoneE164 == 'string' &&
        customerData.phoneE164.trim().length > 0
      ? customerData.phoneE164.trim()
      : undefined;
    await markBusinessCustomerTouch(transaction, {
      businessId: input.businessId,
      customerId: resolvedCustomerId,
      phoneE164: customerPhoneE164,
      activityAt,
      source: 'redeem',
    });

    let remaining = input.redeemMinorUnits;
    const redemptionBatchId = db.collection('ledgerEvents').doc().id;
    const consumedLots: Array<{
      lotId: string;
      issuerBusinessId: string;
      amountMinorUnits: number;
      eventId: string;
    }> = [];

    for (const lot of usableLots) {
      if (remaining <= 0) {
        break;
      }

      const consumeMinorUnits = Math.min(remaining, lot.data.availableMinorUnits);
      const nextAvailable = lot.data.availableMinorUnits - consumeMinorUnits;
      const redeemEventRef = db.collection('ledgerEvents').doc();

      transaction.set(
        lot.ref,
        {
          availableMinorUnits: nextAvailable,
          status: nextAvailable == 0 ? 'redeemed' : 'active',
          lastRedeemedAt: serverTimestamp(),
          updatedAt: serverTimestamp(),
        },
        { merge: true },
      );
      transaction.set(redeemEventRef, {
        eventType: 'redeem',
        groupId: input.groupId,
        issuerBusinessId: lot.data.issuerBusinessId,
        actorBusinessId: input.businessId,
        targetBusinessId: input.businessId,
        operatorUid,
        sourceCustomerId: resolvedCustomerId,
        amountMinorUnits: consumeMinorUnits,
        lotId: lot.id,
        originalIssueEventId: lot.data.originalIssueEventId,
        redemptionBatchId,
        sourceTicketRef: input.sourceTicketRef.trim(),
        participantBusinessIds: uniqueStrings([
          input.businessId,
          lot.data.issuerBusinessId,
        ]),
        participantCustomerIds: [resolvedCustomerId],
        expiresAt: lot.data.expiresAt ?? null,
        createdAt: serverTimestamp(),
        updatedAt: serverTimestamp(),
      });

      consumedLots.push({
        lotId: lot.id,
        issuerBusinessId: lot.data.issuerBusinessId,
        amountMinorUnits: consumeMinorUnits,
        eventId: redeemEventRef.id,
      });
      remaining -= consumeMinorUnits;
    }

    transaction.set(
      customerRef,
      {
        updatedAt: serverTimestamp(),
        lastActivityAt: serverTimestamp(),
      },
      { merge: true },
    );

    incrementBusinessStats(transaction, input.businessId, {
      cashbackRedeemedMinorUnits: input.redeemMinorUnits,
      cashbackRedeemCount: 1,
      scanCount: 1,
      qrScanCount: 1,
    });

    const result = {
      operationKey,
      customerId: resolvedCustomerId,
      redeemedMinorUnits: input.redeemMinorUnits,
      redemptionBatchId,
      consumedLots,
    };

    transaction.set(lockRef, {
      operationType: 'redeem',
      businessId: input.businessId,
      sourceTicketRef: input.sourceTicketRef.trim(),
      createdAt: serverTimestamp(),
      result,
    });

    return result;
  });

  await safelyRunNotificationTask('cashback redeem notification', async () => {
    await notifyClaimedCustomerCashbackRedeemed({
      customerId: result.customerId,
      businessId: input.businessId,
      businessName: business.data.name ?? input.businessId,
      groupId: input.groupId,
      amountMinorUnits: result.redeemedMinorUnits,
      redemptionBatchId: result.redemptionBatchId,
    });
  });

  return result;
}

export async function refundCashbackFlow(
  operatorUid: string,
  input: RefundCashbackInput,
) {
  const operator = await requireOperatorRole(operatorUid, ['owner', 'staff']);
  assertOperatorCanAccessBusiness(operator, input.businessId);
  const business = await loadBusinessContext(input.businessId);

  const operationKey = createOperationKey(
    'refund',
    input.businessId,
    input.redemptionBatchId.trim(),
  );
  const lockRef = db.doc(`operationLocks/${operationKey}`);
  const trimmedNote = input.note?.trim() ?? '';
  const now = new Date();

  const result = await db.runTransaction(async (transaction) => {
    const lockSnap = await transaction.get(lockRef);
    if (lockSnap.exists) {
      return lockSnap.data()?.result;
    }

    const redemptionQuery = db
      .collection('ledgerEvents')
      .where('redemptionBatchId', '==', input.redemptionBatchId.trim());
    const redemptionSnapshots = await transaction.get(redemptionQuery);
    const redeemDocs = redemptionSnapshots.docs.filter(
      (doc) => doc.data().eventType == 'redeem',
    );

    if (redeemDocs.length == 0) {
      throw new HttpsError(
        'not-found',
        'No redeem events were found for this redemption batch.',
      );
    }

    const refundBatchId = db.collection('ledgerEvents').doc().id;
    const refundEventIds: string[] = [];
    const refundLotIds: string[] = [];
    const refundedCustomerIds = new Set<string>();
    let refundedMinorUnits = 0;

    for (const redeemDoc of redeemDocs) {
      const redeemEvent = redeemDoc.data() as {
        actorBusinessId?: string;
        groupId?: string;
        issuerBusinessId?: string;
        sourceCustomerId?: string;
        amountMinorUnits?: number;
        originalIssueEventId?: string;
        expiresAt?: Timestamp | null;
        refundBatchId?: string | null;
      };

      if (redeemEvent.actorBusinessId != input.businessId) {
        throw new HttpsError(
          'permission-denied',
          'This redemption batch belongs to a different business.',
        );
      }

      if (redeemEvent.refundBatchId != null) {
        throw new HttpsError(
          'failed-precondition',
          'This redemption batch has already been refunded.',
        );
      }

      if (
        typeof redeemEvent.groupId !== 'string' ||
        typeof redeemEvent.issuerBusinessId !== 'string' ||
        typeof redeemEvent.sourceCustomerId !== 'string' ||
        typeof redeemEvent.amountMinorUnits !== 'number'
      ) {
        throw new HttpsError(
          'data-loss',
          'Redeem event is missing refund metadata.',
        );
      }

      const refundLotRef = db.collection('walletLots').doc();
      const refundEventRef = db.collection('ledgerEvents').doc();
      const refundExpiresAt = resolveRefundExpiryTimestamp(
        redeemEvent.expiresAt ?? null,
        now,
      );

      transaction.set(refundLotRef, {
        ownerCustomerId: redeemEvent.sourceCustomerId,
        groupId: redeemEvent.groupId,
        issuerBusinessId: redeemEvent.issuerBusinessId,
        issuedByOperatorUid: operatorUid,
        originalIssueEventId:
          redeemEvent.originalIssueEventId ?? refundEventRef.id,
        initialMinorUnits: redeemEvent.amountMinorUnits,
        availableMinorUnits: redeemEvent.amountMinorUnits,
        parentRedeemEventId: redeemDoc.id,
        refundedFromRedemptionBatchId: input.redemptionBatchId.trim(),
        refundBatchId,
        status: 'active',
        expiresAt: refundExpiresAt,
        createdAt: serverTimestamp(),
        updatedAt: serverTimestamp(),
      });
      transaction.set(refundEventRef, {
        eventType: 'refund',
        groupId: redeemEvent.groupId,
        issuerBusinessId: redeemEvent.issuerBusinessId,
        actorBusinessId: input.businessId,
        targetBusinessId: input.businessId,
        operatorUid,
        sourceCustomerId: redeemEvent.sourceCustomerId,
        targetCustomerId: redeemEvent.sourceCustomerId,
        amountMinorUnits: redeemEvent.amountMinorUnits,
        refundBatchId,
        refundedRedemptionBatchId: input.redemptionBatchId.trim(),
        refundedRedeemEventId: redeemDoc.id,
        refundLotId: refundLotRef.id,
        refundReason: trimmedNote.length > 0 ? trimmedNote : null,
        participantBusinessIds: uniqueStrings([
          input.businessId,
          redeemEvent.issuerBusinessId,
        ]),
        participantCustomerIds: [redeemEvent.sourceCustomerId],
        expiresAt: refundExpiresAt,
        createdAt: serverTimestamp(),
        updatedAt: serverTimestamp(),
      });
      transaction.set(
        redeemDoc.ref,
        {
          refundBatchId,
          refundEventId: refundEventRef.id,
          refundLotId: refundLotRef.id,
          refundReason: trimmedNote.length > 0 ? trimmedNote : null,
          refundedAt: serverTimestamp(),
          updatedAt: serverTimestamp(),
        },
        { merge: true },
      );
      transaction.set(
        db.doc(`customers/${redeemEvent.sourceCustomerId}`),
        {
          updatedAt: serverTimestamp(),
          lastActivityAt: serverTimestamp(),
        },
        { merge: true },
      );

      refundEventIds.push(refundEventRef.id);
      refundLotIds.push(refundLotRef.id);
      refundedCustomerIds.add(redeemEvent.sourceCustomerId);
      refundedMinorUnits += redeemEvent.amountMinorUnits;
    }

    incrementBusinessStats(transaction, input.businessId, {
      cashbackRefundedMinorUnits: refundedMinorUnits,
      cashbackRefundCount: 1,
    });

    const result = {
      operationKey,
      businessId: input.businessId,
      redemptionBatchId: input.redemptionBatchId.trim(),
      refundBatchId,
      refundedMinorUnits,
      refundedLotCount: refundLotIds.length,
      refundedCustomerIds: [...refundedCustomerIds],
      refundEventIds,
      refundLotIds,
    };

    transaction.set(lockRef, {
      operationType: 'refund',
      businessId: input.businessId,
      redemptionBatchId: input.redemptionBatchId.trim(),
      createdAt: serverTimestamp(),
      result,
    });

    return result;
  });

  await safelyRunNotificationTask('cashback refund notification', async () => {
    await notifyRefundBatchCustomers({
      refundBatchId: result.refundBatchId,
      businessId: input.businessId,
      businessName: business.data.name ?? input.businessId,
    });
  });

  return result;
}

export async function adminAdjustCashbackFlow(
  ownerUid: string,
  input: AdminAdjustCashbackInput,
) {
  const owner = await requireOperatorRole(ownerUid, ['owner']);
  assertOperatorCanAccessBusiness(owner, input.businessId);

  const business = await loadBusinessContext(input.businessId);
  ensureBusinessGroupMatch(business.data, input.groupId);

  const operationKey = createOperationKey(
    'admin_adjustment',
    input.businessId,
    input.requestId.trim(),
  );
  const lockRef = db.doc(`operationLocks/${operationKey}`);
  const trimmedNote = input.note.trim();
  const adjustedMinorUnits = Math.abs(input.amountMinorUnits);
  const direction = input.amountMinorUnits > 0 ? 'credit' : 'debit';

  const result = await db.runTransaction(async (transaction) => {
    const lockSnap = await transaction.get(lockRef);
    if (lockSnap.exists) {
      return lockSnap.data()?.result;
    }

    const customer = await resolveCustomerIdentityForAdminAdjustment(
      transaction,
      input,
      direction == 'credit',
    );

    if (
      customer.phoneE164 != null &&
      (customer.created || !customer.existedBefore)
    ) {
      transaction.set(
        customer.customerRef,
        {
          phoneE164: customer.phoneE164,
          displayName: customer.customerData?.displayName ?? null,
          isClaimed: customer.customerData?.isClaimed ?? false,
          claimedByUid: customer.customerData?.claimedByUid ?? null,
          createdFrom: customer.customerData?.createdFrom ?? 'admin_adjustment',
          createdAt: customer.customerData?.createdAt ?? serverTimestamp(),
          updatedAt: serverTimestamp(),
          lastActivityAt: serverTimestamp(),
        },
        { merge: true },
      );
    }

    const adjustmentBatchId = db.collection('ledgerEvents').doc().id;
    const adjustmentEventIds: string[] = [];
    const createdLotIds: string[] = [];
    const consumedLots: Array<{
      lotId: string;
      issuerBusinessId: string;
      amountMinorUnits: number;
      eventId: string;
    }> = [];

    if (direction == 'credit') {
      const adjustmentEventRef = db.collection('ledgerEvents').doc();
      const adjustmentLotRef = db.collection('walletLots').doc();
      const expiresAt = Timestamp.fromDate(
        addDays(new Date(), readCashbackExpiryDays(business.data)),
      );

      transaction.set(adjustmentEventRef, {
        eventType: 'admin_adjustment',
        adjustmentDirection: 'credit',
        adjustmentBatchId,
        groupId: input.groupId,
        issuerBusinessId: input.businessId,
        actorBusinessId: input.businessId,
        targetBusinessId: input.businessId,
        operatorUid: ownerUid,
        sourceCustomerId: customer.customerId,
        targetCustomerId: customer.customerId,
        amountMinorUnits: adjustedMinorUnits,
        lotId: adjustmentLotRef.id,
        originalIssueEventId: adjustmentEventRef.id,
        adjustmentNote: trimmedNote,
        participantBusinessIds: [input.businessId],
        participantCustomerIds: [customer.customerId],
        expiresAt,
        createdAt: serverTimestamp(),
        updatedAt: serverTimestamp(),
      });
      transaction.set(adjustmentLotRef, {
        ownerCustomerId: customer.customerId,
        groupId: input.groupId,
        issuerBusinessId: input.businessId,
        issuedByOperatorUid: ownerUid,
        originalIssueEventId: adjustmentEventRef.id,
        initialMinorUnits: adjustedMinorUnits,
        availableMinorUnits: adjustedMinorUnits,
        adjustmentBatchId,
        adjustmentNote: trimmedNote,
        status: 'active',
        expiresAt,
        createdAt: serverTimestamp(),
        updatedAt: serverTimestamp(),
      });
      transaction.set(
        customer.customerRef,
        {
          updatedAt: serverTimestamp(),
          lastActivityAt: serverTimestamp(),
        },
        { merge: true },
      );

      adjustmentEventIds.push(adjustmentEventRef.id);
      createdLotIds.push(adjustmentLotRef.id);
    } else {
      const lotsQuery = db
        .collection('walletLots')
        .where('ownerCustomerId', '==', customer.customerId)
        .where('groupId', '==', input.groupId)
        .orderBy('expiresAt', 'asc');

      const lotSnapshots = await transaction.get(lotsQuery);
      const now = Timestamp.now();
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
      if (availableTotal < adjustedMinorUnits) {
        throw new HttpsError(
          'failed-precondition',
          'The customer does not have enough active cashback in this tandem group for a debit adjustment.',
        );
      }

      let remaining = adjustedMinorUnits;
      for (const lot of usableLots) {
        if (remaining <= 0) {
          break;
        }

        const consumeMinorUnits = Math.min(
          remaining,
          lot.data.availableMinorUnits,
        );
        const nextAvailable = lot.data.availableMinorUnits - consumeMinorUnits;
        const adjustmentEventRef = db.collection('ledgerEvents').doc();

        transaction.set(
          lot.ref,
          {
            availableMinorUnits: nextAvailable,
            status: nextAvailable == 0 ? 'redeemed' : 'active',
            lastAdminAdjustedAt: serverTimestamp(),
            updatedAt: serverTimestamp(),
          },
          { merge: true },
        );
        transaction.set(adjustmentEventRef, {
          eventType: 'admin_adjustment',
          adjustmentDirection: 'debit',
          adjustmentBatchId,
          groupId: input.groupId,
          issuerBusinessId: lot.data.issuerBusinessId,
          actorBusinessId: input.businessId,
          targetBusinessId: input.businessId,
          operatorUid: ownerUid,
          sourceCustomerId: customer.customerId,
          targetCustomerId: customer.customerId,
          amountMinorUnits: consumeMinorUnits,
          lotId: lot.id,
          originalIssueEventId: lot.data.originalIssueEventId,
          adjustmentNote: trimmedNote,
          participantBusinessIds: uniqueStrings([
            input.businessId,
            lot.data.issuerBusinessId,
          ]),
          participantCustomerIds: [customer.customerId],
          expiresAt: lot.data.expiresAt ?? null,
          createdAt: serverTimestamp(),
          updatedAt: serverTimestamp(),
        });

        adjustmentEventIds.push(adjustmentEventRef.id);
        consumedLots.push({
          lotId: lot.id,
          issuerBusinessId: lot.data.issuerBusinessId,
          amountMinorUnits: consumeMinorUnits,
          eventId: adjustmentEventRef.id,
        });
        remaining -= consumeMinorUnits;
      }

      transaction.set(
        customer.customerRef,
        {
          updatedAt: serverTimestamp(),
          lastActivityAt: serverTimestamp(),
        },
        { merge: true },
      );
    }

    const result = {
      operationKey,
      businessId: input.businessId,
      customerId: customer.customerId,
      groupId: input.groupId,
      adjustmentBatchId,
      direction,
      adjustedMinorUnits,
      note: trimmedNote,
      adjustmentEventIds,
      createdLotIds,
      consumedLots,
    };

    transaction.set(lockRef, {
      operationType: 'admin_adjustment',
      businessId: input.businessId,
      customerId: customer.customerId,
      requestId: input.requestId.trim(),
      createdAt: serverTimestamp(),
      result,
    });

    return result;
  });

  await safelyRunNotificationTask('admin adjustment notification', async () => {
    await notifyClaimedCustomerAdminAdjustment({
      customerId: result.customerId,
      businessId: input.businessId,
      businessName: business.data.name ?? input.businessId,
      groupId: result.groupId,
      amountMinorUnits: result.adjustedMinorUnits,
      direction: result.direction,
      adjustmentBatchId: result.adjustmentBatchId,
      note: result.note,
    });
  });

  return result;
}

export async function expireWalletLotsFlow(
  ownerUid: string,
  input: ExpireWalletLotsInput,
) {
  const owner = await requireOperatorRole(ownerUid, ['owner']);
  assertOperatorCanAccessBusiness(owner, input.businessId);

  const business = await loadBusinessContext(input.businessId);
  ensureBusinessGroupMatch(business.data, input.groupId);

  return sweepExpiredActiveWalletLotsBatchFlow({
    businessId: input.businessId,
    operatorUid: ownerUid,
    groupId: input.groupId,
    limit: normalizeExpirySweepLimit(input.maxLots),
    trigger: 'manual_sweep',
  });
}

export async function sweepExpiredActiveWalletLotsBatchFlow({
  businessId,
  operatorUid,
  groupId,
  limit,
  trigger,
}: {
  businessId?: string;
  operatorUid?: string;
  groupId?: string;
  limit?: number;
  trigger: 'manual_sweep' | 'scheduled_sweep';
}) {
  const normalizedLimit = normalizeExpirySweepLimit(limit);
  const now = Timestamp.now();
  const baseQuery = db
    .collection('walletLots')
    .where('status', '==', 'active')
    .where('expiresAt', '<=', now);
  const query =
    groupId == null || groupId.trim().length == 0
      ? baseQuery.orderBy('expiresAt', 'asc').limit(normalizedLimit)
      : baseQuery
          .where('groupId', '==', groupId.trim())
          .orderBy('expiresAt', 'asc')
          .limit(normalizedLimit);
  const snapshot = await query.get();

  const expiredLots: ExpireLotResult[] = [];
  for (const lotDoc of snapshot.docs) {
    const expired = await expireActiveWalletLotDocument({
      lotRef: lotDoc.ref,
      actorBusinessId: businessId,
      operatorUid,
      trigger,
    });
    if (expired != null) {
      expiredLots.push(expired);
    }
  }

  await safelyRunNotificationTask('cashback expiry notification', async () => {
    await notifyCustomersOfExpiredLots({
      expiredLots,
      trigger,
    });
  });

  return {
    businessId: businessId ?? null,
    groupId: groupId?.trim() ?? null,
    scannedLotCount: snapshot.docs.length,
    expiredLotCount: expiredLots.length,
    expiredMinorUnits: expiredLots.reduce(
      (sum, lot) => sum + lot.amountMinorUnits,
      0,
    ),
    expiredLotIds: expiredLots.map((lot) => lot.lotId),
    expireEventIds: expiredLots.map((lot) => lot.eventId),
    trigger,
  };
}
