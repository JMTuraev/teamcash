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

const DEFAULT_CASHBACK_EXPIRY_DAYS = 180;
const REFUND_GRACE_DAYS = 30;
const DEFAULT_EXPIRY_SWEEP_LIMIT = 100;
const MAX_EXPIRY_SWEEP_LIMIT = 200;

interface CustomerIdentityResult {
  customerId: string;
  customerRef: DocumentReference;
  indexRef: DocumentReference;
  created: boolean;
  customerExists: boolean;
  customerData?: CustomerRecord;
  indexExists: boolean;
}

interface BusinessContext {
  businessId: string;
  data: BusinessRecord;
}

interface ExpireLotResult {
  lotId: string;
  eventId: string;
  customerId: string;
  amountMinorUnits: number;
  issuerBusinessId: string;
  groupId: string;
}

export async function createStaffAccountFlow(
  ownerUid: string,
  input: StaffAccountInput,
) {
  const owner = await requireOperatorRole(ownerUid, ['owner']);
  assertOperatorCanAccessBusiness(owner, input.businessId);

  const normalizedUsername = normalizeUsername(input.username);
  const usernameRef = db.doc(`operatorUsernames/${normalizedUsername}`);
  const existingUsername = await usernameRef.get();
  if (existingUsername.exists) {
    throw new HttpsError(
      'already-exists',
      'This username is already assigned to another operator.',
    );
  }

  const business = await loadBusinessContext(input.businessId);
  const aliasEmail = buildOperatorAliasEmail(normalizedUsername);

  let createdAuthUid: string | null = null;
  try {
    const userRecord = await auth.createUser({
      email: aliasEmail,
      password: input.password,
      displayName: input.displayName,
      disabled: false,
    });
    createdAuthUid = userRecord.uid;

    await db.runTransaction(async (transaction) => {
      const usernameSnap = await transaction.get(usernameRef);
      if (usernameSnap.exists) {
        throw new HttpsError(
          'already-exists',
          'This username is already assigned to another operator.',
        );
      }

      const operatorRef = db.doc(`operatorAccounts/${userRecord.uid}`);
      transaction.set(operatorRef, {
        role: 'staff',
        ownerId: owner.uid,
        businessId: input.businessId,
        businessIds: [input.businessId],
        usernameNormalized: normalizedUsername,
        displayName: input.displayName,
        disabledAt: null,
        createdAt: serverTimestamp(),
        updatedAt: serverTimestamp(),
      });
      transaction.set(usernameRef, {
        uid: userRecord.uid,
        loginAliasEmail: aliasEmail,
        status: 'active',
        role: 'staff',
        ownerId: owner.uid,
        businessId: input.businessId,
        createdAt: serverTimestamp(),
        updatedAt: serverTimestamp(),
      });
    });

    const result = {
      staffUid: userRecord.uid,
      username: normalizedUsername,
      businessId: input.businessId,
      businessName: business.data.name ?? input.businessId,
      loginAliasEmail: aliasEmail,
    };

    await safelyRunNotificationTask('staff assignment notification', async () => {
      await notifyStaffAssignment({
        staffUid: userRecord.uid,
        businessId: input.businessId,
        businessName: business.data.name ?? input.businessId,
      });
    });

    return result;
  } catch (error) {
    if (createdAuthUid != null) {
      await auth.deleteUser(createdAuthUid).catch(() => null);
    }
    throw normalizeError(error);
  }
}

