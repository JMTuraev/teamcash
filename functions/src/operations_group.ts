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

export async function claimCustomerWalletByPhoneFlow(
  uid: string,
  phoneNumber: unknown,
) {
  if (typeof phoneNumber != 'string' || phoneNumber.trim().length === 0) {
    throw new HttpsError(
      'failed-precondition',
      'Verified phone auth is required before claiming the wallet.',
    );
  }

  const phoneE164 = normalizePhoneE164(phoneNumber);

  return db.runTransaction(async (transaction) => {
    const existingLinkRef = db.doc(`customerAuthLinks/${uid}`);
    const existingLinkSnap = await transaction.get(existingLinkRef);
    if (existingLinkSnap.exists) {
      const existingLink = existingLinkSnap.data() as {
        customerId: string;
        phoneE164: string;
      };

      if (existingLink.phoneE164 != phoneE164) {
        throw new HttpsError(
          'failed-precondition',
          'This auth user is already linked to a different phone-backed customer.',
        );
      }

      return {
        customerId: existingLink.customerId,
        phoneE164,
        createdCustomer: false,
        claimed: true,
      };
    }

    const customerIdentity = await getOrCreateCustomerIdentity(
      transaction,
      phoneE164,
      'self_claim',
    );

    const existingCustomer = customerIdentity.customerData;
    if (
      existingCustomer?.claimedByUid != null &&
      existingCustomer.claimedByUid != uid
    ) {
      throw new HttpsError(
        'already-exists',
        'This phone-backed wallet has already been claimed by another account.',
      );
    }

    if (!customerIdentity.indexExists) {
      transaction.set(customerIdentity.indexRef, {
        customerId: customerIdentity.customerId,
        phoneE164,
        createdAt: serverTimestamp(),
        updatedAt: serverTimestamp(),
      });
    }

    transaction.set(
      customerIdentity.customerRef,
      {
        phoneE164,
        displayName: existingCustomer?.displayName ?? null,
        isClaimed: true,
        claimedByUid: uid,
        claimedAt: serverTimestamp(),
        createdFrom: existingCustomer?.createdFrom ?? 'self_claim',
        createdAt: existingCustomer?.createdAt ?? serverTimestamp(),
        updatedAt: serverTimestamp(),
      },
      { merge: true },
    );
    transaction.set(existingLinkRef, {
      customerId: customerIdentity.customerId,
      phoneE164,
      linkedAt: serverTimestamp(),
      verifiedAt: serverTimestamp(),
    });

    return {
      customerId: customerIdentity.customerId,
      phoneE164,
      createdCustomer: customerIdentity.created,
      claimed: true,
    };
  });
}


export async function createGroupFlow(ownerUid: string, input: CreateGroupInput) {
  const owner = await requireOperatorRole(ownerUid, ['owner']);
  assertOperatorCanAccessBusiness(owner, input.businessId);

  const businessRef = db.doc(`businesses/${input.businessId}`);
  const groupRef = db.collection('groups').doc();
  const memberRef = groupRef.collection('members').doc(input.businessId);
  const historyRef = groupRef.collection('history').doc();
  const trimmedName = input.name.trim();

  return db.runTransaction(async (transaction) => {
    const businessSnap = await transaction.get(businessRef);
    if (!businessSnap.exists) {
      throw new HttpsError(
        'failed-precondition',
        'Business must exist before it can create a tandem group.',
      );
    }

    const business = businessSnap.data() as BusinessRecord;
    const existingGroupId = business.groupId;
    const membershipStatus =
      business.groupMembershipStatus ?? business.tandemStatus ?? null;

    if (
      existingGroupId != null &&
      existingGroupId.length > 0 &&
      membershipStatus == 'active'
    ) {
      throw new HttpsError(
        'failed-precondition',
        'This business is already active in a tandem group.',
      );
    }

    if (membershipStatus == 'pending') {
      throw new HttpsError(
        'failed-precondition',
        'This business already has a pending tandem membership request.',
      );
    }

    transaction.set(groupRef, {
      name: trimmedName,
      status: 'active',
      createdByOwnerUid: ownerUid,
      createdByBusinessId: input.businessId,
      activeBusinessIds: [input.businessId],
      pendingBusinessIds: [],
      createdAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
    });
    transaction.set(memberRef, {
      businessId: input.businessId,
      status: 'active',
      addedAt: serverTimestamp(),
      joinedAt: serverTimestamp(),
      joinedByRequestId: null,
      updatedAt: serverTimestamp(),
    });
    transaction.set(
      businessRef,
      {
        groupId: groupRef.id,
        groupName: trimmedName,
        groupMembershipStatus: 'active',
        tandemStatus: 'active',
        pendingJoinRequestId: null,
        pendingGroupId: null,
        updatedAt: serverTimestamp(),
      },
      { merge: true },
    );
    transaction.set(historyRef, {
      eventType: 'group_created',
      groupId: groupRef.id,
      businessId: input.businessId,
      actorOwnerUid: ownerUid,
      actorBusinessId: input.businessId,
      createdAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
    });

    return {
      groupId: groupRef.id,
      businessId: input.businessId,
      groupName: trimmedName,
      status: 'active',
    };
  });
}

