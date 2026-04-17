import { HttpsError } from 'firebase-functions/v2/https';
import { FieldValue, type Timestamp } from 'firebase-admin/firestore';

import {
  assertOperatorCanAccessBusiness,
  auth,
  buildOperatorAliasEmail,
  db,
  normalizeUsername,
  requireOperatorRole,
  serverTimestamp,
} from './core.js';
import {
  DEFAULT_CASHBACK_EXPIRY_DAYS,
  loadBusinessContext,
  normalizeError,
  uniqueStrings,
} from './operations_support.js';
import {
  notifyStaffAssignment,
  safelyRunNotificationTask,
} from './notifications.js';
import type {
  CreateBusinessInput,
  ResetStaffPasswordInput,
  StaffAccountInput,
  UpdateStaffProfileInput,
} from './types.js';

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

  await auth.updateUser(staffUid, { disabled: true });

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

    if (staff.usernameNormalized != null && staff.usernameNormalized.length > 0) {
      transaction.set(
        db.doc(`operatorUsernames/${staff.usernameNormalized}`),
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

      if (staff.usernameNormalized != null && staff.usernameNormalized.length > 0) {
        transaction.set(
          db.doc(`operatorUsernames/${staff.usernameNormalized}`),
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

      if (staff.usernameNormalized != null && staff.usernameNormalized.length > 0) {
        transaction.set(
          db.doc(`operatorUsernames/${staff.usernameNormalized}`),
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