export async function disableStaffAccountFlow(
  ownerUid: string,
  staffUid: string,
  reason?: string,
) {
  const owner = await requireOperatorRole(ownerUid, ['owner']);
  const staffRef = db.doc(`operatorAccounts/${staffUid}`);
  const staffSnap = await staffRef.get();
  if (!staffSnap.exists) {
    throw new HttpsError('not-found', 'Staff account was not found.');
  }

  const staff = staffSnap.data() as {
    role?: string;
    ownerId?: string | null;
    businessId?: string | null;
    usernameNormalized?: string | null;
    disabledAt?: Timestamp | null;
  };

  if (staff.role != 'staff') {
    throw new HttpsError(
      'failed-precondition',
      'Only staff accounts can be disabled here.',
    );
  }

  if (staff.businessId == null) {
    throw new HttpsError(
      'failed-precondition',
      'Staff account is missing the assigned business.',
    );
  }

  assertOperatorCanAccessBusiness(owner, staff.businessId);
  const trimmedReason = reason?.trim();

  await auth.updateUser(staffUid, {
    disabled: true,
  });

  await db.runTransaction(async (transaction) => {
    transaction.set(
      staffRef,
      {
        disabledAt: serverTimestamp(),
        disabledBy: ownerUid,
        disableReason:
          trimmedReason != null && trimmedReason.length > 0 ? trimmedReason : null,
        updatedAt: serverTimestamp(),
      },
      { merge: true },
    );

    if (
      staff.usernameNormalized != null &&
      staff.usernameNormalized.length > 0
    ) {
      const usernameRef = db.doc(`operatorUsernames/${staff.usernameNormalized}`);
      transaction.set(
        usernameRef,
        {
          status: 'disabled',
          updatedAt: serverTimestamp(),
        },
        { merge: true },
      );
    }
  });

  return {
    staffUid,
    businessId: staff.businessId,
    disabled: true,
  };
}

export async function resetStaffPasswordFlow(
  ownerUid: string,
  input: ResetStaffPasswordInput,
) {
  const owner = await requireOperatorRole(ownerUid, ['owner']);
  const staffRef = db.doc(`operatorAccounts/${input.staffUid}`);
  const staffSnap = await staffRef.get();
  if (!staffSnap.exists) {
    throw new HttpsError('not-found', 'Staff account was not found.');
  }

  const staff = staffSnap.data() as {
    role?: string;
    businessId?: string | null;
    usernameNormalized?: string | null;
    displayName?: string | null;
    disabledAt?: Timestamp | null;
  };

  if (staff.role != 'staff') {
    throw new HttpsError(
      'failed-precondition',
      'Only staff accounts can be updated here.',
    );
  }

  if (staff.businessId == null || staff.businessId.length === 0) {
    throw new HttpsError(
      'failed-precondition',
      'Staff account is missing the assigned business.',
    );
  }

  if (staff.disabledAt != null) {
    throw new HttpsError(
      'failed-precondition',
      'Disabled staff accounts cannot receive a new password.',
    );
  }

  assertOperatorCanAccessBusiness(owner, staff.businessId);

  try {
    await auth.updateUser(input.staffUid, {
      password: input.password,
    });

    await db.runTransaction(async (transaction) => {
      transaction.set(
        staffRef,
        {
          passwordResetAt: serverTimestamp(),
          passwordResetBy: ownerUid,
          updatedAt: serverTimestamp(),
        },
        { merge: true },
      );

      if (
        staff.usernameNormalized != null &&
        staff.usernameNormalized.length > 0
      ) {
        const usernameRef = db.doc(
          `operatorUsernames/${staff.usernameNormalized}`,
        );
        transaction.set(
          usernameRef,
          {
            passwordResetAt: serverTimestamp(),
            updatedAt: serverTimestamp(),
          },
          { merge: true },
        );
      }
    });

    return {
      staffUid: input.staffUid,
      businessId: staff.businessId,
      username: staff.usernameNormalized ?? '',
      displayName: staff.displayName ?? '',
    };
  } catch (error) {
    throw normalizeError(error);
  }
}