export async function requestGroupJoinFlow(
  ownerUid: string,
  input: GroupJoinRequestInput,
) {
  const owner = await requireOperatorRole(ownerUid, ['owner']);
  assertOperatorCanAccessBusiness(owner, input.businessId);

  const groupRef = db.doc(`groups/${input.groupId}`);
  const businessRef = db.doc(`businesses/${input.businessId}`);

  const result = await db.runTransaction(async (transaction) => {
    const [groupSnap, businessSnap] = await Promise.all([
      transaction.get(groupRef),
      transaction.get(businessRef),
    ]);

    if (!groupSnap.exists) {
      throw new HttpsError('not-found', 'Tandem group was not found.');
    }
    if (!businessSnap.exists) {
      throw new HttpsError('not-found', 'Business was not found.');
    }

    const group = groupSnap.data() as {
      name?: string | null;
      status?: string | null;
      activeBusinessIds?: string[];
      pendingBusinessIds?: string[];
    };
    const business = businessSnap.data() as BusinessRecord & {
      groupName?: string | null;
      pendingJoinRequestId?: string | null;
    };
    const activeBusinessIds = uniqueStrings(group.activeBusinessIds ?? []);

    if ((group.status ?? 'active') != 'active') {
      throw new HttpsError(
        'failed-precondition',
        'Only active tandem groups can accept new join requests.',
      );
    }
    if (activeBusinessIds.length == 0) {
      throw new HttpsError(
        'failed-precondition',
        'A tandem group must have at least one active business before others can join.',
      );
    }
    if (activeBusinessIds.includes(input.businessId)) {
      throw new HttpsError(
        'failed-precondition',
        'This business is already an active member of the tandem group.',
      );
    }

    const membershipStatus =
      business.groupMembershipStatus ?? business.tandemStatus ?? null;
    if (
      membershipStatus == 'active' &&
      business.groupId != null &&
      business.groupId.length > 0
    ) {
      throw new HttpsError(
        'failed-precondition',
        'This business is already active in another tandem group.',
      );
    }

    if (
      membershipStatus == 'pending' &&
      business.pendingJoinRequestId != null &&
      business.pendingJoinRequestId.length > 0
    ) {
      const existingRequestRef = groupRef
          .collection('joinRequests')
          .doc(business.pendingJoinRequestId);
      const existingRequestSnap = await transaction.get(existingRequestRef);
      if (
        existingRequestSnap.exists &&
        (existingRequestSnap.data()?.status as string | undefined) == 'pending'
      ) {
        return {
          requestId: existingRequestRef.id,
          groupId: input.groupId,
          businessId: input.businessId,
          approvalsReceived:
            readIntValue(existingRequestSnap.data(), 'approvalsReceived') ??
            readStringList(existingRequestSnap.data(), 'approvedByBusinessIds')
                .length,
          approvalsRequired:
            readIntValue(existingRequestSnap.data(), 'approvalsRequired') ??
            activeBusinessIds.length,
          status: 'pending',
          reusedExisting: true,
        };
      }

      throw new HttpsError(
        'failed-precondition',
        'This business already has a pending tandem membership request.',
      );
    }

    const requestRef = groupRef.collection('joinRequests').doc();
    const historyRef = groupRef.collection('history').doc();
    const groupName =
      typeof group.name == 'string' && group.name.trim().length > 0
          ? group.name.trim()
          : input.groupId;

    transaction.set(requestRef, {
      businessId: input.businessId,
      targetBusinessId: input.businessId,
      groupId: input.groupId,
      groupName,
      status: 'pending',
      approvalsReceived: 0,
      approvalsRequired: activeBusinessIds.length,
      approvedByBusinessIds: [],
      requestedByOwnerUid: ownerUid,
      requestedAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
    });
    transaction.set(
      businessRef,
      {
        groupId: input.groupId,
        groupName,
        groupMembershipStatus: 'pending',
        tandemStatus: 'pending',
        pendingJoinRequestId: requestRef.id,
        pendingGroupId: input.groupId,
        updatedAt: serverTimestamp(),
      },
      { merge: true },
    );
    transaction.set(
      groupRef,
      {
        pendingBusinessIds: FieldValue.arrayUnion(input.businessId),
        updatedAt: serverTimestamp(),
      },
      { merge: true },
    );
    transaction.set(historyRef, {
      eventType: 'join_request_created',
      groupId: input.groupId,
      businessId: input.businessId,
      actorOwnerUid: ownerUid,
      actorBusinessId: input.businessId,
      requestId: requestRef.id,
      createdAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
    });

    return {
      requestId: requestRef.id,
      groupId: input.groupId,
      businessId: input.businessId,
      approvalsReceived: 0,
      approvalsRequired: activeBusinessIds.length,
      status: 'pending',
      reusedExisting: false,
    };
  });

  await safelyRunNotificationTask('group join request notification', async () => {
    const [groupSnap, businessSnap] = await Promise.all([
      groupRef.get(),
      businessRef.get(),
    ]);
    if (!groupSnap.exists || !businessSnap.exists) {
      return;
    }

    const group = groupSnap.data() as {
      name?: string | null;
      activeBusinessIds?: string[];
    };
    const business = businessSnap.data() as BusinessRecord;

    await notifyOwnersOfGroupJoinRequest({
      requestId:
        typeof result.requestId == 'string' ? result.requestId : input.businessId,
      groupId: input.groupId,
      groupName:
        typeof group.name == 'string' && group.name.trim().length > 0
            ? group.name.trim()
            : input.groupId,
      targetBusinessId: input.businessId,
      targetBusinessName: business.name ?? input.businessId,
      activeBusinessIds: uniqueStrings(group.activeBusinessIds ?? []),
    });
  });

  return result;
}