export async function updateStaffProfileFlow(
  ownerUid: string,
  input: UpdateStaffProfileInput,
) {
  const owner = await requireOperatorRole(ownerUid, ['owner']);
  const staffRef = db.doc(`operatorAccounts/${input.staffUid}`);
  const staffSnap = await staffRef.get();
  if (!staffSnap.exists) {
    throw new HttpsError('not-found', 'Staff account was not found.');
  }

  const staff = staffSnap.data() as {
    role?: string;
    businessId?: string | null;
    usernameNormalized?: string | null;
    displayName?: string | null;
  };

  if (staff.role != 'staff') {
    throw new HttpsError(
      'failed-precondition',
      'Only staff accounts can be updated here.',
    );
  }

  if (staff.businessId == null || staff.businessId.length === 0) {
    throw new HttpsError(
      'failed-precondition',
      'Staff account is missing the assigned business.',
    );
  }

  assertOperatorCanAccessBusiness(owner, staff.businessId);

  const trimmedDisplayName = input.displayName.trim();

  try {
    await auth.updateUser(input.staffUid, {
      displayName: trimmedDisplayName,
    });

    await db.runTransaction(async (transaction) => {
      transaction.set(
        staffRef,
        {
          displayName: trimmedDisplayName,
          updatedAt: serverTimestamp(),
        },
        { merge: true },
      );

      if (
        staff.usernameNormalized != null &&
        staff.usernameNormalized.length > 0
      ) {
        const usernameRef = db.doc(
          `operatorUsernames/${staff.usernameNormalized}`,
        );
        transaction.set(
          usernameRef,
          {
            displayName: trimmedDisplayName,
            updatedAt: serverTimestamp(),
          },
          { merge: true },
        );
      }
    });

    return {
      staffUid: input.staffUid,
      businessId: staff.businessId,
      username: staff.usernameNormalized ?? '',
      displayName: trimmedDisplayName,
    };
  } catch (error) {
    throw normalizeError(error);
  }
}

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

export async function createBusinessFlow(
  ownerUid: string,
  input: CreateBusinessInput,
) {
  const owner = await requireOperatorRole(ownerUid, ['owner']);
  const businessRef = db.collection('businesses').doc();
  const usernameNormalized = owner.data.usernameNormalized;
  const usernameRef =
    typeof usernameNormalized == 'string' && usernameNormalized.length > 0
        ? db.doc(`operatorUsernames/${usernameNormalized}`)
        : null;
  const normalizedPhoneNumbers = uniqueStrings(
    input.phoneNumbers.map((phone) => phone.trim()).filter((phone) => phone.length > 0),
  );

  if (normalizedPhoneNumbers.length == 0) {
    throw new HttpsError(
      'invalid-argument',
      'At least one phone number is required for a business profile.',
    );
  }

  return db.runTransaction(async (transaction) => {
    transaction.set(businessRef, {
      id: businessRef.id,
      ownerUid,
      name: input.name.trim(),
      category: input.category.trim(),
      description: input.description.trim(),
      address: input.address.trim(),
      workingHours: input.workingHours.trim(),
      phoneNumbers: normalizedPhoneNumbers,
      cashbackBasisPoints: input.cashbackBasisPoints,
      cashbackExpiryDays: DEFAULT_CASHBACK_EXPIRY_DAYS,
      redeemPolicy: input.redeemPolicy.trim(),
      groupId: null,
      groupName: null,
      groupMembershipStatus: 'none',
      tandemStatus: 'none',
      locationsCount: 0,
      productsCount: 0,
      manualPhoneIssuingEnabled: true,
      createdAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
    });
    transaction.set(
      db.doc(`operatorAccounts/${ownerUid}`),
      {
        businessIds: FieldValue.arrayUnion(businessRef.id),
        updatedAt: serverTimestamp(),
      },
      { merge: true },
    );

    if (usernameRef != null) {
      transaction.set(
        usernameRef,
        {
          businessIds: FieldValue.arrayUnion(businessRef.id),
          updatedAt: serverTimestamp(),
        },
        { merge: true },
      );
    }

    return {
      businessId: businessRef.id,
      name: input.name.trim(),
      status: 'created',
      groupMembershipStatus: 'none',
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

function resolveRefundExpiryTimestamp(
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

function normalizeExpirySweepLimit(value: number | undefined): number {
  if (value == null || !Number.isInteger(value) || value <= 0) {
    return DEFAULT_EXPIRY_SWEEP_LIMIT;
  }

  return Math.min(value, MAX_EXPIRY_SWEEP_LIMIT);
}

async function expireActiveWalletLotDocument({
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

async function resolveCustomerIdentityForAdminAdjustment(
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

async function resolveCustomerIdForRedeem(
  input: RedeemCashbackInput,
): Promise<string> {
  if (
    input.customerId != null &&
    input.customerId.trim().length > 0
  ) {
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

async function resolveJoinRequestReference(requestId: string) {
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

export async function loadBusinessContext(businessId: string): Promise<BusinessContext> {
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

async function getOrCreateCustomerIdentity(
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

function incrementBusinessStats(
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

async function markBusinessCustomerTouch(
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

  transaction.set(
    dailyTouchRef,
    dailyTouchPayload,
    { merge: true },
  );
  transaction.set(
    customerSummaryRef,
    customerSummaryPayload,
    { merge: true },
  );
}

async function safelyRunNotificationTask(
  description: string,
  task: () => Promise<void>,
) {
  try {
    await task();
  } catch (error) {
    console.error(`[notifications] ${description} failed`, error);
  }
}

async function notifyStaffAssignment({
  staffUid,
  businessId,
  businessName,
}: {
  staffUid: string;
  businessId: string;
  businessName: string;
}) {
  await persistNotification({
    notificationId: `staff-assigned-${staffUid}-${businessId}`,
    recipientUid: staffUid,
    roleSurface: 'staff',
    kind: 'staff_assignment',
    title: `Assigned to ${businessName}`,
    body: `Your staff access is now limited to ${businessName}. Use the dashboard and scan surface for this business only.`,
    businessId,
    entityId: businessId,
    actionRoute: '/staff',
    actionLabel: 'Open staff workspace',
  });
}

async function notifyOwnersOfGroupJoinRequest({
  requestId,
  groupId,
  groupName,
  targetBusinessId,
  targetBusinessName,
  activeBusinessIds,
}: {
  requestId: string;
  groupId: string;
  groupName: string;
  targetBusinessId: string;
  targetBusinessName: string;
  activeBusinessIds: string[];
}) {
  const ownerUids = await loadOwnerUidsForBusinessIds(activeBusinessIds);
  await Promise.all(
    ownerUids.map((ownerUid) =>
      persistNotification({
        notificationId: `owner-join-request-${requestId}-${ownerUid}`,
        recipientUid: ownerUid,
        roleSurface: 'owner',
        kind: 'group_join_requested',
        title: `${targetBusinessName} requested to join ${groupName}`,
        body:
          'All active member businesses must approve before this business can join the tandem.',
        businessId: targetBusinessId,
        groupId,
        entityId: requestId,
        actionRoute: '/owner',
        actionLabel: 'Open approvals',
      }),
    ),
  );
}

async function notifyTargetOwnersOfGroupJoinVote({
  requestId,
  groupId,
  groupName,
  targetBusinessId,
  targetBusinessName,
  status,
  approvalsReceived,
  approvalsRequired,
}: {
  requestId: string;
  groupId: string;
  groupName: string;
  targetBusinessId: string;
  targetBusinessName: string;
  status: string;
  approvalsReceived: number;
  approvalsRequired: number;
}) {
  const ownerUids = await loadOwnerUidsForBusinessIds([targetBusinessId]);
  let title = `${targetBusinessName} join request is still pending`;
  let body = `${approvalsReceived}/${approvalsRequired} approvals are now recorded in ${groupName}.`;

  if (status == 'approved') {
    title = `${targetBusinessName} was approved for ${groupName}`;
    body =
      'All required member approvals were received. The business is now active inside the tandem group.';
  } else if (status == 'rejected') {
    title = `${targetBusinessName} was rejected by ${groupName}`;
    body =
      'One of the current member businesses voted no, so the join request has been closed.';
  }

  await Promise.all(
    ownerUids.map((ownerUid) =>
      persistNotification({
        notificationId: `owner-join-status-${requestId}-${ownerUid}`,
        recipientUid: ownerUid,
        roleSurface: 'owner',
        kind: `group_join_${status}`,
        title,
        body,
        businessId: targetBusinessId,
        groupId,
        entityId: requestId,
        actionRoute: '/owner',
        actionLabel: 'Open group status',
      }),
    ),
  );
}

async function notifyRecipientOfPendingGift({
  transferId,
  recipientPhoneE164,
  groupId,
  amountMinorUnits,
}: {
  transferId: string;
  recipientPhoneE164: string;
  groupId: string;
  amountMinorUnits: number;
}) {
  const phoneIndexSnap = await db
    .doc(`customerPhoneIndex/${recipientPhoneE164}`)
    .get();
  if (!phoneIndexSnap.exists) {
    return;
  }

  const recipientCustomerId = phoneIndexSnap.data()?.customerId;
  if (
    typeof recipientCustomerId != 'string' ||
    recipientCustomerId.trim().length == 0
  ) {
    return;
  }

  const recipientUid = await loadClaimedCustomerUid(recipientCustomerId);
  if (recipientUid == null) {
    return;
  }

  await persistNotification({
    notificationId: `client-gift-pending-${transferId}-${recipientUid}`,
    recipientUid,
    roleSurface: 'client',
    kind: 'gift_pending',
    title: 'Cashback gift is waiting for you',
    body: `A same-group gift worth ${formatNotificationAmount(amountMinorUnits)} is ready to claim in your wallet.`,
    customerId: recipientCustomerId,
    groupId,
    entityId: transferId,
    actionRoute: '/client',
    actionLabel: 'Open wallet',
  });
}

async function notifySenderOfGiftClaim({
  transferId,
  claimedMinorUnits,
  expiredMinorUnits,
}: {
  transferId: string;
  claimedMinorUnits: number;
  expiredMinorUnits: number;
}) {
  const transferSnap = await db.doc(`giftTransfers/${transferId}`).get();
  if (!transferSnap.exists) {
    return;
  }

  const transfer = transferSnap.data() as {
    sourceCustomerId?: string | null;
    recipientCustomerId?: string | null;
    groupId?: string | null;
  };
  if (
    typeof transfer.sourceCustomerId != 'string' ||
    transfer.sourceCustomerId.trim().length == 0
  ) {
    return;
  }

  const senderUid = await loadClaimedCustomerUid(transfer.sourceCustomerId);
  if (senderUid == null) {
    return;
  }

  const title =
    claimedMinorUnits > 0
      ? 'Your cashback gift was claimed'
      : 'Your cashback gift expired';
  const body =
    claimedMinorUnits > 0
      ? `The recipient claimed ${formatNotificationAmount(claimedMinorUnits)}.${expiredMinorUnits > 0 ? ` ${formatNotificationAmount(expiredMinorUnits)} expired before claim.` : ''}`
      : `The reserved gift expired before it could be claimed.`;

  await persistNotification({
    notificationId: `client-gift-claimed-${transferId}-${senderUid}`,
    recipientUid: senderUid,
    roleSurface: 'client',
    kind: claimedMinorUnits > 0 ? 'gift_claimed' : 'gift_expired',
    title,
    body,
    customerId: transfer.sourceCustomerId,
    groupId:
      typeof transfer.groupId == 'string' && transfer.groupId.trim().length > 0
        ? transfer.groupId.trim()
        : null,
    entityId: transferId,
    actionRoute: '/client',
    actionLabel: 'Open history',
  });
}

async function notifyClaimedCustomerCashbackIssued({
  customerId,
  businessId,
  businessName,
  groupId,
  amountMinorUnits,
  eventId,
}: {
  customerId: string;
  businessId: string;
  businessName: string;
  groupId: string;
  amountMinorUnits: number;
  eventId: string;
}) {
  await notifyClaimedCustomer({
    notificationId: `client-issue-${eventId}-${customerId}`,
    customerId,
    roleSurface: 'client',
    kind: 'cashback_issued',
    title: `Cashback added from ${businessName}`,
    body: `${formatNotificationAmount(amountMinorUnits)} was issued to your wallet and stays bound to this tandem group.`,
    businessId,
    groupId,
    entityId: eventId,
    actionRoute: '/client',
    actionLabel: 'Open wallet',
  });
}

async function notifyClaimedCustomerCashbackRedeemed({
  customerId,
  businessId,
  businessName,
  groupId,
  amountMinorUnits,
  redemptionBatchId,
}: {
  customerId: string;
  businessId: string;
  businessName: string;
  groupId: string;
  amountMinorUnits: number;
  redemptionBatchId: string;
}) {
  await notifyClaimedCustomer({
    notificationId: `client-redeem-${redemptionBatchId}-${customerId}`,
    customerId,
    roleSurface: 'client',
    kind: 'cashback_redeemed',
    title: `Cashback redeemed at ${businessName}`,
    body: `${formatNotificationAmount(amountMinorUnits)} was used at checkout from your tandem wallet.`,
    businessId,
    groupId,
    entityId: redemptionBatchId,
    actionRoute: '/client',
    actionLabel: 'Open history',
  });
}

async function notifyRefundBatchCustomers({
  refundBatchId,
  businessId,
  businessName,
}: {
  refundBatchId: string;
  businessId: string;
  businessName: string;
}) {
  const refundSnapshots = await db
    .collection('ledgerEvents')
    .where('refundBatchId', '==', refundBatchId)
    .get();

  const summaries = new Map<
    string,
    { amountMinorUnits: number; groupId: string | null }
  >();

  for (const doc of refundSnapshots.docs) {
    const event = doc.data() as {
      eventType?: string | null;
      sourceCustomerId?: string | null;
      amountMinorUnits?: number;
      groupId?: string | null;
    };
    if (
      event.eventType != 'refund' ||
      typeof event.sourceCustomerId != 'string' ||
      typeof event.amountMinorUnits != 'number'
    ) {
      continue;
    }

    const summary = summaries.get(event.sourceCustomerId) ?? {
      amountMinorUnits: 0,
      groupId:
        typeof event.groupId == 'string' && event.groupId.trim().length > 0
          ? event.groupId.trim()
          : null,
    };
    summary.amountMinorUnits += event.amountMinorUnits;
    summaries.set(event.sourceCustomerId, summary);
  }

  await Promise.all(
    [...summaries.entries()].map(([customerId, summary]) =>
      notifyClaimedCustomer({
        notificationId: `client-refund-${refundBatchId}-${customerId}`,
        customerId,
        roleSurface: 'client',
        kind: 'cashback_refunded',
        title: `Cashback refunded by ${businessName}`,
        body: `${formatNotificationAmount(summary.amountMinorUnits)} was returned to your wallet after a checkout refund.`,
        businessId,
        groupId: summary.groupId,
        entityId: refundBatchId,
        actionRoute: '/client',
        actionLabel: 'Open wallet',
      }),
    ),
  );
}

async function notifyClaimedCustomerAdminAdjustment({
  customerId,
  businessId,
  businessName,
  groupId,
  amountMinorUnits,
  direction,
  adjustmentBatchId,
  note,
}: {
  customerId: string;
  businessId: string;
  businessName: string;
  groupId: string;
  amountMinorUnits: number;
  direction: string;
  adjustmentBatchId: string;
  note: string;
}) {
  const title =
    direction == 'credit'
      ? `Wallet credited by ${businessName}`
      : `Wallet adjusted by ${businessName}`;
  const body =
    direction == 'credit'
      ? `${formatNotificationAmount(amountMinorUnits)} was added to your wallet by the business owner.${note.length > 0 ? ` Note: ${note}` : ''}`
      : `${formatNotificationAmount(amountMinorUnits)} was removed from your wallet by the business owner.${note.length > 0 ? ` Note: ${note}` : ''}`;

  await notifyClaimedCustomer({
    notificationId: `client-admin-adjustment-${adjustmentBatchId}-${customerId}`,
    customerId,
    roleSurface: 'client',
    kind: `admin_adjustment_${direction}`,
    title,
    body,
    businessId,
    groupId,
    entityId: adjustmentBatchId,
    actionRoute: '/client',
    actionLabel: 'Open history',
  });
}

async function notifyCustomersOfExpiredLots({
  expiredLots,
  trigger,
}: {
  expiredLots: ExpireLotResult[];
  trigger: 'manual_sweep' | 'scheduled_sweep';
}) {
  const summaries = new Map<
    string,
    {
      customerId: string;
      groupId: string;
      amountMinorUnits: number;
      eventIds: string[];
    }
  >();

  for (const lot of expiredLots) {
    const summaryKey = `${lot.customerId}::${lot.groupId}`;
    const summary = summaries.get(summaryKey) ?? {
      customerId: lot.customerId,
      groupId: lot.groupId,
      amountMinorUnits: 0,
      eventIds: [],
    };
    summary.amountMinorUnits += lot.amountMinorUnits;
    summary.eventIds.push(lot.eventId);
    summaries.set(summaryKey, summary);
  }

  await Promise.all(
    [...summaries.values()].map((summary) =>
      notifyClaimedCustomer({
        notificationId: `client-expire-${summary.eventIds[0]}-${summary.customerId}`,
        customerId: summary.customerId,
        roleSurface: 'client',
        kind: 'cashback_expired',
        title: 'Cashback expired from your wallet',
        body: `${formatNotificationAmount(summary.amountMinorUnits)} expired before it was used.${trigger == 'manual_sweep' ? ' The business ran an expiry sweep.' : ''}`,
        groupId: summary.groupId,
        entityId: summary.eventIds[0],
        actionRoute: '/client',
        actionLabel: 'Open history',
      }),
    ),
  );
}

async function notifyClaimedCustomerSharedCheckoutContributionReserved({
  customerId,
  businessId,
  businessName,
  groupId,
  amountMinorUnits,
  checkoutId,
  contributionId,
}: {
  customerId: string;
  businessId: string;
  businessName: string;
  groupId: string | null;
  amountMinorUnits: number;
  checkoutId: string;
  contributionId: string;
}) {
  await notifyClaimedCustomer({
    notificationId: `client-shared-reserved-${contributionId}-${customerId}`,
    customerId,
    roleSurface: 'client',
    kind: 'shared_checkout_contribution',
    title: `Contribution reserved for ${businessName}`,
    body: `${formatNotificationAmount(amountMinorUnits)} is reserved for a shared checkout and will be finalized by the business.`,
    businessId,
    groupId,
    entityId: checkoutId,
    actionRoute: '/client',
    actionLabel: 'Open wallet',
  });
}

async function notifyCustomersOfFinalizedSharedCheckout({
  checkoutId,
  businessId,
  businessName,
  groupId,
}: {
  checkoutId: string;
  businessId: string;
  businessName: string;
  groupId: string | null;
}) {
  const contributionsSnap = await db
    .collection(`sharedCheckouts/${checkoutId}/contributions`)
    .get();
  const summaries = new Map<
    string,
    { redeemedMinorUnits: number; expiredMinorUnits: number }
  >();

  for (const doc of contributionsSnap.docs) {
    const contribution = doc.data() as {
      customerId?: string | null;
      redeemedMinorUnits?: number;
      expiredMinorUnits?: number;
    };
    if (typeof contribution.customerId != 'string') {
      continue;
    }

    const summary = summaries.get(contribution.customerId) ?? {
      redeemedMinorUnits: 0,
      expiredMinorUnits: 0,
    };
    summary.redeemedMinorUnits += contribution.redeemedMinorUnits ?? 0;
    summary.expiredMinorUnits += contribution.expiredMinorUnits ?? 0;
    summaries.set(contribution.customerId, summary);
  }

  await Promise.all(
    [...summaries.entries()].map(([customerId, summary]) => {
      if (
        summary.redeemedMinorUnits <= 0 &&
        summary.expiredMinorUnits <= 0
      ) {
        return Promise.resolve();
      }

      const parts = [
        summary.redeemedMinorUnits > 0
          ? `${formatNotificationAmount(summary.redeemedMinorUnits)} was consumed`
          : null,
        summary.expiredMinorUnits > 0
          ? `${formatNotificationAmount(summary.expiredMinorUnits)} expired before finalization`
          : null,
      ].filter((value): value is string => value != null);

      return notifyClaimedCustomer({
        notificationId: `client-shared-finalized-${checkoutId}-${customerId}`,
        customerId,
        roleSurface: 'client',
        kind: 'shared_checkout_finalized',
        title: `Shared checkout finalized at ${businessName}`,
        body: `${parts.join('. ')}.`,
        businessId,
        groupId,
        entityId: checkoutId,
        actionRoute: '/client',
        actionLabel: 'Open history',
      });
    }),
  );
}

async function notifyClaimedCustomer({
  notificationId,
  customerId,
  roleSurface,
  kind,
  title,
  body,
  businessId,
  groupId,
  entityId,
  actionRoute,
  actionLabel,
}: {
  notificationId: string;
  customerId: string;
  roleSurface: 'client';
  kind: string;
  title: string;
  body: string;
  businessId?: string | null;
  groupId?: string | null;
  entityId?: string | null;
  actionRoute?: string | null;
  actionLabel?: string | null;
}) {
  const recipientUid = await loadClaimedCustomerUid(customerId);
  if (recipientUid == null) {
    return;
  }

  await persistNotification({
    notificationId,
    recipientUid,
    roleSurface,
    kind,
    title,
    body,
    businessId,
    customerId,
    groupId,
    entityId,
    actionRoute,
    actionLabel,
  });
}

async function loadOwnerUidsForBusinessIds(
  businessIds: string[],
): Promise<string[]> {
  const ownerUids = new Set<string>();

  await Promise.all(
    uniqueStrings(businessIds)
      .filter((businessId) => businessId.trim().length > 0)
      .map(async (businessId) => {
        const snapshot = await db
          .collection('operatorAccounts')
          .where('businessIds', 'array-contains', businessId)
          .get();

        for (const doc of snapshot.docs) {
          const data = doc.data() as {
            role?: string | null;
            disabledAt?: Timestamp | null;
          };
          if (data.role == 'owner' && data.disabledAt == null) {
            ownerUids.add(doc.id);
          }
        }
      }),
  );

  return [...ownerUids];
}

async function loadClaimedCustomerUid(
  customerId: string,
): Promise<string | null> {
  const customerSnap = await db.doc(`customers/${customerId}`).get();
  if (!customerSnap.exists) {
    return null;
  }

  const claimedByUid = customerSnap.data()?.claimedByUid;
  return typeof claimedByUid == 'string' && claimedByUid.trim().length > 0
    ? claimedByUid.trim()
    : null;
}

async function persistNotification({
  notificationId,
  recipientUid,
  roleSurface,
  kind,
  title,
  body,
  businessId,
  customerId,
  groupId,
  entityId,
  actionRoute,
  actionLabel,
}: {
  notificationId: string;
  recipientUid: string;
  roleSurface: 'owner' | 'staff' | 'client';
  kind: string;
  title: string;
  body: string;
  businessId?: string | null;
  customerId?: string | null;
  groupId?: string | null;
  entityId?: string | null;
  actionRoute?: string | null;
  actionLabel?: string | null;
}) {
  if (recipientUid.trim().length == 0) {
    return;
  }

  await db.doc(`notifications/${notificationId}`).set(
    {
      recipientUid,
      roleSurface,
      kind,
      title,
      body,
      businessId: businessId ?? null,
      customerId: customerId ?? null,
      groupId: groupId ?? null,
      entityId: entityId ?? null,
      actionRoute: actionRoute ?? null,
      actionLabel: actionLabel ?? null,
      isRead: false,
      readAt: null,
      createdAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
    },
    { merge: true },
  );
}

function formatNotificationAmount(amountMinorUnits: number): string {
  return `UZS ${amountMinorUnits.toLocaleString('en-US')}`;
}

function readCashbackBasisPoints(
  business: BusinessRecord,
  requestedBasisPoints: number,
): number {
  return typeof business.cashbackBasisPoints == 'number'
      ? business.cashbackBasisPoints
      : requestedBasisPoints;
}

function readCashbackExpiryDays(business: BusinessRecord): number {
  return typeof business.cashbackExpiryDays == 'number' &&
          business.cashbackExpiryDays > 0
      ? business.cashbackExpiryDays
      : DEFAULT_CASHBACK_EXPIRY_DAYS;
}

function uniqueStrings(values: string[]): string[] {
  return [...new Set(values)];
}

function resolveVoterBusinessId({
  ownerBusinessIds,
  activeBusinessIds,
  requestedBusinessId,
}: {
  ownerBusinessIds: string[];
  activeBusinessIds: string[];
  requestedBusinessId?: string;
}): string {
  const eligibleBusinessIds = ownerBusinessIds.filter(
    (businessId) => activeBusinessIds.includes(businessId),
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

function readStringList(
  data: Record<string, unknown> | undefined,
  key: string,
): string[] {
  const value = data?.[key];
  if (!Array.isArray(value)) {
    return [];
  }

  return value.filter((item): item is string => typeof item == 'string');
}

function readIntValue(
  data: Record<string, unknown> | undefined,
  key: string,
): number | null {
  const value = data?.[key];
  if (typeof value == 'number') {
    return Math.trunc(value);
  }
  return null;
}

function toIsoStringOrNull(value: Timestamp | null): string | null {
  return value?.toDate().toISOString() ?? null;
}

function normalizeError(error: unknown): never {
  if (error instanceof HttpsError) {
    throw error;
  }

  if (error instanceof Error) {
    throw new HttpsError('internal', error.message);
  }

  throw new HttpsError('internal', 'Unexpected backend failure.');
}