export async function voteOnGroupJoinFlow(
  ownerUid: string,
  input: GroupJoinVoteInput,
) {
  const owner = await requireOperatorRole(ownerUid, ['owner']);
  const requestRef = await resolveJoinRequestReference(input.requestId);

  const result = await db.runTransaction(async (transaction) => {
    const requestSnap = await transaction.get(requestRef);
    if (!requestSnap.exists) {
      throw new HttpsError('not-found', 'Join request was not found.');
    }

    const groupRef = requestRef.parent.parent;
    if (groupRef == null) {
      throw new HttpsError(
        'data-loss',
        'Join request is missing the parent tandem group.',
      );
    }

    const groupSnap = await transaction.get(groupRef);
    if (!groupSnap.exists) {
      throw new HttpsError('not-found', 'Parent tandem group was not found.');
    }

    const request = requestSnap.data() as {
      businessId?: string | null;
      targetBusinessId?: string | null;
      status?: string | null;
      approvalsRequired?: number;
      approvedByBusinessIds?: string[];
    };
    const group = groupSnap.data() as {
      name?: string | null;
      activeBusinessIds?: string[];
      pendingBusinessIds?: string[];
    };

    const targetBusinessId =
      typeof request.targetBusinessId == 'string' &&
          request.targetBusinessId.trim().length > 0
      ? request.targetBusinessId.trim()
      : typeof request.businessId == 'string'
      ? request.businessId.trim()
      : undefined;
    if (targetBusinessId == null || targetBusinessId.length == 0) {
      throw new HttpsError(
        'data-loss',
        'Join request is missing the target business id.',
      );
    }

    const activeBusinessIds = uniqueStrings(group.activeBusinessIds ?? []);
    if (activeBusinessIds.length == 0) {
      throw new HttpsError(
        'failed-precondition',
        'The tandem group does not have any active member businesses that can vote.',
      );
    }

    const voterBusinessId = resolveVoterBusinessId({
      ownerBusinessIds: owner.data.businessIds ?? [],
      activeBusinessIds: activeBusinessIds,
      requestedBusinessId: input.voterBusinessId,
    });

    if (voterBusinessId == targetBusinessId) {
      throw new HttpsError(
        'failed-precondition',
        'The requesting business cannot vote on its own join request.',
      );
    }

    const approvedByBusinessIds = new Set(
      readStringList(requestSnap.data(), 'approvedByBusinessIds'),
    );
    const voteRef = requestRef.collection('votes').doc(voterBusinessId);
    const voteSnap = await transaction.get(voteRef);
    const existingVote = voteSnap.data()?.vote as string | undefined;
    const approvalsReceivedBaseline = Math.max(
      readIntValue(requestSnap.data(), 'approvalsReceived') ?? 0,
      approvedByBusinessIds.size,
    );

    if (voteSnap.exists && existingVote == input.vote) {
      return {
        requestId: requestRef.id,
        groupId: groupRef.id,
        voterBusinessId,
        approvalsReceived: approvalsReceivedBaseline,
        approvalsRequired:
          readIntValue(requestSnap.data(), 'approvalsRequired') ??
          activeBusinessIds.length,
        status: (request.status ?? 'pending'),
        resolved: (request.status ?? 'pending') != 'pending',
      };
    }

    if (voteSnap.exists && existingVote != null && existingVote != input.vote) {
      throw new HttpsError(
        'already-exists',
        'This business has already voted on the join request.',
      );
    }

    if ((request.status ?? 'pending') != 'pending') {
      throw new HttpsError(
        'failed-precondition',
        'This join request has already been resolved.',
      );
    }

    const approvalsRequired =
      typeof request.approvalsRequired == 'number' &&
          request.approvalsRequired > 0
      ? request.approvalsRequired
      : activeBusinessIds.length;
    const targetBusinessRef = db.doc(`businesses/${targetBusinessId}`);
    const historyRef = groupRef.collection('history').doc();
    const groupName =
      typeof group.name == 'string' && group.name.trim().length > 0
          ? group.name.trim()
          : groupRef.id;

    transaction.set(voteRef, {
      businessId: voterBusinessId,
      vote: input.vote,
      votedByUid: ownerUid,
      votedAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
    });

    if (input.vote == 'no') {
      transaction.set(
        requestRef,
        {
          status: 'rejected',
          rejectedByBusinessId: voterBusinessId,
          rejectedByUid: ownerUid,
          approvalsReceived: approvalsReceivedBaseline,
          approvalsRequired,
          decidedAt: serverTimestamp(),
          updatedAt: serverTimestamp(),
        },
        { merge: true },
      );
      transaction.set(
        targetBusinessRef,
        {
          groupId: groupRef.id,
          groupName,
          groupMembershipStatus: 'rejected',
          tandemStatus: 'rejected',
          pendingJoinRequestId: null,
          pendingGroupId: null,
          updatedAt: serverTimestamp(),
        },
        { merge: true },
      );
      transaction.set(
        groupRef,
        {
          pendingBusinessIds: FieldValue.arrayRemove(targetBusinessId),
          updatedAt: serverTimestamp(),
        },
        { merge: true },
      );
      transaction.set(historyRef, {
        eventType: 'join_request_rejected',
        requestId: requestRef.id,
        groupId: groupRef.id,
        businessId: targetBusinessId,
        actorOwnerUid: ownerUid,
        actorBusinessId: voterBusinessId,
        createdAt: serverTimestamp(),
        updatedAt: serverTimestamp(),
      });

      return {
        requestId: requestRef.id,
        groupId: groupRef.id,
        voterBusinessId,
        approvalsReceived: approvalsReceivedBaseline,
        approvalsRequired,
        status: 'rejected',
        resolved: true,
      };
    }

    approvedByBusinessIds.add(voterBusinessId);
    const approvalsReceived = approvalsReceivedBaseline + 1;
    const approved = approvalsReceived >= approvalsRequired;

    transaction.set(
      requestRef,
      {
        approvedByBusinessIds: [...approvedByBusinessIds],
        approvalsReceived,
        approvalsRequired,
        status: approved ? 'approved' : 'pending',
        decidedAt: approved ? serverTimestamp() : null,
        updatedAt: serverTimestamp(),
      },
      { merge: true },
    );

    if (approved) {
      const memberRef = groupRef.collection('members').doc(targetBusinessId);
      transaction.set(
        targetBusinessRef,
        {
          groupId: groupRef.id,
          groupName,
          groupMembershipStatus: 'active',
          tandemStatus: 'active',
          pendingJoinRequestId: null,
          pendingGroupId: null,
          updatedAt: serverTimestamp(),
        },
        { merge: true },
      );
      transaction.set(memberRef, {
        businessId: targetBusinessId,
        status: 'active',
        addedAt: serverTimestamp(),
        joinedAt: serverTimestamp(),
        joinedByRequestId: requestRef.id,
        updatedAt: serverTimestamp(),
      });
      transaction.set(
        groupRef,
        {
          activeBusinessIds: FieldValue.arrayUnion(targetBusinessId),
          pendingBusinessIds: FieldValue.arrayRemove(targetBusinessId),
          updatedAt: serverTimestamp(),
        },
        { merge: true },
      );
      transaction.set(historyRef, {
        eventType: 'join_request_approved',
        requestId: requestRef.id,
        groupId: groupRef.id,
        businessId: targetBusinessId,
        actorOwnerUid: ownerUid,
        actorBusinessId: voterBusinessId,
        createdAt: serverTimestamp(),
        updatedAt: serverTimestamp(),
      });
    } else {
      transaction.set(historyRef, {
        eventType: 'join_request_vote_yes',
        requestId: requestRef.id,
        groupId: groupRef.id,
        businessId: targetBusinessId,
        actorOwnerUid: ownerUid,
        actorBusinessId: voterBusinessId,
        createdAt: serverTimestamp(),
        updatedAt: serverTimestamp(),
      });
    }

    return {
      requestId: requestRef.id,
      groupId: groupRef.id,
      voterBusinessId,
      approvalsReceived,
      approvalsRequired,
      status: approved ? 'approved' : 'pending',
      resolved: approved,
    };
  });

  await safelyRunNotificationTask('group join vote notification', async () => {
    const groupRef = requestRef.parent.parent;
    if (groupRef == null) {
      return;
    }

    const [requestSnap, groupSnap] = await Promise.all([
      requestRef.get(),
      groupRef.get(),
    ]);
    if (!requestSnap.exists || !groupSnap.exists) {
      return;
    }

    const request = requestSnap.data() as {
      businessId?: string | null;
      targetBusinessId?: string | null;
      status?: string | null;
      approvalsReceived?: number;
      approvalsRequired?: number;
    };
    const group = groupSnap.data() as {
      name?: string | null;
    };
    const targetBusinessId =
      typeof request.targetBusinessId == 'string' &&
          request.targetBusinessId.trim().length > 0
      ? request.targetBusinessId.trim()
      : typeof request.businessId == 'string'
      ? request.businessId.trim()
      : '';
    if (targetBusinessId.length == 0) {
      return;
    }

    const targetBusinessSnap = await db.doc(`businesses/${targetBusinessId}`).get();
    const targetBusiness = targetBusinessSnap.exists
      ? (targetBusinessSnap.data() as BusinessRecord)
      : undefined;

    await notifyTargetOwnersOfGroupJoinVote({
      requestId: requestRef.id,
      groupId: groupRef.id,
      groupName:
        typeof group.name == 'string' && group.name.trim().length > 0
            ? group.name.trim()
            : groupRef.id,
      targetBusinessId,
      targetBusinessName: targetBusiness?.name ?? targetBusinessId,
      status:
        typeof result.status == 'string'
            ? result.status
            : request.status ?? 'pending',
      approvalsReceived:
        typeof result.approvalsReceived == 'number'
            ? result.approvalsReceived
            : readIntValue(request, 'approvalsReceived') ?? 0,
      approvalsRequired:
        typeof result.approvalsRequired == 'number'
            ? result.approvalsRequired
            : readIntValue(request, 'approvalsRequired') ?? 0,
    });
  });

  return result;
}
